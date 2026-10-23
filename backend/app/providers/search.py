"""Geoapify autocomplete with bounded RAM cache and persistent attempt guards.

Only budget counts/timestamps are persisted; never queries, GPS, or credentials.
No automatic retries or provider fallback (including on 429).
"""
import asyncio
from collections import OrderedDict
from datetime import datetime, timezone
import hashlib
import math
import sqlite3
import time
import unicodedata

import httpx
from fastapi import HTTPException

from app.metrics import metrics


class SearchBudget:
    def __init__(self, filename, limit, credit_limit=2000):
        self.filename, self.limit, self.credit_limit = filename, limit, credit_limit
        with sqlite3.connect(filename) as db:
            db.execute('CREATE TABLE IF NOT EXISTS days (day TEXT PRIMARY KEY, used INTEGER NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS attempts (at REAL NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS credit_days (day TEXT PRIMARY KEY, quarters INTEGER NOT NULL)')
            db.execute('INSERT OR IGNORE INTO credit_days SELECT day,used*4 FROM days')
            db.execute('CREATE TABLE IF NOT EXISTS credit_attempts (at REAL NOT NULL, quarters INTEGER NOT NULL, kind TEXT NOT NULL)')

    def reserve(self, kind='search'):
        if kind not in ('search','tile'):
            raise ValueError('Invalid credit category')
        cost = 4 if kind == 'search' else 1
        now = time.time()
        day = datetime.now(timezone.utc).date().isoformat()
        try:
            with sqlite3.connect(self.filename, timeout=2) as db:
                db.execute('BEGIN IMMEDIATE')
                used = db.execute('SELECT used FROM days WHERE day=?', (day,)).fetchone()
                credits = db.execute('SELECT quarters FROM credit_days WHERE day=?', (day,)).fetchone()
                if (credits[0] if credits else 0)+cost > self.credit_limit*4:
                    raise HTTPException(429, 'Đã đạt ngân sách credits Geoapify trong ngày UTC',
                        headers={'Retry-After':'3600', 'X-RateLimit-Bucket':'geoapify_credits'})
                if kind == 'search' and used and used[0] >= self.limit:
                    raise HTTPException(429, 'Đã đạt ngân sách tìm kiếm Geoapify trong ngày UTC',
                        headers={'Retry-After':'3600', 'X-RateLimit-Bucket':'geoapify_daily'})
                db.execute('DELETE FROM attempts WHERE at < ?', (now-60,))
                db.execute('DELETE FROM credit_attempts WHERE at < ?', (now-60,))
                minute, second = db.execute('SELECT COUNT(*), COALESCE(SUM(at > ?),0) FROM attempts', (now-1,)).fetchone()
                credit_minute, credit_second = db.execute('SELECT COALESCE(SUM(quarters),0), COALESCE(SUM(CASE WHEN at > ? THEN quarters ELSE 0 END),0) FROM credit_attempts', (now-1,)).fetchone()
                if (kind == 'search' and (minute >= 40 or second >= 2)) or credit_second+cost>16 or credit_minute+cost>800:
                    raise HTTPException(429, 'Tìm kiếm quá nhanh. Vui lòng chờ rồi thử lại.',
                        headers={'Retry-After':'2' if second >= 2 or credit_second+cost>16 else '60', 'X-RateLimit-Bucket':'geoapify_local'})
                if kind == 'search':
                    db.execute('INSERT INTO days VALUES (?,1) ON CONFLICT(day) DO UPDATE SET used=used+1', (day,))
                    db.execute('INSERT INTO attempts VALUES (?)', (now,))
                db.execute('INSERT INTO credit_days VALUES (?,?) ON CONFLICT(day) DO UPDATE SET quarters=quarters+excluded.quarters', (day,cost))
                db.execute('INSERT INTO credit_attempts VALUES (?,?,?)',(now,cost,kind))
                db.execute('DELETE FROM credit_days WHERE day < ?', (day,))
                db.execute('DELETE FROM days WHERE day < ?', (day,))
        except sqlite3.Error:
            # Never bypass the spending guard if its store is unavailable.
            raise HTTPException(503, 'Không đọc được bộ đếm quota tìm kiếm') from None

    def snapshot(self):
        with sqlite3.connect(self.filename) as db:
            used = db.execute('SELECT used FROM days WHERE day=?', (datetime.now(timezone.utc).date().isoformat(),)).fetchone()
            credits = db.execute('SELECT quarters FROM credit_days WHERE day=?', (datetime.now(timezone.utc).date().isoformat(),)).fetchone()
        return {'used': used[0] if used else 0, 'limit':self.limit, 'day_boundary':'UTC',
                'credits_used':(credits[0] if credits else 0)/4,'credits_limit':self.credit_limit}


class GeoapifySearchProvider:
    def __init__(self, client, key, budget):
        self.client, self.key, self.budget = client, key, budget
        self.cache = OrderedDict()
        self.pending = {}
        self.blocked_until = 0
        self.cache_hits = self.coalesced = 0

    async def search(self, query, lat, lon):
        query = ' '.join(unicodedata.normalize('NFC', query).split())
        if len(query) < 3:
            return []
        if not self.key:
            raise HTTPException(503, 'Chưa cấu hình Geoapify key')
        # Coarse proximity bias improves repeatability and does not retain GPS history.
        lat, lon = round(lat,2), round(lon,2)
        token = hashlib.sha256(f'{query.casefold()}|{lat}|{lon}'.encode()).hexdigest()
        now = time.monotonic()
        for old in list(self.cache):
            if self.cache[old][0] <= now:
                self.cache.pop(old)
        if token in self.cache:
            self.cache_hits += 1
            self.cache.move_to_end(token)
            return self.cache[token][1]
        if now < self.blocked_until:
            raise HTTPException(429, 'Geoapify đang giới hạn yêu cầu. Vui lòng chờ.',
                headers={'Retry-After':str(math.ceil(self.blocked_until-now)), 'X-RateLimit-Bucket':'geoapify'})
        if token in self.pending:
            self.coalesced += 1
            return await asyncio.shield(self.pending[token])
        if len(self.pending) >= 32:
            raise HTTPException(429, 'Có quá nhiều tìm kiếm đang chờ', headers={'Retry-After':'2'})
        task = asyncio.create_task(self._fetch(query,lat,lon,token))
        self.pending[token] = task
        def completed(done):
            self.pending.pop(token,None)
            if not done.cancelled():
                done.exception()  # Consume failures even if every waiter cancelled.
        task.add_done_callback(completed)
        return await asyncio.shield(task)

    async def _fetch(self, query, lat, lon, token):
        self.budget.reserve()
        started, status = time.perf_counter(), 502
        try:
            response = await asyncio.wait_for(self.client.get('https://api.geoapify.com/v1/geocode/autocomplete',
                params={'text':query, 'filter':'rect:105.2,20.5,106.3,21.6',
                        'bias':f'proximity:{lon},{lat}', 'limit':8, 'lang':'vi',
                        'format':'json', 'apiKey':self.key}), timeout=10)
            status = response.status_code
        except (TimeoutError, httpx.TimeoutException):
            status = 504
            raise HTTPException(504, 'Geoapify hết thời gian phản hồi') from None
        except httpx.RequestError:
            raise HTTPException(502, 'Không kết nối được Geoapify') from None
        finally:
            metrics.record('geoapify.search', (time.perf_counter()-started)*1000, status)
        if status == 429:
            retry = response.headers.get('Retry-After','60')
            retry = min(86400,max(1,int(retry))) if retry.isdigit() else 60
            self.blocked_until = time.monotonic()+retry
            raise HTTPException(429, 'Geoapify đang giới hạn quota',
                headers={'Retry-After':str(retry),'X-RateLimit-Bucket':'geoapify'})
        if status != 200:
            raise HTTPException(502, 'Geoapify từ chối tìm kiếm; kiểm tra key và quyền API')
        try:
            places = []
            for item in response.json()['results']:
                latitude, longitude = float(item['lat']), float(item['lon'])
                if not (20.5 <= latitude <= 21.6 and 105.2 <= longitude <= 106.3):
                    continue
                name = item.get('name') or item['formatted']
                if not isinstance(name,str) or not name.strip():
                    raise ValueError('Missing name')
                # Same-name features within ~45 m often duplicate OSM building/POI records.
                if any(p['name'].casefold()==name.casefold() and
                    math.hypot((p['coordinate']['lat']-latitude)*111000,
                        (p['coordinate']['lon']-longitude)*103000)<45 for p in places):
                    continue
                places.append({'id':item.get('place_id',''), 'name':name,
                    'address':item.get('formatted',''), 'coordinate':{'lat':latitude,'lon':longitude},
                    'provider':'geoapify', 'datasource':item.get('datasource',{})})
        except (KeyError,TypeError,ValueError):
            raise HTTPException(502, 'Dữ liệu tìm kiếm Geoapify không hợp lệ') from None
        self.cache[token] = (time.monotonic()+(600 if places else 30),places)
        while len(self.cache)>256:
            self.cache.popitem(last=False)
        return places

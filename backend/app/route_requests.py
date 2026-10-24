"""Bounded interactive routing requests; independent from scheduler's persisted quota."""
import asyncio
import sqlite3
import time
from datetime import datetime, timezone
from fastapi import HTTPException


class RouteRequests:
    def __init__(self, provider, filename, daily_limit=96):
        self.provider, self.filename, self.daily_limit = provider, filename, daily_limit
        self.pending, self.cache = {}, {}
        self.slots = asyncio.Semaphore(2)
        with sqlite3.connect(filename) as db:
            db.execute('CREATE TABLE IF NOT EXISTS routing_usage (day TEXT PRIMARY KEY, count INTEGER NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS routing_backoff (id INTEGER PRIMARY KEY, until REAL NOT NULL)')

    def reserve(self):
        day = datetime.now(timezone.utc).date().isoformat()
        with sqlite3.connect(self.filename, timeout=5) as db:
            db.execute('BEGIN IMMEDIATE')
            blocked = db.execute('SELECT until FROM routing_backoff WHERE id=1').fetchone()
            if blocked and blocked[0] > time.time():
                raise HTTPException(429, 'Routing yêu cầu chờ trước khi thử lại.', headers={'Retry-After':str(max(1, int(blocked[0]-time.time())+1))})
            row = db.execute('SELECT count FROM routing_usage WHERE day=?', (day,)).fetchone()
            count = row[0] if row else 0
            if count >= self.daily_limit:
                now = datetime.now(timezone.utc)
                retry = 86400 - (now.hour * 3600 + now.minute * 60 + now.second)
                raise HTTPException(429, 'Đã đạt hạn mức routing thử nghiệm trong ngày (UTC).', headers={'Retry-After': str(retry)})
            db.execute('INSERT INTO routing_usage VALUES (?,?) ON CONFLICT(day) DO UPDATE SET count=excluded.count', (day, count + 1))
            db.execute('DELETE FROM routing_usage WHERE day < ?', (day,))

    async def calculate(self, request):
        key = request.model_dump_json()
        now = time.monotonic()
        hit = self.cache.get(key)
        if hit and now - hit[0] < 60:
            return hit[1]
        if key not in self.pending:
            if len(self.pending) >= 8:
                raise HTTPException(429, 'Routing đang bận, thử lại sau.', headers={'Retry-After': '10'})
            task = asyncio.create_task(self.fetch(request, key))
            self.pending[key] = task
            def done(t):
                self.pending.pop(key, None)
                if not t.cancelled():
                    t.exception()  # Observe errors even when the HTTP client disconnected.
            task.add_done_callback(done)
        return await asyncio.shield(self.pending[key])

    async def fetch(self, request, key):
        async with self.slots:
            self.reserve()
            try:
                result = await self.provider.calculate(request)
            except HTTPException as error:
                if error.status_code == 429:
                    try:
                        retry = max(1, int((error.headers or {}).get('Retry-After', '60')))
                    except ValueError:
                        retry = 60
                    with sqlite3.connect(self.filename, timeout=5) as db:
                        db.execute('INSERT INTO routing_backoff VALUES (1,?) ON CONFLICT(id) DO UPDATE SET until=MAX(until,excluded.until)', (time.time()+retry,))
                raise
            if len(self.cache) >= 64:
                self.cache.pop(next(iter(self.cache)))
            self.cache[key] = (time.monotonic(), result)
            return result

    async def close(self):
        tasks = list(self.pending.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

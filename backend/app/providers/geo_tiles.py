"""Authenticated Geoapify raster proxy, bounded HTTP-header-aware RAM cache."""
import asyncio
from collections import OrderedDict
import re
import time
import httpx
from fastapi import HTTPException
from app.metrics import metrics
from app.tile_requests import TileRequests


class GeoapifyTiles:
    def __init__(self, client, key, budget):
        self.client,self.key,self.budget=client,key,budget
        self.cache=OrderedDict()
        self.requests=TileRequests()
        self.hits=0
        self.blocked_until=0
        self.bytes=0
        self.slots=asyncio.Semaphore(3)
        self.next_start=0
        self.pace=asyncio.Lock()

    async def tile(self,z,x,y):
        if not 0<=z<=18 or not 0<=x<2**z or not 0<=y<2**z:
            raise HTTPException(422,'Tile không hợp lệ')
        key=(z,x,y)
        if key in self.cache:
            expiry,data=self.cache[key]
            if expiry>time.monotonic():
                self.cache.move_to_end(key);self.hits+=1
                return data,True
            self.bytes-=len(data);self.cache.pop(key)
        data,joined=await self.requests.get(key,lambda:self.fetch(key))
        return data,joined

    async def fetch(self,key):
        if not self.key:raise HTTPException(503,'Chưa cấu hình Geoapify key')
        if len(self.requests.pending)>128:raise HTTPException(429,'Quá nhiều tile đang chờ',headers={'Retry-After':'2'})
        async with self.slots:
            # Smooth viewport bursts below the shared Free-plan credit rate.
            async with self.pace:
                await asyncio.sleep(max(0,self.next_start-time.monotonic()))
                self.next_start=time.monotonic()+0.15
            if time.monotonic()<self.blocked_until:
                raise HTTPException(429,'Geoapify đang giới hạn tile',headers={'Retry-After':'60'})
            self.budget.reserve('tile')
            started,status=time.perf_counter(),502
            try:
                z,x,y=key
                r=await asyncio.wait_for(self.client.get(f'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png',params={'apiKey':self.key}),timeout=10)
                status=r.status_code
            except (TimeoutError,httpx.TimeoutException):
                status=504
                raise HTTPException(504,'Geoapify map hết thời gian phản hồi') from None
            except httpx.RequestError:
                raise HTTPException(502,'Không kết nối được bản đồ Geoapify') from None
            finally:metrics.record('geoapify.map',(time.perf_counter()-started)*1000,status)
            if status==429:
                self.blocked_until=time.monotonic()+60
                raise HTTPException(429,'Geoapify đang giới hạn tile',headers={'Retry-After':'60'})
            if status!=200 or 'image/png' not in r.headers.get('content-type','') or not r.content.startswith(b'\x89PNG\r\n\x1a\n'):
                raise HTTPException(502,'Geoapify trả tile không hợp lệ')
            control=r.headers.get('cache-control','').lower()
            age=re.search(r'max-age=(\d+)',control)
            if age and not any(v in control for v in ('no-store','no-cache','private')):
                ttl=min(3600,int(age.group(1)))
                if ttl and len(r.content)<=1024*1024:
                    self.cache[key]=(time.monotonic()+ttl,r.content);self.bytes+=len(r.content)
                    while len(self.cache)>256 or self.bytes>32*1024*1024:
                        _,(_,data)=self.cache.popitem(last=False);self.bytes-=len(data)
            return r.content

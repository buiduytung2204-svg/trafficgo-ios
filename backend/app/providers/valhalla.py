from datetime import datetime, timezone
from urllib.parse import urlparse
from uuid import uuid4
from zoneinfo import ZoneInfo
import asyncio
import time
import httpx
from fastapi import HTTPException
from app.metrics import metrics
from app.schemas import Route
from app.providers.routing import RoutingProvider


class ValhallaRoutingProvider(RoutingProvider):
    def __init__(self, client: httpx.AsyncClient, base_url: str):
        self.client, self.base_url = client, base_url.rstrip('/')

    async def calculate(self, request):
        if request.vehicle != 'car':
            raise HTTPException(422, 'Xe máy chưa được xác minh tại Việt Nam')
        url = urlparse(self.base_url)
        if url.scheme not in ('http', 'https') or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise HTTPException(503, 'Chưa cấu hình endpoint Valhalla tin cậy')
        options = {}
        if request.avoid_tolls:
            options['use_tolls'] = 0
        if request.avoid_highways:
            options['use_highways'] = 0
        body = {'locations': [request.origin.model_dump(), request.destination.model_dump()],
                'costing': 'auto', 'costing_options': {'auto': options},
                'format': 'osrm', 'shape_format': 'geojson', 'units': 'kilometers',
                'language': 'en-US', 'alternates': 2}
        if request.departure:
            body['date_time'] = {'type': 1, 'value': request.departure.astimezone(ZoneInfo('Asia/Ho_Chi_Minh')).strftime('%Y-%m-%dT%H:%M')}
            # Valhalla does not support alternates on time-dependent requests.
            body['alternates'] = 0
        start, status = time.perf_counter(), 502
        try:
            response = await asyncio.wait_for(self.client.post(self.base_url+'/route', json=body), timeout=10)
            status = response.status_code
        except (TimeoutError, httpx.TimeoutException):
            status = 504
            raise HTTPException(504, 'Valhalla hết thời gian phản hồi') from None
        except httpx.RequestError:
            raise HTTPException(502, 'Không kết nối được Valhalla') from None
        finally:
            metrics.record('valhalla.routing', (time.perf_counter()-start)*1000, status)
        if status != 200:
            raise HTTPException(429 if status == 429 else 502, 'Valhalla không trả được tuyến',
                headers={'Retry-After': '60', 'X-RateLimit-Bucket': 'valhalla'} if status == 429 else None)
        try:
            data = response.json()
            if data.get('code') not in (None, 'Ok'):
                raise ValueError('Invalid OSRM result')
            routes = []
            for item in data['routes'][:3]:
                routes.append(Route(id=str(uuid4()), distance_m=round(item['distance']),
                    duration_s=round(item['duration']),
                    geometry=[{'lat':p[1], 'lon':p[0]} for p in item['geometry']['coordinates']],
                    legs=[{'distance_m':leg.get('distance'), 'duration_s':leg.get('duration')} for leg in item.get('legs',[])],
                    instructions=[step for leg in item.get('legs',[]) for step in leg.get('steps',[])],
                    provider='valhalla', vehicle='car', retrieved_at=datetime.now(timezone.utc),
                    traffic_aware=False, traffic_delay_s=None))
            return sorted(routes, key=lambda route: route.duration_s)
        except (KeyError, TypeError, ValueError, IndexError):
            raise HTTPException(502, 'Dữ liệu tuyến Valhalla không hợp lệ') from None


class FallbackRoutingProvider(RoutingProvider):
    def __init__(self, primary, fallback=None):
        self.primary, self.fallback = primary, fallback

    async def calculate(self, request):
        try:
            return await self.primary.calculate(request)
        except HTTPException as error:
            if self.fallback is None or error.status_code not in (502, 503, 504):
                raise
            routes = await self.fallback.calculate(request)
            for route in routes:
                route.fallback_reason = f'valhalla_unavailable_{error.status_code}'
            return routes

from abc import ABC, abstractmethod
from datetime import datetime, timezone
from uuid import uuid4
import asyncio
import httpx
import time
import math
from urllib.parse import urlparse
from zoneinfo import ZoneInfo
from fastapi import HTTPException
from app.schemas import Route, RouteRequest
from app.metrics import metrics


class RoutingProvider(ABC):
    @abstractmethod
    async def calculate(self, request: RouteRequest) -> list[Route]: ...


def decode_polyline6(shape: str) -> list[dict]:
    """Valhalla native shapes encode latitude then longitude at precision 1e-6."""
    if not isinstance(shape, str) or not shape or len(shape) > 2_000_000:
        raise ValueError('Invalid shape')
    index, lat, lon = 0, 0, 0
    points = []
    while index < len(shape):
        deltas = []
        for _ in range(2):
            value, shift = 0, 0
            while True:
                if index >= len(shape) or shift > 30:
                    raise ValueError('Truncated or oversized polyline component')
                byte = ord(shape[index]) - 63
                index += 1
                if not 0 <= byte <= 63:
                    raise ValueError('Invalid polyline character')
                value |= (byte & 31) << shift
                if byte < 32:
                    break
                shift += 5
            deltas.append(~(value >> 1) if value & 1 else value >> 1)
        lat += deltas[0]
        lon += deltas[1]
        if not (-90_000_000 <= lat <= 90_000_000 and -180_000_000 <= lon <= 180_000_000):
            raise ValueError('Invalid coordinate')
        points.append({'lat': lat / 1_000_000, 'lon': lon / 1_000_000})
    if len(points) < 2:
        raise ValueError('Shape needs two points')
    return points


class ValhallaRoutingProvider(RoutingProvider):
    """Native Valhalla JSON; no live traffic assumptions, retries or demo default."""

    def __init__(self, client: httpx.AsyncClient, base_url: str):
        self.client, self.base_url = client, base_url.rstrip('/')

    async def calculate(self, request: RouteRequest) -> list[Route]:
        url = urlparse(self.base_url)
        if url.scheme not in ('http', 'https') or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise HTTPException(503, 'Chưa cấu hình endpoint Valhalla tin cậy')
        profile = 'motor_scooter' if request.vehicle == 'motorcycle' else 'auto'
        options = {}
        if request.avoid_tolls:
            options['use_tolls'] = 0
        if request.avoid_highways:
            options['use_highways'] = 0
        body = {'locations': [request.origin.model_dump(), request.destination.model_dump()],
                'costing': profile, 'costing_options': {profile: options},
                'format': 'json', 'units': 'kilometers', 'language': 'en-US', 'alternates': 2}
        if request.departure:
            body['date_time'] = {'type': 1, 'value': request.departure.astimezone(ZoneInfo('Asia/Ho_Chi_Minh')).strftime('%Y-%m-%dT%H:%M')}
            body['alternates'] = 0
        endpoint = self.base_url if url.path.endswith('/route') else self.base_url + '/route'
        started, status = time.perf_counter(), 502
        try:
            response = await asyncio.wait_for(self.client.post(endpoint, json=body), timeout=10)
            status = response.status_code
        except (TimeoutError, httpx.TimeoutException):
            status = 504
            raise HTTPException(504, 'Valhalla hết thời gian phản hồi') from None
        except httpx.RequestError:
            raise HTTPException(502, 'Không kết nối được Valhalla') from None
        finally:
            metrics.record('valhalla.routing', (time.perf_counter()-started)*1000, status)
        if status != 200:
            retry = response.headers.get('Retry-After', '60')
            raise HTTPException(429 if status == 429 else 502, 'Valhalla không trả được tuyến',
                headers={'Retry-After': retry if retry.isdigit() else '60', 'X-RateLimit-Bucket': 'valhalla'} if status == 429 else None)
        try:
            data = response.json()
            trip = data['trip']
            if trip['status'] != 0:
                raise ValueError('Valhalla unsuccessful trip')
            candidates = [trip] + [alternate['trip'] for alternate in data.get('alternates', [])[:2]]
            routes = [self._normalize(item, request.vehicle) for item in candidates]
            return sorted(routes, key=lambda route: route.duration_s)
        except (KeyError, TypeError, ValueError, IndexError, OverflowError):
            raise HTTPException(502, 'Dữ liệu tuyến Valhalla không hợp lệ') from None

    @staticmethod
    def _normalize(trip: dict, vehicle: str = 'car') -> Route:
        if not isinstance(trip, dict):
            raise ValueError('Invalid trip')
        if trip.get('status', 0) != 0 or trip['units'] not in ('kilometers', 'miles'):
            raise ValueError('Invalid trip status or units')
        scale = 1000 if trip['units'] == 'kilometers' else 1609.344
        def summary(raw):
            distance, duration = float(raw['length']) * scale, float(raw['time'])
            if not all(math.isfinite(value) and value >= 0 for value in (distance, duration)):
                raise ValueError('Invalid summary')
            return {'distance_m': round(distance), 'duration_s': round(duration)}
        geometry, legs, instructions = [], [], []
        for leg in trip['legs']:
            points = decode_polyline6(leg['shape'])
            # Leg shape indices are local; normalize instructions to the joined geometry.
            shared = bool(geometry and geometry[-1] == points[0])
            offset = len(geometry) - int(shared)
            geometry.extend(points[1:] if shared else points)
            legs.append(summary(leg['summary']))
            for maneuver in leg.get('maneuvers', []):
                begin, end = maneuver['begin_shape_index'], maneuver['end_shape_index']
                if not isinstance(begin, int) or not isinstance(end, int) or not 0 <= begin <= end < len(points):
                    raise ValueError('Invalid maneuver shape index')
                instructions.append({**maneuver, 'begin_shape_index': begin + offset,
                                     'end_shape_index': end + offset, **summary(maneuver)})
        return Route(id=str(uuid4()), **summary(trip['summary']), geometry=geometry, legs=legs,
                     instructions=instructions, provider='valhalla', vehicle=vehicle,
                     retrieved_at=datetime.now(timezone.utc), traffic_aware=False, traffic_delay_s=None)


class TomTomRoutingProvider(RoutingProvider):
    def __init__(self, client: httpx.AsyncClient, key: str, before_attempt=None):
        self.client, self.key = client, key
        self.before_attempt = before_attempt

    async def get(self, path: str, params: dict):
        if not self.key:
            raise HTTPException(503, 'Chưa cấu hình TomTom API key')
        # Tiles fan out on every viewport change. Do not double a failed burst
        # or make users wait 20s per tile when the provider/network is down.
        attempts = 1 if '/tile/' in path else 2
        for attempt in range(attempts):
            if self.before_attempt:
                self.before_attempt()
            started = time.perf_counter()
            status = 502
            category = ('traffic' if path.startswith('traffic/') else 'map' if '/tile/' in path else
                        'search' if path.startswith('search/') else 'routing' if path.startswith('routing/') else 'attribution')
            try:
                response = await asyncio.wait_for(
                    self.client.get('https://api.tomtom.com/' + path,
                                    params={**params, 'key': self.key}), timeout=10)
                status = response.status_code
            except (httpx.TimeoutException, TimeoutError):
                status = 504
                if attempt + 1 < attempts:
                    await asyncio.sleep(0.25)
                    continue
                raise HTTPException(504, 'Nhà cung cấp hết thời gian phản hồi') from None
            except httpx.RequestError:
                raise HTTPException(502, 'Không kết nối được nhà cung cấp') from None
            finally:
                metrics.record('tomtom.' + category, (time.perf_counter()-started)*1000, status)
            if response.status_code >= 500 and attempt + 1 < attempts:
                await asyncio.sleep(0.25)
                continue
            if response.status_code != 200:
                code = 429 if response.status_code == 429 else 502
                headers = {'X-RateLimit-Bucket': 'tomtom'} if code == 429 else None
                if headers is not None:
                    retry = response.headers.get('Retry-After', '60')
                    headers['Retry-After'] = retry if retry.isdigit() else '60'
                raise HTTPException(code, 'Nhà cung cấp từ chối yêu cầu; kiểm tra quota và cấu hình', headers=headers)
            return response
        raise HTTPException(502, 'Nhà cung cấp không khả dụng')

    async def calculate(self, request):
        if request.vehicle != 'car':
            raise HTTPException(422, 'Xe máy chưa được xác minh cho Việt Nam trên stack hiện tại')
        o, d = request.origin, request.destination
        params = {'traffic': 'true', 'travelMode': 'car', 'maxAlternatives': 2,
                  'instructionsType': 'text', 'language': 'vi-VN',
                  'departAt': request.departure.isoformat() if request.departure else 'now'}
        avoid = []
        if request.avoid_tolls:
            avoid.append('tollRoads')
        if request.avoid_highways:
            avoid.append('motorways')
        if avoid:
            params['avoid'] = ','.join(avoid)
        response = await self.get(f'routing/1/calculateRoute/{o.lat},{o.lon}:{d.lat},{d.lon}/json', params)
        try:
            routes = []
            for raw in response.json().get('routes', [])[:3]:
                summary = raw['summary']
                routes.append(Route(id=str(uuid4()), distance_m=summary['lengthInMeters'],
                    duration_s=summary['travelTimeInSeconds'], traffic_delay_s=summary.get('trafficDelayInSeconds'),
                    geometry=[{'lat': p['latitude'], 'lon': p['longitude']} for leg in raw['legs'] for p in leg['points']],
                    legs=[{'summary': leg.get('summary', {})} for leg in raw['legs']],
                    instructions=raw.get('guidance', {}).get('instructions', []),
                    retrieved_at=datetime.now(timezone.utc), vehicle=request.vehicle))
            return sorted(routes, key=lambda route: route.duration_s)
        except (KeyError, ValueError, TypeError):
            raise HTTPException(502, 'Dữ liệu tuyến không hợp lệ') from None


class GoogleRoutingProvider(RoutingProvider):
    async def calculate(self, request):
        raise HTTPException(501, 'Google Routes cần Google map và xét lại giấy phép trước khi bật')


class HereRoutingProvider(RoutingProvider):
    async def calculate(self, request):
        raise HTTPException(501, 'HERE chưa được cấu hình và xác minh')

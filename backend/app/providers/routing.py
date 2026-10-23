from abc import ABC, abstractmethod
from datetime import datetime, timezone
from uuid import uuid4
import asyncio
import httpx
from fastapi import HTTPException
from app.schemas import Route, RouteRequest


class RoutingProvider(ABC):
    @abstractmethod
    async def calculate(self, request: RouteRequest) -> list[Route]: ...


class TomTomRoutingProvider(RoutingProvider):
    def __init__(self, client: httpx.AsyncClient, key: str, before_attempt=None):
        self.client, self.key = client, key
        self.before_attempt = before_attempt

    async def get(self, path: str, params: dict):
        if not self.key:
            raise HTTPException(503, 'Chưa cấu hình TomTom API key')
        for attempt in range(2):
            if self.before_attempt:
                self.before_attempt()
            try:
                response = await asyncio.wait_for(
                    self.client.get('https://api.tomtom.com/' + path,
                                    params={**params, 'key': self.key}), timeout=10)
            except (httpx.TimeoutException, TimeoutError):
                if attempt == 0:
                    await asyncio.sleep(0.25)
                    continue
                raise HTTPException(504, 'Nhà cung cấp hết thời gian phản hồi') from None
            except httpx.RequestError:
                raise HTTPException(502, 'Không kết nối được nhà cung cấp') from None
            if response.status_code >= 500 and attempt == 0:
                await asyncio.sleep(0.25)
                continue
            if response.status_code != 200:
                code = 429 if response.status_code == 429 else 502
                raise HTTPException(code, 'Nhà cung cấp từ chối yêu cầu; kiểm tra quota và cấu hình')
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

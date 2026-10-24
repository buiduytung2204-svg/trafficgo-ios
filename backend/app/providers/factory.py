"""One routing policy for HTTP requests and the departure worker."""
from fastapi import HTTPException
from app.providers.routing import RoutingProvider, TomTomRoutingProvider, ValhallaRoutingProvider


class TrafficRoutingPolicy(RoutingProvider):
    def __init__(self, client, settings):
        self.settings = settings
        self.valhalla = ValhallaRoutingProvider(client, settings.valhalla_base_url)
        self.tomtom = TomTomRoutingProvider(client, settings.tomtom_api_key,
            motorcycle_verified=(settings.tomtom_motorcycle_vietnam_verified or
                                 settings.tomtom_motorcycle_experimental_enabled))

    async def calculate(self, request):
        if self.settings.routing_provider == 'valhalla':
            return await self.valhalla.calculate(request)
        if not self.settings.tomtom_routing_license_confirmed:
            raise HTTPException(503, 'Chưa xác nhận giấy phép TomTom cho bản đồ và điều hướng hiện tại')
        if request.vehicle == 'motorcycle' and not (self.settings.tomtom_motorcycle_vietnam_verified or
                                                   self.settings.tomtom_motorcycle_experimental_enabled):
            routes = await self.valhalla.calculate(request)
            for route in routes:
                route.fallback_reason = 'motorcycle_traffic_not_verified_vietnam'
            return routes
        # No hidden retry/fallback on 429: the caller persists Retry-After.
        return await self.tomtom.calculate(request)


def create_routing_provider(client, settings):
    return TrafficRoutingPolicy(client, settings)

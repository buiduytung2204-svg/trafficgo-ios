"""Compatibility imports and explicit routing fallback policy."""
from fastapi import HTTPException
from app.providers.routing import RoutingProvider, ValhallaRoutingProvider


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

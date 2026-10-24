from unittest.mock import AsyncMock
import httpx
import pytest
from fastapi import HTTPException
from app.config import Settings
from app.providers.factory import create_routing_provider
from app.schemas import RouteRequest


def request(vehicle='car'):
    return RouteRequest(origin={'lat':21.02,'lon':105.85},
                        destination={'lat':21.04,'lon':105.82}, vehicle=vehicle)


@pytest.mark.asyncio
async def test_license_guard_does_not_call_provider():
    async with httpx.AsyncClient() as client:
        policy = create_routing_provider(client, Settings(_env_file=None, routing_provider='tomtom'))
        policy.tomtom.calculate = AsyncMock()
        with pytest.raises(HTTPException) as error:
            await policy.calculate(request())
        assert error.value.status_code == 503
        policy.tomtom.calculate.assert_not_called()


@pytest.mark.asyncio
async def test_unverified_motorcycle_stays_valhalla():
    async with httpx.AsyncClient() as client:
        policy = create_routing_provider(client, Settings(_env_file=None, routing_provider='tomtom',
            tomtom_routing_license_confirmed=True))
        policy.valhalla.calculate = AsyncMock(return_value=[])
        policy.tomtom.calculate = AsyncMock()
        assert await policy.calculate(request('motorcycle')) == []
        policy.valhalla.calculate.assert_awaited_once()
        policy.tomtom.calculate.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize('vehicle', ['car', 'motorcycle'])
async def test_live_delay_and_profile_are_provider_values(vehicle):
    seen = []
    def handler(req):
        seen.append(req)
        return httpx.Response(200, json={'routes':[
            {'summary':{'lengthInMeters':1200,'travelTimeInSeconds':2100,'trafficDelayInSeconds':480},
             'legs':[{'points':[{'latitude':21.02,'longitude':105.85},
                                 {'latitude':21.04,'longitude':105.82}]}]}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        policy = create_routing_provider(client, Settings(_env_file=None, routing_provider='tomtom',
            tomtom_routing_license_confirmed=True, tomtom_motorcycle_experimental_enabled=True,
            tomtom_api_key='test-only'))
        routes = await policy.calculate(request(vehicle))
    assert len(seen) == 1
    assert seen[0].url.params['travelMode'] == vehicle
    assert seen[0].url.params['traffic'] == 'true'
    assert seen[0].url.params['computeTravelTimeFor'] == 'all'
    assert routes[0].duration_s == 2100
    assert routes[0].traffic_delay_s == 480
    assert routes[0].traffic_aware and routes[0].provider == 'tomtom'


@pytest.mark.asyncio
async def test_429_is_not_retried_or_switched():
    seen = []
    def handler(req):
        seen.append(req)
        return httpx.Response(429, headers={'Retry-After':'120'})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        policy = create_routing_provider(client, Settings(_env_file=None, routing_provider='tomtom',
            tomtom_routing_license_confirmed=True, tomtom_api_key='test-only'))
        with pytest.raises(HTTPException) as error:
            await policy.calculate(request())
    assert len(seen) == 1
    assert error.value.status_code == 429
    assert error.value.headers['Retry-After'] == '120'

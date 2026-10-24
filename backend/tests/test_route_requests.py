import asyncio
import pytest
from fastapi import HTTPException
from app.route_requests import RouteRequests
from app.schemas import RouteRequest

@pytest.mark.asyncio
async def test_route_coalescing_cache_budget_survives_restart(tmp_path):
    class Provider:
        calls = 0
        async def calculate(self, request):
            self.calls += 1
            await asyncio.sleep(.01)
            return []
    provider = Provider()
    filename = str(tmp_path / 'routing.db')
    service = RouteRequests(provider, filename, 1)
    request = RouteRequest(origin={'lat':21.02,'lon':105.85}, destination={'lat':21.04,'lon':105.82})
    await asyncio.gather(service.calculate(request), service.calculate(request))
    await service.calculate(request)
    assert provider.calls == 1
    restarted = RouteRequests(provider, filename, 1)
    with pytest.raises(HTTPException) as error:
        await restarted.calculate(request)
    assert error.value.status_code == 429
    assert int(error.value.headers['Retry-After']) > 0
    assert provider.calls == 1
    await service.close()
    await restarted.close()

@pytest.mark.asyncio
async def test_provider_retry_after_blocks_repeated_calls_and_restart(tmp_path):
    class Provider:
        calls = 0
        async def calculate(self, request):
            self.calls += 1
            raise HTTPException(429, 'Wait', headers={'Retry-After':'120'})
    p = Provider()
    filename = str(tmp_path / 'routing.db')
    req = RouteRequest(origin={'lat':21.02,'lon':105.85}, destination={'lat':21.04,'lon':105.82})
    for _ in range(2):
        guard = RouteRequests(p, filename)
        with pytest.raises(HTTPException) as error:
            await guard.calculate(req)
        assert error.value.status_code == 429
        assert int(error.value.headers['Retry-After']) >= 119
        await guard.close()
    assert p.calls == 1

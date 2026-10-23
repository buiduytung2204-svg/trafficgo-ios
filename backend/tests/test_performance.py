import asyncio
import httpx
import pytest
from fastapi import HTTPException
from app.metrics import Metrics
from app.tile_requests import TileRequests
from app.providers.valhalla import ValhallaRoutingProvider, FallbackRoutingProvider
from app.schemas import RouteRequest
from test_api import client, body


@pytest.mark.asyncio
async def test_coalesce_only_in_flight_not_a_cache():
    requests = TileRequests()
    calls = 0
    async def fetch():
        nonlocal calls
        calls += 1
        await asyncio.sleep(.01)
        return b'actual response'
    results = await asyncio.gather(*(requests.get(('traffic',13,1,2),fetch) for _ in range(8)))
    assert calls == 1
    assert sum(joined for _,joined in results) == 7
    assert not requests.pending
    await requests.get(('traffic',13,1,2),fetch)
    assert calls == 2


@pytest.mark.asyncio
async def test_cancelled_waiter_does_not_cancel_shared_request():
    requests=TileRequests()
    done=asyncio.Event()
    async def fetch():
        await done.wait()
        return 'response'
    first=asyncio.create_task(requests.get('key',fetch))
    await asyncio.sleep(0)
    second=asyncio.create_task(requests.get('key',fetch))
    await asyncio.sleep(0)
    first.cancel()
    with pytest.raises(asyncio.CancelledError):
        await first
    done.set()
    assert (await second)[0]=='response'


def test_metrics_percentiles_errors_and_bound():
    metrics=Metrics()
    for i in range(1,101):
        metrics.record('test',i,429 if i==100 else 200)
    result=metrics.snapshot()['test']
    assert result['p50_ms']==50 and result['p95_ms']==95
    assert result['requests']==100 and result['error_rate']==.01 and result['rate_limited']==1


def test_diagnostics_auth_and_server_timing(client):
    assert client.get('/api/v1/diagnostics',headers={'X-App-Token':'wrong'}).status_code==401
    response=client.get('/api/v1/diagnostics')
    assert response.status_code==200
    assert 'backend_total;dur=' in response.headers['Server-Timing']
    assert 'test-access' not in response.text


@pytest.mark.asyncio
async def test_valhalla_native_normalization_and_options():
    def handler(request):
        import json
        sent=json.loads(request.content)
        assert sent['costing']=='auto' and sent['format']=='json'
        assert sent['costing_options']['auto']['use_tolls']==0
        from test_valhalla import native_response
        return httpx.Response(200,json=native_response())
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as transport:
        routes=await ValhallaRoutingProvider(transport,'http://localhost:8002').calculate(RouteRequest(**body(),avoid_tolls=True))
    assert routes[0].provider=='valhalla' and routes[0].traffic_aware is False
    assert routes[0].traffic_delay_s is None and routes[0].distance_m==1234
    assert routes[0].geometry[0].lat==21.02


@pytest.mark.asyncio
@pytest.mark.parametrize('status',[429,500])
async def test_valhalla_failure_and_motorcycle(status):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(status))) as transport:
        provider=ValhallaRoutingProvider(transport,'http://localhost:8002')
        with pytest.raises(HTTPException) as error:
            await provider.calculate(RouteRequest(**body()))
        assert error.value.status_code==(429 if status==429 else 502)
        with pytest.raises(HTTPException) as error:
            await provider.calculate(RouteRequest(**body(),vehicle='motorcycle'))
        assert error.value.status_code==(429 if status==429 else 502)


@pytest.mark.asyncio
async def test_fallback_is_explicit_and_does_not_evade_rate_limit():
    class Failed:
        async def calculate(self,request): raise HTTPException(503,'offline')
    class Limited:
        async def calculate(self,request): raise HTTPException(429,'limited')
    class Secondary:
        calls=0
        async def calculate(self,request):self.calls+=1;return []
    secondary=Secondary()
    with pytest.raises(HTTPException):await FallbackRoutingProvider(Failed()).calculate(RouteRequest(**body()))
    assert await FallbackRoutingProvider(Failed(),secondary).calculate(RouteRequest(**body()))==[]
    assert secondary.calls==1
    with pytest.raises(HTTPException):await FallbackRoutingProvider(Limited(),secondary).calculate(RouteRequest(**body()))
    assert secondary.calls==1


@pytest.mark.asyncio
async def test_valhalla_empty_malformed_and_timeout():
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json={'trip':{'status':0,'units':'kilometers','summary':{'length':0,'time':0},'legs':[]}}))) as transport:
        with pytest.raises(HTTPException) as error:
            await ValhallaRoutingProvider(transport,'http://localhost').calculate(RouteRequest(**body()))
        assert error.value.status_code==502
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json={'routes':[{}]}))) as transport:
        with pytest.raises(HTTPException) as error:
            await ValhallaRoutingProvider(transport,'http://localhost').calculate(RouteRequest(**body()))
        assert error.value.status_code==502
    def timeout(request):raise httpx.ReadTimeout('timed out')
    async with httpx.AsyncClient(transport=httpx.MockTransport(timeout)) as transport:
        with pytest.raises(HTTPException) as error:
            await ValhallaRoutingProvider(transport,'http://localhost').calculate(RouteRequest(**body()))
        assert error.value.status_code==504


def test_valhalla_selection_independent_of_tomtom_budget(client, monkeypatch):
    from app.main import settings, daily
    from datetime import datetime, timezone
    monkeypatch.setattr(settings,'routing_provider','valhalla')
    daily.update(date=datetime.now(timezone.utc).date().isoformat(),count=settings.daily_provider_budget)
    class Router:
        async def calculate(self,request):return []
    client.app.state.routing=Router()
    assert client.post('/api/v1/routes/calculate',json=body()).status_code==200
    assert client.post('/api/v1/routes/calculate',json={**body(),'vehicle':'motorcycle'}).status_code==200

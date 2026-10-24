from test_api import client, body
from app.main import settings, daily
from app.providers.routing import TomTomRoutingProvider
from app.schemas import RouteRequest
from fastapi import HTTPException
import httpx
import pytest


def test_request_budget_and_body_limit(client):
    daily.update(date='',count=0)
    original=settings.daily_provider_budget
    settings.daily_provider_budget=1
    from datetime import datetime, timezone
    daily.update(date=datetime.now(timezone.utc).date().isoformat(), count=1)
    try:
        assert client.post('/api/v1/routes/calculate',json=body()).status_code==503
    finally:
        settings.daily_provider_budget=original
        daily.update(date='',count=0)
    assert client.post('/api/v1/routes/calculate',content='x'*33000).status_code==413
    assert client.get('/api/v1/traffic/status',headers={'Content-Length':'bad'}).status_code==400


def test_unconfigured_provider_never_returns_fake(client):
    assert client.get('/api/v1/traffic/status').json()['status']=='unavailable'
    assert client.post('/api/v1/routes/calculate',json=body()).status_code==503
    assert client.get('/api/v1/places/search?q=Hanoi').status_code==503


@pytest.mark.asyncio
async def test_malformed_upstream_and_retry_bound():
    calls=[]
    def handler(request):
        calls.append(request)
        return httpx.Response(503)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        with pytest.raises(HTTPException):
            await TomTomRoutingProvider(c,'key').calculate(RouteRequest(**body()))
    assert len(calls)==1  # Routing never doubles a failed request against the quota.
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json={'routes':[{}]}))) as c:
        with pytest.raises(HTTPException) as e:
            await TomTomRoutingProvider(c,'key').calculate(RouteRequest(**body()))
        assert e.value.status_code==502


def test_tile_burst_does_not_block_search_or_routes(client):
    class Provider:
        async def get(self, path, params):
            if path.startswith('search/'):
                return httpx.Response(200, json={'results': []})
            return httpx.Response(200, content=b'png', headers={'content-type': 'image/png'})
        async def calculate(self, request):
            return []
    class Search:
        async def search(self, *args): return []
    class Tiles:
        async def tile(self, *args): return b'png', False
    client.app.state.routing = Provider()
    client.app.state.search = Search()
    client.app.state.geo_tiles = Tiles()
    for _ in range(181):
        assert client.get('/api/v1/geo/tiles/13/6504/3606.png').status_code == 200
    assert client.get('/api/v1/places/search?q=Hanoi').status_code == 200
    assert client.post('/api/v1/routes/calculate', json=body()).status_code == 200


def test_tile_limit_still_applies_independently(client, monkeypatch):
    monkeypatch.setattr(settings, 'tile_requests_per_minute', 2)
    # Missing provider key yields 503 but each request is still rate limited.
    for _ in range(2):
        assert client.get('/api/v1/geo/tiles/13/6504/3606.png').status_code == 503
    response = client.get('/api/v1/geo/tiles/13/6504/3606.png')
    assert response.status_code == 429
    assert response.headers['X-RateLimit-Bucket'] == 'tiles'
    assert 1 <= int(response.headers['Retry-After']) <= 60
    assert client.get('/api/v1/traffic/status').status_code == 200


@pytest.mark.asyncio
async def test_budget_counts_actual_attempts_only():
    attempts=[]
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json={}))) as c:
        p=TomTomRoutingProvider(c,'test',before_attempt=lambda:attempts.append(1))
        await p.get('map/test',{})
    assert len(attempts)==1
    attempts.clear()
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(503))) as c:
        p=TomTomRoutingProvider(c,'test',before_attempt=lambda:attempts.append(1))
        with pytest.raises(HTTPException):
            await p.get('map/test',{})
    assert len(attempts)==2


def test_daily_budget_survives_restart(monkeypatch, tmp_path):
    from app.main import app, reserve_attempts
    from fastapi.testclient import TestClient
    from datetime import datetime, timezone
    monkeypatch.setattr(settings, 'tomtom_api_key', '')
    monkeypatch.setattr(settings, 'provider_budget_file', str(tmp_path/'budget.json'))
    daily.update(date=datetime.now(timezone.utc).date().isoformat(),count=0)
    reserve_attempts(1)
    daily['count']=0
    with TestClient(app):
        assert daily['count']==1


def test_tomtom_endpoints_retired_without_upstream(client):
    assert client.get('/api/v1/tiles/map/13/6504/3606.png').status_code == 410
    assert client.get('/api/v1/tiles/traffic/13/6504/3606.png').status_code == 410
    assert not hasattr(client.app.state, 'provider')
    status = client.get('/api/v1/traffic/status').json()
    assert status['status'] == 'unavailable' and status['provider'] is None
    assert 'TomTom' not in client.get('/api/v1/attribution').text

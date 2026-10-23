from datetime import datetime, timezone, timedelta
import httpx
import jwt
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from app.main import app, db, settings, windows, daily
from app.database import Base
from app.providers.routing import TomTomRoutingProvider
from app.schemas import RouteRequest


@pytest.fixture
def client(monkeypatch):
    # Unit tests must never consume a developer's real provider credentials.
    monkeypatch.setattr(settings, 'tomtom_api_key', '')
    monkeypatch.setattr(settings, 'provider_budget_file', '')
    settings.app_access_token = 'test-access'
    settings.jwt_secret = 'test-secret-that-is-at-least-32-characters'
    windows.clear()
    daily.update(date='', count=0)
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    def session():
        with Session(engine) as s:
            yield s
    app.dependency_overrides[db] = session
    with TestClient(app) as c:
        c.headers['X-App-Token'] = 'test-access'
        yield c
    app.dependency_overrides.clear()


def body():
    return {'origin': {'lat': 21.02, 'lon': 105.85}, 'destination': {'lat': 21.04, 'lon': 105.82}}


def token(uid):
    return jwt.encode({'sub': uid, 'exp': datetime.now(timezone.utc) + timedelta(minutes=5),
                       'iss': 'trafficgo', 'aud': 'trafficgo'}, settings.jwt_secret, algorithm='HS256')


def test_health_auth_validation(client):
    assert client.get('/health').status_code == 200
    assert client.get('/api/v1/traffic/status', headers={'X-App-Token': 'bad'}).status_code == 401
    assert client.post('/api/v1/routes/calculate', json={**body(), 'vehicle': 'bike'}).status_code == 422
    assert client.post('/api/v1/routes/calculate', json={**body(), 'origin': {'lat': 0, 'lon': 0}}).status_code == 422
    assert client.post('/api/v1/routes/calculate', json={**body(), 'vehicle': 'motorcycle'}).status_code == 422
    assert client.get('/api/v1/tiles/map/3/100/1.png').status_code == 422


def test_personal_access(client):
    assert client.get('/api/v1/saved-places').status_code == 401
    a = {'Authorization': 'Bearer ' + token('alice')}
    b = {'Authorization': 'Bearer ' + token('bob')}
    saved = client.post('/api/v1/saved-places', json={'name': 'Nhà', 'coordinate': body()['origin']}, headers=a)
    assert saved.status_code == 201
    assert client.get('/api/v1/saved-places', headers=b).json() == []
    assert client.delete('/api/v1/saved-places/' + saved.json()['id'], headers=b).status_code == 404
    assert client.patch('/api/v1/settings', json={'traffic': False}, headers=a).json()['traffic'] is False
    assert client.patch('/api/v1/settings', json={'theme': 'dark'}, headers=a).json()['traffic'] is False
    assert client.delete('/api/v1/saved-places/' + saved.json()['id'], headers=a).status_code == 204


def test_rate_limit(client):
    for _ in range(180):
        assert client.get('/api/v1/traffic/status').status_code == 200
    assert client.get('/api/v1/traffic/status').status_code == 429


@pytest.mark.asyncio
@pytest.mark.parametrize('status,expected', [(401,502),(403,502),(429,429),(500,502)])
async def test_provider_errors(status, expected):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status))) as c:
        p = TomTomRoutingProvider(c, 'secret')
        with pytest.raises(HTTPException) as e:
            await p.calculate(RouteRequest(**body()))
        assert e.value.status_code == expected
        assert 'secret' not in e.value.detail


@pytest.mark.asyncio
async def test_timeout():
    def timeout(request):
        raise httpx.ReadTimeout('timeout')
    async with httpx.AsyncClient(transport=httpx.MockTransport(timeout)) as c:
        with pytest.raises(HTTPException) as e:
            await TomTomRoutingProvider(c, 'key').calculate(RouteRequest(**body()))
        assert e.value.status_code == 504


@pytest.mark.asyncio
async def test_normalization_and_empty():
    raw = {'summary': {'lengthInMeters': 1200, 'travelTimeInSeconds': 240, 'trafficDelayInSeconds': 30},
           'legs': [{'points': [{'latitude': 21.02, 'longitude': 105.85}, {'latitude': 21.04, 'longitude': 105.82}]}]}
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={'routes': [raw]}))) as c:
        routes = await TomTomRoutingProvider(c, 'key').calculate(RouteRequest(**body()))
        assert routes[0].distance_m == 1200
        assert routes[0].traffic_delay_s == 30
        assert routes[0].geometry[1].lon == 105.82
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={'routes': []}))) as c:
        assert await TomTomRoutingProvider(c, 'key').calculate(RouteRequest(**body())) == []

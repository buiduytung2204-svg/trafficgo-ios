import copy
import json
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi import HTTPException

from app.config import Settings
from app.providers.routing import ValhallaRoutingProvider, decode_polyline6
from app.schemas import RouteRequest


def encode(points):
    result, previous = '', [0, 0]
    for point in points:
        for axis, coordinate in enumerate(point):
            integer = round(coordinate * 1_000_000)
            delta = integer - previous[axis]
            previous[axis] = integer
            value = ~(delta << 1) if delta < 0 else delta << 1
            while value >= 32:
                result += chr((value & 31 | 32) + 63)
                value >>= 5
            result += chr(value + 63)
    return result


def native_response():
    summary = {'length': 1.2345, 'time': 220.4}
    return {'trip': {'status': 0, 'status_message': 'Found route between points',
        'units': 'kilometers', 'summary': summary,
        'legs': [{'summary': summary, 'shape': encode([(21.02, 105.85), (21.04, 105.82)]),
                  'maneuvers': [{'instruction': 'Drive north', 'begin_shape_index': 0,
                                'end_shape_index': 1, **summary}]}]}}


def request(**kwargs):
    return RouteRequest(origin={'lat':21.02,'lon':105.85}, destination={'lat':21.04,'lon':105.82}, **kwargs)


def test_polyline_known_precision6_vector():
    # Independent standard vector scaled to six decimals, including negative longitude.
    assert decode_polyline6('_izlhA~rlgdF_{geC~ywl@_kwzCn`{nI') == [
        {'lat':38.5,'lon':-120.2}, {'lat':40.7,'lon':-120.95}, {'lat':43.252,'lon':-126.453}]
    points = [(21.028501,105.854209),(21.018007,105.835003)]
    assert decode_polyline6(encode(points)) == [dict(zip(('lat','lon'),p)) for p in points]


@pytest.mark.parametrize('shape', ['', '?', '_', '\x00?', '~~~~~~~~~~~~~~?', None])
def test_bad_polyline(shape):
    with pytest.raises(ValueError): decode_polyline6(shape)


@pytest.mark.asyncio
async def test_native_alternates_multileg_units_and_instructions():
    data = native_response()
    second = copy.deepcopy(data['trip']['legs'][0])
    second['shape'] = encode([(21.04,105.82),(21.05,105.81)])
    data['trip']['legs'].append(second)
    alternate = copy.deepcopy(data['trip'])
    alternate['units'] = 'miles'
    alternate['summary'] = {'length':2,'time':500}
    data['alternates'] = [{'trip':alternate}]
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json=data))) as client:
        routes = await ValhallaRoutingProvider(client,'http://localhost:8002/route').calculate(request())
    assert len(routes)==2 and routes[1].distance_m==3219
    assert len(routes[0].geometry)==3
    assert routes[0].instructions[1]['begin_shape_index']==1
    assert routes[0].instructions[1]['end_shape_index']==2
    assert routes[0].traffic_delay_s is None and not routes[0].traffic_aware


@pytest.mark.asyncio
async def test_native_departure_and_endpoint():
    def handler(req):
        assert str(req.url)=='https://example.test/route'
        sent=json.loads(req.content)
        assert sent['alternates']==0 and sent['date_time']['type']==1
        assert sent['costing_options']['auto']['use_highways']==0
        return httpx.Response(200,json=native_response())
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await ValhallaRoutingProvider(client,'https://example.test/route').calculate(request(
            departure=datetime.now(timezone.utc)+timedelta(hours=1),avoid_highways=True))


@pytest.mark.asyncio
@pytest.mark.parametrize('status',[401,403,429,500])
async def test_http_error_no_retry(status):
    calls=[]
    def handler(req):
        calls.append(req)
        return httpx.Response(status,headers={'Retry-After':'120'})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(HTTPException) as error:
            await ValhallaRoutingProvider(client,'https://example.test').calculate(request())
    assert len(calls)==1
    assert error.value.status_code==(429 if status==429 else 502)
    if status==429: assert error.value.headers['Retry-After']=='120'


@pytest.mark.asyncio
@pytest.mark.parametrize('data',[{}, {'trip':{'status':1}}, {'trip':None},
    {'error_code':442,'error':'No path could be found for input'},
    {'trip':{'status':0,'units':'kilometers','summary':{'length':float('inf'),'time':1},'legs':[]}}])
async def test_invalid_native_response(data):
    # json.dumps permits Infinity for testing malformed upstream values.
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,content=json.dumps(data)))) as client:
        with pytest.raises(HTTPException) as error:
            await ValhallaRoutingProvider(client,'http://localhost').calculate(request())
    assert error.value.status_code==502


def test_environment_alias(monkeypatch):
    monkeypatch.setenv('VALHALLA_URL','https://preferred.test/route')
    monkeypatch.setenv('VALHALLA_BASE_URL','https://legacy.test')
    assert Settings(_env_file=None).valhalla_base_url=='https://preferred.test/route'
    monkeypatch.delenv('VALHALLA_URL')
    assert Settings(_env_file=None).valhalla_base_url=='https://legacy.test'


@pytest.mark.asyncio
async def test_experimental_motorcycle_uses_scooter_and_preserves_vehicle():
    def respond(request):
        sent = json.loads(request.content)
        assert sent['costing'] == 'motor_scooter'
        assert 'auto' not in sent['costing_options']
        return httpx.Response(200, json=native_response())
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        request = RouteRequest(origin={'lat': 21.02, 'lon': 105.85},
                               destination={'lat': 21.04, 'lon': 105.82}, vehicle='motorcycle')
        result = await ValhallaRoutingProvider(client, 'https://example.test').calculate(request)
    assert result[0].vehicle == 'motorcycle'
    assert result[0].traffic_aware is False
    assert result[0].traffic_delay_s is None

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from collections import defaultdict, deque
import hmac
import time
import logging
import math
import json
from pathlib import Path
from threading import Lock
import httpx
import jwt
from fastapi import FastAPI, Depends, HTTPException, Header, Query, Response, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy import create_engine, select, delete
from sqlalchemy.orm import Session
from app.config import settings
from app.database import User, SavedPlaceRow, SettingsRow
from app.schemas import RouteRequest, SavedPlace, UserSettings
from app.providers.routing import TomTomRoutingProvider, ValhallaRoutingProvider
from app.providers.valhalla import FallbackRoutingProvider
from app.tile_requests import TileRequests
from app.metrics import metrics, request_upstream

logging.getLogger('httpx').setLevel(logging.WARNING)
engine = create_engine(settings.database_url, pool_pre_ping=True)
windows = defaultdict(deque)
daily = {'date': '', 'count': 0}
limit_lock = Lock()
logger = logging.getLogger('trafficgo')


@asynccontextmanager
async def lifespan(app):
    if settings.provider_budget_file:
        path = Path(settings.provider_budget_file)
        if path.exists():
            try:
                stored = json.loads(path.read_text(encoding='utf-8'))
                if stored.get('date') == datetime.now(timezone.utc).date().isoformat():
                    daily.update(date=stored['date'], count=max(0, int(stored['count'])))
            except (ValueError, KeyError, OSError):
                # Do not silently reset a damaged cost-control counter.
                daily.update(date=datetime.now(timezone.utc).date().isoformat(), count=settings.daily_provider_budget)
    async with httpx.AsyncClient(timeout=httpx.Timeout(12), follow_redirects=False) as client:
        app.state.provider = TomTomRoutingProvider(client, settings.tomtom_api_key,
                                                   before_attempt=lambda: reserve_attempts(1))
        app.state.routing = FallbackRoutingProvider(ValhallaRoutingProvider(client, settings.valhalla_base_url),
            app.state.provider if settings.routing_fallback_to_tomtom else None)
        app.state.tile_requests = TileRequests()
        yield


app = FastAPI(title='TrafficGo API', version='0.1.0', lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                   allow_methods=['GET', 'POST', 'PATCH', 'DELETE'],
                   expose_headers=['Retry-After', 'X-RateLimit-Bucket', 'Server-Timing', 'X-Tile-Coalesced'],
                   allow_headers=['Authorization', 'X-App-Token', 'Content-Type'])


@app.middleware('http')
async def limit_body(request: Request, call_next):
    try:
        length = int(request.headers.get('content-length', '0'))
    except ValueError:
        return Response(status_code=400)
    if length < 0:
        return Response(status_code=400)
    if length > 32768:
        return Response(status_code=413)
    start = time.perf_counter()
    upstream = []
    token = request_upstream.set(upstream)
    try:
        response = await call_next(request)
    finally:
        request_upstream.reset(token)
    duration = (time.perf_counter()-start)*1000
    response.headers['Server-Timing'] = f'backend_total;dur={duration:.3f}, upstream;dur={sum(upstream):.3f}'
    response.headers['Cache-Control'] = 'no-store'
    route = request.scope.get('route')
    path = getattr(route, 'path', 'unmatched')
    category = ('traffic_tile' if '/tiles/' in path and request.path_params.get('kind') == 'traffic' else
                'map_tile' if '/tiles/' in path else 'routing' if '/routes/' in path else
                'search' if '/places/search' in path else 'other')
    if path != '/api/v1/diagnostics':
        metrics.record('backend.'+category, duration, response.status_code)
    logger.info('request method=%s route=%s status=%s', request.method,
                getattr(route, 'path', 'unmatched'), response.status_code)
    return response


@app.exception_handler(SQLAlchemyError)
async def database_error(request: Request, exc: SQLAlchemyError):
    logger.error('database_unavailable')
    return JSONResponse(status_code=503, content={'detail': 'Dịch vụ đồng bộ dữ liệu không khả dụng'}, headers={'Cache-Control': 'no-store'})


def access(request: Request, x_app_token: str = Header(default='')):
    if not settings.app_access_token:
        raise HTTPException(503, 'Backend chưa cấu hình access token')
    if not hmac.compare_digest(x_app_token, settings.app_access_token):
        raise HTTPException(401, 'Access token không hợp lệ')
    now = time.monotonic()
    # One-worker MVP; never trust forwarded IP headers.
    host = request.client.host if request.client else 'unknown'
    is_tile = request.url.path.startswith('/api/v1/tiles/')
    bucket = 'tiles' if is_tile else 'api'
    key = (host, bucket)
    limit = settings.tile_requests_per_minute if is_tile else settings.api_requests_per_minute
    with limit_lock:
        if len(windows) > 10000:
            for stale in [k for k, q in windows.items() if not q or q[-1] < now - 60]:
                windows.pop(stale, None)
            if len(windows) > 10000:
                raise HTTPException(429, 'Dịch vụ đang bận')
        queue = windows[key]
        while queue and queue[0] < now - 60:
            queue.popleft()
        if len(queue) >= limit:
            retry_after = max(1, math.ceil(60 - (now - queue[0])))
            message = ('Đang tải quá nhiều tile bản đồ. Vui lòng chờ một lát.' if is_tile else
                       'Thao tác quá nhanh. Vui lòng thử lại sau ít giây.')
            raise HTTPException(429, message, headers={'Retry-After': str(retry_after),
                                                      'X-RateLimit-Bucket': bucket})
        queue.append(now)


def provider(request: Request, _: None = Depends(access)):
    reserve_attempts(0)
    return request.app.state.provider


def reserve_attempts(count: int):
    day = datetime.now(timezone.utc).date().isoformat()
    with limit_lock:
        if daily['date'] != day:
            daily.update(date=day, count=0)
        if daily['count'] + count > settings.daily_provider_budget or (count == 0 and daily['count'] >= settings.daily_provider_budget):
            now = datetime.now(timezone.utc)
            retry = 86400 - (now.hour * 3600 + now.minute * 60 + now.second)
            raise HTTPException(429, 'Đã đạt giới hạn request/ngày của TrafficGo. Bản đồ và traffic tạm dừng để bảo vệ quota.',
                                headers={'Retry-After': str(retry), 'X-RateLimit-Bucket': 'daily-budget'})
        daily['count'] += count
        if count and settings.provider_budget_file:
            path = Path(settings.provider_budget_file)
            temporary = path.with_suffix(path.suffix + '.tmp')
            try:
                temporary.write_text(json.dumps(daily), encoding='utf-8')
                temporary.replace(path)
            except OSError:
                raise HTTPException(503, 'Không lưu được bộ đếm quota. Tạm dừng gọi provider để bảo vệ chi phí.') from None


def user(authorization: str = Header(default=''), _: None = Depends(access)):
    if not settings.jwt_secret:
        raise HTTPException(503, 'Đồng bộ tài khoản chưa được cấu hình')
    if not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Cần Bearer token')
    try:
        claims = jwt.decode(authorization.removeprefix('Bearer '), settings.jwt_secret,
                            algorithms=['HS256'], issuer=settings.jwt_issuer,
                            audience=settings.jwt_audience, options={'require': ['exp', 'sub', 'iss', 'aud']})
        subject = claims['sub']
        if not isinstance(subject, str) or not 1 <= len(subject) <= 128:
            raise HTTPException(401, 'Thông tin tài khoản không hợp lệ')
        return subject
    except jwt.PyJWTError:
        raise HTTPException(401, 'Phiên đăng nhập không hợp lệ') from None


def db():
    with Session(engine) as session:
        yield session


@app.get('/health')
def health():
    return {'status': 'ok', 'provider_configured': bool(settings.tomtom_api_key)}


@app.get('/api/v1/traffic/status', dependencies=[Depends(access)])
def traffic_status():
    return {'configured': bool(settings.tomtom_api_key), 'provider': 'tomtom',
            'status': 'unverified' if settings.tomtom_api_key else 'unconfigured',
            'provider_updated_at': None, 'motorcycle_supported': False,
            'message': 'Thời điểm tải tile không phải thời điểm đo giao thông'}


@app.get('/api/v1/diagnostics', dependencies=[Depends(access)])
def diagnostics():
    return {'metrics': metrics.snapshot(), 'budget': {'date':daily['date'], 'used':daily['count'],
        'limit':settings.daily_provider_budget}, 'storage':'bounded process memory; latency sample window 2000/category'}


@app.get('/api/v1/attribution')
async def attribution(p=Depends(provider)):
    try:
        caption = (await p.get('map/1/copyrights/caption.json', {})).json()
        notices = (await p.get('map/1/copyrights.json', {})).json()
        return {'caption': caption.get('copyrightsCaption', '© TomTom'), 'notices': notices}
    except ValueError:
        raise HTTPException(502, 'Không tải được thông tin bản quyền') from None


@app.get('/api/v1/tiles/{kind}/{z}/{x}/{y}.png')
async def tiles(kind: str, z: int, x: int, y: int, request: Request, p=Depends(provider)):
    if kind not in ('map', 'traffic') or not 0 <= z <= 18 or not 0 <= x < 2**z or not 0 <= y < 2**z:
        raise HTTPException(422, 'Tile không hợp lệ')
    path = (f'map/1/tile/basic/main/{z}/{x}/{y}.png' if kind == 'map' else
            f'traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png')
    result, joined = await request.app.state.tile_requests.get((kind,z,x,y), lambda: p.get(path, {'tileSize':256}))
    if 'image/png' not in result.headers.get('content-type', ''):
        raise HTTPException(502, 'Tile không hợp lệ')
    return Response(result.content, media_type='image/png', headers={
        'Cache-Control': 'no-store', 'X-Tile-Coalesced':str(joined).lower(),
        'X-Retrieved-At': datetime.now(timezone.utc).isoformat()})


@app.get('/api/v1/places/search')
async def search(q: str = Query(min_length=2, max_length=120),
                 lat: float = Query(21.0285, ge=20.5, le=21.6),
                 lon: float = Query(105.8542, ge=105.2, le=106.3), p=Depends(provider)):
    from urllib.parse import quote
    response = await p.get(f'search/2/search/{quote(q, safe="")}.json',
                           {'countrySet': 'VN', 'lat': lat, 'lon': lon, 'radius': 40000,
                            'limit': 8, 'language': 'vi-VN', 'typeahead': 'true'})
    try:
        return {'places': [{'id': item['id'], 'name': item.get('poi', {}).get('name', item['address'].get('freeformAddress', '')),
                'address': item['address'].get('freeformAddress', ''),
                'coordinate': {'lat': item['position']['lat'], 'lon': item['position']['lon']}}
                for item in response.json().get('results', [])
                if 20.5 <= item['position']['lat'] <= 21.6 and 105.2 <= item['position']['lon'] <= 106.3]}
    except (KeyError, ValueError, TypeError):
        raise HTTPException(502, 'Kết quả tìm kiếm không hợp lệ') from None


@app.post('/api/v1/routes/calculate')
@app.post('/api/v1/routes/refresh')
async def routes(body: RouteRequest, request: Request, _: None=Depends(access)):
    if body.vehicle != 'car':
        raise HTTPException(422, 'Xe máy chưa được xác minh tại Việt Nam')
    if settings.routing_provider == 'tomtom':
        reserve_attempts(0)
        selected = request.app.state.provider
    else:
        selected = request.app.state.routing
    return {'routes': await selected.calculate(body)}


@app.get('/api/v1/saved-places')
def saved_places(uid=Depends(user), session=Depends(db)):
    return [{'id': row.id, **row.data} for row in session.scalars(select(SavedPlaceRow).where(SavedPlaceRow.user_id == uid))]


@app.post('/api/v1/saved-places', status_code=201)
def save_place(body: SavedPlace, uid=Depends(user), session=Depends(db)):
    if not session.get(User, uid):
        session.add(User(id=uid))
        session.flush()
    row = SavedPlaceRow(user_id=uid, data=body.model_dump())
    session.add(row)
    session.commit()
    return {'id': row.id, **row.data}


@app.delete('/api/v1/saved-places/{place_id}', status_code=204)
def remove_place(place_id: str, uid=Depends(user), session=Depends(db)):
    row = session.scalar(select(SavedPlaceRow).where(SavedPlaceRow.id == place_id, SavedPlaceRow.user_id == uid))
    if row is None:
        raise HTTPException(404, 'Không tìm thấy địa điểm')
    session.delete(row)
    session.commit()


@app.get('/api/v1/settings')
def get_settings(uid=Depends(user), session=Depends(db)):
    row = session.get(SettingsRow, uid)
    return row.data if row else UserSettings().model_dump()


@app.patch('/api/v1/settings')
def patch_settings(body: UserSettings, uid=Depends(user), session=Depends(db)):
    if not session.get(User, uid):
        session.add(User(id=uid))
        session.flush()
    row = session.get(SettingsRow, uid)
    data = {**(row.data if row else UserSettings().model_dump()), **body.model_dump(exclude_unset=True)}
    if row:
        row.data = data
    else:
        session.add(SettingsRow(user_id=uid, data=data))
    session.commit()
    return data


@app.delete('/api/v1/me', status_code=204)
def erase_user(uid=Depends(user), session=Depends(db)):
    session.execute(delete(User).where(User.id == uid))
    session.commit()

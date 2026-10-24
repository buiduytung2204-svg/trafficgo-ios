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
from fastapi.exceptions import RequestValidationError
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy import create_engine, select, delete
from sqlalchemy.orm import Session
from app.config import settings
from app.database import User, SavedPlaceRow, SettingsRow, database_engine
from app.schemas import RouteRequest, SavedPlace, UserSettings
from app.providers.factory import create_routing_provider
from app.providers.traffic import UnavailableTrafficProvider
from app.providers.search import GeoapifySearchProvider, SearchBudget
from app.providers.geo_tiles import GeoapifyTiles
from app.tile_requests import TileRequests
from app.route_requests import RouteRequests
from app.metrics import metrics, request_upstream
from app.departure.api import create_router as departure_router
from app.accounts.api import create_router as account_router

logging.getLogger('httpx').setLevel(logging.WARNING)
engine = database_engine(settings.database_url)
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
        app.state.routing = RouteRequests(create_routing_provider(client, settings), settings.interactive_routing_budget_file, settings.interactive_daily_routing_limit)
        app.state.traffic = UnavailableTrafficProvider()
        app.state.tile_requests = TileRequests()
        app.state.search = GeoapifySearchProvider(client, settings.geoapify_api_key,
            SearchBudget(settings.geoapify_budget_file, settings.geoapify_daily_budget, settings.geoapify_daily_credits))
        app.state.geo_tiles = GeoapifyTiles(client,settings.geoapify_api_key,app.state.search.budget)
        try:
            yield
        finally:
            if hasattr(app.state.routing, 'close'):
                await app.state.routing.close()


app = FastAPI(title='TrafficGo API', version='0.1.0', lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                   allow_methods=['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
                   expose_headers=['Retry-After', 'X-RateLimit-Bucket', 'Server-Timing', 'X-Tile-Coalesced'],
                   allow_headers=['Authorization', 'X-App-Token', 'X-Schedule-Token', 'Content-Type'])


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


@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    # Never echo submitted passwords/tokens (including nested request bodies).
    return JSONResponse(status_code=422, content={'detail': [
        {'loc': list(e['loc']), 'type': e['type'], 'msg': e['msg']}
        for e in exc.errors()]})


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
    is_tile = request.url.path.startswith(('/api/v1/tiles/', '/api/v1/geo/tiles/'))
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


def provider():
    raise HTTPException(410, 'TomTom đã ngừng hỗ trợ')


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


app.include_router(departure_router(access, db))
app.include_router(account_router(access, db))


@app.get('/health')
def health():
    configured = bool(settings.valhalla_base_url) if settings.routing_provider == 'valhalla' else bool(settings.tomtom_api_key and settings.tomtom_routing_license_confirmed)
    return {'status': 'ok', 'provider_configured': configured, 'routing_provider': settings.routing_provider}


@app.get('/api/v1/traffic/status', dependencies=[Depends(access)])
def traffic_status():
    return UnavailableTrafficProvider().status()


@app.get('/api/v1/diagnostics', dependencies=[Depends(access)])
def diagnostics(request: Request):
    geo = request.app.state.search
    return {'metrics': metrics.snapshot(), 'geoapify':{**geo.budget.snapshot(),
        'cache_hits':geo.cache_hits, 'coalesced':geo.coalesced, 'tile_cache_hits':request.app.state.geo_tiles.hits}, 'budget': {'date':daily['date'], 'used':daily['count'],
        'limit':settings.daily_provider_budget}, 'storage':'bounded process memory; latency sample window 2000/category'}


@app.get('/api/v1/attribution')
async def attribution():
    return {'caption': '© Geoapify • © OpenStreetMap contributors', 'notices': 'Open Database License; Powered by Geoapify'}


@app.get('/api/v1/geo/tiles/{z}/{x}/{y}.png',dependencies=[Depends(access)])
async def geo_tile(z:int,x:int,y:int,request:Request):
    data,hit=await request.app.state.geo_tiles.tile(z,x,y)
    return Response(data,media_type='image/png',headers={'X-Tile-Coalesced':str(hit).lower()})


@app.get('/api/v1/tiles/{kind}/{z}/{x}/{y}.png')
async def tiles(kind: str, z: int, x: int, y: int, _: None=Depends(access)):
    raise HTTPException(410, 'TomTom đã ngừng hỗ trợ. Dùng /api/v1/geo/tiles cho bản đồ nền.')


@app.get('/api/v1/places/search')
async def search(request: Request, q: str = Query(min_length=2, max_length=120),
                 lat: float = Query(21.0285, ge=20.5, le=21.6),
                 lon: float = Query(105.8542, ge=105.2, le=106.3), _: None=Depends(access)):
    return {'places':await request.app.state.search.search(q,lat,lon),
            'provider':'geoapify', 'attribution':'Powered by Geoapify | ? OpenStreetMap contributors'}


@app.post('/api/v1/routes/calculate')
@app.post('/api/v1/routes/refresh')
async def routes(body: RouteRequest, request: Request, _: None=Depends(access)):
    return {'routes': await request.app.state.routing.calculate(body)}


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

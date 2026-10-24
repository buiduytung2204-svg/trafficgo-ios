"""Windows-local username accounts, opaque per-install sessions, mandatory setup."""
from collections import defaultdict, deque
from datetime import datetime, timezone
import hashlib
import hmac
import secrets
import threading
import time
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from app.database import User
from app.departure.models import Installation, Schedule
from app.departure.api import digest
from app.departure.schemas import ScheduleInput
from app.departure.service import materialize
from app.schemas import Coordinate
from .models import Account

windows = defaultdict(deque)
lock = threading.Lock()


def hash_password(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    key = hashlib.scrypt(password.encode(), salt=salt, n=32768, r=8, p=3, maxmem=64*1024*1024)
    return 'scrypt$32768$8$3$' + salt.hex() + '$' + key.hex()


def verify(password, stored):
    try:
        salt = bytes.fromhex(stored.split('$')[4])
        return hmac.compare_digest(hash_password(password, salt), stored)
    except (ValueError, IndexError):
        return False


DUMMY_HASH = hash_password('dummy-account-password')


class Credentials(BaseModel):
    username: str = Field(pattern=r'^[a-zA-Z0-9_.-]{3,40}$')
    password: str = Field(min_length=10, max_length=128, repr=False)


class PlaceInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=100)
    coordinate: Coordinate


class SetupInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    display_name: str = Field(min_length=1, max_length=100)
    purpose: str = Field(pattern=r'^(school|work|personal)$')
    vehicle: str = Field(pattern=r'^(car|motorcycle)$')
    vehicle_id: str | None = Field(default=None, max_length=100)
    home: PlaceInput
    destination: PlaceInput
    journey_id: str = Field(min_length=1, max_length=100)
    schedule: ScheduleInput

    @model_validator(mode='after')
    def consistency(self):
        if self.schedule.direction != "outbound" or self.schedule.initial_eta_s is None:
            raise ValueError("Setup requires an outbound route with reference ETA")
        if (self.schedule.journey_id != self.journey_id or self.schedule.vehicle != self.vehicle
                or self.schedule.origin != self.home.coordinate
                or self.schedule.destination != self.destination.coordinate):
            raise ValueError('Setup schedule must match selected journey and places')
        if self.vehicle == 'motorcycle' and not self.vehicle_id:
            raise ValueError('Motorcycle setup requires selected vehicle')
        return self


def create_router(access, db):
    router = APIRouter(prefix='/api/v1/accounts', tags=['Accounts'], dependencies=[Depends(access)])

    def transaction_db(request: Request, session=Depends(db)):
        if request.method != "GET" and session.bind.dialect.name == "sqlite":
            session.execute(text("BEGIN IMMEDIATE"))
        yield session

    def throttle(request: Request):
        key = request.client.host if request.client else 'unknown'
        now = time.monotonic()
        with lock:
            for stale in [k for k, q in windows.items() if not q or q[-1] < now-60]:
                del windows[stale]
            if key not in windows and len(windows) >= 2048:
                raise HTTPException(429, 'Thử lại sau', headers={'Retry-After':'60'})
            queue = windows[key]
            while queue and queue[0] < now-60:
                queue.popleft()
            if len(queue) >= 10:
                raise HTTPException(429, 'Quá nhiều lần đăng nhập; chờ một phút', headers={'Retry-After':'60'})
            queue.append(now)

    def current(x_schedule_token: str = Header(default=''), session=Depends(transaction_db)):
        install = session.get(Installation, digest(x_schedule_token)) if x_schedule_token else None
        account = session.get(Account, install.user_id) if install else None
        if not account:
            raise HTTPException(401, 'Cần đăng nhập tài khoản')
        return account

    def info(account):
        return {'user_id':account.user_id, 'username':account.username, 'profile':account.profile}

    def issue(session, account):
        token = secrets.token_urlsafe(32)
        session.add(Installation(token_hash=digest(token), user_id=account.user_id))
        session.commit()
        return {**info(account), 'token':token}

    @router.post('/register', status_code=201, dependencies=[Depends(throttle)])
    def register(body: Credentials, session=Depends(transaction_db)):
        username = body.username.lower()
        password_hash = hash_password(body.password)
        account = Account(user_id='account-'+secrets.token_hex(16), username=username,
                          password_hash=password_hash, profile={'setup_complete':False})
        try:
            session.add(User(id=account.user_id));session.flush();session.add(account);session.flush()
            return issue(session, account)
        except IntegrityError:
            session.rollback()
            raise HTTPException(409, 'Tên đăng nhập đã được sử dụng') from None

    @router.post('/login', dependencies=[Depends(throttle)])
    def login(body: Credentials, session=Depends(transaction_db)):
        account = session.scalar(select(Account).where(Account.username == body.username.lower()))
        # Same expensive computation even when username doesn't exist.
        valid = verify(body.password, account.password_hash) if account else verify(body.password, DUMMY_HASH)
        if not account or not valid:
            raise HTTPException(401, 'Tên đăng nhập hoặc mật khẩu không đúng')
        return issue(session, account)

    @router.get('/me')
    def me(account=Depends(current)):
        return info(account)

    @router.post('/setup')
    def setup(body: SetupInput, account=Depends(current), session=Depends(transaction_db)):
        account = session.scalar(select(Account).where(Account.user_id==account.user_id).with_for_update())
        profile = dict(account.profile)
        if profile.get("setup_complete"):
            return info(account)  # retry is idempotent; edit schedules through their normal API
        row = session.get(Schedule, profile.get('schedule_id')) if profile.get('schedule_id') else None
        if row and row.user_id != account.user_id:
            raise HTTPException(409, 'Lịch không thuộc tài khoản')
        if not row:
            row = Schedule(user_id=account.user_id, data=body.schedule.model_dump(mode='json'))
            session.add(row);session.flush()
        else:
            row.data = body.schedule.model_dump(mode='json');row.revision += 1
        materialize(session, row, datetime.now(timezone.utc))
        account.profile = {**body.model_dump(mode='json', exclude={'schedule'}),
                           'setup_complete':True, 'schedule_id':row.id}
        session.commit()
        return info(account)

    @router.post('/logout', status_code=204)
    def logout(account=Depends(current), x_schedule_token: str=Header(default=''), session=Depends(transaction_db)):
        install = session.get(Installation, digest(x_schedule_token))
        session.delete(install);session.commit()

    return router

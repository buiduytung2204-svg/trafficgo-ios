import hashlib
import secrets
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy import select, delete, text
from sqlalchemy.orm import Session
from app.database import User, SavedRouteRow
from .models import Schedule, Occurrence, NotificationEvent, Installation, DeviceToken, WorkerState
from .schemas import ScheduleInput, OccurrenceAction, DeviceInput
from .service import materialize
from .engine import candidate_arrivals


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def create_router(access, db):
    router = APIRouter(prefix='/api/v1/departure', tags=['Smart departure'], dependencies=[Depends(access)])

    def transaction_db(request: Request, session: Session = Depends(db)):
        if request.method != 'GET' and session.bind.dialect.name == 'sqlite':
            session.execute(text('BEGIN IMMEDIATE'))
        yield session

    def identity(x_schedule_token: str = Header(default=''), session: Session = Depends(transaction_db)):
        row = session.get(Installation, digest(x_schedule_token)) if x_schedule_token else None
        if not row:
            raise HTTPException(401, 'Cần kết nối lịch nhắc trên thiết bị này')
        return row.user_id

    def owned(session, model, row_id, owner):
        row = session.scalar(select(model).where(model.id == row_id).with_for_update())
        if not row or row.user_id != owner:
            raise HTTPException(404, 'Không tìm thấy dữ liệu')
        return row

    def serialize_occurrence(row):
        return {'id': row.id, 'arrival_date': row.arrival_date, 'status': row.status, **row.data}

    def serialize_schedule(session, row):
        occurrences = list(session.scalars(select(Occurrence).where(
            Occurrence.schedule_id == row.id).order_by(Occurrence.arrival_date)))
        now = datetime.now(timezone.utc)
        upcoming = [o for o in occurrences if o.status == 'planned' and
                    datetime.fromisoformat(o.data['arrival_at']) > now]
        current = upcoming[0] if upcoming else (occurrences[-1] if occurrences else None)
        return {'id': row.id, 'revision': row.revision, **row.data,
                'occurrence': serialize_occurrence(current) if current else None}

    @router.post('/session', status_code=201)
    def register(session: Session = Depends(transaction_db)):
        # Separate per-install credential; shared map access token is NOT ownership.
        token = secrets.token_urlsafe(32)
        user = User(id='guest-' + secrets.token_hex(16))
        session.add(user)
        session.flush()
        session.add(Installation(token_hash=digest(token), user_id=user.id))
        session.commit()
        return {'token': token, 'user_id': user.id}

    @router.get('/overview')
    def overview(owner=Depends(identity), session: Session = Depends(transaction_db)):
        state = session.get(WorkerState, 'scheduler')
        worker = state.data if state else {}
        schedules = list(session.scalars(select(Schedule).where(Schedule.user_id == owner)))
        events = list(session.scalars(select(NotificationEvent).where(
            NotificationEvent.user_id == owner).order_by(NotificationEvent.created_at.desc()).limit(100)))
        return {'synced_at': datetime.now(timezone.utc).isoformat(),
                'timezone': 'Asia/Ho_Chi_Minh', 'push_configured': False,
                'worker': {'last_tick_at': worker.get('last_tick_at'),
                           'lease_until': state.lease_until if state else 0,
                           'live_routing_enabled': worker.get('live_routing_enabled', False),
                           'routing_attempts_today': worker.get('attempts', 0)},
                'schedules': [serialize_schedule(session, row) for row in schedules],
                'notifications': [{'id': e.id, 'occurrence_id': e.occurrence_id,
                    'kind': e.kind, 'created_at': e.created_at, 'read': e.read,
                    'delivery_status': e.delivery_status, **e.data} for e in events]}

    def validate_route(session, body, owner):
        if body.saved_route_id:
            owned(session, SavedRouteRow, body.saved_route_id, owner)

    @router.post('/schedules', status_code=201)
    def create(body: ScheduleInput, owner=Depends(identity), session: Session = Depends(transaction_db)):
        if len(list(session.scalars(select(Schedule.id).where(Schedule.user_id == owner)))) >= 50:
            raise HTTPException(422, 'Tối đa 50 lịch trên mỗi thiết bị')
        validate_route(session, body, owner)
        row = Schedule(user_id=owner, data=body.model_dump(mode='json'))
        session.add(row)
        session.flush()
        materialize(session, row, datetime.now(timezone.utc))
        session.commit()
        return serialize_schedule(session, row)

    @router.put('/schedules/{schedule_id}')
    def edit(schedule_id: str, body: ScheduleInput, owner=Depends(identity), session: Session = Depends(transaction_db)):
        row = owned(session, Schedule, schedule_id, owner)
        validate_route(session, body, owner)
        row.data = body.model_dump(mode='json')
        row.revision += 1
        # Cancel occurrences no longer in the recurrence. Never touch terminal trips.
        valid_dates = {d.date().isoformat() for d in candidate_arrivals(row.data, datetime.now(timezone.utc))}
        for item in session.scalars(select(Occurrence).where(Occurrence.schedule_id == row.id,
                                                            Occurrence.status == 'planned')):
            if item.arrival_date not in valid_dates:
                item.status = 'cancelled'
        materialize(session, row, datetime.now(timezone.utc))
        session.commit()
        return serialize_schedule(session, row)

    @router.delete('/schedules/{schedule_id}', status_code=204)
    def remove(schedule_id: str, owner=Depends(identity), session: Session = Depends(transaction_db)):
        row = owned(session, Schedule, schedule_id, owner)
        occurrence_ids = select(Occurrence.id).where(Occurrence.schedule_id == row.id)
        session.execute(delete(NotificationEvent).where(NotificationEvent.occurrence_id.in_(occurrence_ids)))
        session.execute(delete(Occurrence).where(Occurrence.schedule_id == row.id))
        session.delete(row)
        session.commit()

    @router.get('/schedules/{schedule_id}/occurrences')
    def occurrences(schedule_id: str, owner=Depends(identity), session: Session = Depends(transaction_db)):
        owned(session, Schedule, schedule_id, owner)
        return [serialize_occurrence(o) for o in session.scalars(select(Occurrence).where(
            Occurrence.schedule_id == schedule_id).order_by(Occurrence.arrival_date.desc()).limit(30))]

    @router.patch('/occurrences/{occurrence_id}')
    def act(occurrence_id: str, body: OccurrenceAction, owner=Depends(identity), session: Session = Depends(transaction_db)):
        occurrence = session.get(Occurrence, occurrence_id)
        if not occurrence:
            raise HTTPException(404, 'Không tìm thấy chuyến')
        owned(session, Schedule, occurrence.schedule_id, owner)
        session.refresh(occurrence, with_for_update=True)
        if occurrence.status != 'planned' and occurrence.status != body.status:
            raise HTTPException(409, 'Chuyến đã kết thúc, không thể thay đổi')
        occurrence.status = body.status
        session.commit()
        return serialize_occurrence(occurrence)

    @router.patch('/notifications/{event_id}/read')
    def read(event_id: str, owner=Depends(identity), session: Session = Depends(transaction_db)):
        row = owned(session, NotificationEvent, event_id, owner)
        row.read = True
        session.commit()
        return {'read': True}

    @router.post('/devices', status_code=201)
    def device(body: DeviceInput, owner=Depends(identity), session: Session = Depends(transaction_db)):
        row = session.scalar(select(DeviceToken).where(DeviceToken.token_hash == digest(body.token)))
        if row and row.user_id != owner:
            raise HTTPException(409, 'Token đã thuộc thiết bị khác')
        if not row:
            row = DeviceToken(user_id=owner, token_hash=digest(body.token))
            session.add(row)
        row.data, row.active = body.model_dump(), True
        session.commit()
        return {'id': row.id, 'active': row.active, 'push_configured': False}

    @router.delete('/devices/{device_id}', status_code=204)
    def remove_device(device_id: str, owner=Depends(identity), session: Session = Depends(transaction_db)):
        row = owned(session, DeviceToken, device_id, owner)
        session.delete(row)
        session.commit()

    @router.delete('/personal-data', status_code=204)
    def erase(owner=Depends(identity), session: Session = Depends(transaction_db)):
        for model in (NotificationEvent, DeviceToken):
            session.execute(delete(model).where(model.user_id == owner))
        ids = select(Schedule.id).where(Schedule.user_id == owner)
        session.execute(delete(Occurrence).where(Occurrence.schedule_id.in_(ids)))
        session.execute(delete(Schedule).where(Schedule.user_id == owner))
        session.execute(delete(Installation).where(Installation.user_id == owner))
        # Preserve any unrelated existing places/settings belonging to this user.
        session.commit()

    return router

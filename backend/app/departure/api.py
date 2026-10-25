import hashlib
import secrets
from datetime import datetime, timezone, date, timedelta, time
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy import select, delete, text
from sqlalchemy.orm import Session
from app.database import User, SavedRouteRow
from .models import Schedule, Occurrence, NotificationEvent, Installation, DeviceToken, WorkerState
from .schemas import ScheduleInput, OccurrenceAction, DeviceInput, DayException, NotificationAction
from .service import materialize, snapshot, recalculate
from .notifications import NotificationService
from .engine import candidate_arrivals, local, ZONE


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
                'day_exceptions': [serialize_occurrence(o) for o in occurrences
                    if o.status == 'skipped' or o.data.get('day_override')][-14:],
                'occurrence': serialize_occurrence(current) if current else None,
                'upcoming_occurrences': [serialize_occurrence(o) for o in upcoming[:32]]}

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

    @router.post('/occurrences/{occurrence_id}/reminder-event')
    def local_reminder_event(occurrence_id: str, kind: str, owner=Depends(identity), session: Session = Depends(transaction_db)):
        moments = {'preparation_soon': ('prepare_at', -5), 'preparation_due': ('prepare_at', 0),
                   'departure_soon': ('departure_at', -5), 'departure_due': ('departure_at', 0)}
        if kind not in moments:
            raise HTTPException(422, 'Loại nhắc không hợp lệ')
        occurrence = session.get(Occurrence, occurrence_id)
        if not occurrence:
            raise HTTPException(404, 'Không tìm thấy chuyến')
        schedule = owned(session, Schedule, occurrence.schedule_id, owner)
        if not schedule.data['enabled'] or occurrence.status != 'planned':
            raise HTTPException(409, 'Lịch nhắc đã thay đổi hoặc chuyến đã kết thúc')
        now = datetime.now(timezone.utc)
        field, delta = moments[kind]
        instant = occurrence.data.get(field)
        if not instant or now < datetime.fromisoformat(instant) + timedelta(minutes=delta, seconds=-30):
            raise HTTPException(409, 'Giờ nhắc đã thay đổi. Mở lịch để xem giờ mới nhất')
        if now >= datetime.fromisoformat(occurrence.data['arrival_at']):
            raise HTTPException(409, 'Chuyến này đã qua giờ cần đến')
        event = NotificationService().emit(session, schedule, occurrence, kind, now)
        session.commit()
        return {'event_id': event.id}

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
        for item in session.scalars(select(Occurrence).where(Occurrence.schedule_id == row.id,
                                                            Occurrence.status == 'planned')):
            # A saved exception may be farther away than the worker's 7-day window.
            matches = (item.arrival_date == row.data['one_off_date'] if row.data.get('one_off_date')
                       else date.fromisoformat(item.arrival_date).weekday() in row.data['weekdays'])
            if not matches:
                item.status = 'cancelled'
            # Old notification payloads must not start an edited route or old time.
            cancel_reminders(session, item)
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
        if occurrence.status not in ('planned', 'in_progress') and occurrence.status != body.status:
            raise HTTPException(409, 'Chuyến đã kết thúc, không thể thay đổi')
        occurrence.status = body.status
        cancel_reminders(session, occurrence)
        session.commit()
        return serialize_occurrence(occurrence)

    def cancel_reminders(session, occurrence):
        data = dict(occurrence.data)
        data.pop('snooze_until', None)
        data.pop('snooze_source', None)
        occurrence.data = data
        for event in session.scalars(select(NotificationEvent).where(
                NotificationEvent.occurrence_id == occurrence.id)):
            event.data = {**event.data, 'cancelled': True}

    @router.put('/schedules/{schedule_id}/exceptions/{day}')
    def day_exception(schedule_id: str, day: date, body: DayException,
                      owner=Depends(identity), session: Session = Depends(transaction_db)):
        schedule = owned(session, Schedule, schedule_id, owner)
        now = local(datetime.now(timezone.utc))
        if day < now.date() or day > now.date() + timedelta(days=366):
            raise HTTPException(422, 'Chọn ngày từ hôm nay đến một năm tới')
        if (schedule.data.get('one_off_date') and schedule.data['one_off_date'] != day.isoformat()) or (
                not schedule.data.get('one_off_date') and day.weekday() not in schedule.data['weekdays']):
            raise HTTPException(422, 'Ngày này không thuộc lịch lặp')
        occurrence = session.scalar(select(Occurrence).where(Occurrence.schedule_id == schedule.id,
            Occurrence.arrival_date == day.isoformat()).with_for_update())
        if occurrence and occurrence.status != 'planned':
            if body.action == 'skip' and occurrence.status == 'skipped':
                return serialize_occurrence(occurrence)
            if not (body.action == 'reset' and occurrence.status == 'skipped'):
                raise HTTPException(409, 'Chuyến đã bắt đầu hoặc kết thúc')
        arrival = datetime.combine(day, time.fromisoformat(schedule.data['arrival_time']), ZONE)
        if not occurrence:
            occurrence = Occurrence(schedule_id=schedule.id, arrival_date=day.isoformat(),
                data=snapshot(schedule.data, arrival, schedule.revision))
            session.add(occurrence)
            session.flush()
        data = dict(occurrence.data)
        override = {} if body.action == 'reset' else {
            **data.get('day_override', {}), **body.model_dump(exclude={'action'}, exclude_none=True)}
        if (body.action != 'skip' and occurrence.status == 'planned'
                and override == data.get('day_override', {}) and not data.get('snooze_until')):
            session.commit()
            return serialize_occurrence(occurrence)
        arrival = datetime.combine(day, time.fromisoformat(override.get('arrival_time', schedule.data['arrival_time'])), ZONE)
        if body.action != 'skip' and arrival <= now:
            raise HTTPException(409, 'Giờ cần đến đã qua; chọn giờ khác')
        cancel_reminders(session, occurrence)
        data.update(day_override=override, arrival_at=arrival.isoformat(),
                    exception_revision=data.get('exception_revision', 0) + 1)
        data.pop('snooze_until', None)
        data.pop('snooze_source', None)
        recalculate(data, schedule.data)
        occurrence.data = data
        occurrence.status = 'skipped' if body.action == 'skip' else 'planned'
        session.commit()
        return serialize_occurrence(occurrence)

    def event_info(row):
        return {'id': row.id, 'occurrence_id': row.occurrence_id,
                'kind': row.kind, 'created_at': row.created_at, 'read': row.read, **row.data}

    @router.get('/notifications/{event_id}')
    def get_event(event_id: str, owner=Depends(identity), session: Session = Depends(transaction_db)):
        return event_info(owned(session, NotificationEvent, event_id, owner))

    @router.post('/notifications/{event_id}/action')
    def notification_action(event_id: str, body: NotificationAction,
                            owner=Depends(identity), session: Session = Depends(transaction_db)):
        event = session.get(NotificationEvent, event_id)
        if not event or event.user_id != owner:
            raise HTTPException(404, 'Không tìm thấy thông báo')
        occurrence = session.get(Occurrence, event.occurrence_id)
        schedule = owned(session, Schedule, occurrence.schedule_id, owner)
        session.refresh(occurrence, with_for_update=True)
        session.refresh(event, with_for_update=True)
        previous = event.data.get('action_result')
        if previous:
            expected = {'start': 'in_progress', 'skip': 'skipped', 'snooze': 'planned'}
            if previous != body.action or occurrence.status != expected[previous]:
                raise HTTPException(409, 'Thông báo này đã được xử lý')
            return event_info(event)
        now = local(datetime.now(timezone.utc))
        if datetime.fromisoformat(event.created_at) > now:
            raise HTTPException(409, 'Chưa đến giờ nhắc lại')
        if occurrence.status != 'planned' or event.data.get('cancelled') or not schedule.data['enabled']:
            raise HTTPException(409, 'Chuyến không còn chờ xuất phát')
        if datetime.fromisoformat(occurrence.data['arrival_at']) <= now:
            raise HTTPException(409, 'Thông báo đã hết hạn')
        if body.action == 'snooze':
            until = now + timedelta(minutes=5)
            if until >= datetime.fromisoformat(occurrence.data['arrival_at']):
                raise HTTPException(409, 'Không còn đủ thời gian nhắc lại sau 5 phút')
            occurrence.data = {**occurrence.data, 'snooze_until': until.isoformat(), 'snooze_source': event.id}
            reminder_kind = 'snooze_' + hashlib.sha256(event.id.encode()).hexdigest()[:16]
            reminder = NotificationService().emit(session, schedule, occurrence, reminder_kind, until)
            reminder.data = {**reminder.data, 'scheduled_for': until.isoformat()}
            event.data = {**event.data, 'reminder_event_id': reminder.id}
        else:
            occurrence.status = 'in_progress' if body.action == 'start' else 'skipped'
            cancel_reminders(session, occurrence)
        event.read = True
        event.data = {**event.data, 'action_result': body.action, 'action_at': now.isoformat()}
        session.commit()
        return event_info(event)

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

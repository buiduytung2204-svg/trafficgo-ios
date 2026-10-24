import asyncio
import hashlib
import json
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from sqlalchemy import select, update, or_, text
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from fastapi import HTTPException
from app.schemas import RouteRequest
from .models import Schedule, Occurrence, WorkerState
from .engine import local, moments, candidate_arrivals, interval_seconds, due_kinds, TERMINAL
from .notifications import NotificationService


@contextmanager
def write_session(engine):
    with Session(engine) as session:
        if engine.dialect.name == 'sqlite':
            session.execute(text('BEGIN IMMEDIATE'))
        yield session


def snapshot(data, arrival, revision):
    routing_signature = hashlib.sha256(json.dumps({k: data[k] for k in
        ('origin', 'destination', 'vehicle')}, sort_keys=True).encode()).hexdigest()
    result = {'arrival_at': arrival.isoformat(), 'revision': revision,
              'eta_s': data.get('initial_eta_s'), 'eta_updated_at': None,
              'eta_source': 'initial_estimate' if data.get('initial_eta_s') else None,
              'traffic_aware': False, 'attempts': 0, 'next_check_at': None, 'last_error': None,
              'routing_signature': routing_signature}
    recalculate(result, data)
    return result


def recalculate(result, config):
    if result.get('eta_s') is None:
        result.update(prepare_at=None, departure_at=None)
        return
    prepare, departure = moments(datetime.fromisoformat(result['arrival_at']), result['eta_s'],
                                  config['preparation_minutes'], config['buffer_minutes'])
    result.update(prepare_at=prepare.isoformat(), departure_at=departure.isoformat())


def materialize(session, schedule, now):
    if not schedule.data['enabled']:
        return
    for arrival in candidate_arrivals(schedule.data, now):
        row = session.scalar(select(Occurrence).where(Occurrence.schedule_id == schedule.id,
                                                       Occurrence.arrival_date == arrival.date().isoformat()))
        if not row:
            # Never synthesize a past occurrence on first creation/restart.
            if arrival < local(now):
                continue
            row = Occurrence(schedule_id=schedule.id, arrival_date=arrival.date().isoformat(),
                             data=snapshot(schedule.data, arrival, schedule.revision))
            session.add(row)
        elif row.status not in TERMINAL and row.data['revision'] != schedule.revision:
            updated = snapshot(schedule.data, arrival, schedule.revision)
            updated['attempts'] = row.data.get('attempts', 0)
            if (updated['routing_signature'] == row.data.get('routing_signature') and
                (row.data.get('eta_source') != 'initial_estimate' or
                 updated.get('eta_s') == row.data.get('eta_s'))):
                for key in ('eta_s', 'eta_updated_at', 'eta_source', 'traffic_aware', 'last_error', 'next_check_at'):
                    updated[key] = row.data.get(key)
                recalculate(updated, schedule.data)
            row.data = updated
    session.flush()


class DepartureWorker:
    """Explicit single worker with a renewable DB lease; never started by FastAPI."""
    def __init__(self, engine, provider, *, live_enabled=False, daily_limit=24,
                 clock=lambda: datetime.now(timezone.utc), owner=None):
        self.engine, self.provider = engine, provider
        self.live_enabled, self.daily_limit, self.clock = live_enabled, daily_limit, clock
        self.owner = owner or str(uuid4())
        self.notifications = NotificationService()

    def lease(self, now):
        timestamp = now.timestamp()
        with write_session(self.engine) as session:
            if not session.get(WorkerState, 'scheduler'):
                try:
                    session.add(WorkerState(name='scheduler', data={}))
                    session.commit()
                except IntegrityError:
                    session.rollback()
            result = session.execute(update(WorkerState).where(
                WorkerState.name == 'scheduler',
                or_(WorkerState.lease_until <= timestamp, WorkerState.owner == self.owner)
            ).values(owner=self.owner, lease_until=timestamp + 120))
            session.commit()
            return result.rowcount == 1

    def release(self):
        with write_session(self.engine) as session:
            session.execute(update(WorkerState).where(WorkerState.name == 'scheduler',
                WorkerState.owner == self.owner).values(lease_until=0))
            session.commit()

    async def tick(self):
        now = local(self.clock())
        if not self.lease(now):
            return False
        with write_session(self.engine) as session:
            schedules = list(session.scalars(select(Schedule).with_for_update()))
            for schedule in schedules:
                materialize(session, schedule, now)
            session.commit()
            ids = list(session.scalars(select(Occurrence.id).join(Schedule).where(
                Occurrence.status == 'planned',
                Occurrence.arrival_date <= (now.date() + timedelta(days=1)).isoformat())))
        for occurrence_id in ids:
            if not self.lease(local(self.clock())):
                return False
            await self.process(occurrence_id, local(self.clock()))
        with write_session(self.engine) as session:
            state = session.get(WorkerState, 'scheduler')
            state.data = {**state.data, 'last_tick_at': now.isoformat(),
                          'live_routing_enabled': self.live_enabled}
            session.commit()
        return True

    async def process(self, occurrence_id, now):
        call = None
        with write_session(self.engine) as session:
            occurrence = session.get(Occurrence, occurrence_id)
            if not occurrence:
                return
            schedule = session.scalar(select(Schedule).where(Schedule.id == occurrence.schedule_id).with_for_update())
            session.refresh(occurrence, with_for_update=True)
            if not schedule.data['enabled'] or occurrence.status in TERMINAL:
                return
            data = dict(occurrence.data)
            arrival = datetime.fromisoformat(data['arrival_at'])
            if now >= arrival:
                occurrence.status = 'missed'
                session.commit()
                return
            # Include long preparation/buffer windows before a midnight arrival.
            window = arrival - timedelta(minutes=max(90, (data.get('eta_s') or 0) / 60 + 15) + schedule.data['preparation_minutes'] +
                                         schedule.data['buffer_minutes'])
            state = session.get(WorkerState, 'scheduler')
            budget = dict(state.data)
            day = now.astimezone(timezone.utc).date().isoformat()
            if budget.get('budget_day') != day:
                budget.update(budget_day=day, attempts=0)
            allowed_at = budget.get('provider_next_at')
            check_at = data.get('next_check_at')
            allowed = (self.live_enabled and now >= window and data.get('attempts', 0) < 6
                       and budget.get('attempts', 0) < self.daily_limit
                       and (not allowed_at or now >= datetime.fromisoformat(allowed_at))
                       and (not check_at or now >= datetime.fromisoformat(check_at)))
            if allowed:
                data['attempts'] = data.get('attempts', 0) + 1
                departure = datetime.fromisoformat(data['departure_at']) if data.get('departure_at') else arrival
                data['next_check_at'] = (now + timedelta(seconds=interval_seconds(departure, now))).isoformat()
                budget.update(attempts=budget.get('attempts', 0) + 1,
                              provider_next_at=(now + timedelta(seconds=60)).isoformat())
                state.data = budget
                occurrence.data = data
                call = (schedule.revision, RouteRequest(origin=schedule.data['origin'],
                        destination=schedule.data['destination'], vehicle=schedule.data['vehicle']))
                # Persist attempt BEFORE network. Crash/restart cannot reset quota.
                session.commit()
        result, failure, retry = None, None, 900
        if call:
            try:
                routes = await asyncio.wait_for(self.provider.calculate(call[1]), timeout=12)
                if not routes:
                    raise HTTPException(502, 'Empty routes')
                result = min(routes, key=lambda route: route.duration_s)
            except HTTPException as exc:
                failure = f'provider_http_{exc.status_code}'
                if exc.status_code == 429:
                    raw = (exc.headers or {}).get('Retry-After', '900')
                    try:
                        retry = max(900, int(raw))
                    except ValueError:
                        from email.utils import parsedate_to_datetime
                        try:
                            retry = max(900, int((parsedate_to_datetime(raw) - now).total_seconds()))
                        except (ValueError, TypeError, OverflowError):
                            retry = 900
            except Exception:
                # Do not log exception URLs or coordinates. Keep previous ETA.
                failure = 'provider_unavailable'
        with write_session(self.engine) as session:
            occurrence = session.get(Occurrence, occurrence_id)
            if not occurrence:
                return  # Deleted while provider call was in flight.
            schedule = session.scalar(select(Schedule).where(Schedule.id == occurrence.schedule_id).with_for_update())
            session.refresh(occurrence, with_for_update=True)
            if not schedule or not schedule.data['enabled'] or occurrence.status in TERMINAL:
                return
            if call and schedule.revision != call[0]:
                return  # Never apply an ETA to edited endpoints.
            data = dict(occurrence.data)
            old_eta, old_departure = data.get('eta_s'), data.get('departure_at')
            if result:
                data.update(eta_s=result.duration_s, eta_updated_at=now.isoformat(),
                            traffic_aware=result.traffic_aware, eta_source=result.provider, eta_basis='fastest_available_route', last_error=None)
                recalculate(data, schedule.data)
            elif failure:
                data.update(last_error=failure, next_check_at=(now + timedelta(seconds=retry)).isoformat())
                if failure == 'provider_http_429':
                    state = session.get(WorkerState, 'scheduler')
                    state.data = {**state.data, 'provider_next_at': data['next_check_at']}
            occurrence.data = data
            if data.get('eta_s') is not None:
                prepare = datetime.fromisoformat(data['prepare_at'])
                departure = datetime.fromisoformat(data['departure_at'])
                arrival = datetime.fromisoformat(data['arrival_at'])
                kinds = due_kinds(now, arrival, prepare, departure, data['eta_s'])
                if result and old_eta and (data['eta_s'] - old_eta >= 180 or data['eta_s'] >= old_eta * 1.15):
                    kinds += ['eta_increased']
                    if old_departure and departure < datetime.fromisoformat(old_departure):
                        kinds += ['leave_earlier']
                for kind in kinds:
                    self.notifications.emit(session, schedule, occurrence, kind, now)
            session.commit()

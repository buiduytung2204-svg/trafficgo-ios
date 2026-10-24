from datetime import datetime, timedelta
from types import SimpleNamespace
import httpx
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from app.database import Base, User
from app.departure.models import Schedule, Occurrence, NotificationEvent, WorkerState, DeviceToken
from app.departure.engine import ZONE, moments, candidate_arrivals
from app.departure.service import DepartureWorker, materialize
from app.departure.schemas import ScheduleInput
from app.departure.notifications import deliver_push
from test_api import client  # Existing isolated, authenticated DB fixture; no live requests.


def config(**kwargs):
    return ScheduleInput(name='Đi học', origin={'lat': 20.9834, 'lon': 105.7726},
        destination={'lat': 20.9893, 'lon': 105.7821}, arrival_time='07:30',
        weekdays=[0, 1, 2, 3, 4, 5, 6], initial_eta_s=1500, **kwargs).model_dump(mode='json')


class FakeRouting:
    """Test-only synthetic ETAs; never mounted as a live routing endpoint."""
    def __init__(self, *values):
        self.values = list(values or [1500])
        self.calls = 0

    async def calculate(self, request):
        self.calls += 1
        value = self.values.pop(0) if len(self.values) > 1 else self.values[0]
        if isinstance(value, Exception):
            raise value
        return [SimpleNamespace(duration_s=value, provider='simulation', traffic_aware=False)]


@pytest.fixture
def fixture_db(tmp_path):
    engine = create_engine(f'sqlite:///{tmp_path / "departure.db"}')
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        session.add(User(id='test'))
        session.commit()
        schedule = Schedule(user_id='test', data=config())
        session.add(schedule)
        session.commit()
    yield engine
    engine.dispose()


def test_formula_timezone_midnight_and_weekdays():
    arrival = datetime(2026, 10, 26, 7, 30, tzinfo=ZONE)
    prepare, departure = moments(arrival, 1500, 15, 10)
    assert prepare.strftime('%H:%M') == '06:40'
    assert departure.strftime('%H:%M') == '06:55'
    prepare, departure = moments(arrival.replace(hour=0, minute=15), 1500, 15, 10)
    assert prepare.day == 25 and departure.day == 25
    cfg = config()
    cfg.update(weekdays=[0], arrival_time='00:15')
    arrivals = list(candidate_arrivals(cfg, arrival.replace(day=25, hour=23)))
    assert any(a.day == 26 for a in arrivals)
    assert all(a.weekday() == 0 for a in arrivals)
    cfg['one_off_date'] = '2026-10-27'
    assert [a.day for a in candidate_arrivals(cfg, arrival)] == [27]


@pytest.mark.asyncio
async def test_events_restart_no_duplicates_and_completed_immutable(fixture_db):
    now = [datetime(2026, 10, 26, 6, 40, tzinfo=ZONE)]
    provider = FakeRouting(1500, 2400)
    worker = DepartureWorker(fixture_db, provider, live_enabled=True, clock=lambda: now[0])
    assert await worker.tick()
    with Session(fixture_db) as session:
        row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
        assert row.data['departure_at'].endswith('06:55:00+07:00')
        assert session.scalar(select(NotificationEvent)).kind == 'preparation_due'
        occurrence_id = row.id
    await worker.tick()
    worker.release()
    restarted = DepartureWorker(fixture_db, provider, live_enabled=True, clock=lambda: now[0])
    await restarted.tick()
    assert provider.calls == 1
    now[0] += timedelta(minutes=15)
    await restarted.tick()
    with Session(fixture_db) as session:
        row = session.get(Occurrence, occurrence_id)
        assert row.data['eta_s'] == 2400
        kinds = list(session.scalars(select(NotificationEvent.kind)))
        assert 'eta_increased' in kinds and 'leave_earlier' in kinds
        assert len(kinds) == len(set(kinds))
        row.status = 'completed'
        frozen = row.data.copy()
        session.commit()
    now[0] += timedelta(minutes=15)
    await restarted.tick()
    with Session(fixture_db) as session:
        assert session.get(Occurrence, occurrence_id).data == frozen


@pytest.mark.asyncio
async def test_lease_and_quota_are_persistent(fixture_db):
    now = [datetime(2026, 10, 26, 6, 40, tzinfo=ZONE)]
    fake = FakeRouting()
    first = DepartureWorker(fixture_db, fake, live_enabled=True, daily_limit=1, clock=lambda: now[0])
    second = DepartureWorker(fixture_db, fake, live_enabled=True, clock=lambda: now[0])
    await first.tick()
    assert await second.tick() is False
    first.release()
    now[0] += timedelta(minutes=16)
    restarted = DepartureWorker(fixture_db, fake, live_enabled=True, daily_limit=1, clock=lambda: now[0])
    await restarted.tick()
    assert fake.calls == 1


@pytest.mark.asyncio
async def test_429_retains_eta_and_global_retry_after(fixture_db):
    now = [datetime(2026, 10, 26, 6, 0, tzinfo=ZONE)]
    fake = FakeRouting(HTTPException(429, 'limited', headers={'Retry-After': '3600'}))
    worker = DepartureWorker(fixture_db, fake, live_enabled=True, clock=lambda: now[0])
    await worker.tick()
    with Session(fixture_db) as session:
        row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
        assert row.data['eta_s'] == 1500
        assert row.data['last_error'] == 'provider_http_429'
        assert row.data['eta_updated_at'] is None
    now[0] += timedelta(minutes=30)
    await worker.tick()
    assert fake.calls == 1


@pytest.mark.asyncio
@pytest.mark.parametrize('status', ['skipped', 'completed', 'cancelled'])
async def test_disabled_and_terminal_no_requests(fixture_db, status):
    now = datetime(2026, 10, 26, 6, 40, tzinfo=ZONE)
    with Session(fixture_db) as session:
        schedule = session.scalar(select(Schedule))
        materialize(session, schedule, now)
        for row in session.scalars(select(Occurrence)):
            row.status = status
        session.commit()
    provider = FakeRouting()
    await DepartureWorker(fixture_db, provider, live_enabled=True, clock=lambda: now).tick()
    assert provider.calls == 0
    with Session(fixture_db) as session:
        schedule = session.scalar(select(Schedule))
        schedule.data = {**schedule.data, 'enabled': False}
        for row in session.scalars(select(Occurrence)):
            row.status = 'planned'
        session.commit()
    await DepartureWorker(fixture_db, provider, live_enabled=True, clock=lambda: now).tick()
    assert provider.calls == 0


@pytest.mark.asyncio
async def test_eta_decrease_and_offline_keep_estimate(fixture_db):
    now = [datetime(2026, 10, 26, 6, 0, tzinfo=ZONE)]
    worker = DepartureWorker(fixture_db, FakeRouting(2400, 1500, httpx.ConnectError('offline')),
                              live_enabled=True, clock=lambda: now[0])
    for minute in (0, 30, 50):
        now[0] = now[0].replace(hour=6, minute=minute)
        await worker.tick()
    with Session(fixture_db) as session:
        row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
        assert row.data['eta_s'] == 1500
        assert row.data['last_error'] == 'provider_unavailable'
        assert row.data['departure_at'].endswith('06:55:00+07:00')


def test_api_ownership_crud_validation_and_device_tokens(client):
    first = client.post('/api/v1/departure/session').json()['token']
    second = client.post('/api/v1/departure/session').json()['token']
    a, b = {'X-Schedule-Token': first}, {'X-Schedule-Token': second}
    assert client.get('/api/v1/departure/overview').status_code == 401
    body = config()
    assert client.post('/api/v1/departure/schedules', json={**body, 'weekdays': [9]}, headers=a).status_code == 422
    created = client.post('/api/v1/departure/schedules', json=body, headers=a)
    assert created.status_code == 201
    row = created.json()
    path = '/api/v1/departure/schedules/' + row['id']
    assert client.put(path, json=body, headers=b).status_code == 404
    assert client.put(path, json={**body, 'enabled': False}, headers=a).json()['enabled'] is False
    assert client.get('/api/v1/departure/overview', headers=b).json()['schedules'] == []
    occurrence = client.get(path + '/occurrences', headers=a).json()[0]
    opath = '/api/v1/departure/occurrences/' + occurrence['id']
    assert client.patch(opath, json={'status': 'completed'}, headers=b).status_code == 404
    assert client.patch(opath, json={'status': 'completed'}, headers=a).status_code == 200
    assert client.patch(opath, json={'status': 'skipped'}, headers=a).status_code == 409
    device = {'token': 'test-device-token-12345', 'platform': 'android'}
    assert client.post('/api/v1/departure/devices', json=device, headers=a).json()['push_configured'] is False
    assert client.post('/api/v1/departure/devices', json=device, headers=b).status_code == 409
    assert client.delete(path, headers=b).status_code == 404
    assert client.delete('/api/v1/departure/personal-data', headers=a).status_code == 204
    assert client.get('/api/v1/departure/overview', headers=a).status_code == 401


@pytest.mark.asyncio
async def test_invalid_push_token_deactivated(fixture_db):
    now = datetime(2026, 10, 26, 6, 40, tzinfo=ZONE)
    await DepartureWorker(fixture_db, FakeRouting(), clock=lambda: now).tick()
    keys = []
    class Invalid:
        async def send(self, token, payload, idempotency_key):
            keys.append(idempotency_key)
            return 'invalid_token'
    with Session(fixture_db) as session:
        device = DeviceToken(user_id='test', token_hash='x', data={'token': 'test'})
        session.add(device)
        session.flush()
        event = session.scalar(select(NotificationEvent))
        await deliver_push(session, event, Invalid())
        assert not device.active and keys == [f'{event.id}:{device.id}']


@pytest.mark.asyncio
async def test_multiple_schedules_and_cross_midnight_reminder(fixture_db):
    now = [datetime(2026, 10, 25, 23, 30, tzinfo=ZONE)]
    with Session(fixture_db) as session:
        schedule = session.scalar(select(Schedule))
        schedule.data = {**schedule.data, 'arrival_time': '00:15'}
        session.add(Schedule(user_id='test', data=config()))
        session.commit()
    worker = DepartureWorker(fixture_db, FakeRouting(), clock=lambda: now[0])
    await worker.tick()
    with Session(fixture_db) as session:
        rows = list(session.scalars(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26')))
        assert len(rows) == 2
        midnight = next(o for o in rows if '00:15' in o.data['arrival_at'])
        assert midnight.data['prepare_at'] == '2026-10-25T23:25:00+07:00'
        assert midnight.data['departure_at'] == '2026-10-25T23:40:00+07:00'
        assert list(session.scalars(select(NotificationEvent.kind))) == ['preparation_due']


@pytest.mark.asyncio
async def test_completed_during_provider_request_is_not_overwritten(fixture_db):
    now = datetime(2026, 10, 26, 6, 40, tzinfo=ZONE)
    class Completing:
        async def calculate(self, request):
            with Session(fixture_db) as session:
                row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
                row.status = 'completed'
                session.commit()
            return [SimpleNamespace(duration_s=3600, provider='simulation', traffic_aware=False)]
    await DepartureWorker(fixture_db, Completing(), live_enabled=True, clock=lambda: now).tick()
    with Session(fixture_db) as session:
        row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
        assert row.status == 'completed' and row.data['eta_s'] == 1500
        assert list(session.scalars(select(NotificationEvent))) == []


def test_additive_migration_preserves_old_data_and_restart(tmp_path):
    import os
    import sys
    import subprocess
    from pathlib import Path
    from sqlalchemy import text, inspect
    path = tmp_path / 'migration.db'
    env = {**os.environ, 'DATABASE_URL': 'sqlite:///' + path.as_posix()}
    backend = Path(__file__).resolve().parents[1]
    subprocess.run([sys.executable, '-m', 'alembic', 'upgrade', '001'], cwd=backend,
                   env=env, check=True, capture_output=True)
    engine = create_engine(env['DATABASE_URL'])
    with engine.begin() as connection:
        connection.execute(text("INSERT INTO users (id) VALUES ('legacy')"))
        connection.execute(text("INSERT INTO saved_routes (id,user_id,data) VALUES ('route','legacy','{}')"))
    engine.dispose()
    for _ in range(2):
        subprocess.run([sys.executable, '-m', 'alembic', 'upgrade', 'head'], cwd=backend,
                       env=env, check=True, capture_output=True)
    engine = create_engine(env['DATABASE_URL'])
    with engine.connect() as connection:
        assert connection.execute(text('SELECT user_id FROM saved_routes')).scalar() == 'legacy'
        assert 'commute_schedules' in inspect(connection).get_table_names()
    engine.dispose()


def test_schedule_edit_does_not_modify_completed_occurrences(client):
    token = client.post('/api/v1/departure/session').json()['token']
    headers = {'X-Schedule-Token': token}
    schedule = client.post('/api/v1/departure/schedules', json=config(), headers=headers).json()
    occurrence = schedule['occurrence']
    client.patch('/api/v1/departure/occurrences/' + occurrence['id'], json={'status': 'completed'}, headers=headers)
    assert client.put('/api/v1/departure/schedules/' + schedule['id'],
                      json={**config(), 'buffer_minutes': 60}, headers=headers).status_code == 200
    rows = client.get('/api/v1/departure/schedules/' + schedule['id'] + '/occurrences', headers=headers).json()
    completed = next(o for o in rows if o['id'] == occurrence['id'])
    assert completed['status'] == 'completed'
    assert completed['departure_at'] == occurrence['departure_at']


@pytest.mark.asyncio
async def test_edit_preserves_last_provider_eta_and_attempt_budget(fixture_db):
    now = datetime(2026, 10, 26, 6, 0, tzinfo=ZONE)
    worker = DepartureWorker(fixture_db, FakeRouting(2400), live_enabled=True, clock=lambda: now)
    await worker.tick()
    with Session(fixture_db) as session:
        schedule = session.scalar(select(Schedule))
        schedule.data = {**schedule.data, 'buffer_minutes': 20}
        schedule.revision += 1
        materialize(session, schedule, now)
        row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
        assert row.data['eta_s'] == 2400 and row.data['eta_source'] == 'simulation'
        assert row.data['departure_at'].endswith('06:30:00+07:00')
        assert row.data['attempts'] == 1
        schedule.data = {**schedule.data, 'vehicle': 'motorcycle'}
        schedule.revision += 1
        materialize(session, schedule, now)
        assert row.data['eta_s'] == 1500 and row.data['eta_source'] == 'initial_estimate'
        assert row.data['attempts'] == 1


def test_journey_direction_schema_roundtrip():
    from app.departure.schemas import ScheduleInput
    data = ScheduleInput(name='School inbound', origin={'lat':21.02,'lon':105.85},
        destination={'lat':21.04,'lon':105.82}, arrival_time='18:30',
        journey_id='local-school-id', direction='inbound')
    assert data.model_dump()['journey_id'] == 'local-school-id'
    assert data.model_dump()['direction'] == 'inbound'
    import pytest
    with pytest.raises(ValueError):
        ScheduleInput(**{**data.model_dump(), 'direction':'reverse-polyline'})

"""Isolated DB and fake clock; no live routing or real-account data."""
from datetime import datetime, timedelta
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.main import app, db
from app.departure.engine import ZONE
from app.departure.models import Schedule, Occurrence, NotificationEvent
from app.departure.notifications import NotificationService
from app.departure.service import materialize, DepartureWorker
from test_api import client
from test_departure import config, FakeRouting, fixture_db


def setup(client):
    headers = {'X-Schedule-Token': client.post('/api/v1/departure/session').json()['token']}
    row = client.post('/api/v1/departure/schedules', headers=headers, json=config()).json()
    day = (datetime.now(ZONE).date() + timedelta(days=1)).isoformat()
    return headers, row, day


def session_for_test():
    return next(app.dependency_overrides[db]())


def emit(client, headers, schedule_id, day):
    with session_for_test() as session:
        schedule = session.get(Schedule, schedule_id)
        occurrence = session.scalar(select(Occurrence).where(Occurrence.schedule_id == schedule_id, Occurrence.arrival_date == day))
        event = NotificationService().emit(session, schedule, occurrence, 'departure_soon', datetime.now(ZONE))
        session.commit()
        return event.id, occurrence.id


def test_day_override_reset_skip_and_ownership(client):
    headers, row, day = setup(client)
    path = f"/api/v1/departure/schedules/{row['id']}/exceptions/{day}"
    other = {'X-Schedule-Token': client.post('/api/v1/departure/session').json()['token']}
    assert client.put(path, headers=other, json={'action':'skip'}).status_code == 404
    result = client.put(path, headers=headers, json={'action':'change', 'arrival_time':'08:30', 'preparation_minutes':20})
    assert result.status_code == 200, result.text
    occurrence = result.json()
    assert occurrence['arrival_at'].endswith('08:30:00+07:00')
    assert occurrence['departure_at'].endswith('07:55:00+07:00')
    assert occurrence['prepare_at'].endswith('07:35:00+07:00')
    # Editing weekly settings / a worker restart must not erase a day exception.
    updated = client.put(f"/api/v1/departure/schedules/{row['id']}", headers=headers,
                         json={**config(), 'buffer_minutes':15})
    assert updated.status_code == 200
    rows = client.get(f"/api/v1/departure/schedules/{row['id']}/occurrences", headers=headers).json()
    current = next(o for o in rows if o['id'] == occurrence['id'])
    assert current['arrival_at'].endswith('08:30:00+07:00')
    assert current['departure_at'].endswith('07:50:00+07:00')
    assert next(o for o in rows if o['arrival_date'] != day)['arrival_at'].endswith('07:30:00+07:00')
    assert client.put(path, headers=headers, json={'action':'skip'}).json()['status'] == 'skipped'
    assert client.put(path, headers=headers, json={'action':'skip'}).json()['status'] == 'skipped'
    restored = client.put(path, headers=headers, json={'action':'reset'}).json()
    assert restored['status'] == 'planned' and restored['day_override'] == {}
    assert restored['arrival_at'].endswith('07:30:00+07:00')
    client.patch('/api/v1/departure/occurrences/'+occurrence['id'], headers=headers, json={'status':'completed'})
    assert client.put(path, headers=headers, json={'action':'change', 'arrival_time':'09:00'}).status_code == 409


def test_exception_validation_midnight_and_terminal(client):
    headers, row, day = setup(client)
    path = f"/api/v1/departure/schedules/{row['id']}/exceptions/{day}"
    for body in ({'action':'change'}, {'action':'change','arrival_time':'25:00'}, {'action':'change','buffer_minutes':-1}):
        assert client.put(path, headers=headers, json=body).status_code == 422
    result = client.put(path, headers=headers, json={'action':'change','arrival_time':'00:15'}).json()
    assert datetime.fromisoformat(result['departure_at']).date() < datetime.fromisoformat(result['arrival_at']).date()
    old = (datetime.now(ZONE).date()-timedelta(days=1)).isoformat()
    assert client.put(path.replace(day,old), headers=headers, json={'action':'skip'}).status_code == 422


@pytest.mark.parametrize('action,status', [('start','in_progress'),('skip','skipped')])
def test_notification_actions_idempotent_owned_and_stop_reminders(client, action, status):
    headers, row, day = setup(client)
    event_id, occurrence_id = emit(client, headers, row['id'], day)
    path = f'/api/v1/departure/notifications/{event_id}/action'
    other = {'X-Schedule-Token': client.post('/api/v1/departure/session').json()['token']}
    assert client.post(path, headers=other, json={'action':action}).status_code == 404
    for _ in range(2):
        result = client.post(path, headers=headers, json={'action':action})
        assert result.status_code == 200, result.text
        assert result.json()['action_result'] == action
    assert client.post(path, headers=headers, json={'action':'snooze'}).status_code == 409
    with session_for_test() as session:
        assert session.get(Occurrence, occurrence_id).status == status
        assert session.get(NotificationEvent,event_id).data['cancelled']
    if action == 'start':
        assert client.patch('/api/v1/departure/occurrences/'+occurrence_id, headers=headers,
                            json={'status':'completed'}).status_code == 200
        assert client.post(path, headers=headers, json={'action':'start'}).status_code == 409


@pytest.mark.asyncio
async def test_snooze_survives_worker_restart_no_duplicates(client):
    headers, row, day = setup(client)
    event_id, occurrence_id = emit(client, headers, row['id'], day)
    path = f'/api/v1/departure/notifications/{event_id}/action'
    result = client.post(path, headers=headers, json={'action':'snooze'})
    assert result.status_code == 200
    with session_for_test() as session:
        occurrence = session.get(Occurrence, occurrence_id)
        until = occurrence.data['snooze_until']
        original_departure = occurrence.data['departure_at']
        engine = session.bind
    client.post(path, headers=headers, json={'action':'snooze'})
    with Session(engine) as session:
        assert session.get(Occurrence, occurrence_id).data['snooze_until'] == until
    clock = [datetime.fromisoformat(until) - timedelta(seconds=1)]
    provider = FakeRouting()
    worker = DepartureWorker(engine, provider, clock=lambda: clock[0])
    await worker.tick()
    worker.release()
    clock[0] += timedelta(seconds=2)
    restarted = DepartureWorker(engine, provider, clock=lambda: clock[0])
    await restarted.tick()
    await restarted.tick()
    with Session(engine) as session:
        events = list(session.scalars(select(NotificationEvent).where(NotificationEvent.occurrence_id==occurrence_id)))
        assert len([e for e in events if e.kind.startswith('snooze_')]) == 1
        occurrence = session.get(Occurrence, occurrence_id)
        assert occurrence.data['departure_at'] == original_departure
        assert 'snooze_until' not in occurrence.data
    assert provider.calls == 0


@pytest.mark.asyncio
async def test_override_eta_recalculation_and_skip_no_provider(fixture_db):
    now = datetime(2026,10,26,6,40,tzinfo=ZONE)
    with Session(fixture_db) as session:
        schedule = session.scalar(select(Schedule))
        materialize(session,schedule,now)
        occurrence = session.scalar(select(Occurrence).where(Occurrence.arrival_date=='2026-10-26'))
        occurrence.data = {**occurrence.data,'day_override':{'preparation_minutes':20,'buffer_minutes':5}}
        session.commit()
    provider = FakeRouting(2400)
    worker = DepartureWorker(fixture_db,provider,live_enabled=True,clock=lambda:now)
    await worker.tick()
    with Session(fixture_db) as session:
        occurrence = session.scalar(select(Occurrence).where(Occurrence.arrival_date=='2026-10-26'))
        assert occurrence.data['departure_at'].endswith('06:45:00+07:00')
        assert occurrence.data['prepare_at'].endswith('06:25:00+07:00')
        occurrence.status='skipped'
        session.commit()
    await worker.tick()
    assert provider.calls == 1


@pytest.mark.asyncio
async def test_day_changed_during_routing_does_not_apply_stale_eta(fixture_db):
    now = datetime(2026,10,26,6,40,tzinfo=ZONE)
    class Editing(FakeRouting):
        async def calculate(self, request):
            with Session(fixture_db) as session:
                occurrence = session.scalar(select(Occurrence).where(Occurrence.arrival_date=='2026-10-26'))
                occurrence.data = {**occurrence.data, 'exception_revision':1, 'day_override':{'buffer_minutes':20}}
                session.commit()
            return await super().calculate(request)
    await DepartureWorker(fixture_db,Editing(3600),live_enabled=True,clock=lambda:now).tick()
    with Session(fixture_db) as session:
        occurrence = session.scalar(select(Occurrence).where(Occurrence.arrival_date=='2026-10-26'))
        assert occurrence.data['eta_s'] == 1500
        assert list(session.scalars(select(NotificationEvent))) == []


def test_snooze_pending_event_disabled_schedule_and_replay_after_completion(client):
    headers,row,day=setup(client)
    event_id,occurrence_id=emit(client,headers,row['id'],day)
    original = client.post(f'/api/v1/departure/notifications/{event_id}/action',headers=headers,json={'action':'snooze'}).json()
    child = original['reminder_event_id']
    assert client.post(f'/api/v1/departure/notifications/{child}/action',headers=headers,json={'action':'start'}).status_code==409
    result=client.put(f"/api/v1/departure/schedules/{row['id']}",headers=headers,json={**config(),'enabled':False})
    assert result.status_code==200
    assert client.get(f'/api/v1/departure/notifications/{child}',headers=headers).json()['cancelled'] is True
    other={'X-Schedule-Token':client.post('/api/v1/departure/session').json()['token']}
    assert client.get(f'/api/v1/departure/notifications/{child}',headers=other).status_code==404


def test_same_day_change_is_idempotent(client):
    headers,row,day=setup(client)
    path=f"/api/v1/departure/schedules/{row['id']}/exceptions/{day}"
    body={'action':'change','arrival_time':'08:00'}
    first=client.put(path,headers=headers,json=body).json()
    second=client.put(path,headers=headers,json=body).json()
    assert first['exception_revision']==second['exception_revision']


def test_reset_future_date_outside_worker_window_persists(client):
    headers,row,_=setup(client)
    day=(datetime.now(ZONE).date()+timedelta(days=100)).isoformat()
    path=f"/api/v1/departure/schedules/{row['id']}/exceptions/{day}"
    result=client.put(path,headers=headers,json={'action':'reset'})
    assert result.status_code==200
    occurrence_id=result.json()['id']
    rows=client.get(f"/api/v1/departure/schedules/{row['id']}/occurrences",headers=headers).json()
    assert any(o['id']==occurrence_id for o in rows)
    assert client.put(path,headers=headers,json={'action':'reset'}).json()['id']==occurrence_id


def test_edit_weekly_schedule_preserves_far_future_exception_and_cancels_old_payload(client):
    headers,row,_=setup(client)
    day=(datetime.now(ZONE).date()+timedelta(days=100)).isoformat()
    path=f"/api/v1/departure/schedules/{row['id']}/exceptions/{day}"
    occurrence=client.put(path,headers=headers,json={'action':'change','arrival_time':'08:00'}).json()
    event_id,_=emit(client,headers,row['id'],day)
    result=client.put(f"/api/v1/departure/schedules/{row['id']}",headers=headers,json={**config(),'name':'New name'})
    assert result.status_code==200
    rows=client.get(f"/api/v1/departure/schedules/{row['id']}/occurrences",headers=headers).json()
    saved=next(o for o in rows if o['id']==occurrence['id'])
    assert saved['status']=='planned' and saved['day_override']['arrival_time']=='08:00'
    assert client.get(f'/api/v1/departure/notifications/{event_id}',headers=headers).json()['cancelled'] is True


@pytest.mark.parametrize('action,minutes_left', [('snooze',4),('start',-1)])
def test_notification_too_late_is_rejected_without_mutation(client, monkeypatch, action, minutes_left):
    import importlib
    api = importlib.import_module('app.departure.api')
    headers,row,day=setup(client)
    event_id,occurrence_id=emit(client,headers,row['id'],day)
    with session_for_test() as session:
        before = dict(session.get(Occurrence,occurrence_id).data)
    frozen = datetime.fromisoformat(before['arrival_at'])-timedelta(minutes=minutes_left)
    class FrozenDateTime(datetime):
        @classmethod
        def now(cls,tz=None):
            return frozen.astimezone(tz) if tz else frozen.replace(tzinfo=None)
    monkeypatch.setattr(api,'datetime',FrozenDateTime)
    result=client.post(f'/api/v1/departure/notifications/{event_id}/action',headers=headers,json={'action':action})
    assert result.status_code==409
    with session_for_test() as session:
        occurrence=session.get(Occurrence,occurrence_id)
        assert occurrence.status=='planned' and occurrence.data==before
        assert session.get(NotificationEvent,event_id).data.get('action_result') is None


def test_exception_on_non_recurring_day_is_rejected(client):
    headers,row,day=setup(client)
    excluded=datetime.fromisoformat(day).weekday()
    body={**config(),'weekdays':[(excluded+1)%7]}
    assert client.put(f"/api/v1/departure/schedules/{row['id']}",headers=headers,json=body).status_code==200
    result=client.put(f"/api/v1/departure/schedules/{row['id']}/exceptions/{day}",headers=headers,json={'action':'skip'})
    assert result.status_code==422


@pytest.mark.asyncio
async def test_day_off_persists_after_restart_without_skipping_next_day(fixture_db):
    now=datetime(2026,10,26,6,40,tzinfo=ZONE)
    with Session(fixture_db) as session:
        schedule=session.scalar(select(Schedule))
        materialize(session,schedule,now)
        today=session.scalar(select(Occurrence).where(Occurrence.arrival_date=='2026-10-26'))
        today.status='skipped'
        session.commit()
    provider=FakeRouting()
    first=DepartureWorker(fixture_db,provider,clock=lambda:now)
    await first.tick()
    first.release()
    restarted=DepartureWorker(fixture_db,provider,clock=lambda:now)
    await restarted.tick()
    with Session(fixture_db) as session:
        rows={o.arrival_date:o for o in session.scalars(select(Occurrence))}
        assert rows['2026-10-26'].status=='skipped'
        assert rows['2026-10-27'].status=='planned'
        assert not list(session.scalars(select(NotificationEvent).where(NotificationEvent.occurrence_id==rows['2026-10-26'].id)))
    assert provider.calls==0

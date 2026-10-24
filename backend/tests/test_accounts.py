import pytest
from sqlalchemy import select
from test_api import client
from app.main import db
from app.accounts.api import windows, hash_password, verify
from app.accounts.models import Account

@pytest.fixture(autouse=True)
def reset_auth_limits():
    windows.clear()

def register(client, name='student'):
    r = client.post('/api/v1/accounts/register', json={'username': name, 'password':'local-test-password-123'})
    assert r.status_code == 201, r.text
    return r.json()

def auth(a):
    return {'X-Schedule-Token': a['token']}

def setup_body(a):
    origin = {'lat':21.02, 'lon':105.85}
    destination = {'lat':21.04, 'lon':105.82}
    jid = 'setup-'+a['user_id']
    return {'display_name':'Sinh viên', 'purpose':'school', 'vehicle':'motorcycle', 'vehicle_id':'wave-test',
      'home':{'name':'Nhà','coordinate':origin}, 'destination':{'name':'Trường','coordinate':destination},
      'journey_id':jid, 'schedule':{'name':'Nhà → Trường', 'journey_id':jid, 'direction':'outbound',
      'vehicle':'motorcycle','origin':origin,'destination':destination,'arrival_time':'07:30',
      'weekdays':[0,1,2,3,4], 'initial_eta_s':1500, 'preparation_minutes':15, 'buffer_minutes':10}}

def test_password_salted_and_verified():
    a = hash_password('long-enough-password'); b = hash_password('long-enough-password')
    assert a != b and 'long-enough-password' not in a
    assert verify('long-enough-password',a) and not verify('wrong',a)
    assert not verify('anything','broken')

def test_register_login_and_session_revocation(client):
    a = register(client)
    assert a['profile']['setup_complete'] is False and 'password_hash' not in a
    assert client.get('/api/v1/accounts/me',headers=auth(a)).json()['user_id'] == a['user_id']
    assert client.post('/api/v1/accounts/register',json={'username':'STUDENT','password':'another-password-123'}).status_code == 409
    assert client.post('/api/v1/accounts/login',json={'username':'STUDENT','password':'wrong-password'}).status_code == 401
    assert client.post('/api/v1/accounts/login',json={'username':'absent','password':'wrong-password'}).status_code == 401
    b = client.post('/api/v1/accounts/login',json={'username':'STUDENT','password':'local-test-password-123'}).json()
    assert b['user_id'] == a['user_id'] and b['token'] != a['token']
    assert client.post('/api/v1/accounts/logout',headers=auth(a)).status_code == 204
    assert client.get('/api/v1/accounts/me',headers=auth(a)).status_code == 401
    assert client.get('/api/v1/accounts/me',headers=auth(b)).status_code == 200

def test_setup_idempotent_and_owner_isolation(client):
    a = register(client); b = register(client,'another')
    body = setup_body(a)
    r = client.post('/api/v1/accounts/setup',json=body,headers=auth(a))
    assert r.status_code == 200, r.text
    assert r.json()['profile']['setup_complete']
    first = r.json()['profile']['schedule_id']
    assert client.post('/api/v1/accounts/setup',json=body,headers=auth(a)).json()['profile']['schedule_id'] == first
    # New login is a fresh installation; DB profile/schedule survive it.
    new = client.post('/api/v1/accounts/login',json={'username':'student','password':'local-test-password-123'}).json()
    overview = client.get('/api/v1/departure/overview',headers=auth(new)).json()
    assert len(overview['schedules']) == 1
    s = overview['schedules'][0]
    assert s['journey_id'] == body['journey_id'] and s['initial_eta_s'] == 1500
    occurrence = s['occurrence']
    from datetime import datetime
    from app.departure.engine import ZONE
    assert datetime.fromisoformat(occurrence['prepare_at']).astimezone(ZONE).strftime('%H:%M') == '06:40'
    assert datetime.fromisoformat(occurrence['departure_at']).astimezone(ZONE).strftime('%H:%M') == '06:55'
    assert datetime.fromisoformat(occurrence['arrival_at']).astimezone(ZONE).strftime('%H:%M') == '07:30'
    assert client.get('/api/v1/departure/overview',headers=auth(b)).json()['schedules'] == []
    assert client.delete('/api/v1/departure/schedules/'+first,headers=auth(b)).status_code == 404
    assert client.get('/api/v1/accounts/me',headers=auth(b)).json()['profile']['setup_complete'] is False

def test_setup_validation_and_guest_not_account(client):
    guest = client.post('/api/v1/departure/session').json()
    assert client.get('/api/v1/accounts/me',headers=auth(guest)).status_code == 401
    a = register(client); body = setup_body(a)
    assert client.post('/api/v1/accounts/setup',json=body).status_code == 401
    body['vehicle_id'] = None
    assert client.post('/api/v1/accounts/setup',json=body,headers=auth(a)).status_code == 422
    body = setup_body(a); body['schedule']['journey_id'] = 'wrong'
    assert client.post('/api/v1/accounts/setup',json=body,headers=auth(a)).status_code == 422
    body = setup_body(a); body['schedule']['weekdays'] = []
    assert client.post('/api/v1/accounts/setup',json=body,headers=auth(a)).status_code == 422
    assert client.get('/api/v1/departure/overview',headers=auth(a)).json()['schedules'] == []

def test_auth_rate_limit_and_validation_redaction(client):
    r = client.post('/api/v1/accounts/register',json={'username':'ab','password':'secret'})
    assert r.status_code == 422 and 'secret' not in r.text
    windows.clear()
    for _ in range(10):
        assert client.post('/api/v1/accounts/login',json={'username':'bad','password':'short'}).status_code == 422
    r = client.post('/api/v1/accounts/login',json={'username':'bad','password':'short'})
    assert r.status_code == 429 and r.headers['retry-after'] == '60'


def test_additive_migration_preserves_guest_records(tmp_path, monkeypatch):
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import create_engine, text, inspect
    from app.config import settings
    url = f"sqlite:///{tmp_path / 'upgrade.db'}"
    monkeypatch.setattr(settings, 'database_url', url)
    cfg = Config('alembic.ini')
    command.upgrade(cfg, '002')
    engine = create_engine(url)
    with engine.begin() as connection:
        connection.execute(text("INSERT INTO users (id) VALUES ('existing-guest')"))
        connection.execute(text("INSERT INTO saved_places (id,user_id,data) VALUES ('home','existing-guest','{}')"))
    command.upgrade(cfg, 'head')
    with engine.connect() as connection:
        assert connection.execute(text("SELECT count(*) FROM saved_places WHERE user_id='existing-guest'")).scalar() == 1
        assert 'accounts' in inspect(connection).get_table_names()
        assert connection.execute(text('SELECT version_num FROM alembic_version')).scalar() == '003'
    engine.dispose()

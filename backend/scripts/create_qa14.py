"""Explicit local-only QA fixture. Run from backend: python scripts/create_qa14.py.

Creates a NEW account only. Password/session are written to ignored build files.
Historical trips/expenses/ETA/events are SIMULATED, never live GPS/traffic claims.
"""
import asyncio
import csv
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import secrets
import sys
from uuid import uuid4
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import httpx
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from app.config import settings
from app.database import database_engine
from app.accounts.models import Account
from app.departure.models import Schedule, Occurrence, NotificationEvent
from app.departure.service import snapshot, recalculate
from app.departure.notifications import NotificationService
from app.departure.engine import moments, due_kinds

OUT = Path(__file__).resolve().parents[2] / 'build/reports/qa14'
ZONE = ZoneInfo('Asia/Ho_Chi_Minh')


async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    username = 'qa14_' + datetime.now(ZONE).strftime('%m%d_%H%M%S')
    password = 'Qa14-' + secrets.token_urlsafe(12)
    cases = []

    def check(name, condition, detail=''):
        cases.append({'case': name, 'passed': bool(condition), 'detail': detail})
        if not condition:
            raise AssertionError(name)

    engine = database_engine(settings.database_url)
    with Session(engine) as db:
        existing = {a.user_id: (a.username, a.password_hash, json.dumps(a.profile, sort_keys=True))
                    for a in db.scalars(select(Account))}

    async with httpx.AsyncClient(base_url='http://localhost:8000', timeout=35,
        headers={'X-App-Token': settings.app_access_token}) as client:
        async def call(method, path, body=None, expected=200):
            r = await client.request(method, path, json=body)
            if r.status_code != expected:
                # Never print request headers, credential-bearing body or URL.
                raise RuntimeError(f'{method} {path}: HTTP {r.status_code}')
            return r.json() if r.content else None

        auth = await call('POST', '/api/v1/accounts/register',
                          {'username': username, 'password': password, 'nickname': 'QA 14 days'}, 201)
        uid = auth['user_id']
        client.headers['X-Schedule-Token'] = auth['token']
        (OUT / 'account.private.json').write_text(json.dumps({
            'username': username, 'password': password, 'user_id': uid,
            'note': 'Local QA only. Do not commit or use as a personal password.'}, indent=2), encoding='utf-8')
        check('Register new local account', not auth['profile']['setup_complete'])
        r = await client.post('/api/v1/accounts/login', json={'username': username, 'password': password+'wrong'})
        check('Wrong password rejected', r.status_code == 401)
        logged = await call('POST', '/api/v1/accounts/login', {'username': username, 'password': password})
        client.headers['X-Schedule-Token'] = logged['token']
        check('Login and identity', logged['user_id'] == uid)

        places = []
        for query, category in [('NHS Trung Văn', 'home'), ('Đại học CMC cơ sở 2', 'school')]:
            data = (await client.get('/api/v1/places/search', params={'q': query,'lat':21.01,'lon':105.81})).json()
            if not data.get('places'):
                raise RuntimeError('QA place search returned no results')
            place = data['places'][0]
            place.update(category=category, notes='QA14 SIMULATION_ONLY: địa điểm tham khảo thật')
            places.append(place)
        check('Real Geoapify place search', len(places) == 2)

        trips = []
        for direction, origin, destination in [('outbound', places[0], places[1]), ('inbound', places[1], places[0])]:
            result = await call('POST', '/api/v1/routes/calculate', {
                'origin': origin['coordinate'], 'destination': destination['coordinate'],
                'vehicle': 'motorcycle', 'avoid_highways': True})
            candidates = result['routes'] if isinstance(result, dict) else result
            if not candidates:
                raise RuntimeError('QA routing returned no valid route')
            # Select a real alternative if offered, never invent a second route.
            selected = candidates[min(1, len(candidates)-1)]
            trips.append({'name': f'QA14 — {"Đi học" if direction == "outbound" else "Về nhà"}',
                          'origin': origin, 'destination': destination, 'vehicle':'motorcycle', 'route': selected})
        check('Independent real routes both directions', all(len(t['route']['geometry']) >= 2 for t in trips))
        journey_id, vehicle_id = 'qa14-school', 'qa14-wave'

        def schedule(direction, arrival):
            trip = trips[0 if direction == 'outbound' else 1]
            return {'name': f'QA14 MÔ PHỎNG — {direction}', 'journey_id': journey_id,
                'direction': direction, 'route_name':trip['name'],
                'origin':trip['origin']['coordinate'], 'destination':trip['destination']['coordinate'],
                'origin_name':trip['origin']['name'], 'destination_name':trip['destination']['name'],
                'vehicle':'motorcycle', 'arrival_time':arrival, 'weekdays':[0,1,2,3,4],
                'preparation_minutes':15,'buffer_minutes':10,'enabled':True,
                'initial_eta_s':trip['route']['duration_s']}

        setup = {'display_name':'Người dùng QA • 14 ngày mô phỏng','purpose':'school','vehicle':'motorcycle',
            'vehicle_id':vehicle_id, 'home':{k:places[0][k] for k in ('name','coordinate')},
            'destination':{k:places[1][k] for k in ('name','coordinate')},
            'journey_id':journey_id, 'schedule':schedule('outbound','07:30')}
        profile = await call('POST','/api/v1/accounts/setup', setup)
        again = await call('POST','/api/v1/accounts/setup', setup)
        check('Setup retry is idempotent', profile['profile']['schedule_id'] == again['profile']['schedule_id'])
        outbound_id = profile['profile']['schedule_id']
        inbound = await call('POST','/api/v1/departure/schedules',schedule('inbound','18:30'),201)
        inbound_id = inbound['id']
        # Exercise schedule CRUD without leaving an extra schedule behind.
        temporary = await call('POST','/api/v1/departure/schedules', {**schedule('outbound','08:00'), 'name':'QA14 temporary CRUD'},201)
        edited = await call('PUT',f'/api/v1/departure/schedules/{temporary["id"]}',
                           {**schedule('outbound','08:15'),'enabled':False})
        check('Schedule edit and disable', edited['enabled'] is False and edited['arrival_time']=='08:15')
        await call('DELETE',f'/api/v1/departure/schedules/{temporary["id"]}',expected=204)
        check('Schedule delete', True)

        today = datetime.now(ZONE).date()
        days = [today-timedelta(days=13-i) for i in range(14)]
        weekdays = [d for d in days if d.weekday()<5]
        absent = weekdays[3]
        expenses, completed, history, ledger = [], [], [], []
        odometer = 5990
        old_due = 6000
        for i, day in enumerate(days):
            key = day.isoformat()
            trips_today = 0
            status = 'weekend'
            # Explicit simulated user purchase every day, not auto-estimated fuel.
            expenses.append({'id':f'qa14-fuel-{key}','category':'fuel','date':key,'amount':50000,
                'journey_id':journey_id,'direction':None,'notes':'QA14 SIMULATION_ONLY: giả lập người dùng nhập mua xăng'})
            if day.weekday()<5:
                expenses.append({'id':f'qa14-parking-{key}','category':'parking','date':key,'amount':10000,
                    'journey_id':journey_id,'direction':'outbound','notes':'QA14 SIMULATION_ONLY: gửi xe'})
                status = 'skipped/cancelled' if day == absent else 'completed'
                if day != absent:
                    for j, direction in enumerate(['outbound','inbound']):
                        trip = trips[j]
                        completed.append({'id':f'qa14-{key}-{direction}','journey_id':journey_id,
                            'direction':direction,'name':trip['name']+' [MÔ PHỎNG]',
                            'completed_at':datetime.combine(day,datetime.strptime('07:30' if j==0 else '18:30','%H:%M').time(),ZONE).isoformat(),
                            'distance_m':trip['route']['distance_m'], 'simulation_only':True})
                        # Odometer is simulated manual input, not derived GPS history.
                        odometer += round(trip['route']['distance_m']/1000)
                        trips_today += 1
            if i in (6,13):
                expenses.append({'id':f'qa14-service-{i}','category':'other','date':key,'amount':100000,
                    'journey_id':journey_id,'notes':'QA14 SIMULATION_ONLY: bảo dưỡng tuần, đã giả lập xác nhận'})
                history.append({'id':f'qa14-service-{i}','item_id':f'qa14-old-oil-{i}',
                    'name':'Bảo dưỡng QA14 [MÔ PHỎNG]','vehicle_id':vehicle_id,
                    'vehicle_name':'Wave Alpha 2024 • QA14','odometer':odometer,
                    'completed_at':datetime.combine(day,datetime.min.time(),ZONE).isoformat(),'source':'user_confirmed_simulation'})
            ledger.append({'day':i+1,'date':key,'weekday':day.weekday(),'status':status,
                'completed_trips':trips_today,'fuel_vnd':50000,'parking_vnd':10000 if day.weekday()<5 else 0,
                'maintenance_vnd':100000 if i in (6,13) else 0,'odometer_manual_simulated':odometer})

        # Persist clearly labelled history ONLY for the newly-created test account.
        with Session(engine) as db:
            schedules = [db.get(Schedule, outbound_id), db.get(Schedule, inbound_id)]
            for row in schedules:
                assert row.user_id == uid
                for i, day in enumerate(weekdays):
                    arrival = datetime.combine(day, datetime.strptime(row.data['arrival_time'],'%H:%M').time(), ZONE)
                    data = snapshot(row.data, arrival, row.revision)
                    data.update(eta_s=[900,1500,2400,3600][i%4],eta_source='SIMULATION_QA_ONLY',
                        eta_updated_at=(arrival-timedelta(hours=1)).isoformat(), traffic_aware=False,simulation_only=True)
                    recalculate(data,row.data)
                    state = ('skipped' if row.id==outbound_id else 'cancelled') if day==absent else 'completed'
                    occurrence = Occurrence(schedule_id=row.id,arrival_date=day.isoformat(),status=state,data=data)
                    db.add(occurrence);db.flush()
                    for kind in ['preparation_due','departure_due']:
                        service=NotificationService()
                        event=service.emit(db,row,occurrence,kind,arrival-timedelta(minutes=30))
                        event.data={**event.data,'title':'[QA MÔ PHỎNG] '+event.data['title'],'simulation_only':True}
                        event.read=True
                        check_id=service.emit(db,row,occurrence,kind,arrival-timedelta(minutes=29)).id
                        assert check_id==event.id
            db.commit()
            recent = db.scalar(select(NotificationEvent).where(NotificationEvent.user_id==uid)
                               .order_by(NotificationEvent.created_at.desc()))
            recent.read = False
            db.commit()
            check('Historical inbox events deduplicate', db.scalar(select(func.count()).select_from(NotificationEvent).where(NotificationEvent.user_id==uid))==40)
            now_existing={a.user_id:(a.username,a.password_hash,json.dumps(a.profile,sort_keys=True))
                          for a in db.scalars(select(Account).where(Account.user_id!=uid))}
            check('Existing accounts unchanged', all(now_existing.get(k)==v for k,v in existing.items()))

        overview=await call('GET','/api/v1/departure/overview')
        check('Two schedules and simulated inbox visible via real API',len(overview['schedules'])==2 and len(overview['notifications'])==40)
        check('Push truthfully unconfigured',overview['push_configured'] is False)
        prepare,depart=moments(datetime(2026,10,26,7,30,tzinfo=ZONE),1500,15,10)
        check('Smart departure 25min example', prepare.strftime('%H:%M')=='06:40' and depart.strftime('%H:%M')=='06:55')
        prepare2,depart2=moments(datetime(2026,10,26,7,30,tzinfo=ZONE),2400,15,10)
        check('ETA 25 to40 moves departure 15min earlier',(depart-depart2).total_seconds()==900)
        check('Preparation/departure events use clock policy','departure_due' in due_kinds(depart,datetime(2026,10,26,7,30,tzinfo=ZONE),prepare,depart,1500))
        check('14 days expense totals',sum(e['amount'] for e in expenses)==1000000 and len(expenses)==26)
        check('Completed vs skipped trips',len(completed)==18)
        check('Maintenance simulated odometer crosses user-defined threshold',odometer>old_due)

        prefs={'saved':json.dumps(places,ensure_ascii=False),'trips':json.dumps(trips,ensure_ascii=False),
            'journeys.v1':json.dumps({'version':1,'journeys':[{'id':journey_id,'name':'QA14 — Nhà ⇄ CMC [MÔ PHỎNG]',
                'category':'school','enabled':True,'outbound':trips[0],'inbound':trips[1]}],
                'expenses':expenses,'completed':completed},ensure_ascii=False),
            'garage.v1':json.dumps({'version':1,'vehicles':[{'id':vehicle_id,'name':'Wave Alpha 2024 • QA14',
                'model_id':'wave_alpha','year':2024,'variant':'Thường','odometer':odometer}],
                'items':[{'id':'qa14-next-oil','vehicle_id':vehicle_id,'name':'Kiểm tra xe QA14 [MÔ PHỎNG]',
                    'due_km':odometer+20,'due_date':(today+timedelta(days=3)).isoformat(),'source':'user_defined',
                    'notes':'Mốc tự đặt để test, không phải khuyến cáo của Honda'}], 'history':history},ensure_ascii=False),
            'onboarded':True,'default-vehicle':'motorcycle','historyEnabled':True,'history':['NHS Trung Văn','Đại học CMC cơ sở 2']}
        dataset={'simulation_only':True,'user_id':uid,'username':username,'date_from':days[0].isoformat(),
            'date_until':days[-1].isoformat(),'preferences':prefs,'ledger':ledger,
            'summary':{'days':14,'expenses_count':26,'fuel_vnd':700000,'parking_vnd':100000,
                'maintenance_vnd':200000,'total_vnd':1000000,'completed_trips':18,'skipped':1,'cancelled':1,
                'inbox_events':40,'maintenance_records':2,'final_odometer':odometer},
            'route_note':'Real snapshots captured today; not historical route or GPS evidence.'}
        def total_since(start):
            return sum(e['amount'] for e in expenses if start.isoformat() <= e['date'] <= today.isoformat())
        dataset['summary'].update(today_vnd=total_since(today),
            calendar_week_vnd=total_since(today-timedelta(days=today.weekday())),
            month_vnd=total_since(today.replace(day=1)),
            last_7_days_vnd=total_since(today-timedelta(days=6)),
            average_per_completed_trip_vnd=round(1000000/len(completed)), unread_events=1)
        check('Maintenance expenses share receipt IDs',
              all(h['id'] in {e['id'] for e in expenses} for h in history))
        (OUT/'dataset.json').write_text(json.dumps(dataset,ensure_ascii=False,indent=2),encoding='utf-8')
        with (OUT/'daily-ledger.csv').open('w',encoding='utf-8-sig',newline='') as file:
            writer=csv.DictWriter(file,fieldnames=ledger[0].keys());writer.writeheader();writer.writerows(ledger)
        (OUT/'results.json').write_text(json.dumps({'cases':cases,'summary':dataset['summary'],
            'limitations':['14 simulated days, not two weeks of real driving','No real device GPS or closed-app push tested',
                'Mobile local data requires explicit same-browser import','Exactly two live routing calls for real reference geometry']},ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'created_account':username,'case_count':len(cases),'passed':all(c['passed'] for c in cases),
                          'output':'build/reports/qa14','summary':dataset['summary']}))
    engine.dispose()


if __name__=='__main__':
    asyncio.run(main())

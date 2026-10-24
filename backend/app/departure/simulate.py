"""Offline accelerated scenarios, always in a fresh temporary simulation-only DB.

python -m app.departure.simulate --scenario all
No production configuration, HTTP client, credentials, or network are imported.
"""
import argparse
import asyncio
import json
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from types import SimpleNamespace
from sqlalchemy import select
from sqlalchemy.orm import Session
from fastapi import HTTPException
from app.database import Base, User, database_engine
from .models import Schedule, Occurrence, NotificationEvent
from .schemas import ScheduleInput
from .service import DepartureWorker
from .engine import ZONE


SCENARIOS = {
    'eta-increase': [1500, 2400], 'eta-decrease': [2400, 1500],
    'five-minutes': [1500], 'departure-now': [1500], 'late': [3600],
    'offline': [1500, 'offline'], 'restart': [900, 1500, 2400, 3600],
}


class SimulationRouting:
    def __init__(self, values):
        self.values, self.calls = list(values), 0

    async def calculate(self, request):
        self.calls += 1
        value = self.values.pop(0) if len(self.values) > 1 else self.values[0]
        if value == 'offline':
            raise HTTPException(503, 'Simulated offline')
        return [SimpleNamespace(duration_s=value, provider='SIMULATION_ONLY', traffic_aware=False)]


async def scenario(name):
    with tempfile.TemporaryDirectory(prefix='trafficgo-simulation-') as folder:
        engine = database_engine('sqlite:///' + (Path(folder) / 'simulation.db').as_posix())
        Base.metadata.create_all(engine)
        now = [datetime(2026, 10, 26, 6, 0, tzinfo=ZONE)]
        with Session(engine) as session:
            session.add(User(id='simulation'))
            session.commit()
            session.add(Schedule(user_id='simulation', data=ScheduleInput(
                name='SIMULATION ONLY', origin={'lat': 20.9834, 'lon': 105.7726},
                destination={'lat': 20.9893, 'lon': 105.7821}, arrival_time='07:30',
                weekdays=[0], initial_eta_s=1500).model_dump(mode='json')))
            session.commit()
        fake = SimulationRouting(SCENARIOS[name])
        worker = DepartureWorker(engine, fake, live_enabled=True, clock=lambda: now[0])
        times = [0, 30]
        if name == 'five-minutes': times = [50]
        if name == 'departure-now': times = [55]
        if name == 'late': times = [65]
        if name == 'restart': times = [0, 30, 50, 65]
        for minutes in times:
            now[0] = now[0].replace(hour=6, minute=0) + timedelta(minutes=minutes)
            await worker.tick()
            if name == 'restart':
                worker.release()
                engine.dispose()
                engine = database_engine('sqlite:///' + (Path(folder) / 'simulation.db').as_posix())
                worker = DepartureWorker(engine, fake, live_enabled=True, clock=lambda: now[0])
        with Session(engine) as session:
            row = session.scalar(select(Occurrence).where(Occurrence.arrival_date == '2026-10-26'))
            events = list(session.scalars(select(NotificationEvent.kind)))
            print(json.dumps({'scenario': name, 'SIMULATION_ONLY': True, 'routing_calls': fake.calls,
                'eta_s': row.data['eta_s'], 'prepare_at': row.data['prepare_at'],
                'departure_at': row.data['departure_at'], 'last_error': row.data['last_error'],
                'events': events}, ensure_ascii=True))
        worker.release()
        engine.dispose()


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', choices=['all', *SCENARIOS], default='all')
    name = parser.parse_args().scenario
    for selected in SCENARIOS if name == 'all' else [name]:
        await scenario(selected)


if __name__ == '__main__':
    asyncio.run(main())

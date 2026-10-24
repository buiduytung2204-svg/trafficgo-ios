"""Run ONE explicit worker: python -m app.departure.worker (from backend/)."""
import argparse
import asyncio
import logging
import httpx
from app.database import database_engine
from app.config import settings
from app.providers.routing import ValhallaRoutingProvider
from .service import DepartureWorker


async def run(once=False):
    engine = database_engine(settings.database_url)
    async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
        worker = DepartureWorker(engine, ValhallaRoutingProvider(client, settings.valhalla_base_url),
            live_enabled=settings.departure_live_routing_enabled,
            daily_limit=settings.departure_daily_routing_limit)
        try:
            while True:
                try:
                    leader = await worker.tick()
                    if not leader:
                        print('Another departure worker holds the lease; no processing.')
                    if once:
                        return
                except Exception as exc:
                    # No exception message: provider errors may contain secret URLs.
                    logging.error('departure_tick_failed type=%s', type(exc).__name__)
                    if once:
                        raise SystemExit(1) from None
                await asyncio.sleep(30)
        finally:
            worker.release()
            engine.dispose()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once', action='store_true')
    asyncio.run(run(parser.parse_args().once))

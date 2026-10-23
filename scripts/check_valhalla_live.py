"""Opt-in single-route smoke test through the local TrafficGo backend.

Run from the repository root with backend/.venv/Scripts/python.exe.
Consumes one real routing request. Never load-tests the public demo.
"""
import json
from datetime import datetime, timezone
from pathlib import Path
import sys
import time

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from app.config import Settings


def main():
    settings = Settings(_env_file=ROOT / 'backend' / '.env')
    start = time.perf_counter()
    response = httpx.post('http://127.0.0.1:8000/api/v1/routes/calculate',
        headers={'X-App-Token': settings.app_access_token}, timeout=15,
        json={'origin': {'lat':21.0285,'lon':105.8542},
              'destination': {'lat':21.018,'lon':105.835}, 'vehicle':'car'})
    if response.status_code != 200:
        raise SystemExit(f'Local route check failed: HTTP {response.status_code}')
    routes = response.json()['routes']
    assert routes, 'No route returned'
    for route in routes:
        assert route['provider']=='valhalla' and route['vehicle']=='car'
        assert route['traffic_aware'] is False and route['traffic_delay_s'] is None
        assert route['distance_m'] > 0 and route['duration_s'] > 0
        assert len(route['geometry']) >= 2
    report = {'checked_at':datetime.now(timezone.utc).isoformat(),
        'http_status':response.status_code, 'elapsed_ms':round((time.perf_counter()-start)*1000,1),
        'server_timing':response.headers.get('Server-Timing'),
        'routes':[{key:r[key] for key in ('provider','vehicle','distance_m','duration_s',
                                         'traffic_aware','traffic_delay_s')} |
                  {'points':len(r['geometry']),'instructions':len(r['instructions'])} for r in routes]}
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()

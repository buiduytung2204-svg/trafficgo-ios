"""Bounded development probe. Success does NOT certify Vietnamese road legality."""
import argparse
import json
import time
from pathlib import Path

import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='https://valhalla1.openstreetmap.de/route')
    parser.add_argument('--output', default='docs/motorcycle-probe.json')
    args = parser.parse_args()
    cases = [
        ('CMC2-NHS', (20.9834045, 105.7726713), (20.9893201, 105.7821709)),
        ('Hanoi-HoaLac', (21.012, 105.793), (21.004, 105.525)),
    ]
    results = []
    with httpx.Client(timeout=20) as client:
        for name, origin, destination in cases:
            for profile in ('auto', 'motor_scooter', 'motorcycle'):
                body = {'locations': [dict(zip(('lat', 'lon'), p)) for p in (origin, destination)],
                        'costing': profile, 'units': 'kilometers', 'language': 'en-US'}
                started = time.perf_counter()
                row = {'case': name, 'profile': profile}
                try:
                    response = client.post(args.url, json=body)
                    row['http_status'] = response.status_code
                    data = response.json()
                    trip = data.get('trip', {})
                    row.update(status=trip.get('status'), summary=trip.get('summary'),
                               error=data.get('error'),
                               road_names=sorted({s for leg in trip.get('legs', [])
                                                  for m in leg.get('maneuvers', [])
                                                  for s in m.get('street_names', [])}))
                except (httpx.HTTPError, ValueError) as exc:
                    row['error'] = type(exc).__name__
                row['latency_ms'] = round((time.perf_counter() - started) * 1000, 1)
                results.append(row)
                if row.get('http_status') == 429:
                    break
                time.sleep(1)
            if results[-1].get('http_status') == 429:
                break
    report = {'checked_at_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'scope': 'Six requests maximum; public demo; not a legality certification',
              'results': results}
    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=True, indent=2))


if __name__ == '__main__':
    main()

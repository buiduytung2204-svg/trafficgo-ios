# Valhalla development routing

The backend accepts native Valhalla JSON and decodes leg shapes at precision 6
(latitude, longitude), joins leg boundaries, normalizes instruction indices,
converts distances to metres and sorts up to three routes by duration.
The Flutter UI and TomTom map/search/traffic integration are unchanged.

In ignored `backend/.env`, select:

```dotenv
ROUTING_PROVIDER=valhalla
VALHALLA_URL=https://valhalla1.openstreetmap.de/route
ROUTING_FALLBACK_TO_TOMTOM=false
```

`VALHALLA_URL` accepts a base URL or full `/route` URL. Legacy
`VALHALLA_BASE_URL` remains supported; `VALHALLA_URL` wins when both exist.
Restart the backend after changing environment configuration.
No public demo URL is hardcoded as a code/production default.

This public endpoint is for development and occasional manual smoke tests.
It is operated by a third party; availability and quotas are not guaranteed.
Do not benchmark/load-test it or treat it as an unlimited production service.
Use an operator-owned service or a provider with agreed terms for production.
Route coordinates are sent to the configured service; the smoke test uses fixed
public locations, not the user's GPS. Preserve OpenStreetMap contributor
attribution when using OSM-derived routes.

Valhalla ETA is returned with `traffic_aware=false` and `traffic_delay_s=null`.
It is not derived from TomTom tiles or simulated congestion. Historical/default
speeds may be used by the server; no live-traffic capability is assumed.
Motorcycle is rejected with HTTP 422. Avoid-toll/highway flags are preferences,
not guarantees of strict exclusion. Instructions currently request English.
Departure-time requests disable alternatives as required by Valhalla.

Requests have a 10-second total deadline and no automatic retry. HTTP 429 is
preserved with Retry-After, other upstream failures normalize to 502, timeout
to 504, invalid/unconfigured endpoint to 503. Optional TomTom fallback is off;
when explicitly enabled it never bypasses an upstream 429.
Existing backend authentication/rate limiting still apply.

Run offline tests from `backend`: `.venv/Scripts/python.exe -m pytest -q`.
For one opt-in real request through a running local backend, from repository root:

```powershell
backend/.venv/Scripts/python.exe scripts/check_valhalla_live.py
```

References:
- https://valhalla.github.io/valhalla/api/route/api-reference/
- https://valhalla.github.io/valhalla/api/decoding/
- https://valhalla.openstreetmap.de/

Live check on 2026-10-23: direct native adapter returned one Hanoi car route,
3,714 metres, 718 seconds, 198 points, 16 instructions in 743.4 ms.
This is a single smoke result, not a latency benchmark or road-legality audit.

Local FastAPI smoke check also returned HTTP 200, the same normalized route,
backend total 853.058 ms and upstream 844.824 ms (client total 1,186.9 ms).
Only two calls were made to the public demo during this integration.

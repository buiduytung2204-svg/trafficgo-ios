# Geoapify search and quota control

Geoapify autocomplete is optional; `SEARCH_PROVIDER=tomtom` remains the source
default. Select `geoapify` locally only with a valid `GEOAPIFY_API_KEY` in ignored
backend/.env. The key is never sent to Flutter. No paid plan or hosting enabled.
Routing and traffic remain Valhalla and TomTom respectively.

## Local configuration

```dotenv
SEARCH_PROVIDER=geoapify
GEOAPIFY_API_KEY=
GEOAPIFY_DAILY_BUDGET=1000
GEOAPIFY_BUDGET_FILE=.geoapify-budget.db
```

- Minimum 3 characters, Flutter debounce 650 ms and cancellation of stale search.
- Daily limit 1,000 upstream attempts by default; persist in SQLite across restarts.
- Global app limit 2 attempts/second and 40/minute, transactional across workers
  sharing that SQLite file. Missing/corrupt counter fails closed.
- Counts/UTC date/timestamps only on disk; no key, search text or GPS history.
- RAM-only LRU cache: max 256 entries, 10 minutes for results, 30 seconds empty.
  Queries normalized for whitespace/case; proximity rounded to 2 decimals and
  the same coarse bias sent to provider. No persistent result cache.
- Identical in-flight queries coalesce; cache hits consume no provider attempt.
- Timeout 10 seconds, no retry, no automatic fallback to evade budget/429.
- Provider 429 pauses new requests until Retry-After; Flutter honors cooldown.
- Geoapify has its own budget, independent of TomTom tile/traffic budget.
- Near-identical same-name records within 45m deduplicated. Separate campuses
  remain separate. Result points are not verified entrances.

The Free plan currently advertises 3,000 credits/day, 5 requests/second;
autocomplete costs 1 credit/request. Our default guard leaves headroom but
does not know about requests made outside this backend, other APIs sharing the
account quota, other deployments with separate counter files or provider
changes. Verify dashboard usage; do not claim an account-wide spending lock.
Do not remove/reset the local budget database to bypass quota.
Deploy multiple instances only with a shared rate/budget store.

## Attribution and storage

Geoapify explicitly permits storing open-data results with retained attribution.
Responses preserve datasource metadata, and Flutter keeps attribution when
saving a place. Search results/selected map places/saved list show Geoapify and
OSM credit links. Any additional datasource credit is retained with the result.
No changes to TomTom tile caching or licensing are implied.

Official references checked 2026-10-23:
- https://www.geoapify.com/pricing/
- https://www.geoapify.com/pricing-details/
- https://www.geoapify.com/geocoding-api/ (FAQ on storing received results)
- https://www.geoapify.com/terms-and-conditions/
- https://apidocs.geoapify.com/docs/geocoding/

## Live checks

Two initial manual autocomplete calls (not a benchmark):

| Query | HTTP | Result | Client latency |
| --- | --- | --- | --- |
| NHS Trung Văn | 200 | Two same-name OSM records ~12m apart on Tố Hữu; normalized to one | 2,128ms |
| Trường Đại học CMC cơ sở 2 | 200 | Cơ sở 2, Tố Hữu; lat20.9834045/lon105.7726713 | 1,277ms |

Those two manual calls predate the new guard and are reserved in its initial
local counter before activation. The guard is a conservative attempt count,
not a statement of the provider's actual billing count.

Tests use mocked upstream responses and isolated temporary budget databases;
they must not consume real keys. Backend diagnostics expose only counters,
cache-hit/coalescing counts and latency/error metrics, not query/key/GPS.

Live through FastAPI after activation: NHS first request 2,337.0ms, identical
repeat 3.3ms (RAM hit), CMC campus 2 request 2,128.0ms; all HTTP200. Three
incoming search calls consumed two upstream attempts, cache-hit delta1.
Counter after the two initial manual probes and these two upstream calls: 4/1000.
These single observations are not a general latency benchmark.
Validation: 56 backend tests, 35 Flutter tests, analyze clean. APK build number3
succeeded (90.1s), apksigner v2 verifies with the same debug certificate.
Artifact: Documents/TrafficGo-android-test-v3.apk, 161.6MiB;
SHA256 082a09eaaaca421310e2b38b9cdbb7921292c03a3298fbb483f0455c9650bcd5.
Configured keys/tokens were checked absent from APK. No physical-device check
of the new search screen has been performed; install the update for attribution.

## Geoapify basemap web preview

Run the existing Flutter web app with `--dart-define=BASE_MAP_SOURCE=geoapify`
and `--dart-define=API_BASE_URL=http://localhost:8000`. This uses authenticated
`/api/v1/geo/tiles/{z}/{x}/{y}.png`, fixed `osm-carto` style; no key in the client.
Local preview: http://localhost:5173 (served from mobile/build/web-geo).
No new APK was built for this change. Existing APKs retain their TomTom basemap.

Shared `GEOAPIFY_DAILY_CREDITS=2000` caps search + tiles using integer quarter
credits (search4, tile1). Existing search counters migrate at four quarter units
per prior attempt without reset. The search-only 1000/day cap remains too.
Global pacing guard: max4 credits/sec, 200credits/min; search retains2/s,40/min.
Tile fetches paced at most ~6.7/s with3 concurrent upstream calls and bounded
pending requests. Rate counters persist across processes sharing this SQLite
file; app-level limits do not cover other uses of the account/key.

RAM tile cache max256 entries/32MiB, TTL from upstream max-age capped at1hour;
no-cache/no-store/private responses are not cached. No disk/offline tile cache.
Only successful PNGs cache, and in-flight same-tile calls coalesce. Provider
timeouts are not retried and provider429 pauses tile fetches. Cache hits are
free of new upstream attempts. Backend responses remain no-store to clients.

Geoapify mode disables TomTom Traffic even if the setting was previously on;
there is no simulated traffic substitute. TomTom code/keys remain available for
rollback until the user verifies this preview. No TomTom attribution API call
is needed in Geoapify mode. Geoapify/OSM credit links are visible; osm-carto is
excepted from OpenMapTiles attribution per the official map-tiles docs:
https://apidocs.geoapify.com/docs/maps/map-tiles/

Live CMC-area PNG check: two identical backend calls HTTP200, only0.25 credit
increment, RAM hit1, and no TomTom metric categories in that process. PNG
visually inspected; served web index/bootstrap/main JS all HTTP200, Geoapify
proxy route present and configured secrets absent from JS. Full interactive
browser rendering has not been checked by automation; user will compare maps.

### Transient tile recovery in the web client

User screenshot showed grey holes and a timeout banner. Live diagnostics:
106 Geoapify map attempts, 3 errors, 0 rate-limited, provider p95 852.581ms;
backend 110 requests/3 errors. Individual timeout failures therefore left holes
despite most tiles succeeding. No claim that the network outage is eliminated.

The tile client now recovers HTTP502/504 only for `/api/v1/geo/tiles/`, with
one delayed retry (500ms) per request. Both attempts are measured and upstream
misses count toward the same budget. No retry for429, TomTom, or cancellation.
The abort trigger is retained; closing the screen or cancelling the viewport
before retry prevents the extra request. A recovered tile does not emit a stale
failure banner. No full-layer reload/camera reset is used for this recovery.
Persistent failures still surface normally. Web output: build/web-geo-recovery.

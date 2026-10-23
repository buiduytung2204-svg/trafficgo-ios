# Motorcycle routing development check

Checked 2026-10-24 (Asia/Ho_Chi_Minh). Raw bounded live results:
`motorcycle-probe.json`. Reproduce with
`backend/.venv/Scripts/python.exe scripts/check_motorcycle_live.py`.
The probe makes at most six sequential public-demo requests, no retries,
and stops on HTTP 429. No API keys or personal GPS are used.

## Results

All six requests returned HTTP 200 and trip status 0.

| Case | Profile | Distance km | ETA min | has_highway |
| --- | --- | ---: | ---: | --- |
| CMC campus 2 - NHS Trung Van | auto | 1.428 | 4.58 | false |
| CMC campus 2 - NHS Trung Van | motor_scooter | 1.428 | 4.85 | false |
| CMC campus 2 - NHS Trung Van | motorcycle | 1.428 | 4.58 | false |
| Hanoi - Hoa Lac probe | auto | 31.055 | 39.45 | true |
| Hanoi - Hoa Lac probe | motor_scooter | 30.662 | 75.25 | false |
| Hanoi - Hoa Lac probe | motorcycle | 31.020 | 74.52 | false |

The car response names CT.03; neither two-wheeler response does. Both
two-wheeler responses name Dai lo Thang Long, which is insufficient to
distinguish every service-road segment from its parallel carriageways.
`has_highway=false` is a provider classification, not certification of
legal motorcycle access.

## Decision

2026-10-24: Following the user's field testing and request, the UI now presents
motorcycle as a regular vehicle option without a beta label. This is a product
label change; it does not establish comprehensive verification of Vietnamese
road restrictions. The non-live-traffic ETA notice and actual-signs reminder
remain. The routing profile and no-car-fallback policy are unchanged.

Update: the user authorized an experimental coursework mode after reviewing
these limitations. Valhalla now maps `vehicle=motorcycle` to `motor_scooter`;
the UI labels it experimental and reminds users to follow actual signs.
This supersedes the disabled-mode decision below, not the validation findings.
TomTom continues to reject motorcycle requests, and fallback to car routing
is explicitly prohibited for motorcycle requests. Vehicle selection clears
old routes and is locked during navigation or route calculation.

Keep the application's motorcycle mode disabled. The live demo accepts
both profiles and produces different routes, but these two examples do
not verify all Vietnamese restrictions, elevated sections, one-way streets,
time-dependent restrictions or the demo's map-build configuration/version.
No realtime traffic was supplied for these ETAs.

Before enabling, inspect route geometry against OSM edge access tags and
current local restrictions for a reviewed set of known prohibited and
allowed roads, including elevated Ring Road 3 and parallel frontage roads.
Review actual motorcycle class: `motor_scooter` and `motorcycle` are not
interchangeable simply because both accept requests.

Official reference:
https://github.com/valhalla/valhalla/blob/master/docs/docs/api/route/api-reference.md
The reference distinguishes both profiles and explicitly states that
`use_highways=0` is only a preference, not an absolute exclusion. Do not
use that setting alone as a Vietnamese motorcycle legality guarantee.

Application routing and UI remain unchanged. This probe is development
validation, not a production-service availability or safety guarantee.

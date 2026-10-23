# Place search spot check — 2026-10-23 (Asia/Saigon)

User-selected places: NHS Trung Văn and CMC University campus 2.
No provider configuration or production search source changed in this check.
Geoapify was subsequently tested with the user's locally configured key and
passed both places; see GEOAPIFY.md for separate API results and quota checks.
LocationIQ has not been tested. Photon results below are independent evidence.

## Live Photon demo results

Endpoint: `https://photon.komoot.io/api/`, limit 5, Hanoi bias
lat=21.0285/lon=105.8542, bbox=105.2,20.5,106.3,21.6.
Five manual requests total, sequential with a pause between the first four;
no load testing and no application integration against the demo.

| Query | HTTP | Observed result | Coordinate (lat, lon) |
| --- | --- | --- | --- |
| NHS Trung Văn | 200 | Nhà ở xã hội NHS Trung Văn, Phố Tố Hữu, Đại Mỗ, Hà Nội; OSM way 1389555313 | 20.9893201, 105.7821709 |
| Đại học CMC | 200 | Three campuses returned; campus 2 is Trường Đại học CMC (Cơ sở 2), Phố Tố Hữu, Vạn Phúc, Hà Đông; OSM node 13058303799 | 20.9834045, 105.7726713 |
| CMC University | 200 | Empty result | — |
| Vạn Phúc Building Tố Hữu | 200 | Vạn Phúc Building, Phố Tố Hữu, Vạn Phúc, Hà Đông; OSM way 1416268918 | 20.9833104, 105.7727238 |
| Trường Đại học CMC cơ sở 2 | 200 | One result: Trường Đại học CMC (Cơ sở 2), Phố Tố Hữu | 20.9834045, 105.7726713 |

The first four measured round trips were 917, 291, 513, 355 ms respectively.
These are single spot checks, not p50/p95 performance measurements.
Returned points identify mapped features, not verified navigable entrances.
School campus address matches the school's official admissions page:
https://tuyensinh.cmcu.edu.vn/hanoi (Vạn Phúc Building, Tố Hữu, Hà Đông).
NHS identity/address is reported by Photon/OSM; an independent entrance survey
was not performed. Results are not evidence of Geoapify or LocationIQ coverage.

## Constraints and next step

Photon's official README permits reasonable demo use, may throttle/ban heavy
use, and provides no availability guarantee:
https://github.com/komoot/photon#demo-server

OSM-derived data attribution: © OpenStreetMap contributors; ODbL.
https://www.openstreetmap.org/copyright

Photon passes discovery of these two Vietnamese queries, but the English
query fails. This is insufficient to decide general Hanoi coverage or switch
the production provider. Before integration, test ranking, spelling variants,
rate controls and service terms with an operator-owned or agreed endpoint.
Geoapify is now selected in the ignored local backend environment, with separate
quota protection and required attribution in APK build3. No keys in source.

# Traffic-aware routing

HTTP routing and the explicit Windows departure worker now share a provider
factory. Geoapify maps/search and saved route selection are unchanged.

Default remains Valhalla. Optional configuration:

```
ROUTING_PROVIDER=tomtom
TOMTOM_ROUTING_LICENSE_CONFIRMED=true
TOMTOM_MOTORCYCLE_VIETNAM_VERIFIED=false
```

Use the existing backend-only TOMTOM_API_KEY; never put it in Flutter or Git.
Do not enable the licence flag merely because a request succeeds. Verify the
account agreement permits Geoapify map display, saved geometry, short-lived
request coalescing/cache and navigation. The public legal landing page did not
provide enough evidence to establish these rights during this review.
No environment credentials or live provider switches were changed.

TomTom requests use traffic=true, routeType=fastest, up to two alternatives,
computeTravelTimeFor=all and a vehicle-specific travelMode. The adapter returns
the provider's trafficDelayInSeconds directly; missing values remain null.
Never subtract Valhalla ETA from TomTom ETA or infer delay from tile colours.
Traffic-aware estimates are not guaranteed actual arrival times.

Motorcycle stays on Valhalla until Vietnam-specific restrictions are verified.
The explicit verification flag is available for future verified deployments;
automated tests exercise it with mock responses only. Car mode is never used
as a substitute for motorcycle mode. Fallback routes carry an explicit reason
and retain traffic_aware=false.

Existing limits remain 96 interactive requests/day and 24 worker requests/day
unless separately configured. Each TomTom routing calculation now makes at most
one upstream attempt; 429 and Retry-After propagate without hidden retries or
provider switching. These are local limits, not a claim about account quota.
The existing interactive coalescing/cache remains unchanged and must be included
in the licence review before opting in. The worker's live-routing opt-in remains.

Restart backend and the single explicit worker after a verified configuration
change. Do not start another worker. No traffic tile overlay is enabled here.
The UI already displays normalized ETA/delay and requires confirmation for
alternative route proposals; saved routes are not overwritten by this factory.

## Verification

`cd backend` then `.venv\Scripts\python -m pytest -q`.
Tests cover licence guard, motorcycle fallback, each travelMode, exact delay
normalization and a single request on 429. They consume no provider quota.
Live coverage, map licensing and real motorcycle legality are not established
by mock tests.

Official references reviewed 2026-10-24:

- https://docs.tomtom.com/routing-api/documentation/tomtom-maps/v1/calculate-route
- https://docs.tomtom.com/routing-api/documentation/tomtom-maps/v1/product-information/market-coverage
- https://docs.tomtom.com/legal/terms-and-conditions

Market coverage lists Vietnam routing/traffic but does not separately certify
Vietnam motorcycle access rules. Public documentation is insufficient to turn
that verification flag on automatically.

## Local experimental activation — 2026-10-24
User explicitly opted into TomTom motorcycle beta. Local config now selects
TomTom, enables TOMTOM_MOTORCYCLE_EXPERIMENTAL_ENABLED and leaves
TOMTOM_MOTORCYCLE_VIETNAM_VERIFIED=false. The existing licence confirmation gate
was acknowledged for this local experiment; this is user acceptance, not an
independent legal certification of account rights. No paid plan was enabled.

One real, budget-counted motorcycle request returned three routes:
8083 m / 1487 s / delay 0 s; 5511 m / 1508 s / delay 84 s;
7060 m / 1645 s / delay 123 s. These are provider estimates, not ground-truth
validation. Backend and explicit worker restarted; health reports tomtom.
Map route preview displays the motorcycle beta warning. Traffic tiles remain
disabled; this activation changes route ETA, not the congestion overlay.

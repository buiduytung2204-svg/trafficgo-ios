import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class Place {
  final String name;
  final LatLng point;
  const Place(this.name, this.point);
  factory Place.fromJson(Map<String, dynamic> j) => Place(
    j['name'] as String,
    LatLng(
      (j['coordinate']['lat'] as num).toDouble(),
      (j['coordinate']['lon'] as num).toDouble(),
    ),
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'coordinate': {'lat': point.latitude, 'lon': point.longitude},
  };
}

class SavedTrip {
  final String name;
  final Place origin, destination;
  const SavedTrip(this.name, this.origin, this.destination);
  Map<String, dynamic> toJson() => {
    'name': name,
    'origin': origin.toJson(),
    'destination': destination.toJson(),
  };
  factory SavedTrip.fromJson(Map<String, dynamic> j) => SavedTrip(
    j['name'],
    Place.fromJson(j['origin']),
    Place.fromJson(j['destination']),
  );
}

class TravelRoute {
  final String id;
  final int meters, seconds;
  final int? delay;
  final List<LatLng> points;
  final List<dynamic> instructions;
  final DateTime retrievedAt;
  final String provider;
  final bool trafficAware;
  final String? fallbackReason;
  const TravelRoute({
    required this.id,
    required this.meters,
    required this.seconds,
    required this.points,
    required this.retrievedAt,
    this.delay,
    this.instructions = const [],
    this.provider = 'tomtom',
    this.trafficAware = true,
    this.fallbackReason,
  });
  factory TravelRoute.fromJson(Map<String, dynamic> j) => TravelRoute(
    id: j['id'],
    meters: j['distance_m'],
    seconds: j['duration_s'],
    delay: j['traffic_delay_s'],
    points: (j['geometry'] as List)
        .map(
          (p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lon'] as num).toDouble(),
          ),
        )
        .toList(),
    instructions: j['instructions'] as List? ?? [],
    retrievedAt: DateTime.parse(j['retrieved_at']),
    provider: j['provider'] ?? 'tomtom',
    trafficAware: j['traffic_aware'] ?? true,
    fallbackReason: j['fallback_reason'],
  );
}

String formatEta(int seconds) {
  final minutes = (seconds / 60).ceil();
  return minutes < 60
      ? '$minutes phút'
      : '${minutes ~/ 60} giờ ${minutes % 60} phút';
}

List<TravelRoute> fastestRoutes(List<TravelRoute> routes) =>
    [...routes]..sort((a, b) => a.seconds.compareTo(b.seconds));

bool shouldSuggest(int oldSeconds, int newSeconds, Duration sinceLast) =>
    sinceLast >= const Duration(minutes: 5) &&
    oldSeconds > newSeconds &&
    (oldSeconds - newSeconds > 180 ||
        (oldSeconds - newSeconds) / oldSeconds > .15);

// Distance to polyline segments in a local tangent plane, sufficient for Hanoi.
double distanceToRoute(LatLng point, List<LatLng> route) {
  if (route.isEmpty) return double.infinity;
  final scale = math.cos(point.latitude * math.pi / 180);
  double x(LatLng p) => (p.longitude - point.longitude) * 111320 * scale;
  double y(LatLng p) => (p.latitude - point.latitude) * 111320;
  double best = const Distance().as(LengthUnit.Meter, point, route.first);
  for (var i = 1; i < route.length; i++) {
    final ax = x(route[i - 1]), ay = y(route[i - 1]);
    final dx = x(route[i]) - ax, dy = y(route[i]) - ay;
    final denominator = dx * dx + dy * dy;
    final t = denominator == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / denominator).clamp(0.0, 1.0);
    best = math.min(
      best,
      math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
    );
  }
  return best;
}

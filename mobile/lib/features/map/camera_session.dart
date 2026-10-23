import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Current viewport only, in memory. Never writes location history to disk.
final cameraSessionProvider = Provider((ref) => CameraSession());

class CameraSession {
  LatLng center = const LatLng(21.0285, 105.8542);
  double zoom = 13, rotation = 0;
  bool following = false;
  int gestureRevision = 0;

  void update(
    LatLng center,
    double zoom,
    double rotation, {
    required bool gesture,
  }) {
    this.center = center;
    this.zoom = zoom;
    this.rotation = rotation;
    if (gesture) {
      gestureRevision++;
      following = false;
    }
  }
}

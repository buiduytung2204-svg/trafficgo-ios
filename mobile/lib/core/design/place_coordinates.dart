import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Read-only coordinates for the selected place; never a GPS history.
class PlaceCoordinates extends StatelessWidget {
  final LatLng point;
  const PlaceCoordinates({super.key, required this.point});

  @override
  Widget build(BuildContext context) => SelectableText(
    'Vĩ độ: ${point.latitude.toStringAsFixed(6)}°\n'
    'Kinh độ: ${point.longitude.toStringAsFixed(6)}°',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

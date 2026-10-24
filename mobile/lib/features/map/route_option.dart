import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/design/components.dart';

class RouteOption extends StatelessWidget {
  final TravelRoute route;
  final bool selected, fastest;
  final VoidCallback? onTap;
  const RouteOption({
    super.key,
    required this.route,
    required this.selected,
    required this.fastest,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final arrival = DateTime.now().add(Duration(seconds: route.seconds));
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: TrafficMotion.duration(context),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: selected
                  ? color.primaryContainer.withValues(alpha: .5)
                  : color.surface,
            ),
            child: TrafficCard(
              selected: selected,
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        selected ? Icons.check_circle : Icons.radio_button_off,
                        color: selected ? color.primary : color.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${formatEta(route.seconds)} • ${(route.meters / 1000).toStringAsFixed(1)} km',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (selected) const Text('Đang chọn'),
                      if (fastest) const Text('Nhanh nhất theo ETA'),
                      Text(
                        'Đến khoảng ${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    route.trafficAware
                        ? 'Chậm do giao thông: ${route.delay == null ? 'chưa có dữ liệu' : formatEta(route.delay!)}'
                        : 'Thời gian ước tính chưa xét giao thông trực tiếp',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/state.dart';
import '../../core/design/components.dart';
import '../../core/design/traffic_theme.dart';
import '../../core/models.dart';
import '../onboarding/accounts.dart';
import '../departure/controller.dart';
import '../departure/models.dart';
import '../departure/screens.dart';
import '../journeys/store.dart';
import '../journeys/place_picker.dart';
import '../settings/screens.dart';
import 'map_screen.dart';

SavedTrip? _scheduleTrip(WidgetRef ref, CommuteSchedule? next) {
  if (next == null) return null;
  final data = next.json;
  final journey = ref
      .watch(journeysProvider)
      .journeys
      .where((j) => j.id == data['journey_id'])
      .firstOrNull;
  final trip = data['direction'] == 'inbound'
      ? journey?.inbound
      : journey?.outbound;
  return trip != null &&
          trip.vehicle == data['vehicle'] &&
          trip.origin.point.latitude == data['origin']?['lat'] &&
          trip.origin.point.longitude == data['origin']?['lon'] &&
          trip.destination.point.latitude == data['destination']?['lat'] &&
          trip.destination.point.longitude == data['destination']?['lon']
      ? trip
      : null;
}

/// Reparent the same map between overview and full workspace, preserving camera.
class HomeOverview extends ConsumerStatefulWidget {
  const HomeOverview({super.key});
  @override
  ConsumerState<HomeOverview> createState() => _HomeOverviewState();
}

class _HomeOverviewState extends ConsumerState<HomeOverview> {
  final mapKey = GlobalKey(debugLabel: 'overview-retained-map');
  bool expanded = false;
  bool picking = false;
  Place? destination;
  void expand([Place? place]) => setState(() {
    expanded = true;
    if (place != null) destination = place;
  });
  Future<void> search() async {
    if (picking) return;
    picking = true;
    try {
      final place = await pickPlace(context, title: 'Tìm điểm đến');
      if (mounted && place != null) expand(place);
    } finally {
      picking = false;
    }
  }

  Future<void> shortcut(String category) async {
    if (picking) return;
    final place = ref
        .read(stateProvider)
        .saved
        .where((p) => p.category == category)
        .firstOrNull;
    if (place != null) {
      expand(place);
      return;
    }
    picking = true;
    try {
      final chosen = await pickPlace(context, title: 'Thêm địa điểm');
      if (!mounted || chosen == null) return;
      await editSavedPlace(
        context,
        ref,
        Place(
          chosen.name,
          chosen.point,
          category: category,
          address: chosen.address,
          provider: chosen.provider,
          sourceAttribution: chosen.sourceAttribution,
        ),
      );
    } finally {
      picking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final account = ref.watch(accountProvider).account;
    final nickname =
        account?['profile']?['nickname'] ??
        account?['profile']?['display_name'] ??
        account?['username'];
    final departure = ref.watch(departureProvider);
    departure.localNotifications.onOpen = () {
      if (mounted) context.push('/departure-notifications');
    };
    final next = departure.next;
    final trip = _scheduleTrip(ref, next);
    final map = MapScreen(
      key: mapKey,
      compact: !expanded,
      onExpand: expand,
      onCancelSearch: () => setState(() {
        expanded = false;
        destination = null;
      }),
      initialDestination: destination,
      plannedTrip: trip,
    );
    if (expanded) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => expanded = false);
        },
        child: map,
      );
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              textScaler: TextScaler.linear(
                                MediaQuery.textScalerOf(context)
                                    .scale(1)
                                    .clamp(1.0, 1.35),
                              ),
                              maxLines: 1,
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'Traffic'),
                                  TextSpan(
                                    text: 'Go',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? TrafficTokens.lime
                                          : const Color(0xff668b22),
                                    ),
                                  ),
                                ],
                              ),
                              style: const TextStyle(
                                fontSize: 28,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Thông báo',
                            onPressed: () =>
                                context.push('/departure-notifications'),
                            icon: const Icon(Icons.notifications_none_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        nickname == null || nickname.toString().trim().isEmpty
                            ? 'Chào bạn 👋'
                            : 'Chào $nickname 👋',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontSize: 28, letterSpacing: -.8),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hôm nay mình đi đâu?',
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TrafficPress(
                        child: Material(
                          color: colors.surface,
                          shape: StadiumBorder(
                            side: BorderSide(color: colors.outlineVariant),
                          ),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: search,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Tìm điểm đến',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          for (final item in [
                            ('home', 'Nhà', Icons.home_rounded),
                            ('school', 'Trường', Icons.school_rounded),
                            ('work', 'Công ty', Icons.work_rounded),
                          ]) ...[
                            if (item.$1 != 'home') const SizedBox(width: 10),
                            Expanded(
                              child: TrafficPress(
                                child: Material(
                                  color: colors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => shortcut(item.$1),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            item.$3,
                                            size: 32,
                                            color: colors.onSurface,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            item.$2,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      LimeDepartureCard(
                        onEmpty: () => context.push('/schedules'),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(height: 290, child: map),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LimeDepartureCard extends ConsumerWidget {
  final VoidCallback onEmpty;
  const LimeDepartureCard({super.key, required this.onEmpty});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(departureProvider);
    final next = controller.next;
    final trip = _scheduleTrip(ref, next);
    final departure = parseInstant(next?.occurrence?['departure_at']);
    final eta = next?.occurrence?['eta_s'];
    final facts = [
      if (eta != null) formatEta(eta),
      if (trip?.route != null)
        '${(trip!.route!.meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
    ].join(' · ');
    return TrafficEntrance(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [TrafficTokens.limeBright, Color(0xffbceb66)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: TrafficTokens.fontFamily,
              fontFamilyFallback: TrafficTokens.fontFallback,
              fontWeight: FontWeight.w500,
              color: Color(0xff171c24),
              fontSize: 14,
              height: 1.3,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CHUYẾN TIẾP THEO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      next == null
                          ? 'Sẵn sàng cho ngày mới?'
                          : next.json['destination_name']
                                    ?.toString()
                                    .isNotEmpty ==
                                true
                          ? next.json['destination_name']
                          : next.name,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (next != null) ...[
                      Text(
                        departure == null
                            ? 'Chờ ETA'
                            : vietnamTime(next.occurrence?['departure_at'])
                                  .split(' ')
                                  .last,
                        style: TextStyle(
                          fontSize: departure == null ? 26 : 52,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: -2,
                        ),
                      ),
                      const Text('Giờ xuất phát'),
                      const SizedBox(height: 6),
                      Text(
                        facts.isEmpty ? 'Chưa có ước tính' : facts,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text('Thêm lịch nhắc để biết giờ nên xuất phát.'),
                    ],
                  ],
                );
                final action = Theme(
                  data: TrafficTokens.material(Brightness.light),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TrafficPrimaryButton(
                      onPressed: next == null
                          ? onEmpty
                          : () => openCommuteRoute(context, next.json),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              next == null ? 'Tạo lịch' : 'Xem tuyến',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (narrow) ...[
                      text,
                      const SizedBox(height: 14),
                      action,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(flex: 3, child: text),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                const ExcludeSemantics(
                                  child: SizedBox(
                                    height: 80,
                                    child: CampusIllustration(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                action,
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (next != null &&
                        (!controller.online ||
                            next.occurrence?['traffic_aware'] != true)) ...[
                      const SizedBox(height: 10),
                      Text(
                        !controller.online
                            ? 'Bản lưu · Chưa đồng bộ'
                            : 'ETA chưa xét giao thông trực tiếp',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff3e4c30),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Original code-native artwork, independent of the reference image's assets.
class CampusIllustration extends StatelessWidget {
  const CampusIllustration({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(130, 80), painter: _CampusPainter());
}

class _CampusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 130, size.height / 80);
    final paint = Paint();
    void rect(double x, double y, double w, double h, Color c) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(1.5),
        ),
        paint..color = c,
      );
    }

    rect(18, 28, 34, 45, const Color(0xff8dbe58));
    rect(49, 9, 38, 64, const Color(0xff9ccc60));
    canvas.drawPath(
      Path()
        ..moveTo(87, 9)
        ..lineTo(110, 22)
        ..lineTo(110, 73)
        ..lineTo(87, 73)
        ..close(),
      paint..color = const Color(0xff78a84b),
    );
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 3; col++) {
        rect(54 + col * 10.0, 17 + row * 10.0, 5, 6, const Color(0xff477647));
      }
    }
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 2; col++) {
        rect(23 + col * 12.0, 35 + row * 11.0, 6, 7, const Color(0xff527e45));
      }
    }
    rect(66, 57, 13, 16, const Color(0xff375e3d));
    for (final x in [12.0, 115.0]) {
      rect(x, 54, 3, 20, const Color(0xff365b38));
      canvas.drawOval(
        Rect.fromLTWH(x - 7, 43, 18, 23),
        paint..color = const Color(0xff4c8545),
      );
      canvas.drawOval(
        Rect.fromLTWH(x - 4, 36, 12, 19),
        paint..color = const Color(0xff639a4c),
      );
    }
    rect(2, 74, 125, 4, const Color(0xffeffcce));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampusPainter oldDelegate) => false;
}

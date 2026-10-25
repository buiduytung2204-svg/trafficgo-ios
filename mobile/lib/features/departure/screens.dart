import 'day_exception.dart';
import '../../core/design/sheets.dart';
import '../../core/design/components.dart';
import '../journeys/store.dart';
import '../map/map_screen.dart';
import '../journeys/place_picker.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/state.dart';
import '../../core/models.dart';
import 'controller.dart';
import 'models.dart';

void openCommuteRoute(
  BuildContext context,
  Map<String, dynamic> data, {
  bool startNavigation = false,
}) {
  final store = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(journeysProvider);
  final journey = store.journeys
      .where((j) => j.id == data['journey_id'])
      .firstOrNull;
  final trip = data['direction'] == 'inbound'
      ? journey?.inbound
      : journey?.outbound;
  if (trip != null &&
      trip.vehicle == data['vehicle'] &&
      trip.origin.point.latitude == data['origin']?['lat'] &&
      trip.origin.point.longitude == data['origin']?['lon'] &&
      trip.destination.point.latitude == data['destination']?['lat'] &&
      trip.destination.point.longitude == data['destination']?['lon']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          autoStartNavigation: startNavigation,
          plannedTrip: trip,
          plannedVehicle: trip.vehicle,
          journeyId: journey!.id,
          direction: data['direction'],
          occurrenceId: data['occurrence']?['id'],
        ),
      ),
    );
    return;
  }

  context.push(
    '/commute-route',
    extra: {
      'trip': SavedTrip(
        data['name'] ?? data['schedule_name'] ?? 'Lịch đi lại',
        Place.fromJson({
          'name': data['origin_name'] ?? 'Xuất phát',
          'coordinate': data['origin'],
        }),
        Place.fromJson({
          'name': data['destination_name'] ?? 'Điểm đến',
          'coordinate': data['destination'],
        }),
      ),
      'vehicle': data['vehicle'] ?? 'car',
      'journey_id': data['journey_id'],
      'direction': data['direction'],
      'occurrence_id': data['occurrence']?['id'],
      'start_navigation': startNavigation,
    },
  );
}

class NextDepartureCard extends ConsumerStatefulWidget {
  const NextDepartureCard({super.key});
  @override
  ConsumerState<NextDepartureCard> createState() => _NextDepartureCardState();
}

class _NextDepartureCardState extends ConsumerState<NextDepartureCard> {
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(departureProvider);
    controller.localNotifications.onOpen = () {
      if (mounted) context.push('/departure-notifications');
    };
    final next = controller.next;
    final departure = parseInstant(next?.occurrence?['departure_at']);
    if (next == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EmptyPanel(
            icon: Icons.alarm_add_rounded,
            title: 'Lịch nhắc giờ xuất phát',
            message: 'Thêm giờ đến. TrafficGo tính giờ chuẩn bị và xuất phát cho bạn.',
          ),
          TextButton.icon(
            onPressed: () => context.push('/schedules'),
            icon: const Icon(Icons.add_alarm),
            label: const Text('Tạo lịch nhắc đầu tiên'),
          ),
        ],
      );
    }
    final journey = ref
        .watch(journeysProvider)
        .journeys
        .where((j) => j.id == next.json['journey_id'])
        .firstOrNull;
    final purpose = journey?.category == 'school'
        ? 'Đi học'
        : journey?.category == 'work'
        ? 'Đi làm'
        : 'Chuyến tiếp theo';
    final colors = Theme.of(context).colorScheme;
    final eta = next.occurrence?['eta_s'];
    return TrafficEntrance(
      child: TrafficCard(
        color: colors.primaryContainer.withValues(alpha: .58),
        accent: colors.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    journey?.category == 'school'
                        ? Icons.school_rounded
                        : Icons.route_rounded,
                    size: 18,
                  ),
                  label: Text(purpose),
                ),
                Text(
                  next.json['direction'] == 'inbound' ? 'Chiều về' : 'Chiều đi',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              next.json['destination_name']?.toString().isNotEmpty == true
                  ? next.json['destination_name']
                  : next.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            const Text('Xuất phát lúc'),
            Text(
              departure == null
                  ? 'Đang chờ ETA'
                  : vietnamTime(next.occurrence?['departure_at'])
                        .split(' ')
                        .last,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -1.5,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              departure == null
                  ? 'Chưa có thời gian xuất phát'
                  : departureCountdown(departure, DateTime.now()),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('Cần đến ${vietnamTime(next.occurrence?['arrival_at'])}'),
                Text('ETA: ${eta == null ? 'Chưa có' : formatEta(eta)}'),
              ],
            ),
            const SizedBox(height: 16),
            TrafficPrimaryButton.icon(
              onPressed: () => openCommuteRoute(context, next.json),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Mở tuyến hành trình tiếp theo'),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                controller.online ? 'Đã đồng bộ' : 'Mất kết nối • bản lưu',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                Text(
                  controller.workerAlive
                      ? 'Cập nhật tự động đang hoạt động'
                      : 'Cập nhật tự động đang tạm ngưng',
                ),
                if (next.occurrence?['traffic_aware'] != true)
                  const Text('ETA chưa xét giao thông trực tiếp.'),
                TextButton(
                  onPressed: () => context.push('/schedules'),
                  child: const Text('Quản lý lịch nhắc'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SchedulesScreen extends ConsumerWidget {
  const SchedulesScreen({super.key});
  Future<void> action(
    BuildContext context,
    Future<void> Function() work,
  ) async {
    try {
      await work();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chưa lưu được. Kiểm tra kết nối backend rồi thử lại.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(departureProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch đi học / đi làm'),
        actions: [
          IconButton(
            tooltip: 'Lịch sử thông báo',
            icon: Badge(
              isLabelVisible: controller.events.any((e) => e['read'] != true),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => context.push('/departure-notifications'),
          ),
          IconButton(
            tooltip: 'Đồng bộ',
            onPressed: controller.busy ? null : controller.refresh,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: !controller.online
            ? null
            : () => showTrafficEditor<void>(context, const ScheduleEditor()),
        icon: const Icon(Icons.add),
        label: const Text('Tạo lịch'),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (controller.busy) const LinearProgressIndicator(),
            Text(
              controller.online
                  ? 'Đã đồng bộ với backend Windows'
                  : 'Chưa kết nối • chỉ xem bản lưu',
              style: TextStyle(
                color: controller.online
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            Text(
              'Đồng bộ gần nhất: ${vietnamTime(controller.syncedAt?.toIso8601String())}',
            ),
            Text(
              controller.workerAlive
                  ? 'Worker đang hoạt động'
                  : 'Worker chưa chạy hoặc mất heartbeat',
            ),
            const SectionHeading(
              title: 'Đúng giờ, bớt vội',
              subtitle: 'Tách rõ giờ chuẩn bị, giờ xuất phát và giờ cần đến.',
              icon: Icons.alarm,
            ),
            if (controller.error != null) Text(controller.error!),
            if (!controller.online)
              TrafficPrimaryButton.icon(
                onPressed: controller.busy ? null : controller.connect,
                icon: const Icon(Icons.link),
                label: const Text('Kết nối lịch nhắc'),
              ),
            const Text(
              'Múi giờ: Việt Nam (UTC+7). Android/iOS có thể nhắc cục bộ theo lịch đã đồng bộ khi được cấp quyền. Mở app để nhận ETA mới; chưa có push từ server.',
            ),
            const SizedBox(height: 12),
            if (controller.schedules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Chưa có lịch. Lưu một tuyến hoặc hai địa điểm, rồi tạo lịch nhắc.',
                ),
              ),
            for (final schedule in controller.schedules)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              schedule.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Switch(
                            value: schedule.enabled,
                            onChanged: !controller.online
                                ? null
                                : (value) => action(
                                    context,
                                    () => controller.save({
                                      ...schedule.input(),
                                      'enabled': value,
                                    }, schedule.id),
                                  ),
                          ),
                        ],
                      ),
                      Text(
                        '${schedule.json['origin_name']} → ${schedule.json['destination_name']}',
                      ),
                      Text(
                        '${schedule.json['vehicle'] == 'motorcycle' ? 'Xe máy' : 'Ô tô'} • Đến ${schedule.json['arrival_time']}',
                      ),
                      Text(
                        schedule.json['one_off_date'] != null
                            ? 'Một lần: ${schedule.json['one_off_date']}'
                            : 'Lặp: ${(schedule.json['weekdays'] as List).map((d) => ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][d]).join(', ')}',
                      ),
                      if ((schedule.json['day_exceptions'] as List? ?? [])
                          .isNotEmpty)
                        ExpansionTile(
                          title: const Text('Ngoại lệ đã lưu'),
                          children: [
                            for (final exception
                                in schedule.json['day_exceptions'])
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${exception['arrival_date']} • ${statusLabel(exception['status'])}',
                                ),
                                subtitle: Text(
                                  'Giờ cần đến: ${vietnamTime(exception['arrival_at'])}',
                                ),
                              ),
                          ],
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.event_note),
                        label: const Text('Nghỉ / đổi giờ một ngày'),
                        onPressed: !controller.online
                            ? null
                            : () => showTrafficSheet(
                                context,
                                title: 'Ngoại lệ lịch lặp',
                                builder: (_) =>
                                    DayExceptionEditor(schedule: schedule),
                              ),
                      ),
                      if (schedule.occurrence case final occurrence?) ...[
                        Text('Ngày chuyến: ${occurrence['arrival_date']}'),
                        if ((occurrence['day_override'] as Map?)?.isNotEmpty ==
                            true)
                          const Text('Có thay đổi riêng cho ngày này'),
                        Text(
                          'ETA: ${occurrence['eta_s'] == null ? 'Chưa có' : '${((occurrence['eta_s'] as num) / 60).ceil()} phút'}'
                          ' • ${occurrence['eta_source'] == 'initial_estimate' ? 'Ước tính bạn nhập' : occurrence['eta_source'] ?? 'Chờ routing'}',
                        ),
                        Text(
                          'Chuẩn bị: ${vietnamTime(occurrence['prepare_at'])}',
                        ),
                        Text(
                          'Xuất phát: ${vietnamTime(occurrence['departure_at'])}',
                        ),
                        Text(
                          'Cập nhật ETA: ${vietnamTime(occurrence['eta_updated_at'])}',
                        ),
                        Text(
                          'Trạng thái: ${statusLabel(occurrence['status'])}',
                        ),
                        if (occurrence['eta_basis'] ==
                            'fastest_available_route')
                          const Text(
                            'ETA tuyến khả dụng nhanh nhất; không thay geometry tuyến đã lưu.',
                          ),
                        if (occurrence['traffic_aware'] != true)
                          const Text('ETA chưa tính traffic realtime'),
                        if (occurrence['last_error'] != null)
                          const Text(
                            'Routing lỗi; giữ ETA cũ, có thể đã lỗi thời.',
                          ),
                        if (occurrence['status'] == 'planned' ||
                            occurrence['status'] == 'in_progress')
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: !controller.online
                                    ? null
                                    : () => action(
                                        context,
                                        () => controller.mutate(
                                          'PATCH',
                                          'occurrences/${occurrence['id']}',
                                          {'status': 'skipped'},
                                        ),
                                      ),
                                child: const Text('Bỏ qua chuyến'),
                              ),
                              TextButton(
                                onPressed: !controller.online
                                    ? null
                                    : () => action(context, () async {
                                        await controller.mutate(
                                          'PATCH',
                                          'occurrences/${occurrence['id']}',
                                          {'status': 'completed'},
                                        );
                                        final store = ref.read(
                                          journeysProvider,
                                        );
                                        final journey = store.journeys
                                            .where(
                                              (j) =>
                                                  j.id ==
                                                  schedule.json['journey_id'],
                                            )
                                            .firstOrNull;
                                        final trip =
                                            schedule.json['direction'] ==
                                                'inbound'
                                            ? journey?.inbound
                                            : journey?.outbound;
                                        if (trip != null) {
                                          await store.complete(
                                            occurrence['id'],
                                            trip: trip,
                                            journeyId: journey!.id,
                                            direction:
                                                schedule.json['direction'],
                                          );
                                        }
                                      }),
                                child: const Text('Đã hoàn thành'),
                              ),
                            ],
                          ),
                      ],
                      Wrap(
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                openCommuteRoute(context, schedule.json),
                            icon: const Icon(Icons.route),
                            label: const Text('Mở tuyến'),
                          ),
                          TextButton(
                            onPressed: !controller.online
                                ? null
                                : () => showTrafficEditor<void>(
                                    context,
                                    ScheduleEditor(schedule: schedule),
                                  ),
                            child: const Text('Sửa'),
                          ),
                          TextButton(
                            onPressed: !controller.online
                                ? null
                                : () async {
                                    final yes = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text(
                                          'Xóa lịch và thông báo liên quan?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Hủy'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Xóa'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (yes == true && context.mounted) {
                                      await action(
                                        context,
                                        () => controller.mutate(
                                          'DELETE',
                                          'schedules/${schedule.id}',
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Xóa'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.localNotifications.supported)
              OutlinedButton.icon(
                onPressed: () => action(context, () async {
                  final ok = await controller.localNotifications.enable(() {
                    if (context.mounted) {
                      context.push('/departure-notifications');
                    }
                  });
                  if (ok) {
                    await controller.localNotifications.reconcile(
                      controller.schedules,
                    );
                    controller.changed();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Đã bật nhắc cục bộ theo lịch đã đồng bộ. Thay đổi ETA khi app đóng cần đồng bộ lại.'
                              : 'Chưa được cấp quyền thông báo.',
                        ),
                      ),
                    );
                  }
                }),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Cho phép thông báo trên thiết bị'),
              ),
            if (controller.localNotifications.supported &&
                controller.notificationWarning != null)
              Text(
                controller.notificationWarning!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (controller.localNotifications.supported &&
                controller.localNotifications.enabled) ...[
              Text(
                controller.notificationWarning ??
                    'Đã hẹn ${controller.localNotifications.localCount} mốc trên thiết bị${controller.localNotifications.localHorizon == null ? '' : ' đến ${vietnamTime(controller.localNotifications.localHorizon!.toIso8601String())}'}. Cần mở app để nhận ETA/lịch mới; chưa có push từ server.',
              ),
              TextButton(
                onPressed: () => action(context, () async {
                  await controller.localNotifications.testDelivery();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã hẹn kiểm tra sau 1 phút. Hãy khóa màn hình để thử. Focus hoặc cài đặt iOS có thể hạn chế hiển thị.',
                        ),
                      ),
                    );
                  }
                }),
                child: const Text('Thử thông báo sau 1 phút'),
              ),
              TextButton(
                onPressed: () => action(context, () async {
                  await controller.localNotifications.prefs.setBool(
                    '${controller.prefix}departure-local-notifications',
                    false,
                  );
                  await controller.localNotifications.clearScope();
                  controller.changed();
                }),
                child: const Text('Tắt nhắc trên thiết bị'),
              ),
            ],
            if (controller.online)
              TextButton(
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text(
                        'Xóa toàn bộ dữ liệu lịch nhắc trên thiết bị này?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Hủy'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Xóa dữ liệu'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true && context.mounted) {
                    await action(context, controller.eraseRemote);
                  }
                },
                child: const Text('Xóa dữ liệu lịch nhắc của tôi'),
              ),
          ],
        ),
      ),
    );
  }
}

String statusLabel(dynamic status) =>
    const {
      'planned': 'Sắp diễn ra',
      'in_progress': 'Đang di chuyển',
      'completed': 'Đã hoàn thành',
      'skipped': 'Đã bỏ qua',
      'cancelled': 'Đã hủy',
      'missed': 'Đã qua giờ đến',
    }[status] ??
    '$status';

class DepartureNotificationsScreen extends ConsumerWidget {
  const DepartureNotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(departureProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử thông báo')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              controller.online
                  ? 'Hộp thư đã đồng bộ'
                  : 'Mất kết nối • bản lưu',
            ),
            if (controller.events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Chưa có thông báo.'),
              ),
            for (final event in controller.events)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        event['read'] == true
                            ? Icons.drafts_outlined
                            : Icons.markunread_outlined,
                      ),
                      title: Text(event['title']),
                      subtitle: Text(
                        "${event['schedule_name']}\n${vietnamTime(event['created_at'])}${event['arrival_date'] == null ? '' : ' • Chuyến ${event['arrival_date']}'}",
                      ),
                      isThreeLine: true,
                      onTap: () async {
                        if (controller.online) {
                          try {
                            await controller.mutate(
                              'PATCH',
                              'notifications/${event['id']}/read',
                            );
                          } catch (_) {
                            /* Stay unread on failure. */
                          }
                        }
                        if (context.mounted) {
                          openCommuteRoute(context, {
                            ...Map<String, dynamic>.from(event['route']),
                            'name': event['schedule_name'],
                            'occurrence': {'id': event['occurrence_id']},
                          });
                        }
                      },
                      trailing: const Icon(Icons.route),
                    ),
                    if (event['cancelled'] != true &&
                        event['action_result'] == null &&
                        (parseInstant(event['scheduled_for'])
                                ?.isAfter(DateTime.now()) !=
                            true))
                      Wrap(
                        children: [
                          for (final entry in const {
                            'start': 'Xuất phát',
                            'snooze': 'Nhắc lại sau 5 phút',
                            'skip': 'Bỏ qua hôm nay',
                          }.entries)
                            TextButton(
                              onPressed:
                                  !controller.online ||
                                      controller.notificationActions.contains(
                                        event['id'],
                                      )
                                  ? null
                                  : () => handleDepartureNotification(
                                      context,
                                      controller,
                                      event['id'],
                                      entry.key,
                                    ),
                              child: Text(entry.value),
                            ),
                        ],
                      ),
                    if (event['action_result'] != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          const {
                                'start': 'Đã xuất phát',
                                'skip': 'Đã bỏ qua ngày này',
                                'snooze': 'Đã hẹn nhắc lại sau 5 phút',
                              }[event['action_result']] ??
                              'Đã xử lý',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ScheduleEditor extends ConsumerStatefulWidget {
  final CommuteSchedule? schedule;
  final SavedTrip? seedTrip;
  final String? journeyId, direction;
  const ScheduleEditor({
    super.key,
    this.schedule,
    this.seedTrip,
    this.journeyId,
    this.direction,
  });
  @override
  ConsumerState<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends ConsumerState<ScheduleEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  Set<int> weekdays = {0, 1, 2, 3, 4};
  String vehicle = 'car', arrival = '07:30', routeName = '';
  DateTime? oneOff;
  bool enabled = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final j = widget.schedule?.json ?? {};
    for (final key in [
      'name',
      'origin_name',
      'destination_name',
      'olat',
      'olon',
      'dlat',
      'dlon',
      'prep',
      'buffer',
      'eta',
    ]) {
      fields[key] = TextEditingController();
    }
    fields['name']!.text = j['name'] ?? '';
    fields['origin_name']!.text = j['origin_name'] ?? '';
    fields['destination_name']!.text = j['destination_name'] ?? '';
    fields['olat']!.text = '${j['origin']?['lat'] ?? ''}';
    fields['olon']!.text = '${j['origin']?['lon'] ?? ''}';
    fields['dlat']!.text = '${j['destination']?['lat'] ?? ''}';
    fields['dlon']!.text = '${j['destination']?['lon'] ?? ''}';
    fields['prep']!.text = '${j['preparation_minutes'] ?? 15}';
    fields['buffer']!.text = '${j['buffer_minutes'] ?? 10}';
    fields['eta']!.text = j['initial_eta_s'] == null
        ? ''
        : '${((j['initial_eta_s'] as num) / 60).round()}';
    weekdays = ((j['weekdays'] ?? [0, 1, 2, 3, 4]) as List).cast<int>().toSet();
    arrival = j['arrival_time'] ?? arrival;
    vehicle = j['vehicle'] ?? vehicle;
    enabled = j['enabled'] ?? true;
    routeName = j['route_name'] ?? '';
    oneOff = parseInstant(j['one_off_date']);
    final seed = widget.seedTrip;
    if (seed != null) {
      place('o', seed.origin);
      place('d', seed.destination);
      fields['name']!.text = seed.name;
      routeName = seed.name;
      vehicle = seed.vehicle;
      fields['eta']!.text = seed.route == null
          ? ''
          : '${(seed.route!.seconds / 60).ceil()}';
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void place(String prefix, Place place) {
    fields[prefix == 'o' ? 'origin_name' : 'destination_name']!.text =
        place.name;
    fields['${prefix}lat']!.text = '${place.point.latitude}';
    fields['${prefix}lon']!.text = '${place.point.longitude}';
  }

  Widget field(
    String key,
    String label, {
    double? min,
    double? max,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      controller: fields[key],
      decoration: InputDecoration(labelText: label),
      keyboardType: min == null
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        final value = text?.trim() ?? '';
        if (optional && value.isEmpty) return null;
        if (value.isEmpty) return 'Vui lòng nhập';
        if (min == null) return value.length > 100 ? 'Tối đa 100 ký tự' : null;
        final n = double.tryParse(value);
        return n == null ||
                !n.isFinite ||
                n < min ||
                n > max! ||
                (['prep', 'buffer', 'eta'].contains(key) &&
                    n != n.roundToDouble())
            ? 'Giá trị $min–$max'
            : null;
      },
    ),
  );
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (fields['olat']!.text.isEmpty || fields['dlat']!.text.isEmpty) {
      setState(() => error = 'Chọn điểm xuất phát và điểm đến.');
      return;
    }
    if (oneOff == null && weekdays.isEmpty) {
      setState(() => error = 'Chọn ít nhất một ngày lặp.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'name': fields['name']!.text.trim(),
        'route_name': routeName,
        'journey_id': widget.journeyId ?? widget.schedule?.json['journey_id'],
        'direction': widget.direction ?? widget.schedule?.json['direction'],
        'saved_route_id': widget.schedule?.json['saved_route_id'],
        'origin': {
          'lat': double.parse(fields['olat']!.text),
          'lon': double.parse(fields['olon']!.text),
        },
        'destination': {
          'lat': double.parse(fields['dlat']!.text),
          'lon': double.parse(fields['dlon']!.text),
        },
        'origin_name': fields['origin_name']!.text.trim(),
        'destination_name': fields['destination_name']!.text.trim(),
        'vehicle': vehicle,
        'arrival_time': arrival,
        'weekdays': weekdays.toList()..sort(),
        'one_off_date': oneOff?.toIso8601String().split('T').first,
        'preparation_minutes': int.parse(fields['prep']!.text),
        'buffer_minutes': int.parse(fields['buffer']!.text),
        'initial_eta_s': fields['eta']!.text.isEmpty
            ? null
            : int.parse(fields['eta']!.text) * 60,
        'enabled': enabled,
      };
      await ref.read(departureProvider).save(body, widget.schedule?.id);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Chưa lưu được lịch. Kiểm tra backend và dữ liệu.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stateProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.schedule == null ? 'Tạo lịch nhắc' : 'Sửa lịch nhắc',
        ),
      ),
      body: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!ref.watch(departureProvider).online)
                ListTile(
                  title: const Text('Chưa đồng bộ backend'),
                  trailing: TextButton(
                    onPressed: () => ref.read(departureProvider).connect(),
                    child: const Text('Kết nối'),
                  ),
                ),
              if (state.trips.isNotEmpty)
                DropdownButtonFormField<SavedTrip>(
                  decoration: const InputDecoration(
                    labelText: 'Lấy từ tuyến đã lưu',
                  ),
                  isExpanded: true,
                  items: state.trips
                      .map(
                        (trip) => DropdownMenuItem(
                          value: trip,
                          child: Text(trip.name),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (trip) {
                          if (trip != null) {
                            setState(() {
                              place('o', trip.origin);
                              place('d', trip.destination);
                              routeName = trip.name;
                              if (fields['name']!.text.isEmpty) {
                                fields['name']!.text = trip.name;
                              }
                            });
                          }
                        },
                ),
              field('name', 'Tên lịch'),
              for (final prefix in ['o', 'd'])
                ListTile(
                  leading: Icon(
                    prefix == 'o' ? Icons.trip_origin : Icons.location_on,
                  ),
                  title: Text(
                    fields[prefix == 'o' ? 'origin_name' : 'destination_name']!
                            .text
                            .isEmpty
                        ? (prefix == 'o'
                              ? 'Chọn điểm xuất phát'
                              : 'Chọn điểm đến')
                        : fields[prefix == 'o'
                                  ? 'origin_name'
                                  : 'destination_name']!
                              .text,
                  ),
                  trailing: const Icon(Icons.search),
                  onTap: saving
                      ? null
                      : () async {
                          final p = await pickPlace(context);
                          if (p != null && mounted) {
                            setState(() => place(prefix, p));
                          }
                        },
                ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'car', label: Text('Ô tô')),
                  ButtonSegment(value: 'motorcycle', label: Text('Xe máy')),
                ],
                selected: {vehicle},
                onSelectionChanged: saving
                    ? null
                    : (v) => setState(() => vehicle = v.first),
              ),
              ListTile(
                title: const Text('Giờ cần đến (Việt Nam)'),
                subtitle: Text(arrival),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final parts = arrival.split(':').map(int.parse).toList();
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
                  );
                  if (selected != null && mounted) {
                    setState(
                      () => arrival =
                          '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                    );
                  }
                },
              ),
              SwitchListTile(
                title: const Text('Chỉ nhắc một ngày'),
                value: oneOff != null,
                onChanged: saving
                    ? null
                    : (value) => setState(
                        () => oneOff = value ? DateTime.now() : null,
                      ),
              ),
              if (oneOff != null)
                TextButton(
                  onPressed: () async {
                    final day = await pickTrafficDate(
                      context,
                      initialDate: oneOff!,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (day != null && mounted) setState(() => oneOff = day);
                  },
                  child: Text(
                    'Ngày: ${oneOff!.toIso8601String().split('T').first}',
                  ),
                ),
              if (oneOff == null)
                Wrap(
                  spacing: 6,
                  children: [
                    for (var day = 0; day < 7; day++)
                      FilterChip(
                        label: Text(
                          ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][day],
                        ),
                        selected: weekdays.contains(day),
                        onSelected: saving
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  weekdays.add(day);
                                } else {
                                  weekdays.remove(day);
                                }
                              }),
                      ),
                  ],
                ),
              field('prep', 'Thời gian chuẩn bị (phút)', min: 0, max: 180),
              field('buffer', 'Thời gian dự phòng (phút)', min: 0, max: 180),
              field(
                'eta',
                'ETA ban đầu bạn ước tính (phút, tùy chọn)',
                min: 1,
                max: 240,
                optional: true,
              ),
              const Text(
                'ETA nhập tay được ghi rõ là ước tính. Worker cập nhật Valhalla trong khung trước chuyến đi; không phải traffic realtime.',
              ),
              SwitchListTile(
                title: const Text('Bật lịch'),
                value: enabled,
                onChanged: saving ? null : (v) => setState(() => enabled = v),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TrafficPrimaryButton(
                onPressed: saving ? null : submit,
                child: Text(saving ? 'Đang lưu…' : 'Lưu và đồng bộ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> handleDepartureNotification(
  BuildContext context,
  DepartureController controller,
  String eventId,
  String actionId,
) async {
  try {
    final event = actionId == 'open'
        ? await controller.notificationEvent(eventId)
        : await controller.notificationAction(eventId, actionId);
    if (!context.mounted || controller.disposed) return;
    if (actionId == 'open' || actionId == 'start') {
      if (event['cached'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đang mở tuyến từ bản lưu; chưa kiểm tra được thay đổi lịch trên backend.',
            ),
          ),
        );
      }
      openCommuteRoute(context, {
        ...Map<String, dynamic>.from(event['route']),
        'name': event['schedule_name'],
        'occurrence': {'id': event['occurrence_id']},
      }, startNavigation: actionId == 'start');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            actionId == 'snooze'
                ? (controller.notificationWarning ??
                      'Đã hẹn nhắc lại sau 5 phút; giờ xuất phát không thay đổi.')
                : 'Đã bỏ qua ngày của chuyến này.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(departureError(e))));
    }
  }
}

/// Bind once above all home tabs; notification taps survive tab changes and cold start.
class DepartureNotificationBridge extends ConsumerWidget {
  final Widget child;
  const DepartureNotificationBridge({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(departureProvider);
    final intent = controller.pendingNotification;
    if (intent != null) {
      controller.pendingNotification = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && !controller.disposed) {
          handleDepartureNotification(
            context,
            controller,
            intent['event_id'],
            intent['action'],
          );
        }
      });
    }
    return child;
  }
}

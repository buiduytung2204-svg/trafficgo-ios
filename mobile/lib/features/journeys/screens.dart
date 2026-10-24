import '../../core/design/components.dart';
import '../../core/design/sheets.dart';
import 'expense_chart.dart';
import '../../app/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../map/map_screen.dart';
import '../departure/screens.dart';
import '../departure/controller.dart';
import 'place_picker.dart';
import 'store.dart';

void notifyError(BuildContext c, Object e) {
  if (c.mounted) {
    ScaffoldMessenger.of(
      c,
    ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
  }
}

class JourneysScreen extends ConsumerWidget {
  const JourneysScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(journeysProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hành trình hằng ngày'),
        actions: [
          IconButton(
            tooltip: 'Chi phí và thống kê',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpensesScreen()),
            ),
            icon: const Icon(Icons.bar_chart),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await editText(context, 'Tên hành trình');
          if (name == null || name.isEmpty) return;
          final j = Journey(id: newId(), name: name);
          try {
            await store.saveJourney(j);
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => JourneyDetail(id: j.id)),
              );
            }
          } catch (e) {
            if (context.mounted) notifyError(context, e);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Thêm hành trình'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        children: [
          const SectionHeading(
            title: 'Đi lại theo cách của bạn',
            subtitle:
                'Tuyến đã chọn, hai chiều độc lập và lịch nhắc hằng ngày.',
            icon: Icons.route,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.alarm, size: 18),
                label: const Text('Lịch nhắc'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SchedulesScreen()),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Chi phí'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                ),
              ),
            ],
          ),
          const NextDepartureCard(),
          if (store.loadError != null) Text(store.loadError!),
          if (store.journeys.isEmpty)
            const EmptyPanel(
              icon: Icons.route,
              title: 'Chưa có hành trình',
              message: 'Tạo hành trình và chọn riêng tuyến chiều đi, chiều về.',
            ),
          for (final j in store.journeys)
            Card(
              child: ListTile(
                leading: Icon(
                  j.category == 'school'
                      ? Icons.school
                      : j.category == 'work'
                      ? Icons.work
                      : Icons.route,
                ),
                title: Text(j.name),
                subtitle: Text(
                  '${j.enabled ? 'Đang hoạt động' : 'Tạm dừng'} • ${j.outbound == null ? 'Chưa có chiều đi' : 'Có chiều đi'} • ${j.inbound == null ? 'Chưa có chiều về' : 'Có chiều về'}',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => JourneyDetail(id: j.id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<String?> editText(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final c = TextEditingController(text: initial);
  final result = await showTrafficSheet<String>(
    context,
    title: title,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: c,
          maxLength: 100,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên hiển thị'),
        ),
        const SizedBox(height: 16),
        TrafficButton(
          label: 'Lưu',
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
        ),
      ],
    ),
  );
  // Dialog route still animates while pop completes; defer disposing its controller.
  Future.delayed(const Duration(seconds: 1), c.dispose);
  return result;
}

class JourneyDetail extends ConsumerWidget {
  final String id;
  const JourneyDetail({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(journeysProvider);
    final matches = store.journeys.where((j) => j.id == id);
    if (matches.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Hành trình đã xóa')));
    }
    final j = matches.first;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(j.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chiều đi'),
              Tab(text: 'Chiều về'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Đổi tên',
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final name = await editText(
                  context,
                  'Tên hành trình',
                  initial: j.name,
                );
                if (name != null && name.isNotEmpty) {
                  await store.saveJourney(j.copy(name: name));
                }
              },
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  DropdownButton<String>(
                    value: j.category,
                    items: const [
                      DropdownMenuItem(value: 'school', child: Text('Đi học')),
                      DropdownMenuItem(value: 'work', child: Text('Đi làm')),
                      DropdownMenuItem(
                        value: 'personal',
                        child: Text('Cá nhân'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) store.saveJourney(j.copy(category: v));
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Hành trình hoạt động'),
                    subtitle: const Text(
                      'Tạm dừng cũng tắt các lịch nhắc đã liên kết; bật lại lịch trong mục Lịch nhắc.',
                    ),
                    value: j.enabled,
                    onChanged: (v) async {
                      try {
                        final controller = ref.read(departureProvider);
                        if (!v && controller.credential.isNotEmpty) {
                          await controller.refresh();
                          if (!controller.online) {
                            throw StateError(
                              'Cần kết nối backend để tắt lịch nhắc.',
                            );
                          }
                          for (final s in controller.schedules.where(
                            (s) => s.json['journey_id'] == id && s.enabled,
                          )) {
                            await controller.save({
                              ...s.input(),
                              'enabled': false,
                            }, s.id);
                          }
                        }
                        await store.saveJourney(j.copy(enabled: v));
                      } catch (e) {
                        if (context.mounted) notifyError(context, e);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              for (final outbound in [true, false])
                Builder(
                  builder: (context) {
                    final trip = outbound ? j.outbound : j.inbound;
                    final direction = outbound ? 'outbound' : 'inbound';
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (trip == null)
                          const Text(
                            'Chưa chọn tuyến. Chiều về phải được tính riêng theo quy tắc đường một chiều.',
                          )
                        else ...[
                          Text(
                            '${trip.origin.name} → ${trip.destination.name}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (trip.route != null)
                            Text(
                              '${formatEta(trip.route!.seconds)} • ${(trip.route!.meters / 1000).toStringAsFixed(1)} km\nETA tham khảo lúc ${trip.route!.retrievedAt.toLocal()}\n${trip.route!.trafficAware ? 'ETA có traffic' : 'ETA routing, không có traffic realtime'}',
                            ),
                          TrafficPrimaryButton.icon(
                            onPressed: j.enabled
                                ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MapScreen(
                                        plannedTrip: trip,
                                        plannedVehicle: trip.vehicle,
                                        journeyId: id,
                                        direction: direction,
                                      ),
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.navigation),
                            label: const Text('Mở đúng tuyến đã lưu'),
                          ),
                          OutlinedButton.icon(
                            onPressed: j.enabled
                                ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ScheduleEditor(
                                        seedTrip: trip,
                                        journeyId: id,
                                        direction: direction,
                                      ),
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.alarm),
                            label: const Text(
                              'Thiết lập lịch nhắc cho chiều này',
                            ),
                          ),
                          TextButton(
                            onPressed: () => editExpense(
                              context,
                              ref,
                              journeyId: id,
                              direction: direction,
                            ),
                            child: const Text('Thêm chi phí'),
                          ),
                        ],
                        OutlinedButton(
                          onPressed: () async {
                            final picked = await Navigator.push<SavedTrip>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoutePlanner(
                                  initial: trip,
                                  name:
                                      '${j.name} • ${outbound ? 'Chiều đi' : 'Chiều về'}',
                                ),
                              ),
                            );
                            if (picked != null) {
                              final latest = store.journeys
                                  .where((v) => v.id == id)
                                  .firstOrNull;
                              if (latest != null) {
                                final controller = ref.read(departureProvider);
                                final linked = controller.schedules
                                    .where(
                                      (s) =>
                                          s.json['journey_id'] == id &&
                                          s.json['direction'] == direction,
                                    )
                                    .toList();
                                if (linked.isNotEmpty && !controller.online) {
                                  if (context.mounted) {
                                    notifyError(
                                      context,
                                      StateError(
                                        'Kết nối backend trước khi đổi tuyến đang có lịch nhắc.',
                                      ),
                                    );
                                  }
                                  return;
                                }
                                try {
                                  for (final schedule in linked) {
                                    await controller.save({
                                      ...schedule.input(),
                                      'origin': picked.origin
                                          .toJson()['coordinate'],
                                      'destination': picked.destination
                                          .toJson()['coordinate'],
                                      'origin_name': picked.origin.name,
                                      'destination_name':
                                          picked.destination.name,
                                      'vehicle': picked.vehicle,
                                      'route_name': picked.name,
                                      'initial_eta_s': picked.route?.seconds,
                                    }, schedule.id);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    notifyError(context, e);
                                  }
                                  return;
                                }
                                await store.saveJourney(
                                  outbound
                                      ? latest.copy(outbound: picked)
                                      : latest.copy(inbound: picked),
                                );
                              }
                            }
                          },
                          child: Text(
                            trip == null
                                ? 'Tìm và chọn tuyến'
                                : 'Chỉnh sửa tuyến / cập nhật ETA',
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SchedulesScreen(),
                            ),
                          ),
                          child: const Text('Quản lý lịch nhắc'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text(
                                  'Xóa hành trình và tắt lịch nhắc liên quan?',
                                ),
                                content: const Text(
                                  'Lịch sử chuyến và khoản chi được giữ lại.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Xóa'),
                                  ),
                                ],
                              ),
                            );
                            if (yes != true) return;
                            try {
                              final controller = ref.read(departureProvider);
                              if (controller.credential.isNotEmpty) {
                                await controller.refresh();
                              }
                              if (controller.credential.isNotEmpty &&
                                  !controller.online) {
                                throw StateError(
                                  'Cần kết nối backend để xử lý lịch nhắc.',
                                );
                              }
                              for (final s in controller.schedules.where(
                                (s) => s.json['journey_id'] == id,
                              )) {
                                await controller.mutate(
                                  'DELETE',
                                  'schedules/${s.id}',
                                );
                              }
                              await store.deleteJourney(id);
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) notifyError(context, e);
                            }
                          },
                          child: const Text('Xóa hành trình'),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoutePlanner extends ConsumerStatefulWidget {
  final SavedTrip? initial;
  final String name;
  const RoutePlanner({
    super.key,
    this.initial,
    this.name = 'Tuyến thường dùng',
  });
  @override
  ConsumerState<RoutePlanner> createState() => _RoutePlannerState();
}

class _RoutePlannerState extends ConsumerState<RoutePlanner> {
  Place? origin, destination;
  String vehicle = 'car';
  List<TravelRoute> routes = [];
  int selected = 0;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    origin = widget.initial?.origin;
    destination = widget.initial?.destination;
    vehicle = widget.initial?.vehicle ?? 'car';
    if (widget.initial?.route != null) routes = [widget.initial!.route!];
  }

  Future<void> calculate() async {
    if (origin == null || destination == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(apiProvider)
          .routes(origin!.point, destination!, vehicle: vehicle);
      if (mounted) {
        setState(() {
          if (result.isNotEmpty) {
            routes = result;
            selected = 0;
          } else {
            error = 'Không có tuyến phù hợp. Giữ tuyến tham khảo cũ nếu có.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '${errorMessage(e)} • Giữ tuyến cũ nếu có.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  SavedTrip get trip => SavedTrip(
    widget.name == 'Tuyến thường dùng'
        ? '${origin!.name} → ${destination!.name}'
        : widget.name,
    origin!,
    destination!,
    vehicle: vehicle,
    route: routes[selected],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tìm và chọn lộ trình')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeading(
          title: 'Bạn muốn đi đâu?',
          subtitle: 'Chọn điểm đi, điểm đến rồi so sánh các tuyến thực tế.',
          icon: Icons.alt_route,
        ),
        for (final isOrigin in [true, false])
          ListTile(
            leading: Icon(isOrigin ? Icons.trip_origin : Icons.place),
            title: Text(
              (isOrigin ? origin : destination)?.name ??
                  (isOrigin ? 'Chọn điểm xuất phát' : 'Chọn điểm đến'),
            ),
            trailing: const Icon(Icons.search),
            onTap: busy
                ? null
                : () async {
                    final p = await pickPlace(context);
                    if (p != null && mounted) {
                      setState(() {
                        if (isOrigin) {
                          origin = p;
                        } else {
                          destination = p;
                        }
                        routes = [];
                      });
                    }
                  },
          ),
        TextButton.icon(
          onPressed: busy
              ? null
              : () => setState(() {
                  final p = origin;
                  origin = destination;
                  destination = p;
                  routes = [];
                }),
          icon: const Icon(Icons.swap_vert),
          label: const Text('Đảo hai điểm • tính tuyến mới'),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'car', label: Text('Ô tô')),
            ButtonSegment(value: 'motorcycle', label: Text('Xe máy')),
          ],
          selected: {vehicle},
          onSelectionChanged: busy
              ? null
              : (v) => setState(() {
                  vehicle = v.first;
                  routes = [];
                }),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (busy) const LinearProgressIndicator(),
        TrafficPrimaryButton(
          onPressed: busy || origin == null || destination == null
              ? null
              : calculate,
          child: const Text('Tìm tuyến / cập nhật ETA'),
        ),
        for (var i = 0; i < routes.length; i++)
          ListTile(
            leading: Icon(
              i == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(
              '${formatEta(routes[i].seconds)} • ${(routes[i].meters / 1000).toStringAsFixed(1)} km',
            ),
            subtitle: Text(
              '${routes[i].provider} • ${routes[i].trafficAware ? 'Có traffic' : 'Không có traffic realtime'}\nCập nhật ${routes[i].retrievedAt.toLocal()}',
            ),
            onTap: busy ? null : () => setState(() => selected = i),
          ),
        if (routes.isNotEmpty) ...[
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MapScreen(plannedTrip: trip, plannedVehicle: vehicle),
              ),
            ),
            child: const Text('Xem tuyến đã chọn trên bản đồ'),
          ),
          TrafficPrimaryButton(
            onPressed: busy ? null : () => Navigator.pop(context, trip),
            child: const Text('Lưu chính xác tuyến đã chọn'),
          ),
        ],
      ],
    ),
  );
}

Future<void> editExpense(
  BuildContext context,
  WidgetRef ref, {
  Expense? existing,
  String? journeyId,
  String? direction,
}) async {
  await showTrafficEditor<void>(
    context,
    ExpenseEditor(
      existing: existing,
      journeyId: journeyId,
      direction: direction,
    ),
  );
}

class ExpenseEditor extends ConsumerStatefulWidget {
  final Expense? existing;
  final String? journeyId, direction;
  const ExpenseEditor({
    super.key,
    this.existing,
    this.journeyId,
    this.direction,
  });
  @override
  ConsumerState<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends ConsumerState<ExpenseEditor> {
  final amount = TextEditingController(), notes = TextEditingController();
  String category = 'fuel';
  String? journeyId, direction;
  DateTime date = DateTime.now();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    amount.text = e == null ? '' : '${e.amount}';
    notes.text = e?.notes ?? '';
    category = e?.category ?? 'fuel';
    journeyId = e?.journeyId ?? widget.journeyId;
    direction = e?.direction ?? widget.direction;
    if (e != null) date = DateTime.parse(e.date);
  }

  @override
  void dispose() {
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(journeysProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Khoản chi thực tế')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Số tiền (VND)'),
          ),
          DropdownButton<String>(
            isExpanded: true,
            value: category,
            items: expenseTypes.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => category = v!),
          ),
          ListTile(
            title: Text('Ngày: ${date.toIso8601String().split('T').first}'),
            onTap: () async {
              final d = await pickTrafficDate(
                context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (d != null) setState(() => date = d);
            },
          ),
          DropdownButton<String>(
            isExpanded: true,
            value: store.journeys.any((j) => j.id == journeyId)
                ? journeyId
                : '',
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Không gắn hành trình'),
              ),
              for (final j in store.journeys)
                DropdownMenuItem(
                  value: j.id,
                  child: Tooltip(
                    message: j.name,
                    child: Text(
                      j.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => journeyId = v == '' ? null : v),
          ),
          DropdownButton<String>(
            isExpanded: true,
            value: direction ?? '',
            items: const [
              DropdownMenuItem(value: '', child: Text('Không chọn chiều')),
              DropdownMenuItem(value: 'outbound', child: Text('Chiều đi')),
              DropdownMenuItem(value: 'inbound', child: Text('Chiều về')),
            ],
            onChanged: (v) => setState(() => direction = v == '' ? null : v),
          ),
          TextField(
            controller: notes,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Ghi chú'),
          ),
          if (error != null) Text(error!),
          TrafficPrimaryButton(
            onPressed: busy
                ? null
                : () async {
                    final value = int.tryParse(amount.text.trim());
                    if (value == null || value <= 0 || value > 1000000000) {
                      setState(
                        () => error = 'Nhập số nguyên VND từ 1 đến 1 tỷ.',
                      );
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await store.saveExpense(
                        Expense(
                          id: widget.existing?.id ?? newId(),
                          category: category,
                          date: date.toIso8601String().split('T').first,
                          amount: value,
                          notes: notes.text.trim(),
                          journeyId: journeyId,
                          direction: direction,
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = errorMessage(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Xác nhận lưu khoản chi'),
          ),
        ],
      ),
    );
  }
}

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(journeysProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final month = DateTime(now.year, now.month);
    final week = today.subtract(Duration(days: today.weekday - 1));
    final tomorrow = today.add(const Duration(days: 1));
    final totals = <String, int>{};
    for (final e in s.expenses) {
      totals.update(e.category, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    final total = s.expenses.fold<int>(0, (v, e) => v + e.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Chi phí và lịch sử')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => editExpense(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const SectionHeading(
            title: 'Chi tiêu rõ ràng hơn',
            subtitle: 'Chỉ tổng hợp khoản chi bạn đã ghi nhận.',
            icon: Icons.account_balance_wallet_outlined,
          ),
          MetricPanel(
            title: 'Hôm nay',
            value: formatVnd(s.total(today, tomorrow)),
            icon: Icons.today,
          ),
          MetricPanel(
            title: 'Tuần này',
            value: formatVnd(s.total(week, tomorrow)),
            icon: Icons.date_range,
          ),
          MetricPanel(
            title: 'Tháng này',
            value: formatVnd(s.total(month, tomorrow)),
            icon: Icons.calendar_month,
          ),
          Text(
            'Chuyến đã xác nhận hoàn thành: ${s.completed.length}\nChi phí trung bình/chuyến (toàn bộ khoản chi): ${s.completed.isEmpty ? 'Chưa có chuyến' : '${(total / s.completed.length).round()} đ'}',
          ),
          const Divider(),
          ExpenseWeekChart(store: s, today: today),
          const Divider(),
          const Text('Theo loại (toàn bộ thời gian)'),
          for (final e in totals.entries)
            ListTile(
              title: Text(expenseTypes[e.key] ?? e.key),
              trailing: Text(formatVnd(e.value)),
            ),
          const Text('Theo hành trình (toàn bộ thời gian)'),
          for (final id in s.expenses.map((e) => e.journeyId).toSet())
            ListTile(
              title: Text(
                s.journeys.where((j) => j.id == id).firstOrNull?.name ??
                    (id == null ? 'Không gắn hành trình' : 'Hành trình đã xóa'),
              ),
              trailing: Text(
                formatVnd(
                  s.expenses
                      .where((e) => e.journeyId == id)
                      .fold<int>(0, (v, e) => v + e.amount),
                ),
              ),
            ),
          const Divider(),
          const Text('Khoản chi'),
          if (s.expenses.isEmpty)
            const Text(
              'Chưa có khoản chi. Không tự tạo chi phí từ quãng đường.',
            ),
          for (final e in [
            ...s.expenses,
          ]..sort((a, b) => b.date.compareTo(a.date)))
            ListTile(
              title: Text(
                '${expenseTypes[e.category]} • ${formatVnd(e.amount)}',
              ),
              subtitle: Text('${e.date} • ${e.notes}'),
              onTap: () => editExpense(context, ref, existing: e),
              trailing: IconButton(
                tooltip: 'Xóa khoản chi',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Xóa khoản chi?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Hủy'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Xóa'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) await s.deleteExpense(e.id);
                },
              ),
            ),
          const Divider(),
          const Text('Chuyến đã hoàn thành'),
          for (final c in s.completed.reversed)
            ListTile(title: Text(c['name']), subtitle: Text(c['completed_at'])),
        ],
      ),
    );
  }
}

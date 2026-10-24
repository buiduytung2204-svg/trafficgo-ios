import '../map/camera_session.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/state.dart';
import '../../core/models.dart';
import '../departure/controller.dart';
import '../journeys/store.dart';
import '../journeys/screens.dart';
import '../journeys/place_picker.dart';
import '../maintenance/store.dart';
import '../maintenance/screens.dart';
import 'accounts.dart';

Future<void> reloadPersonalData(WidgetRef ref) async {
  ref.invalidate(departureProvider);
  ref.invalidate(cameraSessionProvider);
  ref.invalidate(journeysProvider);
  ref.invalidate(garageProvider);
  ref.invalidate(stateProvider);
  await ref.read(stateProvider).loadToken();
}

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final username = TextEditingController(), password = TextEditingController();
  bool register = true, busy = false;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!RegExp(r'^[a-zA-Z0-9_.-]{3,40}$').hasMatch(username.text.trim()) ||
        password.text.length < 10 ||
        password.text.length > 128) {
      setState(
        () => error =
            'Tên đăng nhập 3–40 ký tự không dấu; mật khẩu 10–128 ký tự.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(accountProvider)
          .authenticate(username.text, password.text, register: register);
      password.clear();
      await reloadPersonalData(ref);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        context.go("/");
      }
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(accountProvider);
    if (c.id != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tài khoản của tôi')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              c.account?['profile']?['display_name'] ??
                  c.account?['username'] ??
                  'Tài khoản',
            ),
            Text(
              c.complete
                  ? 'Đã thiết lập hồ sơ cá nhân'
                  : 'Cần hoàn tất thiết lập ban đầu',
            ),
            if (c.error != null) Text(c.error!),
            const Text(
              'Lịch nhắc được lưu trên backend Windows. Xe, tuyến đã chọn và chi phí được lưu theo tài khoản trên thiết bị này; chưa đồng bộ các dữ liệu đó giữa thiết bị.',
            ),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PersonalSetupScreen()),
              ),
              child: const Text('Xem thiết lập ban đầu'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await c.logout();
                      await reloadPersonalData(ref);
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(register ? 'Tạo tài khoản TrafficGo' : 'Đăng nhập'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Hồ sơ riêng cho xe, hành trình và lịch đi lại của bạn.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: username,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập (không dấu)',
                ),
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu (ít nhất 10 ký tự)',
                ),
                onSubmitted: (_) {
                  if (!busy) submit();
                },
              ),
              const SizedBox(height: 16),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'Đang kết nối…'
                      : register
                      ? 'Tạo tài khoản'
                      : 'Đăng nhập',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        register = !register;
                        error = null;
                      }),
                child: Text(
                  register
                      ? 'Đã có tài khoản? Đăng nhập'
                      : 'Chưa có tài khoản? Đăng ký',
                ),
              ),
              const Text(
                'Tài khoản đang dùng backend Windows. Chưa hỗ trợ khôi phục mật khẩu qua email.',
              ),
              TextButton(
                onPressed: () => context.push('/settings'),
                child: const Text('Cấu hình kết nối backend'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PersonalSetupScreen extends ConsumerStatefulWidget {
  const PersonalSetupScreen({super.key});
  @override
  ConsumerState<PersonalSetupScreen> createState() =>
      _PersonalSetupScreenState();
}

class _PersonalSetupScreenState extends ConsumerState<PersonalSetupScreen> {
  final name = TextEditingController();
  String purpose = 'school', vehicle = 'motorcycle';
  String? vehicleId, error;
  Place? home, destination;
  SavedTrip? trip, inbound;
  Set<int> days = {0, 1, 2, 3, 4};
  TimeOfDay arrival = const TimeOfDay(hour: 7, minute: 30);
  int preparation = 15, buffer = 10;
  bool busy = false;
  int step = 0;
  late final String draftKey;
  @override
  void initState() {
    super.initState();
    draftKey = '${accountPrefix(ref.read(preferencesProvider))}setup-draft.v1';
    try {
      final raw = ref.read(preferencesProvider).getString(draftKey);
      if (raw != null) {
        final d = jsonDecode(raw);
        name.text = d['name'] ?? '';
        purpose = d['purpose'] ?? purpose;
        vehicle = d['vehicle'] ?? vehicle;
        vehicleId = d['vehicle_id'];
        step = (d['step'] as int? ?? 0).clamp(0, 4);
        home = d['home'] == null ? null : Place.fromJson(d['home']);
        destination = d['destination'] == null
            ? null
            : Place.fromJson(d['destination']);
        trip = d['trip'] == null ? null : SavedTrip.fromJson(d['trip']);
        inbound = d['inbound'] == null
            ? null
            : SavedTrip.fromJson(d['inbound']);
        days = Set<int>.from(d['days'] ?? [0, 1, 2, 3, 4]);
        arrival = TimeOfDay(hour: d['hour'] ?? 7, minute: d['minute'] ?? 30);
        preparation = d['preparation'] ?? 15;
        buffer = d['buffer'] ?? 10;
      }
    } catch (_) {
      error = 'Không đọc được bản nháp. Vui lòng kiểm tra lại thông tin.';
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> draft() async {
    final ok = await ref
        .read(preferencesProvider)
        .setString(
          draftKey,
          jsonEncode({
            'name': name.text,
            'purpose': purpose,
            'vehicle': vehicle,
            'vehicle_id': vehicleId,
            'step': step,
            'home': home?.toJson(),
            'destination': destination?.toJson(),
            'trip': trip?.toJson(),
            'inbound': inbound?.toJson(),
            'days': days.toList(),
            'hour': arrival.hour,
            'minute': arrival.minute,
            'preparation': preparation,
            'buffer': buffer,
          }),
        );
    if (!ok) throw StateError('Không lưu được bản nháp');
  }

  String? validateStep() {
    if (step == 0 && name.text.trim().isEmpty) {
      return 'Nhập tên hiển thị của bạn.';
    }
    if (step == 1 &&
        vehicle == 'motorcycle' &&
        !ref.read(garageProvider).vehicles.any((v) => v['id'] == vehicleId)) {
      return 'Thêm và chọn xe của bạn.';
    }
    if (step == 2 && (home == null || destination == null)) {
      return 'Chọn Nhà và điểm đến.';
    }
    if (step == 3 && trip?.route == null) {
      return 'Tìm và chọn một tuyến đường thật.';
    }
    if (step == 4 && days.isEmpty) return 'Chọn ít nhất một ngày đi lại.';
    return null;
  }

  Future<void> next() async {
    // A second pointer event can arrive before the disabled button rebuilds.
    if (busy || ref.read(accountProvider).complete) return;
    final problem = validateStep();
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await draft();
      if (step < 4) {
        setState(() => step++);
        await draft();
      } else {
        await finish();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is StateError ? e.message.toString() : accountError(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish() async {
    if (home == null ||
        destination == null ||
        trip?.route == null ||
        days.isEmpty ||
        name.text.trim().isEmpty) {
      throw StateError('Thiếu thông tin; kiểm tra lại các bước trước.');
    }
    if (trip!.vehicle != vehicle ||
        trip!.origin.point != home!.point ||
        trip!.destination.point != destination!.point) {
      throw StateError('Tuyến phải khớp địa điểm và phương tiện đã chọn.');
    }
    if (vehicle == 'motorcycle' &&
        !ref.read(garageProvider).vehicles.any((v) => v['id'] == vehicleId)) {
      throw StateError('Chọn lại xe của bạn.');
    }
    final c = ref.read(accountProvider);
    final uid = c.id;
    if (uid == null) throw StateError('Cần đăng nhập trước khi thiết lập.');
    final jid = 'setup-$uid';
    // Stable ID makes retry safe. Geometry stays exactly as selected, locally.
    await ref
        .read(journeysProvider)
        .saveJourney(
          Journey(
            id: jid,
            name: trip!.name,
            category: purpose,
            outbound: trip,
            inbound: inbound,
          ),
        );
    final state = ref.read(stateProvider);
    await state.save(home!);
    await state.save(destination!);
    await state.saveTrip(trip!);
    final departure = ref.read(departureProvider);
    await departure.ready;
    final prefs = ref.read(preferencesProvider);
    await prefs.setString('${accountPrefix(prefs)}default-vehicle', vehicle);
    await c.setup({
      'display_name': name.text.trim(),
      'purpose': purpose,
      'vehicle': vehicle,
      'vehicle_id': vehicleId,
      'home': {
        'name': home!.name.substring(0, home!.name.length.clamp(0, 100)),
        'coordinate': home!.toJson()['coordinate'],
      },
      'destination': {
        'name': destination!.name.substring(
          0,
          destination!.name.length.clamp(0, 100),
        ),
        'coordinate': destination!.toJson()['coordinate'],
      },
      'journey_id': jid,
      'schedule': {
        'name': trip!.name.substring(0, trip!.name.length.clamp(0, 100)),
        'journey_id': jid,
        'direction': 'outbound',
        'route_name': trip!.name.substring(0, trip!.name.length.clamp(0, 100)),
        'origin': home!.toJson()['coordinate'],
        'destination': destination!.toJson()['coordinate'],
        'origin_name': home!.name.substring(0, home!.name.length.clamp(0, 100)),
        'destination_name': destination!.name.substring(
          0,
          destination!.name.length.clamp(0, 100),
        ),
        'vehicle': vehicle,
        'arrival_time':
            '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}',
        'weekdays': days.toList()..sort(),
        'preparation_minutes': preparation,
        'buffer_minutes': buffer,
        'initial_eta_s': trip!.route!.seconds.clamp(60, 14400),
        'enabled': true,
      },
    });
    state.completeOnboarding();
    await departure.refresh();
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> choose(bool origin) async {
    final p = await pickPlace(
      context,
      title: origin
          ? 'Chọn Nhà / điểm xuất phát'
          : 'Chọn trường / nơi làm việc',
    );
    if (p == null || !mounted) return;
    setState(() {
      if (origin) {
        home = p;
      } else {
        destination = p;
      }
      trip = null;
      inbound = null;
    });
    await draft();
  }

  Future<void> plan({bool reverse = false}) async {
    final p = await Navigator.push<SavedTrip>(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePlanner(
          name: reverse
              ? '${destination!.name} → ${home!.name}'
              : '${home!.name} → ${destination!.name}',
          initial: reverse
              ? inbound ??
                    SavedTrip('Chiều về', destination!, home!, vehicle: vehicle)
              : trip ??
                    SavedTrip(
                      'Chiều đi',
                      home!,
                      destination!,
                      vehicle: vehicle,
                    ),
        ),
      ),
    );
    if (p == null || !mounted) return;
    final start = reverse ? destination! : home!,
        end = reverse ? home! : destination!;
    if (p.vehicle != vehicle ||
        p.origin.point != start.point ||
        p.destination.point != end.point) {
      setState(
        () => error =
            'Giữ đúng địa điểm và phương tiện đã chọn, hoặc quay lại bước trước để thay đổi.',
      );
      return;
    }
    setState(() {
      if (reverse) {
        inbound = p;
      } else {
        trip = p;
      }
    });
    await draft();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(accountProvider);
    if (c.id == null) {
      return const Scaffold(
        body: Center(child: Text('Cần đăng nhập để tạo hồ sơ.')),
      );
    }
    if (c.complete) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hồ sơ đã thiết lập')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Bạn đã hoàn tất thiết lập. Quản lý xe trong Cài đặt → Xe và bảo dưỡng; chỉnh tuyến và lịch tại Hành trình và chi phí.',
          ),
        ),
      );
    }
    final garage = ref.watch(garageProvider),
        catalog = ref.watch(hondaCatalogProvider);
    final labels = [
      'Về bạn',
      'Xe của bạn',
      'Địa điểm',
      'Chọn tuyến',
      'Lịch đi lại',
    ];
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Thiết lập TrafficGo'),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await c.logout();
                      await reloadPersonalData(ref);
                    },
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Bước ${step + 1}/5 · ${labels[step]}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                LinearProgressIndicator(value: (step + 1) / 5),
                const SizedBox(height: 24),
                if (step == 0) ...[
                  TextField(
                    controller: name,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Tên hiển thị',
                    ),
                    onChanged: (_) => draft(),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: purpose,
                    decoration: const InputDecoration(
                      labelText: 'Mục đích chính',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'school', child: Text('Đi học')),
                      DropdownMenuItem(value: 'work', child: Text('Đi làm')),
                      DropdownMenuItem(
                        value: 'personal',
                        child: Text('Cá nhân'),
                      ),
                    ],
                    onChanged: (v) async {
                      setState(() => purpose = v!);
                      await draft();
                    },
                  ),
                ],
                if (step == 1) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'motorcycle',
                        label: Text('Xe máy'),
                        icon: Icon(Icons.two_wheeler),
                      ),
                      ButtonSegment(
                        value: 'car',
                        label: Text('Ô tô'),
                        icon: Icon(Icons.directions_car),
                      ),
                    ],
                    selected: {vehicle},
                    onSelectionChanged: (v) async {
                      setState(() {
                        vehicle = v.first;
                        trip = null;
                        inbound = null;
                      });
                      await draft();
                    },
                  ),
                  if (vehicle == 'motorcycle') ...[
                    for (final v in garage.vehicles)
                      ListTile(
                        leading: Icon(
                          v['id'] == vehicleId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(v['name']),
                        subtitle: Text('${v['year']} · ${v['variant']}'),
                        onTap: () async {
                          setState(() => vehicleId = v['id']);
                          await draft();
                        },
                      ),
                    OutlinedButton.icon(
                      onPressed: catalog.hasValue
                          ? () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VehicleEditor(
                                    catalog: catalog.requireValue,
                                  ),
                                ),
                              );
                              if (!mounted) return;
                              final all = ref.read(garageProvider).vehicles;
                              if (all.isNotEmpty) {
                                setState(() => vehicleId = all.last['id']);
                              }
                              await draft();
                            }
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Thêm xe: hãng / dòng / năm / phiên bản',
                      ),
                    ),
                    if (catalog.hasError)
                      const Text(
                        'Không đọc được danh mục xe. Thử mở lại ứng dụng.',
                      ),
                  ],
                  const Text(
                    'Chỉ xin vị trí khi bạn chọn GPS. Không tự động theo dõi nền.',
                  ),
                ],
                if (step == 2) ...[
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: Text(home?.name ?? 'Chọn Nhà / điểm xuất phát'),
                    subtitle: const Text(
                      'Tìm tên, GPS, bản đồ hoặc địa điểm đã lưu',
                    ),
                    onTap: () => choose(true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.school),
                    title: Text(
                      destination?.name ?? 'Chọn nơi đến thường xuyên',
                    ),
                    onTap: () => choose(false),
                  ),
                ],
                if (step == 3) ...[
                  Text('${home?.name ?? ""} → ${destination?.name ?? ""}'),
                  FilledButton.tonal(
                    onPressed: home != null && destination != null
                        ? plan
                        : null,
                    child: Text(
                      trip == null
                          ? 'Tìm và chọn tuyến chiều đi'
                          : 'Xem / đổi tuyến chiều đi',
                    ),
                  ),
                  if (trip?.route != null)
                    Text(
                      '${formatEta(trip!.route!.seconds)} · ${(trip!.route!.meters / 1000).toStringAsFixed(1)} km · ${trip!.route!.provider}',
                    ),
                  OutlinedButton(
                    onPressed: home != null && destination != null
                        ? () => plan(reverse: true)
                        : null,
                    child: Text(
                      inbound == null
                          ? 'Thêm chiều về (tùy chọn)'
                          : 'Đã chọn tuyến chiều về',
                    ),
                  ),
                  const Text(
                    'ETA routing chưa có giao thông realtime. Chiều về được tìm riêng, không đảo polyline chiều đi.',
                  ),
                ],
                if (step == 4) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < 7; i++)
                        FilterChip(
                          label: Text(i == 6 ? 'CN' : 'T${i + 2}'),
                          selected: days.contains(i),
                          onSelected: (v) async {
                            setState(() {
                              v ? days.add(i) : days.remove(i);
                            });
                            await draft();
                          },
                        ),
                    ],
                  ),
                  ListTile(
                    title: const Text('Giờ cần đến'),
                    trailing: Text(arrival.format(context)),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: arrival,
                      );
                      if (t != null && mounted) {
                        setState(() => arrival = t);
                        await draft();
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: preparation,
                    decoration: const InputDecoration(
                      labelText: 'Chuẩn bị (phút)',
                    ),
                    items: [
                      for (final n in [0, 5, 10, 15, 20, 30, 45, 60])
                        DropdownMenuItem(value: n, child: Text('$n phút')),
                    ],
                    onChanged: (v) async {
                      setState(() => preparation = v!);
                      await draft();
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: buffer,
                    decoration: const InputDecoration(
                      labelText: 'Dự phòng (phút)',
                    ),
                    items: [
                      for (final n in [0, 5, 10, 15, 20, 30, 45, 60])
                        DropdownMenuItem(value: n, child: Text('$n phút')),
                    ],
                    onChanged: (v) async {
                      setState(() => buffer = v!);
                      await draft();
                    },
                  ),
                  const Text(
                    'Lịch theo múi giờ Việt Nam. Backend Windows cần chạy để cập nhật ETA; thông báo khi app đóng còn cần cấu hình push.',
                  ),
                ],
                const SizedBox(height: 24),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    if (step > 0)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() {
                                  step--;
                                  error = null;
                                });
                                await draft();
                              },
                        child: const Text('Quay lại'),
                      ),
                    FilledButton(
                      onPressed: busy ? null : next,
                      child: Text(
                        busy
                            ? 'Đang lưu…'
                            : step == 4
                            ? 'Hoàn tất và tạo lịch'
                            : 'Tiếp tục',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

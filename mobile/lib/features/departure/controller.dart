import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/state.dart';
import '../../core/api.dart';
import 'models.dart';
import 'local_notifications.dart';

final departureProvider = ChangeNotifierProvider<DepartureController>(
  (ref) => DepartureController(
    ref.watch(apiProvider).dio,
    ref.read(preferencesProvider),
  ),
);

class DepartureController extends ChangeNotifier with WidgetsBindingObserver {
  final Dio dio;
  final DepartureLocalNotifications localNotifications;
  List<CommuteSchedule> schedules = [];
  List<Map<String, dynamic>> events = [];
  Map<String, dynamic> worker = {};
  Map<String, dynamic>? pendingNotification;
  final Set<String> notificationActions = {};
  String credential = '';
  String? error;
  String? notificationWarning;
  bool online = false, busy = false, disposed = false, foreground = true;
  DateTime? syncedAt;
  Timer? poll;
  late final Future<void> ready;
  late final String prefix;
  String get storageKey => '${prefix}departure-session:$apiBase';
  String get cacheKey => '${prefix}departure-overview:$apiBase';
  DepartureController(this.dio, prefs)
    : localNotifications = DepartureLocalNotifications(
        prefs,
        prefix: accountPrefix(prefs),
      ) {
    prefix = accountPrefix(prefs);
    localNotifications.onResponse = (intent) {
      if (disposed) return;
      pendingNotification = intent;
      changed();
    };
    try {
      final cached = prefs.getString(cacheKey);
      if (cached != null) accept(Map<String, dynamic>.from(jsonDecode(cached)));
    } catch (_) {
      /* Ignore damaged cache, never replace server data. */
    }
    WidgetsBinding.instance.addObserver(this);
    ready = start();
  }
  Options get auth => Options(headers: {'X-Schedule-Token': credential});
  bool get workerAlive {
    final tick = parseInstant(worker['last_tick_at']);
    return online &&
        tick != null &&
        DateTime.now().difference(tick).inSeconds < 100;
  }

  CommuteSchedule? get next {
    final candidates = schedules
        .where(
          (s) =>
              s.enabled &&
              s.occurrence?['status'] == 'planned' &&
              parseInstant(s.occurrence?['arrival_at'])
                      ?.isAfter(DateTime.now()) ==
                  true,
        )
        .toList();
    candidates.sort(
      (a, b) =>
          (a.occurrence?['departure_at'] ?? a.occurrence?['arrival_at'] ?? '')
              .compareTo(
                b.occurrence?['departure_at'] ??
                    b.occurrence?['arrival_at'] ??
                    '',
              ),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  void changed() {
    if (!disposed) notifyListeners();
  }

  Future<void> start() async {
    try {
      credential = await TrafficApi.storage.read(key: storageKey) ?? '';
      if (disposed) return;
      if (localNotifications.enabled) await localNotifications.initialize();
      if (credential.isNotEmpty) await refresh();
    } catch (_) {
      error = 'Không đọc được thông tin kết nối lịch nhắc.';
    }
    if (disposed) return;
    poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (foreground && credential.isNotEmpty) unawaited(refresh());
    });
    changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && credential.isNotEmpty) unawaited(refresh());
  }

  Future<void> connect() async {
    await ready;
    if (busy) return;
    if (credential.isNotEmpty) {
      await refresh();
      return;
    }
    busy = true;
    error = null;
    changed();
    try {
      if (prefix.isNotEmpty) throw StateError('Account session required');
      final result = await dio.post('/api/v1/departure/session');
      credential = result.data['token'];
      await TrafficApi.storage.write(key: storageKey, value: credential);
    } catch (_) {
      error =
          'Không kết nối được backend. Kiểm tra access token và máy Windows.';
      online = false;
    } finally {
      busy = false;
      changed();
    }
    if (credential.isNotEmpty) await refresh();
  }

  void accept(Map<String, dynamic> data) {
    schedules = (data['schedules'] as List)
        .map((j) => CommuteSchedule(Map<String, dynamic>.from(j)))
        .toList();
    events = (data['notifications'] as List)
        .map((j) => Map<String, dynamic>.from(j))
        .toList();
    worker = Map<String, dynamic>.from(data['worker'] ?? {});
    syncedAt = parseInstant(data['synced_at']);
  }

  Future<void> refresh() async {
    if (busy || credential.isEmpty || disposed) return;
    busy = true;
    try {
      final response = await dio.get(
        '/api/v1/departure/overview',
        options: auth,
      );
      if (disposed) return;
      final data = Map<String, dynamic>.from(response.data);
      accept(data);
      online = true;
      error = null;
      await localNotifications.prefs.setString(cacheKey, jsonEncode(data));
      try {
        await localNotifications.receive(events);
      } catch (_) {
        /* Inbox remains available. */
      }
    } catch (_) {
      online = false;
      error = 'Mất kết nối hoặc phiên không hợp lệ. Dữ liệu đang xem là bản lưu, chưa đồng bộ.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> mutate(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    if (!online || credential.isEmpty) {
      throw StateError('Backend chưa kết nối; chưa lưu thay đổi.');
    }
    await dio.request(
      '/api/v1/departure/$path',
      data: data,
      options: Options(method: method, headers: auth.headers),
    );
    await refresh();
  }

  Future<Map<String, dynamic>> notificationEvent(String id) async {
    await ready;
    final response = await dio.get(
      '/api/v1/departure/notifications/$id',
      options: auth,
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> notificationAction(
    String id,
    String action,
  ) async {
    await ready;
    if (!notificationActions.add(id)) throw StateError('Đang xử lý thông báo.');
    changed();
    try {
      final response = await dio.post(
        '/api/v1/departure/notifications/$id/action',
        data: {'action': action},
        options: auth,
      );
      final event = Map<String, dynamic>.from(response.data);
      if (disposed) return event;
      notificationWarning = null;
      if (event['reminder_event_id'] case final String reminderId) {
        try {
          final reminder = await notificationEvent(reminderId);
          final scheduled = await localNotifications.scheduleReminder(reminder);
          if (!scheduled) notificationWarning = 'Đã lưu trên backend; thông báo thiết bị chưa được bật hoặc nền tảng chưa hỗ trợ.';
        } catch (_) {
          notificationWarning = 'Đã lưu trên backend nhưng chưa hẹn được thông báo trên thiết bị.';
        }
      }
      await refresh();
      return event;
    } finally {
      notificationActions.remove(id);
      changed();
    }
  }

  Future<void> save(Map<String, dynamic> data, [String? id]) => mutate(
    id == null ? 'POST' : 'PUT',
    id == null ? 'schedules' : 'schedules/$id',
    data,
  );
  Future<void> eraseRemote() async {
    if (!online) throw StateError('Backend chưa kết nối.');
    await dio.delete('/api/v1/departure/personal-data', options: auth);
    await TrafficApi.storage.delete(key: storageKey);
    await localNotifications.prefs.remove(cacheKey);
    credential = '';
    schedules = [];
    events = [];
    online = false;
    worker = {};
    error = null;
    changed();
  }

  @override
  void dispose() {
    disposed = true;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

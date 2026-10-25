import 'dart:convert';

import 'local_plan.dart';
import 'models.dart';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DepartureLocalNotifications {
  final SharedPreferences prefs;
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  static Future<void> _queue = Future.value();
  bool get currentScope {
    final uid = prefs.getString('active-account-id');
    return prefix == (uid == null ? '' : 'account:$uid:');
  }

  Future<T> serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String get planKey => '${prefix}departure-local-plans';
  String get receiptKey => '${prefix}departure-local-receipts';
  String get idsKey => '${prefix}departure-os-ids';
  DateTime? localHorizon;
  int localCount = 0;
  Map<String, dynamic> readMap(String key) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString(key) ?? '{}'),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> track(int id) async {
    final ids = (prefs.getStringList(idsKey) ?? []).toSet()..add('$id');
    await prefs.setStringList(
      idsKey,
      ids.toList().reversed.take(256).toList().reversed.toList(),
    );
  }

  Future<void> clearScope({Future<void> Function()? afterClear}) =>
      serial(() async {
        await _clearScope();
        if (afterClear != null) await afterClear();
      });
  Future<void> _clearScope() async {
    final ids = (prefs.getStringList(idsKey) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    ids.addAll(
      (prefs.getStringList('${prefix}departure-pending-reminders') ?? []).map(
        eventId,
      ),
    );
    if (supported && (ids.isNotEmpty || enabled)) {
      await initialize();
      for (final request in await plugin.pendingNotificationRequests()) {
        try {
          if (jsonDecode(request.payload ?? '{}')['scope'] == prefix) {
            ids.add(request.id);
          }
        } catch (_) {
          /* unrelated payload */
        }
      }
      for (final id in ids) {
        await plugin.cancel(id);
      }
    }
    for (final key in [
      idsKey,
      planKey,
      receiptKey,
      '${prefix}departure-event-signatures',
      '${prefix}departure-pending-reminders',
    ]) {
      await prefs.remove(key);
    }
    localCount = 0;
    localHorizon = null;
  }

  Future<void> reconcile(List<CommuteSchedule> schedules, {DateTime? now}) =>
      serial(() async {
        if (!supported || !enabled || !currentScope) return;
        await initialize();
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          final permission = await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();
          if (permission != null && !permission.isEnabled) {
            await prefs.setBool(
              '${prefix}departure-local-notifications',
              false,
            );
            await _clearScope();
            throw StateError(
              'Thông báo iOS đã bị tắt. Mở Cài đặt để cấp lại quyền.',
            );
          }
        }
        final plans = departurePlans(
          schedules,
          prefix,
          now ?? DateTime.now(),
          limit: 56,
        );
        final previous = readMap(planKey), receipts = readMap(receiptKey);
        final wanted = {for (final plan in plans) plan.id: plan.signature};
        final pending = (await plugin.pendingNotificationRequests())
            .map((n) => n.id)
            .toSet();
        for (final id in previous.keys.where((id) => !wanted.containsKey(id))) {
          await plugin.cancel(eventId('$prefix$id'));
        }
        for (final plan in plans) {
          final id = eventId('$prefix${plan.id}');
          if (previous[plan.id] != plan.signature || !pending.contains(id)) {
            await plugin.zonedSchedule(
              id,
              plan.title,
              plan.body,
              tz.TZDateTime.from(plan.at, tz.UTC),
              details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              payload: plan.payload,
            );
            await track(id);
          }
          receipts[plan.id] = plan.at.toUtc().toIso8601String();
        }
        await prefs.setString(planKey, jsonEncode(wanted));
        final recent = receipts.entries.toList()
          ..sort((a, b) => b.value.toString().compareTo(a.value.toString()));
        await prefs.setString(
          receiptKey,
          jsonEncode(Map.fromEntries(recent.take(1000))),
        );
        localCount = plans.length;
        localHorizon = plans.isEmpty ? null : plans.last.at;
      });
  void Function()? onOpen;
  void Function(Map<String, dynamic>)? onResponse;
  final String prefix;
  DepartureLocalNotifications(this.prefs, {this.prefix = ""});
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get enabled =>
      prefs.getBool('${prefix}departure-local-notifications') ?? false;

  Future<void> initialize() async {
    if (!supported || initialized) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              'departure_actions',
              actions: [
                for (final entry in const {
                  'start': 'Xuất phát',
                  'snooze': 'Nhắc lại sau 5 phút',
                  'skip': 'Bỏ qua hôm nay',
                }.entries)
                  DarwinNotificationAction.plain(
                    entry.key,
                    entry.value,
                    options: {DarwinNotificationActionOption.foreground},
                  ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: handleResponse,
    );
    initialized = true;
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      handleResponse(launch!.notificationResponse!);
    }
  }

  void handleResponse(NotificationResponse response) {
    final intent = decodeIntent(
      response.payload,
      response.notificationResponseType ==
              NotificationResponseType.selectedNotification
          ? null
          : response.actionId,
      prefix,
    );
    if (intent != null) {
      onResponse?.call(intent);
    } else if (response.payload == null) {
      onOpen?.call();
    }
  }

  static Map<String, dynamic>? decodeIntent(
    String? payload,
    String? actionId,
    String scope,
  ) {
    try {
      final data = jsonDecode(payload ?? '') as Map<String, dynamic>;
      if (data['scope'] != scope || data['event_id'] is! String) return null;
      final action = (actionId == null || actionId.isEmpty) ? 'open' : actionId;
      if (!{'open', 'start', 'snooze', 'skip'}.contains(action)) return null;
      return {...data, 'action': action};
    } catch (_) {
      return null;
    }
  }

  static int eventId(String id) {
    var value = 0;
    for (final code in id.codeUnits) {
      value = (value * 31 + code) & 0x7fffffff;
    }
    return value;
  }

  Future<bool> enable(void Function() openInbox) async {
    if (!supported) return false;
    onOpen = openInbox;
    await initialize();
    final allowed = defaultTargetPlatform == TargetPlatform.android
        ? await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission()
        : await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
    await prefs.setBool(
      '${prefix}departure-local-notifications',
      allowed == true,
    );
    return allowed == true;
  }

  static NotificationDetails get details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'smart_departure',
      'Nhắc giờ xuất phát',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          'start',
          'Xuất phát',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'snooze',
          'Nhắc lại sau 5 phút',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'skip',
          'Bỏ qua hôm nay',
          showsUserInterface: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(categoryIdentifier: 'departure_actions'),
  );

  Future<bool> scheduleReminder(Map<String, dynamic> event) =>
      serial(() => _scheduleReminder(event));
  Future<bool> _scheduleReminder(Map<String, dynamic> event) async {
    if (!enabled || !supported || !initialized || !currentScope) return false;
    final id = event['id'] as String;
    final scheduled = DateTime.tryParse(event['scheduled_for'] ?? '');
    if (scheduled == null || !scheduled.isAfter(DateTime.now())) return false;
    final existing =
        prefs.getStringList('${prefix}departure-pending-reminders') ?? [];
    if (existing.length >= 4 && !existing.contains(id)) return false;
    await plugin.zonedSchedule(
      eventId(id),
      event['title'] as String,
      event['schedule_name'] as String?,
      tz.TZDateTime.from(scheduled, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({'event_id': id, 'scope': prefix}),
    );
    await track(eventId(id));
    final seenKey = '${prefix}departure-notified-events';
    final seen = (prefs.getStringList(seenKey) ?? []).toSet()..add(id);
    await prefs.setStringList(
      seenKey,
      seen.toList().reversed.take(500).toList(),
    );
    final pendingKey = '${prefix}departure-pending-reminders';
    final pending = (prefs.getStringList(pendingKey) ?? []).toSet()..add(id);
    await prefs.setStringList(pendingKey, pending.toList());
    return true;
  }

  Future<void> testDelivery() => serial(() async {
    if (!enabled || !supported || !currentScope) {
      throw StateError('Hãy cho phép thông báo trước.');
    }
    await initialize();
    final id = eventId('${prefix}device-notification-check');
    await plugin.zonedSchedule(
      id,
      'Kiểm tra thông báo TrafficGo',
      'Thông báo kiểm tra sau 1 phút. Đây không phải lịch hành trình.',
      tz.TZDateTime.now(tz.UTC).add(const Duration(minutes: 1)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'smart_departure',
          'Nhắc giờ xuất phát',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    await track(id);
  });

  Future<void> receive(List<Map<String, dynamic>> events) =>
      serial(() => _receive(events));
  Future<void> _receive(List<Map<String, dynamic>> events) async {
    // Foreground polling only. No claim of background delivery or push.
    if (!enabled || !supported || !initialized || !currentScope) return;
    final seen =
        (prefs.getStringList('${prefix}departure-notified-events') ?? [])
            .toSet();
    final pendingKey = '${prefix}departure-pending-reminders';
    final pending = (prefs.getStringList(pendingKey) ?? []).toSet();
    final known = events.map((event) => event['id']).toSet();
    final futureEvents =
        events
            .where(
              (e) =>
                  e['cancelled'] != true &&
                  e['action_result'] == null &&
                  (DateTime.tryParse(e['scheduled_for'] ?? '')
                          ?.isAfter(DateTime.now()) ??
                      false),
            )
            .toList()
          ..sort(
            (a, b) => a['scheduled_for'].toString().compareTo(
              b['scheduled_for'].toString(),
            ),
          );
    final selectedFuture = futureEvents.take(4).map((e) => e['id']).toSet();
    final allFuture = futureEvents.map((e) => e['id']).toSet();
    for (final id in pending.toList()) {
      if (!known.contains(id) ||
          (allFuture.contains(id) && !selectedFuture.contains(id))) {
        await plugin.cancel(eventId(id));
        pending.remove(id);
      }
    }
    var count = 0;
    final signatures = readMap('${prefix}departure-event-signatures');
    final receipts = readMap(receiptKey);
    for (final event in events.reversed) {
      final id = event['id'] as String;
      if (event['cancelled'] == true || event['action_result'] != null) {
        await plugin.cancel(eventId(id));
        seen.add(id);
        pending.remove(id);
        continue;
      }
      final scheduled = DateTime.tryParse(event['scheduled_for'] ?? '');
      if (scheduled != null && scheduled.isAfter(DateTime.now())) {
        if (!selectedFuture.contains(id)) continue;
        final signature = jsonEncode([
          scheduled.toUtc().toIso8601String(),
          event['title'],
          event['schedule_name'],
        ]);
        if (signatures[id] == signature && pending.contains(id)) continue;
        await plugin.zonedSchedule(
          eventId(id),
          event['title'] as String,
          event['schedule_name'] as String?,
          tz.TZDateTime.from(scheduled, tz.UTC),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: jsonEncode({'event_id': id, 'scope': prefix}),
        );
        await track(eventId(id));
        signatures[id] = signature;
        seen.add(id);
        pending.add(id);
        continue;
      }
      if (seen.contains(id)) continue;
      final kind = (event['kind'] ?? '').toString().split(':').first;
      final localAt = DateTime.tryParse(
        receipts['local:${event['occurrence_id']}:$kind'] ?? '',
      );
      if (localAt != null &&
          (!localAt.isAfter(DateTime.now()) ||
              readMap(planKey)
                  .containsKey('local:${event['occurrence_id']}:$kind'))) {
        seen.add(id);
        continue;
      }
      final created = DateTime.tryParse(event['created_at'] ?? '');
      if (created == null ||
          DateTime.now().difference(created).inMinutes > 5 ||
          event['read'] == true ||
          count >= 3) {
        seen.add(id);
        continue;
      }
      // Stable ID makes OS replacement idempotent if a process stops after show().
      await plugin.show(
        eventId(id),
        event['title'] as String,
        "${event['schedule_name']} • ${event['traffic_aware'] == true ? 'ETA có dữ liệu traffic' : 'ETA chưa tính traffic realtime'}",
        details,
        payload: jsonEncode({'event_id': id, 'scope': prefix}),
      );
      await track(eventId(id));
      seen.add(id);
      count++;
    }
    await prefs.setString(
      '${prefix}departure-event-signatures',
      jsonEncode(signatures),
    );
    await prefs.setStringList(pendingKey, pending.toList());
    await prefs.setStringList(
      '${prefix}departure-notified-events',
      seen.toList().reversed.take(500).toList(),
    );
  }
}

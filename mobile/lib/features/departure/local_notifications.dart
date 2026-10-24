import 'dart:convert';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DepartureLocalNotifications {
  final SharedPreferences prefs;
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
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

  Future<bool> scheduleReminder(Map<String, dynamic> event) async {
    if (!enabled || !supported || !initialized) return false;
    final id = event['id'] as String;
    final scheduled = DateTime.tryParse(event['scheduled_for'] ?? '');
    if (scheduled == null || !scheduled.isAfter(DateTime.now())) return false;
    await plugin.zonedSchedule(
      eventId(id),
      event['title'] as String,
      event['schedule_name'] as String?,
      tz.TZDateTime.from(scheduled, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({'event_id': id, 'scope': prefix}),
    );
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

  Future<void> receive(List<Map<String, dynamic>> events) async {
    // Foreground polling only. No claim of background delivery or push.
    if (!enabled || !supported || !initialized) return;
    final seen =
        (prefs.getStringList('${prefix}departure-notified-events') ?? [])
            .toSet();
    final pendingKey = '${prefix}departure-pending-reminders';
    final pending = (prefs.getStringList(pendingKey) ?? []).toSet();
    final known = events.map((event) => event['id']).toSet();
    for (final id in pending.difference(known)) {
      await plugin.cancel(eventId(id));
      pending.remove(id);
    }
    var count = 0;
    for (final event in events.reversed) {
      final id = event['id'] as String;
      if (event['cancelled'] == true || event['action_result'] != null) {
        await plugin.cancel(eventId(id));
        seen.add(id);
        pending.remove(id);
        continue;
      }
      if (seen.contains(id)) continue;
      final scheduled = DateTime.tryParse(event['scheduled_for'] ?? '');
      if (scheduled != null && scheduled.isAfter(DateTime.now())) {
        await plugin.zonedSchedule(
          eventId(id),
          event['title'] as String,
          event['schedule_name'] as String?,
          tz.TZDateTime.from(scheduled, tz.UTC),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: jsonEncode({'event_id': id, 'scope': prefix}),
        );
        seen.add(id);
        pending.add(id);
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
      seen.add(id);
      count++;
    }
    await prefs.setStringList(pendingKey, pending.toList());
    await prefs.setStringList(
      '${prefix}departure-notified-events',
      seen.toList().reversed.take(500).toList(),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DepartureLocalNotifications {
  final SharedPreferences prefs;
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  void Function()? onOpen;
  DepartureLocalNotifications(this.prefs);
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get enabled => prefs.getBool('departure-local-notifications') ?? false;

  Future<void> initialize() async {
    if (!supported || initialized) return;
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => onOpen?.call(),
    );
    initialized = true;
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
    await prefs.setBool('departure-local-notifications', allowed == true);
    return allowed == true;
  }

  Future<void> receive(List<Map<String, dynamic>> events) async {
    // Foreground polling only. No claim of background delivery or push.
    if (!enabled || !supported || !initialized) return;
    final seen = (prefs.getStringList('departure-notified-events') ?? [])
        .toSet();
    var count = 0;
    for (final event in events.reversed) {
      final id = event['id'] as String;
      if (seen.contains(id)) continue;
      final created = DateTime.tryParse(event['created_at'] ?? '');
      if (created == null ||
          DateTime.now().difference(created).inMinutes > 5 ||
          event['read'] == true ||
          count >= 3) {
        seen.add(id);
        continue;
      }
      // Stable ID makes OS replacement idempotent if a process stops after show().
      int notificationId = 0;
      for (final code in id.codeUnits) {
        notificationId = (notificationId * 31 + code) & 0x7fffffff;
      }
      await plugin.show(
        notificationId,
        event['title'] as String,
        '${event['schedule_name']} • ETA chưa tính traffic realtime',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'smart_departure',
            'Nhắc giờ xuất phát',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: event['occurrence_id'] as String?,
      );
      seen.add(id);
      count++;
    }
    await prefs.setStringList(
      'departure-notified-events',
      seen.toList().reversed.take(500).toList(),
    );
  }
}

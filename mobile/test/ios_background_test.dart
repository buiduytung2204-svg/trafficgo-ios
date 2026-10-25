import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:trafficgo/features/departure/controller.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/features/departure/local_notifications.dart';
import 'package:trafficgo/features/departure/local_plan.dart';
import 'package:trafficgo/features/departure/models.dart';
import 'package:trafficgo/features/location/location_service.dart';

CommuteSchedule fixture(
  DateTime now, {
  int eta = 1500,
  String status = 'planned',
  bool enabled = true,
  String id = 'trip',
}) {
  final arrival = now.add(const Duration(hours: 2));
  final departure = arrival.subtract(Duration(seconds: eta, minutes: 10));
  return CommuteSchedule({
    'id': 'schedule',
    'name': 'Đi học CMC',
    'enabled': enabled,
    'occurrence': {
      'id': id,
      'status': status,
      'eta_s': eta,
      'arrival_at': arrival.toIso8601String(),
      'departure_at': departure.toIso8601String(),
      'prepare_at': departure
          .subtract(const Duration(minutes: 15))
          .toIso8601String(),
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS background location is opt-in and stream-only, never single-fix',
    () {
      final service = LocationService(android: false, ios: true);
      for (final stream in [false, true]) {
        final ordinary = service.settings(stream: stream) as AppleSettings;
        expect(ordinary.allowBackgroundLocationUpdates, isFalse);
        expect(ordinary.showBackgroundLocationIndicator, isFalse);
      }
      final active = service.settings(
        stream: true,
        backgroundNavigation: true,
      ) as AppleSettings;
      expect(active.allowBackgroundLocationUpdates, isTrue);
      expect(active.showBackgroundLocationIndicator, isTrue);
      expect(active.activityType, ActivityType.automotiveNavigation);
      expect(active.timeLimit, isNull);
      expect(
        (service.settings(
          backgroundNavigation: true,
        ) as AppleSettings).allowBackgroundLocationUpdates,
        isFalse,
      );
    },
  );
  test('Departure plan respects absolute Vietnam times crossing midnight and ETA changes', () {
    final now = DateTime.parse('2030-01-01T22:00:00+07:00');
    final first = fixture(now);
    final plans = departurePlans([first], 'account:a:', now);
    expect(plans, hasLength(4));
    expect(plans.map((p) => p.id).toSet(), hasLength(4));
    final updated = departurePlans(
      [fixture(now, eta: 2400)],
      'account:a:',
      now,
    );
    for (var i = 0; i < 4; i++) {
      expect(updated[i].id, plans[i].id);
      expect(
        plans[i].at.difference(updated[i].at),
        const Duration(minutes: 15),
      );
      expect(updated[i].signature, isNot(plans[i].signature));
    }
    expect(plans.last.at.toUtc(), DateTime.parse('2030-01-01T16:25:00Z'));
    expect(
      departurePlans(
        [
          fixture(now, status: 'skipped'),
          fixture(now, status: 'completed'),
          fixture(now, enabled: false),
        ],
        '',
        now,
      ),
      isEmpty,
    );
    expect(
      departurePlans(
        [
          CommuteSchedule({
            'id': 'x',
            'enabled': true,
            'occurrence': {
              'id': 'unknown',
              'status': 'planned',
              'arrival_at': now.add(const Duration(hours: 1)).toIso8601String(),
            },
          }),
        ],
        '',
        now,
      ),
      isEmpty,
    );
  });
  test('Bounded queue prioritizes nearest valid server occurrences and excludes skipped days', () {
    final now = DateTime.now().toUtc();
    final rows = [
      for (var i = 0; i < 30; i++)
        {
          ...fixture(now.add(Duration(hours: i)), id: 'trip-$i').occurrence!,
          if (i == 1) 'status': 'skipped',
        },
    ];
    final schedule = CommuteSchedule({
      'id': 's',
      'name': 'Lịch',
      'enabled': true,
      'upcoming_occurrences': rows,
    });
    final plans = departurePlans([schedule], '', now, limit: 56);
    expect(plans, hasLength(56));
    expect(plans.any((p) => p.id.startsWith('local:trip-1:')), isFalse);
    expect(plans.first.at.isBefore(plans.last.at), isTrue);
  });

  test('Offline notification opens cached route, explicit backend rejection never bypassed', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    var networkFailure = true;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: networkFailure
                  ? DioExceptionType.connectionError
                  : DioExceptionType.badResponse,
              response: networkFailure
                  ? null
                  : Response(requestOptions: options, statusCode: 409),
            ),
          );
        },
      ),
    );
    final controller = DepartureController(dio, prefs);
    await controller.ready;
    controller.accept({
      'schedules': [fixture(DateTime.now().toUtc()).json],
      'notifications': [],
      'worker': {},
    });
    final event = await controller.notificationEvent(
      'local:trip:departure_due',
    );
    expect(event['cached'], true);
    expect(event['occurrence_id'], 'trip');
    networkFailure = false;
    await expectLater(
      controller.notificationEvent('local:trip:departure_due'),
      throwsA(isA<DioException>()),
    );
    controller.dispose();
    dio.close();
  });

  group('iOS native notification channel', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    late SharedPreferences prefs;
    late DepartureLocalNotifications local;
    late List<MethodCall> calls;
    late Map<int, Map<String, dynamic>> pending;
    late bool permission;
    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      calls = [];
      pending = {};
      permission = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {'notificationLaunchedApp': false};
            }
            if (call.method == 'checkPermissions') {
              return {'isEnabled': permission, 'isAlertEnabled': permission};
            }
            if (call.method == 'pendingNotificationRequests') {
              return pending.values.toList();
            }
            if (call.method == 'zonedSchedule') {
              final a = Map<String, dynamic>.from(call.arguments);
              pending[a['id']] = {
                'id': a['id'],
                'title': a['title'],
                'body': a['body'],
                'payload': a['payload'],
              };
            }
            if (call.method == 'cancel') {
              pending.remove(
                call.arguments is int ? call.arguments : call.arguments['id'],
              );
            }
            return null;
          });
      SharedPreferences.setMockInitialValues({
        'active-account-id': 'a',
        'account:a:departure-local-notifications': true,
      });
      prefs = await SharedPreferences.getInstance();
      local = DepartureLocalNotifications(prefs, prefix: 'account:a:');
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    test('Darwin categories, pre-schedule, no duplicate on sync/restart, ETA replacement, skip cancels', () async {
      final now = DateTime.now().toUtc();
      await local.reconcile([fixture(now)], now: now);
      expect(pending, hasLength(4));
      final init =
          calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
      expect(init['notificationCategories'], hasLength(1));
      expect(init['requestAlertPermission'], false);
      final payload = jsonDecode(pending.values.first['payload']);
      expect(payload['event_id'], startsWith('local:trip:'));
      expect(payload['scope'], 'account:a:');
      await local.reconcile([fixture(now)], now: now);
      final restart = DepartureLocalNotifications(prefs, prefix: 'account:a:');
      await restart.reconcile([fixture(now)], now: now);
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(4));
      await restart.reconcile([fixture(now, eta: 2400)], now: now);
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(8));
      expect(pending, hasLength(4));
      await restart.reconcile([fixture(now, status: 'skipped')], now: now);
      expect(pending, isEmpty);
    });
    test(
      'Logout clearing is account-scoped and stale account cannot schedule',
      () async {
        final now = DateTime.now().toUtc();
        await local.reconcile([fixture(now)], now: now);
        pending[777] = {
          'id': 777,
          'title': 'Other',
          'payload': jsonEncode({'scope': 'account:b:'}),
        };
        await local.clearScope();
        expect(pending.keys, [777]);
        await prefs.setString('active-account-id', 'b');
        await local.reconcile([fixture(now)], now: now);
        expect(pending.keys, [777]);
      },
    );
    test('Logout queue barrier prevents already queued old-scope sync from resurrecting alarms', () async {
      final now = DateTime.now().toUtc();
      await local.reconcile([fixture(now)], now: now);
      final logout = local.clearScope(
        afterClear: () async {
          await prefs.setString('active-account-id', 'b');
        },
      );
      final stale = local.reconcile([fixture(now)], now: now);
      await Future.wait([logout, stale]);
      expect(pending, isEmpty);
    });
    test(
      'Permission revoke cancels owned pending reminders and reports disabled',
      () async {
        final now = DateTime.now().toUtc();
        await local.reconcile([fixture(now)], now: now);
        permission = false;
        await expectLater(
          local.reconcile([fixture(now)], now: now),
          throwsStateError,
        );
        expect(pending, isEmpty);
        expect(local.enabled, isFalse);
      },
    );
    test(
      'Same backend reminder ID with a changed time is rescheduled',
      () async {
        await local.initialize();
        final event = {
          'id': 'snooze',
          'title': 'Nhắc lại',
          'schedule_name': 'Đi học',
          'scheduled_for': DateTime.now()
              .add(const Duration(minutes: 5))
              .toUtc()
              .toIso8601String(),
        };
        await local.receive([event]);
        await local.receive([event]);
        expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(1));
        await local.receive([
          {
            ...event,
            'scheduled_for': DateTime.now()
                .add(const Duration(minutes: 10))
                .toUtc()
                .toIso8601String(),
          },
        ]);
        expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(2));
        await local.receive([
          {...event, 'cancelled': true},
        ]);
        expect(pending, isEmpty);
      },
    );
    test(
      'Native iOS pending queue stays below 64 with many commutes and snoozes',
      () async {
        final now = DateTime.now().toUtc();
        final rows = [
          for (var i = 0; i < 30; i++)
            fixture(now.add(Duration(hours: i)), id: 'trip-$i').occurrence!,
        ];
        await local.reconcile([
          CommuteSchedule({
            'id': 's',
            'name': 'Lịch',
            'enabled': true,
            'upcoming_occurrences': rows,
          }),
        ], now: now);
        expect(pending, hasLength(56));
        await local.receive([
          for (var i = 0; i < 8; i++)
            {
              'id': 'reminder-$i',
              'title': 'Nhắc lại',
              'schedule_name': 'Đi học',
              'scheduled_for': now
                  .add(Duration(minutes: 5 + i))
                  .toIso8601String(),
            },
        ]);
        expect(pending, hasLength(60));
        await local.testDelivery();
        expect(pending.length, lessThan(64));
      },
    );

    test('Receipt prevents duplicate backend banner and smoke test schedules real native alarm', () async {
      final now = DateTime.now().toUtc();
      await local.reconcile([fixture(now)], now: now);
      await prefs.setString(
        local.receiptKey,
        jsonEncode({
          ...local.readMap(local.receiptKey),
          'local:trip:departure_due': now
              .subtract(const Duration(seconds: 5))
              .toIso8601String(),
        }),
      );
      await local.receive([
        {
          'id': 'server',
          'occurrence_id': 'trip',
          'kind': 'departure_due',
          'title': 'Đi',
          'created_at': now.toIso8601String(),
          'schedule_name': 'Đi học',
        },
      ]);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
      await local.receive([
        {
          'id': 'stale-server',
          'occurrence_id': 'trip',
          'kind': 'preparation_due',
          'title': 'Đi',
          'created_at': now.toIso8601String(),
          'schedule_name': 'Đi học',
        },
      ]);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
      await local.testDelivery();
      expect(calls.where((c) => c.method == 'zonedSchedule'), hasLength(5));
    });
  });
}

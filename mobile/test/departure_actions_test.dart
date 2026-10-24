import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/departure/controller.dart';
import 'package:trafficgo/features/departure/day_exception.dart';
import 'package:trafficgo/features/departure/local_notifications.dart';
import 'package:trafficgo/features/departure/models.dart';

import 'departure_test.dart' as fixture;

import 'package:trafficgo/core/models.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/departure/screens.dart';
import 'package:trafficgo/features/map/map_screen.dart';
import 'package:latlong2/latlong.dart';

class Recorder extends DepartureController {
  String? path;
  Map<String, dynamic>? sent;
  Recorder(super.dio, super.prefs);
  @override
  Future<void> mutate(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    this.path = path;
    sent = data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Notification payload preserves event identity and rejects cross-account actions', () {
    final payload = jsonEncode({
      'event_id': 'event-one',
      'scope': 'account:a:',
    });
    for (final action in ['start', 'snooze', 'skip']) {
      final intent = DepartureLocalNotifications.decodeIntent(
        payload,
        action,
        'account:a:',
      );
      expect(intent?['event_id'], 'event-one');
      expect(intent?['action'], action);
    }
    expect(
      DepartureLocalNotifications.decodeIntent(
        payload,
        null,
        'account:a:',
      )?['action'],
      'open',
    );
    expect(
      DepartureLocalNotifications.decodeIntent(payload, 'skip', 'account:b:'),
      isNull,
    );
    expect(
      DepartureLocalNotifications.decodeIntent(payload, 'delete', 'account:a:'),
      isNull,
    );
    expect(
      DepartureLocalNotifications.decodeIntent('broken', null, ''),
      isNull,
    );
    expect(
      DepartureLocalNotifications.eventId('one'),
      DepartureLocalNotifications.eventId('one'),
    );
  });

  for (final action in const {
    'skip': 'Nghỉ / bỏ qua ngày này',
    'change': 'Đổi giờ ngày này',
    'reset': 'Khôi phục theo lịch tuần',
  }.entries) {
    testWidgets('Day exception sends only one date: ${action.key}', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio();
      final c = Recorder(dio, prefs);
      await c.ready;
      final original = Map<String, dynamic>.from(
        (fixture.overview()['schedules'] as List).first,
      );
      final snapshot = jsonEncode(original);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            departureProvider.overrideWith((ref) => c),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DayExceptionEditor(schedule: CommuteSchedule(original)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(action.value));
      await tester.tap(find.text(action.value));
      await tester.pumpAndSettle();
      expect(c.path, startsWith('schedules/one/exceptions/'));
      expect(c.sent?['action'], action.key);
      expect(c.sent?.containsKey('weekdays'), false);
      expect(jsonEncode(original), snapshot);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      dio.close();
    });
  }

  test('Offline notification action fails without claiming success', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.reject(
          DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          ),
        ),
      ),
    );
    final c = DepartureController(dio, prefs);
    await c.ready;
    await expectLater(
      c.notificationAction('event-one', 'snooze'),
      throwsA(isA<DioException>()),
    );
    expect(c.notificationActions, isEmpty);
    expect(c.events, isEmpty);
    c.dispose();
    dio.close();
  });
  test('Android schedules one durable snooze with action buttons and cancels on skip', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {'notificationLaunchedApp': false};
          }
          return null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    SharedPreferences.setMockInitialValues({
      'account:a:departure-local-notifications': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final notifications = DepartureLocalNotifications(
      prefs,
      prefix: 'account:a:',
    );
    await notifications.initialize();
    final event = <String, dynamic>{
      'id': 'reminder-one',
      'title': 'Nhắc lại',
      'schedule_name': 'Nhà → CMC',
      'scheduled_for': DateTime.now()
          .add(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
    };
    await notifications.receive([event]);
    await notifications.receive([event]);
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(scheduled, hasLength(1));
    final args = Map<String, dynamic>.from(scheduled.single.arguments);
    expect(jsonDecode(args['payload'])['event_id'], 'reminder-one');
    expect((args['platformSpecifics']['actions'] as List), hasLength(3));
    expect(args['platformSpecifics']['scheduleMode'], 'inexactAllowWhileIdle');
    await notifications.receive([
      {...event, 'cancelled': true},
    ]);
    expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
    expect(
      prefs.getStringList('account:a:departure-pending-reminders'),
      isEmpty,
    );
  });
  testWidgets(
    'Notification opens the saved inbound trip and exact occurrence',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = JourneyStore(prefs);
      const outbound = SavedTrip(
        'Đi học',
        Place('Nhà', LatLng(21, 105.8)),
        Place('CMC', LatLng(21.01, 105.81)),
        vehicle: 'motorcycle',
      );
      const inbound = SavedTrip(
        'Về nhà',
        Place('CMC', LatLng(21.01, 105.81)),
        Place('Nhà', LatLng(21, 105.8)),
        vehicle: 'motorcycle',
      );
      await store.saveJourney(
        const Journey(
          id: 'school',
          name: 'Đi học',
          outbound: outbound,
          inbound: inbound,
        ),
      );
      final api = fixture.CommutePreviewApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            journeysProvider.overrideWith((ref) => store),
            apiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openCommuteRoute(context, {
                    'journey_id': 'school',
                    'direction': 'inbound',
                    'vehicle': 'motorcycle',
                    'origin': {'lat': 21.01, 'lon': 105.81},
                    'destination': {'lat': 21.0, 'lon': 105.8},
                    'occurrence': {'id': 'inbound-today'},
                  }),
                  child: const Text('Mở thông báo'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở thông báo'));
      await tester.pumpAndSettle();
      final map = tester.widget<MapScreen>(find.byType(MapScreen));
      expect(map.plannedTrip, same(inbound));
      expect(map.direction, 'inbound');
      expect(map.occurrenceId, 'inbound-today');
      expect(map.autoStartNavigation, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dio.close();
    },
  );
}

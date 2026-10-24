import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/models.dart';
import 'package:trafficgo/features/onboarding/accounts.dart';
import 'package:trafficgo/features/onboarding/screens.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/maintenance/store.dart';

class LocalAdapter implements HttpClientAdapter {
  bool offline = false;
  final List<Map<String, dynamic>> setups = [];
  final profile = <String, dynamic>{
    'user_id': 'student',
    'username': 'student',
    'profile': {'setup_complete': false},
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (offline) {
      throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
      );
    }
    Object data = profile;
    if (o.path.endsWith('/overview')) {
      data = {
        'schedules': [],
        'notifications': [],
        'worker': {},
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };
    }
    if (o.path.endsWith('/login') || o.path.endsWith('/register')) {
      data = {...profile, 'token': 'test-private-session'};
    }
    if (o.path.endsWith('/setup')) {
      setups.add(Map<String, dynamic>.from(o.data));
      profile['profile'] = {...o.data, 'setup_complete': true};
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class SetupAccount extends AccountController {
  SetupAccount(super.prefs, {super.client});
  @override
  Future<void> restore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'access': 'test-shared-access'});
  });
  test('Guest data and account vehicle / route / expenses stay separate after restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final guest = AppState(prefs);
    await guest.save(const Place('Nhà khách', LatLng(21, 105.8)));
    final old = JourneyStore(prefs);
    await old.saveJourney(const Journey(id: 'guest', name: 'Tuyến khách'));
    await prefs.setString('active-account-id', 'alice');
    final a = AppState(prefs),
        garageA = GarageStore(prefs),
        journeyA = JourneyStore(prefs);
    expect(a.saved, isEmpty);
    expect(journeyA.journeys, isEmpty);
    await a.save(const Place('Nhà Alice', LatLng(21.1, 105.8)));
    await garageA.saveVehicle({
      'id': 'wave',
      'name': 'Wave của Alice',
      'model_id': 'wave_alpha',
      'year': 2020,
      'variant': 'Thường',
      'odometer': 100,
    });
    await journeyA.saveJourney(const Journey(id: 'alice-trip', name: 'Đi học'));
    await prefs.setString('active-account-id', 'bob');
    expect(AppState(prefs).saved, isEmpty);
    expect(GarageStore(prefs).vehicles, isEmpty);
    expect(JourneyStore(prefs).journeys, isEmpty);
    // Old objects never write into the newly active namespace.
    await a.save(const Place('Trường Alice', LatLng(21.2, 105.8)));
    expect(AppState(prefs).saved, isEmpty);
    await prefs.setString('active-account-id', 'alice');
    expect(AppState(prefs).saved.length, 2);
    expect(GarageStore(prefs).vehicles.single['id'], 'wave');
    expect(JourneyStore(prefs).journeys.single.id, 'alice-trip');
    await prefs.remove('active-account-id');
    expect(AppState(prefs).saved.single.name, 'Nhà khách');
    expect(JourneyStore(prefs).journeys.single.id, 'guest');
  });
  test('Login, setup failure, successful retry and logout keep credentials out of preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final adapter = LocalAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final c = AccountController(prefs, client: dio);
    await c.ready;
    await c.authenticate('student', 'test-password-123', register: true);
    expect(c.id, 'student');
    expect(c.complete, false);
    expect(
      prefs.getString('account:student:profile'),
      isNot(contains('test-private-session')),
    );
    adapter.offline = true;
    await expectLater(
      c.setup({'display_name': 'Sinh viên'}),
      throwsA(isA<DioException>()),
    );
    expect(c.complete, false);
    adapter.offline = false;
    await c.setup({'display_name': 'Sinh viên'});
    expect(c.complete, true);
    await c.logout();
    expect(c.id, isNull);
    expect(prefs.getString('account:student:profile'), isNotNull);
    c.dispose();
  });
  testWidgets(
    'Mandatory setup validates name and motorcycle before letting user continue',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active-account-id', 'student');
      final adapter = LocalAdapter();
      final c = SetupAccount(
        prefs,
        client: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = adapter,
      );
      c.account = Map<String, dynamic>.from(adapter.profile);
      // Keep all HTTP work outside the widget fake clock.
      await t.runAsync(() async {
        await c.ready;
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            accountProvider.overrideWith((ref) => c),
          ],
          child: const MaterialApp(home: PersonalSetupScreen()),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Tiếp tục'));
      await t.pumpAndSettle();
      expect(find.text('Nhập tên hiển thị của bạn.'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Tùng');
      await t.tap(find.text('Tiếp tục'));
      await t.pumpAndSettle();
      expect(find.text('Bước 2/5 · Xe của bạn'), findsOneWidget);
      await t.tap(find.text('Tiếp tục'));
      await t.pumpAndSettle();
      expect(find.text('Thêm và chọn xe của bạn.'), findsOneWidget);
      expect(c.complete, false);
      expect(adapter.setups, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Setup draft resumes on restart and preserves exact selected geometry',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active-account-id', 'student');
      final route = TravelRoute(
        id: 'exact-route',
        meters: 7600,
        seconds: 1500,
        points: const [LatLng(21.02, 105.85), LatLng(21.04, 105.82)],
        retrievedAt: DateTime.utc(2026),
        provider: 'valhalla',
      );
      final trip = SavedTrip(
        'Nhà → Trường',
        const Place('Nhà', LatLng(21.02, 105.85)),
        const Place('Trường', LatLng(21.04, 105.82)),
        route: route,
      );
      await prefs.setString(
        'account:student:setup-draft.v1',
        jsonEncode({
          'name': 'Tùng',
          'purpose': 'school',
          'vehicle': 'car',
          'step': 4,
          'home': trip.origin.toJson(),
          'destination': trip.destination.toJson(),
          'trip': trip.toJson(),
          'hour': 7,
          'minute': 30,
          'days': [0, 1, 2, 3, 4],
          'preparation': 15,
          'buffer': 10,
        }),
      );
      final adapter = LocalAdapter();
      final c = SetupAccount(
        prefs,
        client: Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = adapter,
      );
      c.account = Map<String, dynamic>.from(adapter.profile);
      // Keep all HTTP work outside the widget fake clock.
      await t.runAsync(() async {
        await c.ready;
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            accountProvider.overrideWith((ref) => c),
          ],
          child: const MaterialApp(home: PersonalSetupScreen()),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Bước 5/5 · Lịch đi lại'), findsOneWidget);
      // Going back/reopening must not replace geometry with a newly calculated route.
      await t.ensureVisible(find.text('Quay lại'));
      await t.pumpAndSettle();
      await t.tap(find.text('Quay lại'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.textContaining('valhalla'), 200);
      expect(find.textContaining('valhalla'), findsOneWidget);
      await t.binding.setSurfaceSize(const Size(320, 694));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final stored = jsonDecode(
        prefs.getString('account:student:setup-draft.v1')!,
      );
      expect(stored['trip']['route']['id'], 'exact-route');
      expect(stored['trip']['route']['geometry'].length, 2);
      expect(adapter.setups, isEmpty);
      await t.scrollUntilVisible(find.text('Tiếp tục'),150);
      await t.pumpAndSettle();
      await t.tap(find.text('Tiếp tục'));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).last, const Offset(0, -500));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Hoàn tất và tạo lịch'),150);
      await t.pumpAndSettle();
      await t.tap(find.text('Hoàn tất và tạo lịch'));
      await t.pumpAndSettle();
      expect(c.complete, true);
      expect(adapter.setups.length, 1);
      final saved = JourneyStore(prefs).journeys.single;
      expect(saved.outbound!.route!.id, 'exact-route');
      expect(saved.outbound!.route!.points, route.points);
      final schedule = adapter.setups.single['schedule'];
      expect(schedule['journey_id'], saved.id);
      expect(schedule['initial_eta_s'], 1500);
      expect(schedule['arrival_time'], '07:30');
      expect(schedule['preparation_minutes'], 15);
      expect(schedule['buffer_minutes'], 10);
      expect(prefs.getString('account:student:default-vehicle'), 'car');
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}

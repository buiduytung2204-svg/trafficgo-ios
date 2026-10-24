import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:trafficgo/app/app.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/core/models.dart';
import 'package:trafficgo/features/settings/screens.dart';
import 'package:trafficgo/features/map/map_screen.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trafficgo/core/tile_client.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:trafficgo/features/map/camera_session.dart';

class SearchApi extends TrafficApi {
  final bool offline;
  SearchApi({this.offline = false}) : super('');
  @override
  Future<List<Place>> search(
    String query,
    LatLng near,
    CancelToken cancel,
  ) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      );
    }
    return [];
  }
}

void main() {
  test('Manual pan suspends GPS camera follow and keeps viewport', () {
    final session = CameraSession()..following = true;
    session.update(const LatLng(21.01, 105.77), 15.5, 32, gesture: true);
    expect(session.following, false);
    expect(session.gestureRevision, 1);
    expect(session.zoom, 15.5);
    expect(session.rotation, 32);
  });
  testWidgets('Tile failure and refresh preserve map camera', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    const center = LatLng(21.01, 105.77);
    controller.move(center, 15.5);
    controller.rotate(32);
    await tester.pump();
    final dynamic screen = tester.state(find.byType(MapScreen));
    screen.tileFailure('Traffic: Đã đạt giới hạn request/ngày.');
    await tester.pump();
    await tester.pump();
    expect(screen.tileError, contains('Traffic: Đã đạt giới hạn'));
    expect(find.textContaining('Traffic: Đã đạt giới hạn'), findsOneWidget);
    expect(controller.camera.center.latitude, closeTo(center.latitude, 1e-5));
    expect(controller.camera.center.longitude, closeTo(center.longitude, 1e-5));
    expect(controller.camera.zoom, 15.5);
    expect(controller.camera.rotation, 32);
    await tester.tap(find.byTooltip('Tải lại bản đồ'));
    await tester.pump();
    expect(controller.camera.center.latitude, closeTo(center.latitude, 1e-5));
    expect(controller.camera.zoom, 15.5);
    expect(controller.camera.rotation, 32);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'Tile 429 preserves reason and pauses requests until Retry-After',
    () async {
      var calls = 0;
      String? message;
      final client = TileClient(
        () {},
        onFailure: (value) => message = value,
        client: MockClient((request) async {
          calls++;
          return http.Response(
            '{"detail":"Daily budget reached"}',
            429,
            headers: {'retry-after': '60', 'content-type': 'application/json'},
          );
        }),
      );
      expect(
        (await client.get(Uri.parse('http://localhost/tile.png'))).statusCode,
        429,
      );
      expect(message, 'Daily budget reached');
      expect(
        (await client.get(Uri.parse('http://localhost/another.png')))
            .statusCode,
        429,
      );
      expect(calls, 1);
      client.close();
    },
  );
  test('ETA rounds up and supports hours', () {
    expect(formatEta(61), '2 phút');
    expect(formatEta(3660), '1 giờ 1 phút');
  });
  test('Place roundtrip and normalized route', () {
    const p = Place('Nhà', LatLng(21.02, 105.85));
    expect(Place.fromJson(p.toJson()).point, p.point);
    final r = TravelRoute.fromJson({
      'id': 'r',
      'distance_m': 200,
      'duration_s': 60,
      'geometry': [
        {'lat': 21.02, 'lon': 105.85},
      ],
      'retrieved_at': '2026-10-23T01:00:00Z',
    });
    expect(r.seconds, 60);
    expect(r.delay, isNull);
  });
  test('Route sorting leaves original list unchanged', () {
    TravelRoute r(String id, int seconds) => TravelRoute(
      id: id,
      meters: 100,
      seconds: seconds,
      points: [],
      retrievedAt: DateTime(2026),
    );
    final original = [r('a', 600), r('b', 300)];
    expect(fastestRoutes(original).first.id, 'b');
    expect(original.first.id, 'a');
  });
  test('Reroute savings and cooldown', () {
    expect(shouldSuggest(1200, 900, const Duration(minutes: 6)), true);
    expect(shouldSuggest(1200, 900, const Duration(minutes: 1)), false);
    expect(shouldSuggest(1200, 1100, const Duration(minutes: 6)), false);
  });
  test('Saved trips store endpoints without provider geometry', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);
    state.saveTrip(
      const SavedTrip(
        'Đi làm',
        Place('Nhà', LatLng(21.02, 105.85)),
        Place('Công ty', LatLng(21.04, 105.82)),
      ),
    );
    final restored = AppState(prefs);
    expect(restored.trips.single.destination.name, 'Công ty');
    expect(prefs.getString('trips'), isNot(contains('geometry')));
  });
  test('Distance uses segments rather than sparse vertices', () {
    expect(
      distanceToRoute(const LatLng(21.02, 105.855), [
        const LatLng(21.02, 105.85),
        const LatLng(21.02, 105.86),
      ]),
      lessThan(1),
    );
    expect(
      distanceToRoute(const LatLng(21.03, 105.855), [
        const LatLng(21.02, 105.85),
        const LatLng(21.02, 105.86),
      ]),
      greaterThan(1000),
    );
  });
  test('Offline errors are readable', () {
    expect(
      errorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      ),
      contains('Internet'),
    );
  });
  test('Timeout and server errors are distinct from offline', () {
    final request = RequestOptions(path: '/api/v1/routes/calculate');
    expect(
      errorMessage(
        DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        ),
      ),
      contains('phản hồi quá chậm'),
    );
    expect(
      errorMessage(
        DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 500),
        ),
      ),
      contains('HTTP 500'),
    );
    expect(
      TrafficApi('').dio.options.receiveTimeout,
      const Duration(seconds: 30),
    );
  });
  testWidgets('Onboarding explains foreground location', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: HomeGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bắt đầu khám phá'), findsOneWidget);
    expect(find.textContaining('Không theo dõi nền'), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });
  testWidgets('Settings show motorcycle limitation and persistence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Lớp giao thông'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(prefs.getBool('traffic'), false);
    await tester.scrollUntilVisible(
      find.text('Phương tiện mặc định: Ô tô'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Phương tiện mặc định: Ô tô'), findsOneWidget);
  });
  testWidgets('Onboarding supports large text on iPhone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const HomeGate(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Bắt đầu khám phá'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(tester.takeException(), isNull);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });
  testWidgets('Saved places empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SavedScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Những nơi thân quen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('iPhone map switches to motorcycle', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    expect(find.text('TrafficGo'), findsOneWidget);
    expect(find.text('Kết nối backend để mở bản đồ thật'), findsOneWidget);
    await tester.drag(find.text('Chào Hà Nội!'), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xe máy'));
    await tester.pump();
    expect(
      find.textContaining('Tuân thủ biển báo và đường cấm xe máy thực tế.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final offline in [false, true]) {
    testWidgets('Search ${offline ? 'offline error' : 'empty response'}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            apiProvider.overrideWithValue(SearchApi(offline: offline)),
          ],
          child: const MaterialApp(home: MapScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hoàn Kiếm');
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(
        find.textContaining(
          offline ? 'Kiểm tra Internet' : 'Không tìm thấy địa điểm',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

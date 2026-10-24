import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/features/departure/controller.dart';
import 'package:trafficgo/features/departure/models.dart';
import 'package:trafficgo/features/departure/screens.dart';
import 'package:trafficgo/features/map/map_screen.dart';
import 'package:trafficgo/core/models.dart';
import 'package:latlong2/latlong.dart';

class CommutePreviewApi extends TrafficApi {
  LatLng? requestedOrigin;
  String? requestedVehicle;
  CommutePreviewApi() : super('');
  @override
  Future<List<TravelRoute>> routes(
    LatLng origin,
    Place destination, {
    bool refresh = false,
    String vehicle = 'car',
  }) async {
    requestedOrigin = origin;
    requestedVehicle = vehicle;
    return [];
  }
}

Map<String, dynamic> overview() => {
  'synced_at': '2026-10-26T00:00:00Z',
  'worker': {},
  'notifications': [],
  'schedules': [
    {
      'id': 'one',
      'name': 'Đi học CMC',
      'enabled': true,
      'origin': {'lat': 21.0, 'lon': 105.8},
      'destination': {'lat': 21.01, 'lon': 105.81},
      'origin_name': 'Nhà',
      'destination_name': 'CMC',
      'arrival_time': '07:30',
      'vehicle': 'motorcycle',
      'weekdays': [0, 1, 2, 3, 4],
      'preparation_minutes': 15,
      'buffer_minutes': 10,
      'initial_eta_s': 1500,
      'occurrence': {
        'id': 'trip',
        'status': 'planned',
        'eta_s': 1500,
        'eta_source': 'initial_estimate',
        'traffic_aware': false,
        'arrival_at': '2099-10-26T07:30:00+07:00',
        'prepare_at': '2099-10-26T06:40:00+07:00',
        'departure_at': '2099-10-26T06:55:00+07:00',
      },
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Scheduled route uses saved origin without pretending it is GPS',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = CommutePreviewApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            apiProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(
            home: MapScreen(
              plannedTrip: SavedTrip(
                'Đi học',
                Place('Nhà', LatLng(21, 105.8)),
                Place('CMC', LatLng(21.01, 105.81)),
              ),
              plannedVehicle: 'motorcycle',
            ),
          ),
        ),
      );
      await tester.drag(
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.text('CMC'),
        ),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tìm đường theo lịch đã lưu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tìm đường theo lịch đã lưu'));
      await tester.pumpAndSettle();
      expect(api.requestedOrigin?.latitude, 21);
      expect(api.requestedVehicle, 'motorcycle');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dio.close();
    },
  );
  test('Vietnam display and countdown ignore host timezone', () {
    expect(vietnamTime('2026-10-25T23:40:00Z'), '26/10 06:40');
    expect(
      departureCountdown(
        DateTime.utc(2026, 1, 1, 1, 5),
        DateTime.utc(2026, 1, 1, 1),
      ),
      'Còn 5 phút',
    );
    expect(
      departureCountdown(DateTime.utc(2026), DateTime.utc(2026)),
      'Đã đến giờ xuất phát',
    );
    final schedule = CommuteSchedule(overview()['schedules'][0]);
    expect(schedule.input().containsKey('occurrence'), isFalse);
    expect(schedule.input()['vehicle'], 'motorcycle');
  });

  test('Sync attaches installation credential, persists cache and fails honestly offline', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'departure-session:$apiBase': 'private-install-token',
    });
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: apiBase));
    bool offline = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.headers['X-Schedule-Token'], 'private-install-token');
          if (offline) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError,
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: request,
                data: overview(),
                statusCode: 200,
              ),
            );
          }
        },
      ),
    );
    final controller = DepartureController(dio, prefs);
    await controller.ready;
    expect(controller.online, isTrue);
    expect(controller.next?.name, 'Đi học CMC');
    expect(prefs.getString(controller.cacheKey), isNotNull);
    offline = true;
    await controller.refresh();
    expect(controller.online, isFalse);
    expect(controller.schedules.single.name, 'Đi học CMC');
    expect(controller.error, contains('chưa đồng bộ'));
    await expectLater(
      controller.save(controller.schedules.single.input()),
      throwsStateError,
    );
    controller.dispose();
    dio.close();
  });

  testWidgets('Offline schedule list shows cached times and disables writes', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'departure-overview:$apiBase': jsonEncode(overview()),
    });
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    final controller = DepartureController(dio, prefs);
    await controller.ready;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          departureProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: SchedulesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đi học CMC'), findsOneWidget);
    expect(find.textContaining('chỉ xem bản lưu'), findsOneWidget);
    expect(find.textContaining('Chuẩn bị: 26/10 06:40'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    dio.close();
  });

  testWidgets(
    'Editor validates missing endpoints and supports choosing motorcycle',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [preferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: ScheduleEditor()),
        ),
      );
      await tester.tap(find.text('Xe máy'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Lưu và đồng bộ'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu và đồng bộ'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Tên lịch'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/features/map/map_screen.dart';
import 'package:trafficgo/features/map/route_option.dart';
import 'package:trafficgo/features/journeys/screens.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:trafficgo/core/models.dart';
import 'package:trafficgo/features/journeys/store.dart';

class NoRoutingApi extends TrafficApi {
  int calls = 0;
  NoRoutingApi() : super('');
  @override
  Future<List<TravelRoute>> routes(
    LatLng origin,
    Place destination, {
    bool refresh = false,
    String vehicle = 'car',
  }) async {
    calls++;
    throw StateError('Saved preview must not recalculate');
  }
}

void main() {
  const origin = Place('Nhà', LatLng(21, 105.8));
  const destination = Place('Trường', LatLng(21.01, 105.81));
  final route = TravelRoute(
    id: 'selected-alternative',
    meters: 1700,
    seconds: 420,
    points: [origin.point, const LatLng(21.005, 105.82), destination.point],
    retrievedAt: DateTime.utc(2026, 10, 24),
    provider: 'valhalla',
  );
  final trip = SavedTrip(
    'Đi học',
    origin,
    destination,
    route: route,
    vehicle: 'motorcycle',
  );
  test(
    'Saved selected geometry, vehicle and source survive JSON roundtrip',
    () {
      final restored = SavedTrip.fromJson(
        jsonDecode(jsonEncode(trip.toJson())),
      );
      expect(restored.route!.id, 'selected-alternative');
      expect(restored.route!.points, route.points);
      expect(restored.vehicle, 'motorcycle');
      expect(restored.route!.trafficAware, false);
      final legacy = SavedTrip.fromJson({
        'name': 'Cũ',
        'origin': origin.toJson(),
        'destination': destination.toJson(),
      });
      expect(legacy.route, isNull);
    },
  );
  test(
    'Independent directions, expenses and completed trips survive restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = JourneyStore(prefs);
      await store.saveJourney(
        Journey(id: 'school', name: 'Nhà — Trường', outbound: trip),
      );
      expect(store.journeys.single.inbound, isNull);
      final inbound = SavedTrip(
        'Về',
        destination,
        origin,
        route: TravelRoute(
          id: 'return',
          meters: 2000,
          seconds: 500,
          points: [
            destination.point,
            const LatLng(21.02, 105.83),
            origin.point,
          ],
          retrievedAt: DateTime.now(),
          provider: 'valhalla',
        ),
      );
      await store.saveJourney(store.journeys.single.copy(inbound: inbound));
      await store.saveExpense(
        const Expense(
          id: 'e',
          category: 'parking',
          date: '2026-10-24',
          amount: 5000,
          journeyId: 'school',
          direction: 'outbound',
        ),
      );
      expect(store.completed, isEmpty);
      await store.complete(
        'session',
        trip: trip,
        journeyId: 'school',
        direction: 'outbound',
      );
      await store.complete('session', trip: trip);
      final restored = JourneyStore(prefs);
      expect(restored.completed.length, 1);
      expect(restored.journeys.single.inbound!.route!.id, 'return');
      expect(restored.journeys.single.outbound!.route!.points, route.points);
      expect(
        restored.total(DateTime(2026, 10, 24), DateTime(2026, 10, 25)),
        5000,
      );
      expect(restored.total(DateTime(2026, 10, 25), DateTime(2026, 10, 26)), 0);
      await restored.deleteJourney('school');
      expect(restored.expenses.length, 1);
      expect(restored.completed.length, 1);
    },
  );
  test(
    'Expense edit replaces entry; negative and invalid values rejected',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = JourneyStore(await SharedPreferences.getInstance());
      await expectLater(
        store.saveExpense(
          const Expense(
            id: 'x',
            category: 'fuel',
            date: '2026-10-24',
            amount: -1,
          ),
        ),
        throwsArgumentError,
      );
      await store.saveExpense(
        const Expense(
          id: 'x',
          category: 'fuel',
          date: '2026-10-24',
          amount: 10000,
        ),
      );
      await store.saveExpense(
        const Expense(
          id: 'x',
          category: 'fuel',
          date: '2026-10-24',
          amount: 20000,
        ),
      );
      expect(store.expenses.length, 1);
      expect(store.expenses.single.amount, 20000);
      await store.deleteExpense('x');
      expect(JourneyStore(store.prefs).expenses, isEmpty);
    },
  );
  test('Damaged local document is preserved instead of reset', () async {
    SharedPreferences.setMockInitialValues({'journeys.v1': 'invalid'});
    final prefs = await SharedPreferences.getInstance();
    final store = JourneyStore(prefs);
    await expectLater(
      store.saveJourney(const Journey(id: 'x', name: 'x')),
      throwsStateError,
    );
    expect(prefs.getString('journeys.v1'), 'invalid');
  });
  testWidgets(
    'Opening a saved route renders its snapshot without calling routing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = NoRoutingApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            apiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(home: MapScreen(plannedTrip: trip)),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      expect(
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.text('Trường'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byType(RouteOption),
        200,
        scrollable: find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<RouteOption>(find.byType(RouteOption)).fastest,
        isFalse,
        reason:
            'One saved snapshot is not evidence of the fastest available route',
      );
      expect(api.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dio.close();
    },
  );
  testWidgets(
    'Planner hides coordinates and swapping endpoints invalidates saved geometry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [preferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(home: RoutePlanner(initial: trip)),
        ),
      );
      expect(find.text('Vĩ độ'), findsNothing);
      expect(find.text('Kinh độ'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Lưu chính xác tuyến đã chọn'),
        200,
      );
      expect(find.text('Lưu chính xác tuyến đã chọn'), findsOneWidget);
      await tester.ensureVisible(find.text('Đảo hai điểm • tính tuyến mới'));
      await tester.tap(find.text('Đảo hai điểm • tính tuyến mới'));
      await tester.pump();
      expect(find.text('Lưu chính xác tuyến đã chọn'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

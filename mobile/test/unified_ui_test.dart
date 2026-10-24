import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/home_shell.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/core/models.dart';
import 'package:latlong2/latlong.dart';
import 'package:trafficgo/core/design/components.dart';
import 'package:trafficgo/core/design/sheets.dart';
import 'package:trafficgo/core/design/traffic_theme.dart';
import 'package:trafficgo/features/journeys/screens.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/map/map_screen.dart';
import 'package:trafficgo/features/map/route_option.dart';
import 'personalization_cases_test.dart' as fixtures;

Widget host(Widget child, SharedPreferences prefs, {TrafficApi? api}) =>
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        if (api != null) apiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: TrafficTokens.material(Brightness.light),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        builder: (c, child) => TrafficDesignScope(child: child!),
        home: child,
      ),
    );

class FasterTestApi extends TrafficApi {
  FasterTestApi() : super('');
  @override
  Future<List<TravelRoute>> routes(
    LatLng origin,
    Place destination, {
    bool refresh = false,
    String vehicle = 'car',
  }) async => [
    TravelRoute(
      id: 'proposal-test',
      meters: 7000,
      seconds: 600,
      points: fixtures.route().points,
      retrievedAt: DateTime.now(),
      provider: 'test-only',
    ),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('Vietnamese currency groups thousands without rounding expenses', () {
    expect(formatVnd(1250000), '1.250.000 VNĐ');
    expect(formatVnd(0), '0 VNĐ');
  });
  testWidgets('Four tabs retain the exact map state', (t) async {
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(host(const TrafficHomeShell(), prefs));
    await t.pumpAndSettle();
    final before = t.state(find.byType(MapScreen));
    final nav = find.byType(NavigationBar);
    for (final label in ['Hành trình', 'Cá nhân', 'Bản đồ']) {
      await t.tap(find.descendant(of: nav, matching: find.text(label)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
    expect(identical(before, t.state(find.byType(MapScreen))), isTrue);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Route card selection is explicit and has honest ETA source', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    var selected = false;
    await t.pumpWidget(
      host(
        Scaffold(
          body: RouteOption(
            route: fixtures.route(),
            selected: false,
            fastest: true,
            onTap: () => selected = true,
          ),
        ),
        prefs,
      ),
    );
    await t.pumpAndSettle();
    expect(selected, isFalse);
    expect(
      find.text('Thời gian ước tính chưa xét giao thông trực tiếp'),
      findsOneWidget,
    );
    await t.tap(find.byType(RouteOption));
    await t.pumpAndSettle();
    expect(selected, isTrue);
    expect(t.takeException(), isNull);
  });
  for (final accept in [false, true]) {
    testWidgets(
      'Reroute modal ${accept ? 'accepts' : 'rejects'} without overwriting saved geometry',
      (t) async {
        final prefs = await SharedPreferences.getInstance();
        final trip = fixtures.trip();
        await AppState(prefs).saveTrip(trip);
        await t.pumpWidget(
          host(MapScreen(plannedTrip: trip), prefs, api: FasterTestApi()),
        );
        await t.pumpAndSettle();
        final refresh = find.text('Tìm tuyến nhanh hơn / cập nhật ETA');
        await t.scrollUntilVisible(
          refresh,
          200,
          scrollable: find
              .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await t.pumpAndSettle();
        await t.tap(refresh);
        await t.pumpAndSettle();
        expect(find.text('So sánh tuyến đề xuất'), findsOneWidget);
        expect(
          t
              .widget<RouteOption>(
                find.byType(RouteOption, skipOffstage: false).first,
              )
              .route
              .id,
          trip.route!.id,
        );
        await t.tap(find.text(accept ? 'Xác nhận chuyển tuyến' : 'Giữ tuyến'));
        await t.pumpAndSettle();
        expect(
          t.widget<RouteOption>(find.byType(RouteOption).first).route.id,
          accept ? 'proposal-test' : trip.route!.id,
        );
        expect(AppState(prefs).trips.single.route!.id, trip.route!.id);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
      },
    );
  }
  testWidgets('Wolt expense form validates and saves one actual expense', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () =>
                  showTrafficEditor<void>(c, const ExpenseEditor()),
              child: const Text('Thêm khoản chi'),
            ),
          ),
        ),
        prefs,
      ),
    );
    await t.tap(find.text('Thêm khoản chi'));
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(JourneyStore(prefs).expenses, isEmpty);
    await t.enterText(find.byType(TextField).first, '50000');
    final save = find.text('Xác nhận lưu khoản chi');
    await t.scrollUntilVisible(
      save,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    await t.tap(save);
    await t.pumpAndSettle();
    expect(JourneyStore(prefs).expenses.single.amount, 50000);
    expect(find.byType(ExpenseEditor), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Shadcn calendar uses Wolt and commits only on confirmation', (
    t,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? selected;
    await t.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                selected = await pickTrafficDate(
                  c,
                  initialDate: DateTime(2026, 10, 24),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
              },
              child: const Text('Ngày'),
            ),
          ),
        ),
        prefs,
      ),
    );
    await t.tap(find.text('Ngày'));
    await t.pumpAndSettle();
    expect(selected, isNull);
    await t.tap(find.text('Chọn 24/10/2026'));
    await t.pumpAndSettle();
    expect(selected, DateTime(2026, 10, 24));
    expect(t.takeException(), isNull);
  });
}

import 'package:trafficgo/core/design/components.dart';
// Three isolated acceptance cases. Routing/places are test fixtures, never live traffic.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/core/models.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/maintenance/store.dart';
import 'package:trafficgo/features/maintenance/screens.dart';
import 'package:trafficgo/features/onboarding/accounts.dart';
import 'package:trafficgo/features/onboarding/screens.dart';
import 'personal_setup_test.dart' as fixture;

const home = Place('NHS Trung Văn — TEST', LatLng(20.994, 105.788));
const school = Place('Đại học CMC cơ sở 2 — TEST', LatLng(20.985, 105.798));
TravelRoute route() => TravelRoute(
  id: 'test-selected-2',
  meters: 7600,
  seconds: 1500,
  points: const [
    LatLng(20.994, 105.788),
    LatLng(20.99, 105.79),
    LatLng(20.985, 105.798),
  ],
  retrievedAt: DateTime.utc(2026, 10, 24),
  provider: 'test-fixture',
  trafficAware: false,
);
SavedTrip trip() => SavedTrip(
  'Nhà → Trường — TEST',
  home,
  school,
  vehicle: 'motorcycle',
  route: route(),
);
Map<String, dynamic> draft(int step) => {
  'name': 'Tùng kiểm thử',
  'purpose': 'school',
  'vehicle': 'motorcycle',
  'vehicle_id': 'wave-test',
  'step': step,
  'home': home.toJson(),
  'destination': school.toJson(),
  'trip': trip().toJson(),
  'days': [0, 1, 2, 3, 4],
  'hour': 7,
  'minute': 30,
  'preparation': 15,
  'buffer': 10,
};
Map<String, dynamic> bike() => {
  'id': 'wave-test',
  'name': 'Wave Alpha 2020 — TEST',
  'model_id': 'wave_alpha',
  'year': 2020,
  'variant': 'Thường',
  'odometer': 5990,
};

class FixtureApi extends TrafficApi {
  FixtureApi(fixture.LocalAdapter adapter) : super('test-shared-access') {
    dio.httpClientAdapter = adapter;
  }
  @override
  Future<List<TravelRoute>> routes(
    LatLng origin,
    Place destination, {
    bool refresh = false,
    String vehicle = 'car',
  }) async => [
    TravelRoute(
      id: 'test-slower',
      meters: 8000,
      seconds: 1800,
      points: route().points,
      retrievedAt: DateTime.utc(2026),
      provider: 'test-fixture',
    ),
    route(),
  ];
}

final boundary = GlobalKey();
late Map<String, dynamic> catalog;
Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await t.pumpAndSettle();
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/reports/personalization-cases/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget shell(
  SharedPreferences prefs,
  fixture.SetupAccount c,
  fixture.LocalAdapter adapter, {
  double scale = 1,
  bool dark = false,
  Widget? screen,
}) => ProviderScope(
  overrides: [
    preferencesProvider.overrideWithValue(prefs),
    hondaCatalogProvider.overrideWith((ref) async => catalog),
    accountProvider.overrideWith((ref) => c),
    apiProvider.overrideWith((ref) => FixtureApi(adapter)),
  ],
  child: RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff007c78),
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen ?? const PersonalSetupScreen(),
    ),
  ),
);
fixture.SetupAccount account(
  SharedPreferences prefs,
  fixture.LocalAdapter adapter,
) {
  final c = fixture.SetupAccount(
    prefs,
    client: Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter,
  );
  c.account = Map<String, dynamic>.from(adapter.profile);
  return c;
}

Future<void> press(WidgetTester t, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await t.scrollUntilVisible(
      find.text(text),
      250,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await t.ensureVisible(find.text(text).last);
  await t.pumpAndSettle();
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<SharedPreferences> base({int? step}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('active-account-id', 'student');
  await GarageStore(prefs).saveVehicle(bike());
  final state = AppState(prefs);
  await state.save(home);
  await state.save(school);
  if (step != null) {
    await prefs.setString(
      'account:student:setup-draft.v1',
      jsonEncode(draft(step)),
    );
  }
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    catalog = Map<String, dynamic>.from(
      jsonDecode(
        await File('assets/data/honda_vn_maintenance.json').readAsString(),
      ),
    );
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
    const path = String.fromEnvironment('QA_FONT_PATH');
    if (path.isNotEmpty) {
      final bytes = File(path).readAsBytesSync();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'access': 'test-shared-access'});
  });
  testWidgets(
    'CASE 1: new profile selects bike, both places and exact alternative; creates linked schedule',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final prefs = await base(),
          adapter = fixture.LocalAdapter(),
          c = account(prefs, adapter);
      await t.pumpWidget(shell(prefs, c, adapter));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Tùng kiểm thử');
      await press(t, 'Tiếp tục');
      await t.tap(find.text('Wave Alpha 2020 — TEST'));
      await t.pumpAndSettle();
      await capture(t, 'case1-vehicle');
      await press(t, 'Tiếp tục');
      await t.tap(find.text('Chọn Nhà / điểm xuất phát'));
      await t.pumpAndSettle();
      await t.tap(find.text(home.name).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Chọn nơi đến thường xuyên'));
      await t.pumpAndSettle();
      await t.tap(find.text(school.name).last);
      await t.pumpAndSettle();
      await capture(t, 'case1-places');
      await press(t, 'Tiếp tục');
      await press(t, 'Tìm và chọn tuyến chiều đi');
      await press(t, 'Tìm tuyến / cập nhật ETA');
      await t.tap(find.textContaining('25 phút').last);
      await t.pumpAndSettle();
      await press(t, 'Lưu chính xác tuyến đã chọn');
      await press(t, 'Tiếp tục');
      await capture(t, 'case1-schedule');
      await t.ensureVisible(find.text('Hoàn tất và tạo lịch'));
      await t.pumpAndSettle();
      await t.tap(find.text('Hoàn tất và tạo lịch'));
      await t.tap(find.text('Hoàn tất và tạo lịch'));
      await t.pumpAndSettle();
      expect(c.complete, true);
      expect(
        adapter.setups.length,
        1,
        reason: "Double tap must not submit setup twice",
      );
      final journeys = JourneyStore(prefs).journeys;
      expect(journeys.length, 1);
      expect(journeys.single.outbound!.route!.id, 'test-selected-2');
      expect(journeys.single.outbound!.route!.points, route().points);
      expect(t.takeException(), isNull);
      // Check the exact payload accepted by the isolated fixture backend.
      expect(c.account!['profile']['schedule']['initial_eta_s'], 1500);
      expect(c.account!['profile']['schedule']['arrival_time'], '07:30');
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'CASE 2: restart resumes draft; offline shows error; retry completes once without duplicate journey',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final prefs = await base(step: 4), adapter = fixture.LocalAdapter();
      var c = account(prefs, adapter);
      await t.pumpWidget(shell(prefs, c, adapter));
      await t.pumpAndSettle();
      expect(find.text('Bước 5/5 · Lịch đi lại'), findsOneWidget);
      adapter.offline = true;
      await press(t, 'Hoàn tất và tạo lịch');
      expect(c.complete, false);
      expect(prefs.getBool('account:student:onboarded') ?? false, false);
      expect(
        find.textContaining('Không kết nối được backend Windows'),
        findsOneWidget,
      );
      await capture(t, 'case2-offline');
      expect(prefs.getString('account:student:setup-draft.v1'), isNotNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      adapter.offline = false;
      c = account(prefs, adapter);
      await t.pumpWidget(shell(prefs, c, adapter));
      await t.pumpAndSettle();
      expect(find.text('Bước 5/5 · Lịch đi lại'), findsOneWidget);
      await press(t, 'Hoàn tất và tạo lịch');
      expect(c.complete, true);
      expect(adapter.setups.length, 1);
      expect(JourneyStore(prefs).journeys.length, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'CASE 3: account isolation plus all setup steps on small phone, large text and dark mode',
    (t) async {
      final prefs = await base();
      await JourneyStore(prefs).saveExpense(
        const Expense(
          id: 'fuel',
          category: 'fuel',
          date: '2026-10-24',
          amount: 50000,
        ),
      );
      await prefs.setString('active-account-id', 'other');
      expect(GarageStore(prefs).vehicles, isEmpty);
      expect(JourneyStore(prefs).expenses, isEmpty);
      expect(AppState(prefs).saved, isEmpty);
      await prefs.setString('active-account-id', 'student');
      expect(JourneyStore(prefs).expenses.single.amount, 50000);
      expect(GarageStore(prefs).vehicles.single['id'], 'wave-test');
      await t.binding.setSurfaceSize(const Size(320, 694));
      addTearDown(() => t.binding.setSurfaceSize(null));
      for (final dark in [false, true]) {
        for (var step = 0; step < 5; step++) {
          await prefs.setString(
            'account:student:setup-draft.v1',
            jsonEncode(draft(step)),
          );
          final adapter = fixture.LocalAdapter(),
              c = account(prefs, fixture.LocalAdapter());
          await t.pumpWidget(shell(prefs, c, adapter, scale: 2, dark: dark));
          await t.pumpAndSettle();
          await capture(t, 'case3-${dark ? 'dark' : 'light'}-step${step + 1}');
          expect(
            t.takeException(),
            isNull,
            reason: '320px, text200%, dark=$dark, step=$step',
          );
          final submit = find.widgetWithText(
            TrafficPrimaryButton,
            step == 4 ? 'Hoàn tất và tạo lịch' : 'Tiếp tục',
          );
          await t.scrollUntilVisible(
            submit,
            300,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 40,
          );
          await t.pumpAndSettle();
          await t.ensureVisible(submit);
          await t.pumpAndSettle();
          expect(t.getCenter(submit).dy, lessThan(694));
          expect(t.takeException(), isNull);
          if (step == 4) {
            await capture(
              t,
              'case3-${dark ? 'dark' : 'light'}-schedule-bottom',
            );
          }
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpAndSettle();
        }
      }
      // Vehicle selection form is part of first setup too.
      final catalog = jsonDecode(
        (await t.runAsync(
          () => File('assets/data/honda_vn_maintenance.json').readAsString(),
        ))!,
      );
      final adapter = fixture.LocalAdapter(),
          c = account(prefs, fixture.LocalAdapter());
      await t.pumpWidget(
        shell(
          prefs,
          c,
          adapter,
          scale: 2,
          dark: true,
          screen: VehicleEditor(catalog: Map<String, dynamic>.from(catalog)),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, 'case3-vehicle-editor');
      expect(t.takeException(), isNull, reason: 'vehicle editor large text');
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}

import 'personalization_cases_test.dart' as data;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/settings/screens.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/maintenance/store.dart';
import 'package:trafficgo/features/onboarding/accounts.dart';
import 'personal_setup_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'access': 'test-only'});
  });
  test(
    'Pending journey write survives provider disposal/account switch without notifying dead listeners',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active-account-id', 'before');
      final store = JourneyStore(prefs);
      final writing = store.saveJourney(
        const Journey(id: 'school', name: 'Đi học TEST'),
      );
      store.dispose();
      await prefs.setString('active-account-id', 'after');
      await expectLater(writing, completes);
      expect(JourneyStore(prefs).journeys, isEmpty);
      await prefs.setString('active-account-id', 'before');
      expect(JourneyStore(prefs).journeys.single.id, 'school');
    },
  );
  test(
    'Pending garage write survives disposal and remains in original account',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active-account-id', 'before');
      final store = GarageStore(prefs);
      final writing = store.saveVehicle({
        'id': 'wave',
        'name': 'Wave TEST',
        'model_id': 'wave_alpha',
        'year': 2020,
        'variant': 'Thường',
        'odometer': 1000,
      });
      store.dispose();
      await prefs.setString('active-account-id', 'after');
      await expectLater(writing, completes);
      expect(GarageStore(prefs).vehicles, isEmpty);
      await prefs.setString('active-account-id', 'before');
      expect(GarageStore(prefs).vehicles.single['id'], 'wave');
    },
  );
  test(
    'Expenses reject invalid calendar dates instead of silently moving them to next month',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = JourneyStore(prefs);
      for (final date in [
        '2026-02-31',
        '2026-02-29',
        '2026-13-01',
        '2026-00-10',
        '2026-10-24T09:00:00Z',
      ]) {
        await expectLater(
          store.saveExpense(
            Expense(id: date, category: 'fuel', amount: 50000, date: date),
          ),
          throwsArgumentError,
          reason: date,
        );
      }
      expect(store.expenses, isEmpty);
      await store.saveExpense(
        const Expense(
          id: 'leap',
          category: 'fuel',
          amount: 50000,
          date: '2024-02-29',
        ),
      );
      expect(store.total(DateTime(2024, 2, 1), DateTime(2024, 3, 1)), 50000);
    },
  );
  test('Recovered account connection clears stale offline error', () async {
    final prefs = await SharedPreferences.getInstance();
    final adapter = fixture.LocalAdapter();
    final c = AccountController(
      prefs,
      client: Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter,
    );
    await c.ready;
    await c.authenticate('student', 'test-password-123', register: true);
    adapter.offline = true;
    await c.restore();
    expect(c.error, isNotNull);
    adapter.offline = false;
    await c.restore();
    expect(c.error, isNull);
    c.dispose();
  });
  test('Default vehicle remains account scoped after restart', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active-account-id', 'a');
    await AppState(prefs).setDefaultVehicle('motorcycle');
    expect(AppState(prefs).defaultVehicle, 'motorcycle');
    await prefs.setString('active-account-id', 'b');
    expect(AppState(prefs).defaultVehicle, 'car');
  });
  testWidgets(
    'Settings shows actual motorcycle default and truthful local-delete scope',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await AppState(prefs).setDefaultVehicle('motorcycle');
      await t.pumpWidget(
        ProviderScope(
          overrides: [preferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Phương tiện mặc định: Xe máy'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Phương tiện mặc định: Xe máy'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Xóa địa điểm, tuyến và lịch sử tìm kiếm'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Giữ lại xe, hành trình, chi phí và lịch nhắc'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'Journey/expense CRUD, trip idempotency and history retention survive restart',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = JourneyStore(prefs);
      await store.saveJourney(
        Journey(id: 'school', name: 'School TEST', outbound: data.trip()),
      );
      await store.saveExpense(
        const Expense(
          id: 'fuel',
          category: 'fuel',
          date: '2026-10-24',
          amount: 50000,
          journeyId: 'school',
        ),
      );
      await store.saveExpense(
        const Expense(
          id: 'fuel',
          category: 'fuel',
          date: '2026-10-24',
          amount: 60000,
          journeyId: 'school',
        ),
      );
      expect(store.expenses.length, 1);
      expect(
        store.total(DateTime(2026, 10, 24), DateTime(2026, 10, 25)),
        60000,
      );
      await store.complete(
        'confirmed-trip',
        journeyId: 'school',
        direction: 'outbound',
        trip: data.trip(),
      );
      await store.complete(
        'confirmed-trip',
        journeyId: 'school',
        direction: 'outbound',
        trip: data.trip(),
      );
      expect(store.completed.length, 1);
      await store.deleteJourney('school');
      final reopened = JourneyStore(prefs);
      expect(reopened.journeys, isEmpty);
      expect(reopened.expenses.single.amount, 60000);
      expect(reopened.completed.length, 1);
      await reopened.deleteExpense('fuel');
      expect(JourneyStore(prefs).expenses, isEmpty);
    },
  );
}

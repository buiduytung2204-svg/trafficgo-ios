import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/journeys/screens.dart';

// Mirrors the saved Di hoc recurrence verified separately from the local DB.
// Isolated preferences only: never writes actual user expenses or GPS history.
Future<JourneyStore> weeklyFixture() async {
  SharedPreferences.setMockInitialValues({});
  final store = JourneyStore(await SharedPreferences.getInstance());
  await store.saveJourney(const Journey(id: 'TEST-Di-hoc', name: 'Di hoc'));
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (var i = 6; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    if (day.weekday <= 5) {
      await store.saveExpense(
        Expense(
          id: 'fuel-${day.toIso8601String()}',
          category: 'fuel',
          date: day.toIso8601String().split('T').first,
          amount: 50000,
          journeyId: 'TEST-Di-hoc',
          notes: 'SIMULATION_ONLY: daily fuel, not per direction',
        ),
      );
    }
  }
  await store.saveExpense(
    Expense(
      id: 'maintenance-week',
      category: 'other',
      date: today.toIso8601String().split('T').first,
      amount: 100000,
      journeyId: 'TEST-Di-hoc',
      notes: 'SIMULATION_ONLY: weekly maintenance',
    ),
  );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Five scheduled days: fuel250k + weekly maintenance100k =350k; survives reopen',
    () async {
      final store = await weeklyFixture();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start = today.subtract(const Duration(days: 6));
      expect(store.expenses.where((e) => e.category == 'fuel').length, 5);
      expect(
        store.expenses
            .where((e) => e.category == 'fuel')
            .fold<int>(0, (v, e) => v + e.amount),
        250000,
      );
      expect(
        store.expenses
            .where((e) => e.category == 'other')
            .fold<int>(0, (v, e) => v + e.amount),
        100000,
      );
      expect(store.total(start, today.add(const Duration(days: 1))), 350000);
      expect(store.expenses.every((e) => e.journeyId == 'TEST-Di-hoc'), true);
      expect(store.completed, isEmpty);
      final reopened = JourneyStore(store.prefs);
      expect(reopened.expenses.length, 6);
      expect(reopened.total(start, today.add(const Duration(days: 1))), 350000);
      final daily = [
        for (var i = 0; i < 7; i++)
          reopened.total(
            start.add(Duration(days: i)),
            start.add(Duration(days: i + 1)),
          ),
      ];
      expect(daily.fold<int>(0, (a, b) => a + b), 350000);
      expect(reopened.total(start.subtract(const Duration(days: 1)), start), 0);
    },
  );
  test(
    'Repeated weekly maintenance edit does not duplicate; edit/delete changes totals',
    () async {
      final store = await weeklyFixture();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final start = day.subtract(const Duration(days: 6));
      final maintenance = store.expenses.singleWhere(
        (e) => e.id == 'maintenance-week',
      );
      await store.saveExpense(maintenance);
      expect(store.expenses.length, 6);
      expect(store.total(start, day.add(const Duration(days: 1))), 350000);
      await store.saveExpense(
        Expense(
          id: maintenance.id,
          category: 'other',
          date: maintenance.date,
          amount: 80000,
          journeyId: maintenance.journeyId,
        ),
      );
      expect(store.total(start, day.add(const Duration(days: 1))), 330000);
      await store.deleteExpense(maintenance.id);
      expect(
        JourneyStore(
          store.prefs,
        ).total(start, day.add(const Duration(days: 1))),
        250000,
      );
      expect(store.completed, isEmpty);
    },
  );
  test(
    'Seven riding days is a distinct450k scenario; month boundaries are correct',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = JourneyStore(await SharedPreferences.getInstance());
      for (var i = 0; i < 7; i++) {
        final date = DateTime(2026, 10, 26).add(Duration(days: i));
        await store.saveExpense(
          Expense(
            id: 'all-days-$i',
            category: 'fuel',
            date: date.toIso8601String().split('T').first,
            amount: 50000,
          ),
        );
      }
      await store.saveExpense(
        const Expense(
          id: 'maintenance',
          category: 'other',
          date: '2026-11-01',
          amount: 100000,
        ),
      );
      expect(
        store.total(DateTime(2026, 10, 26), DateTime(2026, 11, 2)),
        450000,
      );
      expect(store.total(DateTime(2026, 10, 1), DateTime(2026, 11, 1)), 300000);
      expect(store.total(DateTime(2026, 11, 1), DateTime(2026, 12, 1)), 150000);
    },
  );
  testWidgets(
    'Statistics displays real store totals and seven daily bars without inventing completed trips',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await weeklyFixture();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(store.prefs),
            journeysProvider.overrideWith((ref) => store),
          ],
          child: const MaterialApp(home: ExpensesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chi phí 7 ngày'), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 7);
      expect(
        chart.data.barGroups.fold<double>(
          0,
          (sum, g) => sum + g.barRods.single.toY,
        ),
        350,
      );
      expect(find.text('250.000 VNĐ'), findsOneWidget);
      expect(find.text('100.000 VNĐ'), findsWidgets);
      // The same amount legitimately appears in the week/month summary and
      // journey breakdown; the chart above verifies the actual 7-day total.
      expect(find.text('350.000 VNĐ'), findsWidgets);
      expect(find.text('Di hoc'), findsOneWidget);
      expect(
        find.textContaining('Chuyến đã xác nhận hoàn thành: 0'),
        findsOneWidget,
      );
      expect(find.textContaining('Chưa có chuyến'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

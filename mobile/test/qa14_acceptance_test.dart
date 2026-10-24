// Accelerated QA data only. Never imports into the user's real preferences.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/design/traffic_theme.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/journeys/screens.dart';
import 'package:trafficgo/features/maintenance/store.dart';
import 'personalization_cases_test.dart' as fixture;

Map<String, dynamic> fallback() {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final start = end.subtract(const Duration(days: 13));
  final expenses = <Map<String, dynamic>>[];
  final completed = <Map<String, dynamic>>[];
  final workdays = List.generate(
    14,
    (i) => start.add(Duration(days: i)),
  ).where((d) => d.weekday <= 5).toList();
  for (var i = 0; i < 14; i++) {
    final day = start.add(Duration(days: i));
    final date = day.toIso8601String().substring(0, 10);
    expenses.add({
      'id': 'fuel-$i',
      'category': 'fuel',
      'date': date,
      'amount': 50000,
      'notes': 'QA simulation',
    });
    if (day.weekday <= 5) {
      expenses.add({
        'id': 'parking-$i',
        'category': 'parking',
        'date': date,
        'amount': 10000,
      });
      if (day != workdays[3]) {
        for (final direction in ['outbound', 'inbound']) {
          completed.add({
            'id': 'trip-$i-$direction',
            'name': 'QA SIMULATION',
            'completed_at': day.toIso8601String(),
          });
        }
      }
    }
    if (i == 6 || i == 13) {
      expenses.add({
        'id': 'service-$i',
        'category': 'other',
        'date': date,
        'amount': 100000,
      });
    }
  }
  return {
    'user_id': 'test-qa14',
    'date_from': start.toIso8601String().substring(0, 10),
    'date_until': end.toIso8601String().substring(0, 10),
    'preferences': {
      'journeys.v1': jsonEncode({
        'version': 1,
        'journeys': [
          Journey(
            id: 'qa14-school',
            name: 'QA14',
            outbound: fixture.trip(),
            inbound: fixture.trip(),
          ).toJson(),
        ],
        'expenses': expenses,
        'completed': completed,
      }),
      'saved': jsonEncode([fixture.home.toJson(), fixture.school.toJson()]),
      'trips': jsonEncode([fixture.trip().toJson()]),
      'garage.v1': jsonEncode({
        'vehicles': [fixture.bike()],
        'items': [],
        'history': [],
      }),
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> data;
  final checks = <String>[];
  setUpAll(() {
    const configured = String.fromEnvironment('QA_DATASET_PATH');
    data = configured.isEmpty
        ? fallback()
        : Map<String, dynamic>.from(
            jsonDecode(File(configured).readAsStringSync()),
          );
  });
  Future<SharedPreferences> prefs() async {
    SharedPreferences.setMockInitialValues({
      'active-account-id': data['user_id'],
      for (final e in (data['preferences'] as Map).entries)
        'account:${data['user_id']}:${e.key}': e.value,
    });
    FlutterSecureStorage.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test(
    '14 simulated days survive reopen:26 expenses,18 completed,1 million VND',
    () async {
      final p = await prefs();
      final s = JourneyStore(p);
      expect(s.expenses.length, 26);
      expect(s.completed.length, 18);
      expect(
        s.total(
          DateTime.parse(data['date_from']),
          DateTime.parse(data['date_until']).add(const Duration(days: 1)),
        ),
        1000000,
      );
      expect(s.expenses.map((e) => e.date).toSet().length, 14);
      expect(
        s.expenses
            .where((e) => e.category == 'fuel')
            .fold<int>(0, (s, e) => s + e.amount),
        700000,
      );
      expect(
        s.expenses
            .where((e) => e.category == 'parking')
            .fold<int>(0, (s, e) => s + e.amount),
        100000,
      );
      expect(JourneyStore(p).completed.length, 18);
      expect(AppState(p).saved.length, 2);
      expect(s.journeys.single.outbound!.route!.points, isNotEmpty);
      expect(s.journeys.single.inbound!.route!.points, isNotEmpty);
      checks.add('14-day persistence/totals/independent direction snapshots');
    },
  );
  test(
    'Expense add,edit,delete and invalid input do not change final fixture',
    () async {
      final p = await prefs();
      final s = JourneyStore(p);
      final date = data['date_until'] as String;
      await s.saveExpense(
        Expense(id: 'qa-temp', category: 'taxi', date: date, amount: 12345),
      );
      await s.saveExpense(
        Expense(id: 'qa-temp', category: 'bus', date: date, amount: 23456),
      );
      expect(s.expenses.where((e) => e.id == 'qa-temp').single.amount, 23456);
      await s.deleteExpense('qa-temp');
      await expectLater(
        s.saveExpense(
          Expense(
            id: 'invalid',
            category: 'fuel',
            date: '2026-02-31',
            amount: 50000,
          ),
        ),
        throwsArgumentError,
      );
      expect(s.expenses.length, 26);
      expect(JourneyStore(p).expenses.length, 26);
      for (final amount in [-1, 0, 1000000001]) {
        await expectLater(
          s.saveExpense(
            Expense(
              id: 'invalid-amount',
              category: 'fuel',
              date: date,
              amount: amount,
            ),
          ),
          throwsArgumentError,
        );
      }
      checks.add('Expense CRUD/invalid date/reopen');
    },
  );
  test(
    'Account isolation leaves other identities empty and original intact',
    () async {
      final p = await prefs();
      await p.setString('active-account-id', 'different-test-user');
      expect(JourneyStore(p).expenses, isEmpty);
      expect(GarageStore(p).vehicles, isEmpty);
      expect(AppState(p).saved, isEmpty);
      await p.setString('active-account-id', data['user_id']);
      expect(JourneyStore(p).expenses.length, 26);
      checks.add('Account namespace isolation');
    },
  );
  test(
    'Manual odometer crosses reminder and confirmation does not duplicate service',
    () async {
      final p = await prefs();
      final s = GarageStore(p);
      final v = {
        'id': 'qa-boundary',
        'name': 'QA boundary vehicle',
        'model_id': 'wave_alpha',
        'year': 2024,
        'variant': 'Thường',
        'odometer': 5999,
      };
      await s.saveVehicle(v);
      final item = {
        'id': 'qa-boundary-oil',
        'vehicle_id': 'qa-boundary',
        'name': 'QA tự đặt',
        'due_km': 6000,
      };
      await s.saveItem(item);
      expect(maintenanceStatus(item, v, DateTime.now()), 'Sắp đến hạn');
      await s.saveVehicle({...v, 'odometer': 6000});
      expect(
        maintenanceStatus(item, {...v, 'odometer': 6000}, DateTime.now()),
        'Đến hạn',
      );
      await s.saveVehicle({...v, 'odometer': 6001});
      expect(
        maintenanceStatus(item, {...v, 'odometer': 6001}, DateTime.now()),
        'Quá hạn',
      );
      final before = s.history.length;
      await s.complete('qa-boundary-oil');
      await s.complete('qa-boundary-oil');
      expect(s.history.length, before + 1);
      expect(JourneyStore(p).expenses.length, 26);
      checks.add(
        'Manual mileage threshold/idempotent maintenance/no automatic expense',
      );
    },
  );
  testWidgets(
    'Opening expense UI shows actual fixture totals, never completes trips',
    (t) async {
      final p = await prefs();
      await t.pumpWidget(
        ProviderScope(
          overrides: [preferencesProvider.overrideWithValue(p)],
          child: MaterialApp(
            theme: TrafficTokens.material(Brightness.light),
            home: const ExpensesScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Chuyến đã xác nhận hoàn thành: 18'),
        findsOneWidget,
      );
      expect(JourneyStore(p).completed.length, 18);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      checks.add('Real expense screen/no invented completion');
    },
  );
  tearDownAll(() {
    final f = File('build/reports/qa14-flutter-results.json');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
      jsonEncode({
        'scope': 'simulated 14 days, no real driving',
        'checks': checks,
        'passed': checks.length == 5,
      }),
    );
  });
}

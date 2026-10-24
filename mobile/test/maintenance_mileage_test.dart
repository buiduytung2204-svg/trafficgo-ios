import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/maintenance/store.dart';
import 'package:trafficgo/features/maintenance/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> catalog;
  final rows = <Map<String, dynamic>>[];
  setUpAll(() async {
    catalog =
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/honda_vn_maintenance.json',
              ),
            )
            as Map<String, dynamic>;
  });
  tearDownAll(() {
    if (const bool.fromEnvironment('MAINTENANCE_TEST_REPORT')) {
      final root = File(
        File('pubspec.yaml').resolveSymbolicLinksSync(),
      ).parent.parent;
      final f = File(
        '${root.path}/build/reports/maintenance-mileage-results.json',
      );
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'simulation_only': true,
          'scope':
              'All catalog model/manual combinations with visually reviewed engine-oil rows. Manual odometer updates; no GPS driving or OS notification test.',
          'cases': rows,
        }),
      );
    }
  });
  test(
    'Each verified model/year reaches first and recurring oil milestones at exact km',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final baseline = today.subtract(const Duration(days: 1));
      for (final model in catalog['models']) {
        for (final doc in model['manuals']) {
          final rule = Map<String, dynamic>.from(doc['maintenance_rules'][0]);
          expect(rule['verification'], 'table_visual_review');
          final step = model['id'] == 'sh350' ? 12000 : 6000;
          expect(rule['first_km'], 1000);
          expect(rule['grid_step_km'], step);
          for (final first in [true, false]) {
            SharedPreferences.setMockInitialValues({});
            final prefs = await SharedPreferences.getInstance();
            final store = GarageStore(prefs);
            final target = first ? 1000 : step;
            final start = target - 101;
            var v = <String, dynamic>{
              'id': 'v',
              'name': model['name'],
              'model_id': model['id'],
              'year': doc['year'],
              'variant': 'User confirmed manual match',
              'odometer': start,
            };
            await store.saveVehicle(v);
            await store.addVerifiedOil(
              vehicleId: 'v',
              manualId: doc['id'],
              confirmed: true,
              lastServiceKm: first ? null : 1000,
              lastServiceDate: baseline,
            );
            expect(store.items.single['due_km'], target);
            final observed = <Map<String, dynamic>>[];
            for (final offset in [-101, -100, -1, 0, 1]) {
              v = {...v, 'odometer': target + offset};
              await store.saveVehicle(v);
              final status = maintenanceStatus(
                store.items.single,
                store.vehicles.single,
                today,
              );
              final expected = offset < -100
                  ? 'Chưa đến hạn'
                  : offset < 0
                  ? 'Sắp đến hạn'
                  : offset == 0
                  ? 'Đến hạn'
                  : 'Quá hạn';
              expect(
                status,
                expected,
                reason: '${model['name']} ${doc['year']} at ${target + offset}',
              );
              observed.add({
                'odometer_km': target + offset,
                'status': status,
                'passed': status == expected,
              });
            }
            final reopened = GarageStore(prefs);
            expect(
              maintenanceStatus(
                reopened.items.single,
                reopened.vehicles.single,
                today,
              ),
              'Quá hạn',
            );
            expect(prefs.getString('journeys.v1'), isNull);
            rows.add({
              'model_id': model['id'],
              'model': model['name'],
              'year': doc['year'],
              'manual_id': doc['id'],
              'manual_label': doc['label'],
              'source_pdf_page': rule['source_pdf_page'],
              'source_url': doc['url'],
              'phase': first ? 'first_oil' : 'after_first_service',
              'target_km': target,
              'starting_odometer': start,
              'simulated_distance_km': 102,
              'observations': observed,
              'survives_reopen': true,
              'real_driving_test': false,
              'system_notification_test': false,
            });
          }
        }
      }
      expect(rows.length, 62);
    },
  );
  test('Grid is absolute, SH350 differs, yearly deadline clamps leap-day', () {
    for (final step in [6000, 12000]) {
      final rule = <String, dynamic>{'first_km': 1000, 'grid_step_km': step};
      expect(nextOilMilestone(rule, null), 1000);
      expect(nextOilMilestone(rule, 999), 1000);
      expect(nextOilMilestone(rule, 1000), step);
      expect(nextOilMilestone(rule, step), step * 2);
      expect(nextOilMilestone(rule, 36000), 36000 + step);
    }
    expect(annualOilDate(DateTime(2024, 2, 29)), DateTime(2025, 2, 28));
    expect(
      maintenanceStatus(
        {'due_km': 6000, 'due_date': '2026-10-24'},
        {'odometer': 2000},
        DateTime(2026, 10, 24),
      ),
      'Đến hạn',
    );
  });
  test(
    'Confirmation and exact-year guard; separate service cycles preserve history/expense IDs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = GarageStore(await SharedPreferences.getInstance());
      final v = <String, dynamic>{
        'id': 'v',
        'name': 'Wave',
        'model_id': 'wave_alpha',
        'year': 2024,
        'variant': 'Confirmed',
        'odometer': 1000,
      };
      await store.saveVehicle(v);
      final date = DateTime.now().subtract(const Duration(days: 1));
      await expectLater(
        store.addVerifiedOil(
          vehicleId: 'v',
          manualId: 114,
          confirmed: false,
          lastServiceKm: null,
          lastServiceDate: date,
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.addVerifiedOil(
          vehicleId: 'v',
          manualId: 87,
          confirmed: true,
          lastServiceKm: null,
          lastServiceDate: date,
        ),
        throwsArgumentError,
      );
      await store.addVerifiedOil(
        vehicleId: 'v',
        manualId: 114,
        confirmed: true,
        lastServiceKm: null,
        lastServiceDate: date,
      );
      final id1 = store.items.single['id'];
      final h1 = await store.complete(id1);
      await store.addVerifiedOil(
        vehicleId: 'v',
        manualId: 114,
        confirmed: true,
        lastServiceKm: 1000,
        lastServiceDate: date,
      );
      final id2 = store.items.single['id'];
      expect(id1, isNot(id2));
      await store.saveVehicle({...v, 'odometer': 6000});
      final h2 = await store.complete(id2);
      expect(h1['id'], isNot(h2['id']));
      expect(store.history.length, 2);
    },
  );
  testWidgets('Odometer update crossing6000 rebuilds visible due badge', (
    tester,
  ) async {
    late GarageStore store;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      store = GarageStore(await SharedPreferences.getInstance());
      await store.saveVehicle({
        'id': 'v',
        'name': 'Wave kiểm thử',
        'model_id': 'wave_alpha',
        'year': 2024,
        'variant': 'Confirmed',
        'odometer': 5999,
      });
      await store.addVerifiedOil(
        vehicleId: 'v',
        manualId: 114,
        confirmed: true,
        lastServiceKm: 1000,
        lastServiceDate: DateTime.now().subtract(const Duration(days: 1)),
      );
    });
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(store.prefs),
          garageProvider.overrideWith((ref) => store),
          hondaCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: const MaterialApp(home: GarageScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thay dầu động cơ • Sắp đến hạn'), findsOneWidget);
    await tester.runAsync(
      () => store.saveVehicle({...store.vehicles.single, 'odometer': 6000}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thay dầu động cơ • Đến hạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'dart:convert';
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
  Map<String, dynamic> vehicle() => {
    'id': 'v',
    'model_id': 'vision',
    'name': 'Vision của tôi',
    'year': 2020,
    'variant': 'Tiêu chuẩn',
    'odometer': 10000,
  };
  Map<String, dynamic> item() => {
    'id': 'i',
    'vehicle_id': 'v',
    'name': 'Thay dầu theo sổ xe',
    'due_date': '2026-10-25',
    'due_km': 12000,
    'notes': 'Chu kỳ tự nhập',
  };
  test(
    'Requested families cover2020–2026; manual-year mapping stays exact and intervals unverified',
    () async {
      final catalog = jsonDecode(
        await rootBundle.loadString('assets/data/honda_vn_maintenance.json'),
      );
      final models = catalog['models'] as List;
      expect(
        models.map((m) => m['id']),
        containsAll([
          'wave_alpha',
          'wave_rsx',
          'vision',
          'future',
          'lead',
          'sh125',
          'sh150',
          'sh160',
          'sh350',
          'shmode',
        ]),
      );
      for (final m in models) {
        expect(m['requested_years'], [
          2020,
          2021,
          2022,
          2023,
          2024,
          2025,
          2026,
        ]);
        for (final doc in m['manuals']) {
          expect(doc['intervals_verified'], false);
          expect(doc['trim_scope'], 'not_verified');
          expect(doc['label'].contains('${doc['year']}'), true);
          expect(Uri.parse(doc['url']).host, 'cdn.honda.com.vn');
        }
      }
      final vision = models.firstWhere((m) => m['id'] == 'vision');
      expect(vision['variants'], contains('Thể thao (Sport)'));
      expect(
        (vision['manuals'] as List).where((m) => m['year'] == 2021),
        isEmpty,
      );
      final sh150 = models.firstWhere((m) => m['id'] == 'sh150');
      expect(
        (sh150['manuals'] as List).every((m) => m['label'].contains('150')),
        true,
      );
    },
  );
  test(
    'Reminder due by date OR manual odometer; never uses route distance',
    () {
      final v = vehicle();
      final i = item();
      expect(maintenanceStatus(i, v, DateTime(2026, 10, 24)), 'Sắp đến hạn');
      expect(maintenanceStatus(i, v, DateTime(2026, 10, 25)), 'Đến hạn');
      expect(maintenanceStatus(i, v, DateTime(2026, 10, 26)), 'Quá hạn');
      expect(
        maintenanceStatus(
          {...i, 'due_date': null},
          {...v, 'odometer': 12000},
          DateTime(2026, 10, 1),
        ),
        'Đến hạn',
      );
      expect(
        maintenanceStatus(
          {...i, 'due_date': null},
          {...v, 'odometer': 12001},
          DateTime(2026, 10, 1),
        ),
        'Quá hạn',
      );
    },
  );
  test(
    'Garage survives reopen; source cannot be forged; confirmation idempotent and no expense auto-created',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = GarageStore(prefs);
      await store.saveVehicle(vehicle());
      await store.saveItem({...item(), 'source': 'Honda verified'});
      final reopened = GarageStore(prefs);
      expect(reopened.items.single['source'], 'user_defined');
      await expectLater(
        reopened.saveVehicle({...vehicle(), 'odometer': 9999}),
        throwsArgumentError,
      );
      expect(reopened.vehicles.single['odometer'], 10000);
      final first = await reopened.complete('i');
      final second = await reopened.complete('i');
      expect(first['id'], second['id']);
      expect(reopened.history.length, 1);
      expect(reopened.items, isEmpty);
      expect(prefs.getString('journeys.v1'), isNull);
      expect(GarageStore(prefs).history.length, 1);
    },
  );
  test(
    'Invalid reminders rejected, deletion preserves service history, corrupt document untouched',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = GarageStore(prefs);
      await store.saveVehicle(vehicle());
      await expectLater(
        store.saveItem({...item(), 'due_date': null, 'due_km': null}),
        throwsArgumentError,
      );
      await store.saveItem(item());
      await store.complete('i');
      await store.saveItem({...item(), 'id': 'new'});
      await store.removeVehicle('v');
      expect(store.vehicles, isEmpty);
      expect(store.items, isEmpty);
      expect(store.history.length, 1);
      await prefs.setString('garage.v1', 'broken');
      final broken = GarageStore(prefs);
      await expectLater(broken.saveVehicle(vehicle()), throwsStateError);
      expect(prefs.getString('garage.v1'), 'broken');
    },
  );
  testWidgets('Manual links never offer a different year as matching', (
    tester,
  ) async {
    final catalog = (await tester.runAsync(
      () async => Map<String, dynamic>.from(
        jsonDecode(
          await rootBundle.loadString('assets/data/honda_vn_maintenance.json'),
        ),
      ),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualLinks(
            catalog: catalog,
            vehicle: {...vehicle(), 'year': 2021},
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Chưa tìm thấy HDSD đúng nhãn năm 2021'),
      findsOneWidget,
    );
    expect(find.textContaining('Honda: Vision 2020'), findsNothing);
    expect(find.textContaining('mốc nhắc do bạn nhập'), findsOneWidget);
  });
  testWidgets('Garage empty state and manual reminder source are visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final catalog = (await tester.runAsync(
      () async => Map<String, dynamic>.from(
        jsonDecode(
          await rootBundle.loadString('assets/data/honda_vn_maintenance.json'),
        ),
      ),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          hondaCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: const MaterialApp(home: GarageScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có xe'), findsOneWidget);
    expect(find.textContaining('Chưa gửi push'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

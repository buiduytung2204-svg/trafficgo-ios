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
  testWidgets(
    'Short ride:5998 to6001, app reopen, explicit maintenance confirmation',
    (tester) async {
      late GarageStore garage;
      late SharedPreferences prefs;
      late Map<String, dynamic> catalog;
      final trace = <Map<String, dynamic>>[];
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        garage = GarageStore(prefs);
        catalog =
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/data/honda_vn_maintenance.json',
                  ),
                )
                as Map<String, dynamic>;
        await garage.saveVehicle({
          'id': 'ride-test',
          'name': 'Wave Alpha mô phỏng',
          'model_id': 'wave_alpha',
          'year': 2024,
          'variant': 'Sổ xe đã đối chiếu trong test',
          'odometer': 5998,
        });
        await garage.addVerifiedOil(
          vehicleId: 'ride-test',
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
      Future<void> mount() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              preferencesProvider.overrideWithValue(prefs),
              garageProvider.overrideWith((ref) => garage),
              hondaCatalogProvider.overrideWith((ref) async => catalog),
            ],
            child: const MaterialApp(home: GarageScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      void verify(String phase, int km, String status) {
        expect(garage.vehicles.single['odometer'], km);
        expect(find.text('Thay dầu động cơ • $status'), findsOneWidget);
        expect(tester.takeException(), isNull);
        trace.add({
          'phase': phase,
          'odometer_km': km,
          'displayed_status': status,
          'passed': true,
        });
      }

      await mount();
      verify('Trước khi đi', 5998, 'Sắp đến hạn');
      await tester.runAsync(
        () => garage.saveVehicle({...garage.vehicles.single, 'odometer': 5999}),
      );
      await tester.pumpAndSettle();
      verify('Chặng1:đi thêm1km', 5999, 'Sắp đến hạn');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        garage = GarageStore(prefs);
      });
      await mount();
      verify('Dừng xe,tắt/mở lại app', 5999, 'Sắp đến hạn');
      await tester.runAsync(
        () => garage.saveVehicle({...garage.vehicles.single, 'odometer': 6000}),
      );
      await tester.pumpAndSettle();
      verify('Chặng2:đi thêm1km', 6000, 'Đến hạn');
      await tester.runAsync(
        () => garage.saveVehicle({...garage.vehicles.single, 'odometer': 6001}),
      );
      await tester.pumpAndSettle();
      verify('Chặng3:đi thêm1km,chưa thay dầu', 6001, 'Quá hạn');
      expect(garage.history, isEmpty);
      expect(prefs.getString('journeys.v1'), isNull);
      await tester.tap(find.byTooltip('Xác nhận đã bảo dưỡng'));
      await tester.pumpAndSettle();
      expect(garage.history, isEmpty);
      await tester.tap(find.text('Đã thực hiện'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pumpAndSettle();
      expect(garage.items, isEmpty);
      expect(garage.history.length, 1);
      expect(garage.history.single['odometer'], 6001);
      expect(prefs.getString('journeys.v1'), isNull);
      trace.add({
        'phase': 'Dừng tại nơi bảo dưỡng,xác nhận đã thay dầu',
        'odometer_km': 6001,
        'history_records': 1,
        'active_reminders': 0,
        'expense_auto_created': false,
        'passed': true,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      final report = {
        'simulation_only': true,
        'vehicle': 'Wave Alpha2024',
        'source_manual_id': 114,
        'source_pdf_page': 44,
        'due_odometer_km': 6000,
        'previous_service_km': 1000,
        'simulated_distance_km': 3,
        'uses_actual_gps': false,
        'odometer_updates': 'simulated manual input through real GarageStore',
        'push_or_system_notification_tested': false,
        'scope':
            'Real Flutter widgets, isolated preferences; no physical riding or real personal records modified.',
        'trace': trace,
      };
      final root = File(
        File('pubspec.yaml').resolveSymbolicLinksSync(),
      ).parent.parent;
      final output = File(
        '${root.path}/build/reports/simple-maintenance-ride.json',
      );
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report),
      );
    },
  );
}

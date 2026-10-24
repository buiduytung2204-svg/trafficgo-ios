import 'package:trafficgo/core/design/traffic_theme.dart';
import 'package:trafficgo/app/home_shell.dart';
import 'package:flutter/services.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/features/settings/screens.dart';
import 'package:trafficgo/features/journeys/screens.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/departure/screens.dart';
import 'package:trafficgo/features/maintenance/screens.dart';
import 'package:trafficgo/features/maintenance/store.dart';
import 'package:trafficgo/features/onboarding/screens.dart';

import 'personalization_cases_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> catalog;
  setUpAll(() async {
    catalog = Map<String, dynamic>.from(
      jsonDecode(
        await File('assets/data/honda_vn_maintenance.json').readAsString(),
      ),
    );
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      for (final name in ['Medium', 'SemiBold', 'Bold']) {
        await (FontLoader('PlusJakartaSans')..addFont(
              rootBundle.load('assets/fonts/PlusJakartaSans-$name.ttf'),
            ))
            .load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      const path = String.fromEnvironment('QA_FONT_PATH');
      if (path.isNotEmpty) {
        final bytes = File(path).readAsBytesSync();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
  final screens = <String, Widget Function()>{
    'home_overview': () => const TrafficHomeShell(),
    'settings': () => const SettingsScreen(),
    'saved_places_routes': () => const SavedScreen(),
    'journeys': () => const JourneysScreen(),
    'journey_detail': () => const JourneyDetail(id: 'school'),
    'expenses_statistics': () => const ExpensesScreen(),
    'expense_form': () => const ExpenseEditor(journeyId: 'school'),
    'garage': () => const GarageScreen(),
    'maintenance_form': () => MaintenanceEditor(vehicle: fixtures.bike()),
    'schedules': () => const SchedulesScreen(),
    'schedule_form': () => ScheduleEditor(
      seedTrip: fixtures.trip(),
      journeyId: 'school',
      direction: 'outbound',
    ),
    'notifications': () => const DepartureNotificationsScreen(),
    'route_planner': () => RoutePlanner(initial: fixtures.trip()),
    'account_signup': () => const AccountScreen(),
  };
  for (final variant in [
    (1.0, false),
    (1.5, false),
    (2.0, false),
    (1.0, true),
    (1.5, true),
    (2.0, true),
  ]) {
    final scale = variant.$1;
    final dark = variant.$2;
    final large = scale > 1;
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key}: text${(scale * 100).round()} ${large ? '320px' : '390px'} ${dark ? 'dark' : 'light'}',
        (t) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final trip = fixtures.trip();
          final state = AppState(prefs);
          await state.save(trip.origin);
          await state.saveTrip(trip);
          await JourneyStore(prefs).saveJourney(
            Journey(
              id: 'school',
              name: 'Nhà — Đại học CMC cơ sở 2',
              outbound: trip,
            ),
          );
          await JourneyStore(prefs).saveExpense(
            Expense(
              id: 'fuel',
              category: 'fuel',
              date: DateTime.now().toIso8601String().substring(0, 10),
              amount: 50000,
              journeyId: 'school',
            ),
          );
          final garage = GarageStore(prefs);
          await garage.saveVehicle(fixtures.bike());
          await garage.saveItem({
            'id': 'oil',
            'vehicle_id': 'wave-test',
            'name': 'Thay dầu động cơ TEST',
            'due_km': 6000,
            'due_date': '2026-10-24',
          });
          final arrival = DateTime.now().toUtc().add(const Duration(days: 1));
          await prefs.setString(
            'departure-overview:$apiBase',
            jsonEncode({
              'schedules': [
                {
                  'id': 'schedule',
                  'name': 'Lịch đi học CMC TEST',
                  'journey_id': 'school',
                  'direction': 'outbound',
                  'enabled': true,
                  'origin': trip.origin.toJson()['coordinate'],
                  'destination': trip.destination.toJson()['coordinate'],
                  'origin_name': trip.origin.name,
                  'destination_name': trip.destination.name,
                  'vehicle': 'motorcycle',
                  'arrival_time': '07:30',
                  'weekdays': [0, 1, 2, 3, 4],
                  'preparation_minutes': 15,
                  'buffer_minutes': 10,
                  'initial_eta_s': 1500,
                  'occurrence': {
                    'id': 'occurrence',
                    'status': 'planned',
                    'eta_s': 1500,
                    'arrival_at': arrival.toIso8601String(),
                    'prepare_at': arrival
                        .subtract(const Duration(minutes: 50))
                        .toIso8601String(),
                    'departure_at': arrival
                        .subtract(const Duration(minutes: 35))
                        .toIso8601String(),
                  },
                },
              ],
              'notifications': [],
              'worker': {},
              'synced_at': DateTime.now().toUtc().toIso8601String(),
            }),
          );
          await t.binding.setSurfaceSize(
            large ? const Size(320, 694) : const Size(390, 844),
          );
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(
            ProviderScope(
              overrides: [
                preferencesProvider.overrideWithValue(prefs),
                hondaCatalogProvider.overrideWith((ref) async => catalog),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('vi'),
                supportedLocales: const [Locale('vi')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: TrafficTokens.material(
                  dark ? Brightness.dark : Brightness.light,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: TrafficDesignScope(
                    child: RepaintBoundary(
                      key: fixtures.boundary,
                      child: child!,
                    ),
                  ),
                ),
                home: entry.value(),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'initial ${entry.key}');
          await fixtures.capture(
            t,
            'full-audit-${entry.key}-${(scale * 100).round()}-${dark ? 'dark' : 'light'}',
          );
          final lists = find.byType(ListView);
          if (lists.evaluate().isNotEmpty) {
            for (var i = 0; i < 3; i++) {
              await t.drag(lists.last, const Offset(0, -500));
              await t.pumpAndSettle();
              expect(t.takeException(), isNull, reason: 'scroll ${entry.key}');
              if (i == 0 && entry.key == 'expenses_statistics') {
                await fixtures.capture(
                  t,
                  'full-audit-expense-chart-${(scale * 100).round()}-${dark ? 'dark' : 'light'}',
                );
              }
            }
          }
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpAndSettle();
        },
      );
    }
  }
}

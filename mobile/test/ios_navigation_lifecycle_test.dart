import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/location/location_service.dart';
import 'package:trafficgo/features/map/map_screen.dart';

import 'personalization_cases_test.dart' as fixtures;

void main() {
  for (final background in [false, true]) {
    testWidgets(
      'Active iOS navigation ${background ? 'keeps' : 'pauses'} GPS stream on lock and always stops on dispose',
      (t) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final stream = StreamController<Position>.broadcast();
        final settings = <AppleSettings>[];
        final service = LocationService(
          android: false,
          ios: true,
          check: () async => LocationPermission.whileInUse,
          enabled: () async => true,
          positions: (s) {
            settings.add(s as AppleSettings);
            return stream.stream;
          },
        );
        await t.pumpWidget(
          ProviderScope(
            overrides: [preferencesProvider.overrideWithValue(prefs)],
            child: MaterialApp(
              home: MapScreen(
                plannedTrip: fixtures.trip(),
                autoStartNavigation: true,
                locations: service,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Định vị khi khóa màn hình?'), findsOneWidget);
        await t.tap(
          find.text(background ? 'Tiếp tục định vị nền' : 'Chỉ khi mở app'),
        );
        await t.pumpAndSettle();
        expect(stream.hasListener, isTrue);
        expect(settings.last.allowBackgroundLocationUpdates, background);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump();
        expect(stream.hasListener, background);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(stream.hasListener, isTrue);
        expect(settings.length, background ? 1 : 2);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
        expect(stream.hasListener, isFalse);
        expect(t.takeException(), isNull);
        await stream.close();
      },
    );
  }
}

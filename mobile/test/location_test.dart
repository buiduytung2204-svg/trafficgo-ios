import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trafficgo/features/location/location_service.dart';

void main() {
  Position position() => Position(
    latitude: 21.02,
    longitude: 105.85,
    timestamp: DateTime.now(),
    accuracy: 100,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  test('Requests foreground permission and accepts approximate fix', () async {
    var prompts = 0;
    final service = LocationService(
      android: true,
      check: () async => LocationPermission.denied,
      request: () async {
        prompts++;
        return LocationPermission.whileInUse;
      },
      enabled: () async => true,
      fix: (s) async => position(),
    );
    expect((await service.current()).accuracy, 100);
    expect(prompts, 1);
  });

  test('Blocked permission does not call GPS', () async {
    var calls = 0;
    final service = LocationService(
      check: () async => LocationPermission.deniedForever,
      enabled: () async => true,
      fix: (s) async {
        calls++;
        return position();
      },
    );
    await expectLater(
      service.current(),
      throwsA(isA<LocationFailure>().having((e) => e.code, 'code', 'blocked')),
    );
    expect(calls, 0);
  });

  test('Disabled device location has actionable error', () async {
    final service = LocationService(
      check: () async => LocationPermission.whileInUse,
      enabled: () async => false,
    );
    await expectLater(
      service.current(),
      throwsA(isA<LocationFailure>().having((e) => e.code, 'code', 'disabled')),
    );
  });

  test('Permission prompt happens even when device location is off', () async {
    final steps = <String>[];
    final service = LocationService(
      check: () async => LocationPermission.denied,
      request: () async {
        steps.add('permission');
        return LocationPermission.whileInUse;
      },
      enabled: () async {
        steps.add('service');
        return false;
      },
    );
    await expectLater(service.current(), throwsA(isA<LocationFailure>()));
    expect(steps, ['permission', 'service']);
  });

  test(
    'Android timeout falls back to native provider and keeps it for stream',
    () async {
      final providers = <bool>[];
      final service = LocationService(
        android: true,
        check: () async => LocationPermission.whileInUse,
        enabled: () async => true,
        fix: (s) async {
          final native = (s as AndroidSettings).forceLocationManager;
          providers.add(native);
          if (!native) throw TimeoutException('No Play Services fix');
          return position();
        },
      );
      expect((await service.current()).latitude, 21.02);
      expect(providers, [false, true]);
      expect(
        (service.settings(stream: true) as AndroidSettings)
            .forceLocationManager,
        true,
      );
      expect(service.settings(stream: true).timeLimit, isNull);
    },
  );

  test('Both providers timing out return Vietnamese GPS error', () async {
    final service = LocationService(
      android: true,
      check: () async => LocationPermission.whileInUse,
      enabled: () async => true,
      fix: (s) async => throw TimeoutException('no fix'),
    );
    await expectLater(
      service.current(),
      throwsA(isA<LocationFailure>().having((e) => e.code, 'code', 'timeout')),
    );
  });
}

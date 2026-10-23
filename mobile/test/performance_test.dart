import 'package:flutter_test/flutter_test.dart';
import 'package:trafficgo/features/map/base_map.dart';
import 'package:trafficgo/features/map/traffic_refresh.dart';
import 'package:trafficgo/core/performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/map/map_screen.dart';

void main() {
  testWidgets(
    'Geoapify map has authenticated tiles and no TomTom traffic layer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            stateProvider.overrideWith(
              (ref) => AppState(prefs)..token = 'test-access',
            ),
          ],
          child: MaterialApp(
            home: MapScreen(
              source: BaseMapSource.configured(source: 'geoapify'),
            ),
          ),
        ),
      );
      final layers = tester
          .widgetList<TileLayer>(find.byType(TileLayer))
          .toList();
      expect(layers.length, 1);
      expect(layers.single.urlTemplate, contains('/api/v1/geo/tiles/'));
      expect(layers.single.tileProvider.headers['X-App-Token'], 'test-access');
      expect(find.text('Powered by Geoapify'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
  test('Geoapify source uses authenticated backend without a client key', () {
    final source = BaseMapSource.configured(source: 'geoapify');
    expect(source.usesBackend, true);
    expect(source.usesTomTom, false);
    expect(source.url, isNot(contains('apiKey')));
  });
  testWidgets('External basemap never gets app token and traffic is gated', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: MapScreen(
            source: BaseMapSource(
              'osm_raster',
              'http://localhost:9999/{z}/{x}/{y}.png',
              '© OpenStreetMap contributors',
            ),
          ),
        ),
      ),
    );
    final layers = tester
        .widgetList<TileLayer>(find.byType(TileLayer))
        .toList();
    expect(layers.length, 1);
    expect(
      layers.single.tileProvider.headers.containsKey('X-App-Token'),
      false,
    );
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    // flutter_map's trailing debounce can complete after the layer unmounts.
    await tester.pump(const Duration(milliseconds: 300));
  });
  test('Stationary foreground does not reload traffic every two minutes', () {
    final start = DateTime(2026, 10, 23, 10);
    final policy = TrafficRefreshPolicy(start);
    for (var minute = 2; minute <= 10; minute += 2) {
      expect(
        policy.shouldRefresh(
          start.add(Duration(minutes: minute)),
          foreground: true,
          enabled: true,
          navigating: false,
          blocked: false,
        ),
        false,
      );
    }
    final now = start.add(const Duration(minutes: 10));
    policy.interact(now.subtract(const Duration(seconds: 3)));
    expect(
      policy.shouldRefresh(
        now,
        foreground: true,
        enabled: true,
        navigating: false,
        blocked: false,
      ),
      true,
    );
    policy.refreshed(now);
    expect(
      policy.shouldRefresh(
        now,
        foreground: true,
        enabled: true,
        navigating: true,
        blocked: false,
      ),
      false,
    );
  });
  test('Hidden, disabled, moving, or rate-limited traffic never refreshes', () {
    final start = DateTime(2026);
    final now = start.add(const Duration(minutes: 3));
    final policy = TrafficRefreshPolicy(start);
    expect(
      policy.shouldRefresh(
        now,
        foreground: false,
        enabled: true,
        navigating: true,
        blocked: false,
      ),
      false,
    );
    expect(
      policy.shouldRefresh(
        now,
        foreground: true,
        enabled: false,
        navigating: true,
        blocked: false,
      ),
      false,
    );
    expect(
      policy.shouldRefresh(
        now,
        foreground: true,
        enabled: true,
        navigating: true,
        blocked: true,
      ),
      false,
    );
    policy.interact(now);
    expect(
      policy.shouldRefresh(
        now,
        foreground: true,
        enabled: true,
        navigating: true,
        blocked: false,
      ),
      false,
    );
  });
  test(
    'OSM source does not use public community tiles or mobile dev bypass',
    () {
      expect(BaseMapSource.configured(source: 'tomtom').usesTomTom, true);
      expect(
        BaseMapSource.configured(
          source: 'stadia_dev',
          web: true,
          hostname: 'localhost',
        ).usesTomTom,
        false,
      );
      expect(
        () => BaseMapSource.configured(
          source: 'stadia_dev',
          web: false,
          hostname: 'localhost',
        ),
        throwsStateError,
      );
      expect(
        () => BaseMapSource.configured(
          source: 'osm_raster',
          osmUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          attribution: 'OSM',
        ),
        throwsStateError,
      );
      expect(
        () => BaseMapSource.configured(
          source: 'osm_raster',
          osmUrl: 'https://maps.example.com/{z}/{x}/{y}.png',
          attribution: '',
        ),
        throwsStateError,
      );
      expect(
        BaseMapSource.configured(
          source: 'osm_raster',
          osmUrl: 'https://maps.example.com/{z}/{x}/{y}.png',
          attribution: '© OpenStreetMap contributors',
        ).url,
        contains('maps.example.com'),
      );
    },
  );
  test('Performance summaries contain counts and error rates without URLs', () {
    final log = PerformanceLog();
    log.record('traffic', 10);
    log.record('traffic', 30, failed: true);
    final entry = (log.snapshot()['metrics'] as Map)['traffic'];
    expect(entry['p50_ms'], 10);
    expect(entry['p95_ms'], 30);
    expect(entry['error_rate'], .5);
    expect(log.json, isNot(contains('http://')));
  });
}

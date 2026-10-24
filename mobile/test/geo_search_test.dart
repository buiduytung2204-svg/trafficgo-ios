import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/api.dart';
import 'package:trafficgo/core/models.dart';
import 'package:trafficgo/features/map/map_screen.dart';

class GeoSearchApi extends TrafficApi {
  int calls = 0;
  GeoSearchApi() : super('');
  @override
  Future<List<Place>> search(
    String query,
    LatLng near,
    CancelToken cancel,
  ) async {
    calls++;
    return [
      const Place(
        'NHS Trung Văn',
        LatLng(20.98932, 105.78217),
        provider: 'geoapify',
        sourceAttribution: '© OpenStreetMap contributors',
      ),
    ];
  }
}

void main() {
  test('Saved Geoapify place retains provider and data-source attribution', () {
    const place = Place(
      'NHS',
      LatLng(21, 105.8),
      provider: 'geoapify',
      sourceAttribution: 'OSM',
    );
    final copy = Place.fromJson(place.toJson());
    expect(copy.provider, 'geoapify');
    expect(copy.sourceAttribution, 'OSM');
  });

  testWidgets('Debounce avoids early calls and result attribution is visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = GeoSearchApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          apiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'NH');
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls, 0);
    await tester.enterText(find.byType(TextField), 'NHS');
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.calls, 0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(api.calls, 1);
    expect(find.text('NHS Trung Văn'), findsOneWidget);
    expect(find.text('Powered by Geoapify'), findsWidgets);
    expect(find.text('© OpenStreetMap contributors'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}

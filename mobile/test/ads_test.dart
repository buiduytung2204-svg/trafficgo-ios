import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficgo/core/ads.dart';

void main() {
  test(
    'Interstitial cooldown includes first three minutes and clock rollback',
    () {
      final previous = DateTime(2026, 10, 28, 7);
      expect(TrafficAds.cooldownElapsed(previous, previous), isFalse);
      expect(
        TrafficAds.cooldownElapsed(
          previous.add(const Duration(seconds: 179)),
          previous,
        ),
        isFalse,
      );
      expect(
        TrafficAds.cooldownElapsed(
          previous.add(const Duration(minutes: 3)),
          previous,
        ),
        isTrue,
      );
      expect(
        TrafficAds.cooldownElapsed(
          previous.subtract(const Duration(minutes: 1)),
          previous,
        ),
        isFalse,
      );
    },
  );
  test(
    'Uninitialized ads never block navigation or claim ad readiness',
    () async {
      final ads = TrafficAds();
      var proceeded = 0;
      await ads.beforeTabChange(() => proceeded++);
      expect(proceeded, 1);
      expect(ads.visible, isFalse);
      ads.setNavigation(true);
      expect(ads.visible, isFalse);
      await ads.beforeTabChange(() => proceeded++);
      expect(proceeded, 2);
      ads.dispose();
    },
  );
  testWidgets('Banner stays absent without SDK readiness', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrafficAdBanner())),
    );
    expect(find.text('Quảng cáo thử nghiệm'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/map/map_screen.dart';

void main() {
  testWidgets('Controlled map shell benchmark without imagery', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final samples = <double>[];
    for (var i = 0; i < 6; i++) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final timer = Stopwatch()..start();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [preferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: MapScreen()),
        ),
      );
      await tester.pump();
      samples.add(timer.elapsedMicroseconds / 1000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    final values = samples.skip(1).toList()..sort();
    final report = {
      'method':
          'Flutter test software-rendered map shell, 390x844, no imagery/network/GPS; excludes first warmup',
      'samples_ms': values,
      'p50_ms': values[2],
      'p95_ms': values.last,
      'full_map_render_ms': null,
      'device_gpu_ms': null,
    };
    const output = String.fromEnvironment('BENCH_REPORT');
    if (output.isNotEmpty) {
      await tester.runAsync(
        () => File(
          output,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report)),
      );
    }
  });
}

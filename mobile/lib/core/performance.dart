import 'dart:convert';
import 'dart:collection';
import 'package:flutter/scheduler.dart';

/// Local, bounded diagnostics. No coordinates, URLs, tokens, or uploads.
class PerformanceLog {
  static final instance = PerformanceLog();
  final Map<String, ListQueue<double>> samples = {};
  final Map<String, int> requests = {}, errors = {};
  final Map<String, Map<String, int>> outcomes = {};
  String phase = 'open';
  final started = Stopwatch()..start();
  double? firstMapFrameMs, firstDecodedTileMs;
  void record(String name, double ms, {bool failed = false, String? outcome}) {
    requests[name] = (requests[name] ?? 0) + 1;
    errors[name] = (errors[name] ?? 0) + (failed ? 1 : 0);
    if (outcome != null) {
      final counts = outcomes.putIfAbsent(name, () => {});
      counts[outcome] = (counts[outcome] ?? 0) + 1;
    }
    final values = samples.putIfAbsent(name, () => ListQueue<double>());
    values.add(ms);
    if (values.length > 2000) values.removeFirst();
  }

  void frames(List<FrameTiming> frames) {
    for (final frame in frames) {
      record('frame.build', frame.buildDuration.inMicroseconds / 1000);
      record('frame.raster', frame.rasterDuration.inMicroseconds / 1000);
    }
  }

  void decodedTile() {
    firstDecodedTileMs ??= started.elapsedMicroseconds / 1000;
  }

  Map<String, dynamic> snapshot() => {
    'scope': 'local process; bounded 2000 samples/category; no GPS history',
    'first_map_shell_frame_ms': firstMapFrameMs,
    'first_decoded_tile_ms': firstDecodedTileMs,
    'render_note':
        'Tile decode is not full viewport completion. Missing frame samples mean platform did not report timings.',
    'metrics': {
      for (final entry in samples.entries)
        entry.key: _summary(entry.key, entry.value),
    },
  };
  Map<String, dynamic> _summary(String name, Iterable<double> values) {
    final sorted = [...values]..sort();
    return {
      'count': requests[name],
      'sample_count': sorted.length,
      'errors': errors[name],
      'error_rate': errors[name]! / requests[name]!,
      'outcomes': outcomes[name] ?? <String, int>{},
      'p50_ms':
          sorted[((sorted.length * .5).ceil() - 1).clamp(0, sorted.length - 1)],
      'p95_ms':
          sorted[((sorted.length * .95).ceil() - 1).clamp(
            0,
            sorted.length - 1,
          )],
    };
  }

  String get json => const JsonEncoder.withIndent('  ').convert(snapshot());
}

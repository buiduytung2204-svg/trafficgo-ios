import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'performance.dart';

/// One recovery attempt only for transient Geoapify tile HTTP 502/504.
/// TomTom, cancellation and quota errors are never retried here.
class TileClient extends http.BaseClient {
  final http.Client _inner;
  final void Function() onReceived;
  final void Function(String)? onFailure;
  final _closed = Completer<void>();
  DateTime? blockedUntil;
  String blockedMessage = '';
  TileClient(this.onReceived, {this.onFailure, http.Client? client})
    : _inner = client ?? http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request, retryGeoTile: true);

  Future<http.StreamedResponse> _send(
    http.BaseRequest request, {
    required bool retryGeoTile,
  }) async {
    final phase = PerformanceLog.instance.phase;
    final kind = request.url.path.contains('/traffic/') ? 'traffic' : 'map';
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil!)) {
      PerformanceLog.instance.record(
        '$phase.tile.$kind',
        0,
        failed: true,
        outcome: 'local_backoff_429',
      );
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'detail': blockedMessage}))),
        429,
        headers: {'content-type': 'application/json'},
      );
    }
    final clock = Stopwatch()..start();
    late http.StreamedResponse response;
    try {
      final raw = await _inner
          .send(request)
          .timeout(const Duration(seconds: 30));
      final bytes = await raw.stream.toBytes().timeout(
        const Duration(seconds: 30),
      );
      response = http.StreamedResponse(
        Stream.value(bytes),
        raw.statusCode,
        headers: raw.headers,
        request: raw.request,
        reasonPhrase: raw.reasonPhrase,
      );
      PerformanceLog.instance.record(
        '$phase.tile.$kind',
        clock.elapsedMicroseconds / 1000,
        failed: raw.statusCode >= 400,
        outcome: 'http_${raw.statusCode}',
      );
      final timing = raw.headers['server-timing'] ?? '';
      for (final component in ['backend_total', 'upstream']) {
        final match = RegExp('$component;dur=([0-9.]+)').firstMatch(timing);
        if (match != null) {
          PerformanceLog.instance.record(
            '$phase.$component.$kind',
            double.parse(match.group(1)!),
            failed: raw.statusCode >= 400,
            outcome: 'http_${raw.statusCode}',
          );
        }
      }
    } catch (e) {
      PerformanceLog.instance.record(
        '$phase.tile.$kind',
        clock.elapsedMicroseconds / 1000,
        failed: e is! http.RequestAbortedException,
        outcome: e is TimeoutException
            ? 'timeout'
            : e is http.RequestAbortedException
            ? 'cancelled'
            : 'transport_error',
      );
      rethrow;
    }
    if (retryGeoTile &&
        request.method == 'GET' &&
        request.url.path.startsWith('/api/v1/geo/tiles/') &&
        (response.statusCode == 502 || response.statusCode == 504)) {
      // Do not reload the whole layer or change the camera for one failed tile.
      final abort = request is http.Abortable ? request.abortTrigger : null;
      final cancelled = await Future.any<bool>([
        Future<bool>.delayed(const Duration(milliseconds: 500), () => false),
        _closed.future.then((_) => true),
        if (abort != null) abort.then((_) => true),
      ]);
      if (cancelled) throw http.RequestAbortedException(request.url);
      final retry = http.AbortableRequest(
        'GET',
        request.url,
        abortTrigger: abort,
      )..headers.addAll(request.headers);
      return _send(retry, retryGeoTile: false);
    }
    if (response.statusCode == 200) onReceived();
    if (response.statusCode >= 400) {
      final bytes = await response.stream.toBytes();
      String message = 'Không tải được tile (HTTP ${response.statusCode}).';
      try {
        final data = jsonDecode(utf8.decode(bytes));
        if (data is Map && data['detail'] is String) message = data['detail'];
      } catch (_) {}
      if (response.statusCode == 429) {
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
        blockedUntil = DateTime.now().add(
          Duration(seconds: seconds.clamp(1, 86400)),
        );
        blockedMessage = message;
      }
      onFailure?.call(message);
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
        request: response.request,
        reasonPhrase: response.reasonPhrase,
      );
    }
    return response;
  }

  @override
  void close() {
    if (!_closed.isCompleted) _closed.complete();
    _inner.close();
    super.close();
  }
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trafficgo/core/performance.dart';
import 'package:trafficgo/core/tile_client.dart';

void main() {
  test('Cancelled viewport never starts a recovery request', () async {
    final abort = Completer<void>();
    var calls = 0;
    final client = TileClient(
      () {},
      client: MockClient((r) async {
        calls++;
        abort.complete();
        return http.Response('timeout', 504);
      }),
    );
    final request = http.AbortableRequest(
      'GET',
      Uri.parse('http://localhost/api/v1/geo/tiles/13/1/1.png'),
      abortTrigger: abort.future,
    );
    await expectLater(
      client.send(request),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(calls, 1);
    client.close();
  });
  test(
    'Geoapify transient tile retries once without showing a stale error',
    () async {
      var calls = 0, received = 0, failures = 0;
      final client = TileClient(
        () => received++,
        onFailure: (_) => failures++,
        client: MockClient((r) async {
          calls++;
          expect(r.headers['X-App-Token'], 'test');
          return http.Response(
            calls == 1 ? 'timeout' : 'png',
            calls == 1 ? 504 : 200,
          );
        }),
      );
      final response = await client.get(
        Uri.parse('http://localhost/api/v1/geo/tiles/13/1/1.png'),
        headers: {'X-App-Token': 'test'},
      );
      expect(response.statusCode, 200);
      expect(calls, 2);
      expect(received, 1);
      expect(failures, 0);
      client.close();
    },
  );

  test(
    'Geoapify permanent timeout has only two attempts; 429 only one',
    () async {
      for (final code in [504, 429]) {
        var calls = 0;
        final client = TileClient(
          () {},
          client: MockClient((r) async {
            calls++;
            return http.Response('error', code);
          }),
        );
        expect(
          (await client.get(
            Uri.parse('http://localhost/api/v1/geo/tiles/13/1/1.png'),
          )).statusCode,
          code,
        );
        expect(calls, code == 504 ? 2 : 1);
        client.close();
      }
    },
  );
  test('Cancelled tile is counted separately from network errors', () async {
    PerformanceLog.instance.phase = 'cancel_test';
    final client = TileClient(
      () {},
      client: MockClient((r) async => throw http.RequestAbortedException()),
    );
    await expectLater(
      client.get(Uri.parse('http://localhost/tile')),
      throwsA(isA<http.RequestAbortedException>()),
    );
    final metric =
        (PerformanceLog.instance.snapshot()['metrics']
            as Map)['cancel_test.tile.map'];
    expect(metric['errors'], 0);
    expect(metric['outcomes'], {'cancelled': 1});
    client.close();
  });
  test('HTTP 504 propagates to backend timing error metrics', () async {
    PerformanceLog.instance.phase = 'diagnostic_test';
    final client = TileClient(
      () {},
      client: MockClient(
        (r) async => http.Response(
          '{"detail":"timeout"}',
          504,
          headers: {
            'server-timing': 'backend_total;dur=10001, upstream;dur=9999',
          },
        ),
      ),
    );
    await client.get(
      Uri.parse('http://localhost/api/v1/tiles/traffic/1/0/0.png'),
    );
    final metrics = PerformanceLog.instance.snapshot()['metrics'] as Map;
    for (final name in ['tile', 'backend_total', 'upstream']) {
      final metric = metrics['diagnostic_test.$name.traffic'] as Map;
      expect(metric['errors'], 1);
      expect(metric['outcomes'], {'http_504': 1});
    }
    client.close();
  });

  test('Transport failure is distinct from HTTP response', () async {
    PerformanceLog.instance.phase = 'transport_test';
    final client = TileClient(
      () {},
      client: MockClient((r) async => throw http.ClientException('network')),
    );
    await expectLater(
      client.get(Uri.parse('http://localhost/tile')),
      throwsA(isA<http.ClientException>()),
    );
    final metric =
        (PerformanceLog.instance.snapshot()['metrics']
            as Map)['transport_test.tile.map'];
    expect(metric['outcomes'], {'transport_error': 1});
    client.close();
  });
}

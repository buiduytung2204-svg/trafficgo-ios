import 'dart:convert';
import 'package:http/http.dart' as http;

/// No retries here: backend owns the bounded upstream retry budget.
class TileClient extends http.BaseClient {
  final http.Client _inner;
  final void Function() onReceived;
  final void Function(String)? onFailure;
  DateTime? blockedUntil;
  String blockedMessage = '';
  TileClient(this.onReceived, {this.onFailure, http.Client? client})
    : _inner = client ?? http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil!)) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'detail': blockedMessage}))),
        429,
        headers: {'content-type': 'application/json'},
      );
    }
    final response = await _inner
        .send(request)
        .timeout(const Duration(seconds: 30));
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
    _inner.close();
    super.close();
  }
}

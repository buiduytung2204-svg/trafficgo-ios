import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'performance.dart';

const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

class TrafficApi {
  final Dio dio;
  TrafficApi(String token)
    : dio = Dio(
        BaseOptions(
          baseUrl: apiBase,
          headers: {'X-App-Token': token},
          connectTimeout: const Duration(seconds: 10),
          // Backend has at most two 10s attempts plus a short retry delay.
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
  Future<List<Place>> search(
    String query,
    LatLng near,
    CancelToken cancel,
  ) async {
    final r = await dio.get(
      '/api/v1/places/search',
      queryParameters: {
        'q': query,
        'lat': near.latitude,
        'lon': near.longitude,
      },
      cancelToken: cancel,
    );
    return (r.data['places'] as List).map((j) => Place.fromJson(j)).toList();
  }

  Future<List<TravelRoute>> routes(
    LatLng origin,
    Place destination, {
    bool refresh = false,
    String vehicle = 'car',
  }) async {
    final clock = Stopwatch()..start();
    try {
      final r = await dio.post(
        '/api/v1/routes/${refresh ? 'refresh' : 'calculate'}',
        data: {
          'origin': {'lat': origin.latitude, 'lon': origin.longitude},
          'destination': destination.toJson()['coordinate'],
          'vehicle': vehicle,
        },
      );
      final routes = fastestRoutes(
        (r.data['routes'] as List).map((j) => TravelRoute.fromJson(j)).toList(),
      );
      PerformanceLog.instance.record(
        refresh ? 'routing.refresh' : 'routing.calculate',
        clock.elapsedMicroseconds / 1000,
      );
      return routes;
    } catch (_) {
      PerformanceLog.instance.record(
        refresh ? 'routing.refresh' : 'routing.calculate',
        clock.elapsedMicroseconds / 1000,
        failed: true,
      );
      rethrow;
    }
  }

  static const storage = FlutterSecureStorage();
  Future<Map<String, dynamic>> attribution() async =>
      Map<String, dynamic>.from((await dio.get('/api/v1/attribution')).data);
}

String errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'];
    if (error.response?.statusCode == 422) {
      return 'Tọa độ hoặc yêu cầu không hợp lệ. Ứng dụng hiện chỉ hỗ trợ vùng Hà Nội.';
    }
    if (error.response?.statusCode == 429) {
      return 'Đã đạt giới hạn yêu cầu. Vui lòng thử lại sau.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Dịch vụ phản hồi quá chậm. Vui lòng thử lại tính đường.';
    }
    if (error.type == DioExceptionType.cancel) {
      return 'Yêu cầu đã bị hủy. Vui lòng thử lại.';
    }
    if (error.response != null) {
      return 'Dịch vụ trả lỗi HTTP ${error.response!.statusCode}. Vui lòng thử lại.';
    }
    return 'Không kết nối được dịch vụ. Kiểm tra Internet và địa chỉ backend.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

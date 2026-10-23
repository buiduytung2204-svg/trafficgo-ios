import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class LocationFailure implements Exception {
  final String code, message;
  const LocationFailure(this.code, this.message);
  @override
  String toString() => message;
}

/// Foreground fixes only; never substitutes a stale cached position for GPS.
class LocationService {
  final Future<LocationPermission> Function() check, request;
  final Future<bool> Function() enabled;
  final Future<Position> Function(LocationSettings) fix;
  final bool android;
  bool nativeProvider = false;
  LocationService({
    Future<LocationPermission> Function()? check,
    Future<LocationPermission> Function()? request,
    Future<bool> Function()? enabled,
    Future<Position> Function(LocationSettings)? fix,
    bool? android,
  }) : check = check ?? Geolocator.checkPermission,
       request = request ?? Geolocator.requestPermission,
       enabled = enabled ?? Geolocator.isLocationServiceEnabled,
       fix = fix ?? ((s) => Geolocator.getCurrentPosition(locationSettings: s)),
       android =
           android ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<void> permission() async {
    var status = await check();
    if (status == LocationPermission.denied) status = await request();
    if (status == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'blocked',
        'Quyền vị trí đã bị chặn. Mở Cài đặt ứng dụng và cho phép vị trí khi dùng app.',
      );
    }
    if (status != LocationPermission.whileInUse &&
        status != LocationPermission.always) {
      throw const LocationFailure(
        'denied',
        'Chưa được cấp quyền vị trí. Bạn vẫn có thể xem bản đồ.',
      );
    }
    if (!await enabled()) {
      throw const LocationFailure(
        'disabled',
        'Vị trí trên điện thoại đang tắt. Hãy bật trong Cài đặt vị trí.',
      );
    }
  }

  LocationSettings settings({bool stream = false}) => android
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: nativeProvider,
          timeLimit: stream ? null : const Duration(seconds: 20),
          distanceFilter: stream ? 12 : 0,
          intervalDuration: const Duration(seconds: 5),
        )
      : LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: stream ? null : const Duration(seconds: 20),
          distanceFilter: stream ? 12 : 0,
        );

  Future<Position> current() async {
    await permission();
    try {
      return await fix(settings()).timeout(const Duration(seconds: 22));
    } catch (e) {
      if (e is! TimeoutException && e is! PlatformException) rethrow;
      // Some Android devices have no working Google Play location provider.
      if (android && !nativeProvider) {
        nativeProvider = true;
        try {
          return await fix(settings()).timeout(const Duration(seconds: 22));
        } on TimeoutException {
          throw const LocationFailure(
            'timeout',
            'Chưa lấy được vị trí mới. Thử ra nơi thoáng, bật độ chính xác vị trí rồi nhấn định vị lại.',
          );
        } on PlatformException {
          throw const LocationFailure(
            'provider',
            'Dịch vụ định vị Android chưa sẵn sàng. Kiểm tra cài đặt vị trí rồi thử lại.',
          );
        }
      }
      throw const LocationFailure(
        'timeout',
        'Chưa lấy được vị trí mới. Kiểm tra quyền và dịch vụ vị trí rồi thử lại.',
      );
    }
  }
}

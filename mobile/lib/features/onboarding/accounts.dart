import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/state.dart';
import '../../core/api.dart';

final accountProvider = ChangeNotifierProvider<AccountController>((ref) {
  final c = AccountController(ref.watch(preferencesProvider));
  return c;
});

class AccountController extends ChangeNotifier {
  final SharedPreferences prefs;
  final Dio dio;
  late final Future<void> ready;
  Map<String, dynamic>? account;
  bool disposed = false;
  String? error;
  AccountController(this.prefs, {Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: apiBase,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    try {
      final raw = prefs.getString('${accountPrefix(prefs)}profile');
      if (raw != null) account = Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      /* Keep damaged cache; server remains authoritative. */
    }
    ready = restore();
  }
  String? get id => prefs.getString('active-account-id');
  bool get complete => account?['profile']?['setup_complete'] == true;
  String sessionKey(String uid) => 'account:$uid:departure-session:$apiBase';
  Future<Options> auth({bool session = true}) async => Options(
    headers: {
      'X-App-Token': await TrafficApi.storage.read(key: 'access') ?? '',
      if (session && id != null)
        'X-Schedule-Token':
            await TrafficApi.storage.read(key: sessionKey(id!)) ?? '',
    },
  );
  Future<void> cache(Map<String, dynamic> data) async {
    await prefs.setString(
      'account:${data['user_id']}:profile',
      jsonEncode(data),
    );
    if (!disposed && id == data['user_id']) {
      account = data;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    final requestedId = id;
    if (requestedId == null) return;
    try {
      final r = await dio.get('/api/v1/accounts/me', options: await auth());
      if (id != requestedId || disposed) return;
      error = null;
      await cache(Map<String, dynamic>.from(r.data));
    } catch (_) {
      if (id != requestedId || disposed) return;
      error = 'Chưa kết nối tài khoản; đang dùng hồ sơ đã lưu.';
    }
    if (!disposed) notifyListeners();
  }

  Future<void> authenticate(
    String username,
    String password, {
    required bool register,
  }) async {
    final r = await dio.post(
      '/api/v1/accounts/${register ? 'register' : 'login'}',
      data: {'username': username.trim(), 'password': password},
      options: await auth(session: false),
    );
    final data = Map<String, dynamic>.from(r.data);
    final uid = data['user_id'] as String;
    await TrafficApi.storage.write(
      key: sessionKey(uid),
      value: data.remove('token') as String,
    );
    if (!await prefs.setString('active-account-id', uid)) {
      throw StateError('Không lưu được tài khoản trên thiết bị.');
    }
    await cache(data);
    error = null;
  }

  Future<void> setup(Map<String, dynamic> body) async {
    final r = await dio.post(
      '/api/v1/accounts/setup',
      data: body,
      options: await auth(),
    );
    await cache(Map<String, dynamic>.from(r.data));
    error = null;
  }

  Future<void> logout() async {
    final uid = id;
    if (uid != null) {
      try {
        await dio.post('/api/v1/accounts/logout', options: await auth());
      } catch (_) {
        /* Local logout still works offline. */
      }
      await TrafficApi.storage.delete(key: sessionKey(uid));
    }
    await prefs.remove('active-account-id');
    account = null;
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    dio.close(force: true);
    super.dispose();
  }
}

String accountError(Object e) {
  if (e is StateError) return e.message.toString();
  if (e is DioException) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] is String) return detail['detail'];
    if (e.response?.statusCode == 422) {
      return 'Kiểm tra tên đăng nhập, mật khẩu và thông tin lịch.';
    }
  }
  return 'Không kết nối được backend Windows. Kiểm tra mạng và cấu hình access token trong Cài đặt.';
}

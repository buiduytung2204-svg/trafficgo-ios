import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend_config.dart';

class BackendConnectionScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const BackendConnectionScreen({super.key, required this.prefs});
  @override
  State<BackendConnectionScreen> createState() =>
      _BackendConnectionScreenState();
}

class _BackendConnectionScreenState extends State<BackendConnectionScreen> {
  late final text = TextEditingController(
    text: widget.prefs.getString(BackendConfig.key) ?? BackendConfig.current,
  );
  final probe = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: false,
    ),
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    probe.close(force: true);
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final url = BackendConfig.normalize(text.text);
      // No backend access token or account credentials sent during the probe.
      final response = await probe.get('$url/health');
      if (response.statusCode != 200 ||
          response.data is! Map ||
          response.data['status'] != 'ok') {
        throw const FormatException(
          'Địa chỉ chưa trả về health hợp lệ của backend.',
        );
      }
      if (!mounted) return;
      await BackendConfig.save(widget.prefs, url);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Đã lưu địa chỉ mới'),
          content: const Text(
            'Đóng hẳn rồi mở lại TrafficGo để áp dụng. Không cần cài lại app. '
            'Nếu đổi sang backend khác, bạn có thể cần đăng nhập lại; dữ liệu cục bộ vẫn được giữ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is FormatException ? e.message : 'Không kết nối được backend. Kiểm tra URL, Internet và tunnel rồi thử lại.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Địa chỉ backend')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Chỉ nhập URL backend của bạn hoặc máy chủ bạn tin cậy. '
            'Sau khi áp dụng, app sẽ gửi yêu cầu đăng nhập và dữ liệu tới địa chỉ này.',
          ),
          const SizedBox(height: 16),
          Text('Đang dùng: ${BackendConfig.current}'),
          const SizedBox(height: 16),
          TextField(
            controller: text,
            enabled: !busy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'URL backend',
              hintText: 'https://…trycloudflare.com',
              helperText: 'Không thêm /health hoặc access token.',
              errorText: error,
              errorMaxLines: 4,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Đang kiểm tra…' : 'Kiểm tra kết nối và lưu'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () {
                    text.text = BackendConfig.buildUrl;
                  },
            child: const Text('Dùng địa chỉ mặc định của bản cài'),
          ),
        ],
      ),
    ),
  );
}

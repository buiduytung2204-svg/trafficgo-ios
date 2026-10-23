import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/state.dart';
import '../../core/api.dart';
import '../../core/performance.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Chẩn đoán hiệu năng'),
            subtitle: const Text(
              'Số liệu cục bộ, không chứa vị trí hoặc token',
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Hiệu năng phiên chạy'),
                content: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                    child: SelectableText(PerformanceLog.instance.json),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Đóng'),
                  ),
                ],
              ),
            ),
          ),
          const ListTile(
            title: Text('Kết nối riêng tư'),
            subtitle: Text(apiBase),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Access token backend'),
            subtitle: Text(
              state.token.isEmpty
                  ? 'Chưa thiết lập'
                  : 'Đã lưu trong bộ nhớ bảo mật',
            ),
            onTap: () async {
              final controller = TextEditingController();
              final value = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Access token'),
                  content: TextField(
                    controller: controller,
                    obscureText: true,
                    autocorrect: false,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Lưu'),
                    ),
                  ],
                ),
              );
              if (value != null) await state.setToken(value);
            },
          ),
          SwitchListTile(
            title: const Text('Lớp giao thông'),
            value: state.traffic,
            onChanged: state.setTraffic,
          ),
          SwitchListTile(
            title: const Text('Lưu lịch sử tìm kiếm trên thiết bị'),
            value: state.historyEnabled,
            onChanged: state.setHistory,
          ),
          ListTile(
            title: const Text('Giao diện'),
            trailing: DropdownButton<ThemeMode>(
              value: state.theme,
              items: ThemeMode.values
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(['Theo hệ thống', 'Sáng', 'Tối'][m.index]),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) state.setTheme(v);
              },
            ),
          ),
          const ListTile(
            title: Text('Phương tiện mặc định: Ô tô'),
            subtitle: Text(
              'Có thể chọn ô tô hoặc xe máy trên bản đồ. ETA Valhalla chưa tính traffic realtime.',
            ),
          ),
          const ListTile(
            title: Text('Đơn vị: km • phút'),
            subtitle: Text(
              'Vị trí chỉ được xử lý khi ứng dụng hoạt động. Không lưu traffic hoặc bản đồ offline.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Xóa dữ liệu trên thiết bị'),
            onTap: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Xóa địa điểm, lịch sử và access token?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Hủy'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Xóa'),
                    ),
                  ],
                ),
              );
              if (yes == true) await state.erase();
            },
          ),
          const ListTile(
            title: Text('TrafficGo 0.1.0'),
            subtitle: Text(
              'Điều hướng cơ bản khi mở ứng dụng. Không có hướng dẫn giọng nói. Dữ liệu có thể thiếu hoặc chậm; tuân thủ biển báo thực tế.',
            ),
          ),
        ],
      ),
    );
  }
}

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Địa điểm đã lưu')),
      body: state.saved.isEmpty && state.trips.isEmpty
          ? const Center(child: Text('Chọn một điểm trên bản đồ rồi nhấn Lưu.'))
          : ListView(
              children: [
                for (final trip in state.trips)
                  ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(trip.name),
                    subtitle: Text(
                      '${trip.origin.name} → ${trip.destination.name}\nChỉ lưu hai điểm; tính tuyến mới từ GPS khi chọn.',
                    ),
                    onTap: () => context.pop(trip.destination),
                    trailing: IconButton(
                      tooltip: 'Xóa tuyến thường dùng',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => state.removeTrip(trip),
                    ),
                  ),
                ...state.saved.map(
                  (p) => ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.point.latitude.toStringAsFixed(4)}, ${p.point.longitude.toStringAsFixed(4)}',
                    ),
                    onTap: () => context.pop(p),
                    trailing: IconButton(
                      tooltip: 'Xóa địa điểm',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => state.remove(p),
                    ),
                  ),
                ),
                if (state.saved.any((p) => p.provider == 'geoapify') ||
                    state.trips.any(
                      (t) =>
                          t.destination.provider == 'geoapify' ||
                          t.origin.provider == 'geoapify',
                    ))
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () =>
                            launchUrl(Uri.parse('https://www.geoapify.com/')),
                        child: const Text('Powered by Geoapify'),
                      ),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                        ),
                        child: const Text('© OpenStreetMap contributors'),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

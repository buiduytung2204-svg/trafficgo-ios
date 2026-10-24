import '../../core/design/sheets.dart';
import '../../core/design/components.dart';
import '../onboarding/accounts.dart';
import '../onboarding/screens.dart';
import '../maintenance/screens.dart';
import '../map/map_screen.dart';
import '../journeys/screens.dart';
import '../journeys/place_picker.dart';
import '../../core/models.dart';
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
      appBar: AppBar(title: const Text('Cá nhân')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const SectionHeading(
            title: 'TrafficGo của bạn',
            subtitle: 'Địa điểm quen, sở thích và nhắc nhở trong một nơi.',
            icon: Icons.person_outline,
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('Địa điểm và tuyến đã lưu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/saved'),
          ),

          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              ref.watch(accountProvider).id == null
                  ? 'Tạo tài khoản / đăng nhập'
                  : 'Tài khoản và hồ sơ cá nhân',
            ),
            subtitle: const Text('Xe, địa điểm và lịch đi lại của bạn'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.two_wheeler),
            title: const Text('Xe và bảo dưỡng'),
            subtitle: const Text(
              'Honda 2020–2026 • tài liệu hãng và mốc bạn thiết lập',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GarageScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.route),
            title: const Text('Hành trình và chi phí'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JourneysScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Lịch nhắc giờ xuất phát'),
            subtitle: const Text('Lịch đi học, đi làm và lịch sử thông báo'),
            onTap: () => context.push('/schedules'),
          ),
          ExpansionTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Kết nối và chẩn đoán'),
            subtitle: const Text('Dành cho thiết lập thử nghiệm'),
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
                        TrafficPrimaryButton(
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
            ],
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
          ListTile(
            title: Text(
              'Phương tiện mặc định: ${state.defaultVehicle == 'motorcycle' ? 'Xe máy' : 'Ô tô'}',
            ),
            subtitle: const Text(
              'Chọn phương tiện trên bản đồ. Nguồn ETA và trạng thái giao thông hiển thị theo từng tuyến.',
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
            title: const Text('Xóa địa điểm, tuyến và lịch sử tìm kiếm'),
            subtitle: const Text(
              'Giữ lại xe, hành trình, chi phí và lịch nhắc. Access token trên máy sẽ bị xóa.',
            ),
            onTap: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text(
                    'Xóa địa điểm, tuyến đã lưu, lịch sử tìm kiếm và access token?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Hủy'),
                    ),
                    TrafficPrimaryButton(
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final p = await pickPlace(context);
          if (p != null && context.mounted) {
            await editSavedPlace(context, ref, p);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: state.saved.isEmpty && state.trips.isEmpty
          ? const Center(child: Text('Chọn một điểm trên bản đồ rồi nhấn Lưu.'))
          : ListView(
              children: [
                for (final trip in state.trips)
                  ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(trip.name),
                    subtitle: Text(
                      '${trip.origin.name} → ${trip.destination.name}\n${trip.route == null ? 'Tuyến cũ chỉ có hai điểm; cần tính tuyến.' : 'Mở đúng tuyến đã lưu; ETA tham khảo.'}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          plannedTrip: trip,
                          plannedVehicle: trip.vehicle,
                        ),
                      ),
                    ),
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
                    subtitle: Text('${p.address} ? ${p.category} ${p.notes}'),
                    onTap: () => context.pop(p),
                    onLongPress: () => editSavedPlace(context, ref, p),
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

Future<void> editSavedPlace(
  BuildContext context,
  WidgetRef ref,
  Place p,
) async {
  final name = TextEditingController(text: p.name),
      address = TextEditingController(text: p.address),
      notes = TextEditingController(text: p.notes);
  var category = p.category;
  String? error;
  final yes = await showTrafficSheet<bool>(
    context,
    title: 'Lưu / sửa địa điểm',
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: name,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Tên địa điểm',
              errorText: error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: address,
            decoration: const InputDecoration(labelText: 'Địa chỉ'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Phân loại'),
            items: const [
              DropdownMenuItem(value: 'home', child: Text('Nhà')),
              DropdownMenuItem(value: 'school', child: Text('Trường học')),
              DropdownMenuItem(value: 'work', child: Text('Công ty')),
              DropdownMenuItem(value: 'favorite', child: Text('Yêu thích')),
              DropdownMenuItem(value: 'other', child: Text('Khác')),
            ],
            onChanged: (v) => set(() => category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Ghi chú'),
          ),
          const SizedBox(height: 12),
          TrafficPrimaryButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                set(() => error = 'Nhập tên địa điểm');
                return;
              }
              Navigator.pop(c, true);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ),
  );
  if (yes == true) {
    final state = ref.read(stateProvider);
    state.remove(p);
    state.save(
      Place(
        name.text.trim(),
        p.point,
        provider: p.provider,
        sourceAttribution: p.sourceAttribution,
        address: address.text.trim(),
        category: category,
        notes: notes.text.trim(),
      ),
    );
  }
  Future.delayed(const Duration(seconds: 1), () {
    name.dispose();
    address.dispose();
    notes.dispose();
  });
}

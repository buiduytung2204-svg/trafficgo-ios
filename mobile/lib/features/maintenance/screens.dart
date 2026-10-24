import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../journeys/screens.dart';
import '../journeys/store.dart';
import 'store.dart';

class GarageScreen extends ConsumerWidget {
  const GarageScreen({super.key});
  Future<void> expense(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> receipt,
  ) async {
    final existing = ref
        .read(journeysProvider)
        .expenses
        .where((e) => e.id == receipt['id'])
        .firstOrNull;
    await editExpense(
      context,
      ref,
      existing:
          existing ??
          Expense(
            id: receipt['id'],
            category: 'other',
            date: (receipt['completed_at'] as String).split('T').first,
            amount: 0,
            notes: 'Bảo dưỡng ${receipt['vehicle_name']}: ${receipt['name']}',
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final garage = ref.watch(garageProvider);
    final catalog = ref.watch(hondaCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Xe và bảo dưỡng')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: catalog.hasValue
            ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VehicleEditor(catalog: catalog.requireValue),
                ),
              )
            : null,
        icon: const Icon(Icons.add),
        label: const Text('Thêm xe'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            'Nhắc trong ứng dụng khi mở màn hình. Chưa gửi push bảo dưỡng khi app đóng. Số km do bạn cập nhật từ công-tơ-mét; không cộng từ tuyến dự kiến.',
          ),
          if (garage.error != null) Text(garage.error!),
          if (catalog.isLoading) const LinearProgressIndicator(),
          if (catalog.hasError)
            TextButton(
              onPressed: () => ref.invalidate(hondaCatalogProvider),
              child: const Text('Không đọc được danh mục. Thử lại'),
            ),
          if (garage.vehicles.isEmpty)
            const ListTile(
              title: Text('Chưa có xe'),
              subtitle: Text(
                'Thêm Honda Wave, Vision, Future, LEAD, SH hoặc SH mode (2020–2026).',
              ),
            ),
          for (final v in garage.vehicles)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v['name'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${v['year']} • ${v['variant']} • ${v['odometer']} km',
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () async {
                            final value = await editText(
                              context,
                              'Công-tơ-mét hiện tại (km)',
                              initial: '${v['odometer']}',
                            );
                            if (value == null) return;
                            try {
                              final km = int.tryParse(value);
                              if (km == null) {
                                throw ArgumentError('Nhập số km nguyên');
                              }
                              await garage.saveVehicle({...v, 'odometer': km});
                            } catch (e) {
                              if (context.mounted) notifyError(context, e);
                            }
                          },
                          child: const Text('Cập nhật số km'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MaintenanceEditor(vehicle: v),
                            ),
                          ),
                          child: const Text('Thêm mốc nhắc'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Xóa xe và các mốc nhắc?'),
                                content: const Text(
                                  'Lịch sử bảo dưỡng và chi phí đã ghi vẫn được giữ.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Xóa'),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) {
                              try {
                                await garage.removeVehicle(v['id']);
                              } catch (e) {
                                if (context.mounted) notifyError(context, e);
                              }
                            }
                          },
                          child: const Text('Xóa xe'),
                        ),
                      ],
                    ),
                    if (catalog.hasValue)
                      ManualLinks(catalog: catalog.requireValue, vehicle: v),
                    for (final item in garage.items.where(
                      (i) => i['vehicle_id'] == v['id'],
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${item['name']} • ${maintenanceStatus(item, v, DateTime.now())}',
                        ),
                        subtitle: Text(
                          '${item['due_date'] == null ? '' : 'Ngày: ${item['due_date']}'} ${item['due_km'] == null ? '' : '• Mốc ${item['due_km']} km'}\n${item['source'] == 'honda_manual_selected_item' ? 'Theo ${item['source_label']}, trang PDF ${item['source_pdf_page']} • đã xác nhận sổ' : 'Do người dùng thiết lập'} • ${item['notes'] ?? ''}',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MaintenanceEditor(vehicle: v, item: item),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Xác nhận đã bảo dưỡng',
                          icon: const Icon(Icons.task_alt),
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text(
                                  'Đã thực hiện bảo dưỡng này?',
                                ),
                                content: const Text(
                                  'Ghi vào lịch sử với số km hiện tại. Bạn sẽ tự thiết lập mốc tiếp theo; không tự tạo chi phí.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Hủy'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Đã thực hiện'),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) {
                              try {
                                await garage.complete(item['id']);
                              } catch (e) {
                                if (context.mounted) notifyError(context, e);
                              }
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const Divider(),
          const Text('Lịch sử bảo dưỡng'),
          for (final h in garage.history.reversed)
            ListTile(
              title: Text('${h['vehicle_name']} • ${h['name']}'),
              subtitle: Text(
                '${h['completed_at'].toString().split('T').first} • ${h['odometer']} km',
              ),
              trailing: TextButton(
                onPressed: () => expense(context, ref, h),
                child: const Text('Chi phí'),
              ),
            ),
        ],
      ),
    );
  }
}

class ManualLinks extends ConsumerWidget {
  final Map<String, dynamic> catalog, vehicle;
  const ManualLinks({super.key, required this.catalog, required this.vehicle});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = (catalog['models'] as List).where(
      (m) => m['id'] == vehicle['model_id'],
    );
    final model = models.firstOrNull;
    final manuals = model == null
        ? <dynamic>[]
        : (model['manuals'] as List)
              .where((m) => m['year'] == vehicle['year'])
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          manuals.isEmpty
              ? 'Chưa tìm thấy HDSD đúng nhãn năm ${vehicle['year']} trong danh mục hãng đã kiểm tra.'
              : 'Có liên kết HDSD do Honda liệt kê cho năm này; chưa xác minh áp dụng riêng cho phiên bản bạn chọn.',
        ),
        Text(
          manuals.isEmpty
              ? 'Chưa có mốc xác minh: mốc nhắc do bạn nhập theo sổ xe. Không tự dùng sổ đời khác.'
              : 'Đã đối chiếu riêng hàng thay dầu trong sách. Các hạng mục khác chưa xác minh; cần kiểm tra đúng mã xe/phiên bản trước khi dùng.',
        ),
        for (final m in manuals) ...[
          if ((m['maintenance_rules'] as List? ?? []).isNotEmpty)
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VerifiedOilEditor(
                    vehicle: vehicle,
                    manual: Map<String, dynamic>.from(m),
                  ),
                ),
              ),
              child: Text('Thiết lập mốc thay dầu • ${m['label']}'),
            ),
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(m['index_url']),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.menu_book),
            label: Text('Honda: ${m['label']}'),
          ),
        ],
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(catalog['official_index']),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Mở danh mục HDSD và điều khoản Honda'),
        ),
      ],
    );
  }
}

class VehicleEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic> catalog;
  const VehicleEditor({super.key, required this.catalog});
  @override
  ConsumerState<VehicleEditor> createState() => _VehicleEditorState();
}

class _VehicleEditorState extends ConsumerState<VehicleEditor> {
  final name = TextEditingController(), odo = TextEditingController(text: '0');
  String modelId = 'wave_alpha',
      variant = 'Chưa xác định / nhập theo giấy tờ xe';
  int year = 2026;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    odo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = (widget.catalog['models'] as List).firstWhere(
      (m) => m['id'] == modelId,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm xe Honda Việt Nam')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: modelId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dòng xe / dung tích'),
            items: [
              for (final m in widget.catalog['models'])
                DropdownMenuItem(
                  value: m['id'] as String,
                  child: Text(m['name']),
                ),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  modelId = v;
                  variant = (widget.catalog['models'] as List)
                      .firstWhere((m) => m['id'] == v)['variants']
                      .first;
                });
              }
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: year,
            decoration: const InputDecoration(labelText: 'Năm xe theo giấy tờ'),
            items: [
              for (var y = 2020; y <= 2026; y++)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (v) => setState(() => year = v!),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(modelId),
            initialValue: variant,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Phiên bản bạn khai báo',
            ),
            items: [
              for (final v in model['variants'])
                DropdownMenuItem(
                  value: v as String,
                  child: Tooltip(
                    message: v,
                    child: Text(
                      v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => variant = v!),
          ),
          Text(model['variant_note']),
          TextField(
            controller: name,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Tên xe (tùy chọn)',
              helperText: 'Để trống để dùng tên dòng xe',
              helperMaxLines: 2,
            ),
          ),
          TextField(
            controller: odo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số km công-tơ-mét hiện tại',
            ),
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final km = int.tryParse(odo.text.trim());
                    if (km == null || km < 0) {
                      setState(() => error = 'Nhập số km nguyên không âm');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await ref.read(garageProvider).saveVehicle({
                        'id': newId(),
                        'model_id': modelId,
                        'name': name.text.trim().isEmpty
                            ? '${model['name']} $year'
                            : name.text.trim(),
                        'year': year,
                        'variant': variant,
                        'odometer': km,
                      });
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Lưu hồ sơ xe'),
          ),
        ],
      ),
    );
  }
}

class MaintenanceEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic> vehicle;
  final Map<String, dynamic>? item;
  const MaintenanceEditor({super.key, required this.vehicle, this.item});
  @override
  ConsumerState<MaintenanceEditor> createState() => _MaintenanceEditorState();
}

class _MaintenanceEditorState extends ConsumerState<MaintenanceEditor> {
  final name = TextEditingController(),
      km = TextEditingController(),
      notes = TextEditingController();
  DateTime? due;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    name.text = widget.item?['name'] ?? '';
    km.text = widget.item?['due_km']?.toString() ?? '';
    notes.text = widget.item?['notes'] ?? '';
    due = DateTime.tryParse(widget.item?['due_date'] ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    km.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mốc bảo dưỡng bạn thiết lập')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Tra đúng sách xe/HEAD trước khi nhập. Không có chu kỳ tự điền hoặc khuyến nghị của TrafficGo. Đến một trong hai mốc ngày/km sẽ được đánh dấu đến hạn.',
        ),
        TextField(
          controller: name,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Hạng mục (thay dầu, kiểm tra phanh…)',
          ),
        ),
        ListTile(
          title: Text(
            due == null
                ? 'Chọn ngày đến hạn (tùy chọn)'
                : due!.toIso8601String().split('T').first,
          ),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: due ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => due = d);
          },
          trailing: IconButton(
            onPressed: () => setState(() => due = null),
            tooltip: 'Bỏ mốc ngày',
            icon: const Icon(Icons.clear),
          ),
        ),
        TextField(
          controller: km,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Mốc công-tơ-mét cần bảo dưỡng (km, tùy chọn)',
          ),
        ),
        TextField(
          controller: notes,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Nguồn / ghi chú theo sổ xe',
          ),
        ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  final k = km.text.trim().isEmpty
                      ? null
                      : int.tryParse(km.text.trim());
                  if (km.text.trim().isNotEmpty && k == null) {
                    setState(() => error = 'Số km không hợp lệ');
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    await ref.read(garageProvider).saveItem({
                      'id': widget.item?['id'] ?? newId(),
                      'vehicle_id': widget.vehicle['id'],
                      'name': name.text.trim(),
                      'due_date': due?.toIso8601String().split('T').first,
                      'due_km': k,
                      'notes': notes.text.trim(),
                    });
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('Lưu mốc nhắc'),
        ),
        if (widget.item != null)
          TextButton(
            onPressed: () async {
              try {
                await ref.read(garageProvider).removeItem(widget.item!['id']);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) setState(() => error = e.toString());
              }
            },
            child: const Text('Xóa mốc nhắc'),
          ),
      ],
    ),
  );
}

class VerifiedOilEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic> vehicle, manual;
  const VerifiedOilEditor({
    super.key,
    required this.vehicle,
    required this.manual,
  });
  @override
  ConsumerState<VerifiedOilEditor> createState() => _VerifiedOilEditorState();
}

class _VerifiedOilEditorState extends ConsumerState<VerifiedOilEditor> {
  final lastKm = TextEditingController();
  DateTime? lastDate;
  bool confirmed = false, busy = false;
  String? error;
  @override
  void dispose() {
    lastKm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.manual['maintenance_rules'][0];
    return Scaffold(
      appBar: AppBar(title: const Text('Đối chiếu mốc thay dầu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.manual['label']} • trang PDF ${rule['source_pdf_page']}',
          ),
          Text(
            'Lần đầu: ${rule['first_km']} km. Sau đó các mốc công-tơ-mét ${rule['grid_step_km']}, ${rule['grid_step_km'] * 2}, ${rule['grid_step_km'] * 3} km… hoặc hàng năm, tùy mốc đến trước. Đây là lịch tiêu chuẩn, không thay thế kiểm tra theo điều kiện sử dụng/HEAD.',
          ),
          if (rule['market_section'] != null) Text(rule['market_section']),
          if (rule['document_note'] != null) Text(rule['document_note']),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(widget.manual['index_url']),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Mở đúng sách Honda để đối chiếu'),
          ),
          TextField(
            controller: lastKm,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Km ở lần thay dầu gần nhất',
              helperText:
                  'Để trống chỉ khi xe chưa thay dầu lần đầu. Không nhập quãng đường tuyến.',
            ),
          ),
          ListTile(
            title: Text(
              lastDate == null
                  ? 'Chọn ngày thay dầu gần nhất / nhận xe mới'
                  : lastDate!.toIso8601String().split('T').first,
            ),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: lastDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => lastDate = d);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: confirmed,
            onChanged: (v) => setState(() => confirmed = v ?? false),
            title: const Text(
              'Tôi đã đối chiếu đúng đời, mã xe và phiên bản trong sách này.',
            ),
          ),
          const Text(
            'Không tự xác nhận sách dùng chung cho bản Sport/tiêu chuẩn. Nếu không chắc mã xe, dùng mốc tự nhập và hỏi HEAD.',
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy || !confirmed
                ? null
                : () async {
                    final km = lastKm.text.trim().isEmpty
                        ? null
                        : int.tryParse(lastKm.text.trim());
                    if (lastDate == null ||
                        (lastKm.text.trim().isNotEmpty && km == null)) {
                      setState(() => error = 'Chọn ngày và nhập số km hợp lệ.');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await ref
                          .read(garageProvider)
                          .addVerifiedOil(
                            vehicleId: widget.vehicle['id'],
                            manualId: widget.manual['id'],
                            confirmed: confirmed,
                            lastServiceKm: km,
                            lastServiceDate: lastDate!,
                          );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Xác nhận tạo mốc nhắc theo sách'),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/state.dart';

final hondaCatalogProvider = FutureProvider<Map<String, dynamic>>(
  (ref) async =>
      jsonDecode(
            await rootBundle.loadString(
              'assets/data/honda_vn_maintenance.json',
            ),
          )
          as Map<String, dynamic>,
);
final garageProvider = ChangeNotifierProvider<GarageStore>(
  (ref) => GarageStore(ref.watch(preferencesProvider)),
);

/// Honda tables have an initial milestone, then an absolute odometer grid.
/// A service at 1,000 km does not shift the next 6,000 km milestone to 7,000 km.
int nextOilMilestone(Map<String, dynamic> rule, int? lastServiceKm) {
  final first = rule['first_km'] as int;
  final step = rule['grid_step_km'] as int;
  if (first <= 0 ||
      step <= first ||
      (lastServiceKm != null && lastServiceKm < 0)) {
    throw ArgumentError('Invalid verified maintenance grid');
  }
  if (lastServiceKm == null || lastServiceKm < first) return first;
  return (lastServiceKm ~/ step + 1) * step;
}

DateTime annualOilDate(DateTime lastService) {
  final maxDay = DateTime(lastService.year + 1, lastService.month + 1, 0).day;
  return DateTime(
    lastService.year + 1,
    lastService.month,
    lastService.day > maxDay ? maxDay : lastService.day,
  );
}

String maintenanceStatus(
  Map<String, dynamic> item,
  Map<String, dynamic> vehicle,
  DateTime now,
) {
  final due = DateTime.tryParse(item['due_date'] ?? '');
  final today = DateTime(now.year, now.month, now.day);
  final remainingKm = item['due_km'] == null
      ? null
      : (item['due_km'] as int) - (vehicle['odometer'] as int);
  if ((due != null && due.isBefore(today)) ||
      (remainingKm != null && remainingKm < 0)) {
    return 'Quá hạn';
  }
  if ((due != null && !due.isAfter(today)) || remainingKm == 0) {
    return 'Đến hạn';
  }
  if ((due != null && due.difference(today).inDays <= 7) ||
      (remainingKm != null && remainingKm <= 100)) {
    return 'Sắp đến hạn';
  }
  return 'Chưa đến hạn';
}

class GarageStore extends ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  final SharedPreferences prefs;
  List<Map<String, dynamic>> vehicles = [], items = [], history = [];
  String? error;
  Future<void> queue = Future.value();
  late final String storageKey;
  GarageStore(this.prefs) {
    storageKey = "${accountPrefix(prefs)}garage.v1";
    try {
      final data = jsonDecode(prefs.getString(storageKey) ?? '{}');
      vehicles = (data['vehicles'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      items = (data['items'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      history = (data['history'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
    } catch (_) {
      error =
          'Không đọc được hồ sơ xe. Giữ bản lưu, khóa ghi để tránh mất dữ liệu.';
    }
  }
  Future<void> change(void Function() action) {
    final result = queue.then((_) async {
      if (error != null) throw StateError(error!);
      final backup = jsonEncode({
        'vehicles': vehicles,
        'items': items,
        'history': history,
      });
      try {
        action();
        final ok = await prefs.setString(
          storageKey,
          jsonEncode({
            'version': 1,
            'vehicles': vehicles,
            'items': items,
            'history': history,
          }),
        );
        if (!ok) throw StateError('Không lưu được hồ sơ xe');
        if (!_disposed) notifyListeners();
      } catch (_) {
        final old = jsonDecode(backup);
        vehicles = (old['vehicles'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        items = (old['items'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        history = (old['history'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        if (!_disposed) notifyListeners();
        rethrow;
      }
    });
    queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> saveVehicle(Map<String, dynamic> v) => change(() {
    if ((v['name'] as String).trim().isEmpty ||
        (v['odometer'] as int) < 0 ||
        (v['year'] as int) < 2020 ||
        v['year'] > 2026) {
      throw ArgumentError('Thông tin xe không hợp lệ');
    }
    final old = vehicles.where((x) => x['id'] == v['id']).firstOrNull;
    if (old != null && v['odometer'] < old['odometer']) {
      throw ArgumentError('Số km mới không được nhỏ hơn số km đã ghi');
    }
    vehicles = [
      for (final x in vehicles)
        if (x['id'] != v['id']) x,
      Map<String, dynamic>.from(v),
    ];
  });
  Future<void> saveItem(Map<String, dynamic> item) => change(() {
    if (!vehicles.any((v) => v['id'] == item['vehicle_id'])) {
      throw ArgumentError('Xe không tồn tại');
    }
    if ((item['name'] as String).trim().isEmpty ||
        (item['due_date'] == null && item['due_km'] == null)) {
      throw ArgumentError('Nhập tên và ít nhất một mốc nhắc');
    }
    if (item['due_date'] != null &&
        DateTime.tryParse(item['due_date']) == null) {
      throw ArgumentError('Ngày không hợp lệ');
    }
    if (item['due_km'] != null && item['due_km'] < 0) {
      throw ArgumentError('Số km không hợp lệ');
    }
    items = [
      for (final x in items)
        if (x['id'] != item['id']) x,
      {...item, 'source': 'user_defined'},
    ];
  });
  Future<void> removeItem(String id) =>
      change(() => items.removeWhere((x) => x['id'] == id));

  Future<void> addVerifiedOil({
    required String vehicleId,
    required int manualId,
    required bool confirmed,
    required int? lastServiceKm,
    required DateTime lastServiceDate,
  }) async {
    if (!confirmed) throw ArgumentError('Cần đối chiếu đúng sổ và mã xe');
    final catalog = jsonDecode(
      await rootBundle.loadString('assets/data/honda_vn_maintenance.json'),
    );
    await change(() {
      final v = vehicles.firstWhere((v) => v['id'] == vehicleId);
      final model = (catalog['models'] as List).firstWhere(
        (m) => m['id'] == v['model_id'],
      );
      final manual = (model['manuals'] as List)
          .where((m) => m['id'] == manualId && m['year'] == v['year'])
          .firstOrNull;
      if (manual == null) {
        throw ArgumentError('Không có tài liệu đúng dòng/năm đã chọn');
      }
      if (lastServiceKm != null &&
          (lastServiceKm < 0 || lastServiceKm > v['odometer'])) {
        throw ArgumentError(
          'Km lần thay dầu không được lớn hơn công-tơ-mét hiện tại',
        );
      }
      if (lastServiceDate.isAfter(DateTime.now())) {
        throw ArgumentError('Ngày bảo dưỡng không được ở tương lai');
      }
      final rule = Map<String, dynamic>.from(
        (manual['maintenance_rules'] as List).single,
      );
      final dueKm = nextOilMilestone(rule, lastServiceKm);
      final id =
          'oil-$vehicleId-$dueKm-${lastServiceDate.toIso8601String().split('T').first}';
      if (history.any((h) => h['item_id'] == id)) {
        throw ArgumentError(
          'Mốc này đã hoàn thành. Cập nhật lần thay dầu gần nhất để tạo mốc tiếp theo.',
        );
      }
      items = [
        for (final i in items)
          if (!(i['vehicle_id'] == vehicleId &&
              i['kind'] == 'engine_oil_replacement'))
            i,
        {
          'id': id,
          'vehicle_id': vehicleId,
          'name': 'Thay dầu động cơ',
          'due_km': dueKm,
          'kind': 'engine_oil_replacement',
          'due_date': annualOilDate(
            lastServiceDate,
          ).toIso8601String().split('T').first,
          'source': 'honda_manual_selected_item',
          'rule_id': rule['id'],
          'manual_id': manualId,
          'source_label': manual['label'],
          'source_pdf_page': rule['source_pdf_page'],
          'source_url': manual['index_url'],
          'manual_confirmed_by_user': true,
          'last_service_km': lastServiceKm,
          'last_service_date': lastServiceDate
              .toIso8601String()
              .split('T')
              .first,
          'notes':
              'Mốc thay dầu theo bảng đã đối chiếu; đến ngày hoặc km trước. Điều kiện sử dụng cần kiểm tra với HEAD.',
        },
      ];
    });
  }

  Future<void> removeVehicle(String id) => change(() {
    vehicles.removeWhere((v) => v['id'] == id);
    items.removeWhere((v) => v['vehicle_id'] == id);
  });
  Future<Map<String, dynamic>> complete(String id) async {
    late Map<String, dynamic> receipt;
    await change(() {
      final item = items.where((v) => v['id'] == id).firstOrNull;
      if (item == null) {
        final old = history.where((v) => v['item_id'] == id).firstOrNull;
        if (old == null) throw StateError('Hạng mục không tồn tại');
        receipt = old;
        return;
      }
      final vehicle = vehicles.firstWhere((v) => v['id'] == item['vehicle_id']);
      receipt = {
        'id': 'maintenance-$id',
        'item_id': id,
        'name': item['name'],
        'vehicle_id': vehicle['id'],
        'vehicle_name': vehicle['name'],
        'odometer': vehicle['odometer'],
        'completed_at': DateTime.now().toIso8601String(),
        'source': 'user_confirmed',
      };
      history.add(receipt);
      items.removeWhere((v) => v['id'] == id);
    });
    return receipt;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/design/components.dart';
import '../../core/design/sheets.dart';
import 'controller.dart';
import 'models.dart';

String departureError(Object error) {
  if (error is DioException && error.response?.data is Map) {
    final message = error.response?.data['detail'];
    if (message is String) return message;
  }
  return 'Chưa lưu được. Kiểm tra kết nối backend rồi thử lại.';
}

class DayExceptionEditor extends ConsumerStatefulWidget {
  final CommuteSchedule schedule;
  const DayExceptionEditor({super.key, required this.schedule});
  @override
  ConsumerState<DayExceptionEditor> createState() => _DayExceptionEditorState();
}

class _DayExceptionEditorState extends ConsumerState<DayExceptionEditor> {
  late DateTime day;
  late TimeOfDay arrival;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    // Calendar day is always Vietnam time, independent of the phone timezone.
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    day =
        DateTime.tryParse(widget.schedule.json['one_off_date'] ?? '') ??
        DateTime(now.year, now.month, now.day);
    final parts = (widget.schedule.json['arrival_time'] as String).split(':');
    arrival = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String get dateKey =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  Future<void> save(String action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final time =
          '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
      await ref.read(departureProvider).mutate(
        'PUT',
        'schedules/${widget.schedule.id}/exceptions/$dateKey',
        {'action': action, if (action == 'change') 'arrival_time': time},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = departureError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.schedule.name),
      const Text('Chỉ áp dụng ngày đã chọn. Lịch cả tuần giữ nguyên.'),
      TextButton.icon(
        icon: const Icon(Icons.calendar_today),
        label: Text('Ngày: $dateKey'),
        onPressed: busy
            ? null
            : () async {
                final now = DateTime.now().toUtc().add(
                  const Duration(hours: 7),
                );
                final first = DateTime(now.year, now.month, now.day);
                final selected = await pickTrafficDate(
                  context,
                  initialDate: day,
                  firstDate: first,
                  lastDate: first.add(const Duration(days: 366)),
                );
                if (selected != null && mounted) setState(() => day = selected);
              },
      ),
      TextButton.icon(
        icon: const Icon(Icons.schedule),
        label: Text('Giờ cần đến riêng: ${arrival.format(context)}'),
        onPressed: busy
            ? null
            : () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: arrival,
                );
                if (selected != null && mounted) {
                  setState(() => arrival = selected);
                }
              },
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      TrafficPrimaryButton(
        onPressed: busy ? null : () => save('change'),
        child: const Text('Đổi giờ ngày này'),
      ),
      TextButton(
        onPressed: busy ? null : () => save('skip'),
        child: const Text('Nghỉ / bỏ qua ngày này'),
      ),
      TextButton(
        onPressed: busy ? null : () => save('reset'),
        child: const Text('Khôi phục theo lịch tuần'),
      ),
    ],
  );
}

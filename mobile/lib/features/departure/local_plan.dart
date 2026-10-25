import 'dart:convert';

import 'models.dart';

class LocalDeparturePlan {
  final String id, title, body, scope;
  final DateTime at;
  const LocalDeparturePlan(this.id, this.title, this.body, this.scope, this.at);
  String get payload => jsonEncode({'event_id': id, 'scope': scope});
  String get signature =>
      jsonEncode([at.toUtc().toIso8601String(), title, body, payload]);
}

/// Uses only server-materialized occurrences and their last known ETA.
/// No invented future ETA, repeated OS alarms or routing API calls.
List<LocalDeparturePlan> departurePlans(
  List<CommuteSchedule> schedules,
  String scope,
  DateTime now, {
  int limit = 60,
}) {
  final result = <String, LocalDeparturePlan>{};
  for (final schedule in schedules) {
    if (!schedule.enabled) continue;
    final rows = schedule.json['upcoming_occurrences'] is List
        ? schedule.json['upcoming_occurrences'] as List
        : [if (schedule.occurrence != null) schedule.occurrence];
    for (final raw in rows) {
      final occurrence = Map<String, dynamic>.from(raw);
      if (occurrence['status'] != 'planned' ||
          occurrence['id'] is! String ||
          occurrence['eta_s'] == null) {
        continue;
      }
      final arrival = parseInstant(occurrence['arrival_at']);
      if (arrival == null ||
          !arrival.isAfter(now) ||
          arrival.isAfter(now.add(const Duration(days: 8)))) {
        continue;
      }
      final snooze = parseInstant(occurrence['snooze_until']);
      for (final entry in [
        ('preparation_soon', 'Sắp đến giờ chuẩn bị', 'prepare_at', -5),
        ('preparation_due', 'Đến giờ chuẩn bị', 'prepare_at', 0),
        ('departure_soon', 'Sắp đến giờ xuất phát', 'departure_at', -5),
        ('departure_due', 'Đến giờ xuất phát', 'departure_at', 0),
      ]) {
        if (entry.$1.startsWith('preparation') &&
            occurrence['prepare_at'] == occurrence['departure_at']) {
          continue;
        }
        final time = parseInstant(occurrence[entry.$3]);
        if (time == null) continue;
        final at = time.add(Duration(minutes: entry.$4));
        if (!at.isAfter(now) || (snooze != null && !at.isAfter(snooze))) {
          continue;
        }
        final id = 'local:${occurrence['id']}:${entry.$1}';
        result[id] = LocalDeparturePlan(
          id,
          entry.$2,
          '${schedule.name} • Theo ETA đã đồng bộ${occurrence['traffic_aware'] == true ? '' : ', chưa xét giao thông trực tiếp'}.',
          scope,
          at,
        );
      }
    }
  }
  final sorted = result.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  return sorted.take(limit).toList();
}

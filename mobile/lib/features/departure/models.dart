DateTime? parseInstant(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

// Server times are ISO instants; display explicitly in Vietnam, independent of device zone.
String vietnamTime(dynamic value) {
  final instant = parseInstant(value);
  if (instant == null) return 'Chưa tính';
  final vn = instant.toUtc().add(const Duration(hours: 7));
  return '${vn.day.toString().padLeft(2, '0')}/${vn.month.toString().padLeft(2, '0')} '
      '${vn.hour.toString().padLeft(2, '0')}:${vn.minute.toString().padLeft(2, '0')}';
}

String departureCountdown(DateTime departure, DateTime now) {
  final seconds = departure.difference(now).inSeconds;
  if (seconds <= 0) return 'Đã đến giờ xuất phát';
  final minutes = (seconds / 60).ceil();
  return minutes >= 60
      ? 'Còn ${minutes ~/ 60} giờ ${minutes % 60} phút'
      : 'Còn $minutes phút';
}

class CommuteSchedule {
  final Map<String, dynamic> json;
  const CommuteSchedule(this.json);
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  bool get enabled => json['enabled'] == true;
  Map<String, dynamic>? get occurrence => json['occurrence'] is Map
      ? Map<String, dynamic>.from(json['occurrence'])
      : null;
  Map<String, dynamic> input() => {
    for (final key in [
      'name',
      'saved_route_id',
      'route_name',
      'journey_id',
      'direction',
      'origin',
      'destination',
      'origin_name',
      'destination_name',
      'vehicle',
      'arrival_time',
      'weekdays',
      'one_off_date',
      'preparation_minutes',
      'buffer_minutes',
      'enabled',
      'initial_eta_s',
    ])
      if (json.containsKey(key)) key: json[key],
  };
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/state.dart';
import '../../core/models.dart';

final journeysProvider = ChangeNotifierProvider<JourneyStore>(
  (ref) => JourneyStore(ref.watch(preferencesProvider)),
);
String newId() => '${DateTime.now().microsecondsSinceEpoch}';
const expenseTypes = {
  'fuel': 'Xăng',
  'parking': 'Gửi xe',
  'toll': 'Cầu đường',
  'bus': 'Xe buýt',
  'rail': 'Tàu',
  'taxi': 'Taxi / xe công nghệ',
  'other': 'Khác',
};

class Journey {
  final String id, name, category;
  final bool enabled;
  final SavedTrip? outbound, inbound;
  const Journey({
    required this.id,
    required this.name,
    this.category = 'school',
    this.enabled = true,
    this.outbound,
    this.inbound,
  });
  Journey copy({
    String? name,
    String? category,
    bool? enabled,
    SavedTrip? outbound,
    SavedTrip? inbound,
  }) => Journey(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    enabled: enabled ?? this.enabled,
    outbound: outbound ?? this.outbound,
    inbound: inbound ?? this.inbound,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'enabled': enabled,
    'outbound': outbound?.toJson(),
    'inbound': inbound?.toJson(),
  };
  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    id: j['id'],
    name: j['name'],
    category: j['category'] ?? 'personal',
    enabled: j['enabled'] ?? true,
    outbound: j['outbound'] == null ? null : SavedTrip.fromJson(j['outbound']),
    inbound: j['inbound'] == null ? null : SavedTrip.fromJson(j['inbound']),
  );
}

class Expense {
  final String id, category, date, notes;
  final String? journeyId, direction;
  final int amount;
  const Expense({
    required this.id,
    required this.category,
    required this.date,
    required this.amount,
    this.notes = '',
    this.journeyId,
    this.direction,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'date': date,
    'amount': amount,
    'notes': notes,
    'journey_id': journeyId,
    'direction': direction,
  };
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'],
    category: j['category'],
    date: j['date'],
    amount: j['amount'],
    notes: j['notes'] ?? '',
    journeyId: j['journey_id'],
    direction: j['direction'],
  );
}

class JourneyStore extends ChangeNotifier {
  final SharedPreferences prefs;
  List<Journey> journeys = [];
  List<Expense> expenses = [];
  List<Map<String, dynamic>> completed = [];
  String? loadError;
  JourneyStore(this.prefs) {
    try {
      final j = jsonDecode(prefs.getString('journeys.v1') ?? '{}') as Map;
      journeys = (j['journeys'] as List? ?? [])
          .map((v) => Journey.fromJson(v))
          .toList();
      expenses = (j['expenses'] as List? ?? [])
          .map((v) => Expense.fromJson(v))
          .toList();
      completed = (j['completed'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
    } catch (_) {
      loadError =
          'Không đọc được dữ liệu hành trình. Bản lưu được giữ lại, không ghi đè.';
    }
  }
  // Single versioned document: no destructive migration of legacy saved places/trips.
  Future<void> persist() async {
    if (loadError != null) throw StateError(loadError!);
    final ok = await prefs.setString(
      'journeys.v1',
      jsonEncode({
        'version': 1,
        'journeys': journeys.map((j) => j.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'completed': completed,
      }),
    );
    if (!ok) throw StateError('Không lưu được dữ liệu trên thiết bị');
    notifyListeners();
  }

  Future<void> _queue = Future.value();
  Future<void> change(void Function() action) {
    final task = _queue.then((_) async {
      if (loadError != null) throw StateError(loadError!);
      final oldJourneys = [...journeys], oldExpenses = [...expenses];
      final oldCompleted = [...completed];
      try {
        action();
        await persist();
      } catch (_) {
        journeys = oldJourneys;
        expenses = oldExpenses;
        completed = oldCompleted;
        notifyListeners();
        rethrow;
      }
    });
    _queue = task.catchError((Object _) {});
    return task;
  }

  Future<void> saveJourney(Journey j) => change(() {
    journeys = [
      for (final old in journeys)
        if (old.id != j.id) old,
      j,
    ];
  });
  Future<void> deleteJourney(String id) =>
      change(() => journeys.removeWhere((j) => j.id == id));
  Future<void> saveExpense(Expense e) async {
    if (e.amount <= 0 ||
        e.amount > 1000000000 ||
        !expenseTypes.containsKey(e.category) ||
        DateTime.tryParse(e.date) == null) {
      throw ArgumentError('Khoản chi không hợp lệ');
    }
    await change(
      () => expenses = [
        for (final old in expenses)
          if (old.id != e.id) old,
        e,
      ],
    );
  }

  Future<void> deleteExpense(String id) =>
      change(() => expenses.removeWhere((e) => e.id == id));
  Future<void> complete(
    String id, {
    String? journeyId,
    String? direction,
    required SavedTrip trip,
  }) => change(() {
    if (completed.any((c) => c['id'] == id)) return;
    completed.add({
      'id': id,
      'journey_id': journeyId,
      'direction': direction,
      'name': trip.name,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'distance_m': trip.route?.meters,
    });
  });

  int total(DateTime from, DateTime until) => expenses
      .where((e) {
        final d = DateTime.parse(e.date);
        return !d.isBefore(from) && d.isBefore(until);
      })
      .fold(0, (sum, e) => sum + e.amount);
}

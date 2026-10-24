import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';

final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
final stateProvider = ChangeNotifierProvider<AppState>(
  (ref) => AppState(ref.watch(preferencesProvider)),
);
final apiProvider = Provider<TrafficApi>((ref) {
  final api = TrafficApi(
    ref.watch(stateProvider.select((state) => state.token)),
  );
  ref.onDispose(() => api.dio.close(force: true));
  return api;
});

String accountPrefix(SharedPreferences prefs) {
  final id = prefs.getString("active-account-id");
  return id == null ? "" : "account:$id:";
}

class AppState extends ChangeNotifier {
  late final String prefix;
  String key(String value) => "$prefix$value";
  final SharedPreferences prefs;
  String token = '';
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  late bool traffic, onboarded, historyEnabled;
  late ThemeMode theme;
  late List<Place> saved;
  late List<SavedTrip> trips;
  late List<String> history;
  AppState(this.prefs) {
    prefix = accountPrefix(prefs);
    traffic = prefs.getBool(key('traffic')) ?? true;
    onboarded = prefs.getBool(key('onboarded')) ?? false;
    historyEnabled = prefs.getBool(key('historyEnabled')) ?? false;
    theme = ThemeMode.values[(prefs.getInt(key('theme')) ?? 0).clamp(0, 2)];
    try {
      saved = (jsonDecode(prefs.getString(key('saved')) ?? '[]') as List)
          .map((j) => Place.fromJson(j))
          .toList();
    } catch (_) {
      saved = [];
    }
    history = prefs.getStringList(key('history')) ?? [];
    try {
      trips = (jsonDecode(prefs.getString(key('trips')) ?? '[]') as List)
          .map((j) => SavedTrip.fromJson(j))
          .toList();
    } catch (_) {
      trips = [];
    }
  }
  String get defaultVehicle {
    final value = prefs.getString(key('default-vehicle'));
    return value == 'motorcycle' ? 'motorcycle' : 'car';
  }

  Future<void> setDefaultVehicle(String value) async {
    if (value != 'car' && value != 'motorcycle') {
      throw ArgumentError('Invalid vehicle');
    }
    if (!await prefs.setString(key('default-vehicle'), value)) {
      throw StateError('Không lưu được phương tiện');
    }
    if (!disposed) notifyListeners();
  }

  Future<void> loadToken() async {
    token = await TrafficApi.storage.read(key: 'access') ?? '';
    if (!disposed) notifyListeners();
  }

  Future<void> setToken(String value) async {
    await TrafficApi.storage.write(key: 'access', value: value);
    token = value;
    if (!disposed) notifyListeners();
  }

  void completeOnboarding() {
    onboarded = true;
    prefs.setBool(key('onboarded'), true);
    if (!disposed) notifyListeners();
  }

  void setTraffic(bool value) {
    traffic = value;
    prefs.setBool(key('traffic'), value);
    if (!disposed) notifyListeners();
  }

  void setTheme(ThemeMode value) {
    theme = value;
    prefs.setInt(key('theme'), value.index);
    if (!disposed) notifyListeners();
  }

  void setHistory(bool value) {
    historyEnabled = value;
    prefs.setBool(key('historyEnabled'), value);
    if (!value) {
      history.clear();
      prefs.remove(key('history'));
    }
    if (!disposed) notifyListeners();
  }

  void recordSearch(String value) {
    if (!historyEnabled || value.isEmpty) return;
    history.remove(value);
    history.insert(0, value);
    history = history.take(15).toList();
    prefs.setStringList(key('history'), history);
  }

  Future<void> save(Place p) async {
    saved.removeWhere((e) => e.name == p.name);
    saved.add(p);
    await persistPlaces();
  }

  Future<void> remove(Place p) async {
    saved.remove(p);
    await persistPlaces();
  }

  Future<void> persistPlaces() async {
    await prefs.setString(
      key('saved'),
      jsonEncode(saved.map((p) => p.toJson()).toList()),
    );
    if (!disposed) notifyListeners();
  }

  Future<void> saveTrip(SavedTrip trip) async {
    trips.removeWhere((t) => t.name == trip.name);
    trips.add(trip);
    await persistTrips();
  }

  Future<void> removeTrip(SavedTrip trip) async {
    trips.remove(trip);
    await persistTrips();
  }

  Future<void> persistTrips() async {
    await prefs.setString(
      key('trips'),
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
    if (!disposed) notifyListeners();
  }

  Future<void> erase() async {
    saved.clear();
    trips.clear();
    history.clear();
    await prefs.remove(key('saved'));
    await prefs.remove(key('history'));
    await prefs.remove(key('trips'));
    await TrafficApi.storage.delete(key: 'access');
    token = '';
    if (!disposed) notifyListeners();
  }
}

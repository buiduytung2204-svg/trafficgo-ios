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

class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  String token = '';
  late bool traffic, onboarded, historyEnabled;
  late ThemeMode theme;
  late List<Place> saved;
  late List<SavedTrip> trips;
  late List<String> history;
  AppState(this.prefs) {
    traffic = prefs.getBool('traffic') ?? true;
    onboarded = prefs.getBool('onboarded') ?? false;
    historyEnabled = prefs.getBool('historyEnabled') ?? false;
    theme = ThemeMode.values[(prefs.getInt('theme') ?? 0).clamp(0, 2)];
    try {
      saved = (jsonDecode(prefs.getString('saved') ?? '[]') as List)
          .map((j) => Place.fromJson(j))
          .toList();
    } catch (_) {
      saved = [];
    }
    history = prefs.getStringList('history') ?? [];
    try {
      trips = (jsonDecode(prefs.getString('trips') ?? '[]') as List)
          .map((j) => SavedTrip.fromJson(j))
          .toList();
    } catch (_) {
      trips = [];
    }
  }
  Future<void> loadToken() async {
    token = await TrafficApi.storage.read(key: 'access') ?? '';
    notifyListeners();
  }

  Future<void> setToken(String value) async {
    await TrafficApi.storage.write(key: 'access', value: value);
    token = value;
    notifyListeners();
  }

  void completeOnboarding() {
    onboarded = true;
    prefs.setBool('onboarded', true);
    notifyListeners();
  }

  void setTraffic(bool value) {
    traffic = value;
    prefs.setBool('traffic', value);
    notifyListeners();
  }

  void setTheme(ThemeMode value) {
    theme = value;
    prefs.setInt('theme', value.index);
    notifyListeners();
  }

  void setHistory(bool value) {
    historyEnabled = value;
    prefs.setBool('historyEnabled', value);
    if (!value) {
      history.clear();
      prefs.remove('history');
    }
    notifyListeners();
  }

  void recordSearch(String value) {
    if (!historyEnabled || value.isEmpty) return;
    history.remove(value);
    history.insert(0, value);
    history = history.take(15).toList();
    prefs.setStringList('history', history);
  }

  void save(Place p) {
    saved.removeWhere((e) => e.name == p.name);
    saved.add(p);
    persistPlaces();
  }

  void remove(Place p) {
    saved.remove(p);
    persistPlaces();
  }

  void persistPlaces() {
    prefs.setString('saved', jsonEncode(saved.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  void saveTrip(SavedTrip trip) {
    trips.removeWhere((t) => t.name == trip.name);
    trips.add(trip);
    persistTrips();
  }

  void removeTrip(SavedTrip trip) {
    trips.remove(trip);
    persistTrips();
  }

  void persistTrips() {
    prefs.setString('trips', jsonEncode(trips.map((t) => t.toJson()).toList()));
    notifyListeners();
  }

  Future<void> erase() async {
    saved.clear();
    trips.clear();
    history.clear();
    await prefs.remove('saved');
    await prefs.remove('history');
    await prefs.remove('trips');
    await TrafficApi.storage.delete(key: 'access');
    token = '';
    notifyListeners();
  }
}

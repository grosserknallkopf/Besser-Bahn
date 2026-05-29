import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_models.dart';
import '../models/station.dart';

/// Searching a station this many times auto-pins it to the favorites list.
const int kAutoStarThreshold = 3;

/// How many non-pinned recent stations to surface as suggestions.
const int kMaxRecents = 6;

const _kStationsKey = 'lib_stations_v1';
const _kRoutesKey = 'lib_routes_v1';
const _kTrainsKey = 'lib_trains_v1';

class LibraryState {
  final List<FavoriteStation> stations;
  final List<SavedRoute> routes;
  final List<SavedTrain> trains;

  const LibraryState({
    this.stations = const [],
    this.routes = const [],
    this.trains = const [],
  });

  LibraryState copyWith({
    List<FavoriteStation>? stations,
    List<SavedRoute>? routes,
    List<SavedTrain>? trains,
  }) {
    return LibraryState(
      stations: stations ?? this.stations,
      routes: routes ?? this.routes,
      trains: trains ?? this.trains,
    );
  }

  /// Pinned stations, most-used first.
  List<Station> get favorites {
    final pinned = stations.where((s) => s.pinned).toList()
      ..sort((a, b) => b.useCount.compareTo(a.useCount));
    return pinned.map((s) => s.station).toList();
  }

  /// Recently used but not pinned, newest first, capped.
  List<Station> get recents {
    final recent = stations.where((s) => !s.pinned && s.lastUsedMs > 0).toList()
      ..sort((a, b) => b.lastUsedMs.compareTo(a.lastUsedMs));
    return recent.take(kMaxRecents).map((s) => s.station).toList();
  }

  bool isStationFavorite(String id) =>
      stations.any((s) => s.station.id == id && s.pinned);

  bool isRouteSaved(String fromId, String toId) =>
      routes.any((r) => r.from.id == fromId && r.to.id == toId);

  bool hasTrain(String key) => trains.any((t) => t.key == key);
}

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    _load();
    return const LibraryState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    List<T> decode<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return [];
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      } catch (_) {
        return [];
      }
    }

    state = LibraryState(
      stations: decode(_kStationsKey, FavoriteStation.fromJson),
      routes: decode(_kRoutesKey, SavedRoute.fromJson),
      trains: decode(_kTrainsKey, SavedTrain.fromJson),
    );
  }

  Future<void> _saveStations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStationsKey,
        jsonEncode(state.stations.map((s) => s.toJson()).toList()));
  }

  Future<void> _saveRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kRoutesKey, jsonEncode(state.routes.map((r) => r.toJson()).toList()));
  }

  Future<void> _saveTrains() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kTrainsKey, jsonEncode(state.trains.map((t) => t.toJson()).toList()));
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Record that the user selected/searched [station]. Increments its use
  /// count, refreshes recency and auto-pins it once it crosses the threshold.
  void recordStationUse(Station station) {
    if (station.id.isEmpty) return;
    final list = List<FavoriteStation>.from(state.stations);
    final idx = list.indexWhere((s) => s.station.id == station.id);
    if (idx >= 0) {
      final existing = list[idx];
      final newCount = existing.useCount + 1;
      list[idx] = existing.copyWith(
        useCount: newCount,
        lastUsedMs: _nowMs(),
        pinned: existing.pinned || newCount >= kAutoStarThreshold,
      );
    } else {
      list.add(FavoriteStation(
        station: station,
        useCount: 1,
        lastUsedMs: _nowMs(),
        pinned: kAutoStarThreshold <= 1,
      ));
    }
    state = state.copyWith(stations: list);
    _saveStations();
  }

  /// Manually star/unstar a station. Unstarring keeps the entry (so it can
  /// still appear in recents) but clears the pin.
  void toggleStationPin(Station station) {
    if (station.id.isEmpty) return;
    final list = List<FavoriteStation>.from(state.stations);
    final idx = list.indexWhere((s) => s.station.id == station.id);
    if (idx >= 0) {
      list[idx] = list[idx].copyWith(pinned: !list[idx].pinned);
    } else {
      list.add(FavoriteStation(
        station: station,
        useCount: 0,
        lastUsedMs: _nowMs(),
        pinned: true,
      ));
    }
    state = state.copyWith(stations: list);
    _saveStations();
  }

  // ---- Routes ----

  void toggleRoute(Station from, Station to) {
    if (from.id.isEmpty || to.id.isEmpty) return;
    final list = List<SavedRoute>.from(state.routes);
    final idx =
        list.indexWhere((r) => r.from.id == from.id && r.to.id == to.id);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.insert(0, SavedRoute(from: from, to: to));
    }
    state = state.copyWith(routes: list);
    _saveRoutes();
  }

  void removeRoute(String key) {
    state = state.copyWith(
        routes: state.routes.where((r) => r.key != key).toList());
    _saveRoutes();
  }

  // ---- Trains ----

  void toggleTrain(SavedTrain train) {
    final list = List<SavedTrain>.from(state.trains);
    final idx = list.indexWhere((t) => t.key == train.key);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.insert(0, train);
    }
    state = state.copyWith(trains: list);
    _saveTrains();
  }

  void removeTrain(String key) {
    state = state.copyWith(
        trains: state.trains.where((t) => t.key != key).toList());
    _saveTrains();
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

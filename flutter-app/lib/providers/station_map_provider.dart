import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../models/station_map.dart';
import '../services/station_map_service.dart';
import 'service_providers.dart';

/// Normalise a track label to its base id ("6A-C" → "6", "2 A-C" → "2").
String normalizeGleis(String g) {
  g = g.trim();
  if (g.isEmpty) return g;
  if (RegExp(r'^\d').hasMatch(g)) {
    return RegExp(r'^\d+').firstMatch(g)!.group(0)!;
  }
  return g.split(RegExp(r'\s+')).first.toUpperCase();
}

/// Parse the platform-section range from a track label's letter suffix:
/// "7 C-G" → (C,G); "13D-F" → (D,F); "7D" → (D,D); "7"/"" → null.
/// Reversed ranges ("G-C") are normalised to start ≤ end. Sectors are A–I.
({String start, String end})? parseGleisSection(String g) {
  final u = g.toUpperCase();
  final range = RegExp(r'([A-I])\s*-\s*([A-I])').firstMatch(u);
  if (range != null) {
    var a = range.group(1)!, b = range.group(2)!;
    if (a.compareTo(b) > 0) {
      final t = a;
      a = b;
      b = t;
    }
    return (start: a, end: b);
  }
  final single = RegExp(r'^\d+\s*([A-I])$').firstMatch(u.trim());
  if (single != null) return (start: single.group(1)!, end: single.group(1)!);
  return null;
}

class StationMapState {
  final Station? station;
  final StationMap? map;
  final String? selectedLevel;

  /// Categories the user has toggled off in the legend.
  final Set<String> hiddenCategories;

  /// When arriving from a journey: the Gleis to board at, highlighted on the
  /// map (normalised, e.g. "6"). Null for a plain station lookup.
  final String? highlightGleis;

  /// The platform-section range to board at, parsed from the arrival/boarding
  /// track label (e.g. "7 C-G" → (C,G)). Null when the label has no section.
  final ({String start, String end})? highlightSection;

  final bool isLoading;
  final String? error;

  const StationMapState({
    this.station,
    this.map,
    this.selectedLevel,
    this.hiddenCategories = const {},
    this.highlightGleis,
    this.highlightSection,
    this.isLoading = false,
    this.error,
  });

  StationMapState copyWith({
    Station? station,
    StationMap? map,
    String? selectedLevel,
    Set<String>? hiddenCategories,
    String? highlightGleis,
    ({String start, String end})? highlightSection,
    bool clearHighlight = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return StationMapState(
      station: station ?? this.station,
      map: map ?? this.map,
      selectedLevel: selectedLevel ?? this.selectedLevel,
      hiddenCategories: hiddenCategories ?? this.hiddenCategories,
      highlightGleis:
          clearHighlight ? null : (highlightGleis ?? this.highlightGleis),
      highlightSection:
          clearHighlight ? null : (highlightSection ?? this.highlightSection),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// The POI for the highlighted boarding Gleis, if present on the current map.
  MapPoi? get highlightPoi {
    final g = highlightGleis;
    final m = map;
    if (g == null || m == null) return null;
    for (final p in m.platforms) {
      if (normalizeGleis(p.name) == g) return p;
    }
    return null;
  }

  /// The real sector cubes (A–I) of the boarding section range, in letter
  /// order, picked to lie on the boarding Gleis — so the map draws a line and
  /// labelled markers exactly where the rider should stand.
  ///
  /// The source `PLATFORM_SECTOR_CUBE` POIs carry NO platform reference, are
  /// sparse, and the platforms FAN OUT (curve apart toward the far end), so a
  /// straight-line model or nearest-centroid assignment both miss. But each
  /// cube sits at a real on-platform position, so for every requested letter we
  /// just take the actual cube of that letter NEAREST the boarding Gleis's
  /// marker. Low letters resolve to the cube on this track's side; the high
  /// letters (often a single shared cube far up the curve) resolve to that real
  /// point. Universal, uses only real data, no per-station table.
  List<({String letter, LatLng pos})> get highlightSectionLine {
    final m = map;
    final plat = highlightPoi;
    final range = highlightSection;
    if (m == null || plat == null || range == null) return const [];

    final level = plat.level ?? '';
    final cubes =
        m.poisOnLevel(level).where((p) => p.isPlatformSector).toList();
    if (cubes.isEmpty) return const [];

    int? letterIdx(String n) {
      final t = n.trim().toUpperCase();
      if (t.length != 1) return null;
      final code = t.codeUnitAt(0);
      return (code >= 65 && code <= 73) ? code - 65 : null; // A..I
    }

    final start = letterIdx(range.start);
    final end = letterIdx(range.end);
    if (start == null || end == null) return const [];

    const dist = Distance();
    final out = <({String letter, LatLng pos})>[];
    for (var i = start; i <= end; i++) {
      final letter = String.fromCharCode(65 + i);
      MapPoi? best;
      var bestD = double.infinity;
      for (final c in cubes) {
        if (letterIdx(c.name) != i) continue;
        final d = dist(c.latLng, plat.latLng);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      if (best != null) out.add((letter: letter, pos: best.latLng));
    }
    return out;
  }

  /// POIs to render: current floor, minus hidden categories.
  List<MapPoi> get visiblePois {
    final m = map;
    if (m == null || selectedLevel == null) return const [];
    return m
        .poisOnLevel(selectedLevel!)
        .where((p) => !hiddenCategories.contains(p.type))
        .toList();
  }
}

class StationMapNotifier extends Notifier<StationMapState> {
  StationMapService get _service => ref.read(stationMapServiceProvider);

  @override
  StationMapState build() => const StationMapState();

  /// Load the map for a station. Pass [highlightGleis] when coming from a
  /// journey so the boarding track is highlighted and its floor pre-selected.
  Future<void> loadForStation(Station station, {String? highlightGleis}) async {
    final raw = highlightGleis?.trim() ?? '';
    final hl = raw.isNotEmpty ? normalizeGleis(raw) : null;
    final section = raw.isNotEmpty ? parseGleisSection(raw) : null;
    state = state.copyWith(
      station: station,
      highlightGleis: hl,
      highlightSection: section,
      clearHighlight: hl == null,
    );
    await _load(() => _service.fetchByStationName(station.name));
  }

  Future<void> loadBySlug(String slug) async {
    state = state.copyWith(clearHighlight: true);
    await _load(() => _service.fetchBySlug(slug));
  }

  Future<void> _load(Future<StationMap> Function() fetch) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final map = await fetch();
      state = state.copyWith(
        map: map,
        selectedLevel: _levelForLoad(map),
        hiddenCategories: const {},
        isLoading: false,
      );
    } on StationMapException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Karte konnte nicht geladen werden.',
      );
    }
  }

  void selectLevel(String level) =>
      state = state.copyWith(selectedLevel: level);

  void toggleCategory(String category) {
    final next = Set<String>.from(state.hiddenCategories);
    next.contains(category) ? next.remove(category) : next.add(category);
    state = state.copyWith(hiddenCategories: next);
  }

  /// Floor to show on load: the one carrying the highlighted boarding Gleis
  /// if we have one, otherwise the floor with the most platforms.
  String _levelForLoad(StationMap map) {
    final g = state.highlightGleis;
    if (g != null) {
      for (final p in map.platforms) {
        if (normalizeGleis(p.name) == g && (p.level?.isNotEmpty ?? false)) {
          return p.level!;
        }
      }
    }
    return _defaultLevel(map);
  }

  /// Default to the floor that actually has the most platforms (Gleise),
  /// so the user lands on the tracks instead of an empty concourse.
  String _defaultLevel(StationMap map) {
    String? best;
    var bestCount = -1;
    for (final lvl in map.levels) {
      final count = map.poisOnLevel(lvl).where((p) => p.isPlatform).length;
      if (count > bestCount) {
        bestCount = count;
        best = lvl;
      }
    }
    if (bestCount <= 0) {
      best = map.levelInit.isNotEmpty
          ? map.levelInit
          : (map.levels.isNotEmpty ? map.levels.first : null);
    }
    return best ?? '';
  }
}

final stationMapProvider =
    NotifierProvider<StationMapNotifier, StationMapState>(
        StationMapNotifier.new);

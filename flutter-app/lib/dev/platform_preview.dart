// Standalone DEV-ONLY preview to iterate on ONE thing: drawing a to-scale,
// top-down train body that stands on a station platform's real track curve.
//
//   flutter run -d linux -t lib/dev/platform_preview.dart
//
// It shows EXACTLY ONE map of Hamburg Hbf's platform area. The placement is
// driven PURELY by OpenStreetMap: the selected Gleis's OSM platform AREA gives
// the exact track-side curve (verified to match satellite), and the train body
// rides that green line. The only thing OSM lacks is the sector LETTERS A–I and
// their order — those come from the bahnhof.de cube chain and are PROJECTED onto
// the OSM line (the yellow markers). A Gleis selector picks the track; the base-
// map dropdown and the OSM / DB-overlay toggles are for comparing backgrounds.
// Everything runs OFFLINE from fixtures (test/fixtures/hamburg-hbf.rsc.txt +
// hamburg-osm.json). On Linux the basemap tiles fall back to network and may be
// blank; overlays render anyway.
//
// NOT wired into the app — pure prototype. Production screens are untouched.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/platform_train.dart';
import '../core/train_geometry.dart';
import '../models/station_map.dart';
import '../services/station_map_service.dart';
import '../theme/app_colors.dart';

void main() {
  runApp(const _PreviewApp());
}

String _readFixture(String name) {
  for (final base in [
    'test/fixtures',
    'flutter-app/test/fixtures',
    '${Directory.current.path}/test/fixtures',
  ]) {
    final f = File('$base/$name');
    if (f.existsSync()) return f.readAsStringSync();
  }
  throw StateError('fixture $name not found (cwd=${Directory.current.path})');
}

double _dist(math.Point<double> a, math.Point<double> b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// PEEL the floor's sector cubes into one chain per platform island. Each
/// island's cubes form a smooth, evenly-spaced curve; cubes carry no track id
/// and several islands interleave, so we extract them greedily:
///   * seed at the highest-letter cube still unused (the long platform 7/8 has
///     the only G/H/I, so it peels first);
///   * walk DOWN the letters with MOMENTUM — predict the next position by
///     constant-velocity extrapolation (cur + (cur−prev)) and take the nearest
///     candidate. Momentum follows the platform's own curve and ignores cubes
///     that veer off onto a neighbouring track (the D8-vs-D10 trap);
///   * remove that chain, repeat. Verified on the Hamburg fixture: reproduces
///     the human-confirmed Gleis-7 chain I3 H4 G2 F22 E1 D10 C20 B12 A13 and
///     three more clean island chains.
List<List<MapPoi>> _peelChains(List<MapPoi> all, math.Point<double> Function(MapPoi) px) {
  final remaining = all.toList();
  final chains = <List<MapPoi>>[];
  while (remaining.length >= 3) {
    final byLetter = <int, List<MapPoi>>{};
    for (final c in remaining) {
      final li = letterIdx(c.name);
      if (li != null) byLetter.putIfAbsent(li, () => []).add(c);
    }
    final letters = byLetter.keys.toList()..sort();
    if (letters.isEmpty) break;
    final chosen = <MapPoi>[byLetter[letters.last]!.first];
    math.Point<double>? prev;
    var cur = px(chosen.first);
    for (var k = letters.length - 2; k >= 0; k--) {
      final cands = byLetter[letters[k]]!;
      final pred = prev == null
          ? cur
          : math.Point(cur.x + (cur.x - prev.x), cur.y + (cur.y - prev.y));
      cands.sort((a, b) => _dist(px(a), pred).compareTo(_dist(px(b), pred)));
      chosen.add(cands.first);
      prev = cur;
      cur = px(cands.first);
    }
    chains.add(chosen);
    remaining.removeWhere(chosen.contains);
  }
  return chains;
}

/// The platform-island chain serving [gleis] — the peeled chain whose cubes lie
/// nearest that Gleis's POI — returned in letter order (A→I). Used ONLY to read
/// the sector LETTERS + their positions (which we project onto the OSM line) and
/// to disambiguate which long edge of the OSM platform is this Gleis's side; the
/// chain itself is never drawn as the train's curve. [robust]=false returns the
/// raw resolver output.
List<({String letter, LatLng pos})> _cubeSpineLetters(
    StationMap map, String gleis,
    {required bool robust}) {
  if (!robust) return platformSectors(map, gleis);

  final plat = map.platforms.firstWhere((p) => normalizeGleis(p.name) == gleis,
      orElse: () => map.platforms.first);
  final level = plat.level ?? map.levelInit;
  final all = map.poisOnLevel(level).where((p) => p.isPlatformSector).toList();
  if (all.length < 3) return platformSectors(map, gleis);
  final mlon = 111320.0 * math.cos(all.first.latitude * math.pi / 180);
  math.Point<double> px(MapPoi c) =>
      math.Point(c.longitude * mlon, c.latitude * 111320.0);

  final chains = _peelChains(all, px);
  if (chains.isEmpty) return platformSectors(map, gleis);
  // Assign a chain to this Gleis via the lift/escalator ANCHORS that name it
  // ("Gleis 7/8 …") — they sit ON the platform, unlike the Gleis POIs which are
  // all clustered at the concourse and can't tell the islands apart.
  final targets = <math.Point<double>>[];
  for (final a in map.platformAnchors) {
    if (a.gleise.contains(gleis)) {
      targets.add(math.Point(a.longitude * mlon, a.latitude * 111320.0));
    }
  }
  if (targets.isEmpty) targets.add(px(plat));
  List<MapPoi> best = chains.first;
  var bestD = double.infinity;
  for (final ch in chains) {
    var d = double.infinity;
    for (final c in ch) {
      for (final t in targets) {
        d = math.min(d, _dist(px(c), t));
      }
    }
    if (d < bestD) {
      bestD = d;
      best = ch;
    }
  }
  // MATCH: the robust chain gives the right cubes/curve; apply the SAME lateral
  // nudge `platformSectors` (the "roh" mode) uses — which the human confirmed
  // sits at the correct distance, on the track — so we get the best of both.
  final island = resolveIsland(map, plat, gleis, 0, 8);
  final sorted = best.toList()
    ..sort((a, b) => (letterIdx(a.name) ?? 0).compareTo(letterIdx(b.name) ?? 0));
  return [
    for (final c in sorted)
      (
        letter: c.name,
        pos: LatLng(
            c.latitude + island.dLat, c.longitude + island.dLon),
      ),
  ];
}

/// Selectable background tile models, to compare how well each renders the
/// tracks under our overlays.
typedef _BaseMap = ({String name, String url, List<String> subs, int maxZoom});
const List<_BaseMap> _baseMaps = [
  (name: 'OSM', url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', subs: [], maxZoom: 19),
  (name: 'CARTO hell', url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png', subs: ['a', 'b', 'c', 'd'], maxZoom: 20),
  (name: 'CARTO dunkel', url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', subs: ['a', 'b', 'c', 'd'], maxZoom: 20),
  (name: 'CARTO hell ohne Text', url: 'https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}.png', subs: ['a', 'b', 'c', 'd'], maxZoom: 20),
  (name: 'CARTO Voyager ohne Text', url: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png', subs: ['a', 'b', 'c', 'd'], maxZoom: 20),
  (name: 'Satellit (Esri)', url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', subs: [], maxZoom: 19),
  (name: 'OpenRailwayMap', url: 'https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png', subs: ['a', 'b', 'c'], maxZoom: 19),
  (name: 'OpenTopoMap', url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', subs: ['a', 'b', 'c'], maxZoom: 17),
];

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platform train preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: AppColors.secondClass),
      home: const _PreviewPage(),
    );
  }
}

class _PreviewPage extends StatefulWidget {
  const _PreviewPage();
  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}


class _PreviewPageState extends State<_PreviewPage> {
  late final StationMap _map;
  late final List<String> _gleise;
  Object? _loadError;

  String _gleis = '7';

  /// The DB bahnhof.de indoor station plan (overlay tiles). Default OFF — it's
  /// distorted; we use OSM instead. Toggle on only to compare.
  bool _showOverlay = false;

  /// Toggle the OSM comparison: the OSM platform area + its centreline + the
  /// OSM rails — OSM knows the Gleise (platform ref "7;8") and the real tracks.
  bool _showOsm = true;

  /// Selected background tile model.
  _BaseMap _baseMap = _baseMaps.first;

  /// OSM platform areas (ref → polygon) and rail ways, from the saved fixture.
  List<({String ref, List<LatLng> pts})> _osmPlatforms = const [];
  List<List<LatLng>> _osmRails = const [];

  /// Diagnostic string from the last [_railFromEdge] call, shown in the banner.
  String _railDiag = '';

  @override
  void initState() {
    super.initState();
    try {
      final rsc = _readFixture('hamburg-hbf.rsc.txt');
      // ignore: invalid_use_of_visible_for_testing_member — dev preview only.
      _map = parseStationMapBody('hamburg-hbf', rsc);
      _gleise =(_map.platforms.map((p) => normalizeGleis(p.name)).toSet().toList()
        ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0)));
      if (!_gleise.contains(_gleis) && _gleise.isNotEmpty) _gleis = _gleise.first;
      _loadOsm();
    } catch (e) {
      _loadError = e;
    }
  }

  void _loadOsm() {
    try {
      final osm = json.decode(_readFixture('hamburg-osm.json')) as Map;
      _osmPlatforms = [
        for (final p in (osm['platforms'] as List))
          (
            ref: p['ref'] as String,
            pts: [
              for (final q in (p['pts'] as List))
                LatLng((q['lat'] as num).toDouble(), (q['lng'] as num).toDouble())
            ],
          ),
      ];
      _osmRails = [
        for (final r in (osm['rails'] as List))
          [
            for (final q in (r['pts'] as List))
              LatLng((q['lat'] as num).toDouble(), (q['lng'] as num).toDouble())
          ],
      ];
    } catch (_) {/* optional */}
  }

  /// Resample [path] to [n] points evenly spaced by arc-length.
  List<LatLng> _resample(List<LatLng> path, int n) {
    if (path.length < 2) return path;
    final mlon = 111320.0 * math.cos(path.first.latitude * math.pi / 180);
    double dist(LatLng a, LatLng b) {
      final dx = (a.longitude - b.longitude) * mlon;
      final dy = (a.latitude - b.latitude) * 111320.0;
      return math.sqrt(dx * dx + dy * dy);
    }

    final cum = <double>[0];
    for (var i = 0; i < path.length - 1; i++) {
      cum.add(cum.last + dist(path[i], path[i + 1]));
    }
    final total = cum.last;
    if (total <= 0) return [path.first, path.last];
    final out = <LatLng>[];
    for (var k = 0; k < n; k++) {
      final d = total * k / (n - 1);
      var i = 0;
      while (i < cum.length - 2 && cum[i + 1] < d) {
        i++;
      }
      final seg = cum[i + 1] - cum[i];
      final f = seg > 0 ? (d - cum[i]) / seg : 0.0;
      out.add(LatLng(
        path[i].latitude + (path[i + 1].latitude - path[i].latitude) * f,
        path[i].longitude + (path[i + 1].longitude - path[i].longitude) * f,
      ));
    }
    return out;
  }

  /// The TRACK line for a Gleis from an OSM platform AREA. A platform is a long
  /// thin LOOP with one long edge against each track (7 on one side, 8 on the
  /// other). We split the loop at its two extreme ends into the two long edges,
  /// resample each by arc-length, and return the edge nearer [ref] (the trusted
  /// cube chain on this Gleis's side) — i.e. the track-7 vs track-8 side. With
  /// no ref we fall back to the medial centreline.
  List<LatLng> _osmTrackLine(List<LatLng> poly, List<LatLng> ref) {
    final loop = poly.toList();
    if (loop.length > 1 &&
        loop.first.latitude == loop.last.latitude &&
        loop.first.longitude == loop.last.longitude) {
      loop.removeLast();
    }
    if (loop.length < 4) return poly;
    final mlon = 111320.0 * math.cos(loop.first.latitude * math.pi / 180);
    math.Point<double> xy(LatLng p) =>
        math.Point(p.longitude * mlon, p.latitude * 111320.0);
    final axis = fitLine([for (final p in loop) xy(p)]);
    if (axis == null) return poly;
    final ts = [
      for (final p in loop)
        (xy(p).x - axis.cx) * axis.dx + (xy(p).y - axis.cy) * axis.dy
    ];
    var iMin = 0, iMax = 0;
    for (var i = 1; i < ts.length; i++) {
      if (ts[i] < ts[iMin]) iMin = i;
      if (ts[i] > ts[iMax]) iMax = i;
    }
    List<LatLng> arc(int a, int b) {
      final out = <LatLng>[];
      var i = a;
      while (true) {
        out.add(loop[i]);
        if (i == b) break;
        i = (i + 1) % loop.length;
      }
      return out;
    }

    const n = 28;
    final e1 = _resample(arc(iMin, iMax), n); // one long edge, iMin→iMax
    final e2 = _resample(arc(iMax, iMin), n).reversed.toList(); // other, aligned
    if (ref.length < 2) {
      return [
        for (var k = 0; k < n; k++)
          LatLng((e1[k].latitude + e2[k].latitude) / 2,
              (e1[k].longitude + e2[k].longitude) / 2),
      ];
    }
    final m2 = 111320.0 * math.cos(e1.first.latitude * math.pi / 180);
    double d(LatLng a, LatLng b) {
      final dx = (a.longitude - b.longitude) * m2, dy = (a.latitude - b.latitude) * 111320.0;
      return math.sqrt(dx * dx + dy * dy);
    }

    double avg(List<LatLng> e) {
      var s = 0.0;
      for (final p in e) {
        var mn = double.infinity;
        for (final r in ref) {
          mn = math.min(mn, d(p, r));
        }
        s += mn;
      }
      return s / e.length;
    }

    return avg(e1) <= avg(e2) ? e1 : e2; // the edge on this Gleis's track side
  }

  /// The actual rail the train rides. The platform track-side [edge] is the
  /// platform LIP; the rail for this Gleis runs ~1–3 m off it, mapped in OSM as
  /// several short `railway=rail` fragments (a long station-throat way is split
  /// at every switch). So instead of picking one whole way, gather EVERY rail
  /// vertex within [tol] m of [edge] (that captures this Gleis's rail and skips
  /// the neighbour track ~8 m away on the platform's other lip), order them by
  /// arc-position ALONG the edge (merging the fragments into one monotone line),
  /// and resample → a clean rail centre-line. Falls back to [edge] if too few.
  List<LatLng> _railFromEdge(List<LatLng> edge, List<List<LatLng>> rails,
      {double tol = 4.0}) {
    if (edge.length < 2 || rails.isEmpty) {
      _railDiag = 'KANTE (keine Rails)';
      return edge;
    }
    final mlon = 111320.0 * math.cos(edge.first.latitude * math.pi / 180);
    math.Point<double> xy(LatLng p) =>
        math.Point(p.longitude * mlon, p.latitude * 111320.0);

    // Perpendicular distance from [p] to the edge polyline + arc-length of the
    // foot along the edge (so we can order picked rail points along the track).
    ({double dist, double s}) nearestOnEdge(math.Point<double> p) {
      var best = double.infinity, bestS = 0.0, acc = 0.0;
      for (var i = 0; i < edge.length - 1; i++) {
        final a = xy(edge[i]), b = xy(edge[i + 1]);
        final ab = b - a;
        final len2 = ab.x * ab.x + ab.y * ab.y;
        final t = len2 > 0
            ? (((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2).clamp(0.0, 1.0)
            : 0.0;
        final proj = math.Point(a.x + ab.x * t, a.y + ab.y * t);
        final d = (p - proj).magnitude;
        if (d < best) {
          best = d;
          bestS = acc + math.sqrt(len2) * t;
        }
        acc += math.sqrt(len2);
      }
      return (dist: best, s: bestS);
    }

    final picked = <({double s, LatLng p})>[];
    for (final r in rails) {
      for (final q in r) {
        final n = nearestOnEdge(xy(q));
        if (n.dist <= tol) picked.add((s: n.s, p: q));
      }
    }
    if (picked.length < 4) {
      _railDiag = 'KANTE (nur ${picked.length} Rail-Pkt ≤${tol.toStringAsFixed(0)}m)';
      return edge;
    }
    picked.sort((a, b) => a.s.compareTo(b.s));
    final spine = _resample([for (final e in picked) e.p], 40);
    _railDiag = 'SCHIENE ✓ (${picked.length} Pkt ≤${tol.toStringAsFixed(0)}m → 40)';
    // Orient to match the edge so nose start/end land on the right ends.
    double d(LatLng a, LatLng b) => (xy(a) - xy(b)).magnitude;
    return d(spine.first, edge.first) <= d(spine.last, edge.first)
        ? spine
        : spine.reversed.toList();
  }

  /// Nearest point on polyline [line] to [p] — used to place each sector letter
  /// (from the DB cube chain) onto the exact OSM track line.
  LatLng _projectOnto(LatLng p, List<LatLng> line) {
    if (line.length < 2) return p;
    final mlon = 111320.0 * math.cos(p.latitude * math.pi / 180);
    math.Point<double> xy(LatLng q) =>
        math.Point(q.longitude * mlon, q.latitude * 111320.0);
    final pp = xy(p);
    var best = p;
    var bestD = double.infinity;
    for (var i = 0; i < line.length - 1; i++) {
      final a = xy(line[i]), b = xy(line[i + 1]);
      final ab = b - a;
      final len2 = ab.x * ab.x + ab.y * ab.y;
      final t = len2 > 0
          ? (((pp.x - a.x) * ab.x + (pp.y - a.y) * ab.y) / len2).clamp(0.0, 1.0)
          : 0.0;
      final proj = math.Point(a.x + ab.x * t, a.y + ab.y * t);
      final d = (pp - proj).magnitude;
      if (d < bestD) {
        bestD = d;
        best = LatLng(proj.y / 111320.0, proj.x / mlon);
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        body: Center(child: Text('Failed to load fixtures:\n$_loadError')),
      );
    }

    const hw = 2.95 / 2;
    const nose = 5.0;

    // The Gleis's cube chain — used ONLY as the SIDE reference (which long edge
    // of the OSM platform is track 7 vs 8) and as the source of the sector
    // letters A–I; it is never drawn as the train's curve.
    final usedLetters = _cubeSpineLetters(_map, _gleis, robust: true);
    final cubeSide = [for (final c in usedLetters) c.pos];

    // OSM: the platform area whose ref contains this Gleis (7 ∈ 7;8), reduced to
    // the track-side edge — verified to sit exactly on the rail. The TRAIN rides
    // THIS line; the cube chain only disambiguates which side is Gleis 7.
    final osmPlat =
        _osmPlatforms.where((p) => p.ref.split(';').contains(_gleis)).toList();
    final osmEdge = osmPlat.isNotEmpty
        ? _osmTrackLine(osmPlat.first.pts, cubeSide)
        : const <LatLng>[];
    // The platform edge is the lip; the train must ride the rail ~1–3 m off it.
    // Gather this Gleis's rail vertices along the edge → real rail centre-line.
    final osmCenter =
        osmEdge.length >= 2 ? _railFromEdge(osmEdge, _osmRails) : osmEdge;

    // SECTORS on the line: the DB cube letters (correct A→I sequence from the
    // peeled chain) projected onto the exact OSM track line — "wo Abschnitt A,
    // B, C … liegt". This is the part OSM can't give; we take only the sector
    // letters from DB and pin them onto OSM's accurate rail. The TRAIN body
    // always sits on osmCenter; no OSM platform → no train (no cube fallback).
    final sectorMarks = osmCenter.length >= 2
        ? [
            for (final c in usedLetters)
              (letter: c.letter, pos: _projectOnto(c.pos, osmCenter))
          ]
        : const <({String letter, LatLng pos})>[];
    final body = osmCenter.length >= 2
        ? TrainGeometry.body(osmCenter,
            halfWidthM: hw, noseStart: true, noseEnd: true, noseLenM: nose)
        : const <LatLng>[];

    // Floor id whose indoor plan to show — the selected Gleis's level.
    final level = _map.platforms
            .firstWhere((p) => normalizeGleis(p.name) == _gleis,
                orElse: () => _map.platforms.first)
            .level ??
        (_map.levelInit.isNotEmpty
            ? _map.levelInit
            : (_map.levels.isNotEmpty ? _map.levels.first : 'GROUND_FLOOR'));

    // EVERY sector cube + EVERY Gleis label on this floor (like the DB plan),
    // regardless of the selected Gleis.
    final levelPois = _map.poisOnLevel(level);
    final allGleise = levelPois.where((p) => p.isPlatform).toList();

    final label = 'Gleis $_gleis · Kante ${osmEdge.length} Pkt · '
        'Zug: ${_railDiag.isEmpty ? "—" : _railDiag} · '
        'Sektoren ${sectorMarks.length}';

    final center = osmCenter.length >= 2
        ? osmCenter[osmCenter.length ~/ 2]
        : (usedLetters.isNotEmpty
            ? usedLetters[usedLetters.length ~/ 2].pos
            : _map.center);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hamburg Hbf — platform train preview'),
        backgroundColor: AppColors.secondClass,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _controls(),
          Container(
            width: double.infinity,
            color: AppColors.secondClass,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 18,
                minZoom: 14,
                maxZoom: 20,
              ),
              children: [
                // BASE map (selectable model) UNDER everything — for comparing.
                TileLayer(
                  key: ValueKey(_baseMap.name),
                  urlTemplate: _baseMap.url,
                  subdomains: _baseMap.subs,
                  maxNativeZoom: _baseMap.maxZoom,
                  maxZoom: 20,
                  userAgentPackageName: 'dev.chuk.besserbahn.preview',
                  errorTileCallback: (_, _, _) {},
                ),
                // The bahnhof.de indoor floor plan (DB station overlay) — the
                // thing the "Overlay" toggle shows/hides, to compare it against
                // the bare base map. Needs the Referer header or the tiles 403.
                if (_showOverlay)
                  TileLayer(
                    urlTemplate: StationMap.indoorTileUrl(level),
                    tileDimension: 256,
                    minNativeZoom: 14,
                    maxNativeZoom: 18,
                    maxZoom: 20,
                    tileProvider: NetworkTileProvider(
                      headers: {'Referer': 'https://www.bahnhof.de/'},
                    ),
                    userAgentPackageName: 'dev.chuk.besserbahn.preview',
                    errorTileCallback: (_, _, _) {},
                  ),
                // OSM rails (faint) — the real track network.
                if (_showOsm)
                  PolylineLayer(polylines: [
                    for (final r in _osmRails)
                      Polyline(
                          points: r,
                          strokeWidth: 1,
                          color: Colors.lightBlue.withValues(alpha: 0.45)),
                  ]),
                // The train body — built on the OSM rail centre-line (osmCenter).
                if (body.length >= 3)
                  PolygonLayer(polygons: [
                    Polygon(
                      points: body,
                      color: AppColors.secondClass.withValues(alpha: 0.5),
                      borderColor: Colors.black87,
                      borderStrokeWidth: 1.5,
                    ),
                  ]),
                // SECTORS on the OSM line: the DB sector letters (A→I), pinned
                // onto the exact rail — where each Abschnitt actually is.
                MarkerLayer(markers: [
                  for (final s in sectorMarks)
                    Marker(
                      point: s.pos,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black87, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(s.letter,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                ]),
                // EVERY Gleis number on this floor (DB-style chip).
                MarkerLayer(markers: [
                  for (final p in allGleise)
                    Marker(
                      point: p.latLng,
                      width: 54,
                      height: 18,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.dbRed,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: Text('Gleis ${p.name}',
                              overflow: TextOverflow.clip,
                              maxLines: 1,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Gleis: '),
            DropdownButton<String>(
              value: _gleis,
              items: [
                for (final g in _gleise)
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => setState(() => _gleis = v ?? _gleis),
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('DB-Bahnsteigplan '),
            Switch(
              value: _showOverlay,
              onChanged: (v) => setState(() => _showOverlay = v),
            ),
            const SizedBox(width: 12),
            const Text('OSM '),
            Switch(
              value: _showOsm,
              onChanged: (v) => setState(() => _showOsm = v),
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Karte: '),
            DropdownButton<_BaseMap>(
              value: _baseMap,
              items: [
                for (final b in _baseMaps)
                  DropdownMenuItem(value: b, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _baseMap = v ?? _baseMap),
            ),
          ]),
          const Text('━ grün = OSM Gleis-Seite (Zug-Linie)   ━ hellblau = OSM-Gleise   ● gelb = Sektor A–I',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }
}

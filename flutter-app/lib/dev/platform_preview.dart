// Standalone DEV-ONLY preview, reduced to ONE job: draw the to-scale train that
// stands at Hamburg Hbf **Gleis 7**, sitting exactly on the OSM rail, spanning
// its sectors I→A.
//
//   flutter run -d linux -t lib/dev/platform_preview.dart
//
// Placement is PURELY OpenStreetMap:
//   1. OSM platform area "7;8" → the track-side long edge for Gleis 7.
//   2. Gather the OSM rail vertices that hug that edge → the real rail curve.
//   3. Clip that curve to the sector span (A…I), so the train is exactly as long
//      as the platform and the rail's bend into the throat (past A) is excluded —
//      that bend was the only thing that ever kinked.
// The sector LETTERS A–I (which OSM lacks) come from the bahnhof.de cube chain
// and are projected onto the rail (the yellow markers); the cubes also tell which
// of the platform's two long edges is Gleis 7's side.
//
// Everything is OFFLINE from fixtures (test/fixtures/hamburg-hbf.rsc.txt +
// hamburg-osm.json). NOT wired into the app — pure prototype.
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

const _gleis = '7';

void main() => runApp(const _PreviewApp());

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

/// PEEL the floor's sector cubes into one chain per platform island, then return
/// Gleis 7's chain as (letter, position) in A→I order. Cubes carry the sector
/// LETTERS but no track id and several islands interleave, so we extract greedily
/// from the highest letter down with constant-velocity momentum (follows the
/// island's own curve, ignores cubes veering onto a neighbour track), then pick
/// the chain nearest Gleis 7's lift/escalator anchors. Used ONLY for the letters
/// + which platform edge is Gleis 7's side — never as the train's curve.
List<({String letter, LatLng pos})> _cubeLetters(StationMap map) {
  final plat = map.platforms.firstWhere(
      (p) => normalizeGleis(p.name) == _gleis,
      orElse: () => map.platforms.first);
  final level = plat.level ?? map.levelInit;
  final all = map.poisOnLevel(level).where((p) => p.isPlatformSector).toList();
  if (all.length < 3) return platformSectors(map, _gleis);
  final mlon = 111320.0 * math.cos(all.first.latitude * math.pi / 180);
  math.Point<double> px(MapPoi c) =>
      math.Point(c.longitude * mlon, c.latitude * 111320.0);

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
  if (chains.isEmpty) return platformSectors(map, _gleis);

  final targets = <math.Point<double>>[];
  for (final a in map.platformAnchors) {
    if (a.gleise.contains(_gleis)) {
      targets.add(math.Point(a.longitude * mlon, a.latitude * 111320.0));
    }
  }
  if (targets.isEmpty) targets.add(px(plat));
  var best = chains.first;
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
  final island = resolveIsland(map, plat, _gleis, 0, 8);
  final sorted = best.toList()
    ..sort((a, b) => (letterIdx(a.name) ?? 0).compareTo(letterIdx(b.name) ?? 0));
  return [
    for (final c in sorted)
      (letter: c.name, pos: LatLng(c.latitude + island.dLat, c.longitude + island.dLon)),
  ];
}

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
  Object? _loadError;
  List<({String ref, List<LatLng> pts})> _osmPlatforms = const [];
  List<List<LatLng>> _osmRails = const [];

  @override
  void initState() {
    super.initState();
    try {
      // ignore: invalid_use_of_visible_for_testing_member — dev preview only.
      _map = parseStationMapBody('hamburg-hbf', _readFixture('hamburg-hbf.rsc.txt'));
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
    } catch (e) {
      _loadError = e;
    }
  }

  /// Resample [path] to [n] points evenly spaced by arc-length.
  List<LatLng> _resample(List<LatLng> path, int n) {
    if (path.length < 2) return path;
    final mlon = 111320.0 * math.cos(path.first.latitude * math.pi / 180);
    double d(LatLng a, LatLng b) {
      final dx = (a.longitude - b.longitude) * mlon;
      final dy = (a.latitude - b.latitude) * 111320.0;
      return math.sqrt(dx * dx + dy * dy);
    }

    final cum = <double>[0];
    for (var i = 0; i < path.length - 1; i++) {
      cum.add(cum.last + d(path[i], path[i + 1]));
    }
    final total = cum.last;
    if (total <= 0) return [path.first, path.last];
    final out = <LatLng>[];
    for (var k = 0; k < n; k++) {
      final dd = total * k / (n - 1);
      var i = 0;
      while (i < cum.length - 2 && cum[i + 1] < dd) {
        i++;
      }
      final seg = cum[i + 1] - cum[i];
      final f = seg > 0 ? (dd - cum[i]) / seg : 0.0;
      out.add(LatLng(
        path[i].latitude + (path[i + 1].latitude - path[i].latitude) * f,
        path[i].longitude + (path[i + 1].longitude - path[i].longitude) * f,
      ));
    }
    return out;
  }

  /// The Gleis-7 long edge of the OSM platform AREA. A platform is a long thin
  /// loop with one long edge against each track (7 vs 8). Split the loop at its
  /// two extreme ends into the two long edges and return the one nearer [ref]
  /// (the trusted cube chain on Gleis 7's side).
  List<LatLng> _trackSideEdge(List<LatLng> poly, List<LatLng> ref) {
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

    const n = 40;
    final e1 = _resample(arc(iMin, iMax), n);
    final e2 = _resample(arc(iMax, iMin), n).reversed.toList();
    if (ref.length < 2) {
      return [
        for (var k = 0; k < n; k++)
          LatLng((e1[k].latitude + e2[k].latitude) / 2,
              (e1[k].longitude + e2[k].longitude) / 2),
      ];
    }
    final m2 = 111320.0 * math.cos(e1.first.latitude * math.pi / 180);
    double d(LatLng a, LatLng b) {
      final dx = (a.longitude - b.longitude) * m2,
          dy = (a.latitude - b.latitude) * 111320.0;
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

    return avg(e1) <= avg(e2) ? e1 : e2;
  }

  /// The Gleis-7 rail centre-line. The platform [edge] is the LIP; the rail runs
  /// ~1–3 m off it, mapped as several short fragments. Gather every OSM rail
  /// vertex within 4 m of [edge] (captures this rail, skips the neighbour ~8 m
  /// away on the other lip), order them by arc-position along [edge], resample.
  List<LatLng> _railFromEdge(List<LatLng> edge) {
    if (edge.length < 2 || _osmRails.isEmpty) return edge;
    final mlon = 111320.0 * math.cos(edge.first.latitude * math.pi / 180);
    math.Point<double> xy(LatLng p) =>
        math.Point(p.longitude * mlon, p.latitude * 111320.0);

    ({double dist, double s}) onEdge(math.Point<double> p) {
      var best = double.infinity, bestS = 0.0, acc = 0.0;
      for (var i = 0; i < edge.length - 1; i++) {
        final a = xy(edge[i]), b = xy(edge[i + 1]);
        final ab = b - a;
        final len2 = ab.x * ab.x + ab.y * ab.y;
        final t = len2 > 0
            ? (((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2).clamp(0.0, 1.0)
            : 0.0;
        final proj = math.Point(a.x + ab.x * t, a.y + ab.y * t);
        final dd = (p - proj).magnitude;
        if (dd < best) {
          best = dd;
          bestS = acc + math.sqrt(len2) * t;
        }
        acc += math.sqrt(len2);
      }
      return (dist: best, s: bestS);
    }

    final picked = <({double s, LatLng p})>[];
    for (final r in _osmRails) {
      for (final q in r) {
        final n = onEdge(xy(q));
        if (n.dist <= 4.0) picked.add((s: n.s, p: q));
      }
    }
    if (picked.length < 4) return edge;
    picked.sort((a, b) => a.s.compareTo(b.s));
    return _resample([for (final e in picked) e.p], 60);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
          body: Center(child: Text('Failed to load fixtures:\n$_loadError')));
    }

    const hw = 2.95 / 2; // ICE half-width, metres
    const nose = 5.0;

    // Gleis 7's sector letters A–I (+ their positions) and the OSM platform area.
    final letters = _cubeLetters(_map);
    final cubeSide = [for (final c in letters) c.pos];
    final osmPlat =
        _osmPlatforms.where((p) => p.ref.split(';').contains(_gleis)).toList();

    // OSM rail curve for Gleis 7, then CLIP it to the sector span (I…A): the
    // train is exactly platform-long and the throat bend past A is excluded.
    final rail = osmPlat.isNotEmpty
        ? _railFromEdge(_trackSideEdge(osmPlat.first.pts, cubeSide))
        : const <LatLng>[];
    final path = rail.length >= 2 ? RoutePath.build(rail) : null;

    List<({String letter, LatLng pos})> sectors = const [];
    List<LatLng> body = const [];
    List<LatLng> bandSpine = const [];
    if (path != null) {
      // Each sector letter pinned onto the rail.
      sectors = [
        for (final c in letters) (letter: c.letter, pos: path.pointAt(path.locate(c.pos)))
      ];
      final arcs = [for (final c in letters) path.locate(c.pos)];
      final lo = arcs.reduce(math.min) - nose;
      final hi = arcs.reduce(math.max) + nose;
      bandSpine = path.slice(lo, hi);
      body = TrainGeometry.body(bandSpine,
          halfWidthM: hw, noseStart: true, noseEnd: true, noseLenM: nose);
    }

    final center = bandSpine.isNotEmpty
        ? bandSpine[bandSpine.length ~/ 2]
        : (letters.isNotEmpty ? letters[letters.length ~/ 2].pos : _map.center);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hamburg Hbf — Gleis 7 · Zug I→A'),
        backgroundColor: AppColors.secondClass,
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 18,
          minZoom: 15,
          maxZoom: 20,
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            maxNativeZoom: 20,
            maxZoom: 20,
            userAgentPackageName: 'dev.chuk.besserbahn.preview',
            errorTileCallback: (_, _, _) {},
          ),
          // The train body — built on the clipped OSM rail (Gleis 7, I→A).
          if (body.length >= 3)
            PolygonLayer(polygons: [
              Polygon(
                points: body,
                color: AppColors.secondClass.withValues(alpha: 0.55),
                borderColor: Colors.black87,
                borderStrokeWidth: 1.5,
              ),
            ]),
          // Sector letters A–I pinned on the rail.
          MarkerLayer(markers: [
            for (final s in sectors)
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
        ],
      ),
    );
  }
}

import 'dart:io';
import 'dart:math' as math;

import 'package:besser_bahn/core/platform_train.dart' as pt;
import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Perpendicular distance (metres) from [p] to the line through [a]–[b], in a
/// local equirectangular metre frame (fine over a single platform).
double _perpMetres(LatLng p, LatLng a, LatLng b) {
  const mlat = 111320.0;
  final mlon = 111320.0 * math.cos(a.latitude * math.pi / 180);
  math.Point<double> xy(LatLng q) =>
      math.Point(q.longitude * mlon, q.latitude * mlat);
  final pa = xy(a), pb = xy(b), pp = xy(p);
  final ex = pb.x - pa.x, ey = pb.y - pa.y;
  final len = math.sqrt(ex * ex + ey * ey);
  if (len < 1e-9) return 0;
  // |cross(b-a, p-a)| / |b-a|
  return ((pp.x - pa.x) * ey - (pp.y - pa.y) * ex).abs() / len;
}

/// Deterministic parse test for the bahnhof.de station-map scrape, using a
/// SAVED Kiel Hbf RSC fixture (no network) so it can't flake in CI.
///
/// Kiel Hbf is the station that "showed no train" in the app: this proves the
/// data IS in the payload (8 platforms / 16 sector cubes) and our parser pulls
/// it out — so if a train fails to render there, the bug is in placement
/// (platform_train), not the scrape. See [station_map_live_test] for the
/// network round-trip.
void main() {
  test('parses Kiel Hbf RSC fixture: platforms, sector cubes, levels', () {
    final body =
        File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('kiel-hbf', body);

    final cubes = map.pois.where((p) => p.isPlatformSector).length;

    // The numbers we verified by hand from the live payload.
    expect(map.platforms.length, 8, reason: 'PLATFORM POIs (Gleise)');
    expect(cubes, 16, reason: 'PLATFORM_SECTOR_CUBE POIs (A/B/C…)');
    expect(map.levels, contains('GROUND_FLOOR'));
    expect(map.center.latitude, closeTo(54.315, 0.05));
    expect(map.center.longitude, closeTo(10.132, 0.05));
    expect(map.pois, isNotEmpty);
  });

  test('platformGenericBody draws a closed train body when no Wagenreihung', () {
    final body = File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('kiel-hbf', body);

    // A Gleis that actually carries sector cubes on its platform island.
    final gleis = map.platforms
        .map((p) => pt.normalizeGleis(p.name))
        .firstWhere(
          (g) => pt.platformSectors(map, g).length >= 2,
          orElse: () => '',
        );
    expect(gleis, isNotEmpty, reason: 'expected a Gleis with ≥2 sector cubes');

    // Without a Wagenreihung we still get a single closed polygon (a train
    // body), curved along the platform, sized to a realistic length — not a
    // bare line nor the whole platform.
    final outline =
        pt.platformGenericBody(map, gleis: gleis, lengthM: 140);
    expect(outline.length, greaterThanOrEqualTo(3),
        reason: 'generic body is a closed ring');
  });

  test('Kiel Hbf generic body centreline is essentially straight', () {
    final body = File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('kiel-hbf', body);

    // Kiel is a terminus of parallel STRAIGHT platforms and has 0 lift/escalator
    // anchors, so its island resolution can mix cubes from several tracks. The
    // body must still come out straight (no phantom parabola bend).
    final gleis = map.platforms
        .map((p) => pt.normalizeGleis(p.name))
        .firstWhere(
          (g) => pt.platformSectors(map, g).length >= 2,
          orElse: () => '',
        );
    expect(gleis, isNotEmpty, reason: 'expected a Gleis with ≥2 sector cubes');

    final outline = pt.platformGenericBody(map, gleis: gleis, lengthM: 140);
    expect(outline.length, greaterThanOrEqualTo(3));

    // Chord between the two most-distant vertices (the body's long axis). On a
    // straight platform every vertex sits within ~half the body width (≈1.4 m,
    // plus a little for the rounded snouts) of that chord; a parabola bend
    // would push the mid vertices several metres off it. Allow ~4 m.
    const dist = Distance();
    var ai = 0, bi = 0;
    var best = -1.0;
    for (var i = 0; i < outline.length; i++) {
      for (var j = i + 1; j < outline.length; j++) {
        final d = dist.as(LengthUnit.Meter, outline[i], outline[j]);
        if (d > best) {
          best = d;
          ai = i;
          bi = j;
        }
      }
    }
    final a = outline[ai], b = outline[bi];
    var maxDev = 0.0;
    for (final p in outline) {
      maxDev = math.max(maxDev, _perpMetres(p, a, b));
    }
    expect(maxDev, lessThan(4.0),
        reason: 'Kiel platform is straight; body deviates $maxDev m from chord');
  });

  test('Hamburg Hbf body stays straight despite mis-assigned cubes', () {
    // Hamburg Hbf is strongly curved, BUT the bahnhof.de sector cubes are
    // mis-assigned per letter (measured: a single Abschnitt sits up to ~60 m
    // off the platform line — physically impossible). Connecting them would
    // zig-zag, so we lay the train straight on the platform's best-fit axis.
    // This locks that: every body vertex stays near its own chord.
    final body = File('test/fixtures/hamburg-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('hamburg-hbf', body);
    final dirty = map.platforms
        .map((p) => pt.normalizeGleis(p.name))
        .where((g) => pt.platformSectors(map, g).length >= 2)
        .toList();
    expect(dirty, isNotEmpty);
    const dist = Distance();
    for (final g in dirty) {
      final outline = pt.platformGenericBody(map, gleis: g, lengthM: 200);
      if (outline.length < 3) continue;
      var ai = 0, bi = 0, best = -1.0;
      for (var i = 0; i < outline.length; i++) {
        for (var j = i + 1; j < outline.length; j++) {
          final d = dist.as(LengthUnit.Meter, outline[i], outline[j]);
          if (d > best) {
            best = d;
            ai = i;
            bi = j;
          }
        }
      }
      var maxDev = 0.0;
      for (final p in outline) {
        maxDev = math.max(maxDev, _perpMetres(p, outline[ai], outline[bi]));
      }
      expect(maxDev, lessThan(4.0),
          reason: 'Gleis $g body should be straight, deviates $maxDev m');
    }
  });
}

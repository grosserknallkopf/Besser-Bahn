import 'dart:io';

import 'package:besser_bahn/core/platform_train.dart' as pt;
import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

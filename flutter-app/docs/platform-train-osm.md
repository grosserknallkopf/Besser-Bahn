# Standing-train placement on the platform — findings (2026-05-31)

How to draw the to-scale, top-down train **standing at a platform** so it sits
exactly on the right track, follows the track's curve, and shows where each
coach/sector is. Worked out interactively against Hamburg Hbf with a standalone
Linux preview (`lib/dev/platform_preview.dart`).

## TL;DR
- **OpenStreetMap is the accurate, trustworthy source for WHERE the track is.**
  It matches the satellite imagery perfectly, knows the Gleis numbers, and has
  clean track/platform geometry. **Trust OSM for the line the train rides.**
- The bahnhof.de data we used before is NOT reliable for geometry:
  - the `PLATFORM_SECTOR_CUBE` markers are **mis-assigned per letter** — measured
    28 m (Kiel) to **60 m** (Hamburg) off the real platform line, impossible for
    one sector;
  - the DB indoor floor-plan tile overlay is **distorted/warped** in places.
- **The one remaining task** is no longer "where is the track" (OSM solves that)
  but **"where exactly is each part of the train"** — i.e. mapping the sectors
  (Abschnitt A–G/I) and therefore each coach onto the OSM line.

## What OSM gives (verified via Overpass at Hamburg Hbf)
- **Gleis numbers:** `public_transport=platform` areas tagged `ref` = `1`, `2`,
  `5;6`, **`7;8`**, `11;12`, `13;14` (a double-track island platform is one area
  labelled with its track pair).
- **Real track geometry:** ~79 `railway=rail` ways (clean lines; `ref` on them is
  the *line/route* number, not the Gleis).
- **Stop positions:** `stop_position` nodes with `ref` per track.
- Platforms are mapped as **AREA polygons** (a long thin loop), not centre-lines.
  To get a line: split the loop at its two extreme ends into the two long edges,
  resample each by arc-length, and take the **edge on the wanted track's side**
  (track 7 vs 8 = the two long edges). That edge sits on the rail (the platform
  centre-line would sit *between* tracks 7 and 8).
- **OSM does NOT provide platform sectors (Abschnitt A, B, C …).** A search for
  `railway=platform_section_sign` / single-letter `ref` near Hbf found only
  entrances and signals — no sector signs. So the A–G positions must come from
  elsewhere.

## Where the sectors come from (the cubes — order only, not geometry)
The bahnhof.de sector cubes carry the letters (A–I) and an internal id, but no
track link, and their absolute positions are contaminated. However, **peeling**
recovers the correct *sequence* per platform island:
1. Group cubes by letter; seed at the highest-letter cube still unused (the long
   7/8 platform has the only G/H/I, so it peels first).
2. Walk DOWN the letters with **momentum** (predict next = `cur + (cur − prev)`,
   take the nearest candidate) — follows the platform's own curve, ignores cubes
   that veer onto another track.
3. Remove that chain, repeat. Assign each chain to a Gleis via the lift/escalator
   **anchors** that name it ("Gleis 7/8 …", which sit on the platform).
This reproduced the human-confirmed Gleis-7 chain
`I3 H4 G2 F22 E1 D10 C20 B12 A13` and three more clean island chains. So the
cubes give a reliable **A→I ordering / relative spacing**, just not trustworthy
absolute geometry.

## The plan (synthesis)
1. **Track line = OSM** (platform area → track-side edge for the Gleis). This is
   exactly where the train sits; verified against satellite. The train body is
   built along this line.
2. **Side (7 vs 8)** = the OSM platform edge nearer the trusted cube chain (or
   the Gleis POI); the cubes reliably tell the *side* even though their exact
   positions are off.
3. **Sectors / coaches along the line** = project the cube chain's letter
   positions (order + spacing) onto the OSM line, then lay the Wagenreihung
   coaches by their real metre offsets. ← **this is the last open piece.**
4. Moving train keeps using the route `zuglauf` polyline (unchanged).

## Notes
- **Satellite layer** in the preview is **Esri "World Imagery"** (ArcGIS), NOT
  OpenStreetMap — OSM itself serves no aerial imagery. It's usable for dev/
  reference; for production, aerial tiles need a provider with terms/key (Esri,
  Mapbox, Bing, …). We do NOT need satellite in the app — it was only to verify
  that the OSM vector tracks match reality (they do).
- **Standalone preview:** `flutter run -d linux -t lib/dev/platform_preview.dart`.
  Toggles: base-map model (OSM / CARTO / Esri sat / OpenRailwayMap / OpenTopo),
  DB indoor plan on/off, OSM overlay on/off, Gleis, manual lateral fine-tune.
  Fixtures: `test/fixtures/hamburg-hbf.rsc.txt` (DB station map),
  `test/fixtures/hamburg-zuglauf.json` (route polyline),
  `test/fixtures/hamburg-osm.json` (OSM platforms + rails);
  fetched by `api-tests/fetch_hamburg_zuglauf.py` and an Overpass query.
- All of this is still in the **dev preview only** — not yet ported into the
  production app (`lib/core/platform_train.dart`, the Bahnhofskarte / Umstiegs- /
  Routenkarte). Porting = make the placement fetch OSM platform/rail geometry
  (Overpass) per station, cache it, and feed the OSM line + cube-derived sectors
  into the existing body geometry.

# TODO

## Suche: "Bahnhof in der Nähe" (GPS → nächste Station)

Standort-Icon im "Von"-Feld der Verbindungssuche: GPS-Fix holen → nächsten
Bahnhof finden → als Startstation einsetzen.

**Status:** geparkt (GPS-Fix im Testgerät nicht verfügbar → blockiert).

**Schon vorhanden:**
- `geolocator: ^14.0.0` in pubspec.
- `lib/services/location_service.dart` → `LocationService.currentFix()` liefert
  `UserFix(latLng, accuracy)` inkl. deutscher Permission-/Fehlertexte.
- `VendoService.searchLocations(query)` (POST `/mob/location/search`,
  media `application/x.db.vendo.mob.location.v3+json`) — nur Textsuche.

**Offen — Endpoint für Koordinaten-Suche:**
- `POST /mob/location/nearby` existiert (GET → 405), aber alle geratenen Bodies
  liefern `{"domain":"MOB","code":"VALIDIERUNG","status":"ERROR"}` (HTTP 400).
  Probiert: `coordinates`/`coordinate`/`position`/`koordinate`, lat-long als
  float + microdegrees, mit/ohne `radius`/`maxResults`/`locationTypes`.
- **Nächster Schritt:** im echten DB-Navigator die "in der Nähe"-Stationssuche
  auslösen, mit HTTP Toolkit den `/location/nearby`-Request abgreifen → exaktes
  Body-Format übernehmen. (Echte App schickt zusätzlich `x-device-os-name`,
  `x-device-os-version`, `x-device-model`, `x-instana-android` — evtl. relevant.)

**UI:** Standort-Icon ins "Von"-Feld, `LocationService.currentFix()` →
nearby-Call → erste Station als Start setzen; `LocationException`-Text in
SnackBar zeigen.

## "In der Nähe": Abfahrten + Karte zu einem Screen zusammenlegen

Die offizielle DB-App hat eine GPS-basierte "in der Nähe"-Ansicht: eine Karte
mit dem eigenen Standort, drumherum die Stationen, und was dort gleich abfährt.

Idee: die zwei Tabs **Abfahrten** + **Karte** zu *einem* Screen mergen → weniger
Tabs (aktuell 5: Suche, Reisen, Zug, Abfahrten, Karte). Karte zeigt Standort +
nahe Bahnhöfe; Tippen/Standort → Abfahrtstafel der nächsten Station inline.

**Status:** geparkt — Kern ist GPS-basiert, Fix im Testgerät nicht verfügbar.

**Abhängig von:** Koordinaten-Endpoint oben (`/location/nearby`-Body klären).
Danach: `home_screen.dart` destinations von 5 → 4 Tabs, Abfahrten- und Karte-
Screens in einen kombinierten "In der Nähe"-Screen ziehen.

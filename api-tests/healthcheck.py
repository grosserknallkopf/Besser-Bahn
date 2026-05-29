#!/usr/bin/env python3
"""
Besser-Bahn API health check.

Probes every upstream endpoint the app depends on and asserts the response
still has the shape we parse. Run it to find out *fast* when Deutsche Bahn
changes or removes an endpoint.

Two ways to run:
    python3 healthcheck.py            # human-readable table, exit 1 on failure
    pytest healthcheck.py             # CI / assertion mode

Zero hard deps beyond `requests`.

Endpoint map (see app code in flutter-app/lib/services/):
  bahn.de GET endpoints      -> autocomplete, departures, train run. Not bot-gated.
  app.services-bahn.de /mob  -> DB Navigator backend: location + journey+PRICES (v9).
                                Replaces the Akamai-blocked website journey POST.
  bahnhof.de /{slug}/karte   -> indoor station map (RSC GeoJSON).
  v*.db.transport.rest       -> community HAFAS mirror, historically flaky.
  www.bahn.de angebote/fahrplan POST -> Akamai-blocked (OPS_BLOCKED) from non-browser;
                                we assert it STAYS blocked so a change is noticed.
"""
from __future__ import annotations

import json
import sys
import time
import uuid
from datetime import datetime, timezone

import requests

TIMEOUT = 20
DBNAV_UA = "DBNavigator/Android/26.9.0"

# Known stations used as fixtures.
KIEL = "8000199"
BERLIN_HBF = "8011160"
KOELN_HBF = "8000207"

# Vendo (DB Navigator) location ids — stable HAFAS strings.
KIEL_LOC = ("A=1@O=Kiel Hbf@X=10131976@Y=54314982@U=80@L=8000199@"
            "p=1779908603@i=U×008001304@")
BERLIN_LOC = ("A=1@O=Berlin Hbf@X=13369549@Y=52525589@U=80@L=8011160@"
              "p=1779908603@i=U×008065969@")


def _corr_id() -> str:
    return f"{uuid.uuid4()}_{uuid.uuid4()}"


def _browser_headers() -> dict:
    return {
        "User-Agent": ("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                       "(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"),
        "Accept": "application/json",
        "Accept-Language": "de-DE,de;q=0.9",
    }


def _vendo_headers(media: str) -> dict:
    return {
        "Accept": media,
        "Content-Type": media,
        "Accept-Language": "de",
        "User-Agent": DBNAV_UA,
        "X-App-Version": "26.9.0",
        "X-Correlation-ID": _corr_id(),
    }


class CheckError(AssertionError):
    """Raised when an endpoint responds but the shape we rely on is gone."""


# --------------------------------------------------------------------------
# Individual checks. Each returns a short detail string on success or raises.
# --------------------------------------------------------------------------

def check_bahn_autocomplete() -> str:
    r = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/orte",
        params={"suchbegriff": "Köln Hbf", "typ": "ALL", "limit": "5"},
        headers=_browser_headers(), timeout=TIMEOUT,
    )
    r.raise_for_status()
    data = r.json()
    if not isinstance(data, list) or not data:
        raise CheckError("expected non-empty list")
    first = data[0]
    for key in ("id", "extId", "name"):
        if key not in first:
            raise CheckError(f"missing field '{key}' in station object")
    return f"{len(data)} hits, top='{first['name']}' eva={first['extId']}"


def check_bahn_departures() -> str:
    now = datetime.now()
    r = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={
            "datum": now.strftime("%Y-%m-%d"),
            "zeit": now.strftime("%H:%M:00"),
            "ortExtId": KOELN_HBF, "mitVias": "false",
        },
        headers=_browser_headers(), timeout=TIMEOUT,
    )
    r.raise_for_status()
    entries = r.json().get("entries", [])
    if not entries:
        raise CheckError("no departure entries")
    e = entries[0]
    if "verkehrmittel" not in e or "journeyId" not in e:
        raise CheckError("departure entry missing verkehrmittel/journeyId")
    return f"{len(entries)} departures, first journeyId len={len(e['journeyId'])}"


def check_bahn_train_run() -> str:
    """reiseloesung/fahrt — powers the Zugverlauf (onward stops)."""
    now = datetime.now()
    dep = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={"datum": now.strftime("%Y-%m-%d"),
                "zeit": now.strftime("%H:%M:00"),
                "ortExtId": KOELN_HBF, "mitVias": "false"},
        headers=_browser_headers(), timeout=TIMEOUT,
    )
    dep.raise_for_status()
    entries = dep.json().get("entries", [])
    if not entries:
        raise CheckError("no departures to derive a journeyId")
    jid = entries[0]["journeyId"]
    r = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/fahrt",
        params={"journeyId": jid}, headers=_browser_headers(), timeout=TIMEOUT,
    )
    r.raise_for_status()
    data = r.json()
    halte = data.get("halte") or data.get("verlauf") or []
    if not halte:
        raise CheckError("train run has no halte/verlauf")
    return f"{len(halte)} stops on the train run"


def check_vendo_location() -> str:
    media = "application/x.db.vendo.mob.location.v3+json"
    r = requests.post(
        "https://app.services-bahn.de/mob/location/search",
        headers=_vendo_headers(media),
        data=json.dumps({"locationTypes": ["ALL"], "searchTerm": "Köln Hbf"}),
        timeout=TIMEOUT,
    )
    r.raise_for_status()
    data = r.json()
    if not isinstance(data, list) or not data:
        raise CheckError("expected non-empty list")
    first = data[0]
    for key in ("locationId", "evaNr", "coordinates"):
        if key not in first:
            raise CheckError(f"missing field '{key}'")
    return f"{len(data)} hits, top='{first['name']}' eva={first['evaNr']}"


def check_vendo_journey() -> str:
    """The important one: journeys WITH prices, replaces website fahrplan."""
    media = "application/x.db.vendo.mob.verbindungssuche.v9+json"
    body = {
        "autonomeReservierung": False,
        "einstiegsTypList": ["STANDARD"],
        "fahrverguenstigungen": {
            "deutschlandTicketVorhanden": False,
            "nurDeutschlandTicketVerbindungen": False,
        },
        "klasse": "KLASSE_2",
        "reiseHin": {"wunsch": {
            "abgangsLocationId": KIEL_LOC,
            "alternativeHalteBerechnung": True,
            "verkehrsmittel": ["ALL"],
            "zeitWunsch": {
                "reiseDatum": datetime.now().astimezone().isoformat(),
                "zeitPunktArt": "ABFAHRT",
            },
            "zielLocationId": BERLIN_LOC,
        }},
        "reisendenProfil": {"reisende": [{
            "ermaessigungen": ["KEINE_ERMAESSIGUNG KLASSENLOS"],
            "reisendenTyp": "ERWACHSENER",
        }]},
        "reservierungsKontingenteVorhanden": False,
    }
    r = requests.post(
        "https://app.services-bahn.de/mob/angebote/fahrplan",
        headers=_vendo_headers(media), data=json.dumps(body), timeout=TIMEOUT,
    )
    r.raise_for_status()
    conns = r.json().get("verbindungen", [])
    if not conns:
        raise CheckError("no verbindungen returned")
    c = conns[0]
    legs = c["verbindung"]["verbindungsAbschnitte"]
    if not legs:
        raise CheckError("verbindung has no verbindungsAbschnitte")
    # price is best-effort (some legs are price-less), so only soft-check.
    price = (c.get("angebote", {}).get("preise", {})
             .get("gesamt", {}).get("ab", {}).get("betrag"))
    price_txt = f", ab {price} EUR" if price is not None else ", no price"
    return f"{len(conns)} journeys, first has {len(legs)} legs{price_txt}"


def check_vendo_train_polyline() -> str:
    """
    GET /mob/zuglauf/{id} — the exact track geometry DB Navigator draws on its
    map (polylineGroup.polylineDesc[].coordinates). Powers the app's route map
    (services/vendo_service.fetchTripPolyline). Id is the bahn.de departures
    journeyId / a vendo leg's zuglaufId (same HAFAS-style string).
    """
    now = datetime.now()
    dep = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={"datum": now.strftime("%Y-%m-%d"),
                "zeit": now.strftime("%H:%M:00"),
                "ortExtId": BERLIN_HBF, "mitVias": "false"},
        headers=_browser_headers(), timeout=TIMEOUT,
    )
    dep.raise_for_status()
    entries = dep.json().get("entries", [])
    if not entries:
        raise CheckError("no departures to derive a zuglaufId")
    jid = entries[0]["journeyId"]

    media = "application/x.db.vendo.mob.zuglauf.v2+json"
    import urllib.parse
    r = requests.get(
        f"https://app.services-bahn.de/mob/zuglauf/{urllib.parse.quote(jid, safe='')}",
        headers=_vendo_headers(media), timeout=TIMEOUT,
    )
    r.raise_for_status()
    data = r.json()
    descs = (data.get("polylineGroup") or {}).get("polylineDesc") or []
    pts = [c for d in descs for c in (d.get("coordinates") or [])]
    if not pts:
        raise CheckError("no polylineGroup.polylineDesc coordinates")
    first = pts[0]
    if "latitude" not in first or "longitude" not in first:
        raise CheckError("coordinate missing latitude/longitude")
    return f"{len(pts)} track points (first {first['latitude']},{first['longitude']})"


def check_bahnhof_map() -> str:
    r = requests.get("https://www.bahnhof.de/hamburg-hbf/karte",
                     headers=_browser_headers(), timeout=TIMEOUT)
    r.raise_for_status()
    html = r.text
    if '"poi":{"' not in html and '"poi\\":{\\"' not in html:
        raise CheckError("no embedded poi object in RSC stream")
    if "PLATFORM" not in html:
        raise CheckError("no PLATFORM (Gleis) category in map data")
    return "RSC contains poi object with PLATFORM category"


def check_bay_departure_link() -> str:
    """
    The station map links a tapped bay/track to live departures by matching the
    map POI's bay label against the departure board's `gleis`. Verify the two
    DB data sources still share a labelling so the match works (the app falls
    back to showing all departures when they don't, so this is a soft check).
    """
    now = datetime.now()
    dep = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={"datum": now.strftime("%Y-%m-%d"),
                "zeit": now.strftime("%H:%M:00"),
                "ortExtId": KIEL, "mitVias": "false"},
        headers=_browser_headers(), timeout=TIMEOUT,
    )
    dep.raise_for_status()
    gleise = {e.get("gleis") for e in dep.json().get("entries", []) if e.get("gleis")}

    karte = requests.get("https://www.bahnhof.de/kiel-hbf/karte",
                         headers=_browser_headers(), timeout=TIMEOUT)
    karte.raise_for_status()
    import re as _re
    bays = set(_re.findall(r"\[H\]([0-9A-Za-z]+)", karte.text))

    shared = gleise & bays
    if not shared:
        raise CheckError("no shared bay labels between map and departures "
                         "(app will fall back to all-departures view)")
    return f"{len(shared)} bay labels link map↔departures (e.g. {sorted(shared)[:4]})"


def _norm_gleis(g: str) -> str:
    """Mirror the app: drop the platform section suffix → base track id."""
    import re as _re
    g = g.strip()
    if not g:
        return g
    if _re.match(r"^\d", g):
        return _re.match(r"^\d+", g).group(0)
    return _re.split(r"\s+", g)[0].upper()


def check_gleis_departure_link() -> str:
    """
    Tapping a Gleis on the map links to its departures by matching the POI's
    track number to the board's `gleis`. The board adds a section suffix
    ("6A-C") the map omits ("6"); we normalise both. Verify they still align
    for trains at a big station — this is the universal (non-bus) case.
    """
    now = datetime.now()
    dep = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={"datum": now.strftime("%Y-%m-%d"), "zeit": now.strftime("%H:%M:00"),
                "ortExtId": "8002549", "mitVias": "false"},  # Hamburg Hbf
        headers=_browser_headers(), timeout=TIMEOUT,
    )
    dep.raise_for_status()
    dep_g = {_norm_gleis(e["gleis"]) for e in dep.json().get("entries", [])
             if e.get("gleis")}

    karte = requests.get("https://www.bahnhof.de/hamburg-hbf/karte",
                         headers=_browser_headers(), timeout=TIMEOUT)
    karte.raise_for_status()
    import re as _re
    # Decode the RSC stream (same as the app) before matching.
    blob = "".join(
        json.loads(s) for s in
        _re.findall(r'self\.__next_f\.push\(\[\d+,("(?:[^"\\]|\\.)*")\]\)',
                    karte.text, _re.S))
    poi_tracks = {_norm_gleis(m) for m in
                  _re.findall(r'"type":"PLATFORM".{0,200}?"name":"([^"]+)"', blob)}
    poi_tracks.discard("")

    shared = dep_g & poi_tracks
    # Most departing tracks should map to a POI track number.
    if len(shared) < 5:
        raise CheckError(f"only {len(shared)} normalised tracks align "
                         f"(dep={sorted(dep_g)[:8]} poi={sorted(poi_tracks)[:8]})")
    return f"{len(shared)} track ids align map↔departures after normalisation"


def check_bahnhof_sitemap() -> str:
    r = requests.get("https://www.bahnhof.de/sitemap.xml",
                     headers=_browser_headers(), timeout=TIMEOUT)
    r.raise_for_status()
    count = r.text.count("<loc>https://www.bahnhof.de/")
    if count < 4000:
        raise CheckError(f"sitemap only has {count} urls (expected >4000)")
    return f"{count} sitemap urls"


def check_hafas_rest() -> str:
    """Community HAFAS mirror — flaky, treated as a soft/degraded check."""
    r = requests.get("https://v6.db.transport.rest/locations",
                     params={"query": "Koeln", "results": "1"},
                     headers=_browser_headers(), timeout=TIMEOUT)
    if r.status_code != 200:
        raise CheckError(f"HAFAS mirror down (HTTP {r.status_code})")
    data = r.json()
    if not data:
        raise CheckError("HAFAS mirror returned empty")
    return f"HAFAS mirror up ({data[0].get('name')})"


def check_website_journey_still_blocked() -> str:
    """
    The website journey POST is Akamai bot-blocked from non-browser clients.
    We assert it STAYS blocked — if this starts returning data, we can simplify.
    """
    now = datetime.now()
    body = {
        "abfahrtsHalt": KIEL_LOC, "ankunftsHalt": BERLIN_LOC,
        "anfrageZeitpunkt": now.strftime("%Y-%m-%dT%H:%M"),
        "ankunftSuche": "ABFAHRT", "klasse": "KLASSE_2",
        "produktgattungen": ["ICE", "EC_IC", "IR", "REGIONAL", "SBAHN"],
        "reisende": [{"typ": "ERWACHSENER", "ermaessigungen": [
            {"art": "KEINE_ERMAESSIGUNG", "klasse": "KLASSENLOS"}],
            "alter": [], "anzahl": 1}],
        "schnelleVerbindungen": True,
    }
    r = requests.post("https://www.bahn.de/web/api/angebote/fahrplan",
                      headers={**_browser_headers(),
                               "Content-Type": "application/json"},
                      data=json.dumps(body), timeout=TIMEOUT)
    if r.status_code == 200 and "verbindungen" in r.text:
        # Not an error — a happy surprise worth flagging.
        raise CheckError("website journey POST now WORKS — consider using it")
    # Any non-200 (OPS_BLOCKED / 403 / 422 / 500) means still unusable, as expected.
    reason = "OPS_BLOCKED" if "OPS_BLOCKED" in r.text else f"HTTP {r.status_code}"
    return f"still unusable as expected ({reason}); use vendo instead"


# (name, callable, soft) — soft checks warn instead of fail.
CHECKS = [
    ("bahn.de autocomplete (orte)", check_bahn_autocomplete, False),
    ("bahn.de departures (abfahrten)", check_bahn_departures, False),
    ("bahn.de train run (fahrt)", check_bahn_train_run, False),
    ("vendo location search", check_vendo_location, False),
    ("vendo journey + prices (v9)", check_vendo_journey, False),
    ("vendo train polyline (zuglauf)", check_vendo_train_polyline, False),
    ("bahnhof.de station map (karte)", check_bahnhof_map, False),
    ("map bay ↔ departures link", check_bay_departure_link, True),
    ("map Gleis ↔ departures (normalised)", check_gleis_departure_link, False),
    ("bahnhof.de sitemap", check_bahnhof_sitemap, False),
    ("HAFAS rest mirror (flaky)", check_hafas_rest, True),
    ("website journey blocked check", check_website_journey_still_blocked, True),
]


# --------------------------------------------------------------------------
# pytest entrypoints (one test per non-soft check)
# --------------------------------------------------------------------------
def _make_pytest(fn):
    def _t():
        fn()
    return _t


for _name, _fn, _soft in CHECKS:
    if not _soft:
        globals()[f"test_{_fn.__name__}"] = _make_pytest(_fn)


# --------------------------------------------------------------------------
# Standalone runner
# --------------------------------------------------------------------------
def main() -> int:
    print(f"Besser-Bahn API health check — {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}\n")
    failures = 0
    for name, fn, soft in CHECKS:
        t0 = time.monotonic()
        try:
            detail = fn()
            ms = int((time.monotonic() - t0) * 1000)
            print(f"  ✅ {name:36} {ms:>5}ms  {detail}")
        except Exception as e:  # noqa: BLE001 - report everything
            ms = int((time.monotonic() - t0) * 1000)
            tag = "⚠️ WARN" if soft else "❌ FAIL"
            print(f"  {tag} {name:36} {ms:>5}ms  {type(e).__name__}: {e}")
            if not soft:
                failures += 1
    print()
    if failures:
        print(f"{failures} hard check(s) FAILED — an API likely changed.")
        return 1
    print("All hard checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

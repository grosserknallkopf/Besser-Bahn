#!/usr/bin/env python3
"""One-off: mint Hamburg-Hbf train zuglauf ids and pull their track polylines,
saving the best-covering one as test/fixtures/hamburg-zuglauf.json
(a JSON array of {lat,lng}).

Same patterns as healthcheck.py: bahn.de abfahrten for journeyIds at Hamburg Hbf
(EVA 8002549), then GET /mob/zuglauf/{id} on the DB Navigator backend. We score
each polyline by how many of the main-hall long-distance platform positions it
passes within 35 m of, then by total nearness — so we keep a polyline that runs
ALONG the curved main-hall tracks (Gleis 5-14), not an S-Bahn tunnel run that
only clips a couple of tracks.
"""
import json
import math
import os
import urllib.parse
import uuid
from datetime import datetime

import requests

DBNAV_UA = "DBNavigator/Android/26.9.0"
HAMBURG_EVA = "8002549"
TIMEOUT = 20

# Main-hall long-distance platform positions, read from the parsed fixture
# (Gleis -> lat,lng), the tracks we draw the platform train on.
PLATFORMS = {
    "3": (53.552777, 10.007659), "4": (53.552754, 10.007514),
    "5": (53.552732, 10.007374), "6": (53.552711, 10.007238),
    "7": (53.552689, 10.007103), "8": (53.552665, 10.006951),
    "11": (53.552619, 10.006664), "12": (53.552588, 10.006465),
    "13": (53.552564, 10.006313), "14": (53.552543, 10.006179),
}


def browser_headers():
    return {
        "User-Agent": ("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                       "(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"),
        "Accept": "application/json",
        "Accept-Language": "de-DE,de;q=0.9",
    }


def vendo_headers(media):
    return {
        "Accept": media, "Content-Type": media, "Accept-Language": "de",
        "User-Agent": DBNAV_UA, "X-App-Version": "26.9.0",
        "X-Correlation-ID": f"{uuid.uuid4()}_{uuid.uuid4()}",
    }


def haversine(a, b):
    R = 6371000.0
    dlat = math.radians(b[0] - a[0]); dlon = math.radians(b[1] - a[1])
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    h = math.sin(dlat/2)**2 + math.cos(la1)*math.cos(la2)*math.sin(dlon/2)**2
    return 2 * R * math.asin(math.sqrt(h))


def fetch_polyline(jid):
    media = "application/x.db.vendo.mob.zuglauf.v2+json"
    r = requests.get(
        f"https://app.services-bahn.de/mob/zuglauf/{urllib.parse.quote(jid, safe='')}",
        headers=vendo_headers(media), timeout=TIMEOUT)
    if r.status_code != 200:
        return None
    data = r.json()
    descs = (data.get("polylineGroup") or {}).get("polylineDesc") or []
    pts = [{"lat": c["latitude"], "lng": c["longitude"]}
           for d in descs for c in (d.get("coordinates") or [])
           if "latitude" in c and "longitude" in c]
    return pts or None


def score(pts):
    """(#platforms covered within 35 m, -sum of nearest dists) — higher better."""
    covered = 0
    total = 0.0
    for g, pos in PLATFORMS.items():
        nd = min(haversine(pos, (p["lat"], p["lng"])) for p in pts)
        if nd <= 35:
            covered += 1
        total += nd
    return covered, -total


def main():
    now = datetime.now()
    dep = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={"datum": now.strftime("%Y-%m-%d"),
                "zeit": now.strftime("%H:%M:00"),
                "ortExtId": HAMBURG_EVA, "mitVias": "false"},
        headers=browser_headers(), timeout=TIMEOUT)
    dep.raise_for_status()
    entries = dep.json().get("entries", [])
    print(f"{len(entries)} departures at Hamburg Hbf")

    best = None  # (score_tuple, pts, label)
    seen = set()
    for e in entries:
        jid = e.get("journeyId")
        vm = (e.get("verkehrmittel") or {})
        label = vm.get("mittelText") or (jid or "")[:20]
        # focus on long-distance / regional through the main hall, skip bus/U/S
        kat = (vm.get("produktGattung") or "").upper()
        if any(x in label.upper() for x in ("BUS", "U1", "U2", "U3", "U4")):
            continue
        if not jid or jid in seen:
            continue
        seen.add(jid)
        try:
            pts = fetch_polyline(jid)
        except Exception as ex:
            continue
        if not pts:
            continue
        sc = score(pts)
        print(f"  {label:>6}: {len(pts):>3} pts, covered={sc[0]} sumNear={-sc[1]:.0f}m")
        if best is None or sc > best[0] or (sc == best[0] and len(pts) > len(best[1])):
            best = (sc, pts, label)
        if len(seen) >= 60:
            break

    if best is None:
        raise SystemExit("no usable polyline found")
    sc, pts, label = best
    out = os.path.abspath(os.path.join(
        os.path.dirname(__file__), "..", "flutter-app",
        "test", "fixtures", "hamburg-zuglauf.json"))
    with open(out, "w") as f:
        json.dump(pts, f)
    print(f"\nBEST: '{label}' {len(pts)} pts, covered={sc[0]}/10 -> {out}")


if __name__ == "__main__":
    main()

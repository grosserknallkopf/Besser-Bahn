#!/usr/bin/env python3
"""
Reproducible comparison: does the platform train sit ON the real rails?

Quantifies, for the Besser-Bahn station map, whether the train body drawn at a
platform actually overlies the OpenStreetMap railway=rail centre-line, and
compares the CURRENT production placement against a DIRECT-OSM placement.

KNOWN TEST CASE
  ERX 83 / Fahrt-Nr 21041, Kiel Hbf (eva 8000199) Gl 1 22:43 -> Raisdorf
  (eva 8004924) Gl 1 22:51. Regional erixx (Coradia LINT) service in S-H.

THE TWO METHODS (ported from the Flutter app)
  A) CURRENT (cube-anchored LSQ): exactly lib/core/platform_train.dart —
     anchor the Wagenreihung's platform.sectors (A-I metre offsets) to
     bahnhof.de PLATFORM_SECTOR_CUBE POIs, least-squares fit offset->arc onto
     the OSM rail spine (core/osm_rail.dart), slice each coach off that curve.
     If a station has <2 sector cubes (Raisdorf has NONE) it cannot place a
     train at all -- that is itself a result we report.
  B) DIRECT-OSM: ignore the bahnhof.de cubes entirely. Recover the OSM rail
     spine for the Gleis directly (platform area -> track-side edge -> rail),
     centre the train on the rail's mid-point span, slice each coach off it.

METRIC
  For each coach outline, the perpendicular distance (metres) of its centre-line
  sample points to the nearest OSM railway=rail vertex/segment for that Gleis.
  Report mean / max / p95 per method; flag any coach straying > 2.5 m off-rail.

DATA SOURCES (keyless, stdlib + urllib only -- matches api-tests style):
  * OSM   : Overpass (same QL as services/osm_platform_service.dart),
            UA 'BesserBahn/1.0 (+https://bahn.chuk.dev)' (mandatory, else 406).
  * bahnhof.de map : RSC flight stream at /{slug}/karte (RSC:1 header).
  * Wagenreihung   : bahn.de reisebegleitung/wagenreihung/vehicle-sequence.
                     erixx publishes NONE (404) -> we fall back to a realistic
                     Coradia-LINT composition so the geometry test still runs.

Deterministic: pass --date YYYY-MM-DD (default = tomorrow). No clock branching
in the geometry.

Run:  python3 compare_train_placement.py [--date 2026-06-02]
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

# --------------------------------------------------------------------------
# Test-case constants
# --------------------------------------------------------------------------
KIEL_EVA = "8000199"
RAISDORF_EVA = "8004924"
RAISDORF_LL = (54.280940, 10.243694)
KIEL_LL = (54.314982, 10.131976)
TRAIN_NUMBER = "21041"
TRAIN_CATEGORY = "ERX"

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.openstreetmap.fr/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
OVERPASS_UA = "BesserBahn/1.0 (+https://bahn.chuk.dev)"
BROWSER_UA = ("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36")
TIMEOUT = 30

# A realistic erixx Coradia LINT 41 composition (2 single-unit cars coupled),
# used only when the live Wagenreihung 404s (it always does for ERX). Each car
# ~41 m; sectors are the DB A-I 50 m-ish metre bands the platform reports. These
# numbers exist purely so methods A and B both have a coach list to place; the
# OFF-RAIL metric does not depend on the absolute metre values being DB-exact,
# only on the placement mapping them onto a curve.
FALLBACK_SECTORS = [  # name, start_m, end_m  (along the platform)
    ("A", 0.0, 35.0),
    ("B", 35.0, 70.0),
    ("C", 70.0, 105.0),
    ("D", 105.0, 140.0),
]
FALLBACK_COACHES = [  # sector, start_m, end_m
    ("A", 12.0, 53.0),
    ("C", 53.0, 94.0),
]


# --------------------------------------------------------------------------
# tiny HTTP (stdlib)
# --------------------------------------------------------------------------
def _get(url: str, headers: dict) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def _post(url: str, data: dict, headers: dict) -> tuple[int, bytes]:
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


# --------------------------------------------------------------------------
# Planar metre frame (equirectangular) -- mirrors core/train_geometry _Frame
# --------------------------------------------------------------------------
class Frame:
    def __init__(self, lat0: float):
        self.mlat = 111320.0
        self.mlon = 111320.0 * math.cos(math.radians(lat0))

    def xy(self, ll):  # (lat, lon) -> (x, y)
        return (ll[1] * self.mlon, ll[0] * self.mlat)

    def ll(self, p):
        return (p[1] / self.mlat, p[0] / self.mlon)


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


# --------------------------------------------------------------------------
# Geometry ports from the Flutter app
# --------------------------------------------------------------------------
def fit_line(pts):
    """Least-squares principal axis (centroid + unit dir). core/platform_train fitLine."""
    if len(pts) < 2:
        return None
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    cxx = cxy = cyy = 0.0
    for p in pts:
        ddx, ddy = p[0] - cx, p[1] - cy
        cxx += ddx * ddx
        cxy += ddx * ddy
        cyy += ddy * ddy
    tr = cxx + cyy
    l1 = tr / 2 + math.sqrt(max(tr * tr / 4 - (cxx * cyy - cxy * cxy), 0.0))
    if abs(cxy) > 1e-9:
        dx, dy = l1 - cyy, cxy
    else:
        dx, dy = (1.0, 0.0) if cxx >= cyy else (0.0, 1.0)
    nn = math.hypot(dx, dy)
    if nn == 0:
        return None
    return (cx, cy, dx / nn, dy / nn)


def resample(path, n):
    """core/osm_rail _resample: even arc-length resample to n points (lat/lon)."""
    if len(path) < 2:
        return path
    mlon = 111320.0 * math.cos(math.radians(path[0][0]))

    def d(a, b):
        dx = (a[1] - b[1]) * mlon
        dy = (a[0] - b[0]) * 111320.0
        return math.hypot(dx, dy)

    cum = [0.0]
    for i in range(len(path) - 1):
        cum.append(cum[-1] + d(path[i], path[i + 1]))
    total = cum[-1]
    if total <= 0:
        return [path[0], path[-1]]
    out = []
    for k in range(n):
        dd = total * k / (n - 1)
        i = 0
        while i < len(cum) - 2 and cum[i + 1] < dd:
            i += 1
        seg = cum[i + 1] - cum[i]
        f = (dd - cum[i]) / seg if seg > 0 else 0.0
        out.append((path[i][0] + (path[i + 1][0] - path[i][0]) * f,
                    path[i][1] + (path[i + 1][1] - path[i][1]) * f))
    return out


def track_side_edge(poly, ref):
    """core/osm_rail _trackSideEdge: the platform's long edge nearer `ref`.
    With empty ref (no cubes) returns the platform CENTRE-LINE (the mid edge)."""
    loop = list(poly)
    if len(loop) > 1 and loop[0] == loop[-1]:
        loop.pop()
    if len(loop) < 4:
        return poly
    mlon = 111320.0 * math.cos(math.radians(loop[0][0]))

    def xy(p):
        return (p[1] * mlon, p[0] * 111320.0)

    axis = fit_line([xy(p) for p in loop])
    if axis is None:
        return poly
    cx, cy, dx, dy = axis
    ts = [(xy(p)[0] - cx) * dx + (xy(p)[1] - cy) * dy for p in loop]
    iMin = min(range(len(ts)), key=lambda i: ts[i])
    iMax = max(range(len(ts)), key=lambda i: ts[i])

    def arc(a, b):
        out = []
        i = a
        while True:
            out.append(loop[i])
            if i == b:
                break
            i = (i + 1) % len(loop)
        return out

    n = 40
    e1 = resample(arc(iMin, iMax), n)
    e2 = list(reversed(resample(arc(iMax, iMin), n)))
    if len(ref) < 2:
        # No trusted side -> the platform centre-line (mean of the two edges).
        return [((e1[k][0] + e2[k][0]) / 2, (e1[k][1] + e2[k][1]) / 2)
                for k in range(n)]

    def avg(e):
        s = 0.0
        for p in e:
            mn = min(_geo(p, r) for r in ref)
            s += mn
        return s / len(e)

    return e1 if avg(e1) <= avg(e2) else e2


def _geo(a, b):
    """metres between two (lat,lon)."""
    mlon = 111320.0 * math.cos(math.radians(a[0]))
    return math.hypot((a[1] - b[1]) * mlon, (a[0] - b[0]) * 111320.0)


def rail_from_edge(edge, rails):
    """core/osm_rail _railFromEdge: rail vertices within 4 m of the edge,
    ordered by arc-position, 6 m-bin nearest, resampled to 60."""
    if len(edge) < 2 or not rails:
        return []
    mlon = 111320.0 * math.cos(math.radians(edge[0][0]))

    def xy(p):
        return (p[1] * mlon, p[0] * 111320.0)

    exy = [xy(p) for p in edge]

    def on_edge(p):
        best = math.inf
        best_s = 0.0
        acc = 0.0
        for i in range(len(exy) - 1):
            a, b = exy[i], exy[i + 1]
            abx, aby = b[0] - a[0], b[1] - a[1]
            len2 = abx * abx + aby * aby
            t = (((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / len2) if len2 > 0 else 0.0
            t = max(0.0, min(1.0, t))
            proj = (a[0] + abx * t, a[1] + aby * t)
            dd = math.hypot(p[0] - proj[0], p[1] - proj[1])
            if dd < best:
                best = dd
                best_s = acc + math.sqrt(len2) * t
            acc += math.sqrt(len2)
        return best, best_s

    picked = []
    for r in rails:
        for q in r:
            dist, s = on_edge(xy(q))
            if dist <= 4.0:
                picked.append((s, dist, q))
    if len(picked) < 4:
        return []
    picked.sort(key=lambda e: e[0])
    binM = 6.0
    bins = {}
    for s, dist, q in picked:
        b = math.floor(s / binM)
        if b not in bins or dist < bins[b][1]:
            bins[b] = (s, dist, q)
    spine = [bins[b][2] for b in sorted(bins)]
    if len(spine) < 2:
        return []
    return resample(spine, 60)


def osm_rail_for_gleis(platforms, rails, gleis, cube_side):
    """core/osm_rail osmRailForGleis: the real rail spine the train rides."""
    def ref_has(ref):
        for tok in ref.split(";"):
            digits = re.sub(r"[^0-9]", "", tok)
            if digits == gleis:
                return True
        return False

    for ref, pts in platforms:
        if not ref_has(ref):
            continue
        edge = track_side_edge(pts, cube_side)
        rail = rail_from_edge(edge, rails)
        if len(rail) < 2:
            continue
        rp = RoutePath.build(rail)
        if rp is None:
            return rail
        a = rp.locate(edge[0])
        b = rp.locate(edge[-1])
        clipped = rp.slice(min(a, b), max(a, b))
        return clipped if len(clipped) >= 2 else rail
    return []


# --------------------------------------------------------------------------
# RoutePath (arc-length indexed curve) -- core/train_geometry RoutePath
# --------------------------------------------------------------------------
class RoutePath:
    def __init__(self, points, frame, v, cum):
        self.points = points
        self._f = frame
        self._v = v
        self._cum = cum

    @staticmethod
    def build(path):
        pts = _dedupe(path)
        if len(pts) < 2:
            return None
        f = Frame(pts[0][0])
        v = [f.xy(p) for p in pts]
        cum = [0.0]
        for i in range(len(v) - 1):
            cum.append(cum[-1] + _dist(v[i + 1], v[i]))
        return RoutePath(pts, f, v, cum)

    @property
    def length(self):
        return self._cum[-1]

    def _at(self, d):
        if d <= 0:
            return self._v[0]
        if d >= self._cum[-1]:
            return self._v[-1]
        lo, hi = 0, len(self._cum) - 1
        while lo + 1 < hi:
            mid = (lo + hi) >> 1
            if self._cum[mid] <= d:
                lo = mid
            else:
                hi = mid
        seg = self._cum[hi] - self._cum[lo]
        t = (d - self._cum[lo]) / seg if seg > 0 else 0.0
        return (self._v[lo][0] + (self._v[hi][0] - self._v[lo][0]) * t,
                self._v[lo][1] + (self._v[hi][1] - self._v[lo][1]) * t)

    def locate(self, ll):
        pp = self._f.xy(ll)
        best, best_arc = math.inf, 0.0
        for i in range(len(self._v) - 1):
            a, b = self._v[i], self._v[i + 1]
            abx, aby = b[0] - a[0], b[1] - a[1]
            len2 = abx * abx + aby * aby
            t = (((pp[0] - a[0]) * abx + (pp[1] - a[1]) * aby) / len2) if len2 > 0 else 0.0
            t = max(0.0, min(1.0, t))
            proj = (a[0] + abx * t, a[1] + aby * t)
            d = math.hypot(pp[0] - proj[0], pp[1] - proj[1])
            if d < best:
                best = d
                best_arc = self._cum[i] + math.sqrt(len2) * t
        return best_arc

    def slice(self, startM, endM):
        if endM < startM:
            startM, endM = endM, startM
        total = self._cum[-1]
        if total <= 0:
            return [self.points[0], self.points[-1]]
        startM = max(0.0, min(total, startM))
        endM = max(0.0, min(total, endM))
        out = [self._at(startM)]
        for i in range(len(self._cum)):
            if startM < self._cum[i] < endM:
                out.append(self._v[i])
        out.append(self._at(endM))
        return [self._f.ll(q) for q in out]


def _dedupe(pts):
    out = []
    for p in pts:
        if (not out or abs(out[-1][0] - p[0]) > 1e-9
                or abs(out[-1][1] - p[1]) > 1e-9):
            out.append(p)
    return out


# --------------------------------------------------------------------------
# TrainGeometry.body -- the coach outline. We only need the CENTRE-LINE samples
# for the metric, so body() here returns the spine samples (the body hugs them
# +/- halfwidth; the centre-line is what must lie on the rail).
# --------------------------------------------------------------------------
def coach_centreline(spine):
    return _dedupe(spine)


# --------------------------------------------------------------------------
# Off-rail metric
# --------------------------------------------------------------------------
def perp_to_rails(ll, rails_xy, frame):
    """Min perpendicular distance (m) from point ll to any rail segment."""
    p = frame.xy(ll)
    best = math.inf
    for seg in rails_xy:
        for i in range(len(seg) - 1):
            a, b = seg[i], seg[i + 1]
            abx, aby = b[0] - a[0], b[1] - a[1]
            len2 = abx * abx + aby * aby
            t = (((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / len2) if len2 > 0 else 0.0
            t = max(0.0, min(1.0, t))
            proj = (a[0] + abx * t, a[1] + aby * t)
            d = math.hypot(p[0] - proj[0], p[1] - proj[1])
            if d < best:
                best = d
    return best


def gleis_rails(platforms, rails, gleis):
    """The rail segments belonging to this Gleis: every rail within 4 m of the
    Gleis platform's track-side edge -- the same gather core/osm_rail uses to
    decide which rail the train rides. Used as the metric's ground truth."""
    def ref_has(ref):
        return any(re.sub(r"[^0-9]", "", t) == gleis for t in ref.split(";"))

    edge = None
    for ref, pts in platforms:
        if ref_has(ref):
            edge = track_side_edge(pts, [])  # centre-line; we just need proximity
            break
    if edge is None:
        return rails
    mlon = 111320.0 * math.cos(math.radians(edge[0][0]))

    def xy(p):
        return (p[1] * mlon, p[0] * 111320.0)

    exy = [xy(p) for p in edge]

    def near_edge(q):
        qx = xy(q)
        for i in range(len(exy) - 1):
            a, b = exy[i], exy[i + 1]
            abx, aby = b[0] - a[0], b[1] - a[1]
            len2 = abx * abx + aby * aby
            t = (((qx[0] - a[0]) * abx + (qx[1] - a[1]) * aby) / len2) if len2 > 0 else 0.0
            t = max(0.0, min(1.0, t))
            proj = (a[0] + abx * t, a[1] + aby * t)
            if math.hypot(qx[0] - proj[0], qx[1] - proj[1]) <= 6.0:
                return True
        return False

    out = []
    for r in rails:
        kept = [q for q in r if near_edge(q)]
        if len(kept) >= 2:
            out.append(kept)
    return out or rails


def stats(values):
    if not values:
        return None
    vs = sorted(values)
    mean = sum(vs) / len(vs)
    p95 = vs[min(len(vs) - 1, int(round(0.95 * (len(vs) - 1))))]
    return {"mean": mean, "max": vs[-1], "p95": p95, "n": len(vs)}


# --------------------------------------------------------------------------
# Data fetch
# --------------------------------------------------------------------------
def fetch_osm(lat, lon):
    r = 600.0
    dlat = r / 111320.0
    dlon = r / (111320.0 * math.cos(math.radians(lat)))
    bbox = f"{lat - dlat},{lon - dlon},{lat + dlat},{lon + dlon}"
    ql = ("[out:json][timeout:25];("
          f'way["public_transport"="platform"]["ref"]({bbox});'
          f'relation["public_transport"="platform"]["ref"]({bbox});'
          f'way["railway"="rail"]({bbox});'
          ");out geom;")
    body = None
    for ep in OVERPASS_ENDPOINTS:
        try:
            st, raw = _post(ep, {"data": ql},
                            {"User-Agent": OVERPASS_UA, "Accept": "*/*"})
            if st == 200:
                body = raw
                break
        except Exception:
            continue
    if body is None:
        raise RuntimeError("all Overpass mirrors unavailable")
    els = json.loads(body).get("elements", [])
    platforms = []
    rails = []
    for el in els:
        tags = el.get("tags") or {}
        if tags.get("railway") == "rail":
            pts = [(g["lat"], g["lon"]) for g in (el.get("geometry") or [])
                   if "lat" in g and "lon" in g]
            if len(pts) >= 2:
                rails.append(pts)
        elif tags.get("public_transport") == "platform" and tags.get("ref"):
            if el.get("type") == "relation":
                ways = [[(g["lat"], g["lon"]) for g in (m.get("geometry") or [])
                         if "lat" in g and "lon" in g]
                        for m in (el.get("members") or []) if m.get("type") == "way"]
                pts = stitch_ring(ways)
            else:
                pts = [(g["lat"], g["lon"]) for g in (el.get("geometry") or [])
                       if "lat" in g and "lon" in g]
            if len(pts) >= 2:
                platforms.append((tags["ref"], pts))
    return platforms, rails


def stitch_ring(ways):
    """services/osm_platform_service _stitchRing."""
    segs = [list(w) for w in ways if len(w) >= 2]
    if not segs:
        return []

    def near(a, b):
        return abs(a[0] - b[0]) < 1e-7 and abs(a[1] - b[1]) < 1e-7

    chain = segs.pop(0)
    changed = True
    while segs and changed:
        changed = False
        for i, w in enumerate(segs):
            if near(w[0], chain[-1]):
                chain += w[1:]
            elif near(w[-1], chain[-1]):
                chain += list(reversed(w))[1:]
            elif near(w[-1], chain[0]):
                chain = w[:-1] + chain
            elif near(w[0], chain[0]):
                chain = list(reversed(w[1:])) + chain
            else:
                continue
            segs.pop(i)
            changed = True
            break
    return chain


def fetch_bahnhof_cubes(slug):
    """bahnhof.de RSC map -> {level -> [(letter, (lat,lon))]} sector cubes and
    PLATFORM POIs. Returns (cubes, platforms, anchors)."""
    st, raw = _get(f"https://www.bahnhof.de/{slug}/karte",
                   {"User-Agent": BROWSER_UA, "Accept": "*/*", "RSC": "1"})
    if st != 200:
        return [], [], []
    t = raw.decode("utf-8", "replace")
    poi = extract_poi_object(t)
    cubes, platforms = [], []
    if poi:
        for cat, feats in poi.items():
            if not isinstance(feats, list):
                continue
            for f in feats:
                if not isinstance(f, dict):
                    continue
                props = f.get("properties") or {}
                geom = f.get("geometry") or {}
                coords = geom.get("coordinates") or []
                if len(coords) < 2:
                    continue
                lon, lat = float(coords[0]), float(coords[1])
                typ = props.get("type") or cat
                name = props.get("name") or ""
                lvl = props.get("level")
                if typ == "PLATFORM_SECTOR_CUBE":
                    cubes.append((name, lat, lon, lvl))
                elif typ == "PLATFORM":
                    platforms.append((name, lat, lon, lvl))
    return cubes, platforms, []


def extract_poi_object(blob):
    """Balance-parse the "poi":{...} object (mirrors station_map_service)."""
    m = re.search(r'"poi":\{"[A-Z]', blob)
    if not m:
        return None
    open_i = blob.index("{", m.start())
    depth = 0
    in_str = False
    esc = False
    for i in range(open_i, len(blob)):
        c = blob[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(blob[open_i:i + 1])
                except Exception:
                    return None
    return None


def fetch_wagenreihung(eva, date, hhmm, category, number):
    """vehicle-sequence. Returns (sectors, coaches) or (None, None) on 404."""
    local_iso = f"{date}T{hhmm}:00"
    dt = datetime.fromisoformat(local_iso) - timedelta(hours=2)  # local Berlin DST
    utc = dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    params = urllib.parse.urlencode({
        "administrationId": "80", "category": category, "date": date,
        "evaNumber": eva, "number": number, "time": utc,
    })
    st, raw = _get(
        "https://www.bahn.de/web/api/reisebegleitung/wagenreihung/"
        "vehicle-sequence?" + params,
        {"User-Agent": BROWSER_UA, "Accept": "application/json",
         "Accept-Language": "de-DE,de;q=0.9"})
    if st != 200:
        return None, None, st
    j = json.loads(raw)
    plat = j.get("platform") or {}
    sectors = [(s["name"], s["start"], s["end"]) for s in plat.get("sectors", [])]
    coaches = []
    for g in j.get("groups", []):
        for v in g.get("vehicles", []):
            pp = v.get("platformPosition") or {}
            if (pp.get("end", 0) - pp.get("start", 0)) > 0:
                coaches.append((pp.get("sector", ""), pp["start"], pp["end"]))
    if not sectors or not coaches:
        return None, None, st
    return sectors, coaches, st


# --------------------------------------------------------------------------
# Placement methods
# --------------------------------------------------------------------------
def cube_letter(name):
    t = name.strip().upper()
    if len(t) == 1 and "A" <= t <= "I":
        return ord(t) - ord("A")
    return None


def resolve_cubes_for_gleis(cubes, platforms, gleis):
    """Simplified resolveIsland: pick the nearest PLATFORM POI for this Gleis,
    then take the sector cubes on its level nearest that platform. Returns a
    list of (letter_idx, (lat,lon)) ordered A->I. Empty if <2 cubes -> current
    method cannot place a train (the production guard)."""
    def norm(n):
        n = n.strip()
        m = re.match(r"^\d+", n)
        return m.group(0) if m else n.split()[0].upper() if n else n

    plat = next((p for p in platforms if norm(p[0]) == gleis), None)
    if plat is None:
        return []
    plvl = plat[3]
    lvl_cubes = [c for c in cubes if c[3] == plvl]
    if len(lvl_cubes) < 2:
        # fall back to wherever the most cubes live (track level)
        by = {}
        for c in cubes:
            by.setdefault(c[3], []).append(c)
        if by:
            lvl_cubes = max(by.values(), key=len)
    if len(lvl_cubes) < 2:
        return []
    # nearest cube per letter to the platform POI
    by_letter = {}
    for name, lat, lon, _ in lvl_cubes:
        li = cube_letter(name)
        if li is None:
            continue
        d = _geo((lat, lon), (plat[1], plat[2]))
        if li not in by_letter or d < by_letter[li][0]:
            by_letter[li] = (d, (lat, lon))
    out = [(li, by_letter[li][1]) for li in sorted(by_letter)]
    return out


def place_current(platforms_osm, rails_osm, gleis, cubes, plat_pois,
                  sectors, coaches):
    """Method A: cube-anchored LSQ onto OSM rail spine. Returns
    (coach_centrelines, note)."""
    resolved = resolve_cubes_for_gleis(cubes, plat_pois, gleis)
    if len(resolved) < 2:
        return [], f"<2 sector cubes for Gleis {gleis} -> CANNOT place a train"
    cube_side = [pos for _, pos in resolved]
    rail = osm_rail_for_gleis(platforms_osm, rails_osm, gleis, cube_side)
    if len(rail) < 2:
        return [], "no OSM rail spine recovered"
    curve = RoutePath.build(rail)
    if curve is None:
        return [], "degenerate curve"
    # sector metre-offset -> arc anchors
    anchors = []
    for name, s, e in sectors:
        li = cube_letter(name)
        if li is None:
            continue
        match = next((pos for cl, pos in resolved if cl == li), None)
        if match is None:
            continue
        anchors.append(((s + e) / 2, curve.locate(match)))
    if len(anchors) < 2:
        return [], (f"<2 sector->cube anchors (sectors "
                    f"{[s[0] for s in sectors]}, cubes "
                    f"{[chr(65 + cl) for cl, _ in resolved]})")
    n = len(anchors)
    sx = sum(a[0] for a in anchors)
    sy = sum(a[1] for a in anchors)
    sxx = sum(a[0] * a[0] for a in anchors)
    sxy = sum(a[0] * a[1] for a in anchors)
    denom = n * sxx - sx * sx
    if abs(denom) < 1e-9:
        return [], "LSQ denom ~0"
    slope = (n * sxy - sx * sy) / denom
    intercept = (sy - slope * sx) / n
    def arc_of(off):
        return slope * off + intercept
    cls = []
    for _, cs, ce in coaches:
        spine = curve.slice(arc_of(cs), arc_of(ce))
        cls.append(coach_centreline(spine))
    return cls, f"placed {len(cls)} coaches via {len(anchors)} cube anchors"


def place_direct_osm(platforms_osm, rails_osm, gleis, sectors, coaches):
    """Method B: place purely from OSM. Recover the rail spine for the Gleis
    WITHOUT cubes (centre-line edge), centre the train on the rail mid-span,
    slice coaches by their metre offsets. Returns (coach_centrelines, note)."""
    rail = osm_rail_for_gleis(platforms_osm, rails_osm, gleis, [])
    if len(rail) < 2:
        return [], "no OSM rail spine recovered"
    curve = RoutePath.build(rail)
    if curve is None:
        return [], "degenerate curve"
    # Train extent from the coach metre offsets; centre it on the rail mid-point.
    lo = min(c[1] for c in coaches)
    hi = max(c[2] for c in coaches)
    train_len = hi - lo
    start_arc = max(0.0, curve.length / 2 - train_len / 2)
    cls = []
    for _, cs, ce in coaches:
        a0 = start_arc + (cs - lo)
        a1 = start_arc + (ce - lo)
        spine = curve.slice(a0, a1)
        cls.append(coach_centreline(spine))
    return cls, f"placed {len(cls)} coaches centred on OSM rail (len {curve.length:.0f} m)"


# --------------------------------------------------------------------------
# Evaluate one (station, gleis)
# --------------------------------------------------------------------------
def evaluate(label, osm_ll, slug, gleis, sectors, coaches, wr_note):
    print(f"\n{'='*72}\n{label}  (Gleis {gleis})\n{'='*72}")
    platforms_osm, rails_osm = fetch_osm(*osm_ll)
    print(f"  OSM: {len(platforms_osm)} platform refs "
          f"{[p[0] for p in platforms_osm][:6]}, {len(rails_osm)} rail ways")
    cubes, plat_pois, _ = fetch_bahnhof_cubes(slug)
    print(f"  bahnhof.de '{slug}': {len(cubes)} sector cubes, "
          f"{len(plat_pois)} PLATFORM pois {[p[0] for p in plat_pois][:8]}")
    print(f"  Wagenreihung: {wr_note}")

    # Ground-truth rails for this Gleis, projected once.
    grails = gleis_rails(platforms_osm, rails_osm, gleis)
    frame = Frame(osm_ll[0])
    rails_xy = [[frame.xy(p) for p in seg] for seg in grails]

    results = {}
    for mname, fn in [
        ("A CURRENT (cube-anchored LSQ)",
         lambda: place_current(platforms_osm, rails_osm, gleis, cubes,
                               plat_pois, sectors, coaches)),
        ("B DIRECT-OSM",
         lambda: place_direct_osm(platforms_osm, rails_osm, gleis, sectors,
                                  coaches)),
    ]:
        cls, note = fn()
        all_d = []
        off_rail_coaches = 0
        for coach in cls:
            ds = [perp_to_rails(ll, rails_xy, frame) for ll in coach]
            all_d += ds
            if ds and max(ds) > 2.5:
                off_rail_coaches += 1
        s = stats(all_d)
        results[mname] = (s, note, off_rail_coaches, len(cls))
        if s:
            print(f"\n  {mname}")
            print(f"    {note}")
            print(f"    off-rail dist (m): mean={s['mean']:.2f}  "
                  f"p95={s['p95']:.2f}  max={s['max']:.2f}  "
                  f"({s['n']} centre-line points)")
            print(f"    coaches straying >2.5 m off-rail: "
                  f"{off_rail_coaches}/{len(cls)}")
        else:
            print(f"\n  {mname}\n    {note}\n    (no train placed -> no metric)")
    return results


def verdict(label, results):
    a = results.get("A CURRENT (cube-anchored LSQ)")
    b = results.get("B DIRECT-OSM")
    print(f"\n  VERDICT [{label}]:")
    sa = a[0] if a else None
    sb = b[0] if b else None
    if sa is None and sb is not None:
        print(f"    CURRENT could not place a train ({a[1]}); DIRECT-OSM did, "
              f"mean {sb['mean']:.2f} m / max {sb['max']:.2f} m off-rail. "
              f"DIRECT-OSM is strictly better here (current draws nothing).")
    elif sa is not None and sb is not None:
        diff = sa['mean'] - sb['mean']
        better = "DIRECT-OSM" if diff > 0 else "CURRENT"
        print(f"    CURRENT mean {sa['mean']:.2f} m / max {sa['max']:.2f} m;  "
              f"DIRECT-OSM mean {sb['mean']:.2f} m / max {sb['max']:.2f} m.")
        print(f"    {better} is better by {abs(diff):.2f} m mean off-rail.")
    elif sa is not None:
        print(f"    only CURRENT placed a train (mean {sa['mean']:.2f} m).")
    else:
        print("    neither method placed a train.")


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    default_date = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
    ap.add_argument("--date", default=default_date,
                    help="YYYY-MM-DD the train runs (default: tomorrow)")
    args = ap.parse_args()
    date = args.date

    print(f"Besser-Bahn train-on-rails comparison — {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}")
    print(f"Test train: {TRAIN_CATEGORY} {TRAIN_NUMBER} Kiel Hbf Gl 1 22:43 -> "
          f"Raisdorf Gl 1 22:51   (date {date})")

    # --- Wagenreihung: try live (Kiel then Raisdorf), else realistic fallback.
    sectors = coaches = None
    wr_note = ""
    for lbl, eva in [("Kiel Hbf", KIEL_EVA), ("Raisdorf", RAISDORF_EVA)]:
        s, c, st = fetch_wagenreihung(
            eva, date, "22:43" if eva == KIEL_EVA else "22:51",
            TRAIN_CATEGORY, TRAIN_NUMBER)
        if s and c:
            sectors, coaches = s, c
            wr_note = f"live from {lbl} ({len(c)} coaches, {len(s)} sectors)"
            break
        else:
            wr_note = f"vehicle-sequence HTTP {st} at {lbl}"
    if not sectors:
        sectors, coaches = FALLBACK_SECTORS, FALLBACK_COACHES
        wr_note = (f"erixx publishes NO Wagenreihung (last: {wr_note}); "
                   f"using realistic Coradia-LINT fallback "
                   f"({len(coaches)} coaches, {len(sectors)} sectors)")

    all_results = []
    for label, osm_ll, slug, gleis in [
        ("RAISDORF", RAISDORF_LL, "raisdorf", "1"),
        ("KIEL HBF", KIEL_LL, "kiel-hbf", "1"),
    ]:
        try:
            res = evaluate(label, osm_ll, slug, gleis, sectors, coaches, wr_note)
            all_results.append((label, res))
        except Exception as e:
            print(f"\n{label}: ERROR {type(e).__name__}: {e}")

    print(f"\n{'#'*72}\nVERDICTS\n{'#'*72}")
    for label, res in all_results:
        verdict(label, res)
    print()


if __name__ == "__main__":
    main()

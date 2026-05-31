#!/usr/bin/env python3
"""One-off: pull a real Wagenreihung (coach sequence) for a train standing at
Hamburg Hbf **Gleis 7**, saving it as
test/fixtures/hamburg-wagenreihung.json — the offline input for the platform-
train preview (lib/dev/platform_preview.dart).

Same backend the app uses (services/coach_sequence_service.dart):
  GET bahn.de/web/api/reisebegleitung/wagenreihung/vehicle-sequence
The response carries, in metres along the platform:
  platform.{start,end,sectors[{name,start,end}]}  and per vehicle
  platformPosition.{start,end,sector}  ← exactly "coach N occupies metre a..b,
  sector C", which we map onto the OSM rail.

NB the `time` param MUST be ISO-8601 WITH a zone/millis (…Z) — a bare
"YYYY-MM-DDTHH:MM:SS" 500s. We send UTC like the app's toUtc().toIso8601String().
"""
import json
import os
from datetime import datetime, timedelta

import requests

EVA = "8002549"  # Hamburg Hbf
TIMEOUT = 20
HDRS = {
    "User-Agent": ("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"),
    "Accept": "application/json", "Accept-Language": "de-DE,de;q=0.9",
}
FIXTURE = os.path.join(os.path.dirname(__file__),
                       "../flutter-app/test/fixtures/hamburg-wagenreihung.json")


def train_number(journey_id):
    """The Zugnummer (fahrtNr) lives in the journeyId as the `ZE` field —
    `…#ZE#11234#…`. The departure's mittelText ("RE70") is the LINE, not the
    train number, and 400s the sequence API."""
    parts = journey_id.split("#")
    for i, t in enumerate(parts):
        if t == "ZE" and i + 1 < len(parts):
            return parts[i + 1]
    return None


def departures(dt):
    r = requests.get(
        "https://www.bahn.de/web/api/reiseloesung/abfahrten",
        params={"datum": dt.strftime("%Y-%m-%d"), "zeit": dt.strftime("%H:%M:00"),
                "ortExtId": EVA, "mitVias": "false"},
        headers=HDRS, timeout=TIMEOUT)
    r.raise_for_status()
    return r.json().get("entries", [])


def utc_iso(local_iso):
    """bahn.de departures are local Berlin (summer = UTC+2). The sequence API
    wants UTC ISO with millis + Z, matching the app's toUtc().toIso8601String()."""
    dt = datetime.fromisoformat(local_iso) - timedelta(hours=2)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def vehicle_sequence(category, number, local_iso):
    r = requests.get(
        "https://www.bahn.de/web/api/reisebegleitung/wagenreihung/vehicle-sequence",
        params={"administrationId": "80", "category": category,
                "date": local_iso[:10], "evaNumber": EVA,
                "number": str(number), "time": utc_iso(local_iso)},
        headers=HDRS, timeout=TIMEOUT)
    if r.status_code != 200:
        return None
    return r.json()


def main():
    base = datetime.now()
    seen = set()
    for h in range(0, 24):
        for x in departures(base + timedelta(hours=h)):
            gleis = str(x.get("gleis") or "")
            if not gleis.startswith("7"):  # "7", "7A-D", "7G-I" …
                continue
            vm = x.get("verkehrmittel") or {}
            cat = (vm.get("kurzText") or "").strip()
            num = train_number(x.get("journeyId", ""))
            key = (cat, num, x["zeit"])
            if not cat or not num or not num.isdigit() or key in seen:
                continue
            seen.add(key)
            js = vehicle_sequence(cat, num, x["zeit"])
            if not js:
                continue
            plat = js.get("platform") or {}
            if not plat.get("sectors"):
                continue
            print(f"FOUND {cat} {num} @ Gleis {gleis} ({x['zeit']})")
            print("  platform:", {k: plat.get(k) for k in ("name", "start", "end")})
            print("  sectors:", [(s["name"], round(s["start"], 1), round(s["end"], 1))
                                 for s in plat["sectors"]])
            for gr in js.get("groups", []):
                t = gr.get("transport") or {}
                print(f"  group {gr.get('name')} {t.get('category')} {t.get('number')} "
                      f"({len(gr.get('vehicles') or [])} vehicles)")
                for v in (gr.get("vehicles") or []):
                    pp = v.get("platformPosition") or {}
                    print(f"    wagon {v.get('wagonIdentificationNumber')} "
                          f"sec {pp.get('sector')} {round(pp.get('start', 0), 1)}.."
                          f"{round(pp.get('end', 0), 1)} m "
                          f"{(v.get('type') or {}).get('category')}")
            with open(FIXTURE, "w") as f:
                json.dump(js, f, ensure_ascii=False)
            print("saved", FIXTURE)
            return
    print("no Gleis-7 train with a coach sequence in the next 24 h")


if __name__ == "__main__":
    main()

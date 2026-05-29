"""Throwaway: for the RE7 Kiel->Hamburg leg, what destinations do the
Wagenreihung coach groups carry? If they're all the SAME (merge southbound),
our new `splits` getter is false and the red banner is correctly suppressed."""
import json
import uuid
from datetime import datetime

import requests

KIEL = "A=1@O=Kiel Hbf@X=10131976@Y=54314982@U=80@L=8000199@B=1@p=0@"
BERLIN = "A=1@O=Berlin Hbf@X=13369549@Y=52525589@U=80@L=8011160@B=1@p=0@"
UA = "DBNavigator/Android/26.9.0"


def vh(media):
    return {"Accept": media, "Content-Type": media, "Accept-Language": "de",
            "User-Agent": UA, "X-App-Version": "26.9.0",
            "X-Correlation-ID": f"{uuid.uuid4()}_{uuid.uuid4()}"}


def journey():
    media = "application/x.db.vendo.mob.verbindungssuche.v9+json"
    body = {"autonomeReservierung": False, "einstiegsTypList": ["STANDARD"],
            "fahrverguenstigungen": {"deutschlandTicketVorhanden": False,
                                     "nurDeutschlandTicketVerbindungen": False},
            "klasse": "KLASSE_2",
            "reiseHin": {"wunsch": {"abgangsLocationId": KIEL,
                                    "alternativeHalteBerechnung": True,
                                    "verkehrsmittel": ["ALL"],
                                    "zeitWunsch": {"reiseDatum": datetime.now().astimezone().isoformat(),
                                                   "zeitPunktArt": "ABFAHRT"},
                                    "zielLocationId": BERLIN}},
            "reisendenProfil": {"reisende": [{"ermaessigungen": ["KEINE_ERMAESSIGUNG KLASSENLOS"],
                                              "reisendenTyp": "ERWACHSENER"}]},
            "reservierungsKontingenteVorhanden": False}
    r = requests.post("https://app.services-bahn.de/mob/angebote/fahrplan",
                      headers=vh(media), data=json.dumps(body), timeout=20)
    r.raise_for_status()
    return r.json().get("verbindungen", [])


def wagenreihung(cat, number, eva, t):
    r = requests.get("https://www.bahn.de/web/api/reisebegleitung/wagenreihung/vehicle-sequence",
                     params={"administrationId": "80", "category": cat, "date": t[:10],
                             "evaNumber": eva, "number": str(number), "time": t},
                     headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"}, timeout=20)
    return r.status_code, (r.json() if r.status_code == 200 else r.text[:120])


def main():
    for c in journey()[:3]:
        legs = c["verbindung"]["verbindungsAbschnitte"]
        first = legs[0]
        vm = first.get("verkehrsmittel", {})
        cat = vm.get("produktGattung") or vm.get("kategorie") or ""
        line = vm.get("name") or vm.get("mitteltext") or ""
        nr = vm.get("nummer") or vm.get("fahrtNr") or ""
        halt = first.get("halte", [{}])[0]
        eva = halt.get("extId") or (first.get("abgangsOrt", {}) or {}).get("extId")
        dep = (halt.get("abfahrtsZeitpunkt") or halt.get("abfahrtZeitpunkt")
               or first.get("abfahrtsZeitpunkt"))
        print(f"\nleg0 line={line!r} cat={cat!r} nr={nr!r} eva={eva} dep={dep}")
        if not (cat and nr and eva and dep):
            print("   (missing fields, dumping vm keys:", list(vm.keys()), ")")
            continue
        st, data = wagenreihung(cat, nr, eva, dep)
        if st != 200:
            print(f"   wagenreihung HTTP {st}: {data}")
            continue
        groups = data.get("groups", [])
        dests = [(g.get("transport", {}) or {}).get("destination", {}) for g in groups]
        names = [(d or {}).get("name") for d in dests]
        print(f"   groups={len(groups)} destinations={names}")
        print(f"   -> distinct non-empty = {len(set(n for n in names if n))}  => splits={len(set(n for n in names if n))>1}")


if __name__ == "__main__":
    main()

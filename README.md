# Besser Bahn

**Die bessere Bahn-App. Privacy-first, für Vielfahrer.**

Ein Premium-Begleiter für die Deutsche Bahn: Verbindungssuche, Live-Abfahrten,
Zugläufe auf der Karte, Verspätungs- und Anschluss-Vorhersage, Träwelling-Check-ins
und das Finden günstigerer Split-Tickets — alles ohne Tracking, ohne Werbung,
ohne Konto-Zwang.

Optional lässt sich das **eigene DB-Konto verbinden** — dann liegen **Tickets
(inkl. Barcode zum Vorzeigen), BahnCard und BahnBonus** direkt in der App.

<p align="center">
  <img src="assets/app_icon.png" width="100" />
</p>

## Funktionen

### 🔎 Suche
- Verbindungssuche zwischen zwei Stationen mit Stationsautovervollständigung
- Mehrteilige Verbindungsdetails: alle Umstiege, Gleise, Halte und Echtzeit-Verspätungen
- **Anschluss- und Pünktlichkeits-Badges** je Umstieg, berechnet von einem
  selbst gehosteten Vorhersage-Modell

### 🚉 Bahnhof
Ein kombinierter Tab mit interner Umschaltung zwischen:
- **Zug** – Zuglauf einer einzelnen Fahrt mit allen Halten, Gleisen und Verspätungen
- **Abfahrten** – Live-Abfahrtstafel eines Bahnhofs, inklusive Kartenansicht
- **Karte** – interaktive Bahnhofskarte (Bahnsteige, Aufzüge, POIs)

### 🧭 Karten & Live-Daten
- Streckenverlauf als exakte Gleis-Polylinie, die die DB selbst zeichnet
- Neutraler deutscher Basemap-Hintergrund (BKG TopPlus-Open, grau)
- Offline-Kachel-Cache auf dem Gerät
- **Wagenreihung & freie Sitzplätze** – Sitzplatzkarte und Wagenreihenfolge je Zug
- **Flügelzug-Erkennung** – zeigt an, in welchen Zugteil man einsteigen muss
- „Mein Standort" und Stationen in der Nähe per GPS

### 💶 Split-Ticket
- Findet günstigere Ticket-Kombinationen für eine gefundene Verbindung
- Berücksichtigt **BahnCard** (25/50, 1./2. Klasse) und **Deutschland-Ticket**
- Direkte Buchungslinks für jedes Teil-Ticket (oberstes Angebot = das richtige)
- OS-Benachrichtigung, sobald die Analyse fertig ist

### 👤 DB-Konto (optional)
Das eigene DB-Konto lässt sich verbinden — die App spricht dann dasselbe
Backend wie der DB Navigator:
- **Meine Tickets** – gebuchte Fahrkarten inklusive **Barcode zum Vorzeigen**
  bei der Kontrolle
- **BahnCard** – Kartenansicht und Kontrollansicht, offline verfügbar
- **BahnBonus** – Punkte- und Statusstand
- **Gemerkte Reisen** synchronisieren mit „Meine Reisen" im DB-Konto
- Login per OAuth2 (PKCE, kein Passwort in der App); komplett optional — ohne
  Konto funktioniert alles andere unverändert

### 🤝 Träwelling
- Login per OAuth2 (PKCE, kein Passwort in der App)
- Per-Bein-Check-in direkt aus der Verbindungsansicht
- Auto-Check-in: ein Tipp auf das Träwelling-Symbol im Zug checkt ein
- Feed & Freunde, einstellbare Standard-Sichtbarkeit

### 📚 Reisen
- Lokale Bibliothek: Favoriten, zuletzt gesucht, gespeicherte Routen und Züge
- Häufige Suchen werden automatisch als Favorit markiert

### 🔗 Teilen
- Offizielles „Reise teilen": erzeugt einen echten DB-Buchungslink für genau
  diese Verbindung (nicht nur eine Suche)

## Datenschutz

- **Kein Tracking, kein Firebase, kein Google Analytics, keine Werbung**
- Suchanfragen, Favoriten und Tokens bleiben auf dem Gerät
- Das Vorhersage-Backend läuft auf Servern in Deutschland (Hetzner, DSGVO-konform)
- Siehe [PRIVACY-POLICY.md](PRIVACY-POLICY.md)

## Installation

### Android
Gehe zur [Releases-Seite](https://github.com/chukfinley/Besser-Bahn/releases)
und lade die neueste Version herunter.

### iOS
Ich besitze weder einen Mac noch ein iOS-Gerät, um die App für iOS zu
kompilieren. Wenn du die App erfolgreich für iOS bauen kannst, melde dich gerne —
ich stelle die iOS-Version dann offiziell hier bereit.

## Wie es funktioniert

Die App nutzt **keine offizielle Endkunden-API** der Deutschen Bahn. Stattdessen
spricht sie bevorzugt das Backend der **DB-Navigator-App** an
(`app.services-bahn.de/mob`), das die echten Fahrplan-, Preis-, Wagenreihungs-
und Streckendaten liefert. Als Rückfallebene dienen die bahn.de-Web-API und ein
öffentlicher HAFAS-Spiegel.

Die **Anschluss- und Pünktlichkeits-Vorhersage** kommt von einem separaten,
selbst gehosteten Dienst (`bahn.chuk.dev`), der ein Verspätungsmodell bereitstellt.

Die Split-Ticket-Logik zerlegt eine Verbindung in alle möglichen Teilstrecken
und findet per dynamischer Programmierung die günstigste Kombination, die die
gesamte Strecke abdeckt — inklusive BahnCard- und Deutschland-Ticket-Rabatten.

## Projektstruktur

| Verzeichnis          | Inhalt                                                        |
| -------------------- | ------------------------------------------------------------- |
| `flutter-app/`       | Die App (Flutter, Riverpod, GoRouter)                         |
| `prediction-service/`| Selbst gehostete Verspätungs-/Anschluss-Vorhersage-API        |
| `api-tests/`         | Health-Checks für alle genutzten Upstream-Endpunkte           |
| `docs/`              | Projekt-Webseite                                              |
| `main.py`            | Split-Ticket-Logik auch als eigenständiges Python-CLI         |

## Development

### App bauen

```bash
git clone https://github.com/chukfinley/Besser-Bahn
cd Besser-Bahn/flutter-app
flutter pub get
flutter run
```

Voraussetzung: Flutter (SDK ^3.10) auf dem System installiert.

### Endpunkt-Health-Check

Vor Arbeiten an Netzwerk-/Datencode prüft `api-tests/healthcheck.py`, ob alle
Upstream-Endpunkte noch die erwartete Antwortform liefern:

```bash
cd api-tests && python3 healthcheck.py
```

### Split-Ticket als CLI

Die Split-Ticket-Analyse läuft auch ohne App:

```bash
uv run main.py "https://www.bahn.de/buchung/start?vbid=..." [--age 30] [--bahncard BC25_2] [--deutschland-ticket]
```

## Empfohlene Open-Source Bahn-Projekte und Tools

*   **Traewelldroid** – Check-in-App für ÖPNV/Fernverkehr in Europa, basiert auf
    Open-Data-Schnittstellen.
    [GitHub](https://github.com/Traewelldroid/traewelldroid)
*   **Transportr** – quelloffene ÖPNV-App für viele Regionen weltweit.
    [GitHub](https://github.com/grote/Transportr)
*   **OpenRailwayMap** – detaillierte interaktive Karte des weltweiten
    Eisenbahnnetzes auf OSM-Basis. [Website](https://openrailwaymap.org/)
*   **bahn.expert** – tiefe Analyse von Zugverbindungen, Verspätungen und
    Pünktlichkeitsstatistiken. [Website](https://bahn.expert/)

## Datenschutz im Bahnverkehr

Organisationen wie Digitalcourage setzen sich für Transparenz und Nutzerrechte ein:

*   **Klage gegen die Deutsche Bahn wegen Datenerfassung im DB Navigator** –
    Digitalcourage hat die DB verklagt, weil der „DB Navigator" persönliche Daten
    ohne ausreichende Einwilligung weitergibt.
    [Details bei Digitalcourage](https://digitalcourage.de/pressemitteilungen/2025/bahn-klage-termin)

## Spenden

Wenn diese App dir hilft, bei deinen Bahnreisen Geld zu sparen, freue ich mich
über eine Spende — sie sichert Weiterentwicklung und Wartung. Die
Spendenmöglichkeiten findest du über den „Sponsor"-Button oben auf dieser
GitHub-Seite.

## Beitragen

Beiträge sind willkommen! Öffne ein Issue oder einen Pull Request, wenn du
Verbesserungen vorschlagen möchtest.

## Lizenz

Lizenziert unter der DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE — siehe
[LICENSE.txt](LICENSE.txt).

## Haftungsausschluss

Diese App ist ein inoffizielles Projekt und steht in keiner Verbindung zur
Deutschen Bahn AG. Die Nutzung erfolgt auf eigene Gefahr. Die gefundenen
Split-Tickets entsprechen den Beförderungsbedingungen der Deutschen Bahn.

## Danksagung

Großer Dank an Lukas Weihrauch und sein Video, das die Inspiration für dieses
Projekt lieferte: [https://youtu.be/SxKtI8f5QTU](https://youtu.be/SxKtI8f5QTU)

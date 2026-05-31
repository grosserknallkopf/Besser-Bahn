import '../models/journey.dart';

/// German short weekday names (Mon=1 … Sun=7), as DB writes them ("Fr.").
const _weekdayDe = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];

String _hhmm(DateTime? t) {
  if (t == null) return '';
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// Train label as the DB Navigator app prints it. DB only parenthesises the
/// train number when the line itself is numbered ("RE7 (11283)", "S1 (…)");
/// for category-only services the number is appended with a space ("ICE 705").
String _lineLabel(JourneyLeg leg) {
  final name = leg.line?.name.trim() ?? '';
  final nr = leg.line?.fahrtNr.trim() ?? '';
  if (name.isEmpty) return leg.line?.displayName ?? 'Zug';
  if (nr.isEmpty || name.contains(nr)) return name;
  // Line carries its own number (RE7, RB33, S1) → "name (nr)"; pure category
  // (ICE, IC, EC) → "name nr".
  return name.contains(RegExp(r'\d')) ? '$name ($nr)' : '$name $nr';
}

/// Rich "Reise teilen" text mirroring the official DB Navigator share: route,
/// date, each train (label · direction · Ab/An with platform), then the bahn.de
/// vbid deep link. Example:
///
///   Kiel Hbf → Berlin Hbf
///   Fr. 29.05.2026
///
///   RE7 (11283)
///   Nach Neumünster
///   Ab 19:05 Kiel Hbf, Gleis 4
///   An 20:22 Hamburg Hbf, Gleis 7G-I
///
///   ICE 705
///   …
///
///   Verbindung ansehen: https://www.bahn.de/buchung/start?vbid=…
String journeyShareText(Journey journey, String link) {
  final o = journey.origin?.name ?? '';
  final d = journey.destination?.name ?? '';
  final dep = (journey.plannedDeparture ?? journey.departure)?.toLocal();

  final b = StringBuffer()..writeln('$o → $d');
  if (dep != null) {
    b.writeln('${_weekdayDe[dep.weekday - 1]} '
        '${dep.day.toString().padLeft(2, '0')}.'
        '${dep.month.toString().padLeft(2, '0')}.${dep.year}');
  }

  for (final leg in journey.legs.where((l) => !l.isWalking)) {
    b.writeln();
    b.writeln(_lineLabel(leg));
    final dir = leg.direction?.trim();
    if (dir != null && dir.isNotEmpty) b.writeln('Nach $dir');
    final abG =
        leg.departurePlatform != null ? ', Gleis ${leg.departurePlatform}' : '';
    final anG =
        leg.arrivalPlatform != null ? ', Gleis ${leg.arrivalPlatform}' : '';
    b.writeln('Ab ${_hhmm(leg.departure ?? leg.plannedDeparture)} '
        '${leg.origin.name}$abG');
    b.writeln('An ${_hhmm(leg.arrival ?? leg.plannedArrival)} '
        '${leg.destination.name}$anG');
  }

  b..writeln()..write('Verbindung ansehen: $link');
  return b.toString();
}

/// Arrival-focused "ETA für Abholer" message: where to, when you arrive (with
/// platform + delay) and a live link to follow the train. Short and skimmable —
/// meant for the person picking you up, not a full itinerary.
///
///   🚆 Ich komme nach Berlin Hbf
///   Ankunft ~20:22, Gleis 7 (ICE 705)
///   +6 Min später als geplant
///   Live verfolgen: https://www.bahn.de/buchung/start?vbid=…
String etaShareText(Journey journey, String link) {
  final d = journey.destination?.name ?? 'Ziel';
  final transit = journey.legs.where((l) => !l.isWalking).toList();
  final last = transit.isEmpty ? null : transit.last;
  final arr = last?.arrival ?? last?.plannedArrival;
  final plat = last?.arrivalPlatform ?? last?.plannedArrivalPlatform;
  final line = last?.line?.displayName;
  final delay = last?.arrivalDelayMinutes ?? 0;

  final b = StringBuffer()..writeln('🚆 Ich komme nach $d');
  if (arr != null) {
    b.writeln('Ankunft ~${_hhmm(arr)}'
        '${plat != null ? ', Gleis $plat' : ''}'
        '${line != null ? ' ($line)' : ''}');
  }
  if (delay > 0) b.writeln('+$delay Min später als geplant');
  b.write('Live verfolgen: $link');
  return b.toString();
}

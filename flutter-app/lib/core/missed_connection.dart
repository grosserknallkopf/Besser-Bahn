import 'dart:convert';

import '../models/journey.dart';
import '../models/station.dart';

/// Everything needed to restart the journey from the missed boarding point.
/// It is small enough to travel as a notification payload and contains no
/// account or ticket data.
class MissedConnectionRescue {
  final Station from;
  final Station to;
  final DateTime scheduledDeparture;
  final int legIndex;
  final bool isConnection;

  const MissedConnectionRescue({
    required this.from,
    required this.to,
    required this.scheduledDeparture,
    required this.legIndex,
    required this.isConnection,
  });

  String get label => isConnection ? 'Anschluss verpasst' : 'Zug verpasst';

  Map<String, dynamic> toJson() => {
    'from': from.toJson(),
    'to': to.toJson(),
    'departure': scheduledDeparture.toIso8601String(),
    'legIndex': legIndex,
    'connection': isConnection,
  };

  String encode() => jsonEncode(toJson());

  factory MissedConnectionRescue.fromJson(Map<String, dynamic> json) =>
      MissedConnectionRescue(
        from: Station.fromJson(json['from'] as Map<String, dynamic>? ?? {}),
        to: Station.fromJson(json['to'] as Map<String, dynamic>? ?? {}),
        scheduledDeparture: DateTime.parse(json['departure'] as String),
        legIndex: (json['legIndex'] as num?)?.toInt() ?? 0,
        isConnection: json['connection'] as bool? ?? false,
      );

  factory MissedConnectionRescue.decode(String raw) =>
      MissedConnectionRescue.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// The train/connection that can plausibly be missed right now. Starts
  /// shortly before departure so a rider who already knows they cannot make it
  /// can reroute without waiting for the timetable to tick past zero.
  static MissedConnectionRescue? forJourney(Journey journey, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final destination = journey.destination;
    if (destination == null || destination.vendoLocationId.isEmpty) return null;

    final candidates = <MissedConnectionRescue>[];
    var transitIndex = 0;
    for (final leg in journey.legs.where((l) => !l.isWalking)) {
      final departure = leg.departure ?? leg.plannedDeparture;
      final index = transitIndex++;
      if (departure == null || leg.origin.vendoLocationId.isEmpty) continue;
      if (current.isBefore(departure.subtract(const Duration(minutes: 30))) ||
          current.isAfter(departure.add(const Duration(minutes: 90)))) {
        continue;
      }
      candidates.add(
        MissedConnectionRescue(
          from: leg.origin,
          to: destination,
          scheduledDeparture: departure,
          legIndex: index,
          isConnection: index > 0,
        ),
      );
    }
    if (candidates.isEmpty) return null;

    // Prefer the most recently due train. Up to ten minutes before departure,
    // that upcoming train is already the actionable one.
    candidates.sort((a, b) {
      final aDue = !a.scheduledDeparture.isAfter(
        current.add(const Duration(minutes: 10)),
      );
      final bDue = !b.scheduledDeparture.isAfter(
        current.add(const Duration(minutes: 10)),
      );
      if (aDue != bDue) return aDue ? -1 : 1;
      return aDue
          ? b.scheduledDeparture.compareTo(a.scheduledDeparture)
          : a.scheduledDeparture.compareTo(b.scheduledDeparture);
    });
    return candidates.first;
  }
}

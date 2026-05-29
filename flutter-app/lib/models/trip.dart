import 'departure.dart';
import 'station.dart';

class Trip {
  final String id;
  final TransitLine line;
  final String direction;
  final Station origin;
  final Station destination;
  final List<Stopover> stopovers;
  final List<Map<String, double>>? polyline; // lat/lng points

  const Trip({
    required this.id,
    required this.line,
    required this.direction,
    required this.origin,
    required this.destination,
    required this.stopovers,
    this.polyline,
  });

  Trip copyWith({List<Map<String, double>>? polyline}) {
    return Trip(
      id: id,
      line: line,
      direction: direction,
      origin: origin,
      destination: destination,
      stopovers: stopovers,
      polyline: polyline ?? this.polyline,
    );
  }

  /// Stable signature of the *physical route* (ordered stop ids), independent
  /// of the date-bearing trip id. Used to cache the track geometry across days.
  String get routeKey {
    final ids = stopovers
        .map((s) => s.stop.id.isNotEmpty ? s.stop.id : s.stop.name)
        .where((s) => s.isNotEmpty)
        .toList();
    return ids.join('>');
  }

  factory Trip.fromHafas(Map<String, dynamic> json) {
    final lineJson = json['line'] as Map<String, dynamic>? ?? {};
    final originJson = json['origin'] as Map<String, dynamic>? ?? {};
    final destJson = json['destination'] as Map<String, dynamic>? ?? {};
    final stopsJson = json['stopovers'] as List<dynamic>? ?? [];
    final polyJson = json['polyline'] as Map<String, dynamic>?;

    List<Map<String, double>>? polyline;
    if (polyJson != null) {
      final features = polyJson['features'] as List<dynamic>? ?? [];
      polyline = features
          .whereType<Map<String, dynamic>>()
          .where((f) => f['geometry'] != null)
          .map((f) {
        final coords = (f['geometry'] as Map<String, dynamic>)['coordinates'];
        if (coords is List && coords.length >= 2) {
          return {
            'lat': (coords[1] as num).toDouble(),
            'lng': (coords[0] as num).toDouble(),
          };
        }
        return <String, double>{};
      }).where((m) => m.isNotEmpty).toList();
    }

    return Trip(
      id: json['id'] as String? ?? '',
      line: TransitLine.fromHafas(lineJson),
      direction: json['direction'] as String? ?? '',
      origin: Station.fromHafas(originJson),
      destination: Station.fromHafas(destJson),
      stopovers: stopsJson
          .whereType<Map<String, dynamic>>()
          .map(Stopover.fromHafas)
          .toList(),
      polyline: polyline,
    );
  }

  /// Find the current/next stop based on time
  Stopover? get currentStop {
    final now = DateTime.now();
    for (final stop in stopovers) {
      final dep = stop.departure ?? stop.arrival;
      if (dep != null && dep.isAfter(now)) return stop;
    }
    return stopovers.lastOrNull;
  }

  /// Estimated current position between stops
  CurrentPosition? get estimatedPosition {
    final now = DateTime.now();
    for (int i = 0; i < stopovers.length - 1; i++) {
      final current = stopovers[i];
      final next = stopovers[i + 1];
      final depTime = current.departure;
      final arrTime = next.arrival;

      if (depTime != null && arrTime != null) {
        if (now.isAfter(depTime) && now.isBefore(arrTime)) {
          final total = arrTime.difference(depTime).inSeconds;
          final elapsed = now.difference(depTime).inSeconds;
          final progress = total > 0 ? elapsed / total : 0.0;

          if (current.stop.hasLocation && next.stop.hasLocation) {
            final lat = current.stop.latitude! +
                (next.stop.latitude! - current.stop.latitude!) * progress;
            final lng = current.stop.longitude! +
                (next.stop.longitude! - current.stop.longitude!) * progress;
            return CurrentPosition(
              latitude: lat,
              longitude: lng,
              fromStop: current,
              toStop: next,
              progress: progress,
            );
          }
        }
      }
    }
    return null;
  }
}

class Stopover {
  final Station stop;
  final DateTime? arrival;
  final DateTime? plannedArrival;
  final int? arrivalDelay; // seconds
  final DateTime? departure;
  final DateTime? plannedDeparture;
  final int? departureDelay; // seconds
  final String? arrivalPlatform;
  final String? plannedArrivalPlatform;
  final String? departurePlatform;
  final String? plannedDeparturePlatform;
  final bool cancelled;

  const Stopover({
    required this.stop,
    this.arrival,
    this.plannedArrival,
    this.arrivalDelay,
    this.departure,
    this.plannedDeparture,
    this.departureDelay,
    this.arrivalPlatform,
    this.plannedArrivalPlatform,
    this.departurePlatform,
    this.plannedDeparturePlatform,
    this.cancelled = false,
  });

  bool get hasArrivalPlatformChange =>
      arrivalPlatform != null &&
      plannedArrivalPlatform != null &&
      arrivalPlatform != plannedArrivalPlatform;

  bool get hasDeparturePlatformChange =>
      departurePlatform != null &&
      plannedDeparturePlatform != null &&
      departurePlatform != plannedDeparturePlatform;

  String? get platform => departurePlatform ?? arrivalPlatform;
  String? get plannedPlatform =>
      plannedDeparturePlatform ?? plannedArrivalPlatform;

  bool get hasPlatformChange =>
      hasArrivalPlatformChange || hasDeparturePlatformChange;

  int get delayMinutes {
    final d = departureDelay ?? arrivalDelay;
    return d != null ? d ~/ 60 : 0;
  }

  /// Whether this stop is in the past
  bool get isPast {
    final dep = departure ?? arrival;
    return dep != null && dep.isBefore(DateTime.now());
  }

  factory Stopover.fromHafas(Map<String, dynamic> json) {
    final stopJson = json['stop'] as Map<String, dynamic>? ?? {};
    return Stopover(
      stop: Station.fromHafas(stopJson),
      arrival: _parse(json['arrival']),
      plannedArrival: _parse(json['plannedArrival']),
      arrivalDelay: json['arrivalDelay'] as int?,
      departure: _parse(json['departure']),
      plannedDeparture: _parse(json['plannedDeparture']),
      departureDelay: json['departureDelay'] as int?,
      arrivalPlatform: json['arrivalPlatform'] as String?,
      plannedArrivalPlatform: json['plannedArrivalPlatform'] as String?,
      departurePlatform: json['departurePlatform'] as String?,
      plannedDeparturePlatform: json['plannedDeparturePlatform'] as String?,
      cancelled: json['cancelled'] as bool? ?? false,
    );
  }
}

class CurrentPosition {
  final double latitude;
  final double longitude;
  final Stopover fromStop;
  final Stopover toStop;
  final double progress; // 0.0 to 1.0

  const CurrentPosition({
    required this.latitude,
    required this.longitude,
    required this.fromStop,
    required this.toStop,
    required this.progress,
  });
}

DateTime? _parse(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}

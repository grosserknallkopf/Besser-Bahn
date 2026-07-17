import 'dart:math' as math;

/// One scheduled point along a train leg. The points normally are stations;
/// interpolating between them is deliberately conservative but good enough to
/// tell whether the rider is materially behind the timetable.
class TimedRoutePoint {
  final double latitude;
  final double longitude;
  final DateTime scheduledAt;
  final int reportedDelaySeconds;

  const TimedRoutePoint({
    required this.latitude,
    required this.longitude,
    required this.scheduledAt,
    this.reportedDelaySeconds = 0,
  });

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'at': scheduledAt.toIso8601String(),
    'delay': reportedDelaySeconds,
  };

  factory TimedRoutePoint.fromJson(Map<String, dynamic> json) =>
      TimedRoutePoint(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        scheduledAt: DateTime.parse(json['at'] as String),
        reportedDelaySeconds: (json['delay'] as num?)?.toInt() ?? 0,
      );
}

class TrackedJourneyLeg {
  final String id;
  final String lineName;
  final String destinationName;
  final List<TimedRoutePoint> route;

  const TrackedJourneyLeg({
    required this.id,
    required this.lineName,
    required this.destinationName,
    required this.route,
  });

  DateTime get departure => route.first.scheduledAt;
  DateTime get arrival => route.last.scheduledAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'line': lineName,
    'destination': destinationName,
    'route': route.map((p) => p.toJson()).toList(),
  };

  factory TrackedJourneyLeg.fromJson(Map<String, dynamic> json) =>
      TrackedJourneyLeg(
        id: json['id'] as String,
        lineName: json['line'] as String? ?? 'Zug',
        destinationName: json['destination'] as String,
        route: (json['route'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(TimedRoutePoint.fromJson)
            .toList(growable: false),
      );
}

class JourneyPositionSample {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final DateTime timestamp;

  const JourneyPositionSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.timestamp,
  });
}

class JourneyPositionInference {
  final double progress;
  final double distanceToRouteMetres;
  final double distanceToDestinationMetres;
  final int inferredDelayMinutes;
  final int reportedDelayMinutes;
  final bool shouldNotifyExit;

  const JourneyPositionInference({
    required this.progress,
    required this.distanceToRouteMetres,
    required this.distanceToDestinationMetres,
    required this.inferredDelayMinutes,
    required this.reportedDelayMinutes,
    required this.shouldNotifyExit,
  });

  /// A positional delay is only interesting when it is both meaningful and
  /// clearly worse than the delay DB already reports.
  bool get suggestsUnreportedDelay =>
      inferredDelayMinutes >= 5 &&
      inferredDelayMinutes >= reportedDelayMinutes + 5;
}

/// Timetable + GPS inference shared by the foreground stream and Android's
/// headless callback. It has no Flutter dependencies so its edge cases can be
/// unit-tested without a device.
class ExitAlarmIntelligence {
  const ExitAlarmIntelligence();

  JourneyPositionInference? evaluate(
    TrackedJourneyLeg leg,
    JourneyPositionSample sample,
  ) {
    if (leg.route.length < 2 || sample.accuracy > 250) return null;
    if (sample.timestamp.isBefore(
      leg.departure.subtract(const Duration(minutes: 2)),
    )) {
      return null;
    }
    // Keep tracking a badly delayed train beyond its scheduled arrival, but
    // don't let yesterday's journey claim today's position.
    if (sample.timestamp.isAfter(leg.arrival.add(const Duration(hours: 4)))) {
      return null;
    }

    _Projection? nearest;
    for (var i = 0; i < leg.route.length - 1; i++) {
      final candidate = _project(sample, leg.route[i], leg.route[i + 1], i);
      if (nearest == null ||
          candidate.distanceMetres < nearest.distanceMetres) {
        nearest = candidate;
      }
    }
    if (nearest == null) return null;

    final from = leg.route[nearest.segment];
    final to = leg.route[nearest.segment + 1];
    final segmentMetres = _distance(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    // A chord between two distant stations does not follow every rail curve.
    // Widen only in proportion to that chord and cap the tolerance; this keeps
    // long-distance trains detectable without accepting arbitrary locations.
    final routeTolerance = math.min(
      20000.0,
      math.max(2000.0, segmentMetres * .12),
    );
    if (nearest.distanceMetres > routeTolerance) return null;

    final segmentSeconds = to.scheduledAt
        .difference(from.scheduledAt)
        .inSeconds;
    if (segmentSeconds <= 0) return null;
    final expectedAt = from.scheduledAt.add(
      Duration(
        milliseconds: (segmentSeconds * 1000 * nearest.fraction).round(),
      ),
    );
    final inferredDelay = sample.timestamp.difference(expectedAt).inMinutes;
    final reportedDelay =
        (from.reportedDelaySeconds +
            ((to.reportedDelaySeconds - from.reportedDelaySeconds) *
                    nearest.fraction)
                .round()) ~/
        60;

    final completedSegments = nearest.segment + nearest.fraction;
    final progress = completedSegments / (leg.route.length - 1);
    final destination = leg.route.last;
    final destinationMetres = _distance(
      sample.latitude,
      sample.longitude,
      destination.latitude,
      destination.longitude,
    );
    // At railway speed a two-minute look-ahead is useful; cap it so the alarm
    // never fires many kilometres before the stop. Accuracy expands the radius
    // slightly instead of allowing a noisy fix to miss the stop altogether.
    final exitRadius = math.min(
      2500.0,
      math.max(1500.0, sample.speed * 120) + sample.accuracy,
    );

    return JourneyPositionInference(
      progress: progress.clamp(0, 1),
      distanceToRouteMetres: nearest.distanceMetres,
      distanceToDestinationMetres: destinationMetres,
      inferredDelayMinutes: inferredDelay,
      reportedDelayMinutes: reportedDelay,
      // The temporal guard above plus some actual route progress prevents a
      // rider waiting at the destination before departure from tripping it.
      shouldNotifyExit: progress >= .08 && destinationMetres <= exitRadius,
    );
  }

  _Projection _project(
    JourneyPositionSample p,
    TimedRoutePoint a,
    TimedRoutePoint b,
    int segment,
  ) {
    const earth = 6371000.0;
    final refLat = _radians((a.latitude + b.latitude + p.latitude) / 3);
    double x(double lon) => _radians(lon) * math.cos(refLat) * earth;
    double y(double lat) => _radians(lat) * earth;
    final ax = x(a.longitude), ay = y(a.latitude);
    final bx = x(b.longitude), by = y(b.latitude);
    final px = x(p.longitude), py = y(p.latitude);
    final dx = bx - ax, dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    final fraction = lengthSquared == 0
        ? 0.0
        : (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
    final qx = ax + dx * fraction, qy = ay + dy * fraction;
    return _Projection(
      segment: segment,
      fraction: fraction,
      distanceMetres: math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy)),
    );
  }

  double _distance(double lat1, double lon1, double lat2, double lon2) {
    const earth = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}

class _Projection {
  final int segment;
  final double fraction;
  final double distanceMetres;

  const _Projection({
    required this.segment,
    required this.fraction,
    required this.distanceMetres,
  });
}

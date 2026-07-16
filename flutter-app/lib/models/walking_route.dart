/// One point of a walking route. Kept free of latlong2 so the model layer
/// stays map-library-agnostic; the map screen maps these to LatLng.
class WalkingPoint {
  final double lat;
  final double lon;
  const WalkingPoint(this.lat, this.lon);
}

/// A real walking route from DB's own routing (`/mob/location/calculateroute`,
/// #21) — the way you'd walk it, with how far and how long.
///
/// The point of it: a straight line between two platforms says "80 m" when the
/// walk is 400 m around the tracks and up two lifts. DB routes it properly, so
/// "6 min Weg" can be an answer instead of a guess.
class WalkingRoute {
  final List<WalkingPoint> points;

  /// Metres along the route (not as the crow flies).
  final int? distanceMetres;

  /// DB's own walking time (`traveltime`).
  final Duration? duration;

  const WalkingRoute({
    required this.points,
    this.distanceMetres,
    this.duration,
  });

  int? get minutes => duration?.inMinutes;

  /// "430 m · 6 min", with whatever DB gave us.
  String? get summary {
    final parts = <String>[
      if (distanceMetres != null) '$distanceMetres m',
      // Round up: a 40-second walk is "1 min", never "0 min".
      if (duration != null) '${duration!.inSeconds <= 60 ? 1 : minutes} min',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

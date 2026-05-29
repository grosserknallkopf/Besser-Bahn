import 'departure.dart';
import 'station.dart';

class JourneyResult {
  final List<Journey> journeys;
  final String? earlierRef;
  final String? laterRef;

  const JourneyResult({
    required this.journeys,
    this.earlierRef,
    this.laterRef,
  });

  factory JourneyResult.fromHafas(Map<String, dynamic> json) {
    final list = json['journeys'] as List<dynamic>? ?? [];
    return JourneyResult(
      journeys:
          list.whereType<Map<String, dynamic>>().map(Journey.fromHafas).toList(),
      earlierRef: json['earlierRef'] as String?,
      laterRef: json['laterRef'] as String?,
    );
  }
}

class Journey {
  final List<JourneyLeg> legs;
  final String? refreshToken;
  final JourneyPrice? price;

  const Journey({
    required this.legs,
    this.refreshToken,
    this.price,
  });

  factory Journey.fromHafas(Map<String, dynamic> json) {
    final legsJson = json['legs'] as List<dynamic>? ?? [];
    final priceJson = json['price'] as Map<String, dynamic>?;
    return Journey(
      legs: legsJson
          .whereType<Map<String, dynamic>>()
          .map(JourneyLeg.fromHafas)
          .toList(),
      refreshToken: json['refreshToken'] as String?,
      price: priceJson != null ? JourneyPrice.fromJson(priceJson) : null,
    );
  }

  Station? get origin => legs.firstOrNull?.origin;
  Station? get destination => legs.lastOrNull?.destination;
  DateTime? get departure => legs.firstOrNull?.departure;
  DateTime? get arrival => legs.lastOrNull?.arrival;
  DateTime? get plannedDeparture => legs.firstOrNull?.plannedDeparture;
  DateTime? get plannedArrival => legs.lastOrNull?.plannedArrival;

  int get transfers => legs.where((l) => !l.isWalking).length - 1;

  Duration? get duration {
    final dep = departure;
    final arr = arrival;
    if (dep == null || arr == null) return null;
    return arr.difference(dep);
  }

  String get durationString {
    final d = duration;
    if (d == null) return '';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}min';
    return '${minutes}min';
  }

  bool get hasDelay => legs.any((l) =>
      (l.departureDelay != null && l.departureDelay! > 0) ||
      (l.arrivalDelay != null && l.arrivalDelay! > 0));
}

class JourneyLeg {
  final String? tripId;
  final Station origin;
  final Station destination;
  final DateTime? departure;
  final DateTime? plannedDeparture;
  final int? departureDelay;
  final String? departurePlatform;
  final String? plannedDeparturePlatform;
  final DateTime? arrival;
  final DateTime? plannedArrival;
  final int? arrivalDelay;
  final String? arrivalPlatform;
  final String? plannedArrivalPlatform;
  final TransitLine? line;
  final String? direction;
  final bool isWalking;
  final int? walkingDistance;
  final bool cancelled;
  final List<LegStopover> stopovers;
  final OccupancyInfo? occupancy;

  const JourneyLeg({
    this.tripId,
    required this.origin,
    required this.destination,
    this.departure,
    this.plannedDeparture,
    this.departureDelay,
    this.departurePlatform,
    this.plannedDeparturePlatform,
    this.arrival,
    this.plannedArrival,
    this.arrivalDelay,
    this.arrivalPlatform,
    this.plannedArrivalPlatform,
    this.line,
    this.direction,
    this.isWalking = false,
    this.walkingDistance,
    this.cancelled = false,
    this.stopovers = const [],
    this.occupancy,
  });

  bool get hasDeparturePlatformChange =>
      departurePlatform != null &&
      plannedDeparturePlatform != null &&
      departurePlatform != plannedDeparturePlatform;

  bool get hasArrivalPlatformChange =>
      arrivalPlatform != null &&
      plannedArrivalPlatform != null &&
      arrivalPlatform != plannedArrivalPlatform;

  int get departureDelayMinutes =>
      departureDelay != null ? departureDelay! ~/ 60 : 0;
  int get arrivalDelayMinutes =>
      arrivalDelay != null ? arrivalDelay! ~/ 60 : 0;

  factory JourneyLeg.fromHafas(Map<String, dynamic> json) {
    final originJson = json['origin'] as Map<String, dynamic>? ?? {};
    final destJson = json['destination'] as Map<String, dynamic>? ?? {};
    final lineJson = json['line'] as Map<String, dynamic>?;
    final stopsJson = json['stopovers'] as List<dynamic>? ?? [];
    final loadJson = json['loadFactor'] as String?;

    return JourneyLeg(
      tripId: json['tripId'] as String?,
      origin: Station.fromHafas(originJson),
      destination: Station.fromHafas(destJson),
      departure: _parse(json['departure']),
      plannedDeparture: _parse(json['plannedDeparture']),
      departureDelay: json['departureDelay'] as int?,
      departurePlatform: json['departurePlatform'] as String?,
      plannedDeparturePlatform: json['plannedDeparturePlatform'] as String?,
      arrival: _parse(json['arrival']),
      plannedArrival: _parse(json['plannedArrival']),
      arrivalDelay: json['arrivalDelay'] as int?,
      arrivalPlatform: json['arrivalPlatform'] as String?,
      plannedArrivalPlatform: json['plannedArrivalPlatform'] as String?,
      line: lineJson != null ? TransitLine.fromHafas(lineJson) : null,
      direction: json['direction'] as String?,
      isWalking: json['walking'] as bool? ?? false,
      walkingDistance: json['distance'] as int?,
      cancelled: json['cancelled'] as bool? ?? false,
      stopovers: stopsJson
          .whereType<Map<String, dynamic>>()
          .map(LegStopover.fromHafas)
          .toList(),
      occupancy: loadJson != null
          ? OccupancyInfo(level: _parseLoadFactor(loadJson))
          : null,
    );
  }
}

class LegStopover {
  final Station stop;
  final DateTime? arrival;
  final DateTime? departure;
  final int? arrivalDelay;
  final int? departureDelay;

  const LegStopover({
    required this.stop,
    this.arrival,
    this.departure,
    this.arrivalDelay,
    this.departureDelay,
  });

  factory LegStopover.fromHafas(Map<String, dynamic> json) {
    final stopJson = json['stop'] as Map<String, dynamic>? ?? {};
    return LegStopover(
      stop: Station.fromHafas(stopJson),
      arrival: _parse(json['arrival']),
      departure: _parse(json['departure']),
      arrivalDelay: json['arrivalDelay'] as int?,
      departureDelay: json['departureDelay'] as int?,
    );
  }
}

class JourneyPrice {
  final double amount;
  final String currency;

  const JourneyPrice({required this.amount, this.currency = 'EUR'});

  factory JourneyPrice.fromJson(Map<String, dynamic> json) {
    return JourneyPrice(
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'EUR',
    );
  }

  String get formatted => '${amount.toStringAsFixed(2)} €';
}

class OccupancyInfo {
  final OccupancyLevel level;

  const OccupancyInfo({required this.level});
}

enum OccupancyLevel {
  unknown,
  low,
  medium,
  high,
  veryHigh;

  String get label {
    switch (this) {
      case OccupancyLevel.unknown:
        return 'Keine Daten';
      case OccupancyLevel.low:
        return 'Gering';
      case OccupancyLevel.medium:
        return 'Mittel';
      case OccupancyLevel.high:
        return 'Hoch';
      case OccupancyLevel.veryHigh:
        return 'Sehr hoch';
    }
  }
}

OccupancyLevel _parseLoadFactor(String factor) {
  switch (factor) {
    case 'low-to-medium':
      return OccupancyLevel.low;
    case 'high':
      return OccupancyLevel.high;
    case 'very-high':
      return OccupancyLevel.veryHigh;
    case 'exceptionally-high':
      return OccupancyLevel.veryHigh;
    default:
      return OccupancyLevel.unknown;
  }
}

DateTime? _parse(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}

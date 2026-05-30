import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/coach_sequence.dart';

/// Service for the Deutsche Bahn Wagenreihung (coach sequence) API
class CoachSequenceService {
  final ApiClient _client = ApiClient();
  static const _base = ApiConstants.dbWebApiBaseUrl;

  /// Session cache of resolved sequences, keyed by train + station + time, so a
  /// stop's platform train is drawn instantly once fetched and a whole trip's
  /// stops can be prefetched and kept warm while the journey is open.
  static final Map<String, CoachSequence> _cache = {};

  /// Get coach sequence for a train at a specific station
  ///
  /// [category] - Train category: ICE, IC, EC, etc.
  /// [number] - Train number (e.g., 148)
  /// [stationEva] - Station EVA number
  /// [date] - Date of travel
  /// [time] - Departure time at the station (ISO 8601)
  Future<CoachSequence> getCoachSequence({
    required String category,
    required int number,
    required String stationEva,
    required DateTime date,
    required DateTime time,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr = time.toUtc().toIso8601String();

    final result = await _client.get(
      '$_base/reisebegleitung/wagenreihung/vehicle-sequence',
      queryParams: {
        'administrationId': '80',
        'category': category,
        'date': dateStr,
        'evaNumber': stationEva,
        'number': number.toString(),
        'time': timeStr,
      },
    );
    return CoachSequence.fromJson(result);
  }

  /// Categories the vehicle-sequence endpoint actually serves. Long-distance
  /// (ICE/IC/EC) *and* the regional trains (RE/RB/IRE) — the latter matters for
  /// wing trains (Flügelzüge, e.g. the RE7 that splits in Neumünster into a Kiel
  /// and a Flensburg portion): the Wagenreihung is the only source that says
  /// *which* coaches go where. S-Bahn / bus / tram have no sequence → skipped.
  static const _coachCategories = {
    'ICE', 'IC', 'EC', 'ECE', 'RE', 'RB', 'IRE', 'RJ', 'RJX', 'EN', 'NJ', 'D',
  };

  /// Get coach sequence for a train portion.
  ///
  /// [category] - product (ICE, IC, RE, RB, …).
  /// [trainNumber] - the *train* number (Zugnummer / fahrtNr, e.g. "11266"),
  ///   NOT the line number — a wing train's two portions share the line "RE 7"
  ///   but carry distinct train numbers.
  Future<CoachSequence?> getCoachSequenceForDeparture({
    required String category,
    required String trainNumber,
    required String stationEva,
    required DateTime? departureTime,
  }) async {
    if (departureTime == null) return null;

    final cat = category.toUpperCase().trim();
    final number = int.tryParse(trainNumber.trim());
    if (number == null || !_coachCategories.contains(cat)) return null;

    final key = '$cat|$number|$stationEva|${departureTime.toUtc().toIso8601String()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final cs = await getCoachSequence(
        category: cat,
        number: number,
        stationEva: stationEva,
        date: departureTime,
        time: departureTime,
      );
      _cache[key] = cs;
      return cs;
    } catch (_) {
      return null;
    }
  }

  /// Warm the cache for every stop of one train (fire-and-forget) so opening any
  /// stop's platform map shows the to-scale train instantly — and it stays
  /// cached for the whole session while the journey is open.
  Future<void> prefetchTrainStops({
    required String category,
    required String trainNumber,
    required Iterable<({String eva, DateTime? time})> stops,
  }) async {
    await Future.wait([
      for (final s in stops)
        if (s.eva.isNotEmpty && s.time != null)
          getCoachSequenceForDeparture(
            category: category,
            trainNumber: trainNumber,
            stationEva: s.eva,
            departureTime: s.time,
          ),
    ]);
  }
}

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/coach_sequence.dart';

/// Service for the Deutsche Bahn Wagenreihung (coach sequence) API
class CoachSequenceService {
  final ApiClient _client = ApiClient();
  static const _base = ApiConstants.dbWebApiBaseUrl;

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

  /// Get coach sequence from a departure object
  Future<CoachSequence?> getCoachSequenceForDeparture({
    required String lineName,
    required String stationEva,
    required DateTime? departureTime,
  }) async {
    if (departureTime == null) return null;

    // Parse category and number from line name (e.g., "ICE 148" -> ICE, 148)
    final parts = lineName.split(' ');
    if (parts.length < 2) return null;

    final category = parts[0].toUpperCase();
    final number = int.tryParse(parts.last);
    if (number == null) return null;

    // Only long-distance trains have coach sequence data
    if (!['ICE', 'IC', 'EC', 'ECE'].contains(category)) return null;

    try {
      return await getCoachSequence(
        category: category,
        number: number,
        stationEva: stationEva,
        date: departureTime,
        time: departureTime,
      );
    } catch (_) {
      return null;
    }
  }
}

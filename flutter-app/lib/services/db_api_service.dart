import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/split_ticket.dart';

/// Service for Deutsche Bahn internal web API (bahn.de)
/// Used for price queries and split-ticketing.
class DbApiService {
  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        'User-Agent': ApiConstants.userAgent,
        'Accept': 'application/json',
        'Accept-Language': 'de-DE,de;q=0.9',
        'Content-Type': 'application/json',
      };

  /// Search stations via bahn.de API
  Future<List<Map<String, dynamic>>> searchStations(String query) async {
    final uri = Uri.parse(
      '${ApiConstants.dbWebApiBaseUrl}/reiseloesung/orte',
    ).replace(queryParameters: {
      'suchbegriff': query,
      'typ': 'ALL',
      'limit': '10',
    });

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) return [];

    final result = json.decode(response.body);
    if (result is List) return result.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  /// Get connection details with prices (for split-ticketing)
  Future<Map<String, dynamic>> getConnectionDetails({
    required String fromId,
    required String toId,
    required String dateTime,
    required List<Map<String, dynamic>> travellers,
    bool deutschlandTicket = false,
  }) async {
    final uri = Uri.parse(
        '${ApiConstants.dbWebApiBaseUrl}/angebote/fahrplan');

    final body = {
      'abfahrtsHalt': fromId,
      'ankunftsHalt': toId,
      'anfrageZeitpunkt': dateTime,
      'ankunftSuche': 'ABFAHRT',
      'klasse': 'KLASSE_2',
      'produktgattungen': [
        'ICE', 'EC_IC', 'IR', 'REGIONAL', 'SBAHN',
        'BUS', 'SCHIFF', 'UBAHN', 'TRAM', 'ANRUFPFLICHTIG',
      ],
      'reisende': travellers,
      'schnelleVerbindungen': true,
      'deutschlandTicketVorhanden': deutschlandTicket,
    };

    final response = await _client.post(uri, headers: _headers,
        body: json.encode(body));
    if (response.statusCode != 200) {
      throw Exception('Failed to get connections: ${response.statusCode}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get price for a single segment
  Future<SegmentPrice> getSegmentPrice({
    required String fromId,
    required String toId,
    required String dateTime,
    required List<Map<String, dynamic>> travellers,
    bool deutschlandTicket = false,
    required int delayMs,
  }) async {
    await Future.delayed(Duration(milliseconds: delayMs));

    try {
      final result = await getConnectionDetails(
        fromId: fromId,
        toId: toId,
        dateTime: dateTime,
        travellers: travellers,
        deutschlandTicket: deutschlandTicket,
      );

      final connections = result['verbindungen'] as List<dynamic>? ?? [];
      if (connections.isEmpty) {
        return const SegmentPrice(price: double.infinity, isDTicketCovered: false);
      }

      final first = connections[0] as Map<String, dynamic>;

      // Check Deutschland-Ticket coverage
      bool isDTicketCovered = false;
      if (deutschlandTicket) {
        final verbindungsAbschnitte =
            first['verbindungsAbschnitte'] as List<dynamic>? ?? [];
        for (final abschnitt in verbindungsAbschnitte) {
          if (abschnitt is Map<String, dynamic>) {
            final attrs =
                abschnitt['abpiAbfahrtAttributes'] as List<dynamic>? ?? [];
            for (final attr in attrs) {
              if (attr is Map<String, dynamic> && attr['key'] == '9G') {
                isDTicketCovered = true;
                break;
              }
            }
          }
        }
      }

      if (isDTicketCovered) {
        return const SegmentPrice(price: 0.0, isDTicketCovered: true);
      }

      final priceObj = first['angebotsPreis'] as Map<String, dynamic>?;
      final price = (priceObj?['betrag'] as num?)?.toDouble() ?? double.infinity;
      return SegmentPrice(price: price, isDTicketCovered: false);
    } catch (_) {
      return const SegmentPrice(price: double.infinity, isDTicketCovered: false);
    }
  }

  /// Create traveller payload for API
  static List<Map<String, dynamic>> createTravellerPayload({
    BahnCardType bahnCard = BahnCardType.none,
  }) {
    return [
      {
        'typ': 'ERWACHSENER',
        'ermaessigungen': [
          {
            'art': bahnCard.apiValue,
            'klasse': bahnCard.classValue,
          }
        ],
        'alter': [],
        'anzahl': 1,
      }
    ];
  }

  /// Open/book a WHOLE connection on bahn.de: the standard fahrplan-suche deep
  /// link, pre-filled with origin/destination, date and the user's BahnCard /
  /// Deutschland-Ticket so the shown price matches the app.
  static String generateJourneyLink({
    required String fromName,
    required String toName,
    required String fromId,
    required String toId,
    required String departureIso,
    BahnCardType bahnCard = BahnCardType.none,
    bool deutschlandTicket = false,
  }) {
    final from = Uri.encodeComponent(fromName);
    final to = Uri.encodeComponent(toName);
    final hd = Uri.encodeComponent(departureIso.split('.').first);
    final dtFlag = deutschlandTicket ? 'true' : 'false';
    final bcCode = bahnCard.bookingCode;
    final bcParam = bcCode.isNotEmpty ? '&rk=$bcCode' : '';

    return 'https://www.bahn.de/buchung/fahrplan/suche#'
        'sts=true&so=$from&zo=$to'
        '&soid=$fromId&zoid=$toId'
        '&hd=$hd'
        '&dt=$dtFlag$bcParam';
  }

  /// Generate a booking link for a split ticket
  static String generateBookingLink(SplitTicket ticket, {
    BahnCardType bahnCard = BahnCardType.none,
    bool deutschlandTicket = false,
  }) {
    final from = Uri.encodeComponent(ticket.from);
    final to = Uri.encodeComponent(ticket.to);
    final dtFlag = deutschlandTicket ? 'true' : 'false';
    final bcCode = bahnCard.bookingCode;
    final bcParam = bcCode.isNotEmpty ? '&rk=$bcCode' : '';

    return 'https://www.bahn.de/buchung/fahrplan/suche#'
        'sts=true&so=$from&zo=$to'
        '&soid=${ticket.fromId}&zoid=${ticket.toId}'
        '&hd=${ticket.departureIso}'
        '&dt=$dtFlag$bcParam';
  }

  void dispose() => _client.close();
}

class SegmentPrice {
  final double price;
  final bool isDTicketCovered;
  const SegmentPrice({required this.price, required this.isDTicketCovered});
}

import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/utils/split_stops.dart';
import 'package:flutter_test/flutter_test.dart';

Station _st(String name) => Station(id: name, name: name);

LegStopover _so(String name) =>
    LegStopover(stop: _st(name), departure: DateTime(2026, 7, 14, 10));

/// `product` mirrors what VendoService._mapProduct emits.
JourneyLeg _leg(String product, List<String> stops, {bool walking = false}) =>
    JourneyLeg(
      tripId: 't-$product',
      origin: _st(stops.first),
      destination: _st(stops.last),
      plannedDeparture: DateTime(2026, 7, 14, 10),
      arrival: DateTime(2026, 7, 14, 12),
      isWalking: walking,
      line: walking
          ? null
          : TransitLine(
              name: product,
              fahrtNr: '1',
              productName: product,
              product: product),
      stopovers: [for (final s in stops) _so(s)],
    );

void main() {
  group('D-Ticket coverage from the SELECTED connection (#13)', () {
    test('an all-regional route is covered end to end', () {
      final stops = splitStopsFromJourney(Journey(legs: [
        _leg('regional', ['Kiel Hbf', 'Neumünster', 'Hamburg Hbf']),
      ]));

      expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isTrue);
    });

    test('REGRESSION: a regional+ICE route is NOT covered end to end', () {
      // The exact reported shape: a D-Ticket-eligible regional leg followed by
      // an ICE. The old "any section carries 9G → whole segment free" logic
      // priced this at 0,00 € and told the rider their ICE was covered.
      final stops = splitStopsFromJourney(Journey(legs: [
        _leg('regional', ['Kiel Hbf', 'Hamburg Hbf']),
        _leg('nationalExpress', ['Hamburg Hbf', 'Berlin Hbf']),
      ]));

      expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isFalse,
          reason: 'one ICE hop makes the whole segment payable');
    });

    test('the regional prefix of a mixed route is still covered on its own',
        () {
      final stops = splitStopsFromJourney(Journey(legs: [
        _leg('regional', ['Kiel Hbf', 'Hamburg Hbf']),
        _leg('nationalExpress', ['Hamburg Hbf', 'Berlin Hbf']),
      ]));
      final hamburg = stops.indexWhere((s) => s['name'] == 'Hamburg Hbf');

      // Kiel → Hamburg: regional only.
      expect(isSegmentDTicketCovered(stops, 0, hamburg), isTrue);
      // Hamburg → Berlin: the ICE.
      expect(isSegmentDTicketCovered(stops, hamburg, stops.length - 1), isFalse);
      // This split — D-Ticket to Hamburg, buy from Hamburg — is the whole point.
    });

    test('an unidentifiable train blocks coverage rather than reading as free',
        () {
      final stops = splitStopsFromJourney(Journey(legs: [
        JourneyLeg(
          tripId: 'x',
          origin: _st('A'),
          destination: _st('B'),
          line: null, // unknown product
          stopovers: [_so('A'), _so('B')],
        ),
      ]));

      expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isFalse,
          reason: 'unknown product must not be assumed local');
    });

    test('a walking transfer between two regional legs stays covered', () {
      final stops = splitStopsFromJourney(Journey(legs: [
        _leg('regional', ['A', 'B']),
        _leg('', ['B', 'C'], walking: true),
        _leg('suburban', ['C', 'D']),
      ]));

      expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isTrue,
          reason: 'a fare-free gap must not block coverage');
    });

    test('every long-distance product needs a ticket', () {
      for (final p in ['nationalExpress', 'national']) {
        final stops =
            splitStopsFromJourney(Journey(legs: [_leg(p, ['A', 'B'])]));
        expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isFalse,
            reason: '$p is not covered by the Deutschlandticket');
      }
    });

    test('every local product is covered', () {
      for (final p in ['regional', 'suburban', 'subway', 'tram', 'bus']) {
        final stops =
            splitStopsFromJourney(Journey(legs: [_leg(p, ['A', 'B'])]));
        expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isTrue,
            reason: '$p is covered by the Deutschlandticket');
      }
    });
  });
}

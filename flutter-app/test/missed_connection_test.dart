import 'package:besser_bahn/core/missed_connection.dart';
import 'package:besser_bahn/models/departure.dart';
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = Station(id: '1', name: 'A');
  const b = Station(id: '2', name: 'B');
  const c = Station(id: '3', name: 'C');
  const line = TransitLine(
    name: 'ICE 1',
    fahrtNr: '1',
    productName: 'ICE',
    product: 'nationalExpress',
  );
  final ten = DateTime(2026, 7, 17, 10);
  final journey = Journey(
    legs: [
      JourneyLeg(
        origin: a,
        destination: b,
        departure: ten,
        arrival: ten.add(const Duration(hours: 1)),
        line: line,
      ),
      JourneyLeg(
        origin: b,
        destination: c,
        departure: ten.add(const Duration(hours: 1, minutes: 10)),
        arrival: ten.add(const Duration(hours: 2)),
        line: line,
      ),
    ],
  );

  test('offers rescue from the original origin around first departure', () {
    final rescue = MissedConnectionRescue.forJourney(
      journey,
      now: ten.add(const Duration(minutes: 5)),
    );

    expect(rescue, isNotNull);
    expect(rescue!.from.id, a.id);
    expect(rescue.to.id, c.id);
    expect(rescue.isConnection, isFalse);
  });

  test('offers rescue from transfer station for missed connection', () {
    final rescue = MissedConnectionRescue.forJourney(
      journey,
      now: ten.add(const Duration(hours: 1, minutes: 15)),
    );

    expect(rescue, isNotNull);
    expect(rescue!.from.id, b.id);
    expect(rescue.to.id, c.id);
    expect(rescue.isConnection, isTrue);
  });

  test('hides the action outside the plausible missed window', () {
    final rescue = MissedConnectionRescue.forJourney(
      journey,
      now: ten.subtract(const Duration(hours: 2)),
    );

    expect(rescue, isNull);
  });

  test('notification payload round-trips stations and leg', () {
    final rescue = MissedConnectionRescue(
      from: b,
      to: c,
      scheduledDeparture: ten,
      legIndex: 1,
      isConnection: true,
    );

    final decoded = MissedConnectionRescue.decode(rescue.encode());
    expect(decoded.from.id, b.id);
    expect(decoded.to.id, c.id);
    expect(decoded.legIndex, 1);
    expect(decoded.isConnection, isTrue);
  });
}

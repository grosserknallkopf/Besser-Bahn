import 'package:besser_bahn/core/exit_alarm_intelligence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const intelligence = ExitAlarmIntelligence();
  final departure = DateTime(2026, 7, 17, 10);
  final arrival = DateTime(2026, 7, 17, 11);

  TrackedJourneyLeg leg({int reportedDelaySeconds = 0}) => TrackedJourneyLeg(
    id: 'ice-1',
    lineName: 'ICE 1',
    destinationName: 'Berlin Hbf',
    route: [
      TimedRoutePoint(
        latitude: 52,
        longitude: 13,
        scheduledAt: departure,
        reportedDelaySeconds: reportedDelaySeconds,
      ),
      TimedRoutePoint(
        latitude: 52,
        longitude: 14,
        scheduledAt: arrival,
        reportedDelaySeconds: reportedDelaySeconds,
      ),
    ],
  );

  JourneyPositionSample sample({
    required double longitude,
    required DateTime at,
    double accuracy = 15,
    double speed = 25,
  }) => JourneyPositionSample(
    latitude: 52,
    longitude: longitude,
    accuracy: accuracy,
    speed: speed,
    timestamp: at,
  );

  test('matches an on-time position to the timetable', () {
    final result = intelligence.evaluate(
      leg(),
      sample(longitude: 13.5, at: departure.add(const Duration(minutes: 30))),
    );

    expect(result, isNotNull);
    expect(result!.progress, closeTo(.5, .01));
    expect(result.inferredDelayMinutes, 0);
    expect(result.suggestsUnreportedDelay, isFalse);
  });

  test('spots position delay DB has not reported', () {
    final result = intelligence.evaluate(
      leg(),
      sample(longitude: 13.5, at: departure.add(const Duration(minutes: 42))),
    );

    expect(result!.inferredDelayMinutes, 12);
    expect(result.reportedDelayMinutes, 0);
    expect(result.suggestsUnreportedDelay, isTrue);
  });

  test('does not call an already reported delay unreported', () {
    final result = intelligence.evaluate(
      leg(reportedDelaySeconds: 10 * 60),
      sample(longitude: 13.5, at: departure.add(const Duration(minutes: 42))),
    );

    expect(result!.inferredDelayMinutes, 12);
    expect(result.reportedDelayMinutes, 10);
    expect(result.suggestsUnreportedDelay, isFalse);
  });

  test('uses speed-aware but bounded destination corridor', () {
    final result = intelligence.evaluate(
      leg(),
      sample(
        longitude: 13.98,
        at: arrival.add(const Duration(minutes: 8)),
        speed: 30,
      ),
    );

    expect(result!.distanceToDestinationMetres, lessThan(2500));
    expect(result.shouldNotifyExit, isTrue);
  });

  test('rejects an inaccurate fix', () {
    final result = intelligence.evaluate(
      leg(),
      sample(
        longitude: 13.5,
        at: departure.add(const Duration(minutes: 30)),
        accuracy: 500,
      ),
    );

    expect(result, isNull);
  });

  test('cannot alarm at destination before departure', () {
    final result = intelligence.evaluate(
      leg(),
      sample(longitude: 14, at: departure.subtract(const Duration(minutes: 5))),
    );

    expect(result, isNull);
  });
}

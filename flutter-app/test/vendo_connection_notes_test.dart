import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shapes mirror live `/mob/angebote/fahrplan` connections.
Map<String, dynamic> _conn({
  Map<String, dynamic>? topNotiz,
  List<Map<String, dynamic>>? echtzeitNotizen,
  List<Map<String, dynamic>>? himNotizen,
}) =>
    {
      'verbindung': {
        'kontext': 'ctx-1',
        if (topNotiz != null) 'topNotiz': topNotiz,
        if (echtzeitNotizen != null) 'echtzeitNotizen': echtzeitNotizen,
        if (himNotizen != null) 'himNotizen': himNotizen,
        'verbindungsAbschnitte': [
          {
            'typ': 'FAHRZEUG',
            'mitteltext': 'ICE 947',
            'kurztext': 'ICE',
            'produktGattung': 'ICE',
            'abgangsOrt': {'evaNr': '8000207', 'name': 'Köln Hbf'},
            'ankunftsOrt': {'evaNr': '8011160', 'name': 'Berlin Hbf'},
            'abgangsDatum': '2026-07-15T20:44:00+02:00',
            'ankunftsDatum': '2026-07-16T00:17:00+02:00',
            'halte': [],
          }
        ],
      }
    };

void main() {
  group('connection-level notes (#20)', () {
    final svc = VendoService();

    test('the connection note reaches the journey', () {
      // The live case: the leg carries no notes at all, and this is the only
      // place that says the train stops short of Berlin Hbf.
      final j = svc.parseConnection(_conn(echtzeitNotizen: [
        {
          'prio': 'HOCH',
          'text': 'Der Zielhalt Berlin Hbf entfällt. '
              'Ausstieg in Berlin-Spandau möglich.'
        }
      ]));

      expect(j.disruptions, hasLength(1));
      expect(j.disruptions.first, contains('Berlin-Spandau'));
      expect(j.legs.first.disruptions, isEmpty,
          reason: 'proves the leg was not the source');
    });

    test('the "textDefault" placeholder never reaches the UI', () {
      // 11 of 15 live connections carry exactly this as topNotiz.
      final j = svc.parseConnection(_conn(
        topNotiz: {'prio': 'NORMAL', 'text': 'textDefault'},
        echtzeitNotizen: [
          {'prio': 'NORMAL', 'text': 'textDefault'}
        ],
      ));
      expect(j.disruptions, isEmpty);
    });

    test('him and realtime notes are merged, deduped', () {
      final j = svc.parseConnection(_conn(
        himNotizen: [
          {'text': 'Bauarbeiten'}
        ],
        echtzeitNotizen: [
          {'text': 'Bauarbeiten'},
          {'text': 'Verbindung fällt aus'},
        ],
      ));
      expect(j.disruptions, ['Bauarbeiten', 'Verbindung fällt aus']);
    });

    test('an undisturbed connection has none', () {
      expect(svc.parseConnection(_conn()).disruptions, isEmpty);
    });
  });
}

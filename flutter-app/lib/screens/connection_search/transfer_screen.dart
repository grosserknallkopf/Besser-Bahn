import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions.dart';
import '../../models/station.dart';
import '../../providers/station_map_provider.dart';

/// Everything needed to describe one change between two legs — passed to the
/// [TransferScreen] via GoRouter `extra`.
class TransferInfo {
  /// Where you change (the arriving train's destination).
  final Station station;
  final String? arrGleis; // Ausstieg
  final String? depGleis; // Einstieg
  final DateTime? arrival; // when the first train gets in
  final DateTime? departure; // when the next train leaves
  final String? fromLine; // arriving train
  final String? toLine; // departing train
  final int? walkMinutes; // scheduled foot-transfer duration (FUSSWEG leg)
  final int? walkDistance; // metres
  final Station? toStation; // Einstieg station, if the walk crosses stations

  const TransferInfo({
    required this.station,
    this.arrGleis,
    this.depGleis,
    this.arrival,
    this.departure,
    this.fromLine,
    this.toLine,
    this.walkMinutes,
    this.walkDistance,
    this.toStation,
  });

  /// The time you actually have to change: arrival → next departure.
  int? get availableMinutes => (arrival != null && departure != null)
      ? departure!.difference(arrival!).inMinutes
      : null;

  bool get crossStation =>
      toStation != null && toStation!.name.isNotEmpty &&
      toStation!.name != station.name;
}

/// A focused "how do I change here" screen: Ausstieg → Fußweg → Einstieg, the
/// time you have (colour-coded), and a button to see both Gleise on the map.
class TransferScreen extends ConsumerWidget {
  final TransferInfo info;

  const TransferScreen({super.key, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mins = info.availableMinutes;
    final (color, headline, sub) = _verdict(context, mins);

    return Scaffold(
      appBar: AppBar(title: Text('Umstieg in ${info.station.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Available transfer time — the headline.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(mins != null && mins <= 2
                    ? Icons.warning_amber_rounded
                    : Icons.timer_outlined,
                    color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: color, fontWeight: FontWeight.bold)),
                      if (sub != null)
                        Text(sub,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: color)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Ausstieg → (Fußweg) → Einstieg
          _stopRow(
            context,
            icon: Icons.logout,
            iconColor: Colors.red,
            title: 'Ausstieg',
            gleis: info.arrGleis,
            line: info.fromLine,
            timeLabel: 'an',
            time: info.arrival,
            station: info.station.name,
          ),
          if (info.walkMinutes != null || info.walkDistance != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.directions_walk,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    [
                      if (info.walkMinutes != null)
                        'Fußweg ca. ${info.walkMinutes} min',
                      if (info.walkDistance != null) '${info.walkDistance} m',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          _stopRow(
            context,
            icon: Icons.login,
            iconColor: const Color(0xFF2E9E5B),
            title: 'Einstieg',
            gleis: info.depGleis,
            line: info.toLine,
            timeLabel: 'ab',
            time: info.departure,
            station: info.crossStation ? info.toStation!.name : null,
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: () => _openMap(context, ref),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Gleise auf der Karte zeigen'),
          ),
          const SizedBox(height: 8),
          Text(
            'Rot = Ausstieg · Grün = Einstieg',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _openMap(BuildContext context, WidgetRef ref) {
    final note = (info.arrGleis != null && info.depGleis != null)
        ? 'Ausstieg Gleis ${info.arrGleis} · Einstieg Gleis ${info.depGleis}'
        : info.depGleis != null
            ? 'Einstieg Gleis ${info.depGleis}'
            : 'Umstieg in ${info.station.name}';
    ref.read(stationMapProvider.notifier).loadForStation(
          info.station,
          highlightGleis: info.depGleis,
          role: GleisRole.board,
          secondaryGleis: info.arrGleis,
          secondaryRole: GleisRole.alight,
          transferNote: note,
        );
    context.push('/station-map');
  }

  /// (colour, headline, subline) for the available transfer time.
  (Color, String, String?) _verdict(BuildContext context, int? mins) {
    final scheme = Theme.of(context).colorScheme;
    if (mins == null) {
      return (scheme.primary, 'Umstieg', null);
    }
    if (mins <= 2) {
      return (
        scheme.error,
        '$mins min zum Umsteigen',
        'Knapp – Anschluss evtl. nicht erreichbar.'
      );
    }
    if (mins <= 5) {
      return (
        const Color(0xFFCC8800),
        '$mins min zum Umsteigen',
        'Wenig Zeit – zügig zum Gleis.'
      );
    }
    return (const Color(0xFF2E9E5B), '$mins min zum Umsteigen', 'Genug Zeit.');
  }

  Widget _stopRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? gleis,
    String? line,
    required String timeLabel,
    DateTime? time,
    String? station,
  }) {
    final theme = Theme.of(context);
    final parts = [
      if (line != null && line.isNotEmpty) line,
      if (station != null && station.isNotEmpty) station,
      if (time != null) '$timeLabel ${time.hhmm}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (gleis != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Gleis $gleis',
                            style: TextStyle(
                                color: iconColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                    ],
                  ],
                ),
                if (parts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(parts.join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

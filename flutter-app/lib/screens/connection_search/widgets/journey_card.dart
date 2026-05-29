import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/journey.dart';
import '../../../core/extensions.dart';
import '../../../core/share_text.dart';
import '../../../providers/service_providers.dart';
import '../../../widgets/delay_badge.dart';
import '../../../widgets/platform_badge.dart';
import '../../../widgets/occupancy_indicator.dart';
import '../../../widgets/prediction_badge.dart';

class JourneyCard extends ConsumerWidget {
  final Journey journey;

  const JourneyCard({super.key, required this.journey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final transitLegs = journey.legs.where((l) => !l.isWalking).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Show the FULL connection (all legs + transfers), not just leg 1.
          context.push('/connection', extra: journey);
        },
        // Long-press shares the official bahn.de "Reise teilen" link to this
        // exact connection — no need to open the detail screen first.
        onLongPress: () => _share(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Prediction strip (Anschluss / Pünktlichkeit) on the left.
              PredictionBadge(journey: journey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
            children: [
              // Route row: which station to which station — so a saved/searched
              // connection is identifiable at a glance, not just by its times.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      journey.origin?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.arrow_forward,
                        size: 13, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Expanded(
                    child: Text(
                      journey.destination?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Time row
              Row(
                children: [
                  // Departure
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _timeWithDelay(context, journey.plannedDeparture,
                          journey.legs.firstOrNull?.departureDelay),
                      if (journey.legs.firstOrNull?.departurePlatform != null ||
                          journey.legs.firstOrNull?.plannedDeparturePlatform !=
                              null)
                        _depPlatform(context, journey.legs.firstOrNull!),
                    ],
                  ),

                  // Duration & transfers
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          journey.durationString,
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          journey.transfers == 0
                              ? 'Direkt'
                              : '${journey.transfers} Umstieg'
                                  '${journey.transfers > 1 ? 'e' : ''}',
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                  // Arrival
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _timeWithDelay(context, journey.plannedArrival,
                          journey.legs.lastOrNull?.arrivalDelay),
                      if (journey.legs.lastOrNull?.arrivalPlatform != null)
                        PlatformBadge(
                          platform:
                              journey.legs.lastOrNull?.arrivalPlatform,
                          plannedPlatform: journey
                              .legs.lastOrNull?.plannedArrivalPlatform,
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Per-train length comparison (one row each) on the left; price
              // pinned top-right with the rows free to extend below it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _legLengthBar(context, transitLegs)),
                  if (journey.price != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      journey.price!.formatted,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary),
                    ),
                  ],
                ],
              ),
            ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    String? link;
    try {
      link = await ref.read(vendoServiceProvider).shareJourney(journey);
    } catch (_) {/* no shareable link */}
    if (link == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Reise lässt sich nicht teilen.')),
      );
      return;
    }
    final o = journey.origin?.name ?? '';
    final d = journey.destination?.name ?? '';
    await SharePlus.instance.share(
      ShareParams(
        text: journeyShareText(journey, link),
        subject: o.isNotEmpty && d.isNotEmpty ? '$o → $d' : 'Bahn-Reise',
      ),
    );
  }

  Widget _timeWithDelay(
      BuildContext context, DateTime? planned, int? delaySec) {
    if (planned == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          planned.hhmm,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        DelayBadge(delaySeconds: delaySec),
      ],
    );
  }

  /// Departure platform shown in the preview ("Gl. 3"), red when the train
  /// leaves from a platform other than the scheduled one (abweichende Abfahrt).
  Widget _depPlatform(BuildContext context, JourneyLeg leg) {
    final theme = Theme.of(context);
    final display = leg.departurePlatform ?? leg.plannedDeparturePlatform;
    if (display == null || display.isEmpty) return const SizedBox.shrink();
    final changed = leg.hasDeparturePlatformChange;
    final color = changed ? Colors.red : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackIcon(size: 13, color: color),
          const SizedBox(width: 3),
          if (changed && leg.plannedDeparturePlatform != null) ...[
            Text(leg.plannedDeparturePlatform!,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 3),
          ],
          Text(display,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: changed ? Colors.red : null)),
        ],
      ),
    );
  }

  /// Length comparison as ONE row per train (no duplicated bar + chips): a
  /// coloured line badge on the left, a proportional fill bar showing the share
  /// of travel time, and the % on the right. Stacks vertically, so it reads
  /// cleanly with 1, 2 or 4 trains and uses the width instead of crushing text.
  Widget _legLengthBar(BuildContext context, List<JourneyLeg> legs) {
    if (legs.isEmpty) return const SizedBox.shrink();
    int legMinutes(JourneyLeg l) {
      final d = l.departure ?? l.plannedDeparture;
      final a = l.arrival ?? l.plannedArrival;
      if (d != null && a != null) {
        final m = a.difference(d).inMinutes;
        if (m > 0) return m;
      }
      return 1;
    }

    final mins = legs.map(legMinutes).toList();
    final total = mins.fold<int>(0, (s, m) => s + m);
    if (total <= 0) return const SizedBox.shrink();
    final multi = legs.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < legs.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _legRow(
            context,
            legs[i].line?.displayName ?? '',
            multi ? (mins[i] / total * 100).round() : null,
            _productColor(context, legs[i]),
            legs[i].occupancy?.level,
          ),
        ],
      ],
    );
  }

  Widget _legRow(BuildContext context, String label, int? percent, Color color,
      OccupancyLevel? occupancy) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        border: Border.all(color: color.withAlpha(150)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.isEmpty ? '–' : label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );

    return Row(
      children: [
        badge,
        if (occupancy != null && occupancy != OccupancyLevel.unknown) ...[
          const SizedBox(width: 6),
          OccupancyIndicator(level: occupancy),
        ],
        // Proportional fill bar only when there's more than one train.
        if (percent != null) ...[
          const SizedBox(width: 8),
          Expanded(child: _fillBar(context, percent, color)),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ],
    );
  }

  /// Horizontal track filled to [percent]% in [color] (rounded ends).
  Widget _fillBar(BuildContext context, int percent, Color color) {
    final fill = percent.clamp(1, 100);
    final rest = 100 - fill;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            Expanded(flex: fill, child: Container(color: color)),
            if (rest > 0)
              Expanded(
                flex: rest,
                child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
          ],
        ),
      ),
    );
  }

  /// Colour per train product, so segments are visually distinct.
  Color _productColor(BuildContext context, JourneyLeg leg) {
    final p = (leg.line?.productName ?? leg.line?.displayName ?? '')
        .toUpperCase();
    if (p.startsWith('ICE')) return Colors.red.shade700;
    if (p.startsWith('IC') || p.startsWith('EC')) return Colors.blue.shade700;
    if (p.startsWith('RE') || p.startsWith('RB')) return Colors.teal.shade700;
    if (p.startsWith('S')) return Colors.green.shade700;
    return Theme.of(context).colorScheme.primary;
  }

}

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
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Prediction strip (Anschluss / Pünktlichkeit) on the left.
              PredictionBadge(journey: journey),
              const SizedBox(width: 12),
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
              const SizedBox(height: 6),

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

              // Proportional leg-length bar: each train's width ∝ time spent on
              // it, so you see at a glance which leg dominates the trip.
              if (transitLegs.length > 1) ...[
                const SizedBox(height: 8),
                _legLengthBar(context, transitLegs),
              ],

              const SizedBox(height: 8),

              // Product chips + occupancy
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final leg in transitLegs)
                          _productChip(context, leg),
                      ],
                    ),
                  ),
                  if (journey.price != null)
                    Text(
                      journey.price!.formatted,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary),
                    ),
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

  /// Horizontal bar split proportionally to each leg's travel time, labelled
  /// with the line name and the % of the trip spent on it.
  Widget _legLengthBar(BuildContext context, List<JourneyLeg> legs) {
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
    // Keep every leg visible: a leg never gets less than ~10% of the bar width.
    final minFlex = (total * 0.10).round().clamp(1, total);

    return Row(
      children: [
        for (var i = 0; i < legs.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            flex: mins[i] < minFlex ? minFlex : mins[i],
            child: _legSegment(
              context,
              legs[i].line?.displayName ?? '',
              (mins[i] / total * 100).round(),
              _productColor(context, legs[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _legSegment(
      BuildContext context, String label, int percent, Color color) {
    return Container(
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        border: Border.all(color: color.withAlpha(160)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label.isEmpty ? '$percent%' : '$label · $percent%',
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
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

  Widget _productChip(BuildContext context, JourneyLeg leg) {
    final name = leg.line?.displayName ?? '';
    if (name.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          if (leg.occupancy != null) ...[
            const SizedBox(width: 4),
            OccupancyIndicator(level: leg.occupancy!.level),
          ],
        ],
      ),
    );
  }
}

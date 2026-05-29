import 'package:flutter/material.dart';
import '../../../models/trip.dart';
import '../../../core/extensions.dart';
import '../../../widgets/delay_badge.dart';
import '../../../widgets/platform_badge.dart';

class StopTimeline extends StatelessWidget {
  final List<Stopover> stopovers;

  /// Tapping a stop opens its station map (with the boarding Gleis highlighted).
  final void Function(Stopover stop)? onStopTap;

  const StopTimeline({super.key, required this.stopovers, this.onStopTap});

  @override
  Widget build(BuildContext context) {
    if (stopovers.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Halte',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            for (int i = 0; i < stopovers.length; i++)
              InkWell(
                onTap: onStopTap == null
                    ? null
                    : () => onStopTap!(stopovers[i]),
                child: _StopRow(
                  stopover: stopovers[i],
                  isFirst: i == 0,
                  isLast: i == stopovers.length - 1,
                  tappable: onStopTap != null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  final Stopover stopover;
  final bool isFirst;
  final bool isLast;
  final bool tappable;

  const _StopRow({
    required this.stopover,
    required this.isFirst,
    required this.isLast,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPast = stopover.isPast;
    final textColor = isPast
        ? theme.colorScheme.onSurfaceVariant.withAlpha(150)
        : theme.colorScheme.onSurface;

    // Times
    final arrTime = stopover.plannedArrival?.hhmm;
    final depTime = stopover.plannedDeparture?.hhmm;
    final displayTime = isFirst ? depTime : (isLast ? arrTime : depTime ?? arrTime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time column
            SizedBox(
              width: 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (displayTime != null)
                    Text(
                      displayTime,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: stopover.cancelled ? Colors.red : textColor,
                        decoration: stopover.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Timeline line
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  if (!isFirst)
                    Container(
                      width: 2,
                      height: 8,
                      color: isPast
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.primary.withAlpha(60),
                    ),
                  Container(
                    width: isFirst || isLast ? 14 : 10,
                    height: isFirst || isLast ? 14 : 10,
                    decoration: BoxDecoration(
                      color: stopover.cancelled
                          ? Colors.red
                          : isPast
                              ? theme.colorScheme.outlineVariant
                              : theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: isFirst || isLast
                          ? Border.all(
                              color: theme.colorScheme.primary.withAlpha(100),
                              width: 2)
                          : null,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isPast
                            ? theme.colorScheme.outlineVariant
                            : theme.colorScheme.primary.withAlpha(60),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Station info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stopover.stop.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isFirst || isLast
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color:
                                  stopover.cancelled ? Colors.red : textColor,
                              decoration: stopover.cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (tappable) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.map_outlined,
                              size: 15,
                              color: Theme.of(context).colorScheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        DelayBadge(
                          delaySeconds:
                              stopover.departureDelay ?? stopover.arrivalDelay,
                          cancelled: stopover.cancelled,
                        ),
                        if (stopover.platform != null) ...[
                          const SizedBox(width: 8),
                          PlatformBadge(
                            platform: stopover.platform,
                            plannedPlatform: stopover.plannedPlatform,
                          ),
                        ],
                      ],
                    ),

                    // Show both arr and dep times for intermediate stops
                    if (!isFirst && !isLast &&
                        arrTime != null && depTime != null &&
                        arrTime != depTime)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'an $arrTime  ab $depTime',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

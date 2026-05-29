import 'package:flutter/material.dart';
import '../../../models/trip.dart';
import '../../../core/extensions.dart';

class TrainInfoHeader extends StatelessWidget {
  final Trip trip;

  const TrainInfoHeader({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = trip.stopovers.firstOrNull;
    final destination = trip.stopovers.lastOrNull;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Train name and direction
            Row(
              children: [
                _productBadge(context, trip.line.productName),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.line.displayName,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '→ ${trip.direction}',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),

            if (trip.line.operatorName != null) ...[
              const SizedBox(height: 2),
              Text(
                trip.line.operatorName!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            const Divider(height: 24),

            // Origin -> Destination with times
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(origin?.stop.name ?? '',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (origin?.plannedDeparture != null)
                        _timeRow(
                          context,
                          origin!.plannedDeparture!.hhmm,
                          origin.departureDelay,
                        ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward,
                    color: theme.colorScheme.onSurfaceVariant),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(destination?.stop.name ?? '',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          textAlign: TextAlign.end),
                      if (destination?.plannedArrival != null)
                        _timeRow(
                          context,
                          destination!.plannedArrival!.hhmm,
                          destination.arrivalDelay,
                          alignEnd: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Info chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _infoChip(Icons.stop_circle_outlined,
                    '${trip.stopovers.length} Halte'),
                if (trip.currentStop != null)
                  _infoChip(Icons.location_on,
                      'Nächst: ${trip.currentStop!.stop.name}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _productBadge(BuildContext context, String product) {
    final color = switch (product.toUpperCase()) {
      'ICE' => Colors.white,
      'IC' || 'EC' => Colors.grey.shade200,
      _ => Theme.of(context).colorScheme.primaryContainer,
    };
    final textColor = switch (product.toUpperCase()) {
      'ICE' => Colors.red.shade700,
      'IC' || 'EC' => Colors.grey.shade700,
      _ => Theme.of(context).colorScheme.onPrimaryContainer,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withAlpha(60)),
      ),
      child: Text(
        product.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _timeRow(BuildContext context, String time, int? delaySeconds,
      {bool alignEnd = false}) {
    final minutes = delaySeconds != null ? delaySeconds ~/ 60 : 0;
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Text(time, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        if (minutes > 0) ...[
          const SizedBox(width: 4),
          Text('+$minutes',
              style: TextStyle(
                  color: minutes <= 5 ? Colors.orange : Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

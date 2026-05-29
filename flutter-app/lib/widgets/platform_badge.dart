import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PlatformBadge extends StatelessWidget {
  final String? platform;
  final String? plannedPlatform;

  const PlatformBadge({super.key, this.platform, this.plannedPlatform});

  @override
  Widget build(BuildContext context) {
    final display = platform ?? plannedPlatform;
    if (display == null || display.isEmpty) return const SizedBox.shrink();

    final changed = platform != null &&
        plannedPlatform != null &&
        platform != plannedPlatform;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.layers, size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 2),
        if (changed && plannedPlatform != null) ...[
          Text(
            plannedPlatform!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          display,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: changed ? AppColors.delay : null,
          ),
        ),
      ],
    );
  }
}

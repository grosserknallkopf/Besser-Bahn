import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class DelayBadge extends StatelessWidget {
  final int? delaySeconds;
  final bool cancelled;

  const DelayBadge({super.key, this.delaySeconds, this.cancelled = false});

  @override
  Widget build(BuildContext context) {
    if (cancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.cancelled,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Ausfall',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (delaySeconds == null || delaySeconds == 0) {
      return const SizedBox.shrink();
    }

    final minutes = delaySeconds! ~/ 60;
    final color = minutes <= 5 ? AppColors.warning : AppColors.delay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        '+$minutes',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Small painted rail-track glyph (two rails + sleepers) used as the Gleis
/// marker everywhere — clearer than a generic icon and consistent across the
/// departure/arrival ends so the platform reads the same on both sides.
class TrackIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const TrackIcon({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TrackPainter(c)),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final Color color;
  const _TrackPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    // Two slightly converging rails (top-down track in light perspective).
    final railTop = h * 0.08, railBot = h * 0.92;
    canvas.drawLine(Offset(w * 0.30, railTop), Offset(w * 0.22, railBot), p);
    canvas.drawLine(Offset(w * 0.70, railTop), Offset(w * 0.78, railBot), p);
    // Sleepers across the rails.
    for (final t in const [0.22, 0.5, 0.78]) {
      final y = railTop + (railBot - railTop) * t;
      final inset = w * 0.06 * (t - 0.5).abs() * 2; // mirror the convergence
      canvas.drawLine(
          Offset(w * 0.14 + inset, y), Offset(w * 0.86 - inset, y), p);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.color != color;
}

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
        TrackIcon(
            size: 14,
            color: changed
                ? AppColors.delay
                : Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
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

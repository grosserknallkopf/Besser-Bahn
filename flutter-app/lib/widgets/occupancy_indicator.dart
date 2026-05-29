import 'package:flutter/material.dart';
import '../models/journey.dart';

class OccupancyIndicator extends StatelessWidget {
  final OccupancyLevel level;

  const OccupancyIndicator({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    if (level == OccupancyLevel.unknown) return const SizedBox.shrink();

    final (color, filled) = switch (level) {
      OccupancyLevel.low => (Colors.green, 1),
      OccupancyLevel.medium => (Colors.orange, 2),
      OccupancyLevel.high => (Colors.red, 3),
      OccupancyLevel.veryHigh => (Colors.red.shade900, 3),
      OccupancyLevel.unknown => (Colors.grey, 0),
    };

    return Tooltip(
      message: level.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 1),
            child: Icon(
              Icons.person,
              size: 14,
              color: i < filled ? color : color.withAlpha(50),
            ),
          );
        }),
      ),
    );
  }
}

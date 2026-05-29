import 'package:flutter/material.dart';
import '../../../models/coach_sequence.dart';
import '../../../theme/app_colors.dart';

class CoachSequenceView extends StatelessWidget {
  final CoachSequence sequence;

  /// When true the train doubles as a seat-plan picker: passenger cars become
  /// tappable, show their free-seat count and highlight the selected one.
  final bool selectable;

  /// Free-seat count per wagon number (from the seat map), shown on each car.
  final Map<int, int> freeByWagon;
  final int? selectedWagon;
  final void Function(Coach coach)? onCoachTap;

  const CoachSequenceView({
    super.key,
    required this.sequence,
    this.selectable = false,
    this.freeByWagon = const {},
    this.selectedWagon,
    this.onCoachTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coaches = sequence.allCoaches;
    if (coaches.isEmpty) return const SizedBox.shrink();

    final platformLength = sequence.platform.length;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Wagenreihung',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Gleis ${sequence.departurePlatform}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (sequence.hasPlatformChange) ...[
                  const SizedBox(width: 4),
                  Text('(plan: ${sequence.scheduledPlatform})',
                      style: TextStyle(
                          color: AppColors.delay,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // Sector labels
            if (sequence.platform.sectors.isNotEmpty && platformLength > 0)
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    for (final sector in sequence.platform.sectors)
                      Expanded(
                        flex: ((sector.end - sector.start) / platformLength * 1000)
                            .round(),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: theme.colorScheme.outlineVariant),
                            ),
                          ),
                          child: Text(
                            sector.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Coach visualization as a connected train (horizontal scroll)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < coaches.length; i++) ...[
                    _Car(
                      coach: coaches[i],
                      isFront: i == 0,
                      isRear: i == coaches.length - 1,
                      selectable: selectable,
                      freeCount: freeByWagon[coaches[i].wagonNumber],
                      isSelected: selectedWagon != null &&
                          coaches[i].wagonNumber == selectedWagon,
                      onTap: onCoachTap == null
                          ? null
                          : () => onCoachTap!(coaches[i]),
                    ),
                    if (i < coaches.length - 1) const _Coupler(),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendItem(AppColors.firstClass, '1. Klasse'),
                _legendItem(AppColors.secondClass, '2. Klasse'),
                _legendItem(AppColors.restaurant, 'Restaurant'),
                _legendItem(AppColors.locomotive, 'Triebkopf'),
              ],
            ),

            // Groups info (multiple train portions)
            if (sequence.groups.length > 1) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              for (final group in sequence.groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.train, size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '${group.transport.category} ${group.transport.number}'
                        ' → ${group.transport.destination ?? ""}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

/// Coupler bar drawn between two cars to make the train look connected.
class _Coupler extends StatelessWidget {
  const _Coupler();
  @override
  Widget build(BuildContext context) => Container(
        width: 4,
        height: 4,
        color: AppColors.locomotive.withAlpha(140),
      );
}

/// A single car drawn train-style. End power cars (Triebköpfe) get a tapered
/// ICE-like nose; passenger cars get a class stripe + window band.
class _Car extends StatelessWidget {
  final Coach coach;
  final bool isFront;
  final bool isRear;
  final bool selectable;
  final int? freeCount;
  final bool isSelected;
  final VoidCallback? onTap;

  const _Car({
    required this.coach,
    required this.isFront,
    required this.isRear,
    this.selectable = false,
    this.freeCount,
    this.isSelected = false,
    this.onTap,
  });

  Color get _classColor => coach.isLocomotive
      ? AppColors.locomotive
      : coach.isRestaurant
          ? AppColors.restaurant
          : coach.isFirstClass
              ? AppColors.firstClass
              : coach.isMixed
                  ? AppColors.firstClass
                  : AppColors.secondClass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = coach.isOpen;
    final accent = open ? _classColor : AppColors.closedCoach;
    final isHead = coach.isLocomotive && (isFront || isRear);
    final canSelect = selectable && !coach.isLocomotive && coach.wagonNumber > 0;
    final borderColor = isSelected ? AppColors.onTime : accent;

    // ICE nose: strong rounding on the outer end of an end power car.
    final noseSide = isHead
        ? (isFront
            ? const BorderRadius.horizontal(
                left: Radius.circular(20), right: Radius.circular(5))
            : const BorderRadius.horizontal(
                left: Radius.circular(5), right: Radius.circular(20)))
        : BorderRadius.circular(5);

    final car = Container(
      width: isHead ? 46 : 54,
      height: 46,
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.onTime.withValues(alpha: 0.16)
            : isHead
                ? AppColors.locomotive
                : theme.colorScheme.surfaceContainerHighest,
        borderRadius: noseSide,
        border: Border.all(color: borderColor, width: isSelected ? 3 : 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: isHead
          ? const Center(
              child: Icon(Icons.train, color: Colors.white, size: 20))
          : Column(
              children: [
                // class stripe
                Container(height: 5, color: accent),
                // window band
                Expanded(
                  child: Center(
                    child: Text(
                      coach.wagonNumber > 0 ? '${coach.wagonNumber}' : '–',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: open ? null : Colors.grey,
                      ),
                    ),
                  ),
                ),
                // free-seat count when selecting; amenity icons otherwise.
                SizedBox(
                  height: 15,
                  child: freeCount != null
                      ? Center(
                          child: Text('$freeCount frei',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: freeCount! > 0
                                    ? AppColors.onTime
                                    : AppColors.closedCoach,
                              )),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (coach.hasBikeSpace)
                              const Icon(Icons.pedal_bike, size: 11),
                            if (coach.hasQuietZone)
                              const Icon(Icons.volume_off, size: 11),
                            if (coach.hasFamilyZone)
                              const Icon(Icons.family_restroom, size: 11),
                            if (coach.hasWheelchairSpace)
                              const Icon(Icons.accessible, size: 11),
                            if (coach.isRestaurant)
                              const Icon(Icons.restaurant, size: 11),
                          ],
                        ),
                ),
              ],
            ),
    );

    return Tooltip(
      message: _tooltipText(),
      child: canSelect
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: car,
            )
          : car,
    );
  }

  String _tooltipText() {
    final parts = <String>[];
    if (coach.wagonNumber > 0) parts.add('Wagen ${coach.wagonNumber}');
    if (coach.isFirstClass) parts.add('1. Klasse');
    if (coach.isSecondClass) parts.add('2. Klasse');
    if (coach.isMixed) parts.add('1./2. Klasse');
    if (coach.isRestaurant) parts.add('Bordrestaurant');
    if (coach.isLocomotive) parts.add('Triebkopf');
    if (coach.hasBikeSpace) parts.add('Fahrrad');
    if (coach.hasQuietZone) parts.add('Ruhebereich');
    if (coach.hasFamilyZone) parts.add('Familienbereich');
    if (coach.hasWheelchairSpace) parts.add('Rollstuhl');
    if (!coach.isOpen) parts.add('Gesperrt');
    if (coach.platformPosition != null) {
      parts.add('Sektor ${coach.platformPosition!.sector}');
    }
    return parts.join(' · ');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/seat_map.dart';
import '../../../models/trip.dart';
import '../../../providers/seat_map_provider.dart';
import '../../../services/seat_map_service.dart';
import '../../../theme/app_colors.dart';

/// Collapsible card that offers the seat plan for trains that have one
/// (long-distance only). Lazily builds [SeatMapView] on first expand, so the
/// gsd request only fires when the user opens it.
class SeatMapSection extends StatefulWidget {
  final Trip trip;

  const SeatMapSection({super.key, required this.trip});

  /// Whether this train carries a reservable seat plan worth offering.
  static bool isAvailableFor(Trip trip) {
    final p = trip.line.productName.toUpperCase();
    return SeatMapService.reservableProducts.contains(p) &&
        trip.stopovers.length >= 2;
  }

  @override
  State<SeatMapSection> createState() => _SeatMapSectionState();
}

class _SeatMapSectionState extends State<SeatMapSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!SeatMapSection.isAvailableFor(widget.trip)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.event_seat, color: AppColors.onTime),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Freie Sitzplätze',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            // The header inside the view repeats "Freie Sitzplätze"; trim ours
            // to just the toggle by letting the view own the section body.
            SeatMapView(trip: widget.trip),
          ],
        ],
      ),
    );
  }
}

/// Graphical "free seats" view for a train run: a coach selector strip plus the
/// selected coach's seat plan, painted from DB's own geometry. Free (status 0)
/// seats are the ones the user is after — they read green; reserved/occupied
/// read grey. Embeddable (no Scaffold).
class SeatMapView extends ConsumerStatefulWidget {
  final Trip trip;

  const SeatMapView({super.key, required this.trip});

  @override
  ConsumerState<SeatMapView> createState() => _SeatMapViewState();
}

class _SeatMapViewState extends ConsumerState<SeatMapView> {
  bool _firstClass = false;
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final req = SeatMapRequest.fromTrip(widget.trip, firstClass: _firstClass);
    if (req == null) {
      return _info(theme, 'Für diesen Zug fehlen die Daten für den Sitzplan.');
    }
    final async = ref.watch(seatMapProvider(req));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('Klasse',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              SegmentedButton<bool>(
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('2. Kl.')),
                  ButtonSegment(value: true, label: Text('1. Kl.')),
                ],
                selected: {_firstClass},
                onSelectionChanged: (s) => setState(() {
                  _firstClass = s.first;
                  _selected = 0;
                }),
              ),
            ],
          ),
        ),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _info(theme, 'Sitzplan konnte nicht geladen werden.'),
          data: (map) {
            if (map == null || map.isEmpty) {
              return _info(
                  theme,
                  _firstClass
                      ? 'Keine 1.-Klasse-Reservierungsdaten für diesen Zug.'
                      : 'Für diesen Zug ist kein Sitzplan verfügbar.');
            }
            return _content(theme, map);
          },
        ),
      ],
    );
  }

  Widget _content(ThemeData theme, SeatMap map) {
    final sel = _selected.clamp(0, map.coaches.length - 1);
    final coach = map.coaches[sel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            '${map.totalFree} von ${map.totalSeats} Plätzen frei',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        // Coach selector strip.
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            itemCount: map.coaches.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = map.coaches[i];
              final isSel = i == sel;
              final full = !c.hasFree;
              final accent = full ? AppColors.closedCoach : AppColors.onTime;
              return InkWell(
                onTap: () => setState(() => _selected = i),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 52,
                  decoration: BoxDecoration(
                    color: isSel
                        ? accent.withValues(alpha: 0.18)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSel ? accent : theme.colorScheme.outlineVariant,
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Wg ${c.number}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${c.freeCount} frei',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: full ? AppColors.closedCoach : accent,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Seat plan for the selected coach.
        if (coach.layout == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _coachFallback(theme, coach),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _CoachPlan(coach: coach, layout: coach.layout!),
                ),
              ),
            ),
          ),
        _legend(theme),
      ],
    );
  }

  // When the geometry API has no layout for this coach type, still show the
  // numbers as a simple wrap of chips so the data isn't lost.
  Widget _coachFallback(ThemeData theme, SeatCoach coach) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in coach.seats)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(s.status),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(s.number,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: s.status == SeatStatus.free
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _legend(ThemeData theme) {
    Widget chip(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(spacing: 16, runSpacing: 8, children: [
        chip(AppColors.onTime, 'frei'),
        chip(AppColors.closedCoach, 'reserviert / belegt'),
        chip(AppColors.dbRed, 'ausgewählt'),
      ]),
    );
  }

  Widget _info(ThemeData theme, String msg) => Padding(
        padding: const EdgeInsets.all(24),
        child: Row(children: [
          Icon(Icons.info_outline,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant))),
        ]),
      );
}

Color _statusColor(SeatStatus s) {
  switch (s) {
    case SeatStatus.free:
      return AppColors.onTime;
    case SeatStatus.selected:
      return AppColors.dbRed;
    case SeatStatus.occupied:
    case SeatStatus.unknown:
      return AppColors.closedCoach;
  }
}

/// Renders a single coach's seat plan from DB's grid geometry. Horizontally
/// laid out at a fixed unit scale; the parent scrolls it sideways.
class _CoachPlan extends StatelessWidget {
  final SeatCoach coach;
  final CoachLayout layout;

  const _CoachPlan({required this.coach, required this.layout});

  static const _unit = 8.0; // px per layout grid unit

  @override
  Widget build(BuildContext context) {
    final w = (layout.width + 4) * _unit;
    final h = (layout.height + 4) * _unit;
    return CustomPaint(
      size: Size(w, h),
      painter: _CoachPainter(
        coach: coach,
        layout: layout,
        unit: _unit,
        onSurfaceVariant: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _CoachPainter extends CustomPainter {
  final SeatCoach coach;
  final CoachLayout layout;
  final double unit;
  final Color onSurfaceVariant;

  _CoachPainter({
    required this.coach,
    required this.layout,
    required this.unit,
    required this.onSurfaceVariant,
  });

  // Pad so seats near the grid edges aren't clipped.
  static const _pad = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Coach body outline.
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(unit * _pad * 0.5, unit * _pad * 0.5,
          (layout.width + _pad) * unit, (layout.height + _pad) * unit),
      Radius.circular(unit * 1.5),
    );
    canvas.drawRRect(
        bodyRect,
        Paint()
          ..color = onSurfaceVariant.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    final seatSize = unit * 3.0;
    for (final el in layout.elements) {
      final cx = (el.x + _pad) * unit;
      final cy = (el.y + _pad) * unit;
      switch (el.type) {
        case LayoutElementType.platz:
          _paintSeat(canvas, el, cx, cy, seatSize);
          break;
        case LayoutElementType.einbau:
          _paintFixture(canvas, el, cx, cy);
          break;
        case LayoutElementType.symbol:
          _paintSymbol(canvas, el, cx, cy);
          break;
        case LayoutElementType.unknown:
          break;
      }
    }
  }

  void _paintSeat(
      Canvas canvas, LayoutElement el, double cx, double cy, double s) {
    final status = coach.statusOf(el.number ?? '');
    final color = _statusColor(status);
    final rect = Rect.fromLTWH(cx, cy, s, s);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(unit * 0.6));
    canvas.drawRRect(rrect, Paint()..color = color);

    // Backrest: a thicker bar on the side the seat faces.
    final back = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = unit * 0.7
      ..strokeCap = StrokeCap.round;
    switch (el.direction) {
      case ElementDirection.links:
        canvas.drawLine(rect.topLeft, rect.bottomLeft, back);
        break;
      case ElementDirection.rechts:
        canvas.drawLine(rect.topRight, rect.bottomRight, back);
        break;
      case ElementDirection.oben:
        canvas.drawLine(rect.topLeft, rect.topRight, back);
        break;
      case ElementDirection.unten:
        canvas.drawLine(rect.bottomLeft, rect.bottomRight, back);
        break;
      case ElementDirection.none:
        break;
    }

    // Seat number, when it fits.
    if (s >= unit * 2.4 && (el.number?.isNotEmpty ?? false)) {
      final tp = TextPainter(
        text: TextSpan(
          text: el.number,
          style: TextStyle(
            fontSize: unit * 1.25,
            fontWeight: FontWeight.w700,
            color: status == SeatStatus.free
                ? Colors.white
                : Colors.black.withValues(alpha: 0.55),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: s);
      tp.paint(canvas, Offset(cx + (s - tp.width) / 2, cy + (s - tp.height) / 2));
    }
  }

  void _paintFixture(Canvas canvas, LayoutElement el, double cx, double cy) {
    final paint = Paint()..color = onSurfaceVariant.withValues(alpha: 0.3);
    final sub = el.subtype ?? '';
    if (sub.startsWith('TISCH')) {
      // Table block.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx, cy, unit * 2.4, unit * 2.4),
            Radius.circular(unit * 0.4)),
        paint,
      );
    } else if (sub.startsWith('WAND')) {
      // Partition wall — a short thick line.
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx, cy + unit * 2.4),
        Paint()
          ..color = onSurfaceVariant.withValues(alpha: 0.45)
          ..strokeWidth = unit * 0.6,
      );
    }
  }

  void _paintSymbol(Canvas canvas, LayoutElement el, double cx, double cy) {
    final icon = _symbolIcon(el.subtype);
    final size = unit * 2.4;
    if (icon == null) {
      // Class markers etc. — render the bare label.
      final label = _symbolLabel(el.subtype);
      if (label == null) return;
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                fontSize: unit * 1.6,
                fontWeight: FontWeight.bold,
                color: onSurfaceVariant)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx, cy));
      return;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: onSurfaceVariant,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx, cy));
  }

  IconData? _symbolIcon(String? subtype) {
    switch (subtype) {
      case 'WC':
      case 'WC_BEHINDERT':
        return Icons.wc;
      case 'FAHRRAD':
        return Icons.directions_bike;
      case 'HANDY':
        return Icons.smartphone;
      case 'BEHINDERT':
      case 'ROLLSTUHL':
        return Icons.accessible;
      case 'GEPAECK':
        return Icons.luggage;
      case 'RESTAURANT':
      case 'BISTRO':
        return Icons.restaurant;
      case 'KINDER':
      case 'KLEINKIND':
        return Icons.child_friendly;
      case 'RUHE':
        return Icons.volume_off;
      case 'STROM':
      case 'STECKDOSE':
        return Icons.power;
      default:
        return null;
    }
  }

  String? _symbolLabel(String? subtype) {
    switch (subtype) {
      case 'KLASSE_1':
        return '1';
      case 'KLASSE_2':
        return '2';
      default:
        return null;
    }
  }

  @override
  bool shouldRepaint(covariant _CoachPainter old) =>
      old.coach != coach || old.layout != layout;
}

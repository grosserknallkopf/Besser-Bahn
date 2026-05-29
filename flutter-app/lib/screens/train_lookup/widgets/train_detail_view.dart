import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/coach_sequence.dart';
import '../../../models/seat_map.dart';
import '../../../models/trip.dart';
import '../../../providers/seat_map_provider.dart';
import 'coach_sequence_view.dart';
import 'seat_map_view.dart';
import 'stop_timeline.dart';
import 'train_info_header.dart';
import 'train_map_view.dart';

/// The full detail of one train: header, live map, coach sequence and stop
/// timeline. Used standalone on the train screen and stacked per leg in the
/// connection view. Returns column children (no Scaffold) so it can be embedded.
///
/// When the train has a reservable seat plan, the Wagenreihung doubles as the
/// coach picker for the "Freie Sitzplätze" panel below — so coaches aren't
/// drawn twice. Selection + class + expand state live here and feed both.
class TrainDetailView extends ConsumerStatefulWidget {
  final Trip trip;
  final CoachSequence? coach;
  final void Function(Stopover stop)? onStopTap;

  /// EVA / name of the stop you board at and alight at on this leg. When set,
  /// the timeline collapses stops outside that segment (e.g. the train's run
  /// before your boarding station). Null = standalone train, show all stops.
  final String? boardingId;
  final String? alightingId;

  const TrainDetailView({
    super.key,
    required this.trip,
    this.coach,
    this.onStopTap,
    this.boardingId,
    this.alightingId,
  });

  @override
  ConsumerState<TrainDetailView> createState() => _TrainDetailViewState();
}

class _TrainDetailViewState extends ConsumerState<TrainDetailView> {
  bool _seatsExpanded = false;
  bool _firstClass = false;
  int? _selectedWagon; // explicit user pick; null → auto (first free)

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final reservable = SeatPlanSection.isAvailableFor(trip);

    // Only fetch the seat map once the panel is open.
    final req = (_seatsExpanded && reservable)
        ? SeatMapRequest.fromTrip(trip, firstClass: _firstClass)
        : null;
    final seatAsync =
        req != null ? ref.watch(seatMapProvider(req)) : null;
    final SeatMap? seatMap =
        seatAsync?.maybeWhen(data: (m) => m, orElse: () => null);

    // Free-seat count per wagon, and the effective selection (explicit pick or
    // first coach with free seats) shared by the Wagenreihung and the panel.
    final freeByWagon = <int, int>{};
    if (seatMap != null) {
      for (final c in seatMap.coaches) {
        final nr = int.tryParse(c.number);
        if (nr != null) freeByWagon[nr] = c.freeCount;
      }
    }
    final effectiveWagon = _effectiveWagon(seatMap);

    final hasWagenreihung = widget.coach != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TrainInfoHeader(trip: trip),
        TrainMapView(trip: trip),
        if (widget.coach != null)
          CoachSequenceView(
            sequence: widget.coach!,
            // Turn the train into the seat-plan picker once the panel is open.
            selectable: _seatsExpanded && reservable,
            freeByWagon: freeByWagon,
            selectedWagon: effectiveWagon,
            onCoachTap: (c) => setState(() => _selectedWagon = c.wagonNumber),
          ),
        SeatPlanSection(
          trip: trip,
          expanded: _seatsExpanded,
          onToggle: () => setState(() => _seatsExpanded = !_seatsExpanded),
          firstClass: _firstClass,
          onFirstClass: (v) => setState(() {
            _firstClass = v;
            _selectedWagon = null;
          }),
          seatAsync: seatAsync,
          selectedWagon: effectiveWagon,
          onSelectWagon: (nr) => setState(() => _selectedWagon = nr),
          hasExternalSelector: hasWagenreihung,
        ),
        StopTimeline(
          stopovers: trip.stopovers,
          onStopTap: widget.onStopTap,
          boardingId: widget.boardingId,
          alightingId: widget.alightingId,
        ),
      ],
    );
  }

  int? _effectiveWagon(SeatMap? map) {
    if (_selectedWagon != null) return _selectedWagon;
    if (map == null) return null;
    for (final c in map.coaches) {
      if (c.hasFree) return int.tryParse(c.number);
    }
    return map.coaches.isNotEmpty ? int.tryParse(map.coaches.first.number) : null;
  }
}

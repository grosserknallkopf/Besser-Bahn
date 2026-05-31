import '../models/journey.dart';

/// Where a journey is right now. Drives the "Bald" / "Unterwegs" / "Beendet"
/// presentation.
enum TripPhase { upcoming, onBoard, finished }

/// Client-side "Reisefortschritt" computed purely from a journey's times — the
/// single source of truth shared by the in-app progress card and any future
/// OS surface (Live Activity, home-screen widget, watch face). No server push:
/// every value here is derived on-device from the saved/live itinerary.
class TripProgress {
  final TripPhase phase;

  /// 0‥1 fraction of the way from first departure to final arrival (0 before
  /// boarding, 1 once arrived).
  final double fraction;

  /// Minutes until departure (>=0) while [phase] is upcoming, else 0.
  final int minutesToDeparture;

  /// Minutes until final arrival (>=0) while not finished, else 0.
  final int minutesToArrival;

  /// The next transfer station still ahead, or null (single leg / already past
  /// the last transfer / not started).
  final String? nextTransferStation;

  /// Minutes until that transfer's train departs, or null.
  final int? minutesToTransfer;

  final String originName;
  final String destinationName;

  const TripProgress({
    required this.phase,
    required this.fraction,
    required this.minutesToDeparture,
    required this.minutesToArrival,
    required this.originName,
    required this.destinationName,
    this.nextTransferStation,
    this.minutesToTransfer,
  });

  /// True when the trip is worth surfacing now: in progress, or departing
  /// within [soon] (default 3 h). Far-future and finished trips return false.
  bool isActive({Duration soon = const Duration(hours: 3)}) {
    if (phase == TripPhase.onBoard) return true;
    if (phase == TripPhase.upcoming) {
      return minutesToDeparture <= soon.inMinutes;
    }
    return false;
  }

  /// Compute progress for [journey] as of [now] (defaults to wall clock).
  static TripProgress? of(Journey journey, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final transit = journey.legs.where((l) => !l.isWalking).toList();
    if (transit.isEmpty) return null;
    final dep = transit.first.departure ?? transit.first.plannedDeparture;
    final arr = transit.last.arrival ?? transit.last.plannedArrival;
    if (dep == null || arr == null) return null;

    final origin = transit.first.origin.name;
    final dest = transit.last.destination.name;

    if (clock.isAfter(arr)) {
      return TripProgress(
        phase: TripPhase.finished,
        fraction: 1,
        minutesToDeparture: 0,
        minutesToArrival: 0,
        originName: origin,
        destinationName: dest,
      );
    }

    if (clock.isBefore(dep)) {
      return TripProgress(
        phase: TripPhase.upcoming,
        fraction: 0,
        minutesToDeparture: dep.difference(clock).inMinutes,
        minutesToArrival: arr.difference(clock).inMinutes,
        originName: origin,
        destinationName: dest,
      );
    }

    // On board: progress + next transfer.
    final total = arr.difference(dep).inSeconds;
    final done = clock.difference(dep).inSeconds;
    String? transferStation;
    int? minsToTransfer;
    for (final leg in transit) {
      final lDep = leg.departure ?? leg.plannedDeparture;
      if (lDep != null && lDep.isAfter(clock)) {
        transferStation = leg.origin.name;
        minsToTransfer = lDep.difference(clock).inMinutes;
        break;
      }
    }
    return TripProgress(
      phase: TripPhase.onBoard,
      fraction: total <= 0 ? 1 : (done / total).clamp(0.0, 1.0),
      minutesToDeparture: 0,
      minutesToArrival: arr.difference(clock).inMinutes,
      originName: origin,
      destinationName: dest,
      nextTransferStation: transferStation,
      minutesToTransfer: minsToTransfer,
    );
  }
}

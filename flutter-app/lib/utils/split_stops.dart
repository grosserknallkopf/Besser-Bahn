import '../models/journey.dart';

/// Build the ordered, de-duplicated station list (split candidates) for a
/// journey straight from its legs — the Vendo search already carries every
/// `halt` in `leg.stopovers`, so no extra trip fetch is needed. Mirrors the
/// connection-detail split entry, minus the on-screen trip cache, so the bulk
/// comparison and the single analysis break at the same stations.
///
/// Each entry is `{name, id, departure_iso}`, ready for the split engine.
/// The candidate count is capped (the pairwise price scan grows with its
/// square): every leg boundary (start / terminus / transfer) is kept and the
/// intermediate stops are evenly sampled down to [cap].
List<Map<String, dynamic>> splitStopsFromJourney(Journey journey,
    {int cap = 12}) {
  final stops = <Map<String, dynamic>>[];

  void add(String id, String name, DateTime? dep, bool boundary) {
    if (id.isEmpty) return;
    if (stops.isNotEmpty && stops.last['id'] == id) {
      if (dep != null) stops.last['departure_iso'] = dep.toIso8601String();
      if (boundary) stops.last['_boundary'] = true;
      return;
    }
    stops.add({
      'name': name,
      'id': id,
      'departure_iso': dep?.toIso8601String() ?? '',
      '_boundary': boundary,
    });
  }

  for (final leg in journey.legs) {
    if (leg.isWalking) continue;
    if (leg.stopovers.isNotEmpty) {
      final n = leg.stopovers.length;
      for (var i = 0; i < n; i++) {
        final so = leg.stopovers[i];
        add(so.stop.id, so.stop.name, so.departure ?? so.arrival,
            i == 0 || i == n - 1);
      }
    } else {
      add(leg.origin.id, leg.origin.name,
          leg.plannedDeparture ?? leg.departure, true);
      add(leg.destination.id, leg.destination.name, leg.arrival, true);
    }
  }

  if (stops.length > cap) {
    final boundaries = stops.where((s) => s['_boundary'] == true).toList();
    final inner = stops.where((s) => s['_boundary'] != true).toList();
    final slots = (cap - boundaries.length).clamp(0, inner.length);
    final keep = <Map<String, dynamic>>{...boundaries};
    if (slots > 0) {
      final step = inner.length / slots;
      for (var k = 0; k < slots; k++) {
        keep.add(inner[(k * step).floor()]);
      }
    }
    stops.removeWhere((s) => !keep.contains(s));
  }

  return stops;
}

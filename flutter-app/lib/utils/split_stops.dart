import '../models/journey.dart';

/// Products the Deutschlandticket is valid on: local and regional transport
/// only. Anything else (ICE/IC/EC, and any product we can't identify) needs a
/// ticket.
const _dTicketProducts = {
  'regional',
  'suburban',
  'subway',
  'tram',
  'bus',
  'ferry',
};

/// Is the segment from stop [i] to stop [j] of [stops] entirely travelled on
/// trains the Deutschlandticket covers?
///
/// Answered from the SELECTED connection's own trains (see `_product` above),
/// so it needs no network call and can't be fooled by a cheaper regional
/// alternative that the rider isn't taking. ALL hops must be covered: one ICE
/// hop makes the whole segment payable — the bug behind #13, where any single
/// D-Ticket-eligible section marked an ICE segment as free.
bool isSegmentDTicketCovered(
    List<Map<String, dynamic>> stops, int i, int j) {
  for (var k = i; k < j; k++) {
    final product = stops[k]['_product'];
    // '' = no train on this hop (transfer gap) → fare-neutral, keep checking.
    if (product == '') continue;
    // null = an onward train we couldn't identify → assume it needs a ticket.
    if (product is! String || !_dTicketProducts.contains(product)) return false;
  }
  return true;
}

/// Build the ordered, de-duplicated station list (split candidates) for a
/// journey straight from its legs — the Vendo search already carries every
/// `halt` in `leg.stopovers`, so no extra trip fetch is needed. Mirrors the
/// connection-detail split entry, minus the on-screen trip cache, so the bulk
/// comparison and the single analysis break at the same stations.
///
/// Each entry is `{name, id, departure_iso}`, ready for the split engine.
///
/// Each stop also carries `_product`, describing how the SELECTED connection
/// travels *onward* from it. That's what makes "is this hop covered by the
/// Deutschlandticket" answerable about the connection the rider actually
/// picked, rather than about some other train that happens to serve the same
/// pair of stations (#13). Three cases, deliberately distinct:
///
///  * a product string (`regional`, `nationalExpress`, …) — the onward train
///  * `''` — no train leaves here: the journey's last stop, or a transfer gap
///    between two legs. Fare-neutral.
///  * `null` — there IS an onward train but its product is unknown. Must block
///    coverage, or an unidentified ICE reads as free.
///
/// The candidate count is capped (the pairwise price scan grows with its
/// square): every leg boundary (start / terminus / transfer) is kept and the
/// intermediate stops are evenly sampled down to [cap].
List<Map<String, dynamic>> splitStopsFromJourney(Journey journey,
    {int cap = 12}) {
  final stops = <Map<String, dynamic>>[];

  void add(String id, String name, DateTime? dep, bool boundary,
      String? product) {
    if (id.isEmpty) return;
    if (stops.isNotEmpty && stops.last['id'] == id) {
      if (dep != null) stops.last['departure_iso'] = dep.toIso8601String();
      if (boundary) stops.last['_boundary'] = true;
      // A transfer stop is arrived at on one train and left on the next — the
      // onward product is the one that matters, so it overwrites the ''
      // the arriving leg left here.
      stops.last['_product'] = product;
      return;
    }
    stops.add({
      'name': name,
      'id': id,
      'departure_iso': dep?.toIso8601String() ?? '',
      '_boundary': boundary,
      '_product': product,
    });
  }

  for (final leg in journey.legs) {
    if (leg.isWalking) continue;
    // Every stop of this leg except its last is left aboard THIS train. A leg
    // with no line data yields null → unknown, which blocks coverage.
    final product = leg.line != null ? (leg.line!.product) : null;
    if (leg.stopovers.isNotEmpty) {
      final n = leg.stopovers.length;
      for (var i = 0; i < n; i++) {
        final so = leg.stopovers[i];
        add(so.stop.id, so.stop.name, so.departure ?? so.arrival,
            i == 0 || i == n - 1, i == n - 1 ? '' : product);
      }
    } else {
      add(leg.origin.id, leg.origin.name,
          leg.plannedDeparture ?? leg.departure, true, product);
      add(leg.destination.id, leg.destination.name, leg.arrival, true, '');
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

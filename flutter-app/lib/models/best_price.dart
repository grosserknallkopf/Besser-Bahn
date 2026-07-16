import 'journey.dart';

/// One time-of-day slot of DB's Bestpreis calendar (`tagesbestpreis`, #21).
///
/// The whole day comes back in ONE request — six slots, each with its cheapest
/// offer and the connections behind it. Reproducing that with the normal search
/// would take ~6 paginated calls against a backend that starts refusing after
/// ~10 in six seconds.
class BestPriceInterval {
  /// Slot bounds, e.g. 19:00 → 00:00. DB picks them, they are not uniform.
  final DateTime from;
  final DateTime to;

  /// Cheapest offer in this slot (`angebotsPreis`), or null when nothing is on
  /// offer — a slot with connections but no price is normal (late trains, a
  /// leg with no Sparpreis).
  final double? price;
  final String currency;

  /// DB's own flag for the cheapest slot of the day (`istBestpreis`) — read
  /// rather than recomputed, so we mark what DB would mark.
  final bool isBest;

  /// The price covers only part of the trip (`istTeilpreis`), so it can't be
  /// compared with a full-trip price on another slot.
  final bool isPartialPrice;

  /// The connections behind the slot — the same shape the normal search
  /// returns, `kontext` included, so detail/share/split all work off them.
  final List<Journey> journeys;

  const BestPriceInterval({
    required this.from,
    required this.to,
    this.price,
    this.currency = 'EUR',
    this.isBest = false,
    this.isPartialPrice = false,
    this.journeys = const [],
  });

  String? get formattedPrice =>
      price == null ? null : '${price!.toStringAsFixed(2)} €';
}

/// The day, as [BestPriceInterval]s.
class BestPriceDay {
  final DateTime date;
  final List<BestPriceInterval> intervals;

  const BestPriceDay({required this.date, this.intervals = const []});

  /// Cheapest full-trip price of the day, ignoring part-trip prices (they
  /// aren't comparable) — used to scale the bars.
  double? get cheapest {
    final prices = [
      for (final i in intervals)
        if (i.price != null && !i.isPartialPrice) i.price!,
    ];
    return prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
  }

  double? get dearest {
    final prices = [
      for (final i in intervals)
        if (i.price != null && !i.isPartialPrice) i.price!,
    ];
    return prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b);
  }

  bool get hasPrices => cheapest != null;
}

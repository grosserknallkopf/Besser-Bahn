class Station {
  final String id; // EVA number
  final String name;
  final double? latitude;
  final double? longitude;
  final StationProducts? products;

  /// Full HAFAS location string (`A=1@O=...@L=<eva>@...`). Required by the
  /// DB Vendo journey API; the plain EVA [id] is not enough there.
  final String? locationId;

  const Station({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.products,
    this.locationId,
  });

  factory Station.fromHafas(Map<String, dynamic> json) {
    final loc = json['location'] as Map<String, dynamic>?;
    final prods = json['products'] as Map<String, dynamic>?;
    return Station(
      id: (json['id'] ?? json['extId'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      latitude: loc?['latitude'] as double? ?? json['lat'] as double?,
      longitude: loc?['longitude'] as double? ?? json['lon'] as double?,
      products: prods != null ? StationProducts.fromJson(prods) : null,
    );
  }

  factory Station.fromDbWeb(Map<String, dynamic> json) {
    // bahn.de `reiseloesung/orte` returns `id` = full HAFAS string,
    // `extId` = EVA number. Keep both.
    final full = json['id']?.toString();
    return Station(
      id: (json['extId'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      latitude: json['lat'] as double?,
      longitude: json['lon'] as double?,
      locationId: (full != null && full.contains('@')) ? full : null,
    );
  }

  /// Compact JSON for local persistence (favorites, recents, saved routes).
  /// [products] is intentionally dropped — not needed for stored stations.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lon': longitude,
        'locationId': locationId,
      };

  factory Station.fromJson(Map<String, dynamic> json) => Station(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lon'] as num?)?.toDouble(),
        locationId: json['locationId'] as String?,
      );

  bool get hasLocation => latitude != null && longitude != null;

  /// Best identifier for the DB Vendo journey API: the full HAFAS string if we
  /// have it, otherwise a minimal one built from the EVA number.
  String get vendoLocationId =>
      locationId ?? (id.isNotEmpty ? 'A=1@L=$id@' : id);
}

class StationProducts {
  final bool nationalExpress; // ICE
  final bool national; // IC/EC
  final bool regionalExpress;
  final bool regional;
  final bool suburban; // S-Bahn
  final bool bus;
  final bool ferry;
  final bool subway; // U-Bahn
  final bool tram;

  const StationProducts({
    this.nationalExpress = false,
    this.national = false,
    this.regionalExpress = false,
    this.regional = false,
    this.suburban = false,
    this.bus = false,
    this.ferry = false,
    this.subway = false,
    this.tram = false,
  });

  factory StationProducts.fromJson(Map<String, dynamic> json) {
    return StationProducts(
      nationalExpress: json['nationalExpress'] as bool? ?? false,
      national: json['national'] as bool? ?? false,
      regionalExpress: json['regionalExpress'] as bool? ?? false,
      regional: json['regional'] as bool? ?? false,
      suburban: json['suburban'] as bool? ?? false,
      bus: json['bus'] as bool? ?? false,
      ferry: json['ferry'] as bool? ?? false,
      subway: json['subway'] as bool? ?? false,
      tram: json['tram'] as bool? ?? false,
    );
  }
}

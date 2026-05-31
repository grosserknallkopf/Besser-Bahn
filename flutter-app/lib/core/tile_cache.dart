import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'app_log.dart';

/// A 1×1 fully transparent PNG, shown in place of a tile that fails to load so
/// flutter_map renders it silently instead of bubbling the error up to the
/// console (belt-and-suspenders with the errorTileCallback + global filter).
final Uint8List _transparentTile = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Persistent on-disk cache for map tiles (FMTC / ObjectBox backend).
///
/// Goal (user-chosen): keep ~50 MB of tiles on disk, evicting the oldest when
/// full, so re-opening the map — even after an app restart — paints instantly
/// from disk instead of re-downloading every tile.
///
/// FMTC has two independent limits:
///  * the per-store `maxLength` counts **tiles** and removes the OLDEST when
///    exceeded → this is our LRU eviction. ~50 MB ≈ 1500 tiles at ~30 KB each.
///  * `maxDatabaseSize` is a hard **KB** ceiling that *throws* (no eviction)
///    on write when hit → we set it well above the LRU target purely as a
///    safety net so we never actually hit it.
///
/// Init is best-effort: on platforms without the ObjectBox native library
/// (e.g. a plain Linux desktop build) or any failure, we silently fall back to
/// a normal [NetworkTileProvider] — the map still works, tiles just aren't
/// persisted.
class TileCache {
  TileCache._();

  static const _store = 'mapTiles';
  static const _maxTiles = 1500; // ≈ 50 MB; oldest evicted past this (LRU)

  static bool _ready = false;
  static bool get isReady => _ready;

  static Future<void> init() async {
    try {
      await FMTCObjectBoxBackend().initialise(
        // KB. Generous ceiling; the per-store maxLength keeps us near ~50 MB.
        maxDatabaseSize: 200000, // 200 MB hard cap (never expected to hit)
      );
      await FMTCStore(_store).manage.create(maxLength: _maxTiles);
      _ready = true;
      AppLog.log('tile cache ready (store "$_store", maxLength $_maxTiles)',
          tag: 'map');
    } catch (e) {
      _ready = false;
      AppLog.log('tile cache unavailable → network only ($e)', tag: 'map');
    }
  }

  /// Shared HTTP client for ALL tile fetches, with a HARD cap on concurrent
  /// connections per host. This is the core fix for "the map chokes the whole
  /// app": flutter_map/FMTC otherwise open UNLIMITED parallel connections, and
  /// NetworkTileProvider's default wraps a RetryClient that retries every
  /// failure — so a wide map fires hundreds-to-thousands of tile requests at
  /// once, saturating the app's connection pool until unrelated calls
  /// (bahnhof.de station maps, the route polyline) time out. Verified: the
  /// device reaches every host in <1 s via curl, yet the app timed out at 12 s —
  /// self-inflicted by the flood. Capping connections makes excess tiles QUEUE
  /// instead of flooding, and NO RetryClient means no failure amplification.
  static final http.Client _tileHttp = IOClient(
    HttpClient()
      ..maxConnectionsPerHost = 6
      ..connectionTimeout = const Duration(seconds: 12),
  );

  /// A caching tile provider when the cache is up, else a plain network one,
  /// wrapped in a circuit breaker (see [_BreakerTileProvider]). Both use the
  /// shared connection-capped [_tileHttp].
  /// [headers] is forwarded (e.g. the `Referer` the indoor tiles require).
  static TileProvider provider({Map<String, String>? headers}) {
    final TileProvider inner = _ready
        ? FMTCTileProvider(
            stores: const {_store: BrowseStoreStrategy.readUpdateCreate},
            loadingStrategy: BrowseLoadingStrategy.cacheFirst,
            cachedValidDuration: const Duration(days: 30),
            headers: headers,
            httpClient: _tileHttp,
          )
        : NetworkTileProvider(
            headers: headers ?? const {},
            httpClient: _tileHttp,
          );
    return _BreakerTileProvider(inner);
  }

  // --- Circuit breaker -------------------------------------------------------
  // When a tile host goes unreachable, flutter_map/FMTC re-request the missing
  // tiles relentlessly (thousands/sec was observed), saturating the connection
  // and janking the whole app — even starving unrelated API calls. The breaker
  // trips after a short burst of failures and then serves a transparent tile
  // instantly (no network) for a cooldown, so the storm can't form. It probes
  // again after the cooldown, so the map recovers on its own once the host is
  // back.
  static int _failCount = 0;
  static DateTime _windowStart = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _blockUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get tilesBlocked => DateTime.now().isBefore(_blockUntil);

  static void noteTileFailure() {
    final now = DateTime.now();
    if (now.difference(_windowStart).inSeconds >= 2) {
      _windowStart = now;
      _failCount = 0;
    }
    _failCount++;
    if (_failCount >= 250) {
      _blockUntil = now.add(const Duration(seconds: 4));
      _failCount = 0;
    }
  }

  /// OpenFreeMap "Positron" — clean light-grey Positron look, German local
  /// labels, free/keyless. Served as VECTOR tiles (rendered by vector_map_tiles)
  /// — this is the host that's REACHABLE on the user's network (CARTO's raster
  /// CDN is not, so a raster switch left the map blank + stormed). Warmed at
  /// startup so the style is ready before the first map opens.
  static const String _styleUri =
      'https://tiles.openfreemap.org/styles/positron';

  /// CARTO Positron raster — last-resort fallback ONLY if the vector style
  /// permanently fails. (Not used during loading — see [outdoorLayer].)
  static const String _fallbackTileUrl =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

  static Future<Style>? _styleFuture;
  static Style? _style;

  /// Start loading the vector style NOW (fire-and-forget) at app startup, so the
  /// first map already has it ready instead of paying the ~1-6 s fetch then.
  static void warmStyle() {
    _loadStyle().then((_) {}).catchError((_) {});
  }

  static Future<Style> _loadStyle() {
    final sw = Stopwatch()..start();
    return _styleFuture ??= StyleReader(uri: _styleUri)
        .read()
        .timeout(const Duration(seconds: 12))
        .then((s) {
      _style = s;
      AppLog.log('vector basemap style loaded in ${sw.elapsedMilliseconds}ms',
          tag: 'map');
      return s;
    }).catchError((Object e) {
      AppLog.log('vector basemap style FAILED after ${sw.elapsedMilliseconds}ms '
          '($e) → raster fallback', tag: 'map');
      throw e;
    });
  }

  /// The shared outdoor base layer (every map). Vector Positron once the style
  /// is ready (warmed at startup). While still loading → plain background (NOT
  /// a second tile host, which would double the load / storm if unreachable).
  /// Only if the vector style PERMANENTLY fails do we drop to the CARTO raster.
  static Widget outdoorLayer() {
    final ready = _style;
    if (ready != null) return _vectorLayer(ready);
    return FutureBuilder<Style>(
      future: _loadStyle(),
      builder: (context, snap) {
        if (snap.data != null) return _vectorLayer(snap.data!);
        if (snap.hasError) return _rasterFallback();
        return const SizedBox.shrink();
      },
    );
  }

  static Widget _vectorLayer(Style style) => VectorTileLayer(
        theme: style.theme,
        sprites: style.sprites,
        tileProviders: style.providers,
        fileCacheTtl: const Duration(days: 30),
        maximumZoom: 20,
        layerMode: VectorTileLayerMode.raster,
      );

  static TileLayer _rasterFallback() => TileLayer(
        urlTemplate: _fallbackTileUrl,
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: 'de.chuk.besserebahn',
        tileProvider: provider(),
        maxZoom: 20,
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
        errorImage: MemoryImage(_transparentTile),
        errorTileCallback: (_, error, _) {
          noteTileFailure();
          AppLog.tileError(error.toString());
        },
      );
}

/// Wraps a tile provider with [TileCache]'s circuit breaker: while tripped
/// (a tile host is hammering-unreachable) it serves a transparent tile instantly
/// instead of hitting the network, so a dead host can't saturate the connection.
class _BreakerTileProvider extends TileProvider {
  final TileProvider _inner;
  _BreakerTileProvider(this._inner);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    if (TileCache.tilesBlocked) return MemoryImage(_transparentTile);
    return _inner.getImage(coordinates, options);
  }

  @override
  void dispose() => _inner.dispose();
}

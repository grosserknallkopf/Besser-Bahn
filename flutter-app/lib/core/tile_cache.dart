import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

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

  /// A caching tile provider when the cache is up, else a plain network one,
  /// wrapped in a circuit breaker (see [_BreakerTileProvider]).
  /// [headers] is forwarded (e.g. the `Referer` the indoor tiles require).
  static TileProvider provider({Map<String, String>? headers}) {
    final TileProvider inner = _ready
        ? FMTCTileProvider(
            stores: const {_store: BrowseStoreStrategy.readUpdateCreate},
            loadingStrategy: BrowseLoadingStrategy.cacheFirst,
            cachedValidDuration: const Duration(days: 30),
            headers: headers,
          )
        : NetworkTileProvider(headers: headers ?? const {});
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
    if (_failCount >= 24) {
      _blockUntil = now.add(const Duration(seconds: 8));
      _failCount = 0;
      AppLog.log('tile host unreachable → pausing tile fetches 8s', tag: 'tiles');
    }
  }

  /// CARTO "Positron" raster tiles — same clean light-grey look, but plain PNG
  /// RASTER instead of vector. Raster renders far lighter: the GPU just blits
  /// ready images, whereas vector tiles re-rasterise geometry on the CPU every
  /// pan/zoom — which was the "ultra slow" map rendering, brutal on desktop GL.
  /// Keyless, multi-subdomain CDN, no style JSON to fetch → opens instantly.
  static const String _positronRaster =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

  /// The shared outdoor base layer for every map. Plain raster — no style fetch,
  /// no vector rasterisation, so it opens immediately and pans smoothly.
  static Widget outdoorLayer() => TileLayer(
        urlTemplate: _positronRaster,
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: 'de.chuk.besserebahn',
        tileProvider: provider(),
        maxZoom: 20,
        // Failed tile → transparent (no red FMTCBrowsingError dump); feed the
        // circuit breaker + the quiet [tiles] timeline.
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

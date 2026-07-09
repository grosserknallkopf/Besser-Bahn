import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
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

/// Persistent on-disk cache for raster map tiles — a pure-Dart filesystem LRU,
/// no native backend (previously FMTC's ObjectBox store, dropped so the app
/// carries no non-free native lib).
///
/// Goal (user-chosen): keep ~50 MB of tiles on disk, evicting the oldest when
/// full, so re-opening the map — even after an app restart — paints instantly
/// from disk instead of re-downloading every tile. Only the two RASTER layers
/// use this (the last-resort raster basemap fallback + bahnhof.de indoor
/// tiles); the main VECTOR basemap has its own cache in [vector_map_tiles].
///
/// Eviction: [_DiskTileStore] counts **files** and deletes the OLDEST (by
/// mtime, touched on every cache hit) past [_maxTiles] → LRU. ~50 MB ≈ 1500
/// tiles at ~30 KB each. Freshness: a cached tile older than [_validDuration]
/// is re-fetched.
///
/// Init is best-effort: on any failure (or a platform with no writable cache
/// dir) we silently fall back to a network-only [_CachingTileProvider] that
/// still shares the connection-capped client — the map works, tiles just
/// aren't persisted.
class TileCache {
  TileCache._();

  static const _maxTiles = 1500; // ≈ 50 MB; oldest evicted past this (LRU)
  static const _validDuration = Duration(days: 30);

  static bool _ready = false;
  static bool get isReady => _ready;

  static Future<void> init() async {
    try {
      await _DiskTileStore.init(maxTiles: _maxTiles);
      _ready = true;
      AppLog.log('tile cache ready (disk LRU, maxTiles $_maxTiles)', tag: 'map');
    } catch (e) {
      _ready = false;
      AppLog.log('tile cache unavailable → network only ($e)', tag: 'map');
    }
  }

  /// Shared HTTP client for ALL tile fetches, with a HARD cap on concurrent
  /// connections per host. This is the core fix for "the map chokes the whole
  /// app": flutter_map otherwise open UNLIMITED parallel connections, and
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

  /// A disk-caching (cache-first) tile provider, wrapped in a circuit breaker
  /// (see [_BreakerTileProvider]). When the disk store is down it degrades to
  /// network-only but still shares the connection-capped [_tileHttp].
  /// [headers] is forwarded (e.g. the `Referer` the indoor tiles require).
  static TileProvider provider({Map<String, String>? headers}) {
    return _BreakerTileProvider(
      _CachingTileProvider(
        client: _tileHttp,
        headers: headers,
        persist: _ready,
        validDuration: _validDuration,
      ),
    );
  }

  // --- Circuit breaker -------------------------------------------------------
  // When a tile host goes unreachable, flutter_map re-request the missing
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

/// A [TileProvider] that serves each tile from the on-disk [_DiskTileStore]
/// when a fresh copy exists, else fetches it over the shared connection-capped
/// client and writes it back (cache-first). Falls back to network-only when
/// [persist] is false (disk store failed to init).
class _CachingTileProvider extends TileProvider {
  _CachingTileProvider({
    required http.Client client,
    required this.persist,
    required this.validDuration,
    Map<String, String>? headers,
  })  : _client = client,
        _headers = headers;

  final http.Client _client;
  final Map<String, String>? _headers;
  final bool persist;
  final Duration validDuration;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _DiskTileImage(
      url: getTileUrl(coordinates, options),
      headers: _headers,
      client: _client,
      persist: persist,
      validDuration: validDuration,
    );
  }
}

/// [ImageProvider] that resolves one raster tile: fresh disk hit → bytes from
/// disk; otherwise download → decode → (optionally) persist. Keyed purely by
/// URL so flutter's image cache dedupes identical tiles.
@immutable
class _DiskTileImage extends ImageProvider<_DiskTileImage> {
  const _DiskTileImage({
    required this.url,
    required this.headers,
    required this.client,
    required this.persist,
    required this.validDuration,
  });

  final String url;
  final Map<String, String>? headers;
  final http.Client client;
  final bool persist;
  final Duration validDuration;

  @override
  Future<_DiskTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DiskTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
      _DiskTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadBytes(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _loadBytes(ImageDecoderCallback decode) async {
    final bytes = await _fetch();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<Uint8List> _fetch() async {
    // 1) fresh disk hit
    if (persist) {
      final cached = _DiskTileStore.readFresh(url, validDuration);
      if (cached != null) return cached;
    }
    // 2) network
    try {
      final resp = await client.get(Uri.parse(url), headers: headers);
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        if (persist) _DiskTileStore.write(url, resp.bodyBytes);
        return resp.bodyBytes;
      }
      // 3) serve a stale copy rather than fail, if we have one
      if (persist) {
        final stale = _DiskTileStore.readAny(url);
        if (stale != null) return stale;
      }
      throw NetworkImageLoadException(
          statusCode: resp.statusCode, uri: Uri.parse(url));
    } catch (_) {
      if (persist) {
        final stale = _DiskTileStore.readAny(url);
        if (stale != null) return stale;
      }
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _DiskTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Pure-Dart filesystem tile store with count-based LRU eviction. One file per
/// tile (name = SHA-1 of the URL); the file mtime is the LRU timestamp,
/// bumped on every cache hit. All I/O is synchronous — tiles are tiny (~30 KB)
/// and this runs off the platform channel, so a sync read/write is cheaper
/// than the async plumbing it would otherwise need. Eviction runs opportunis-
/// tically every [_trimEvery] writes (and once at startup).
class _DiskTileStore {
  _DiskTileStore._();

  static Directory? _dir;
  static int _maxTiles = 1500;
  static int _writesSinceTrim = 0;
  static const _trimEvery = 64;

  static bool get _ready => _dir != null;

  static Future<void> init({required int maxTiles}) async {
    _maxTiles = maxTiles;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/map_tiles');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    unawaited(Future(_trim)); // startup sweep, off the init critical path
  }

  static File? _fileFor(String url) {
    final dir = _dir;
    if (dir == null) return null;
    final name = sha1.convert(utf8.encode(url)).toString();
    return File('${dir.path}/$name');
  }

  /// Bytes if a cached tile exists and is younger than [maxAge]; else null.
  /// Touches the file mtime on a hit so it survives LRU eviction longest.
  static Uint8List? readFresh(String url, Duration maxAge) {
    if (!_ready) return null;
    final f = _fileFor(url);
    if (f == null || !f.existsSync()) return null;
    try {
      if (DateTime.now().difference(f.lastModifiedSync()) > maxAge) return null;
      final bytes = f.readAsBytesSync();
      try {
        f.setLastModifiedSync(DateTime.now()); // LRU touch
      } catch (_) {/* best-effort */}
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Bytes if any cached tile exists (ignoring age) — for serving stale on a
  /// network failure. Does NOT touch mtime.
  static Uint8List? readAny(String url) {
    if (!_ready) return null;
    final f = _fileFor(url);
    if (f == null || !f.existsSync()) return null;
    try {
      return f.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  static void write(String url, Uint8List bytes) {
    if (!_ready) return;
    final f = _fileFor(url);
    if (f == null) return;
    try {
      f.writeAsBytesSync(bytes);
    } catch (_) {
      return;
    }
    if (++_writesSinceTrim >= _trimEvery) {
      _writesSinceTrim = 0;
      unawaited(Future(_trim));
    }
  }

  /// Delete the oldest files (by mtime) until at most [_maxTiles] remain.
  static void _trim() {
    final dir = _dir;
    if (dir == null) return;
    try {
      final files = dir.listSync().whereType<File>().toList();
      if (files.length <= _maxTiles) return;
      files.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in files.take(files.length - _maxTiles)) {
        try {
          f.deleteSync();
        } catch (_) {/* raced with another delete; ignore */}
      }
    } catch (_) {/* best-effort housekeeping */}
  }
}

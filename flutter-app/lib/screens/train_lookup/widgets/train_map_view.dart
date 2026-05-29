import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/tile_cache.dart';
import '../../../models/trip.dart';
import '../../../providers/service_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/lazy_mount.dart';

/// Inline route map with the live (time-interpolated) train position.
/// Tap to open a larger, fully interactive fullscreen map.
class TrainMapView extends ConsumerStatefulWidget {
  final Trip trip;

  const TrainMapView({super.key, required this.trip});

  @override
  ConsumerState<TrainMapView> createState() => _TrainMapViewState();
}

class _TrainMapViewState extends ConsumerState<TrainMapView> {
  Timer? _ticker;

  /// Trip with the exact track geometry attached once it has been resolved.
  /// Starts as the bahn.de trip (straight lines) and snaps onto the rails when
  /// [HafasService.fetchRoutePolyline] returns.
  late Trip _trip;

  bool _polylineStarted = false;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    // Advance the live position marker every 15s without re-fetching.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Kick off the (network) route-geometry fetch only once the map is actually
  /// shown — off-screen legs must not hit the network.
  void _ensurePolyline() {
    if (_polylineStarted) return;
    _polylineStarted = true;
    _loadPolyline();
  }

  Future<void> _loadPolyline() async {
    if (_trip.polyline != null && _trip.polyline!.isNotEmpty) return;
    try {
      final poly =
          await ref.read(hafasServiceProvider).fetchRoutePolyline(_trip);
      if (poly != null && poly.isNotEmpty && mounted) {
        setState(() => _trip = _trip.copyWith(polyline: poly));
      }
    } catch (_) {/* keep straight-line fallback */}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasStops = _trip.stopovers.any((s) => s.stop.hasLocation);
    if (!hasStops) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 240,
        // Only mount the actual map (and fetch its tiles + geometry) once it
        // scrolls into view — off-screen legs stay a cheap placeholder.
        child: LazyMount(
          placeholder: _placeholder(context),
          builder: (context) {
            _ensurePolyline();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _TrainMapFullScreen(trip: _trip),
                ),
              ),
              child: Stack(
                children: [
                  // The non-interactive map would otherwise swallow pointer
                  // events; ignore them so a tap anywhere opens fullscreen.
                  IgnorePointer(
                      child: TrainMap(trip: _trip, interactive: false)),
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: CircleBorder(),
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.fullscreen,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined,
              size: 32, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 6),
          Text('Karte', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TrainMapFullScreen extends StatelessWidget {
  final Trip trip;
  const _TrainMapFullScreen({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trip.line.displayName)),
      body: TrainMap(trip: trip, interactive: true),
    );
  }
}

/// The actual flutter_map for a trip: route polyline, stops, and the live
/// train position. Reused inline (non-interactive) and fullscreen.
class TrainMap extends StatelessWidget {
  final Trip trip;
  final bool interactive;

  const TrainMap({super.key, required this.trip, this.interactive = true});

  @override
  Widget build(BuildContext context) {
    final stops = trip.stopovers.where((s) => s.stop.hasLocation).toList();
    if (stops.isEmpty) return const SizedBox.shrink();

    final points = stops
        .map((s) => LatLng(s.stop.latitude!, s.stop.longitude!))
        .toList();
    final routePoints = (trip.polyline != null && trip.polyline!.isNotEmpty)
        ? trip.polyline!.map((p) => LatLng(p['lat']!, p['lng']!)).toList()
        : points;
    final currentPos = trip.estimatedPosition;

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(40),
        ),
        interactionOptions: InteractionOptions(
          flags: interactive
              ? (InteractiveFlag.all & ~InteractiveFlag.rotate)
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: RetinaMode.isHighDensity(context),
          userAgentPackageName: 'de.chuk.besserebahn',
          tileProvider: TileCache.provider(),
          maxZoom: 20,
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePoints,
              color: AppColors.dbRed.withAlpha(200),
              strokeWidth: 4,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final stop in stops)
              Marker(
                point: LatLng(stop.stop.latitude!, stop.stop.longitude!),
                width: 12,
                height: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: stop.isPast ? Colors.grey : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.dbRed, width: 2),
                  ),
                ),
              ),
            if (currentPos != null)
              Marker(
                point: LatLng(currentPos.latitude, currentPos.longitude),
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.dbRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.dbRed.withAlpha(120),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.train, size: 14, color: Colors.white),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

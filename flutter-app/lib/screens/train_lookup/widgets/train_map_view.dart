import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/tile_cache.dart';
import '../../../core/train_dimensions.dart';
import '../../../core/train_geometry.dart';
import '../../../models/coach_sequence.dart';
import '../../../models/trip.dart';
import '../../../providers/service_providers.dart';
import '../../../theme/app_colors.dart';

/// Open the full-screen, fully interactive route map for [trip]. Pass the
/// [coachSequence] when known so the live train is drawn to its real length.
void openTrainMap(BuildContext context, Trip trip,
    {CoachSequence? coachSequence}) {
  Navigator.of(context).push(
    MaterialPageRoute(
        builder: (_) => TrainMapView(trip: trip, coachSequence: coachSequence)),
  );
}

/// Full-screen route map with the live train (a to-scale top-down body that
/// slides continuously along the exact track geometry, fetched on open).
class TrainMapView extends ConsumerStatefulWidget {
  final Trip trip;
  final CoachSequence? coachSequence;

  const TrainMapView({super.key, required this.trip, this.coachSequence});

  @override
  ConsumerState<TrainMapView> createState() => _TrainMapViewState();
}

class _TrainMapViewState extends ConsumerState<TrainMapView> {
  /// Trip with the exact track geometry attached once it has been resolved.
  /// Starts as the bahn.de trip (straight lines) and snaps onto the rails when
  /// [HafasService.fetchRoutePolyline] returns.
  late Trip _trip;

  bool _polylineStarted = false;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _ensurePolyline();
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
  Widget build(BuildContext context) {
    final hasStops = _trip.stopovers.any((s) => s.stop.hasLocation);
    return Scaffold(
      appBar: AppBar(title: Text(_trip.line.displayName)),
      body: hasStops
          ? TrainMap(
              trip: _trip,
              coachSequence: widget.coachSequence,
              interactive: true)
          : const Center(child: Text('Keine Streckendaten verfügbar.')),
    );
  }
}

/// The actual flutter_map for a trip: route polyline, stops, the live train,
/// and a metric scale bar.
class TrainMap extends StatelessWidget {
  final Trip trip;
  final CoachSequence? coachSequence;
  final bool interactive;

  const TrainMap({
    super.key,
    required this.trip,
    this.coachSequence,
    this.interactive = true,
  });

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
        TileCache.outdoorLayer(),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution('© OpenStreetMap'),
            TextSourceAttribution('© OpenMapTiles'),
          ],
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
          ],
        ),
        // The live train: a top-down body that hugs the rails and slides
        // continuously (its own per-frame ticker) instead of jumping.
        _LiveTrain(trip: trip, route: routePoints, coachSequence: coachSequence),
        const Scalebar(
          alignment: Alignment.bottomRight,
          padding: EdgeInsets.only(right: 12, bottom: 20),
        ),
      ],
    );
  }
}

/// The moving train, drawn as a to-scale top-down body on the route polyline.
///
/// It carries its own frame ticker and recomputes the head position from the
/// wall clock every frame, so the train glides smoothly along the track and
/// rounds curves — rather than hopping every few seconds. When zoomed out far
/// enough that the real body would be sub-pixel, it's floored to a small
/// on-screen size so it stays a visible train; once the real length exceeds
/// that floor (zoomed in) it is exactly to scale.
class _LiveTrain extends StatefulWidget {
  final Trip trip;
  final List<LatLng> route;
  final CoachSequence? coachSequence;

  const _LiveTrain(
      {required this.trip, required this.route, this.coachSequence});

  @override
  State<_LiveTrain> createState() => _LiveTrainState();
}

class _LiveTrainState extends State<_LiveTrain>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() {}))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Where the train's head is right now: the live-interpolated position while
  /// running, else the platform it's dwelling at, else nothing.
  LatLng? _head() {
    final pos = widget.trip.estimatedPosition;
    if (pos != null) return LatLng(pos.latitude, pos.longitude);
    // Dwelling at a stop (arrived, not yet departed) → sit on that platform.
    final now = DateTime.now();
    Stopover? at;
    for (final s in widget.trip.stopovers) {
      final arr = s.arrival ?? s.departure;
      if (arr != null && !arr.isAfter(now)) {
        final dep = s.departure ?? s.arrival;
        if (dep == null || dep.isAfter(now)) at = s;
      }
    }
    if (at != null && at.stop.hasLocation) {
      return LatLng(at.stop.latitude!, at.stop.longitude!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final head = _head();
    if (head == null || widget.route.length < 2) {
      return const SizedBox.shrink();
    }

    // Real-world size: exact from the Wagenreihung if we have it, else a
    // realistic figure for the product category.
    final dims = TrainDimensions.forProduct(widget.trip.line.product);
    var lenM = dims.totalLengthM;
    var halfWM = dims.halfWidthM;
    var noseM = dims.noseLenM;
    var bothNose = dims.noseBothEnds;
    final cs = widget.coachSequence;
    if (cs != null) {
      final cc = cs.allCoaches
          .where((c) => c.platformPosition != null)
          .map((c) => c.platformPosition!)
          .toList();
      if (cc.isNotEmpty) {
        final s = cc.map((p) => p.start).reduce(math.min);
        final e = cc.map((p) => p.end).reduce(math.max);
        if (e - s > 10) lenM = e - s;
      }
      final hs = isHighSpeedCoach(cs);
      bothNose = hs;
      noseM = hs ? 6 : 0;
      halfWM = (hs ? 2.95 : 2.84) / 2;
    }

    // Floor the on-screen size so the train never shrinks to an invisible
    // speck; above the floor it's exactly to scale.
    final mpp = _metersPerPixel(MapCamera.of(context), head);
    final effLen = math.max(lenM, 30 * mpp);
    final effHalfW = math.max(halfWM, 4 * mpp);
    final effNose = noseM > 0 ? math.min(effLen * 0.42, math.max(noseM, effLen * 0.28)) : 0.0;

    // Carve the body out of the route polyline: tail → head, so it bends with
    // every curve between. The head is the front (direction of travel).
    final headArc = TrainGeometry.locate(widget.route, head);
    final spine = TrainGeometry.slice(
        widget.route, headArc - effLen, headArc);
    if (spine.length < 2) return const SizedBox.shrink();

    final outline = TrainGeometry.body(
      spine,
      halfWidthM: effHalfW,
      noseStart: bothNose, // tail snout only on a symmetric EMU (ICE)
      noseEnd: true, // the front always tapers
      noseLenM: effNose,
    );
    if (outline.length < 3) return const SizedBox.shrink();

    return PolygonLayer(
      polygons: [
        Polygon(
          points: outline,
          color: AppColors.dbRed,
          borderColor: Colors.white,
          borderStrokeWidth: 1.5,
        ),
      ],
    );
  }

  /// Ground metres per screen pixel near [at] — for flooring the on-screen size.
  double _metersPerPixel(MapCamera cam, LatLng at) {
    final east = LatLng(at.latitude, at.longitude + 0.002);
    final pa = cam.latLngToScreenOffset(at);
    final pb = cam.latLngToScreenOffset(east);
    final px = (pb - pa).distance;
    if (px <= 0) return 1;
    return const Distance()(at, east) / px;
  }
}

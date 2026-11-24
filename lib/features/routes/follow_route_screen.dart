import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../services/routing/location_source.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'my_location.dart';
import 'route_parts.dart';

/// Unterwegs der Route folgen: eigener Standort live auf der Karte, Restdistanz und Fortschritt, Warnung mit Vibration,
/// sobald man die Route verlässt. Nur bei geöffneter App (der Bildschirm bleibt an) – keine Ortung im Hintergrund.
class FollowRouteScreen extends ConsumerStatefulWidget {
  const FollowRouteScreen({super.key, required this.route});

  final PlannedRoute route;

  @override
  ConsumerState<FollowRouteScreen> createState() => _FollowRouteScreenState();
}

class _FollowRouteScreenState extends ConsumerState<FollowRouteScreen> {
  final _map = MapController();
  late final RouteFollower _follower = RouteFollower(
    widget.route.points,
    offRouteDistance: widget.route.discipline.isBike ? 60 : 50,
  );
  StreamSubscription<GeoPoint>? _positions;
  final _watch = Stopwatch();
  Timer? _ticker;
  GeoPoint? _position;
  FollowState? _state;
  bool _followCamera = true;
  String? _problem;

  /// Gemerkt, weil `ref` im `dispose` nicht mehr benutzt werden darf.
  late final Future<void> Function(bool on) _screenAwake = ref.read(screenAwakeProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_screenAwake(true));
    _start();
  }

  void _start() {
    _positions = ref
        .read(locationSourceProvider)
        .watch()
        .listen(
          _onPosition,
          onError: (Object error) {
            if (mounted) setState(() => _problem = error is LocationProblem ? error.message : '$error');
          },
        );
    _watch.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onPosition(GeoPoint position) {
    final previous = _state;
    final state = _follower.update(position);
    if (!mounted) return;
    // Spürbar warnen, wenn man die Route verlässt bzw. ankommt.
    if (state.isOffRoute && !(previous?.isOffRoute ?? false)) unawaited(HapticFeedback.heavyImpact());
    if (state.arrived && !(previous?.arrived ?? false)) unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _position = position;
      _state = state;
      _problem = null;
    });
    if (_followCamera) {
      try {
        _map.move(latLng(position), _map.camera.zoom < 15 ? 16 : _map.camera.zoom);
      } on Object {
        // Karte noch nicht bereit.
      }
    }
  }

  @override
  void dispose() {
    unawaited(_positions?.cancel());
    _ticker?.cancel();
    unawaited(_screenAwake(false));
    super.dispose();
  }

  static String _clock(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final state = _state;
    final color = variantColor(route.variant);
    final padding = MediaQuery.paddingOf(context);
    final offRoute = state?.isOffRoute ?? false;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PlannerMap(
              controller: _map,
              start: route.points.first,
              destination: route.isLoop ? null : route.points.last,
              routes: [route],
              selected: route,
              height: null,
              rounded: false,
              initialPoints: Geo.thin(route.points, 200),
              myLocation: _position,
              routingSource: route.engine.isEmpty ? null : route.engine,
            ),
          ),
          Positioned(
            top: padding.top + 10,
            left: 12,
            right: 12,
            child: Row(
              spacing: 10,
              children: [
                LiquidSurface(
                  radius: LiquidRadii.pill,
                  strong: true,
                  child: IconButton(
                    tooltip: 'Beenden',
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: LiquidSurface(
                    radius: LiquidRadii.pill,
                    strong: true,
                    tint: offRoute ? AppColors.of(context).alert : null,
                    shadow: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      child: Text(
                        _problem ??
                            (state == null
                                ? 'Standort wird gesucht …'
                                : state.arrived
                                ? 'Geschafft – Ziel erreicht!'
                                : offRoute
                                ? 'Abseits der Route (${state.offRouteMeters.round()} m)'
                                : 'Auf der Route'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: offRoute ? AppColors.of(context).alert : null,
                        ),
                      ),
                    ),
                  ),
                ),
                LiquidSurface(
                  radius: LiquidRadii.pill,
                  strong: true,
                  child: IconButton(
                    tooltip: _followCamera ? 'Karte frei bewegen' : 'Karte mitführen',
                    isSelected: _followCamera,
                    icon: const Icon(Icons.navigation_outlined),
                    selectedIcon: const Icon(Icons.navigation),
                    onPressed: () => setState(() => _followCamera = !_followCamera),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: LiquidSpacing.page,
            right: LiquidSpacing.page,
            bottom: LiquidSpacing.page + padding.bottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                LocateMeButton(map: _map, onLocated: (point) => setState(() => _position = point)),
                LiquidCard(
                  strong: true,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      Semantics(
                        liveRegion: true,
                        label:
                            'Noch ${RouteFormat.distance(state?.remainingMeters ?? _follower.totalMeters)}, '
                            '${((state?.fraction ?? 0) * 100).round()} Prozent geschafft',
                        excludeSemantics: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: LiquidMetric(
                                value: RouteFormat.distance(state?.remainingMeters ?? _follower.totalMeters),
                                label: 'noch',
                              ),
                            ),
                            Expanded(
                              child: LiquidMetric(
                                value: RouteFormat.distance(state?.progressMeters ?? 0),
                                label: 'geschafft',
                              ),
                            ),
                            Expanded(
                              child: LiquidMetric(value: _clock(_watch.elapsed), label: 'unterwegs'),
                            ),
                          ],
                        ),
                      ),
                      LiquidProgressBar(
                        value: state?.fraction ?? 0,
                        color: offRoute ? AppColors.of(context).alert : color,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

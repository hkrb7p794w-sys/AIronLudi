import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/routing/garmin_course_service.dart';
import '../../services/routing/routing_providers.dart';
import '../../services/routing/worker_maps.dart';
import '../../services/share/export_folders.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'my_location.dart';

part 'route_map_layers.dart';

LatLng latLng(GeoPoint point) => LatLng(point.latitude, point.longitude);

GeoPoint geoPoint(LatLng point) => GeoPoint(point.latitude, point.longitude);

/// Farbe je Variante (Vorschläge unterscheidbar auf der Karte).
Color variantColor(RouteVariant variant) => switch (variant) {
  RouteVariant.balanced => const Color(0xFF0A84FF),
  RouteVariant.hilly => const Color(0xFFFF6B35),
  RouteVariant.green => const Color(0xFF30C26B),
};

/// Kachel-Zwischenspeicher der Karten; in Widget-Tests aus (dort gibt es keinen Cache-Ordner).
abstract final class OsmTiles {
  @visibleForTesting
  static bool cacheDisabled = false;
}

/// Kartenkacheln: über den Worker (MapTiler, im Dunkelmodus dunkel), sonst OSM. Gibt es keinen Worker mit Kacheln,
/// bleibt alles wie bisher.
class BaseTiles extends ConsumerWidget {
  const BaseTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worker = ref.watch(workerTilesProvider).value;
    final cacheOff = OsmTiles.cacheDisabled ? DisabledMapCachingProvider() : null;
    if (worker != null) {
      return TileLayer(
        urlTemplate: worker.urlTemplate(dark: Theme.of(context).brightness == Brightness.dark),
        userAgentPackageName: 'io.github.hkrb7p794w.gym',
        tileProvider: NetworkTileProvider(headers: worker.headers, cachingProvider: cacheOff),
      );
    }
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'io.github.hkrb7p794w.gym',
      tileProvider: cacheOff == null ? null : NetworkTileProvider(cachingProvider: cacheOff),
    );
  }
}

/// Quellenangabe unten rechts als kleine Glas-Pille (bricht nicht über den Rand wie `SimpleAttributionWidget`).
Widget osmAttribution({String? routingSource}) => _Attribution(routingSource: routingSource);

class _Attribution extends ConsumerWidget {
  const _Attribution({this.routingSource});

  final String? routingSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(workerTilesProvider).value == null
        ? '© OpenStreetMap-Mitwirkende'
        : WorkerTiles.attribution;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: LiquidSurface(
          radius: LiquidRadii.pill,
          strong: true,
          shadow: false,
          blur: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              routingSource == null ? tiles : '$tiles · $routingSource',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interaktive Karte des Planers: Start (grün), Ziel (rot), Vorschläge als Linien mit Richtungspfeilen auf der
/// gewählten Route. Antippen und langes Drücken melden den Punkt (was daraus wird, entscheidet der Planer).
class PlannerMap extends StatelessWidget {
  const PlannerMap({
    super.key,
    required this.controller,
    required this.start,
    this.destination,
    this.routes = const [],
    this.selected,
    this.onTap,
    this.onLongPress,
    this.height = 320,
    this.rounded = true,
    this.initialPoints = const [],
    this.myLocation,
    this.routingSource,
  });

  final MapController controller;
  final GeoPoint? start;
  final GeoPoint? destination;
  final List<PlannedRoute> routes;
  final PlannedRoute? selected;
  final void Function(GeoPoint point)? onTap;
  final void Function(GeoPoint point)? onLongPress;

  /// Höhe; `null` füllt den verfügbaren Platz (Vollbild).
  final double? height;
  final bool rounded;

  /// Beim Aufbau auf diese Punkte ausrichten (z. B. alle Vorschläge im Vollbild).
  final List<GeoPoint> initialPoints;

  /// Eigener Standort (blauer Punkt), nach „Mein Standort“.
  final GeoPoint? myLocation;
  final String? routingSource;

  /// Mitte Deutschlands, solange kein Start bekannt ist.
  static const fallbackCenter = LatLng(51.1657, 10.4515);

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final route in routes)
        if (route.id != selected?.id) route,
    ];
    final fit = initialPoints.length > 1
        ? CameraFit.coordinates(
            coordinates: [for (final point in initialPoints) latLng(point)],
            padding: const EdgeInsets.fromLTRB(36, 110, 36, 150),
            maxZoom: 16,
          )
        : null;
    return SizedBox(
      height: height ?? double.infinity,
      child: ClipRRect(
        borderRadius: rounded ? LiquidRadii.cardAll : BorderRadius.zero,
        child: Semantics(
          label: 'Karte des Routenplaners',
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: start == null ? fallbackCenter : latLng(start!),
              initialZoom: start == null ? 5.5 : 13,
              initialCameraFit: fit,
              onTap: onTap == null ? null : (_, point) => onTap!(geoPoint(point)),
              onLongPress: onLongPress == null ? null : (_, point) => onLongPress!(geoPoint(point)),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              const BaseTiles(),
              PolylineLayer(
                polylines: [
                  for (final route in others)
                    Polyline(
                      points: [for (final point in route.points) latLng(point)],
                      color: variantColor(route.variant).withValues(alpha: 0.45),
                      strokeWidth: 3,
                    ),
                  if (selected case final route?)
                    Polyline(
                      points: [for (final point in route.points) latLng(point)],
                      color: variantColor(route.variant),
                      strokeWidth: 5,
                      borderColor: Colors.white.withValues(alpha: 0.85),
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              if (selected case final route?) DirectionArrows(points: route.points, color: variantColor(route.variant)),
              if (selected case final route?)
                KilometerMarkers(points: route.points, color: variantColor(route.variant)),
              if (selected case final route?) RoutePoiLayer(route: route),
              MyLocationLayer(point: myLocation),
              MarkerLayer(
                markers: [
                  if (destination case final destination?)
                    Marker(
                      point: latLng(destination),
                      child: _Pin(color: AppColors.of(context).alert, icon: Icons.sports_score),
                    ),
                  if (start case final start?)
                    Marker(
                      point: latLng(start),
                      child: _Pin(color: AppColors.of(context).good, icon: Icons.flag),
                    ),
                ],
              ),
              osmAttribution(routingSource: routingSource),
            ],
          ),
        ),
      ),
    );
  }

  /// Kamera auf die Strecke(n) bzw. Punkte ausrichten.
  static void fit(MapController controller, List<GeoPoint> points) {
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        controller.move(latLng(points.single), 14);
        return;
      }
      controller.fitCamera(
        CameraFit.coordinates(
          coordinates: [for (final point in points) latLng(point)],
          padding: const EdgeInsets.all(36),
          maxZoom: 16,
        ),
      );
    } on Object {
      // Karte noch nicht aufgebaut: beim nächsten Mal.
    }
  }
}

/// Karte im Vollbild (Antippen der kleinen Karte): Routen mit Pfeilen, Auswahl der Vorschläge unten, langes Drücken
/// setzt Start bzw. Ziel über [onLongPress] (liefert den neuen Stand, Vorschläge verfallen dann).
class FullscreenRouteMap extends StatefulWidget {
  const FullscreenRouteMap({
    super.key,
    required this.start,
    this.destination,
    this.routes = const [],
    this.selected = 0,
    this.onSelect,
    this.onLongPress,
    this.title,
  });

  final GeoPoint? start;
  final GeoPoint? destination;
  final List<PlannedRoute> routes;
  final int selected;
  final ValueChanged<int>? onSelect;
  final ({GeoPoint? start, GeoPoint? destination}) Function(GeoPoint point)? onLongPress;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required GeoPoint? start,
    GeoPoint? destination,
    List<PlannedRoute> routes = const [],
    int selected = 0,
    ValueChanged<int>? onSelect,
    ({GeoPoint? start, GeoPoint? destination}) Function(GeoPoint point)? onLongPress,
    String? title,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FullscreenRouteMap(
        start: start,
        destination: destination,
        routes: routes,
        selected: selected,
        onSelect: onSelect,
        onLongPress: onLongPress,
        title: title,
      ),
    ),
  );

  @override
  State<FullscreenRouteMap> createState() => _FullscreenRouteMapState();
}

class _FullscreenRouteMapState extends State<FullscreenRouteMap> {
  final _map = MapController();
  late GeoPoint? _start = widget.start;
  late GeoPoint? _destination = widget.destination;
  late List<PlannedRoute> _routes = widget.routes;
  late int _selected = widget.selected.clamp(0, widget.routes.isEmpty ? 0 : widget.routes.length - 1);
  GeoPoint? _myLocation;

  PlannedRoute? get _current => _routes.isEmpty ? null : _routes[_selected];

  void _longPress(GeoPoint point) {
    final callback = widget.onLongPress;
    if (callback == null) return;
    unawaited(HapticFeedback.mediumImpact());
    final next = callback(point);
    setState(() {
      _start = next.start;
      _destination = next.destination;
      _routes = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PlannerMap(
              controller: _map,
              start: _start,
              destination: _destination,
              routes: _routes,
              selected: current,
              onLongPress: widget.onLongPress == null ? null : _longPress,
              height: null,
              rounded: false,
              initialPoints: [
                for (final route in _routes) ...Geo.thin(route.points, 200),
                if (_routes.isEmpty) ...[?_start, ?_destination],
              ],
              routingSource: current?.engine,
              myLocation: _myLocation,
            ),
          ),
          Positioned(
            right: 12,
            bottom: padding.bottom + (_routes.length > 1 ? 84 : 24),
            child: LocateMeButton(map: _map, onLocated: (point) => setState(() => _myLocation = point)),
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
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close_fullscreen),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (widget.onLongPress != null)
                  Expanded(
                    child: LiquidSurface(
                      radius: LiquidRadii.pill,
                      strong: true,
                      shadow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Text(
                          _routes.isEmpty
                              ? 'Lange drücken setzt den Punkt.'
                              : 'Lange drücken verschiebt den Start und plant neu.',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: AppText.footnote(context).copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  )
                else if (widget.title case final title?)
                  Expanded(
                    child: LiquidSurface(
                      radius: LiquidRadii.pill,
                      strong: true,
                      shadow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_routes.length > 1)
            Positioned(
              left: 12,
              right: 12,
              bottom: padding.bottom + 16,
              child: LiquidSurface(
                radius: LiquidRadii.pill,
                strong: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    spacing: 6,
                    children: [
                      for (final (index, route) in _routes.indexed)
                        ChoiceChip(
                          avatar: CircleAvatar(backgroundColor: variantColor(route.variant), radius: 6),
                          label: Text('${route.variant.label} · ${RouteFormat.distance(route.stats.distanceMeters)}'),
                          selected: index == _selected,
                          shape: const StadiumBorder(),
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() => _selected = index);
                            widget.onSelect?.call(index);
                            PlannerMap.fit(_map, Geo.thin(route.points, 200));
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

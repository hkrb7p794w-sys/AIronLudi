import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../ui/liquid.dart';

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

/// OSM-Kacheln mit Quellenangabe (wie `RouteMap`).
List<Widget> osmBaseLayers() => [
  TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'io.github.hkrb7p794w.gym',
    tileProvider: OsmTiles.cacheDisabled ? NetworkTileProvider(cachingProvider: DisabledMapCachingProvider()) : null,
  ),
];

/// Quellenangabe unten rechts als kleine Glas-Pille (bricht nicht über den Rand wie `SimpleAttributionWidget`).
Widget osmAttribution({String? routingSource}) => _Attribution(routingSource: routingSource);

class _Attribution extends StatelessWidget {
  const _Attribution({this.routingSource});

  final String? routingSource;

  @override
  Widget build(BuildContext context) => Align(
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
            routingSource == null ? '© OpenStreetMap-Mitwirkende' : '© OpenStreetMap-Mitwirkende · $routingSource',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    ),
  );
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
              ...osmBaseLayers(),
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
              MarkerLayer(
                markers: [
                  if (destination case final destination?)
                    Marker(
                      point: latLng(destination),
                      child: const _Pin(color: Colors.red, icon: Icons.sports_score),
                    ),
                  if (start case final start?)
                    Marker(
                      point: latLng(start),
                      child: const _Pin(color: Colors.green, icon: Icons.flag),
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
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

/// Richtungspfeile entlang der Strecke, Abstand je nach Zoom (etwa alle 90 Bildpunkte, höchstens 80 Pfeile).
class DirectionArrows extends StatelessWidget {
  const DirectionArrows({super.key, required this.points, required this.color, this.pixelSpacing = 90});

  final List<GeoPoint> points;
  final Color color;
  final double pixelSpacing;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final spacing = pixelSpacing * RouteArrows.metersPerPixel(camera.center.latitude, camera.zoom);
    final arrows = RouteArrows.along(points, spacing);
    return MarkerLayer(
      markers: [
        for (final arrow in arrows)
          Marker(
            point: latLng(arrow.point),
            width: 18,
            height: 18,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: arrow.bearing * math.pi / 180,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: const Icon(Icons.navigation, size: 10, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Umschalter „Automatisch / Frei zeichnen“ als Liquid-Pille.
class PlannerModeSwitch extends StatelessWidget {
  const PlannerModeSwitch({super.key, required this.automatic, required this.onChanged});

  final bool automatic;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(
      shape: const StadiumBorder(),
      backgroundColor: LiquidTheme.of(context).fillFor(context),
    ),
    segments: const [
      ButtonSegment(value: true, icon: Icon(Icons.auto_awesome), label: Text('Automatisch')),
      ButtonSegment(value: false, icon: Icon(Icons.draw_outlined), label: Text('Frei planen')),
    ],
    selected: {automatic},
    onSelectionChanged: (selection) {
      if (selection.single != automatic) onChanged(selection.single);
    },
  );
}

/// Auswahl der Umgebung: Mix oder Wald/Wasser/Asphalt (Natur und Asphalt schließen sich aus).
class PreferenceChips extends StatelessWidget {
  const PreferenceChips({super.key, required this.selected, required this.onChanged});

  final Set<RoutePreference> selected;
  final ValueChanged<Set<RoutePreference>> onChanged;

  static IconData icon(RoutePreference preference) => switch (preference) {
    RoutePreference.nature => Icons.forest_outlined,
    RoutePreference.water => Icons.water_outlined,
    RoutePreference.paved => Icons.add_road,
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilterChip(
        avatar: const Icon(Icons.balance, size: 18),
        label: const Text(RoutePreference.mixLabel),
        selected: selected.isEmpty,
        showCheckmark: false,
        shape: const StadiumBorder(),
        onSelected: (_) => onChanged(const {}),
      ),
      for (final preference in RoutePreference.values)
        FilterChip(
          avatar: Icon(icon(preference), size: 18),
          label: Text(preference.label),
          tooltip: preference.detail,
          selected: selected.contains(preference),
          showCheckmark: false,
          shape: const StadiumBorder(),
          onSelected: (_) => onChanged(RoutePreference.toggle(selected, preference)),
        ),
    ],
  );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 16, color: Colors.white),
    ),
  );
}

/// Kennzahlen einer Route: Distanz, Anstieg, Abstieg, geschätzte Dauer.
class RouteStatsRow extends StatelessWidget {
  const RouteStatsRow({super.key, required this.route});

  final PlannedRoute route;

  @override
  Widget build(BuildContext context) {
    final stats = route.stats;
    final elevationKnown = stats.hasElevation;
    return Wrap(
      spacing: LiquidSpacing.xl,
      runSpacing: LiquidSpacing.m,
      children: [
        LiquidMetric(value: RouteFormat.distance(stats.distanceMeters), label: 'Distanz'),
        LiquidMetric(
          value: elevationKnown ? '↑ ${stats.ascentMeters.round()}' : '–',
          unit: elevationKnown ? 'hm' : null,
          label: 'Anstieg',
        ),
        LiquidMetric(
          value: elevationKnown ? '↓ ${stats.descentMeters.round()}' : '–',
          unit: elevationKnown ? 'hm' : null,
          label: 'Abstieg',
        ),
        LiquidMetric(value: RouteFormat.duration(route.duration), label: 'geschätzt'),
      ],
    );
  }
}

/// Kompaktes Höhenprofil (Fläche unter der Linie, weiche Kurve).
class ElevationProfileChart extends StatelessWidget {
  const ElevationProfileChart({super.key, required this.route, this.height = 130});

  final PlannedRoute route;
  final double height;

  @override
  Widget build(BuildContext context) {
    final samples = RouteStats.profile(route.points);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    if (samples.length < 2) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text('Kein Höhenprofil verfügbar', style: TextStyle(color: secondary, fontSize: 13)),
        ),
      );
    }
    final color = variantColor(route.variant);
    final low = samples.map((sample) => sample.elevation).reduce(math.min);
    final high = samples.map((sample) => sample.elevation).reduce(math.max);
    final padding = math.max(10.0, (high - low) * 0.15);
    final maxX = samples.last.kilometers;
    return Semantics(
      label:
          'Höhenprofil: von ${low.round()} bis ${high.round()} Meter, ${route.stats.ascentMeters.round()} Höhenmeter '
          'Anstieg',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX <= 0 ? 1 : maxX,
            minY: (low - padding).floorToDouble(),
            maxY: (high + padding).ceilToDouble(),
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: math.max(5, ((high - low + 2 * padding) / 3).roundToDouble()),
              getDrawingHorizontalLine: (_) => FlLine(color: LiquidTheme.of(context).track, strokeWidth: 1),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      '${spot.x.toStringAsFixed(1).replaceAll('.', ',')} km · ${spot.y.round()} m',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final sample in samples) FlSpot(sample.kilometers, sample.elevation)],
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: color,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
                  ),
                ),
              ),
            ],
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text('${value.round()}', style: TextStyle(fontSize: 10, color: secondary)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: math.max(0.5, (maxX / 4).ceilToDouble()),
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text('${value.round()} km', style: TextStyle(fontSize: 10, color: secondary)),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

/// Zeile „Einheit am …“, wenn die Route in eine Einheit übernommen wurde.
String? plannedLabel(PlannedRoute route) {
  final day = route.plannedDay;
  if (day == null) return null;
  final today = CalendarDay.today();
  final when = day == today
      ? 'heute'
      : day == today.adding(1)
      ? 'morgen'
      : 'am ${GermanFormat.date(day)}';
  return route.slotTitle == null ? 'Geplant für $when' : '${route.slotTitle} $when';
}

/// Exportiert die Route als GPX und/oder FIT-Kurs und öffnet das Teilen-Menü des Systems.
Future<void> shareRoute(BuildContext context, PlannedRoute route, {required bool fit}) async {
  final folder = Directory(p.join((await getTemporaryDirectory()).path, 'routen-export'));
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  folder.createSync(recursive: true);
  final XFile file;
  if (fit) {
    final path = p.join(folder.path, GpxExport.fileName(route, extension: 'fit'));
    File(path).writeAsBytesSync(FitCourseFile.bytes(route, created: DateTime.now()));
    file = XFile(path, mimeType: 'application/vnd.ant.fit');
  } else {
    final path = p.join(folder.path, GpxExport.fileName(route));
    File(path).writeAsStringSync(GpxExport.xml(route));
    file = XFile(path, mimeType: 'application/gpx+xml');
  }
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      subject: route.name,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

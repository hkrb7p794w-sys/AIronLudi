import 'dart:io';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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

/// Interaktive Karte des Planers: Start (grün), Ziel (rot), Vorschläge als Linien; Antippen setzt einen Pin.
class PlannerMap extends StatelessWidget {
  const PlannerMap({
    super.key,
    required this.controller,
    required this.start,
    this.destination,
    this.routes = const [],
    this.selected,
    this.onTap,
    this.height = 320,
    this.routingSource,
  });

  final MapController controller;
  final GeoPoint? start;
  final GeoPoint? destination;
  final List<PlannedRoute> routes;
  final PlannedRoute? selected;
  final void Function(GeoPoint point)? onTap;
  final double height;
  final String? routingSource;

  /// Mitte Deutschlands, solange kein Start bekannt ist.
  static const fallbackCenter = LatLng(51.1657, 10.4515);

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final route in routes)
        if (route.id != selected?.id) route,
    ];
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: LiquidRadii.cardAll,
        child: Semantics(
          label: 'Karte des Routenplaners. Antippen setzt einen Punkt.',
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: start == null ? fallbackCenter : latLng(start!),
              initialZoom: start == null ? 5.5 : 13,
              onTap: onTap == null ? null : (_, point) => onTap!(geoPoint(point)),
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

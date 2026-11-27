part of 'route_parts.dart';

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
                    border: Border.all(color: AppPalette.onColor, width: 1.5),
                    boxShadow: const [BoxShadow(color: AppPalette.mapShadow, blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: const Icon(Icons.navigation, size: 10, color: AppPalette.onColor),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kilometermarken („1“, „2“ …) entlang der Strecke; bei weitem Zoom alle 2, 5, 10 … km, damit sie lesbar bleiben.
class KilometerMarkers extends StatelessWidget {
  const KilometerMarkers({super.key, required this.points, required this.color, this.minPixelSpacing = 56});

  final List<GeoPoint> points;
  final Color color;
  final double minPixelSpacing;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final step = KilometerMarks.step(minPixelSpacing * RouteArrows.metersPerPixel(camera.center.latitude, camera.zoom));
    final marks = KilometerMarks.along(points, stepKm: step);
    return MarkerLayer(
      markers: [
        for (final mark in marks)
          Marker(
            point: latLng(mark.point),
            width: 30,
            height: 22,
            child: IgnorePointer(
              child: Semantics(
                label: 'Kilometer ${mark.kilometer}',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.onColor,
                    borderRadius: BorderRadius.circular(LiquidRadii.pill),
                    border: Border.all(color: color, width: 1.5),
                    boxShadow: const [BoxShadow(color: AppPalette.mapShadow, blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: Center(
                    child: Text(
                      '${mark.kilometer}',
                      style: AppText.caption(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Punkte unterwegs (Trinkbrunnen, Hundewiesen, Kotbeutel) als kleine Symbole auf der Karte.
class RoutePoiLayer extends ConsumerWidget {
  const RoutePoiLayer({super.key, required this.route});

  final PlannedRoute route;

  static IconData icon(PoiKind kind) => switch (kind) {
    PoiKind.water => Icons.water_drop,
    PoiKind.dogPark => Icons.pets,
    PoiKind.bags => Icons.shopping_bag_outlined,
  };

  static Color color(PoiKind kind) => switch (kind) {
    PoiKind.water => AppPalette.mapBlue,
    PoiKind.dogPark => AppPalette.mapGreen,
    PoiKind.bags => AppPalette.mapGrey,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pois = ref.watch(routePoisProvider(route)).value ?? const <RoutePoi>[];
    if (pois.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        for (final poi in pois)
          Marker(
            point: latLng(poi.point),
            width: 24,
            height: 24,
            child: Tooltip(
              message: poi.name == null ? poi.kind.label : '${poi.kind.label}: ${poi.name}',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppPalette.onColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: color(poi.kind), width: 2),
                  boxShadow: const [BoxShadow(color: AppPalette.mapShadow, blurRadius: 3, offset: Offset(0, 1))],
                ),
                child: Icon(icon(poi.kind), size: 13, color: color(poi.kind)),
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
  const PreferenceChips({super.key, required this.selected, required this.onChanged, this.discipline});

  final Set<RoutePreference> selected;
  final ValueChanged<Set<RoutePreference>> onChanged;

  /// Nur passende Wegarten anbieten (Hundewiese beim Spazieren).
  final RouteDiscipline? discipline;

  static IconData icon(RoutePreference preference) => switch (preference) {
    RoutePreference.nature => Icons.forest_outlined,
    RoutePreference.water => Icons.water_outlined,
    RoutePreference.paved => Icons.add_road,
    RoutePreference.dogPark => Icons.pets,
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
      for (final preference in RoutePreference.available(discipline ?? RouteDiscipline.run))
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
      border: Border.all(color: AppPalette.onColor, width: 2),
      boxShadow: const [BoxShadow(color: AppPalette.mapShadowStrong, blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 16, color: AppPalette.onColor),
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
          child: Text('Kein Höhenprofil verfügbar', style: AppText.footnote(context).copyWith(color: secondary)),
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
                      AppText.caption(context).copyWith(color: AppPalette.onColor, fontWeight: FontWeight.w600),
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
                    child: Text('${value.round()}', style: AppText.caption(context).copyWith(color: secondary)),
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
                    child: Text('${value.round()} km', style: AppText.caption(context).copyWith(color: secondary)),
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
  final folder = await ExportFolders.fresh(ExportFolders.routeExport);
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

/// „An Uhr senden“: Datei im passenden Format über das Teilen-Menü an die App der Uhr geben, mit kurzer Anleitung je
/// Hersteller. Garmin bekommt einen FIT-Kurs, alle anderen GPX.
Future<void> showSendToWatchSheet(BuildContext context, PlannedRoute route) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('An Uhr senden', style: Theme.of(sheet).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Wähle deine Uhr. Im Teilen-Menü dann die App des Herstellers wählen – sie überträgt die Strecke beim '
              'nächsten Synchronisieren.',
              style: LiquidText.label(sheet),
            ),
          ),
          WatchMapTile(route: route),
          _GarminDirectTile(route: route),
          for (final watch in WatchTarget.values)
            Builder(
              builder: (context) => ListTile(
                leading: Icon(watch.icon),
                title: Text(watch.label),
                subtitle: Text(watch.steps),
                isThreeLine: true,
                trailing: Text(watch.fit ? 'FIT' : 'GPX', style: LiquidText.label(context)),
                onTap: () async {
                  await shareRoute(context, route, fit: watch.fit);
                },
              ),
            ),
        ],
      ),
    ),
  ),
);

/// „Direkt an Garmin Connect“: legt den Kurs im Garmin-Konto an (inoffizieller Zugang) und speichert die Route. Klappt
/// das nicht, steht die Meldung mit dem Weg über die FIT-Datei darunter.
class _GarminDirectTile extends ConsumerStatefulWidget {
  const _GarminDirectTile({required this.route});

  final PlannedRoute route;

  @override
  ConsumerState<_GarminDirectTile> createState() => _GarminDirectTileState();
}

class _GarminDirectTileState extends ConsumerState<_GarminDirectTile> {
  bool _busy = false;
  GarminCourseResult? _result;

  Future<void> _send() async {
    setState(() => _busy = true);
    final result = await ref.read(garminCourseTargetProvider).send(widget.route);
    // Kurs-ID merken (ungespeicherte Vorschläge werden dabei gespeichert).
    if (result is GarminCourseSent) await ref.read(routeStoreProvider).save(widget.route);
    if (!mounted) return;
    unawaited(result is GarminCourseSent ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final scheme = Theme.of(context).colorScheme;
    final sent = widget.route.garminCourseID != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: _busy
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(Icons.cloud_upload_outlined, color: scheme.primary),
          title: Text(sent ? 'Erneut an Garmin Connect senden' : 'Direkt an Garmin Connect senden'),
          subtitle: const Text(
            'Legt den Kurs in deinem Garmin-Konto an – ohne Umweg über eine Datei. Nicht offiziell von Garmin '
            'unterstützt; klappt es nicht, nimm „Garmin“ unten.',
          ),
          isThreeLine: true,
          enabled: !_busy,
          onTap: () => unawaited(_send()),
        ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LiquidCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Icon(
                    result is GarminCourseSent ? Icons.check_circle : Icons.info_outline,
                    color: result is GarminCourseSent ? AppColors.of(context).good : scheme.error,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(result.message),
                        if (result case GarminCourseSent(:final courseID))
                          TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                            onPressed: () =>
                                unawaited(launchUrl(GarminCourse.link(courseID), mode: LaunchMode.externalApplication)),
                            child: const Text('In Garmin Connect öffnen'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(indent: 16, endIndent: 16),
      ],
    );
  }
}

/// Uhren und Radcomputer mit dem Weg dorthin.
enum WatchTarget {
  garmin(
    'Garmin',
    Icons.watch,
    true,
    'Teilen › Garmin Connect öffnet den Kurs. Dort „An Gerät senden“; auf der Uhr unter Navigation › Kurse.',
  ),
  apple(
    'Apple Watch',
    Icons.watch_outlined,
    false,
    'Teilen › App mit Routen-Import (z. B. WorkOutDoors, Footpath). Die Watch-App zeigt die Strecke beim Training.',
  ),
  coros(
    'Coros',
    Icons.watch_outlined,
    false,
    'Teilen › COROS-App › Route importieren, dann mit der Uhr synchronisieren.',
  ),
  suunto('Suunto', Icons.watch_outlined, false, 'Teilen › Suunto-App › Route importieren und „In der Uhr verwenden“.'),
  polar(
    'Polar',
    Icons.watch_outlined,
    false,
    'Datei in Polar Flow (Web oder App) unter Favoriten › Routen importieren.',
  ),
  wahoo(
    'Wahoo / Radcomputer',
    Icons.directions_bike,
    false,
    'Teilen › Wahoo-App (ELEMNT) › Route speichern, dann synchronisieren.',
  );

  const WatchTarget(this.label, this.icon, this.fit, this.steps);

  final String label;
  final IconData icon;
  final bool fit;
  final String steps;
}

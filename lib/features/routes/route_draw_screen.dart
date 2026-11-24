import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import '../endurance/endurance_controller.dart';
import 'address_field.dart';
import 'my_location.dart';
import 'route_detail_screen.dart';
import 'route_parts.dart';
import 'route_planner_screen.dart';

/// Werkzeug auf der Karte: Wegpunkte antippen oder mit dem Finger zeichnen.
enum DrawTool { points, freehand }

/// „Frei planen“: Wegpunkte antippen oder eine grobe Linie zeichnen; jeder Abschnitt wird auf echte OSM-Wege der
/// gewählten Sportart und Umgebung gelegt (Valhalla/BRouter). Unten eine schwebende Glasleiste mit Distanz,
/// Höhenmetern und Dauer, Rückgängig, Rundweg schließen und Zurücksetzen.
class RouteDrawScreen extends ConsumerStatefulWidget {
  const RouteDrawScreen({super.key, this.start, this.discipline = RouteDiscipline.run, this.preferences = const {}});

  final GeoPoint? start;
  final RouteDiscipline discipline;
  final Set<RoutePreference> preferences;

  @override
  ConsumerState<RouteDrawScreen> createState() => _RouteDrawScreenState();
}

class _RouteDrawScreenState extends ConsumerState<RouteDrawScreen> {
  final _map = MapController();
  final _route = DrawnRoute();
  late RouteDiscipline _discipline = widget.discipline;
  late Set<RoutePreference> _preferences = {...widget.preferences};
  DrawTool _tool = DrawTool.points;
  final List<GeoPoint> _stroke = [];
  bool _busy = false;
  String? _engine;
  GeoPoint? _myLocation;

  /// Gewählter Wegpunkt (0 = Start) zum Verschieben oder Löschen; [_moving]: der nächste Tipp verschiebt ihn.
  int? _selected;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    if (widget.start case final start?) _route.setStart(start);
  }

  int? get _thresholdPace => ref.read(enduranceControllerProvider).plan?.request.thresholds.runThresholdPace;

  // Abschnitte routen

  /// Strecke über [waypoints] auf Wegen, mit Höhen (wirft [NoRouteFound] bzw. [RoutingUnavailable]).
  Future<RoutedPath> _routePath(List<GeoPoint> waypoints) async {
    final backend = ref.read(routingBackendProvider);
    var path = await backend.route(
      waypoints,
      discipline: _discipline,
      variant: RouteVariant.balanced,
      preferences: _preferences,
    );
    if (!path.hasElevation) {
      try {
        final points = path.points;
        final indices = _sampleIndices(points.length, ValhallaFormat.maxHeightPoints);
        final heights = await backend.elevations([for (final index in indices) points[index]]);
        path = RoutedPath(
          points: ElevationFill.interpolate(points, indices, heights),
          distanceMeters: path.distanceMeters,
          engine: path.engine,
        );
      } on RoutingUnavailable {
        // Ohne Höhen weiter: Distanz und Dauer stimmen trotzdem.
      }
    }
    return path;
  }

  /// Neuen Abschnitt bis zum letzten der [waypoints] anhängen (Zwischenpunkte eines Strichs bleiben gespeichert).
  Future<void> _routeTo(List<GeoPoint> waypoints) async {
    if (waypoints.length < 2 || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await _routePath(waypoints);
      if (!mounted) return;
      // Anschluss exakt am bisherigen Ende, damit die Linie nicht springt.
      final segment = [waypoints.first, ...path.points.skip(1)];
      setState(() {
        _route.add(segment, target: waypoints.last, vias: waypoints.sublist(1, waypoints.length - 1));
        _engine = path.engine;
      });
      unawaited(HapticFeedback.selectionClick());
    } on NoRouteFound {
      _say('Dorthin gibt es keinen passenden Weg. Setze den Punkt näher an einen Weg.');
    } on RoutingUnavailable catch (error) {
      _say('${error.message} Bitte gleich noch einmal versuchen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nach dem Bearbeiten die betroffenen Abschnitte neu routen; klappt es nicht, wird die Änderung zurückgenommen.
  Future<void> _reroute(List<int> dirty) async {
    if (dirty.isEmpty) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      for (final index in dirty) {
        final request = _route.request(index);
        final path = await _routePath(request);
        if (!mounted) return;
        setState(() {
          _route.setRouted(index, [request.first, ...path.points.skip(1)]);
          _engine = path.engine;
        });
      }
      unawaited(HapticFeedback.selectionClick());
    } on Object catch (error) {
      if (!mounted) return;
      setState(_route.undo);
      _say(
        error is NoRouteFound
            ? 'Dort gibt es keinen passenden Weg – Änderung zurückgenommen.'
            : 'Neu routen hat nicht geklappt – Änderung zurückgenommen.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fangbereich für Wegpunkte und Linie: etwa 28 Bildpunkte in Metern.
  double get _touchMeters {
    try {
      return 28 * RouteArrows.metersPerPixel(_map.camera.center.latitude, _map.camera.zoom);
    } on Object {
      return 40;
    }
  }

  void _deleteSelected() {
    final index = _selected;
    if (index == null || _busy) return;
    final dirty = _route.removeWaypoint(index);
    setState(() {
      _selected = null;
      _moving = false;
    });
    unawaited(_reroute(dirty));
  }

  void _longPress(GeoPoint point) {
    if (_tool != DrawTool.points || _busy || !_route.hasSegments) return;
    final segment = _route.nearestSegment(point, maxDistance: _touchMeters);
    if (segment == null) {
      _say('Lange auf die Linie drücken, um dort einen Punkt einzufügen.');
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    final dirty = _route.insertWaypoint(segment, point);
    setState(() {
      _selected = segment + 1;
      _moving = false;
    });
    unawaited(_reroute(dirty));
  }

  static List<int> _sampleIndices(int count, int max) {
    if (count <= max) return [for (var index = 0; index < count; index++) index];
    final step = (count - 1) / (max - 1);
    return {for (var index = 0; index < max; index++) (index * step).round()}.toList();
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // Eingaben auf der Karte

  void _tap(GeoPoint point) {
    if (_tool != DrawTool.points || _busy) return;
    if (_route.isEmpty) {
      unawaited(HapticFeedback.selectionClick());
      setState(() => _route.setStart(point));
      return;
    }
    // Gewählten Punkt verschieben.
    if (_moving && _selected != null) {
      final dirty = _route.moveWaypoint(_selected!, point);
      setState(() => _moving = false);
      unawaited(_reroute(dirty));
      return;
    }
    // Punkt antippen wählt ihn aus (zum Verschieben oder Löschen).
    if (_route.nearestWaypoint(point, maxDistance: _touchMeters) case final index?) {
      unawaited(HapticFeedback.selectionClick());
      setState(() => _selected = _selected == index ? null : index);
      return;
    }
    if (_selected != null) {
      setState(() => _selected = null);
      return;
    }
    unawaited(_routeTo([_route.end!, point]));
  }

  void _strokeStart(DragStartDetails details) {
    if (_busy) return;
    setState(
      () => _stroke
        ..clear()
        ..add(geoPoint(_map.camera.screenOffsetToLatLng(details.localPosition))),
    );
  }

  void _strokeUpdate(DragUpdateDetails details) {
    if (_busy || _stroke.isEmpty) return;
    final point = geoPoint(_map.camera.screenOffsetToLatLng(details.localPosition));
    if (Geo.distance(_stroke.last, point) < 8) return;
    setState(() => _stroke.add(point));
  }

  void _strokeEnd(DragEndDetails _) {
    if (_stroke.length < 2) {
      setState(_stroke.clear);
      return;
    }
    final stroke = [..._stroke];
    setState(_stroke.clear);
    if (_route.isEmpty) _route.setStart(stroke.first);
    final waypoints = FreehandStroke.waypoints(stroke);
    // Vom bisherigen Ende an den Anfang des Strichs anschließen.
    final end = _route.end!;
    final connected = Geo.distance(end, waypoints.first) > 30 ? [end, ...waypoints] : [end, ...waypoints.skip(1)];
    unawaited(_routeTo(Geo.thin(connected, FreehandStroke.maxWaypoints)));
  }

  // Werkzeuge

  void _undo() => setState(() {
    _route.undo();
    _selected = null;
    _moving = false;
  });

  Future<void> _close() async {
    if (_route.start case final start? when _route.canClose) await _routeTo([_route.end!, start]);
  }

  Future<void> _reset() async {
    if (_route.hasSegments) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Route verwerfen?'),
          content: const Text('Alle Abschnitte werden entfernt.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verwerfen')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(_route.reset);
  }

  Future<void> _save() async {
    final points = _route.points;
    if (points.length < 2 || _route.start == null) return;
    final store = ref.read(routeStoreProvider);
    final distance = Geo.length(points);
    final request = RouteRequest(
      discipline: _discipline,
      shape: RouteShape.drawn,
      start: _route.start!,
      distanceMeters: distance,
      preferences: _preferences,
    );
    final route = PlannedRoute(
      id: const Uuid().v4(),
      username: store.username,
      name: PlannedRoute.suggestedName(request, RouteVariant.balanced, distance),
      request: request,
      variant: RouteVariant.balanced,
      points: PlannedRoute.storable(points),
      engine: _engine ?? '',
      createdAt: DateTime.now(),
      runThresholdPace: _thresholdPace,
    );
    await store.save(route);
    if (!mounted) return;
    await Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id)));
  }

  /// Adresse suchen: ohne Start wird sie zum Start, sonst als nächster Punkt angehängt (auf Wegen geroutet).
  Future<void> _searchAddress() async {
    final place = await showModalBottomSheet<Place>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  _route.isEmpty ? 'Start suchen' : 'Nächsten Punkt suchen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _route.isEmpty
                      ? 'Die Adresse wird zum Start der Route.'
                      : 'Die Route wird vom bisherigen Ende auf Wegen bis zu dieser Adresse verlängert.',
                  style: LiquidText.label(context),
                ),
              ),
              AddressField(
                hint: 'Adresse oder Ort',
                icon: _route.isEmpty ? Icons.flag : Icons.add_location_alt_outlined,
                color: _route.isEmpty ? AppColors.of(context).good : AppColors.of(context).alert,
                near: _route.end ?? _nearCenter,
                autofocus: true,
                onSelected: (place) => Navigator.pop(context, place),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (place == null || !mounted) return;
    if (_route.isEmpty) {
      setState(() => _route.setStart(place.point));
      _map.move(latLng(place.point), 15);
    } else {
      await _routeTo([_route.end!, place.point]);
      if (mounted) PlannerMap.fit(_map, Geo.thin(_route.points, 200));
    }
  }

  GeoPoint? get _nearCenter {
    try {
      return _map.camera.zoom < 8 ? null : geoPoint(_map.camera.center);
    } on Object {
      return null;
    }
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                Text('Sportart und Umgebung', style: Theme.of(context).textTheme.titleLarge),
                SegmentedButton<RouteDiscipline>(
                  showSelectedIcon: false,
                  segments: [
                    for (final discipline in RouteDiscipline.values)
                      ButtonSegment(
                        value: discipline,
                        label: Text(discipline.label, textAlign: TextAlign.center),
                      ),
                  ],
                  selected: {_discipline},
                  onSelectionChanged: (selection) {
                    setState(() => _discipline = selection.single);
                    setSheet(() {});
                  },
                ),
                PreferenceChips(
                  discipline: _discipline,
                  selected: _preferences,
                  onChanged: (selection) {
                    setState(() => _preferences = selection);
                    setSheet(() {});
                  },
                ),
                Text(
                  'Gilt für die nächsten Abschnitte. Bereits gezeichnete bleiben, wie sie sind.',
                  style: LiquidText.label(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _route.points;
    final stats = _route.stats;
    final duration = RouteDuration.estimate(
      discipline: _discipline,
      distanceMeters: stats.distanceMeters,
      ascentMeters: stats.ascentMeters,
      runThresholdPace: _thresholdPace,
    );
    final color = variantColor(RouteVariant.balanced);
    final drawing = _tool == DrawTool.freehand;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frei planen'),
        actions: [
          IconButton(
            tooltip: 'Adresse suchen',
            onPressed: _busy ? null : () => unawaited(_searchAddress()),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Sportart und Umgebung',
            onPressed: _settings,
            icon: Icon(PreferenceChips.icon(_preferences.firstOrNull ?? RoutePreference.nature)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 4, LiquidSpacing.page, 10),
            child: PlannerModeSwitch(
              automatic: false,
              onChanged: (automatic) {
                if (!automatic) return;
                unawaited(
                  Navigator.of(context)
                      .pushReplacement(MaterialPageRoute<void>(builder: (_) => const RoutePlannerScreen())),
                );
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: drawing ? 'Karte: mit dem Finger eine Linie zeichnen' : 'Karte: Wegpunkte antippen',
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: _route.start == null ? PlannerMap.fallbackCenter : latLng(_route.start!),
                        initialZoom: _route.start == null ? 5.5 : 14,
                        onTap: (_, point) => _tap(geoPoint(point)),
                        onLongPress: (_, point) => _longPress(geoPoint(point)),
                        // Beim Zeichnen steht die Karte still; Doppeltippen setzt keine zwei Punkte.
                        interactionOptions: InteractionOptions(
                          flags: drawing
                              ? InteractiveFlag.none
                              : InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.doubleTapZoom,
                        ),
                      ),
                      children: [
                        const BaseTiles(),
                        PolylineLayer(
                          polylines: [
                            if (points.length > 1)
                              Polyline(
                                points: [for (final point in points) latLng(point)],
                                color: color,
                                strokeWidth: 5,
                                borderColor: Colors.white.withValues(alpha: 0.85),
                                borderStrokeWidth: 1.5,
                              ),
                            if (_stroke.length > 1)
                              Polyline(
                                points: [for (final point in _stroke) latLng(point)],
                                color: color.withValues(alpha: 0.5),
                                strokeWidth: 4,
                                pattern: StrokePattern.dashed(segments: const [10, 8]),
                              ),
                          ],
                        ),
                        if (points.length > 1) DirectionArrows(points: points, color: color),
                        if (points.length > 1) KilometerMarkers(points: points, color: color),
                        MarkerLayer(
                          markers: [
                            // Wegpunkte zum Bearbeiten (Start und Ziel haben eigene Symbole).
                            for (final (index, waypoint) in _route.waypoints.indexed)
                              if (index > 0 && (index < _route.waypoints.length - 1 || _route.isClosed))
                                Marker(
                                  point: latLng(waypoint),
                                  width: index == _selected ? 30 : 20,
                                  height: index == _selected ? 30 : 20,
                                  child: _Handle(color: color, selected: index == _selected),
                                ),
                            if (_route.end case final end? when _route.hasSegments && !_route.isClosed)
                              Marker(
                                point: latLng(end),
                                child: _Dot(
                                  color: AppColors.of(context).alert,
                                  icon: Icons.sports_score,
                                  selected: _selected == _route.waypoints.length - 1,
                                ),
                              ),
                            if (_route.start case final start?)
                              Marker(
                                point: latLng(start),
                                child: _Dot(
                                  color: AppColors.of(context).good,
                                  icon: Icons.flag,
                                  selected: _selected == 0,
                                ),
                              ),
                          ],
                        ),
                        MyLocationLayer(point: _myLocation),
                        osmAttribution(routingSource: _engine),
                      ],
                    ),
                  ),
                ),
                if (drawing)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _strokeStart,
                      onPanUpdate: _strokeUpdate,
                      onPanEnd: _strokeEnd,
                    ),
                  ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Column(
                    spacing: 8,
                    children: [
                      _ToolSwitch(tool: _tool, onChanged: (tool) => setState(() => _tool = tool)),
                      IgnorePointer(
                        child: LiquidSwitcher(
                          child: _Hint(
                            key: ValueKey('${_tool.name}${_route.isEmpty}$_busy$_selected$_moving'),
                            text: _busy
                                ? 'Wird auf Wege gelegt …'
                                : _moving
                                ? 'Tippe auf die neue Position des Punkts.'
                                : _selected != null
                                ? 'Punkt gewählt: verschieben oder löschen.'
                                : _route.isEmpty
                                ? (drawing
                                      ? 'Zeichne mit dem Finger los – der Anfang wird zum Start.'
                                      : 'Tippe den Start an oder suche eine Adresse (Lupe).')
                                : (drawing
                                      ? 'Weiterzeichnen: Die Linie wird auf echte Wege gelegt.'
                                      : 'Nächsten Punkt antippen · Punkt antippen zum Bearbeiten · lange auf die Linie '
                                            'drücken fügt einen Punkt ein.'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: LiquidSpacing.page,
                  right: LiquidSpacing.page,
                  bottom: LiquidSpacing.page + MediaQuery.paddingOf(context).bottom,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      LocateMeButton(map: _map, onLocated: (point) => setState(() => _myLocation = point)),
                      if (_selected case final index? when index < _route.waypoints.length)
                        _EditBar(
                          label: index == 0
                              ? 'Start'
                              : index == _route.waypoints.length - 1
                              ? 'Ziel'
                              : 'Punkt $index',
                          moving: _moving,
                          onMove: _busy ? null : () => setState(() => _moving = !_moving),
                          onDelete: _busy ? null : _deleteSelected,
                          onDone: () => setState(() {
                            _selected = null;
                            _moving = false;
                          }),
                        ),
                      _TelemetryBar(
                        distance: stats.distanceMeters,
                        ascent: stats.hasElevation ? stats.ascentMeters : null,
                        duration: duration,
                        pendingMeters: _stroke.length > 1 ? Geo.length(_stroke) : null,
                        busy: _busy,
                        surroundings: '${_discipline.label} · ${RoutePreference.describe(_preferences)}',
                        onUndo: _busy || _route.isEmpty ? null : _undo,
                        onClose: _busy || !_route.canClose ? null : () => unawaited(_close()),
                        onReset: _busy || _route.isEmpty ? null : () => unawaited(_reset()),
                        onSave: _busy || points.length < 2 ? null : () => unawaited(_save()),
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

class _ToolSwitch extends StatelessWidget {
  const _ToolSwitch({required this.tool, required this.onChanged});

  final DrawTool tool;
  final ValueChanged<DrawTool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: LiquidSurface(
      radius: LiquidRadii.pill,
      strong: true,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<DrawTool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide.none),
          segments: const [
            ButtonSegment(value: DrawTool.points, icon: Icon(Icons.touch_app_outlined), label: Text('Punkte')),
            ButtonSegment(value: DrawTool.freehand, icon: Icon(Icons.gesture), label: Text('Zeichnen')),
          ],
          selected: {tool},
          onSelectionChanged: (selection) => onChanged(selection.single),
        ),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: LiquidSurface(
      radius: LiquidRadii.pill,
      strong: true,
      shadow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.footnote(context).copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    ),
  );
}

/// Schwebende Glasleiste: Live-Werte und Werkzeuge.
class _TelemetryBar extends StatelessWidget {
  const _TelemetryBar({
    required this.distance,
    required this.ascent,
    required this.duration,
    required this.pendingMeters,
    required this.busy,
    required this.surroundings,
    required this.onUndo,
    required this.onClose,
    required this.onReset,
    required this.onSave,
  });

  final double distance;
  final double? ascent;
  final Duration duration;
  final double? pendingMeters;
  final bool busy;
  final String surroundings;
  final VoidCallback? onUndo;
  final VoidCallback? onClose;
  final VoidCallback? onReset;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => LiquidCard(
    strong: true,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Semantics(
          liveRegion: true,
          label:
              'Distanz ${RouteFormat.distance(distance)}, '
              '${ascent == null ? 'Höhe unbekannt' : 'Anstieg ${RouteFormat.elevation(ascent!)}'}, '
              'Dauer ${RouteFormat.duration(duration)}',
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: _Value(
                  value: RouteFormat.distance(distance),
                  label: pendingMeters == null ? 'Distanz' : '+ ${RouteFormat.distance(pendingMeters!)} Entwurf',
                ),
              ),
              Expanded(
                child: _Value(value: ascent == null ? '–' : '↑ ${ascent!.round()} hm', label: 'Anstieg'),
              ),
              Expanded(
                child: _Value(value: RouteFormat.duration(duration), label: 'geschätzt'),
              ),
              if (busy) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
        ),
        Text(surroundings, style: LiquidText.label(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(
          children: [
            IconButton(tooltip: 'Rückgängig', onPressed: onUndo, icon: const Icon(Icons.undo)),
            IconButton(tooltip: 'Rundweg schließen', onPressed: onClose, icon: const Icon(Icons.loop)),
            IconButton(tooltip: 'Zurücksetzen', onPressed: onReset, icon: const Icon(Icons.delete_sweep_outlined)),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onSave,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Icon(Icons.bookmark_add_outlined, size: 18),
                      Flexible(child: Text('Speichern', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Value extends StatelessWidget {
  const _Value({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: LiquidText.kpi(context, size: 20)),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: LiquidText.label(context)),
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.icon, this.selected = false});

  final Color color;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: selected ? Colors.amber : Colors.white, width: selected ? 3 : 2),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 16, color: Colors.white),
    ),
  );
}

/// Griff eines Wegpunkts (gewählt: größer, gelber Rand).
class _Handle extends StatelessWidget {
  const _Handle({required this.color, required this.selected});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: selected ? Colors.amber : color, width: selected ? 4 : 3),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))],
    ),
  );
}

/// Werkzeuge für den gewählten Wegpunkt.
class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.label,
    required this.moving,
    required this.onMove,
    required this.onDelete,
    required this.onDone,
  });

  final String label;
  final bool moving;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => LiquidSurface(
    radius: LiquidRadii.pill,
    strong: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: moving ? 'Verschieben abbrechen' : 'Punkt verschieben',
            isSelected: moving,
            onPressed: onMove,
            icon: const Icon(Icons.open_with),
          ),
          IconButton(tooltip: 'Punkt löschen', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          IconButton(tooltip: 'Fertig', onPressed: onDone, icon: const Icon(Icons.check)),
        ],
      ),
    ),
  );
}

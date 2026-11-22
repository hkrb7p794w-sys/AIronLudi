import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/location_source.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../endurance/endurance_controller.dart';
import 'route_detail_screen.dart';
import 'route_draw_screen.dart';
import 'route_parts.dart';

/// Was ein Antippen der Karte setzt.
enum _PinTarget { start, destination }

/// Routenplaner auf OpenStreetMap: Start (Standort oder Pin), Rundweg / zum Ziel / Richtung, Distanz, Wegearten und
/// optional Höhenmeter; erzeugt 2–3 Vorschläge mit Karte, Richtungspfeilen, Höhenprofil, Kennzahlen, „Neu würfeln“,
/// Übernahme und Export. Liegen Vorschläge vor, ist die Karte nur zum Ansehen: Punkte setzt dann nur ein langes
/// Drücken oder „Startpunkt ändern“ – versehentliches Antippen beim Zoomen löscht nichts mehr.
class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  ConsumerState<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  final _map = MapController();
  late RouteDiscipline _discipline;
  late RouteShape _shape;
  late double _kilometers;
  late final TextEditingController _distanceField;
  bool _wantsElevation = false;
  int _elevation = 150;
  CompassDirection _direction = CompassDirection.north;
  _PinTarget _pin = _PinTarget.start;
  Set<RoutePreference> _preferences = {};

  /// Nach „Startpunkt ändern“: der nächste Tipp setzt den Punkt, auch wenn Vorschläge vorliegen.
  bool _editingPins = false;

  GeoPoint? _start;
  bool _startFromLocation = false;
  GeoPoint? _destination;
  bool _locating = false;

  bool _planning = false;
  String? _progress;
  String? _problem;
  int _seed = DateTime.now().millisecondsSinceEpoch % 100000;
  List<PlannedRoute> _routes = const [];
  int _selected = 0;
  final Set<String> _saved = {};

  @override
  void initState() {
    super.initState();
    final settings = ref.read(routeStoreProvider).settings;
    _discipline = settings.discipline;
    _shape = settings.shape;
    _kilometers = settings.distanceKilometers.clamp(_minKm, _maxKm);
    _distanceField = TextEditingController(text: _kmText(_kilometers));
    _preferences = {...settings.preferences};
    if (settings.elevationGain case final gain?) {
      _wantsElevation = true;
      _elevation = gain;
    }
  }

  @override
  void dispose() {
    _distanceField.dispose();
    super.dispose();
  }

  double get _minKm => 1;
  double get _maxKm => RouteRequest.maxDistance(_discipline) / 1000;
  int get _maxElevation => _discipline.isBike ? 4000 : 2000;

  static String _kmText(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1).replaceAll('.', ',');

  PlannedRoute? get _current => _routes.isEmpty ? null : _routes[_selected.clamp(0, _routes.length - 1)];

  RouteRequest? get _request {
    final start = _start;
    if (start == null) return null;
    return RouteRequest(
      discipline: _discipline,
      shape: _shape,
      start: start,
      destination: _shape == RouteShape.toDestination ? _destination : null,
      bearingDegrees: _shape == RouteShape.direction ? _direction.degrees : null,
      distanceMeters: _kilometers * 1000,
      elevationGainMeters: _wantsElevation ? _elevation.toDouble() : null,
      preferences: _preferences,
    );
  }

  /// Vorschläge liegen vor: Antippen verschiebt keine Punkte (Ansichtsmodus).
  bool get _pinsLocked => _routes.isNotEmpty && !_editingPins;

  void _clearResults() {
    _routes = const [];
    _selected = 0;
    _problem = null;
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _problem = null;
    });
    try {
      final point = await ref.read(locationSourceProvider).current();
      if (!mounted) return;
      setState(() {
        _start = point;
        _startFromLocation = true;
        if (_shape == RouteShape.toDestination && _destination == null) _pin = _PinTarget.destination;
        _clearResults();
      });
      PlannerMap.fit(_map, [point, ?_destination]);
    } on LocationProblem catch (problem) {
      if (!mounted) return;
      setState(() => _problem = problem.message);
      if (problem.canOpenSettings) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(problem.message),
            action: SnackBarAction(label: 'Einstellungen', onPressed: DeviceLocationSource.openSettings),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _tapMap(GeoPoint point) {
    if (_pinsLocked) return;
    _placePin(point);
  }

  /// Langes Drücken setzt immer einen Punkt (ausdrücklich), auch über vorhandenen Vorschlägen.
  void _longPressMap(GeoPoint point) {
    HapticFeedback.mediumImpact();
    _placePin(point);
  }

  void _placePin(GeoPoint point) {
    HapticFeedback.selectionClick();
    setState(() {
      _editingPins = false;
      if (_shape == RouteShape.toDestination && _pin == _PinTarget.destination) {
        _destination = point;
        _pin = _PinTarget.start;
      } else {
        _start = point;
        _startFromLocation = false;
        if (_shape == RouteShape.toDestination && _destination == null) _pin = _PinTarget.destination;
      }
      _clearResults();
    });
  }

  void _changeStart() => setState(() {
    _editingPins = true;
    _pin = _PinTarget.start;
  });

  void _reset() => setState(() {
    _start = null;
    _destination = null;
    _startFromLocation = false;
    _editingPins = false;
    _pin = _PinTarget.start;
    _clearResults();
  });

  void _openDrawing() {
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RouteDrawScreen(start: _start, discipline: _discipline, preferences: _preferences),
        ),
      ),
    );
  }

  Future<void> _plan({bool reroll = false}) async {
    final request = _request;
    if (request == null) {
      setState(() => _problem = 'Bitte zuerst einen Startpunkt wählen: Standort oder Pin auf der Karte.');
      return;
    }
    if (request.problem case final problem?) {
      setState(() => _problem = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    if (reroll) _seed++;
    setState(() {
      _planning = true;
      _progress = 'Wegenetz wird abgefragt …';
      _problem = null;
    });
    final store = ref.read(routeStoreProvider);
    unawaited(
      store.updateSettings(
        (settings) => settings
          ..discipline = _discipline
          ..shape = _shape
          ..distanceKilometers = _kilometers
          ..elevationGain = _wantsElevation ? _elevation : null
          ..preferences = {..._preferences},
      ),
    );
    try {
      final routes =
          await RoutePlanner(ref.read(routingBackendProvider), features: ref.read(routeFeatureSourceProvider)).generate(
            request,
            username: store.username,
            seed: _seed,
            runThresholdPace: ref.read(enduranceControllerProvider).plan?.request.thresholds.runThresholdPace,
            onProgress: (message) {
              if (mounted) setState(() => _progress = message);
            },
            isCancelled: () => !mounted,
          );
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _selected = 0;
        _editingPins = false;
      });
      PlannerMap.fit(_map, [for (final route in routes) ...Geo.thin(route.points, 200)]);
    } on NoRouteFound catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } on RoutingUnavailable catch (error) {
      if (mounted) {
        setState(
          () => _problem =
              '${error.message} Die öffentlichen Routing-Server sind gerade nicht erreichbar – bitte '
              'gleich noch einmal versuchen.',
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _problem = '${error.message}');
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _save(PlannedRoute route, {bool open = false}) async {
    await ref.read(routeStoreProvider).save(route);
    if (!mounted) return;
    setState(() => _saved.add(route.id));
    if (open) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route gespeichert.')));
    }
  }

  Future<void> _assign(PlannedRoute route) async {
    if (await assignRouteToSession(context, ref, route) && mounted) setState(() => _saved.add(route.id));
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route planen'),
        actions: [
          if (_start != null)
            IconButton(
              tooltip: 'Planer zurücksetzen',
              onPressed: _planning ? null : _reset,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 4, LiquidSpacing.page, 12),
            child: PlannerModeSwitch(automatic: true, onChanged: (automatic) => automatic ? null : _openDrawing()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 0),
            child: Stack(
              children: [
                PlannerMap(
                  controller: _map,
                  start: _start,
                  destination: _shape == RouteShape.toDestination ? _destination : null,
                  routes: _routes,
                  selected: current,
                  onTap: _planning ? null : _tapMap,
                  onLongPress: _planning ? null : _longPressMap,
                  routingSource: current?.engine,
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10,
                  child: IgnorePointer(
                    child: LiquidSwitcher(
                      child: _MapHint(key: ValueKey('$_start$_destination$_shape$_pin$_pinsLocked'), text: _hint),
                    ),
                  ),
                ),
              ],
            ),
          ),
          FormSection(
            header: 'Start',
            children: [
              ListTile(
                leading: _locating
                    ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Icon(Icons.my_location, color: _startFromLocation ? theme.colorScheme.primary : null),
                title: const Text('Aktueller Standort'),
                subtitle: Text(
                  _start == null
                      ? 'oder einen Pin auf der Karte setzen'
                      : _startFromLocation
                      ? 'Start: dein Standort'
                      : 'Start: Pin auf der Karte',
                ),
                onTap: _locating || _planning ? null : () => unawaited(_useLocation()),
              ),
              if (_routes.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.edit_location_alt_outlined,
                    color: _editingPins ? theme.colorScheme.primary : null,
                  ),
                  title: Text(_shape == RouteShape.toDestination ? 'Start oder Ziel ändern' : 'Startpunkt ändern'),
                  subtitle: Text(
                    _editingPins ? 'Tippe jetzt auf die Karte.' : 'Oder einen Punkt auf der Karte lange drücken.',
                  ),
                  onTap: _planning ? null : _changeStart,
                ),
            ],
          ),
          FormSection(
            header: 'Disziplin',
            footer: _discipline.surfaces,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<RouteDiscipline>(
                  showSelectedIcon: false,
                  segments: [
                    for (final discipline in RouteDiscipline.values)
                      ButtonSegment(
                        value: discipline,
                        label: Text(discipline.label, textAlign: TextAlign.center),
                      ),
                  ],
                  selected: {_discipline},
                  onSelectionChanged: (selection) => setState(() {
                    _discipline = selection.single;
                    _kilometers = _kilometers.clamp(_minKm, _maxKm);
                    _distanceField.text = _kmText(_kilometers);
                    _elevation = math.min(_elevation, _maxElevation);
                    _clearResults();
                  }),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Umgebung',
            footer: _preferences.isEmpty
                ? 'Ausgewogener Mix aus Natur- und befestigten Wegen.'
                : [
                    for (final preference in RoutePreference.values)
                      if (_preferences.contains(preference)) preference.detail,
                  ].join(' · '),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: PreferenceChips(
                  selected: _preferences,
                  onChanged: (selection) => setState(() {
                    _preferences = selection;
                    _clearResults();
                  }),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Strecke',
            footer: switch (_shape) {
              RouteShape.loop => 'Start und Ziel sind gleich – die Route schließt sich als Runde.',
              RouteShape.toDestination =>
                'Setze das Ziel mit einem Pin. Ist es näher als die Wunschdistanz, baut der Planer einen Umweg ein.',
              RouteShape.direction => 'Offenes Ziel: Die Route führt genau die Wunschdistanz in diese Richtung.',
              RouteShape.drawn => null,
            },
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<RouteShape>(
                  showSelectedIcon: false,
                  segments: [
                    for (final shape in RouteShape.generated) ButtonSegment(value: shape, label: Text(shape.label)),
                  ],
                  selected: {_shape},
                  onSelectionChanged: (selection) => setState(() {
                    _shape = selection.single;
                    _pin = _shape == RouteShape.toDestination && _start != null && _destination == null
                        ? _PinTarget.destination
                        : _PinTarget.start;
                    _clearResults();
                  }),
                ),
              ),
              if (_shape == RouteShape.toDestination)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SegmentedButton<_PinTarget>(
                    segments: const [
                      ButtonSegment(value: _PinTarget.start, label: Text('Pin: Start'), icon: Icon(Icons.flag)),
                      ButtonSegment(
                        value: _PinTarget.destination,
                        label: Text('Pin: Ziel'),
                        icon: Icon(Icons.sports_score),
                      ),
                    ],
                    selected: {_pin},
                    onSelectionChanged: (selection) => setState(() => _pin = selection.single),
                  ),
                ),
              if (_shape == RouteShape.direction)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final direction in CompassDirection.values)
                        ChoiceChip(
                          label: Text(direction.label),
                          selected: _direction == direction,
                          onSelected: (_) => setState(() {
                            _direction = direction;
                            _clearResults();
                          }),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Ziel',
            footer:
                'Der Planer passt die Wegpunkte an, bis die Distanz auf ±${GermanFormat.decimal(RouteRequest.tolerance * 100)} % '
                'stimmt (bei Strecken zum festen Ziel, soweit das Wegenetz es zulässt).',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
                child: Row(
                  children: [
                    const Expanded(child: Text('Distanz')),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        controller: _distanceField,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none, suffixText: 'km'),
                        onSubmitted: _setDistanceText,
                        onTapOutside: (_) => _setDistanceText(_distanceField.text),
                      ),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _kilometers.clamp(_minKm, _maxKm),
                min: _minKm,
                max: _maxKm,
                divisions: ((_maxKm - _minKm) * (_discipline.isBike ? 1 : 2)).round(),
                label: '${_kmText(_kilometers)} km',
                onChanged: (value) => setState(() {
                  _kilometers = _discipline.isBike ? value.roundToDouble() : (value * 2).round() / 2;
                  _distanceField.text = _kmText(_kilometers);
                  _clearResults();
                }),
              ),
              SwitchListTile(
                title: const Text('Höhenmeter vorgeben'),
                subtitle: Text(_wantsElevation ? 'ca. $_elevation hm Anstieg' : 'flach oder hügelig – egal'),
                value: _wantsElevation,
                onChanged: (value) => setState(() {
                  _wantsElevation = value;
                  _clearResults();
                }),
              ),
              if (_wantsElevation)
                Slider(
                  value: _elevation.toDouble().clamp(0, _maxElevation.toDouble()),
                  max: _maxElevation.toDouble(),
                  divisions: _maxElevation ~/ (_discipline.isBike ? 50 : 10),
                  label: '$_elevation hm',
                  onChanged: (value) => setState(() {
                    _elevation = value.round();
                    _clearResults();
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 16, LiquidSpacing.page, 4),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _planning ? null : () => unawaited(_plan()),
              icon: _planning
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.route),
              label: Text(_planning ? (_progress ?? 'Wird berechnet …') : 'Routen vorschlagen'),
            ),
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 12, LiquidSpacing.page, 0),
              child: LiquidCard(
                tint: Colors.orange,
                child: Row(
                  spacing: 12,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    Expanded(child: Text(problem)),
                  ],
                ),
              ),
            ),
          LiquidSwitcher(
            child: current == null
                ? const SizedBox.shrink(key: ValueKey('leer'))
                : _Results(
                    key: ValueKey(_routes.map((route) => route.id).join()),
                    routes: _routes,
                    selected: _selected,
                    saved: _saved,
                    onSelect: (index) {
                      setState(() => _selected = index);
                      PlannerMap.fit(_map, Geo.thin(_routes[index].points, 200));
                    },
                    onReroll: _planning ? null : () => unawaited(_plan(reroll: true)),
                    onSave: (route) => unawaited(_save(route)),
                    onOpen: (route) => unawaited(_save(route, open: true)),
                    onAssign: (route) => unawaited(_assign(route)),
                  ),
          ),
        ],
      ),
    );
  }

  String get _hint {
    if (_start == null) return 'Tippe auf die Karte, um den Start zu setzen – oder nutze deinen Standort.';
    if (_editingPins) {
      return _pin == _PinTarget.destination
          ? 'Tippe auf die Karte für das neue Ziel.'
          : 'Tippe auf die Karte für den neuen Start.';
    }
    if (_pinsLocked) return 'Ansicht: Zum Verschieben lange drücken oder „Startpunkt ändern“.';
    if (_shape == RouteShape.toDestination && (_destination == null || _pin == _PinTarget.destination)) {
      return 'Tippe auf die Karte, um das Ziel zu setzen.';
    }
    return _routes.isEmpty ? 'Antippen verschiebt den Start.' : 'Wähle unten einen Vorschlag.';
  }

  void _setDistanceText(String text) {
    final value = parseNumber(text);
    setState(() {
      if (value != null) _kilometers = value.clamp(_minKm, _maxKm).toDouble();
      _distanceField.text = _kmText(_kilometers);
      _clearResults();
    });
  }
}

class _MapHint extends StatelessWidget {
  const _MapHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: LiquidSurface(
      radius: LiquidRadii.pill,
      strong: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    ),
  );
}

/// Vorschläge: Auswahl als Glaskarten, darunter Kennzahlen, Höhenprofil und Aktionen der gewählten Route.
class _Results extends StatelessWidget {
  const _Results({
    super.key,
    required this.routes,
    required this.selected,
    required this.saved,
    required this.onSelect,
    required this.onReroll,
    required this.onSave,
    required this.onOpen,
    required this.onAssign,
  });

  final List<PlannedRoute> routes;
  final int selected;
  final Set<String> saved;
  final ValueChanged<int> onSelect;
  final VoidCallback? onReroll;
  final ValueChanged<PlannedRoute> onSave;
  final ValueChanged<PlannedRoute> onOpen;
  final ValueChanged<PlannedRoute> onAssign;

  @override
  Widget build(BuildContext context) {
    final route = routes[selected.clamp(0, routes.length - 1)];
    final isSaved = saved.contains(route.id);
    return LiquidAppear(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 20, LiquidSpacing.page, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: LiquidSpacing.m,
          children: [
            Row(
              children: [
                Expanded(child: Text('VORSCHLÄGE', style: LiquidText.sectionHeader(context))),
                TextButton.icon(
                  onPressed: onReroll,
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Neu würfeln'),
                ),
              ],
            ),
            // Natürliche Höhe statt fester Höhe: wächst mit der Schriftgröße (Dynamic Type).
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    for (final (index, item) in routes.indexed)
                      _VariantCard(route: item, isSelected: index == selected, onTap: () => onSelect(index)),
                  ],
                ),
              ),
            ),
            LiquidCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: LiquidSpacing.m,
                children: [
                  Text(route.name, style: Theme.of(context).textTheme.titleMedium),
                  RouteStatsRow(route: route),
                  if (route.preferenceShare case final share?)
                    AppChip(
                      text: 'ca. ${(share * 100).round()} % ${RoutePreference.describe(route.request.preferences)}',
                      color: variantColor(route.variant),
                    ),
                  ElevationProfileChart(route: route),
                  if (!route.request.withinTolerance(route.stats.distanceMeters))
                    Text(
                      route.request.shape == RouteShape.toDestination &&
                              route.stats.distanceMeters > route.request.distanceMeters
                          ? 'Das Ziel liegt weiter als die Wunschdistanz – kürzer geht es nicht.'
                          : 'Näher an die Wunschdistanz kam das Wegenetz hier nicht. „Neu würfeln“ probiert andere Wege.',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => onAssign(route),
                  icon: const Icon(Icons.event_available),
                  label: const Text('In Einheit übernehmen'),
                ),
                OutlinedButton.icon(
                  onPressed: isSaved ? () => onOpen(route) : () => onSave(route),
                  icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_add_outlined),
                  label: Text(isSaved ? 'Gespeichert – öffnen' : 'Speichern'),
                ),
                Builder(
                  builder: (context) => OutlinedButton.icon(
                    onPressed: () => unawaited(shareRoute(context, route, fit: false)),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('GPX'),
                  ),
                ),
                Builder(
                  builder: (context) => OutlinedButton.icon(
                    onPressed: () => unawaited(shareRoute(context, route, fit: true)),
                    icon: const Icon(Icons.watch),
                    label: const Text('FIT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.route, required this.isSelected, required this.onTap});

  final PlannedRoute route;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = variantColor(route.variant);
    final stats = route.stats;
    return Semantics(
      selected: isSelected,
      button: true,
      label:
          '${route.variant.label}: ${RouteFormat.distance(stats.distanceMeters)}, '
          '${stats.hasElevation ? RouteFormat.elevation(stats.ascentMeters) : 'Höhe unbekannt'}, '
          '${RouteFormat.duration(route.duration)}',
      excludeSemantics: true,
      child: SizedBox(
        width: 172,
        child: AnimatedContainer(
          duration: LiquidMotion.of(context, LiquidMotion.medium),
          curve: LiquidMotion.settle,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LiquidRadii.card),
            border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
          ),
          child: LiquidCard(
            radius: LiquidRadii.card - 2,
            shadow: false,
            tint: isSelected ? color : null,
            padding: const EdgeInsets.all(14),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: const SizedBox.square(dimension: 10),
                    ),
                    Expanded(
                      child: Text(
                        route.variant.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                Text(RouteFormat.distance(stats.distanceMeters), style: LiquidText.kpi(context, size: 22)),
                Text(
                  '${stats.hasElevation ? '↑ ${RouteFormat.elevation(stats.ascentMeters)}' : '–'} · '
                  '${RouteFormat.duration(route.duration)}',
                  style: LiquidText.label(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

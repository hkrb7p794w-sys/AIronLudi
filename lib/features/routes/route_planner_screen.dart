import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../services/routing/location_source.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'address_field.dart';
import 'my_location.dart';
import 'route_detail_screen.dart';
import 'route_draw_screen.dart';
import 'route_parts.dart';
import 'route_planner_controller.dart';

/// Routenplaner auf OpenStreetMap: Start (Adresse, Standort oder Pin), Rundweg / zum Ziel / Richtung, Distanz,
/// Wegearten und optional Höhenmeter; zeigt bis zu drei Vorschläge, sobald sie einzeln fertig sind – mit Karte,
/// Richtungspfeilen, Kilometermarken, Höhenprofil, Kennzahlen, „Neu würfeln“, Übernahme und Export. Der Stand liegt im
/// [RoutePlannerController] und bleibt beim Verlassen erhalten. Liegen Vorschläge vor, ist die Karte nur zum Ansehen:
/// Antippen öffnet das Vollbild, Punkte setzt langes Drücken oder „Startpunkt ändern“.
class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  ConsumerState<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  final _map = MapController();
  late final TextEditingController _distanceField;
  bool _locating = false;
  int _fitted = 0;

  RoutePlannerController get _c => ref.read(routePlannerControllerProvider);

  @override
  void initState() {
    super.initState();
    _distanceField = TextEditingController(text: _kmText(_c.kilometers));
    // Bei vorhandenen Vorschlägen (Rückkehr in den Planer) die Karte darauf ausrichten.
    _fitted = _c.routes.isEmpty ? _c.fitGeneration : _c.fitGeneration - 1;
  }

  @override
  void dispose() {
    _distanceField.dispose();
    super.dispose();
  }

  static String _kmText(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    _c.update((planner) => planner.problem = null);
    try {
      final point = await ref.read(locationSourceProvider).current();
      if (!mounted) return;
      _c.useLocation(point);
      PlannerMap.fit(_map, [point, ?_c.destination]);
    } on LocationProblem catch (problem) {
      if (!mounted) return;
      _c.update((planner) => planner.problem = problem.message);
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

  /// Antippen öffnet die Karte im Vollbild; nur nach „Startpunkt ändern“ setzt der Tipp einen Punkt.
  void _tapMap(GeoPoint point) {
    if (_c.editingPins) {
      _placePin(point);
      return;
    }
    unawaited(_openFullscreen());
  }

  Future<void> _openFullscreen() {
    final c = _c;
    return FullscreenRouteMap.open(
      context,
      start: c.start,
      destination: c.shape == RouteShape.toDestination ? c.destination : null,
      routes: c.routes,
      selected: c.selected,
      onSelect: c.select,
      onLongPress: c.planning
          ? null
          : (point) {
              _longPressMap(point);
              return (start: c.start, destination: c.shape == RouteShape.toDestination ? c.destination : null);
            },
    );
  }

  /// Langes Drücken setzt immer einen Punkt (ausdrücklich), auch über vorhandenen Vorschlägen.
  void _longPressMap(GeoPoint point) {
    unawaited(HapticFeedback.mediumImpact());
    _placePin(point);
  }

  void _placePin(GeoPoint point) {
    unawaited(HapticFeedback.selectionClick());
    _c.placePin(point);
  }

  void _selectAddress(Place place, {required bool isDestination}) {
    final c = _c..selectAddress(place, isDestination: isDestination);
    PlannerMap.fit(_map, [?c.start, if (c.shape == RouteShape.toDestination) ?c.destination]);
  }

  /// Bezugspunkt für Vorschläge: Start, sonst Kartenmitte.
  GeoPoint? get _near {
    if (_c.start case final start?) return start;
    try {
      final center = _map.camera.center;
      return _map.camera.zoom < 8 ? null : geoPoint(center);
    } on Object {
      return null;
    }
  }

  void _openDrawing() {
    final c = _c;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RouteDrawScreen(start: c.start, discipline: c.discipline, preferences: c.preferences),
        ),
      ),
    );
  }

  Future<void> _plan({bool reroll = false}) async {
    FocusScope.of(context).unfocus();
    await _c.plan(reroll: reroll);
  }

  Future<void> _save(PlannedRoute route, {bool open = false}) async {
    await _c.save(route);
    if (!mounted) return;
    if (open) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route gespeichert.')));
    }
  }

  /// Aktuelle Vorgaben samt Start als Vorlage („Gassi 3 km ab Zuhause“).
  Future<void> _saveTemplate() async {
    final c = _c;
    final start = c.start;
    if (start == null) return;
    final favorite = ref.read(routeStoreProvider).favoriteNear(start);
    final place = favorite?.name ?? c.startAddress?.split(', ').first;
    final suggestion =
        '${c.discipline == RouteDiscipline.walk ? 'Gassi' : c.discipline.label} '
        '${_kmText(c.kilometers)} km${place == null ? '' : ' ab $place'}';
    final name = await askName(context, title: 'Als Vorlage speichern', initial: suggestion, hint: 'z. B. Gassi 3 km');
    if (name == null || !mounted) return;
    await ref
        .read(routeStoreProvider)
        .saveTemplate(
          RouteTemplate(
            id: const Uuid().v4(),
            name: name,
            discipline: c.discipline,
            shape: c.shape,
            kilometers: c.kilometers,
            start: start,
            startLabel: favorite?.name ?? c.startAddress,
            preferences: c.preferences,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Vorlage „$name“ gespeichert – unter Routen.')));
    }
  }

  Future<void> _assign(PlannedRoute route) async {
    if (await assignRouteToSession(context, ref, route) && mounted) _c.markSaved(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(routePlannerControllerProvider);
    final current = c.current;
    if (c.fitGeneration != _fitted) {
      _fitted = c.fitGeneration;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => PlannerMap.fit(_map, [for (final route in c.routes) ...Geo.thin(route.points, 200)]),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route planen'),
        actions: [
          if (c.start != null && c.shape != RouteShape.toDestination)
            IconButton(
              tooltip: 'Als Vorlage speichern',
              onPressed: c.planning ? null : () => unawaited(_saveTemplate()),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          if (c.start != null)
            IconButton(
              tooltip: 'Planer zurücksetzen',
              onPressed: c.planning ? null : c.reset,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (c.forSlot case final slot?)
            Padding(
              padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 4, LiquidSpacing.page, 4),
              child: LiquidCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                tint: theme.colorScheme.primary,
                child: Row(
                  spacing: 10,
                  children: [
                    const Icon(Icons.event_note),
                    Expanded(child: Text('Für „${slot.title}“ am ${GermanFormat.date(slot.day)}', maxLines: 2)),
                    IconButton(
                      tooltip: 'Ohne Einheit planen',
                      icon: const Icon(Icons.close),
                      onPressed: () => c.update((planner) => planner.forSlot = null),
                    ),
                  ],
                ),
              ),
            ),
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
                  start: c.start,
                  destination: c.shape == RouteShape.toDestination ? c.destination : null,
                  routes: c.routes,
                  selected: current,
                  onTap: c.planning ? null : _tapMap,
                  onLongPress: c.planning ? null : _longPressMap,
                  myLocation: c.myLocation,
                  routingSource: current?.engine,
                ),
                Positioned(
                  right: 8,
                  bottom: 30,
                  child: LocateMeButton(
                    map: _map,
                    onLocated: (point) => c.update((planner) => planner.myLocation = point),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: LiquidSurface(
                    radius: LiquidRadii.pill,
                    strong: true,
                    shadow: false,
                    child: IconButton(
                      tooltip: 'Karte im Vollbild',
                      icon: const Icon(Icons.open_in_full, size: 20),
                      onPressed: () => unawaited(_openFullscreen()),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10,
                  child: IgnorePointer(
                    child: LiquidSwitcher(
                      child: _MapHint(key: ValueKey('$c.start$c.destination$c.shape$c.pin$c.pinsLocked'), text: _hint),
                    ),
                  ),
                ),
              ],
            ),
          ),
          FormSection(
            header: 'Start',
            children: [
              AddressField(
                hint: 'Startadresse oder Ort',
                icon: Icons.flag,
                color: AppColors.of(context).good,
                value: c.startAddress,
                near: _near,
                enabled: !c.planning,
                point: c.start,
                onSelected: (place) => _selectAddress(place, isDestination: false),
              ),
              ListTile(
                leading: _locating
                    ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Icon(Icons.my_location, color: c.startFromLocation ? theme.colorScheme.primary : null),
                title: const Text('Aktueller Standort'),
                subtitle: Text(
                  c.start == null
                      ? 'oder einen Pin auf der Karte setzen'
                      : c.startFromLocation
                      ? 'Start: dein Standort'
                      : c.startAddress != null
                      ? 'Start: gesuchte Adresse'
                      : 'Start: Pin auf der Karte',
                ),
                onTap: _locating || c.planning ? null : () => unawaited(_useLocation()),
              ),
              if (c.routes.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.edit_location_alt_outlined,
                    color: c.editingPins ? theme.colorScheme.primary : null,
                  ),
                  title: Text(c.shape == RouteShape.toDestination ? 'Start oder Ziel ändern' : 'Startpunkt ändern'),
                  subtitle: Text(
                    c.editingPins ? 'Tippe jetzt auf die Karte.' : 'Oder einen Punkt auf der Karte lange drücken.',
                  ),
                  onTap: c.planning ? null : c.changeStart,
                ),
            ],
          ),
          FormSection(
            header: 'Disziplin',
            footer: c.discipline.surfaces,
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
                  selected: {c.discipline},
                  onSelectionChanged: (selection) {
                    c.setDiscipline(selection.single);
                    _distanceField.text = _kmText(c.kilometers);
                  },
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Umgebung',
            footer: c.preferences.isEmpty
                ? 'Ausgewogener Mix aus Natur- und befestigten Wegen.'
                : [
                    for (final preference in RoutePreference.values)
                      if (c.preferences.contains(preference)) preference.detail,
                  ].join(' · '),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: PreferenceChips(
                  discipline: c.discipline,
                  selected: c.preferences,
                  onChanged: (selection) => c.update((planner) {
                    planner.preferences = selection;
                    planner.clearResults();
                  }),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Strecke',
            footer: switch (c.shape) {
              RouteShape.loop => 'Start und Ziel sind gleich – die Route schließt sich als Runde.',
              RouteShape.toDestination =>
                'Ziel als Adresse eingeben oder mit einem Pin setzen. Ist es näher als die Wunschdistanz, baut der Planer '
                    'einen Umweg ein.',
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
                  selected: {c.shape},
                  onSelectionChanged: (selection) => c.setShape(selection.single),
                ),
              ),
              if (c.shape == RouteShape.toDestination)
                AddressField(
                  hint: 'Zieladresse oder Ort',
                  icon: Icons.sports_score,
                  color: AppColors.of(context).alert,
                  value: c.destinationAddress,
                  near: _near,
                  enabled: !c.planning,
                  point: c.destination,
                  onSelected: (place) => _selectAddress(place, isDestination: true),
                ),
              if (c.shape == RouteShape.toDestination)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SegmentedButton<PinTarget>(
                    segments: const [
                      ButtonSegment(value: PinTarget.start, label: Text('Pin: Start'), icon: Icon(Icons.flag)),
                      ButtonSegment(
                        value: PinTarget.destination,
                        label: Text('Pin: Ziel'),
                        icon: Icon(Icons.sports_score),
                      ),
                    ],
                    selected: {c.pin},
                    onSelectionChanged: (selection) => c.update((planner) => planner.pin = selection.single),
                  ),
                ),
              if (c.shape == RouteShape.direction)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final direction in CompassDirection.values)
                        ChoiceChip(
                          label: Text(direction.label),
                          selected: c.direction == direction,
                          onSelected: (_) => c.update((planner) {
                            planner.direction = direction;
                            planner.clearResults();
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
                value: c.kilometers.clamp(c.minKm, c.maxKm),
                min: c.minKm,
                max: c.maxKm,
                divisions: ((c.maxKm - c.minKm) * (c.discipline.isBike ? 1 : 2)).round(),
                label: '${_kmText(c.kilometers)} km',
                onChanged: (value) {
                  c.update((planner) {
                    planner.kilometers = planner.discipline.isBike ? value.roundToDouble() : (value * 2).round() / 2;
                    planner.clearResults();
                  });
                  _distanceField.text = _kmText(c.kilometers);
                },
              ),
              SwitchListTile(
                title: const Text('Höhenmeter vorgeben'),
                subtitle: Text(c.wantsElevation ? 'ca. $c.elevation hm Anstieg' : 'flach oder hügelig – egal'),
                value: c.wantsElevation,
                onChanged: (value) => c.update((planner) {
                  planner.wantsElevation = value;
                  planner.clearResults();
                }),
              ),
              if (c.wantsElevation)
                Slider(
                  value: c.elevation.toDouble().clamp(0, c.maxElevation.toDouble()),
                  max: c.maxElevation.toDouble(),
                  divisions: c.maxElevation ~/ (c.discipline.isBike ? 50 : 10),
                  label: '$c.elevation hm',
                  onChanged: (value) => c.update((planner) {
                    planner.elevation = value.round();
                    planner.clearResults();
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 16, LiquidSpacing.page, 4),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: c.planning ? null : () => unawaited(_plan()),
              icon: c.planning
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.route),
              label: Text(c.planning ? (c.progress ?? 'Wird berechnet …') : 'Routen vorschlagen'),
            ),
          ),
          if (c.problem case final problem?)
            Padding(
              padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 12, LiquidSpacing.page, 0),
              child: LiquidCard(
                tint: AppColors.of(context).caution,
                child: Row(
                  spacing: 12,
                  children: [
                    Icon(Icons.info_outline, color: AppColors.of(context).caution),
                    Expanded(child: Text(problem)),
                  ],
                ),
              ),
            ),
          if (c.notice case final notice?)
            Padding(
              padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 12, LiquidSpacing.page, 0),
              child: LiquidCard(
                tint: theme.colorScheme.primary,
                child: Row(
                  spacing: 12,
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    Expanded(child: Text(notice)),
                  ],
                ),
              ),
            ),
          LiquidSwitcher(
            child: current == null
                ? const SizedBox.shrink(key: ValueKey('leer'))
                : _Results(
                    key: ValueKey(c.fitGeneration),
                    routes: c.routes,
                    selected: c.selected,
                    saved: c.saved,
                    onSelect: (index) {
                      c.select(index);
                      PlannerMap.fit(_map, Geo.thin(c.routes[index].points, 200));
                    },
                    onReroll: c.planning ? null : () => unawaited(_plan(reroll: true)),
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
    final c = ref.read(routePlannerControllerProvider);
    if (c.start == null) return 'Start: Adresse eingeben, Standort nutzen oder Karte lange drücken.';
    if (c.editingPins) {
      return c.pin == PinTarget.destination
          ? 'Tippe auf die Karte für das neue Ziel.'
          : 'Tippe auf die Karte für den neuen Start.';
    }
    if (c.pinsLocked) return 'Antippen: Vollbild · lange drücken verschiebt den Start.';
    if (c.shape == RouteShape.toDestination && (c.destination == null || c.pin == PinTarget.destination)) {
      return 'Ziel: Adresse eingeben oder Karte lange drücken.';
    }
    return 'Antippen: Vollbild · lange drücken verschiebt den Start.';
  }

  void _setDistanceText(String text) {
    final value = parseNumber(text);
    final c = ref.read(routePlannerControllerProvider);
    c.update((planner) {
      if (value != null) planner.kilometers = value.clamp(planner.minKm, planner.maxKm).toDouble();
      planner.clearResults();
    });
    _distanceField.text = _kmText(c.kilometers);
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
          style: AppText.footnote(context).copyWith(fontWeight: FontWeight.w500),
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
                      style: AppText.footnote(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    onPressed: () => unawaited(showSendToWatchSheet(context, route)),
                    icon: const Icon(Icons.watch_outlined),
                    label: const Text('An Uhr'),
                  ),
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
                        style: AppText.footnote(context).copyWith(fontWeight: FontWeight.w600),
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

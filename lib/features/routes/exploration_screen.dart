import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import 'my_location.dart';
import 'route_parts.dart';

/// Persönliche Karte: Heatmap der besuchten Kacheln, eroberte Kacheln und Gebiete aus geschlossenen Runden.
class ExplorationScreen extends ConsumerStatefulWidget {
  const ExplorationScreen({super.key});

  @override
  ConsumerState<ExplorationScreen> createState() => _ExplorationScreenState();
}

class _ExplorationScreenState extends ConsumerState<ExplorationScreen> {
  final _map = MapController();
  bool _importing = false;
  bool _fitted = false;
  GeoPoint? _myLocation;

  /// Höchstzahl gezeichneter Kacheln (Leistung auf älteren Geräten).
  static const maxDrawnTiles = 6000;

  @override
  void initState() {
    super.initState();
    // Beim Öffnen neue, schon geladene Aktivitäten still übernehmen.
    unawaited(_import(silent: true));
  }

  Future<void> _import({bool silent = false}) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final activities = await ref.read(activityRepositoryProvider).all();
      final result = await ref.read(explorationImportProvider).importCached(activities);
      if (!mounted || silent && result.tracks == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.tracks == 0
                ? 'Keine neuen Strecken. Aktivitäten zählen, sobald ihr Verlauf einmal geladen wurde (Aktivität öffnen).'
                : '${result.tracks} Strecken übernommen: ${result.newTiles} neue Kacheln'
                      '${result.territories > 0 ? ', ${result.territories} neue Gebiete' : ''}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Karte zurücksetzen?'),
        content: const Text('Alle Kacheln und Gebiete dieses Benutzers werden gelöscht. Aktivitäten bleiben erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(routeStoreProvider).resetExploration();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(routeStoreProvider);
    final state = store.exploration;
    final visits = state.visits.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final drawn = visits.take(maxDrawnTiles).toList();
    final maxCount = drawn.isEmpty ? 1 : drawn.first.value;
    final heat = Theme.of(context).colorScheme.primary;
    const captured = Color(0xFF30C26B);
    final points = [
      for (final territory in state.territories) ...territory.polygon,
      if (state.territories.isEmpty)
        for (final entry in drawn.take(400)) ExplorationTile.fromKey(entry.key).center,
    ];
    if (!_fitted && points.isNotEmpty) {
      _fitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => PlannerMap.fit(_map, points));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Karte'),
        actions: [
          IconButton(
            tooltip: 'Aktivitäten übernehmen',
            onPressed: _importing ? null : () => unawaited(_import()),
            icon: _importing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 32),
        children: [
          if (store.hasForeignExploration)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LiquidCard(
                tint: Colors.orange,
                child: Text('Die Karte in diesem Speicher gehört einem anderen Benutzer und wird nicht angezeigt.'),
              ),
            ),
          SizedBox(
            height: 380,
            child: ClipRRect(
              borderRadius: LiquidRadii.cardAll,
              child: Semantics(
                label: 'Karte der erkundeten Kacheln und eroberten Gebiete',
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: points.isEmpty ? PlannerMap.fallbackCenter : latLng(points.first),
                    initialZoom: points.isEmpty ? 5.5 : 12,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  ),
                  children: [
                    ...osmBaseLayers(),
                    PolygonLayer(
                      polygons: [
                        for (final entry in drawn)
                          Polygon(
                            points: [for (final corner in ExplorationTile.fromKey(entry.key).corners) latLng(corner)],
                            color: (state.captured.contains(entry.key) ? captured : heat).withValues(
                              alpha: 0.18 + 0.42 * math.min(1, entry.value / math.max(1, math.min(maxCount, 8))),
                            ),
                          ),
                        for (final key in state.captured)
                          if (!state.visits.containsKey(key))
                            Polygon(
                              points: [for (final corner in ExplorationTile.fromKey(key).corners) latLng(corner)],
                              color: captured.withValues(alpha: 0.28),
                            ),
                        for (final territory in state.territories)
                          Polygon(
                            points: [for (final point in territory.polygon) latLng(point)],
                            color: Colors.transparent,
                            borderColor: captured,
                            borderStrokeWidth: 2,
                          ),
                      ],
                    ),
                    MyLocationLayer(point: _myLocation),
                    osmAttribution(),
                    Positioned(
                      right: 8,
                      bottom: 30,
                      child: LocateMeButton(map: _map, onLocated: (point) => setState(() => _myLocation = point)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: LiquidSpacing.l),
          LiquidCard(
            child: Wrap(
              spacing: LiquidSpacing.xl,
              runSpacing: LiquidSpacing.m,
              children: [
                LiquidMetric(value: '${state.tileCount}', label: 'Kacheln erkundet'),
                LiquidMetric(
                  value: GermanFormat.decimal(state.capturedSquareKilometers),
                  unit: 'km²',
                  label: 'erobert',
                ),
                LiquidMetric(value: '${state.territories.length}', label: 'Gebiete'),
                LiquidMetric(value: '${state.largestCluster}', label: 'größter Cluster'),
              ],
            ),
          ),
          if (state.territories.isNotEmpty)
            FormSection(
              header: 'Gebiete',
              children: [
                for (final territory in state.territories.reversed.take(30))
                  ListTile(
                    leading: const Icon(Icons.flag_circle, color: captured),
                    title: Text(territory.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${GermanFormat.date(territory.day)} · ${GermanFormat.decimal(territory.areaSquareMeters / 1e6)} km²',
                    ),
                    onTap: () => PlannerMap.fit(_map, territory.polygon),
                  ),
              ],
            ),
          FormSection(
            footer:
                'Eine Kachel entspricht einer OSM-Kachel der Zoomstufe ${ExplorationTile.zoom} (etwa 190 × 190 m). Eine '
                'Runde gilt als geschlossen, wenn Start und Ziel höchstens ${ExplorationRules.closeDistance.round()} m '
                'auseinander liegen und sie mindestens 2 ha umschließt. Gezählt werden Läufe, Radfahrten, Wanderungen '
                'und Spaziergänge mit GPS, deren Verlauf schon einmal geladen wurde.',
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Karte zurücksetzen'),
                onTap: () => unawaited(_reset()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import 'exploration_screen.dart';
import 'route_detail_screen.dart';
import 'route_parts.dart';
import 'route_planner_screen.dart';

/// Routen: neue Route planen, gespeicherte Routen und – optional – Gebiete & Erkundung.
class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(routeStoreProvider);
    final routes = store.routes;
    final exploration = store.exploration;
    final enabled = store.settings.explorationEnabled;
    void open(Widget screen) => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
    return Scaffold(
      appBar: AppBar(title: const Text('Routen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 0),
            child: LiquidCard(
              onTap: () => open(const RoutePlannerScreen()),
              semanticLabel: 'Neue Route planen',
              child: Row(
                spacing: 14,
                children: [
                  const SportIcon(
                    symbol: 'point.topleft.down.to.point.bottomright.curvepath',
                    color: Colors.teal,
                    size: 44,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Neue Route planen', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          'Laufen, Rennrad oder Gravel – Rundweg, zum Ziel oder in eine Richtung',
                          style: LiquidText.label(context),
                        ),
                      ],
                    ),
                  ),
                  const DisclosureChevron(),
                ],
              ),
            ),
          ),
          if (store.hasForeignRoutes)
            const FormSection(
              footer:
                  'Die gespeicherten Routen in diesem Speicher gehören einem anderen Benutzer und werden hier nicht '
                  'angezeigt.',
              children: [],
            ),
          FormSection(
            header: 'Gespeichert',
            footer: routes.isEmpty ? 'Gespeicherte und in Einheiten übernommene Routen erscheinen hier.' : null,
            children: [
              for (final route in routes)
                ListTile(
                  leading: SportIcon(symbol: route.discipline.symbol, color: variantColor(route.variant), size: 32),
                  title: Text(route.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      RouteFormat.distance(route.stats.distanceMeters),
                      if (route.stats.hasElevation) '↑ ${RouteFormat.elevation(route.stats.ascentMeters)}',
                      ?plannedLabel(route),
                    ].join(' · '),
                  ),
                  trailing: const DisclosureChevron(),
                  onTap: () => open(RouteDetailScreen(routeID: route.id)),
                ),
            ],
          ),
          FormSection(
            header: 'Gebiete & Erkundung',
            footer:
                'Optional: Geschlossene Runden erobern die umschlossene Fläche, alle Strecken füllen deine '
                'Erkundungskarte. Die Daten bleiben bei deinem Benutzer.',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.flag_circle_outlined),
                title: const Text('Gebiete anzeigen'),
                value: enabled,
                onChanged: (value) =>
                    unawaited(store.updateSettings((settings) => settings.explorationEnabled = value)),
              ),
              if (enabled)
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Meine Karte'),
                  subtitle: Text(
                    '${exploration.tileCount} Kacheln · ${exploration.territories.length} Gebiete · '
                    '${GermanFormat.decimal(exploration.capturedSquareKilometers)} km²',
                  ),
                  trailing: const DisclosureChevron(),
                  onTap: () => open(const ExplorationScreen()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Unter „Heute“: Routen, die für heute in eine Einheit übernommen wurden.
class PlannedRoutesTodaySection extends ConsumerWidget {
  const PlannedRoutesTodaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routeStoreProvider).plannedOn(CalendarDay.today());
    if (routes.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: 'Route für heute',
      children: [
        for (final route in routes)
          ListTile(
            leading: SportIcon(symbol: route.discipline.symbol, color: variantColor(route.variant), size: 32),
            title: Text(route.slotTitle ?? route.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                RouteFormat.distance(route.stats.distanceMeters),
                if (route.stats.hasElevation) '↑ ${RouteFormat.elevation(route.stats.ascentMeters)}',
                'ca. ${RouteFormat.duration(route.duration)}',
              ].join(' · '),
            ),
            trailing: const DisclosureChevron(),
            onTap: () => unawaited(
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id))),
            ),
          ),
      ],
    );
  }
}

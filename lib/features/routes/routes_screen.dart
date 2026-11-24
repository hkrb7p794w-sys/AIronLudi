import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'address_field.dart';
import 'exploration_screen.dart';
import 'route_detail_screen.dart';
import 'route_parts.dart';
import 'route_planner_controller.dart';
import 'route_planner_screen.dart';

/// Routen: neue Route planen, offene Routen, Archiv der abgeschlossenen und – optional – Gebiete & Erkundung.
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  @override
  void initState() {
    super.initState();
    // Gelaufene bzw. gefahrene Routen ins Archiv übernehmen (Aktivität am geplanten Tag).
    unawaited(_completeFromActivities());
  }

  Future<void> _completeFromActivities() async {
    try {
      final activities = await ref.read(activityRepositoryProvider).all();
      if (!mounted) return;
      final count = await ref.read(routeStoreProvider).completeFromActivities(activities);
      if (count > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 1 ? 'Eine Route ist erledigt – im Archiv.' : '$count Routen sind erledigt – im Archiv.',
            ),
          ),
        );
      }
    } on Object {
      // Ohne Aktivitäten bleibt alles offen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(routeStoreProvider);
    final routes = store.openRoutes;
    final archive = store.archive;
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
                          'Laufen, Rennrad, Gravel oder Spazieren – Rundweg, zum Ziel oder in eine Richtung',
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
            header: 'Geplant und gespeichert',
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
            header: 'Archiv',
            footer: archive.isEmpty
                ? 'Abgeschlossene Routen landen hier – automatisch, sobald am geplanten Tag eine passende Aktivität '
                      'vorliegt, oder über „Als erledigt markieren“.'
                : null,
            children: [
              for (final route in archive.take(5)) ArchivedRouteTile(route: route),
              if (archive.length > 5)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Alle ${archive.length} anzeigen'),
                  trailing: const DisclosureChevron(),
                  onTap: () => open(const RouteArchiveScreen()),
                ),
            ],
          ),
          FormSection(
            header: 'Vorlagen',
            footer: store.templates.isEmpty
                ? 'Im Planer speichert das Lesezeichen oben die Vorgaben samt Start als Vorlage – z. B. „Gassi 3 km ab '
                      'Zuhause“. Antippen plant sie dann mit einem Tipp.'
                : 'Antippen plant die Vorlage sofort.',
            children: [
              for (final template in store.templates)
                ListTile(
                  leading: SportIcon(symbol: template.discipline.symbol, color: Colors.teal, size: 32),
                  title: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [template.summary, ?template.startLabel].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Vorlage bearbeiten',
                    onSelected: (_) => unawaited(store.deleteTemplate(template.id)),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Löschen'))],
                  ),
                  onTap: () {
                    final planner = ref.read(routePlannerControllerProvider)..applyTemplate(template);
                    open(const RoutePlannerScreen());
                    unawaited(planner.plan());
                  },
                ),
            ],
          ),
          FormSection(
            header: 'Favorisierte Orte',
            footer: store.favorites.isEmpty
                ? 'Tippe im Planer auf den Stern neben Start oder Ziel, um einen Ort zu merken (z. B. Zuhause, '
                      'Hundewiese). Favoriten erscheinen beim Antippen der Adresszeile.'
                : 'Favoriten erscheinen beim Antippen der Adresszeile für Start und Ziel.',
            children: [
              for (final favorite in store.favorites)
                ListTile(
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text(favorite.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    favorite.address ??
                        '${favorite.point.latitude.toStringAsFixed(5)}, ${favorite.point.longitude.toStringAsFixed(5)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Favorit bearbeiten',
                    onSelected: (action) async {
                      if (action == 'delete') {
                        await store.deleteFavorite(favorite.id);
                        return;
                      }
                      final name = await askFavoriteName(context, initial: favorite.name);
                      if (name != null) await store.renameFavorite(favorite.id, name);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                      PopupMenuItem(value: 'delete', child: Text('Löschen')),
                    ],
                  ),
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

/// Eintrag im Archiv: Name, Distanz, wann abgeschlossen.
class ArchivedRouteTile extends StatelessWidget {
  const ArchivedRouteTile({super.key, required this.route});

  final PlannedRoute route;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Stack(
      clipBehavior: Clip.none,
      children: [
        SportIcon(symbol: route.discipline.symbol, color: variantColor(route.variant), size: 32),
        Positioned(right: -4, bottom: -4, child: Icon(Icons.check_circle, size: 16, color: AppColors.of(context).good)),
      ],
    ),
    title: Text(route.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        RouteFormat.distance(route.stats.distanceMeters),
        'erledigt am ${GermanFormat.date(CalendarDay.fromDate(route.completedAt!.toLocal()))}',
      ].join(' · '),
    ),
    trailing: const DisclosureChevron(),
    onTap: () => unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id))),
    ),
  );
}

/// Alle abgeschlossenen Routen.
class RouteArchiveScreen extends ConsumerWidget {
  const RouteArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(routeStoreProvider).archive;
    return Scaffold(
      appBar: AppBar(title: const Text('Archiv')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: '${archive.length} abgeschlossene Routen',
            children: [for (final route in archive) ArchivedRouteTile(route: route)],
          ),
        ],
      ),
    );
  }
}

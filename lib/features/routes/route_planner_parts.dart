part of 'route_planner_screen.dart';

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

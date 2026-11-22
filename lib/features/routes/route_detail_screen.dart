import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../endurance/endurance_controller.dart';
import 'route_parts.dart';

/// Gespeicherte Route: Karte, Kennzahlen, Höhenprofil; übernehmen in eine Einheit, exportieren, umbenennen, löschen.
class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.routeID});

  final String routeID;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  final _map = MapController();

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(routeStoreProvider);
    final route = store.route(widget.routeID);
    if (route == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Diese Route gibt es nicht mehr.')),
      );
    }
    final planned = plannedLabel(route);
    return Scaffold(
      appBar: AppBar(
        title: Text(route.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Mehr',
            onSelected: (action) => switch (action) {
              'rename' => _rename(route),
              'delete' => _delete(route),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
              PopupMenuItem(value: 'delete', child: Text('Löschen')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 32),
        children: [
          PlannerMap(
            controller: _map,
            start: route.points.first,
            destination: route.isLoop ? null : route.points.last,
            routes: [route],
            selected: route,
            onTap: (_) => unawaited(
              FullscreenRouteMap.open(
                context,
                start: route.points.first,
                destination: route.isLoop ? null : route.points.last,
                routes: [route],
                title: route.name,
              ),
            ),
            routingSource: route.engine.isEmpty ? null : route.engine,
          ),
          const SizedBox(height: LiquidSpacing.l),
          LiquidCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: LiquidSpacing.m,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    AppChip(text: route.discipline.label, color: variantColor(route.variant)),
                    AppChip(
                      text: route.request.shape == RouteShape.drawn ? RouteShape.drawn.label : route.variant.label,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    if (route.request.preferences.isNotEmpty)
                      AppChip(
                        text: RoutePreference.describe(route.request.preferences),
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                  ],
                ),
                RouteStatsRow(route: route),
                ElevationProfileChart(route: route),
              ],
            ),
          ),
          FormSection(
            header: 'Training',
            footer: planned == null
                ? 'Übernimm die Route in eine Einheit des Ausdauerplans oder lege einen Tag fest – sie erscheint dann '
                      'unter „Heute“.'
                : null,
            children: [
              ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(planned ?? 'In Einheit übernehmen'),
                subtitle: planned == null ? null : const Text('Antippen zum Ändern'),
                trailing: const DisclosureChevron(),
                onTap: () => unawaited(assignRouteToSession(context, ref, route)),
              ),
              if (route.isCompleted)
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(
                    'Erledigt am ${GermanFormat.date(CalendarDay.fromDate(route.completedAt!.toLocal()))}'
                    '${route.activityID == null ? '' : ' (Aktivität erkannt)'}',
                  ),
                  subtitle: const Text('Antippen holt die Route zurück in die Planung.'),
                  onTap: () => unawaited(ref.read(routeStoreProvider).setCompleted(route, completed: false)),
                )
              else
                ListTile(
                  leading: const Icon(Icons.task_alt),
                  title: const Text('Als erledigt markieren'),
                  subtitle: const Text('Die Route wandert ins Archiv.'),
                  onTap: () => unawaited(ref.read(routeStoreProvider).setCompleted(route, completed: true)),
                ),
            ],
          ),
          FormSection(
            header: 'Export',
            footer: 'GPX für Uhren, Radcomputer und Karten-Apps; FIT-Kurs für Garmin (z. B. über Garmin Connect).',
            children: [
              Builder(
                builder: (context) => ListTile(
                  leading: const Icon(Icons.watch_outlined),
                  title: const Text('An Uhr senden'),
                  subtitle: const Text('Garmin, Apple Watch, Coros, Suunto, Polar, Wahoo'),
                  trailing: const DisclosureChevron(),
                  onTap: () => unawaited(showSendToWatchSheet(context, route)),
                ),
              ),
              Builder(
                builder: (context) => ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Als GPX teilen'),
                  onTap: () => unawaited(shareRoute(context, route, fit: false)),
                ),
              ),
              Builder(
                builder: (context) => ListTile(
                  leading: const Icon(Icons.watch),
                  title: const Text('Als FIT-Kurs teilen'),
                  onTap: () => unawaited(shareRoute(context, route, fit: true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(PlannedRoute route) async {
    final controller = TextEditingController(text: route.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Route umbenennen'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Sichern')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    route.name = name;
    await ref.read(routeStoreProvider).save(route);
  }

  Future<void> _delete(PlannedRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Route löschen?'),
        content: Text('„${route.name}“ wird entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(routeStoreProvider).delete(route.id);
    if (mounted) Navigator.of(context).pop();
  }
}

/// Wählt eine Einheit (Ausdauerplan, passende Sportart, nächste 14 Tage) oder einen Tag und speichert die Route
/// mit dieser Zuordnung. Ungespeicherte Vorschläge werden dabei gespeichert.
Future<bool> assignRouteToSession(BuildContext context, WidgetRef ref, PlannedRoute route) async {
  final plan = ref.read(enduranceControllerProvider).plan;
  // Spaziergänge haben keine Einheiten im Ausdauerplan: nur Tag wählen.
  final sport = switch (route.discipline) {
    RouteDiscipline.run => EnduranceSport.run,
    RouteDiscipline.roadBike || RouteDiscipline.gravel => EnduranceSport.bike,
    RouteDiscipline.walk => null,
  };
  final today = CalendarDay.today();
  final slots = [
    if (plan != null)
      for (var offset = 0; offset < 14; offset++)
        for (final slot in plan.slotsOn(today.adding(offset)))
          if (sport != null && !slot.current.isRest && slot.current.sport == sport) slot,
  ];
  final choice = await showModalBottomSheet<_Assignment>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('In Einheit übernehmen', style: Theme.of(context).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Heute'),
              onTap: () => Navigator.pop(context, _Assignment(day: today)),
            ),
            for (final slot in slots)
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(slot.current.title),
                subtitle: Text(
                  '${slot.day == today ? 'Heute' : GermanFormat.date(slot.day)} · ${slot.current.minutes} min',
                ),
                onTap: () =>
                    Navigator.pop(context, _Assignment(day: slot.day, slotID: slot.id, slotTitle: slot.current.title)),
              ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Anderen Tag wählen …'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: today.referenceDate.toLocal(),
                  lastDate: today.adding(365).referenceDate.toLocal(),
                  initialDate: today.referenceDate.toLocal(),
                  locale: const Locale('de', 'DE'),
                );
                if (picked != null && context.mounted) {
                  Navigator.pop(context, _Assignment(day: CalendarDay.fromDate(picked)));
                }
              },
            ),
            if (route.plannedDay != null)
              ListTile(
                leading: const Icon(Icons.event_busy),
                title: const Text('Zuordnung entfernen'),
                onTap: () => Navigator.pop(context, const _Assignment(day: null)),
              ),
            if (plan == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text('Mit einem Ausdauerplan erscheinen hier auch die kommenden Einheiten.'),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return false;
  route
    ..plannedDay = choice.day
    ..slotID = choice.slotID
    ..slotTitle = choice.slotTitle;
  await ref.read(routeStoreProvider).save(route);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(choice.day == null ? 'Zuordnung entfernt.' : '${plannedLabel(route)} – gespeichert.')),
    );
  }
  return true;
}

final class _Assignment {
  const _Assignment({required this.day, this.slotID, this.slotTitle});

  final CalendarDay? day;
  final String? slotID;
  final String? slotTitle;
}

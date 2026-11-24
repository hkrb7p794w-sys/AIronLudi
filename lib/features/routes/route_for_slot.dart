import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import 'route_detail_screen.dart';
import 'route_parts.dart';
import 'route_planner_controller.dart';
import 'route_planner_screen.dart';

/// In einer Einheit des Ausdauerplans: „Route dazu planen“ (Disziplin und Distanz aus der Einheit vorbelegt, Vorschläge
/// werden der Einheit zugeordnet) und die schon zugeordneten Routen.
class RouteForSlotSection extends StatelessWidget {
  const RouteForSlotSection({super.key, required this.slot, this.runThresholdPace});

  final PlanSlot slot;
  final int? runThresholdPace;

  @override
  Widget build(BuildContext context) {
    final workout = slot.current;
    if (workout.isRest) return const SizedBox.shrink();
    return RouteForUnitSection(
      unitID: slot.id,
      day: slot.day,
      title: workout.title,
      isBike: workout.sport == EnduranceSport.bike,
      isRun: workout.sport == EnduranceSport.run,
      minutes: workout.minutes,
      meters: workout.meters,
      runThresholdPace: runThresholdPace,
    );
  }
}

/// Einheit aus dem Wochenplan (Roast B-04): gleiche Route-Funktion wie im Ausdauerplan, die Kennung verbindet
/// Tag, Sportart und Intensität.
class RouteForSessionSection extends StatelessWidget {
  const RouteForSessionSection({super.key, required this.slot, required this.day, this.minutes});

  final SessionSlot slot;
  final CalendarDay day;
  final int? minutes;

  static String unitID(SessionSlot slot, CalendarDay day) =>
      'woche:${day.iso}:${slot.sport.rawValue}:${slot.intensity.rawValue}';

  @override
  Widget build(BuildContext context) {
    final isRun = slot.sport == TrainingSport.run;
    final isBike = slot.sport == TrainingSport.bike;
    if (!isRun && !isBike) return const SizedBox.shrink();
    return RouteForUnitSection(
      unitID: unitID(slot, day),
      day: day,
      title: slot.title,
      isBike: isBike,
      isRun: isRun,
      minutes: minutes ?? SessionMatcher.defaultMinutes(slot),
    );
  }
}

/// Gemeinsamer Teil: Vorschlag aus Sportart und Dauer bzw. Strecke, zugeordnete Routen, „Route dazu planen“.
class RouteForUnitSection extends ConsumerWidget {
  const RouteForUnitSection({
    super.key,
    required this.unitID,
    required this.day,
    required this.title,
    required this.isBike,
    required this.isRun,
    required this.minutes,
    this.meters,
    this.runThresholdPace,
  });

  final String unitID;
  final CalendarDay day;
  final String title;
  final bool isBike;
  final bool isRun;
  final int minutes;
  final int? meters;
  final int? runThresholdPace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = RouteForWorkout.suggest(
      isBike: isBike,
      isRun: isRun,
      minutes: minutes,
      meters: meters,
      runThresholdPace: runThresholdPace,
    );
    final store = ref.watch(routeStoreProvider);
    final assigned = [
      for (final route in [...store.openRoutes, ...store.archive])
        if (route.slotID == unitID) route,
    ];
    if (suggestion == null && assigned.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: 'Route',
      footer: suggestion == null
          ? null
          : 'Vorbelegt: ${suggestion.discipline.label}, ${GermanFormat.decimal(suggestion.kilometers)} km '
                '(${meters != null ? 'Strecke der Einheit' : '$minutes min im lockeren Tempo'}). '
                'Gespeicherte Vorschläge gehören dann zu dieser Einheit.',
      children: [
        for (final route in assigned)
          ListTile(
            leading: SportIcon(symbol: route.discipline.symbol, color: variantColor(route.variant), size: 32),
            title: Text(route.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [RouteFormat.distance(route.stats.distanceMeters), if (route.isCompleted) 'erledigt'].join(' · '),
            ),
            trailing: const DisclosureChevron(),
            onTap: () => unawaited(
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id))),
            ),
          ),
        if (suggestion case final suggestion?)
          ListTile(
            leading: const Icon(Icons.route),
            title: const Text('Route dazu planen'),
            trailing: const DisclosureChevron(),
            onTap: () {
              ref
                  .read(routePlannerControllerProvider)
                  .prepareForSlot(
                    discipline: suggestion.discipline,
                    kilometers: suggestion.kilometers,
                    day: day,
                    slotID: unitID,
                    title: title,
                  );
              unawaited(
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RoutePlannerScreen())),
              );
            },
          ),
      ],
    );
  }
}

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
class RouteForSlotSection extends ConsumerWidget {
  const RouteForSlotSection({super.key, required this.slot, this.runThresholdPace});

  final PlanSlot slot;
  final int? runThresholdPace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = slot.current;
    final suggestion = workout.isRest
        ? null
        : RouteForWorkout.suggest(
            isBike: workout.sport == EnduranceSport.bike,
            isRun: workout.sport == EnduranceSport.run,
            minutes: workout.minutes,
            meters: workout.meters,
            runThresholdPace: runThresholdPace,
          );
    final store = ref.watch(routeStoreProvider);
    final assigned = [
      for (final route in [...store.openRoutes, ...store.archive])
        if (route.slotID == slot.id) route,
    ];
    if (suggestion == null && assigned.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: 'Route',
      footer: suggestion == null
          ? null
          : 'Vorbelegt: ${suggestion.discipline.label}, ${GermanFormat.decimal(suggestion.kilometers)} km '
                '(${workout.meters != null ? 'Strecke der Einheit' : '${workout.minutes} min im lockeren Tempo'}). '
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
                    day: slot.day,
                    slotID: slot.id,
                    title: workout.title,
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

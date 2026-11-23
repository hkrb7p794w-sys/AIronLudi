import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import 'fuel_plan_screen.dart';

/// In einer Einheit des Ausdauerplans: „Verpflegung planen“ mit Sportart, Dauer, Strecke, Intensität und
/// Körpergewicht aus Einheit und Profil – bzw. der schon gespeicherte Plan der Einheit.
class FuelForSlotSection extends ConsumerWidget {
  const FuelForSlotSection({super.key, required this.slot});

  final PlanSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = slot.current;
    if (workout.isRest) return const SizedBox.shrink();
    final store = ref.watch(fuelStoreProvider);
    final saved = store.planForSlot(slot.id);
    final scenario = saved?.scenario ?? scenarioForSlot(ref, slot);
    final carbs = FuelRules.carbsPerHour(scenario);
    return FormSection(
      header: 'Verpflegung',
      footer: saved == null
          ? 'Übernimmt ${workout.sport.label}, ${workout.minutes} min, ${scenario.isRace ? 'Wettkampf' : scenario.intensity.label} '
                'und ${GermanFormat.decimal(scenario.weightKilograms)} kg.'
          : null,
      children: [
        ListTile(
          leading: const Icon(Icons.local_drink_outlined),
          title: Text(saved == null ? 'Verpflegung planen' : 'Verpflegungsplan'),
          subtitle: Text(
            carbs > 0
                ? 'Unterwegs $carbs g Kohlenhydrate je Stunde'
                : 'Unterwegs keine Kohlenhydrate nötig – Plan für davor und danach',
          ),
          trailing: const DisclosureChevron(),
          onTap: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FuelPlanScreen(
                  scenario: scenario,
                  productIDs: saved?.productIDs ?? store.profile.setup,
                  planID: saved?.id,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Szenario aus der Einheit (ohne gespeicherten Plan).
  static FuelScenario scenarioForSlot(WidgetRef ref, PlanSlot slot) {
    final body = ref.read(fuelBodyProvider);
    return FuelScenario.fromWorkout(
      slot.current,
      weightKilograms: body.weight,
      age: body.age,
      profile: ref.read(fuelStoreProvider).profile,
      day: slot.day,
      slotID: slot.id,
    );
  }
}

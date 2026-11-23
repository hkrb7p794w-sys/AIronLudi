import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import 'fuel_plan_screen.dart';

/// Abschnitt „Verpflegung“ unter einer geplanten Einheit: neuer Plan mit den Werten der Einheit oder der gespeicherte,
/// mit Hinweis, wenn sich die Einheit seitdem geändert hat.
class _FuelSection extends ConsumerWidget {
  const _FuelSection({required this.slotID, required this.fresh, required this.link, required this.summary});

  final String slotID;

  /// Szenario aus der Einheit (ohne gespeicherten Plan).
  final FuelScenario fresh;
  final FuelPlanLink link;

  /// „Laufen, 120 min, Locker“.
  final String summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(fuelStoreProvider);
    final saved = store.planForSlot(slotID);
    final scenario = saved?.scenario ?? fresh;
    final stale = saved != null && !link.matches(saved.scenario);
    final carbs = FuelRules.carbsPerHour(scenario);
    return FormSection(
      header: 'Verpflegung',
      footer: saved == null
          ? 'Übernimmt $summary und ${GermanFormat.decimal(scenario.weightKilograms)} kg.'
          : stale
          ? 'Die ${link.label} hat sich seit dem Speichern geändert – im Plan anpassen.'
          : null,
      children: [
        ListTile(
          leading: Icon(stale ? Icons.update : Icons.local_drink_outlined),
          title: Text(saved == null ? 'Verpflegung planen' : 'Verpflegungsplan'),
          subtitle: Text(
            [
              carbs > 0
                  ? 'Unterwegs $carbs g Kohlenhydrate je Stunde'
                  : 'Unterwegs keine Kohlenhydrate nötig – Plan für davor und danach',
              if (saved?.loggedAt != null) 'im Tagebuch',
            ].join(' · '),
          ),
          trailing: const DisclosureChevron(),
          onTap: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FuelPlanScreen(
                  scenario: scenario,
                  productIDs: saved?.productIDs ?? store.profile.setup,
                  planID: saved?.id,
                  link: link,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// In einer Einheit des Ausdauerplans: Sportart, Dauer, Strecke, Intensität, Tag und Gewicht übernommen.
class FuelForSlotSection extends ConsumerWidget {
  const FuelForSlotSection({super.key, required this.slot});

  final PlanSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = slot.current;
    if (workout.isRest) return const SizedBox.shrink();
    final fresh = scenarioForSlot(ref, slot);
    return _FuelSection(
      slotID: slot.id,
      fresh: fresh,
      summary: '${workout.sport.label}, ${workout.minutes} min, ${fresh.isRace ? 'Wettkampf' : fresh.intensity.label}',
      link: FuelPlanLink(
        label: 'Einheit',
        matches: (scenario) => scenario.matchesWorkout(workout, day: slot.day),
        update: (scenario) => scenario.updatedFromWorkout(workout, day: slot.day),
      ),
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

/// In einer Einheit des Wochenplans (auch Krafttraining). Ohne Tag (Vorlage) gilt der nächste passende Wochentag
/// nicht – der Plan nimmt dann heute.
class FuelForSessionSection extends ConsumerWidget {
  const FuelForSessionSection({super.key, required this.slot, this.day, this.minutes});

  final SessionSlot slot;
  final CalendarDay? day;

  /// Geplante Minuten, falls bekannt (sonst Standarddauer der Einheit).
  final int? minutes;

  /// Kennung für gespeicherte Pläne: Tag und Einheit.
  static String slotID(SessionSlot slot, CalendarDay? day) => 'week:${day?.iso ?? 'any'}:${slot.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ref.watch(fuelBodyProvider);
    final id = slotID(slot, day);
    final fresh = FuelScenario.fromSession(
      slot,
      weightKilograms: body.weight,
      minutes: minutes,
      age: body.age,
      profile: ref.watch(fuelStoreProvider).profile,
      day: day,
      slotID: id,
    );
    if (fresh == null) return const SizedBox.shrink();
    return _FuelSection(
      slotID: id,
      fresh: fresh,
      summary: '${fresh.sport.label}, ${fresh.minutes} min, ${fresh.intensity.label}',
      // Im Wochenplan stehen nur Sportart und Intensität fest; die Dauer stellst du im Plan ein.
      link: FuelPlanLink(
        label: 'Einheit',
        matches: (scenario) => scenario.sport == fresh.sport && scenario.intensity == fresh.intensity,
        update: (scenario) => scenario.copyWith(sport: fresh.sport, intensity: fresh.intensity),
      ),
    );
  }
}

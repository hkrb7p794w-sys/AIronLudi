import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../endurance/endurance_controller.dart';
import 'fuel_parts.dart';
import 'fuel_plan_screen.dart';
import 'fuel_products_screen.dart';
import 'fuel_profile_screen.dart';
import 'fuel_scenario_screen.dart';

/// Neues Szenario mit Gewicht und Profil des Benutzers.
FuelScenario newFuelScenario(WidgetRef ref, {FuelSport sport = FuelSport.run, int minutes = 90}) {
  final body = ref.read(fuelBodyProvider);
  return FuelScenario.withProfile(
    ref.read(fuelStoreProvider).profile,
    sport: sport,
    minutes: minutes,
    weightKilograms: body.weight,
    age: body.age,
    day: CalendarDay.today(),
  );
}

/// Szenario einstellen, danach den Plan zeigen.
Future<void> openNewFuelPlan(BuildContext context, WidgetRef ref) async {
  final store = ref.read(fuelStoreProvider);
  final result = await Navigator.of(context).push<(FuelScenario, List<String>)>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FuelScenarioScreen(scenario: newFuelScenario(ref), productIDs: store.profile.setup),
    ),
  );
  if (result == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FuelPlanScreen(scenario: result.$1, productIDs: result.$2),
    ),
  );
}

/// Einstieg: neuer Plan, gespeicherte Pläne, eigene Produkte, Profil.
class FuelPlannerScreen extends ConsumerWidget {
  const FuelPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(fuelStoreProvider);
    final profile = store.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Fuel Planner')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 4),
            child: LiquidCard(
              onTap: () => unawaited(openNewFuelPlan(context, ref)),
              semanticLabel: 'Neuen Verpflegungsplan erstellen',
              child: Row(
                spacing: 14,
                children: [
                  SportIcon(symbol: 'figure.mixed.cardio', color: Theme.of(context).colorScheme.primary, size: 44),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text('Neuer Plan', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          'Vorher, unterwegs und danach – Kohlenhydrate, Flüssigkeit, Natrium und Koffein.',
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
          if (store.hasForeignData)
            const FormSection(
              children: [
                ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Der gespeicherte Stand gehört einem anderen Benutzer und wird nicht verändert.'),
                ),
              ],
            ),
          FormSection(
            header: 'Gespeicherte Pläne',
            footer: store.plans.isEmpty
                ? 'Öffne den Planer auch direkt aus einer Einheit des Ausdauerplans – Sportart, Dauer und Intensität '
                      'werden übernommen.'
                : null,
            children: [
              if (store.plans.isEmpty) const ListTile(title: Text('Noch keine Pläne')),
              for (final saved in store.plans) _PlanTile(saved: saved),
            ],
          ),
          FormSection(
            header: 'Einstellungen',
            footer: 'Gilt nur für dich; andere Benutzer auf diesem Gerät haben ihr eigenes Profil.',
            children: [
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Meine Produkte und Mischungen'),
                subtitle: Text('${store.ownProducts.length} eigene · ${FuelProducts.all.length} mitgeliefert'),
                trailing: const DisclosureChevron(),
                onTap: () => unawaited(
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FuelProductsScreen())),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Mein Profil'),
                subtitle: Text(
                  [
                    profile.gut.label,
                    profile.sweatRateLitersPerHour == null
                        ? 'Schweiß geschätzt'
                        : '${GermanFormat.decimal(profile.sweatRateLitersPerHour!)} l/h',
                    'Salz ${profile.saltiness.label.split(' ').first.toLowerCase()}',
                  ].join(' · '),
                ),
                trailing: const DisclosureChevron(),
                onTap: () => unawaited(
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FuelProfileScreen())),
                ),
              ),
            ],
          ),
          const FormSection(
            header: 'Grundlage',
            footer:
                'ACSM 2016 (Thomas, Erdman, Burke) und 2007 (Flüssigkeit), ISSN Nutrient Timing 2017 und Koffein 2021, '
                'Jeukendrup 2014 und 2017 (Gut-Training), Burke 2011, Podlogar 2022 und Morton 2026 (bis 120 g/h), '
                'Barnes 2019 (Schweiß), Moore 2015 (Protein), King 2022 (Krafttraining). Richtwerte, keine '
                'medizinische Beratung.',
            children: [],
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.saved});

  final SavedFuelPlan saved;

  /// Gehört der Plan zu einer Einheit des Ausdauerplans, wird sie auf Änderungen geprüft.
  static FuelPlanLink? _link(WidgetRef ref, FuelScenario scenario) {
    final id = scenario.slotID;
    if (id == null) return null;
    final slot = ref.read(enduranceControllerProvider).plan?.slot(id);
    if (slot == null || slot.current.isRest) return null;
    return FuelPlanLink(
      label: 'Einheit',
      matches: (s) => s.matchesWorkout(slot.current, day: slot.day),
      update: (s) => s.updatedFromWorkout(slot.current, day: slot.day),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = saved.scenario;
    final carbs = FuelRules.carbsPerHour(s);
    return Dismissible(
      key: ValueKey(saved.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => unawaited(ref.read(fuelStoreProvider).deletePlan(saved.id)),
      child: ListTile(
        leading: SportIcon(symbol: s.sport.symbol, color: s.sport.color),
        title: Text(s.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (s.day case final day?) GermanFormat.date(day),
            '${s.minutes} min',
            '$carbs g/h',
            if (saved.loggedAt != null) 'im Tagebuch',
          ].join(' · '),
        ),
        trailing: const DisclosureChevron(),
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  FuelPlanScreen(scenario: s, productIDs: saved.productIDs, planID: saved.id, link: _link(ref, s)),
            ),
          ),
        ),
      ),
    );
  }
}

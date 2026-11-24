import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/deep_links.dart';
import '../../app/router.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../nutrition/nutrition_controller.dart';

/// „Ernährung heute“ auf „Heute“ (Roast B-02): übrige Kalorien und Protein mit denselben Tageszielen wie im Reiter
/// Ernährung, dazu „Mahlzeit erfassen“. Lädt die Mahlzeiten von heute selbst und rechnet bei jeder Änderung neu
/// (auch aus dem Fuel Planner oder einem Widget).
class TodayNutritionSection extends ConsumerStatefulWidget {
  const TodayNutritionSection({
    super.key,
    required this.activities,
    required this.hasGarminData,
    required this.recovery,
  });

  final List<GarminActivity> activities;
  final bool hasGarminData;
  final RecoveryLevel? recovery;

  @override
  ConsumerState<TodayNutritionSection> createState() => _TodayNutritionSectionState();
}

class _TodayNutritionSectionState extends ConsumerState<TodayNutritionSection> {
  List<StoredMeal> _meals = const [];
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _changes = ref.read(mealDataChangesProvider).listen((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final meals = await ref.read(mealRepositoryProvider).day(CalendarDay.today());
    if (mounted) setState(() => _meals = meals);
  }

  /// Wie die Schnellaktion „Mahlzeit erfassen“: Reiter Ernährung, dort öffnet sich das Erfassen.
  void _logMeal() {
    ref.read(pendingRouteProvider.notifier).open(const PendingRoute(AppRoute.logMeal));
    ref.read(routerProvider).go(tabPath(AppRoute.logMeal.tab));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final today = CalendarDay.today();
    final targets = NutritionController.targetsFor(
      today,
      activities: widget.activities,
      settings: settings,
      profile: ref.read(appModelProvider).sync.profile,
      hasGarminData: widget.hasGarminData,
      recovery: widget.recovery,
    );
    final intake = FoodAggregation.of([
      for (final meal in _meals)
        if (meal.day == today) ...meal.items,
    ]);
    final kcal = NutritionBudget.line(Nutrient.kcal, targets: targets.values, totals: intake.totals, intake: intake);
    final protein = NutritionBudget.line(
      Nutrient.protein,
      targets: targets.values,
      totals: intake.totals,
      intake: intake,
    );
    final theme = Theme.of(context);
    final eaten = _meals.where((meal) => !meal.isWater).length;
    return FormSection(
      header: 'Ernährung heute · ${targets.dayType.label}',
      children: [
        if (kcal != null)
          ListTile(
            title: Text(
              kcal.remaining >= 0
                  ? '${GermanFormat.number(kcal.remaining.roundToDouble())} kcal übrig'
                  : '${GermanFormat.number(-kcal.remaining.roundToDouble())} kcal drüber',
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                const SizedBox(height: 2),
                LiquidProgressBar(
                  value: kcal.progress,
                  semanticsLabel: 'Kalorien: ${kcal.progress >= 1 ? 'erreicht' : '${(kcal.progress * 100).round()} %'}',
                ),
                Text(
                  [
                    if (protein != null) 'Protein ${NutritionBudget.remainingText(protein)}',
                    eaten == 0 ? 'noch nichts erfasst' : '$eaten ${eaten == 1 ? 'Mahlzeit' : 'Mahlzeiten'}',
                  ].join(' · '),
                ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('Mahlzeit erfassen'),
          textColor: theme.colorScheme.primary,
          iconColor: theme.colorScheme.primary,
          onTap: _logMeal,
        ),
      ],
    );
  }
}

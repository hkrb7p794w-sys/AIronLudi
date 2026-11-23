import 'package:coach_core/coach_core.dart';

import '../../data/repositories/meal_repository.dart';

/// Ergebnis einer Übernahme: neu angelegt und dabei ersetzt (frühere Einträge desselben Plans).
typedef FuelDiaryResult = ({List<StoredMeal> saved, List<StoredMeal> removed});

/// Uhrzeit je Phase (Spezifikation 7): Startzeit des Plans, sonst jetzt (heute) bzw. 10 Uhr (anderer Tag); immer
/// innerhalb des Tages des Plans.
Map<FuelPhase, DateTime> fuelDiaryTimes(FuelPlan plan, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final today = CalendarDay.fromDate(at);
  final day = plan.scenario.day ?? today;
  final start = plan.scenario.startMinuteOfDay ?? (day == today ? at.hour * 60 + at.minute : 10 * 60);
  final dayStart = DateTime(day.year, day.month, day.day);
  return {
    for (final entry in FuelDiary.entries(plan))
      entry.phase: dayStart.add(Duration(minutes: (start + entry.minute).clamp(0, 24 * 60 - 1))),
  };
}

/// Schon eingetragene Mahlzeiten, die eine Phase doppelt zählen würden (gleicher Tag, Zeitfenster und Energie wie
/// beim Ersetzen von Platzhaltern). Einträge dieses Plans zählen nicht – sie werden beim Übernehmen ersetzt.
Map<FuelPhase, StoredMeal> fuelDiaryConflicts(
  FuelPlan plan,
  List<StoredMeal> dayMeals, {
  String? planID,
  DateTime? now,
}) {
  final times = fuelDiaryTimes(plan, now: now);
  final result = <FuelPhase, StoredMeal>{};
  for (final entry in FuelDiary.entries(plan)) {
    final at = times[entry.phase]!;
    final kilocalories = entry.totals[Nutrient.kcal] ?? 0;
    for (final meal in dayMeals) {
      if (meal.isWater) continue;
      final marker = FuelDiary.marker(meal.hint);
      if (marker != null && marker.planID == planID) continue;
      if (FuelDiary.isPlaceholder(hint: meal.hint, items: meal.items)) continue;
      final mealKilocalories = NutritionSummary.totals(meal.items)[Nutrient.kcal] ?? 0;
      if (FuelDiary.replaces(
        placeholderAt: at,
        placeholderKilocalories: kilocalories,
        mealAt: meal.createdAt,
        mealKilocalories: mealKilocalories,
      )) {
        result[entry.phase] = meal;
        break;
      }
    }
  }
  return result;
}

/// Übernimmt Phasen eines Plans ins Ernährungstagebuch: je Phase eine Mahlzeit „Snack“ auf dem Tag des Plans zur
/// Uhrzeit der Phase, mit Markierung im Hinweis. Frühere Einträge desselben Plans werden ersetzt – außer vorher/danach,
/// wenn sie schon in echte Lebensmittel geändert wurden (dann tragen sie keine Markierung mehr).
Future<FuelDiaryResult> writeFuelPlanToDiary(
  MealRepository meals,
  FuelPlan plan, {
  required String planID,
  required Set<FuelPhase> phases,
  List<String> previousMealIDs = const [],
  DateTime? now,
}) async {
  final times = fuelDiaryTimes(plan, now: now);
  final day = plan.scenario.day ?? CalendarDay.fromDate(now ?? DateTime.now());
  final candidates = {
    for (final meal in [...await meals.byIDs(previousMealIDs), ...await meals.day(day)]) meal.id: meal,
  };
  final removed = <StoredMeal>[];
  for (final meal in candidates.values) {
    final marker = FuelDiary.marker(meal.hint);
    if (marker == null || marker.planID != planID) continue;
    await meals.delete(meal.id);
    removed.add(meal);
  }
  final saved = <StoredMeal>[];
  for (final entry in FuelDiary.entries(plan, phases: phases)) {
    final meal = StoredMeal(
      day: day,
      createdAt: times[entry.phase]!,
      category: MealCategory.snack,
      title: '${entry.title} · ${plan.scenario.displayTitle}',
      hint: FuelDiary.hint(planID, entry.phase),
      items: entry.items,
    );
    await meals.save(meal);
    saved.add(meal);
  }
  return (saved: saved, removed: removed);
}

/// „Rückgängig“: neue Einträge entfernen, ersetzte wiederherstellen.
Future<void> undoFuelDiary(MealRepository meals, FuelDiaryResult result) async {
  for (final meal in result.saved) {
    await meals.delete(meal.id);
  }
  for (final meal in result.removed) {
    await meals.save(meal);
  }
}

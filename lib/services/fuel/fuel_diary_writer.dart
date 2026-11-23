import 'package:coach_core/coach_core.dart';

import '../../data/repositories/meal_repository.dart';

/// Übernimmt Phasen eines Plans ins Ernährungstagebuch (Spezifikation 7): je Phase eine Mahlzeit „Snack“ auf dem Tag
/// des Plans, zur Uhrzeit der Phase (Start bekannt) bzw. ab jetzt (heute) oder ab 10 Uhr (anderer Tag). Gibt die
/// gespeicherten Mahlzeiten zurück (für „Rückgängig“).
Future<List<StoredMeal>> writeFuelPlanToDiary(
  MealRepository meals,
  FuelPlan plan, {
  required Set<FuelPhase> phases,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final today = CalendarDay.fromDate(at);
  final day = plan.scenario.day ?? today;
  final start = plan.scenario.startMinuteOfDay ?? (day == today ? at.hour * 60 + at.minute : 10 * 60);
  final dayStart = DateTime(day.year, day.month, day.day);
  final saved = <StoredMeal>[];
  for (final entry in FuelDiary.entries(plan, phases: phases)) {
    // Innerhalb des Tages bleiben (eine Mahlzeit 3–4 h vor einem Start um 6 Uhr zählt zum selben Tag).
    final minute = (start + entry.minute).clamp(0, 24 * 60 - 1);
    final meal = StoredMeal(
      day: day,
      createdAt: dayStart.add(Duration(minutes: minute)),
      category: MealCategory.snack,
      title: '${entry.title} · ${plan.scenario.displayTitle}',
      items: entry.items,
    );
    await meals.save(meal);
    saved.add(meal);
  }
  return saved;
}

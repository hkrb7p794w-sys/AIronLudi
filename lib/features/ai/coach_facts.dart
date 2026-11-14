import 'package:coach_core/coach_core.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../services/garmin/garmin_sync_service.dart';
import '../nutrition/nutrition_controller.dart';
import '../today/today_controller.dart';

/// Ernährungslücken der letzten 14 Tage gegen das Referenzziel (Port von `RecipeViewModel.gaps`).
List<String> nutritionGaps({
  required List<StoredMeal> meals,
  required CoachSettings settings,
  required GarminProfile? garminProfile,
  required CalendarDay today,
}) {
  final start = today.adding(-14);
  final byDay = <CalendarDay, List<StoredMeal>>{};
  for (final meal in meals) {
    if (meal.day >= start && meal.day < today) (byDay[meal.day] ??= []).add(meal);
  }
  final totals = [
    for (final day in byDay.values)
      if (day.length >= 2) NutritionSummary.totals([for (final meal in day) ...meal.items]),
  ];
  final reference = NutritionPlanner.compute(
    activities: const [],
    planItems: const [],
    settings: settings.nutrition,
    garminProfile: garminProfile,
    day: today,
    hasGarminData: false,
  );
  return RecipePlanner.gaps(dailyTotals: totals, targets: reference.values);
}

/// Fakten aus den Regeln der App für Chat und KI-Analyse – überall dieselben, damit sich Antworten nicht
/// widersprechen. Im Datenschutzmodus „reduziert“ ohne Rohwerte (Port von `CoachFacts`).
abstract final class CoachFacts {
  static ChatFacts chat({
    required CoachSettings settings,
    required GarminSyncService sync,
    required List<WeightEntry> weights,
    required TodaySnapshot? snapshot,
    required List<DailyMetrics> metrics,
    required List<GarminActivity> activities,
    required List<StoredMeal> meals,
    required List<CalendarDay> gymDays,
    List<GymSession> gym = const [],
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(now ?? DateTime.now());
    final facts = ChatFacts(profile: settings.coachingProfile, privacy: settings.privacy)
      ..withholdsWeightTargets = settings.nutrition.weightTargetsWithheld;
    if (snapshot != null) {
      facts
        ..recommendation = snapshot.recommendation.label
        ..reasons = snapshot.recommendation.reasons;
      if (snapshot.advice case final advice?) {
        facts.todaySessions = [advice.headline];
      } else if (snapshot.today case final plan?) {
        facts.todaySessions = [for (final item in plan.items) item.title];
      }
    }
    if (settings.profile.mode == ProfileMode.personal) {
      final schedule = settings.schedule(today);
      facts.runWeek = RunPlanner.week(
        profile: settings.profile,
        schedule: schedule,
        monday: PlanAdjustments.monday(today),
        activities: activities,
      );
      if (facts.todaySessions.isEmpty) {
        facts.todaySessions = [for (final slot in schedule.slots(Weekday.of(today))) slot.title];
      }
    }
    facts.mobilityLine = settings.mobility.contextLine(today);
    // Die drei jüngsten vollständig übertragenen Einheiten der letzten Woche.
    final reports = [
      for (final report in sync.reportStore.load().values)
        if (report.day >= today.adding(-7) && report.day <= today) report,
    ]..sort((a, b) => a.day != b.day ? b.day.compareTo(a.day) : b.id.compareTo(a.id));
    facts.activityFindings = [
      for (final report in reports.take(3))
        ?ActivityFindings.contextLine(report, full: settings.privacy == PrivacyMode.full),
    ];
    facts.sleep = SleepCoach.report(days: metrics, settings: settings.sleep, goal: settings.profile.goal, today: today);
    // Dieselben Ziele wie im Reiter Ernährung und im Widget.
    facts.targets = NutritionController.targetsFor(
      today,
      activities: activities,
      settings: settings,
      profile: sync.profile,
      hasGarminData: metrics.isNotEmpty,
      recovery: RecoveryEvaluator.today(
        days: metrics,
        form: FitnessForm.seriesUntil(activities, today: today),
        today: today,
      ).level,
    );
    final todaysMeals = [
      for (final meal in meals)
        if (meal.day == today) meal,
    ];
    final eaten = [for (final meal in todaysMeals) ...meal.items];
    if (eaten.isNotEmpty) {
      final totals = NutritionSummary.totals(eaten);
      facts
        ..eatenKilocalories = totals[Nutrient.kcal]
        ..eaten = totals
        ..todayMeals = [
          for (final meal in todaysMeals)
            ChatMealLine(title: meal.title, nutrients: NutritionSummary.totals(meal.items)),
        ];
    }
    facts
      ..gymSessions = gym
      ..insights = settings.insights
      ..activities = [
        for (final activity in activities)
          if ((activity.day ?? today) >= today.adding(-56)) activity,
      ]
      ..todayMetrics = metrics.where((day) => day.day == today).lastOrNull;
    final tomorrow = today.adding(1);
    facts.tomorrowSessions = [for (final slot in settings.schedule(tomorrow).slots(Weekday.of(tomorrow))) slot.title];
    final weekDays = <CalendarDay, List<MealItem>>{};
    for (final meal in meals) {
      if (meal.day >= today.adding(-7) && meal.day < today) (weekDays[meal.day] ??= []).addAll(meal.items);
    }
    if (weekDays.isNotEmpty) {
      final totals = [for (final items in weekDays.values) NutritionSummary.totals(items)];
      double average(Nutrient nutrient) =>
          totals.fold(0.0, (sum, values) => sum + (values[nutrient] ?? 0)) / totals.length;
      facts.weekAverage = NutrientValues({
        Nutrient.kcal: average(Nutrient.kcal),
        Nutrient.protein: average(Nutrient.protein),
      });
    }
    facts.weightTrend = WeightTrend.trend(WeightTrend.merged(weights), today: today);
    final form = FitnessForm.seriesUntil(activities, today: today);
    if (FitnessForm.isReliable(form)) {
      if (form.lastOrNull?.formPercent case final percent?) facts.formZone = FormZone.of(percent);
    }
    facts.weekHighlights = WeeklyReport.lastWeek(
      activities: activities,
      days: metrics,
      gymDays: gymDays,
      today: today,
    ).highlights;
    return facts;
  }

  /// Fakten für die KI-Analyse: Chat-Fakten plus Krafttraining, Ernährungslücken und Gewicht.
  static List<String> analysis({
    required CoachSettings settings,
    required GarminSyncService sync,
    required List<WeightEntry> weights,
    required TodaySnapshot? snapshot,
    required List<DailyMetrics> metrics,
    required List<GarminActivity> activities,
    required List<StoredMeal> meals,
    required List<GymSession> gym,
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(now ?? DateTime.now());
    final facts = chat(
      settings: settings,
      sync: sync,
      weights: weights,
      snapshot: snapshot,
      metrics: metrics,
      activities: activities,
      meals: meals,
      gymDays: [for (final session in gym) session.day],
      now: now,
    );
    final lines = [
      ...ChatContext.lines(facts),
      for (final observation in GymCoach.observations(sessions: gym, today: today)) 'Krafttraining: $observation',
    ];
    final recentGym = gym.where((session) => session.day >= today.adding(-28)).length;
    if (recentGym > 0) lines.add('Krafteinheiten in den letzten 4 Wochen: $recentGym');
    final recent = [
      for (final activity in activities)
        if (activity.day case final day? when day >= today.adding(-28) && day <= today) activity,
    ];
    if (recent.isNotEmpty) {
      final minutes = recent.fold(0.0, (sum, activity) => sum + (activity.durationSeconds ?? 0)) / 60;
      lines.add('Ausdaueraktivitäten in den letzten 4 Wochen: ${recent.length}, zusammen ${minutes.toInt()} Minuten');
    }
    lines.addAll([
      for (final gap in nutritionGaps(meals: meals, settings: settings, garminProfile: sync.profile, today: today))
        'Ernährung 14 Tage: $gap',
    ]);
    return lines;
  }

  /// Was fehlt – geht an die KI, damit sie nichts ergänzt, und wird in der Ansicht genannt.
  static List<String> missing({
    required List<DailyMetrics> metrics,
    required List<GarminActivity> activities,
    required List<StoredMeal> meals,
    required List<GymSession> gym,
    required int weights,
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(now ?? DateTime.now());
    final result = <String>[];
    final week = today.adding(-7);
    if (!metrics.any((day) => day.day >= week)) {
      result.add('Keine Erholungsdaten (Ruhepuls, HRV, Schlaf) der letzten 7 Tage');
    } else if (!metrics.any((day) => day.day >= week && (day.sleepSeconds ?? 0) > 0)) {
      result.add('Keine Schlafdaten der letzten 7 Tage');
    }
    if (!activities.any((activity) => (activity.day?.compareTo(today.adding(-14)) ?? -1) >= 0)) {
      result.add('Keine Ausdaueraktivitäten in den letzten 2 Wochen');
    }
    if (!gym.any((session) => session.day >= today.adding(-42))) {
      result.add('Keine Krafteinheiten in den letzten 6 Wochen');
    }
    final mealDays = {
      for (final meal in meals)
        if (meal.day >= today.adding(-14)) meal.day,
    }.length;
    if (mealDays < 3) result.add('Kaum erfasste Mahlzeiten ($mealDays Tage in 2 Wochen)');
    if (weights == 0) result.add('Kein Gewichtsverlauf');
    return result;
  }
}

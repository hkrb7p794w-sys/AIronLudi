import 'package:coach_core/coach_core.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/metrics_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../data/settings/settings_store.dart';
import '../../features/gym/gym_controller.dart';
import '../../features/health/morning_report_views.dart';
import '../../features/nutrition/nutrition_controller.dart';
import '../../features/today/today_controller.dart';
import '../activities/live_activities.dart';
import 'widget_store.dart';

/// Homescreen-Widgets: schreibt den Stand der App in den gemeinsamen Speicher und übernimmt Wasser, das im Widget
/// getippt wurde. Ohne gemeinsamen Speicher passiert nichts – die App bleibt unberührt (Port von `WidgetPublisher`).
final class WidgetPublisher {
  WidgetPublisher({
    required this.store,
    required this.settings,
    required this.settingsStore,
    required this.metrics,
    required this.activities,
    required this.gymSessions,
    required this.meals,
    required this.gym,
    required this.garminProfile,
    required this.schedule,
    this.liveActivities,
    this.isDemo = false,
  });

  final WidgetStore store;
  final CoachSettings settings;
  final SettingsStore settingsStore;
  final MetricsRepository metrics;
  final ActivityRepository activities;
  final GymRepository gymSessions;
  final MealRepository meals;
  final GymController gym;
  final GarminProfile? Function() garminProfile;
  final SeasonSchedule? schedule;

  /// Live-Aktivität „Mahlzeiten heute“ (iOS); `null` ohne Plattformteil.
  final LiveActivityHost? liveActivities;
  final bool isDemo;

  /// Schalter in den Einstellungen (Ernährung); aus, solange ihn niemand einschaltet.
  bool get mealsActivityEnabled => settingsStore.boolValue(SettingsKeys.mealsLiveActivity);

  /// Wasser aus dem Widget als Einträge speichern (beim Öffnen, vor dem Neuberechnen).
  Future<int> takeQueuedActions({DateTime? now}) async {
    if (isDemo || !await store.isAvailable) return 0;
    final current = now ?? DateTime.now();
    final today = CalendarDay.fromDate(current);
    final queue = await store.loadQueue();
    final pending = queue.pending(today);
    for (final entry in pending) {
      await meals.save(
        StoredMeal(
          day: entry.day,
          createdAt: entry.at,
          category: NutritionController.category(entry.at.toLocal()),
          title: 'Wasser',
          items: [MealItem.water(milliliters: entry.waterMilliliters)],
        ),
      );
    }
    // Auch verfallene Einträge entfernen, damit die Datei nicht wächst.
    final oldest = today.adding(-WidgetActionQueue.maxAgeDays);
    await store.removeFromQueue({
      for (final entry in pending) entry.id,
      for (final entry in queue.entries)
        if (entry.day < oldest) entry.id,
    });
    return pending.length;
  }

  /// Stand schreiben und die Widgets neu laden. Günstig: rechnet dieselben Regeln wie die Reiter, ohne KI.
  Future<void> publish({DateTime? now}) async {
    if (isDemo || !settings.profile.onboardingDone) return;
    final current = now ?? DateTime.now();
    final available = await store.isAvailable;
    // Die Live-Aktivität „Mahlzeiten heute“ braucht keinen gemeinsamen Ordner.
    if (!available && !mealsActivityEnabled) {
      await liveActivities?.updateMeals(null, now: current);
      return;
    }
    final value = await snapshot(now: current);
    if (available) {
      await store.save(value);
      await store.reloadWidgets();
    }
    await liveActivities?.updateMeals(
      mealsActivityEnabled ? MealsLiveState.fromSnapshot(value, now: current) : null,
      now: current,
    );
  }

  Future<WidgetSnapshot> snapshot({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = CalendarDay.fromDate(current);
    final since = today.adding(-120);
    final results = await (
      metrics.range(from: since, to: today),
      activities.range(from: since, to: today),
      gymSessions.sessions(),
      meals.range(from: since, to: today),
    ).wait;
    final days = results.$1;
    final recentActivities = results.$2;
    final sessions = [...results.$3]..sort((a, b) => b.start.compareTo(a.start));
    final recentMeals = results.$4;
    final todayMeals = [
      for (final meal in recentMeals)
        if (meal.day == today) meal,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Heute: dieselbe Rechnung wie im Reiter (laufende Einheit mit Satz zählt mit).
    final active = gym.active;
    final running = active != null && gym.sessionState(now: current).countsAsTrained;
    final gymDays = [for (final session in sessions) session.day, if (running) active.day];
    final controller = TodayController(store: settingsStore, schedule: schedule)
      ..update(
        days: days,
        activities: recentActivities,
        settings: settings,
        gymDays: gymDays,
        gym: [for (final session in sessions) GymItem.fromSession(session)],
        now: current,
      );
    final focus = controller.snapshot?.focus;
    controller.dispose();
    final report = MorningReportBuilder.make(
      settings: settings,
      days: days,
      activities: recentActivities,
      focus: focus,
      now: current,
    );

    final todayPart = WidgetToday(
      level: focus?.level ?? report.level,
      headline: focus?.headline ?? report.headline,
      sessions: [
        for (final item in focus?.items ?? const <TodayFocusItem>[])
          if (item.sport case final sport?)
            WidgetSession(
              title: item.title,
              target: item.target,
              done: item.status == SessionStatus.done,
              symbol: sport.symbol,
            ),
      ],
      week: focus?.progress.text,
      weekFraction: focus?.progress.fraction,
    );

    // Ernährung: Ziele wie im Reiter, Summen ohne Schätzung.
    final targets = NutritionController.targetsFor(
      today,
      activities: recentActivities,
      settings: settings,
      profile: garminProfile(),
      hasGarminData: days.isNotEmpty,
      recovery: focus?.level ?? report.level,
    );
    final food = [
      for (final meal in todayMeals)
        if (!meal.isWater) meal,
    ];
    final totals = NutritionSummary.totals([for (final meal in food) ...meal.items]);
    // Flüssigkeit aus Getränken und Lebensmitteln wie in der Übersicht der App.
    final water = Hydration.total([for (final meal in todayMeals) ...meal.items]).total;
    final mealKilocalories = <MealCategory, double>{};
    for (final meal in food) {
      final slot = MealSplit.slot(meal.category);
      mealKilocalories[slot] =
          (mealKilocalories[slot] ?? 0) + (NutritionSummary.totals(meal.items)[Nutrient.kcal] ?? 0);
    }
    final last = food.lastOrNull;
    final nutrition = WidgetSnapshot.nutritionFrom(
      targets: targets.values,
      totals: totals,
      water: water,
      lastMeal: last == null
          ? null
          : WidgetLastMeal(
              title: last.title,
              at: last.createdAt,
              kcal: NutritionSummary.totals(last.items)[Nutrient.kcal] ?? 0,
            ),
      mealKilocalories: mealKilocalories,
    );

    // Gym nur mit Krafttraining im Profil.
    WidgetGym? gymPart;
    if (settings.profile.trains(TrainingSport.strength)) {
      final monday = today.adding(-today.weekdayIndex);
      // Wie im Plan: App-Einheiten und Krafttraining von der Uhr, je Tag einmal.
      final watchDays = [
        for (final activity in recentActivities)
          if (activity.sport == ActivitySport.strength) ?activity.day,
      ];
      final weekDone = {
        for (final day in [...gymDays, ...watchDays])
          if (day >= monday && day <= today) day,
      }.length;
      final personal = settings.profile.mode == ProfileMode.personal;
      final planned = personal ? settings.schedule(today).count(TrainingSport.strength) : null;
      final openStrength = (focus?.items ?? const <TodayFocusItem>[])
          .where((item) => item.sport == TrainingSport.strength && item.status != SessionStatus.done)
          .firstOrNull;
      final routine = personal ? RoutineRotation.next(routines: settings.gym.routines, sessions: sessions) : null;
      final lastSession = sessions.firstOrNull;
      gymPart = WidgetGym(
        next: routine?.name ?? gym.todayWorkout?.name ?? openStrength?.title,
        nextDetail: routine == null
            ? openStrength?.target
            : '${routine.items.length} Übungen · ca. ${RoutineRotation.estimatedMinutes(routine)} min',
        running: running,
        runningTitle: running ? active.title : null,
        last: lastSession == null
            ? null
            : WidgetLastSession(
                title: lastSession.title,
                day: lastSession.day,
                sets: lastSession.doneSetCount,
                volumeKg: lastSession.volumeKg,
              ),
        weekDone: weekDone,
        weekPlanned: planned != null && planned > 0 ? planned : null,
        nextIsForDay: routine == null ? true : null,
      );
    }

    final battery = BodyBatteryAnalysis.summary(days: days, today: today).current;
    final result = WidgetSnapshot(
      createdAt: current,
      day: today,
      today: todayPart,
      nutrition: nutrition,
      gym: gymPart,
      health: WidgetSnapshot.healthFrom(report, bodyBattery: battery),
    );
    // Mahlzeiten-Anzeigen: nur Tage mit eingetragenem Essen (Wasser allein zählt nicht), lückenlos.
    final foodDays = {
      for (final meal in recentMeals)
        if (!meal.isWater) meal.day,
    };
    final foodStreak = DailyStreak.compute(activeDays: foodDays, today: today, lookback: 120, jokers: 0);
    result.mealStreak = WidgetStreak(days: foodStreak.current, activeToday: foodStreak.activeToday);
    // Serie wie auf „Heute“: Tage mit Training oder Mahlzeit, ein Joker je Woche.
    final activeDays = {
      for (final activity in recentActivities) ?activity.day,
      ...gymDays,
      for (final meal in recentMeals) meal.day,
    };
    final streak = DailyStreak.compute(activeDays: activeDays, today: today, lookback: 120);
    result.streak = WidgetStreak(days: streak.current, activeToday: streak.activeToday);
    return result;
  }
}

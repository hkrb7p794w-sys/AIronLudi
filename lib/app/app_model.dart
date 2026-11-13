import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../data/repositories/gym_repository.dart';
import '../data/repositories/meal_repository.dart';
import '../data/repositories/metrics_repository.dart';
import '../data/repositories/source_store.dart';
import '../data/settings/coach_settings.dart';
import '../services/garmin/garmin_client.dart';
import '../services/garmin/garmin_connect_session.dart';
import '../services/garmin/garmin_sync_service.dart';
import '../services/gym/garmin_strength_service.dart';
import '../services/health/health_import_service.dart';
import '../services/reminders/reminder_service.dart';

/// Was der App-Zustand von der laufenden Krafteinheit wissen muss (Port des Zugriffs auf `GymViewModel.shared`).
abstract interface class ActiveGym {
  GymSession? get active;

  ActiveSessionState sessionState(DateTime now);

  /// Nur geöffnete, nie begonnene Einheit von früher verwerfen (keine Live-Aktivität, zählt nicht).
  void discardAbandoned();
}

/// Ohne Gym-Bereich (Tests, Vorschauen): keine laufende Einheit.
final class NoActiveGym implements ActiveGym {
  const NoActiveGym();

  @override
  GymSession? get active => null;

  @override
  ActiveSessionState sessionState(DateTime now) => ActiveSessionState.none;

  @override
  void discardAbandoned() {}
}

/// Zentrale Abhängigkeiten der App und Status des Garmin-Abrufs (Port von `AppModel`).
final class AppModel extends ChangeNotifier {
  AppModel({
    required this.settings,
    required this.garmin,
    required this.sync,
    required this.health,
    required this.sources,
    required this.reminders,
    required this.strength,
    required this.metrics,
    required this.activities,
    required this.meals,
    required this.gymRepository,
    this.seasonSchedule,
    this.gym = const NoActiveGym(),
    this.isDemo = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CoachSettings settings;
  final GarminClient garmin;
  final GarminSyncService sync;
  final HealthImportService health;
  final SourceStore sources;
  final ReminderService reminders;
  final GarminStrengthService strength;
  final MetricsRepository metrics;
  final ActivityRepository activities;
  final MealRepository meals;
  final GymRepository gymRepository;

  /// Saisonplan (aus `season-plan.json`), nur im Modus Saison genutzt.
  final SeasonSchedule? seasonSchedule;
  ActiveGym gym;

  /// Screenshot-Modus mit Beispieldaten: kein Abruf, keine Mitteilungen.
  final bool isDemo;
  final DateTime Function() _clock;

  bool isSyncing = false;
  SyncReport? lastReport;
  String? lastError;

  /// Einmalig beim Start (wie im Initialisierer von `AppModel`): Altbestand der Tageswerte gilt als Garmin.
  Future<void> start() async {
    sources.preferences = () => settings.sources;
    sync.sources = sources;
    health
      ..sources = sources
      ..reportStore = sync.reportStore;
    if (!isDemo) await sources.migrateIfNeeded();
  }

  SeasonSchedule? get _season => settings.profile.mode == ProfileMode.season ? seasonSchedule : null;

  /// Planerfüllung für Begleiter und Rangliste. Im Saisonplan gelten die festen Einheiten als geplant.
  MotivationSummary motivation(Set<CalendarDay> trainingDays, {CalendarDay? today}) {
    final season = _season;
    return MotivationSummary.compute(
      schedule: (monday) {
        final pause = settings.trainingBreak;
        // Tage einer Pause (Urlaub) gelten nicht als geplant.
        if (season == null) {
          final week = settings.schedule(monday);
          return pause?.removing(week, monday: monday) ?? week;
        }
        var week = WeekSchedule();
        final planned = ReminderPlanner.season(
          schedule: season,
          config: settings.season,
          decisions: settings.competitionDecisions,
          today: monday,
          includeToday: true,
          days: 7,
        );
        for (final reminder in planned) {
          if (pause?.contains(reminder.day) ?? false) continue;
          week = week.withSlots(const [SessionSlot(TrainingSport.other)], Weekday.of(reminder.day));
        }
        return week;
      },
      trainingDays: trainingDays,
      today: today ?? CalendarDay.fromDate(_clock()),
    );
  }

  /// Erinnerungen der nächsten 14 Tage neu planen (nach Änderungen am Plan und beim Öffnen der App). Nach jedem Abruf
  /// und jeder Krafteinheit erneut: Erinnerungen für schon Erledigtes entfallen.
  Future<void> refreshReminders() async {
    if (!settings.profile.onboardingDone || isDemo) return;
    await reminders.refresh(
      seasonSchedule: _season,
      log: await trainingLog(),
      loggedMeals: await loggedMeals(),
      morningSummary: await morningSummary(),
    );
  }

  /// Einordnung der letzten Nacht für die 8-Uhr-Mitteilung; `null`, solange die Werte von heute fehlen.
  Future<String?> morningSummary({DateTime? now}) async {
    if (!settings.reminders.morningReport) return null;
    final today = CalendarDay.fromDate(now ?? _clock());
    final days = await metrics.range(from: today.adding(-60), to: today);
    return MorningReportReminder.morningSummary(
      MorningReport.make(days: days, today: today, sleep: settings.sleep, goal: settings.profile.goal),
    );
  }

  /// Heute und morgen schon erfasste Mahlzeiten (Wasser zählt nicht) – dafür keine Erinnerung.
  Future<Set<String>> loggedMeals({DateTime? now}) async {
    final today = CalendarDay.fromDate(now ?? _clock());
    return {
      for (final meal in await meals.range(from: today, to: today.adding(1)))
        if (!meal.isWater) MealReminderPlanner.loggedKey(meal.day, meal.category),
    };
  }

  /// Aktivitäten und Krafteinheiten dieser und der letzten Woche.
  Future<TrainingLog> trainingLog({DateTime? now}) async {
    final at = now ?? _clock();
    final today = CalendarDay.fromDate(at);
    final start = today.adding(-today.weekdayIndex - 7);
    final recent = await activities.range(from: start, to: CalendarDay(9999, 12, 31));
    final gymDays = {
      for (final session in await gymRepository.sessions())
        if (session.day >= start) session.day,
    };
    // Laufende Einheit (mindestens ein Satz) zählt schon als trainiert; nur geöffnet zählt nicht.
    if (gym.active case final active? when gym.sessionState(at).countsAsTrained) gymDays.add(active.day);
    return TrainingLog(activities: recent, gymDays: gymDays);
  }

  DateTime? get lastSync => lastReport?.finishedAt ?? sync.lastSync;

  /// Gewicht aus eigenen Eingaben, Garmin und Health (Vorrang in `WeightTrend.merged`).
  List<WeightEntry> get allWeights => [...settings.weights, ...sync.weights, ...health.weights];

  /// Schutzgrenzen mit den neuesten Wägungen und Gesundheitsangaben abgleichen.
  void refreshGoalGuards() => settings.refreshGoalGuards(allWeights, garmin: sync.profile);

  /// Verbundene Quellen (für Vorrang und Doppelte).
  Set<DataProvider> get connectedSources => {
    if (garmin.isConfigured) DataProvider.garmin,
    if (health.isEnabled) DataProvider.appleHealth,
  };

  /// Nach geänderten Quellen-Einstellungen: Tageswerte und Aktivitäten neu zusammenführen.
  Future<void> applySourcePreferences() async {
    await sources.rebuild();
    await sources.deduplicateActivities(connected: connectedSources);
    notifyListeners();
  }

  /// Beim Öffnen der App: nur abrufen, wenn eine Quelle verbunden ist und der letzte Abruf länger her ist. Nach
  /// Fehlschlägen wartet der automatische Abruf länger (1 min … 6 h); manuell geht es immer.
  Future<void> syncIfDue() async {
    if (isDemo) return;
    refreshGoalGuards();
    gym.discardAbandoned();
    final now = _clock();
    final garminDue =
        sources.syncStates[DataProvider.garmin]?.isDue(now: now, minimumInterval: SyncPlan.minimumInterval) ?? true;
    if (garmin.isConfigured && garminDue && SyncPlan.isDue(lastSync: sync.lastSync, now: now)) {
      await syncNow();
    } else if (health.isEnabled && SyncPlan.isDue(lastSync: health.lastImport, now: now)) {
      await health.importNow(garminConnected: garmin.isConfigured);
    }
  }

  static String _message(Object error) => switch (error) {
    GarminAPIError(:final message) || GarminConnectError(:final message) => message,
    _ => '$error',
  };

  /// Erst Garmin, dann Health: Health ergänzt nur, was Garmin nicht liefert.
  Future<void> syncNow() async {
    if (isSyncing || isDemo) return;
    isSyncing = true;
    notifyListeners();
    try {
      if (garmin.isConfigured) {
        try {
          lastReport = await sync.sync();
          lastError = null;
          await sources.recordSuccess(DataProvider.garmin);
        } on Object catch (error) {
          lastError = _message(error);
          await sources.recordFailure(DataProvider.garmin, error: _message(error));
        }
      }
      await health.importNow(garminConnected: garmin.isConfigured);
      refreshGoalGuards();
      if (health.isEnabled) {
        if (health.lastProblem case final problem?) {
          await sources.recordFailure(DataProvider.appleHealth, error: problem);
        } else {
          await sources.recordSuccess(DataProvider.appleHealth);
        }
      }
      await sources.deduplicateActivities(connected: connectedSources);
      // Wartende Gym-Einheiten: Sätze in die inzwischen geladene Aufzeichnung der Uhr schreiben.
      if (settings.gym.uploadsToGarmin && (garmin.connect?.isLoggedIn ?? false)) {
        await strength.reconcile(garmin: garmin.connect!, gym: settings.gym);
      }
      await refreshReminders();
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }
}

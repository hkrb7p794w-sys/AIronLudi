import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/coach_settings.dart';
import '../../platform/notifications.dart';

/// Erinnerungen an geplante Einheiten als lokale Mitteilungen – funktioniert ohne Server und ohne Push-Berechtigung,
/// also auch mit SideStore. In der Mitteilung lässt sich die Einheit auslassen oder (in der App) verschieben. Ohne
/// Erlaubnis zeigt die App die Erinnerung als Karte unter „Heute“.
final class ReminderService extends ChangeNotifier {
  ReminderService({
    required this._settings,
    this._center,
    bool Function()? suppressesToday,
    void Function(String route)? openRoute,
  }) : _suppressesToday = suppressesToday ?? (() => false),
       _openRoute = openRoute ?? ((_) {});

  static const identifierPrefix = 'coach.reminder.';

  final CoachSettings _settings;
  final NotificationCenterBridge? _center;

  /// Läuft gerade eine Krafteinheit? Dann keine Erinnerung für heute (`GymViewModel.sessionState().suppressesReminders`).
  final bool Function() _suppressesToday;

  /// Öffnet einen Bereich der App (Morning Report → Gesundheit).
  final void Function(String route) _openRoute;

  NotificationPermission permission = NotificationPermission.unknown;

  /// Tag, für den die App das Verschieben anbieten soll (aus einer Mitteilung geöffnet).
  CalendarDay? pendingDay;

  /// „Nächste Woche planen“ aus der Sonntags-Mitteilung geöffnet.
  bool showsWeekPlanning = false;

  /// Laufende Neuplanung: Aufrufe kommen nacheinander dran. Sonst könnte eine ältere Planung (vor dem Start der Einheit
  /// begonnen) nach einer neueren ihre Erinnerung für heute wieder eintragen.
  Future<void>? _lastRefresh;

  /// Fragt beim ersten Mal nach der Erlaubnis und plant die Erinnerungen der nächsten 14 Tage neu. [loggedMeals]: schon
  /// erfasste Mahlzeiten (`MealReminderPlanner.loggedKey`) – dafür gibt es keine Erinnerung.
  Future<void> refresh({
    required SeasonSchedule? seasonSchedule,
    TrainingLog log = const TrainingLog(),
    Set<String> loggedMeals = const {},
    String? morningSummary,
    DateTime? now,
  }) {
    final previous = _lastRefresh;
    final task = () async {
      await previous;
      await _performRefresh(seasonSchedule, log, loggedMeals, morningSummary, now ?? DateTime.now());
    }();
    _lastRefresh = task;
    return task;
  }

  Future<void> _performRefresh(
    SeasonSchedule? seasonSchedule,
    TrainingLog log,
    Set<String> loggedMeals,
    String? morningSummary,
    DateTime now,
  ) async {
    final center = _center;
    if (center == null) return;
    final config = _settings.reminders;
    final wanted =
        config.enabled ||
        config.equipment ||
        config.weekPlanning ||
        config.nutritionReview ||
        config.meals.anyEnabled ||
        config.morningReport;
    permission = await center.permission(requestIfNeeded: wanted);
    notifyListeners();

    final pending = await center.pendingIdentifiers();
    await center.removePending(pending.where((id) => id.startsWith(identifierPrefix)).toList());
    if (permission != NotificationPermission.allowed) return;

    // Während einer laufenden Krafteinheit keine Erinnerung für heute (auch nicht für eine weitere Einheit).
    final today = CalendarDay.fromDate(now);
    final training = _suppressesToday();
    final planned = config.enabled
        ? reminders(seasonSchedule: seasonSchedule, log: log, now: now)
        : <TrainingReminder>[];
    final pause = _settings.trainingBreak;
    for (final reminder in planned) {
      if ((training && reminder.day == today) || (pause?.contains(reminder.day) ?? false)) continue;
      // Unmittelbar vor dem Eintragen erneut prüfen: Die Einheit kann inzwischen gestartet sein.
      if (reminder.day == today && _suppressesToday()) continue;
      await center.add(
        LocalNotification(
          id: reminder.id,
          title: reminder.title,
          body: ReminderPlanner.body(reminder, lead: CompanionVoice.reminderLead(_settings.companion)),
          day: reminder.day,
          hour: _settings.reminders.hour,
          minute: _settings.reminders.minute,
          category: reminder.canAdjust ? NotificationCategories.adjustable : NotificationCategories.plain,
          info: {'day': reminder.day.iso},
        ),
      );
    }

    // Ausrüstung am Vorabend und Wochenplanung am Sonntag (iOS erlaubt höchstens 64 geplante Mitteilungen).
    for (final note in notes(
      seasonSchedule: seasonSchedule,
      log: log,
      loggedMeals: loggedMeals,
      morningSummary: morningSummary,
      now: now,
    )) {
      await center.add(
        LocalNotification(
          id: note.id,
          title: note.title,
          body: note.body,
          day: note.day,
          hour: note.hour,
          minute: note.minute,
          category: note.kind == ScheduledNoteKind.weekPlanning ? NotificationCategories.planning : null,
          info: {'day': note.day.iso, 'kind': note.kind.rawValue},
        ),
      );
    }
  }

  static int _minutes(DateTime now) => now.hour * 60 + now.minute;

  List<ScheduledNote> notes({
    required SeasonSchedule? seasonSchedule,
    TrainingLog log = const TrainingLog(),
    Set<String> loggedMeals = const {},
    String? morningSummary,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final today = CalendarDay.fromDate(at);
    final minutesNow = _minutes(at);
    final config = _settings.reminders;
    return [
      if (config.equipment && _settings.profile.mode == ProfileMode.season && seasonSchedule != null)
        ...ReminderPlanner.swimEquipment(
          schedule: seasonSchedule,
          config: _settings.season,
          decisions: _settings.competitionDecisions,
          today: today,
          minutesNow: minutesNow,
          log: log,
        ),
      if (config.weekPlanning)
        ...ReminderPlanner.weekPlanning(
          mode: _settings.profile.mode,
          today: today,
          minutesNow: minutesNow,
          hour: config.planningHour,
          minute: config.planningMinute,
        ),
      if (config.nutritionReview) ...NutritionReviewReminder.nutritionReview(today: today, minutesNow: minutesNow),
      ...MealReminderPlanner.meals(config.meals, today: today, minutesNow: minutesNow, logged: loggedMeals),
      if (config.morningReport)
        ...MorningReportReminder.morningReport(today: today, minutesNow: minutesNow, summary: morningSummary),
    ];
  }

  List<TrainingReminder> reminders({
    required SeasonSchedule? seasonSchedule,
    TrainingLog log = const TrainingLog(),
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final today = CalendarDay.fromDate(at);
    final includeToday = _minutes(at) < _settings.reminders.hour * 60 + _settings.reminders.minute;
    switch (_settings.profile.mode) {
      case ProfileMode.personal:
        return ReminderPlanner.personal(
          profile: _settings.profile,
          adjustments: _settings.planAdjustments,
          today: today,
          includeToday: includeToday,
          log: log,
        );
      case ProfileMode.season:
        if (seasonSchedule == null) return [];
        return ReminderPlanner.season(
          schedule: seasonSchedule,
          config: _settings.season,
          decisions: _settings.competitionDecisions,
          today: today,
          includeToday: includeToday,
          log: log,
        );
    }
  }

  /// Einheiten eines Tages diese Woche auslassen.
  void skip(CalendarDay day) {
    _settings.planAdjustments = _settings.planAdjustments..skip(Weekday.of(day), inWeekOf: day);
    unawaited(_center?.removeDelivered(['$identifierPrefix${day.iso}']));
  }

  /// Einheiten eines Tages auf einen anderen Tag derselben Woche verschieben.
  void move(CalendarDay day, {required Weekday to}) {
    _settings.planAdjustments = _settings.planAdjustments..move(Weekday.of(day), to: to, inWeekOf: day);
    unawaited(_center?.removeDelivered(['$identifierPrefix${day.iso}']));
  }

  /// Antippen oder Aktion einer Mitteilung.
  void handle(NotificationAnswer answer) {
    final kind = answer.info['kind'];
    if (kind == ScheduledNoteKind.weekPlanning.rawValue) {
      showsWeekPlanning = true;
      notifyListeners();
      return;
    }
    // Morning Report: Gesundheitsbereich mit dem Bericht öffnen.
    if (kind == ScheduledNoteKind.morningReport.rawValue) {
      _openRoute('health');
      return;
    }
    // Ausrüstungs-Erinnerung: nur die App öffnen.
    final day = CalendarDay.tryParse(answer.info['day'] ?? '');
    if (kind != null || day == null) return;
    switch (answer.action) {
      case NotificationCategories.skipAction:
        skip(day);
      case NotificationCategories.doneAction:
        break;
      default:
        pendingDay = _settings.profile.mode == ProfileMode.personal ? day : null;
        notifyListeners();
    }
  }
}

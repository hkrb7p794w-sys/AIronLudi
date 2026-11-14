import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/coach_settings.dart';
import '../../data/settings/settings_store.dart';
import '../../services/ai/ai_client.dart';

/// Was die Ansicht „Heute“ zeigt.
final class TodaySnapshot {
  TodaySnapshot({
    required this.metrics,
    required this.isFromYesterday,
    required this.recommendation,
    required this.plan,
    required this.week,
    required this.today,
    required this.advice,
    this.sessions,
    this.focus,
    this.load,
  });

  final DailyMetrics? metrics;

  /// `true`, wenn für heute noch keine Werte vorliegen und die von gestern gezeigt werden.
  final bool isFromYesterday;
  final Recommendation recommendation;
  final PlanState plan;
  final WeeklyVolume week;

  /// Einheiten des Tages mit Hinweisen (Portierung von `coach_today()`).
  final TodayPlan? today;

  /// Empfehlung aus dem eigenen Wochenplan (nur bei persönlichem Profil).
  final ScheduleAdvice? advice;

  /// Soll/Ist je Einheit dieser Woche (nur bei persönlichem Profil).
  final SessionWeek? sessions;

  /// „Jetzt dran“ für beide Modi.
  final TodayFocus? focus;

  /// Belastung der letzten 7 Tage über alle Sportarten.
  final WeekLoadResult? load;
}

/// Berechnet Tagesampel, Wochen-Soll/Ist und Rennvorbereitung aus den gespeicherten Daten und holt die KI-Notiz
/// (einmal je Tag und Ampelstufe, zwischengespeichert) – Port von `TodayViewModel`.
final class TodayController extends ChangeNotifier {
  TodayController({required this._store, required this._schedule});

  static const noteKey = SettingsKeys.note;
  static const fallbackSource = 'Regeln (ohne KI)';

  final SettingsStore _store;
  final SeasonSchedule? _schedule;

  TodaySnapshot? snapshot;
  List<String> notePoints = const [];
  String noteSource = '';

  /// Regeln hinter Tagesampel und Notiz.
  List<String> noteEvidence = const [];
  String? noteError;
  bool isLoadingNote = false;

  void update({
    required List<DailyMetrics> days,
    required List<GarminActivity> activities,
    required CoachSettings settings,
    List<CalendarDay> gymDays = const [],
    List<GymItem> gym = const [],
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(now ?? DateTime.now());
    final state = RecoveryEvaluator.today(
      days: days,
      form: FitnessForm.seriesUntil(activities, today: today),
      today: today,
    );
    final metrics = state.metrics;
    final recommendation = state.recommendation;
    final hasRecovery = state.isKnown;
    final week = WeeklyVolume.from(activities, weekContaining: today, gymDays: gymDays);
    final plan = SeasonPlan.state(today: today, config: settings.season, week: week);
    final todayPlan = switch (_schedule) {
      final schedule? => todayPlanFor(
        schedule: schedule,
        activities: activities,
        gymDays: gymDays,
        settings: settings,
        today: today,
        recommendation: recommendation,
        hasMetrics: hasRecovery,
      ),
      null => null,
    };
    ScheduleAdvice? advice;
    SessionWeek? sessions;
    TodayFocus? focus;
    if (settings.profile.mode == ProfileMode.personal) {
      // „Geschafft“ nur, wenn die geplanten Einheiten wirklich gemacht sind (Sportart, Dauer).
      final week = sessionWeek(settings: settings, activities: activities, gymDays: gymDays, today: today);
      sessions = week;
      final recovery = MissedSessions.cappedRecovery(
        hasRecovery ? recommendation.level : null,
        sickDay: settings.illnessDay,
        today: today,
      );
      final personal = ScheduleAdvisor.advice(
        profile: settings.profile,
        schedule: settings.schedule(today),
        day: today,
        recovery: recovery,
        trainedToday: week.allCounted(today),
      );
      advice = personal;
      focus = TodayFocus.personal(
        advice: personal,
        recommendation: hasRecovery ? recommendation : null,
        week: week,
        activities: activities,
        today: today,
      );
    } else if (todayPlan != null) {
      focus = TodayFocus.season(
        today: todayPlan,
        recommendation: recommendation,
        hasMetrics: hasRecovery,
        plan: plan,
        week: week,
      );
    }
    snapshot = TodaySnapshot(
      metrics: metrics,
      isFromYesterday: metrics != null && metrics.day < today,
      recommendation: recommendation,
      plan: plan,
      week: week,
      today: todayPlan,
      advice: advice,
      sessions: sessions,
      focus: focus,
      load: WeekLoad.check(
        activities: activities,
        gym: gym,
        today: today,
        maxIncrease: Personalization.maxLoadIncrease(settings.profile.effectiveGoals(today)),
      ),
    );
    _showCachedOrFallback();
    notifyListeners();
  }

  /// Soll/Ist der Woche: Plan mit Ausnahmen, Laufminuten aus dem Laufplan, Aktivitäten und Krafteinheiten.
  static SessionWeek sessionWeek({
    required CoachSettings settings,
    required List<GarminActivity> activities,
    required List<CalendarDay> gymDays,
    required CalendarDay today,
    CalendarDay? weekOf,
  }) {
    final monday = PlanAdjustments.monday(weekOf ?? today);
    final schedule = settings.schedule(monday);
    final runWeek = RunPlanner.week(
      profile: settings.profile,
      schedule: schedule,
      monday: monday,
      activities: activities,
    );
    final runMinutes = <Weekday, List<int>>{};
    for (final session in runWeek?.sessions ?? const <RunSession>[]) {
      (runMinutes[session.weekday] ??= []).add(session.minutes);
    }
    final planned = SessionMatcher.planned(schedule, monday: monday, runMinutes: runMinutes);
    return SessionMatcher.match(planned: planned, activities: activities, gymDays: gymDays.toSet(), today: today);
  }

  /// Erledigtes der Woche: Aktivitäten (Rad nur mit Distanz) und Krafteinheiten aus Garmin und App.
  static TodayPlan todayPlanFor({
    required SeasonSchedule schedule,
    required List<GarminActivity> activities,
    required List<CalendarDay> gymDays,
    required CoachSettings settings,
    required CalendarDay today,
    required Recommendation recommendation,
    required bool hasMetrics,
  }) {
    final monday = today.adding(-today.weekdayIndex);
    final progress = TodayPlan.doneThisWeek(activities: activities, gymDays: gymDays, weekOf: today, upTo: today);
    final zones = HeartRateZoneCalculator.distribution(
      activities,
      today: today,
      weeks: 1,
    ).perWeek.where((week) => week.monday == monday).firstOrNull?.run;
    return TodayPlan(
      schedule: schedule,
      config: settings.season,
      decisions: settings.competitionDecisions,
      today: today,
      level: hasMetrics ? recommendation.level : null,
      advice: recommendation.advice,
      done: progress.done,
      gymDays: progress.strengthDays,
      runZones: zones,
    );
  }

  /// KI-Notiz holen. Ohne eingerichteten Worker bleibt die regelbasierte Notiz stehen.
  Future<void> loadNote(AIClient ai, {required CoachSettings settings, bool force = false}) async {
    final snapshot = this.snapshot;
    if (snapshot == null || !ai.isConfigured || isLoadingNote) return;
    final cached = _cachedNote(snapshot);
    if (!force && cached != null && cached.source != fallbackSource) return;
    // Beim Öffnen nur, wenn die KI-Stufe automatische Notizen erlaubt; „Neu formulieren“ zählt als Anfrage.
    final trigger = force ? AITrigger.user : AITrigger.automatic;
    final advice = snapshot.advice;
    final task = advice == null ? 'daily_note' : 'personal_note';
    if (!ai.allows(task, trigger: trigger)) {
      noteError = null;
      _showCachedOrFallback();
      notifyListeners();
      return;
    }
    isLoadingNote = true;
    notifyListeners();
    try {
      final Map<String, Object?> input;
      if (advice != null) {
        // Persönliches Profil: gleiche Empfehlung wie die Karte, ohne Werte des Saisonplans.
        input = PersonalNote.input(
          profile: settings.coachingProfile,
          advice: advice,
          recommendation: snapshot.metrics == null ? null : snapshot.recommendation,
          metrics: snapshot.metrics,
          week: snapshot.sessions,
          today: snapshot.plan.today,
          privacy: settings.privacy,
        );
      } else {
        input = CoachingNote.input(
          recommendation: snapshot.recommendation,
          metrics: snapshot.metrics,
          plan: snapshot.plan,
          config: settings.season,
          week: snapshot.week,
          privacy: settings.privacy,
        );
        // Gleiche Einheiten und Hinweise wie in der Ansicht – Karte und Notiz widersprechen sich nicht.
        if (snapshot.today case final today?) {
          input['todayItems'] = [
            for (final item in today.items)
              CoachingNote.line(item.title, item.caption, done: item.done, chip: item.chip),
          ];
          input['openItems'] = [
            for (final item in today.open) CoachingNote.line(item.title, item.caption, done: false, chip: item.chip),
          ];
        }
      }
      final response = await ai.run(task, input: input, trigger: trigger);
      final points = CoachingNote.points(response.output);
      if (points.isEmpty) throw const AIClientError.http(200, 'Leere KI-Antwort');
      await _store.setJson(noteKey, {
        'day': snapshot.plan.today.iso,
        'level': snapshot.recommendation.level.rawValue,
        'points': points,
        'source': 'KI · ${response.model}',
        'sources': CoachingNote.sources(response.output),
        if (advice != null) 'personal': true,
      });
      noteError = null;
    } on Object catch (error) {
      noteError = error is AIClientError ? error.message : '$error';
    } finally {
      isLoadingNote = false;
    }
    _showCachedOrFallback();
    notifyListeners();
  }

  void _showCachedOrFallback() {
    final snapshot = this.snapshot;
    if (snapshot == null) return;
    final advice = snapshot.advice;
    if (_cachedNote(snapshot) case final cached?) {
      notePoints = cached.points;
      noteSource = cached.source;
      noteEvidence = [...snapshot.recommendation.evidenceIDs, ...cached.sources];
    } else if (advice != null) {
      notePoints = PersonalNote.fallback(
        advice: advice,
        recommendation: snapshot.metrics == null ? null : snapshot.recommendation,
        week: snapshot.sessions,
      );
      noteSource = fallbackSource;
      noteEvidence = [...advice.evidenceIDs, if (snapshot.metrics != null) ...snapshot.recommendation.evidenceIDs];
    } else {
      notePoints = CoachingNote.fallback(snapshot.recommendation, plan: snapshot.plan);
      noteSource = fallbackSource;
      noteEvidence = snapshot.recommendation.evidenceIDs;
    }
  }

  /// Zwischengespeicherte Notiz für denselben Tag, dieselbe Ampelstufe und denselben Modus.
  ({List<String> points, String source, List<String> sources})? _cachedNote(TodaySnapshot snapshot) {
    final json = _store.json(noteKey);
    if (json is! Map) return null;
    final points = json['points'];
    final source = json['source'];
    if (json['day'] != snapshot.plan.today.iso ||
        json['level'] != snapshot.recommendation.level.rawValue ||
        (json['personal'] == true) != (snapshot.advice != null) ||
        points is! List ||
        source is! String) {
      return null;
    }
    final sources = json['sources'];
    return (
      points: [for (final point in points) '$point'],
      source: source,
      sources: sources is List ? [for (final id in sources) '$id'] : const <String>[],
    );
  }
}

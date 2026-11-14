import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../data/settings/settings_store.dart';
import '../../services/ai/ai_client.dart';
import '../../services/garmin/garmin_sync_service.dart';
import '../today/today_controller.dart';
import 'coach_facts.dart';

/// Daten für Regeln, Chat und Analyse.
typedef AIData = ({
  List<DailyMetrics> metrics,
  List<GarminActivity> activities,
  List<StoredMeal> meals,
  List<GymSession> gym,
  List<WeightEntry> weights,
});

/// Sammelt die Empfehlungen der Regeln und startet die KI-Analyse. Beides landet im selben Eingang
/// (`InsightInbox`), der Doppeltes und Widersprüche aussortiert (Port von `AIViewModel`).
final class AIController extends ChangeNotifier {
  AIController({required SettingsStore store, required SeasonSchedule? schedule})
    : _today = TodayController(store: store, schedule: schedule);

  final TodayController _today;
  bool isAnalyzing = false;
  String? error;
  String? note;
  List<String> missing = const [];

  /// Gleiche Tagesbewertung wie unter „Heute“ (für Regeln, Chat und Fakten).
  TodaySnapshot? snapshot;

  @override
  void dispose() {
    _today.dispose();
    super.dispose();
  }

  /// Regeln neu auswerten. Was eine Regel nicht mehr meldet, gilt ab jetzt als „nicht mehr aktuell“.
  void refreshRules({
    required CoachSettings settings,
    required GarminSyncService sync,
    required AIData data,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    _today.update(
      days: data.metrics,
      activities: data.activities,
      settings: settings,
      gymDays: [for (final session in data.gym) session.day],
      gym: [for (final session in data.gym) GymItem.fromSession(session)],
      now: time,
    );
    snapshot = _today.snapshot;
    final day = CalendarDay.fromDate(time);
    final rules = InsightRules.build(
      InsightRulesInput(
        now: time,
        recommendation: data.metrics.any((metrics) => metrics.day >= day.adding(-1)) ? snapshot?.recommendation : null,
        sleep: SleepCoach.report(days: data.metrics, settings: settings.sleep, goal: settings.profile.goal, today: day),
        gymObservations: GymCoach.observations(sessions: data.gym, today: day),
        nutritionGaps: nutritionGaps(meals: data.meals, settings: settings, garminProfile: sync.profile, today: day),
        planSuggestions: [
          for (final suggestion in _planSuggestions(settings))
            if (!settings.dismissedSuggestions.contains(suggestion.id)) suggestion,
        ],
      ),
    );
    var inbox = InsightInbox.retireRules(settings.insights, keeping: {for (final rule in rules) rule.id}, now: time);
    inbox = InsightInbox.merge(inbox, rules, now: time);
    if (!listEquals(inbox, settings.insights)) settings.insights = inbox;
    missing = CoachFacts.missing(
      metrics: data.metrics,
      activities: data.activities,
      meals: data.meals,
      gym: data.gym,
      weights: data.weights.length,
      now: time,
    );
    notifyListeners();
  }

  static void mark(InsightStatus status, Insight insight, CoachSettings settings, {bool onlyIfNew = false}) {
    if (onlyIfNew && insight.status != InsightStatus.newInsight) return;
    settings.insights = InsightInbox.setStatus(
      status,
      id: insight.id,
      insights: settings.insights,
      now: DateTime.now(),
    );
  }

  /// KI-Analyse auf Anfrage: Fakten der App, fehlende Daten und die Regeln gehen an den Worker; zurück kommen nur
  /// geprüfte Empfehlungen mit Belegen.
  Future<void> analyze({
    required InsightTopic? topic,
    required CoachSettings settings,
    required GarminSyncService sync,
    required AIClient ai,
    required AIData data,
    DateTime? now,
  }) async {
    if (isAnalyzing) return;
    final time = now ?? DateTime.now();
    isAnalyzing = true;
    error = null;
    note = null;
    notifyListeners();
    try {
      final facts = InsightAnalysis.facts(
        CoachFacts.analysis(
          settings: settings,
          sync: sync,
          weights: data.weights,
          snapshot: snapshot,
          metrics: data.metrics,
          activities: data.activities,
          meals: data.meals,
          gym: data.gym,
          now: time,
        ),
      );
      if (facts.isEmpty) {
        error = 'Noch zu wenige Daten für eine Analyse.';
        return;
      }
      final rules = [
        for (final insight in settings.insights)
          if (insight.origin == InsightOrigin.rules && insight.isCurrent(time)) insight,
      ];
      final input = InsightAnalysis.input(
        topic: topic,
        facts: facts,
        missing: missing,
        ruleInsights: rules,
        closed: settings.insights,
      );
      final response = await ai.run('ai_insights', input: input);
      final insights = InsightAnalysis.insights(response.output, facts: facts, model: response.model, now: time);
      final before = settings.insights.length;
      settings.insights = InsightInbox.merge(settings.insights, insights, now: time);
      final added = settings.insights.length - before;
      note = added > 0
          ? '$added neue Empfehlung${added == 1 ? '' : 'en'}.'
          : 'Keine neuen Empfehlungen – die bisherigen gelten weiter.';
    } on Object catch (failure) {
      error = failure is AIClientError ? failure.message : '$failure';
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Planvorschläge wie unter „Heute“ (nur eigener Wochenplan).
  List<PlanSuggestion> _planSuggestions(CoachSettings settings) {
    final snapshot = this.snapshot;
    if (settings.profile.mode != ProfileMode.personal || snapshot == null) return const [];
    final day = snapshot.plan.today;
    final load = snapshot.load;
    return [
      if (snapshot.advice case final advice?)
        ?PlanSuggestion.recovery(
          advice: advice,
          profile: settings.profile,
          adjustments: settings.planAdjustments,
          today: day,
        ),
      if (load != null) ...[
        ?PlanSuggestion.load(load, profile: settings.profile, adjustments: settings.planAdjustments, today: day),
        ?PlanSuggestion.nextWeek(
          load: load,
          profile: settings.profile,
          adjustments: settings.planAdjustments,
          today: day,
        ),
      ],
    ];
  }
}

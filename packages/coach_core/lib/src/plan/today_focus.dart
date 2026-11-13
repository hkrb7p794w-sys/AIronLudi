import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/recommendation.dart';
import '../coach/recovery_level.dart';
import '../coach/season_plan.dart';
import '../evidence/evidence.dart';
import '../garmin/garmin_activity.dart';
import '../profile/schedule_advisor.dart';
import '../profile/session_match.dart';
import '../profile/user_profile.dart';
import '../profile/week_load.dart';
import 'today_plan.dart';

/// Eine Einheit auf der Karte „Jetzt dran“.
final class TodayFocusItem {
  const TodayFocusItem({
    required this.id,
    required this.sport,
    required this.title,
    required this.target,
    required this.demanding,
    required this.status,
    required this.chip,
    required this.detail,
  });

  final String id;

  /// `null` = Ruhetag bzw. Regeneration.
  final TrainingSport? sport;
  final String title;

  /// Soll bzw. Soll/Ist: „Soll 45 min · Locker“, Saisonplan: Pace/Watt aus dem Plan.
  final String target;
  final bool demanding;
  final SessionStatus? status;

  /// Hinweis bei gelber/roter Ampel („nicht heute“).
  final String chip;

  /// Ablauf zum Aufklappen.
  final String detail;

  @override
  String toString() => 'TodayFocusItem($id, $title, $target, $status)';
}

/// Wochenfortschritt auf der Karte.
final class TodayFocusProgress {
  const TodayFocusProgress({
    required this.sessionsDone,
    required this.sessionsPlanned,
    required this.minutesDone,
    required this.minutesPlanned,
  });

  final int sessionsDone;
  final int sessionsPlanned;
  final int minutesDone;
  final int? minutesPlanned;

  double get fraction {
    final planned = minutesPlanned;
    if (planned != null && planned > 0) return math.min(minutesDone / planned, 1);
    return sessionsPlanned > 0 ? math.min(sessionsDone / sessionsPlanned, 1) : 0;
  }

  /// „3/5 Einheiten · 140/210 min“
  String get text =>
      '$sessionsDone/$sessionsPlanned Einheiten · '
      '${minutesPlanned == null ? '$minutesDone min' : '$minutesDone/$minutesPlanned min'}';

  @override
  bool operator ==(Object other) =>
      other is TodayFocusProgress &&
      other.sessionsDone == sessionsDone &&
      other.sessionsPlanned == sessionsPlanned &&
      other.minutesDone == minutesDone &&
      other.minutesPlanned == minutesPlanned;

  @override
  int get hashCode => Object.hash(sessionsDone, sessionsPlanned, minutesDone, minutesPlanned);
}

/// „Jetzt dran“: eine Karte für beide Modi. Heutige Einheiten mit Soll, Ampel, eine Zeile „warum“, der Widerspruch
/// zwischen Regel und Plan und der Wochenfortschritt. Nur die Quelle der Einheiten unterscheidet sich: Musterwoche
/// des Saisonplans oder eigener Wochenplan mit Soll/Ist.
final class TodayFocus {
  const TodayFocus({
    required this.level,
    required this.headline,
    required this.detail,
    required this.why,
    required this.conflict,
    required this.items,
    required this.progress,
    required this.evidenceIDs,
  });

  /// `null`, wenn noch keine Erholungswerte vorliegen.
  final RecoveryLevel? level;
  final String headline;
  final String detail;
  final String? why;

  /// Regel und Plan widersprechen sich – beides steht da, die Regel gilt.
  final String? conflict;
  final List<TodayFocusItem> items;
  final TodayFocusProgress progress;
  final List<String> evidenceIDs;

  // Eigener Wochenplan

  static TodayFocus personal({
    required ScheduleAdvice advice,
    required Recommendation? recommendation,
    required SessionWeek week,
    required List<GarminActivity> activities,
    required CalendarDay today,
  }) {
    final items = [
      for (final result in week.resultsOn(today))
        TodayFocusItem(
          id: result.id,
          sport: result.planned.slot.sport,
          title: result.planned.slot.title,
          target: result.actualMinutes == null
              ? 'Soll ${result.planned.targetMinutes} min · ${result.planned.slot.intensity.label}'
              : result.compareText,
          demanding: result.planned.slot.intensity.isDemanding,
          status: result.status,
          chip: '',
          detail: result.planned.slot.guide,
        ),
    ];
    final level = recommendation?.level;
    final counted = week.results.where((result) => result.status.counts).toList();
    // Nur Einheiten aus dem Plan: Spaziergänge füllen ihn nicht, Krafteinheiten aus der App schon.
    final minutesDone = counted.fold(
      0,
      (sum, result) =>
          sum +
          (result.actualMinutes ??
              (result.planned.slot.sport == TrainingSport.strength ? WeekLoad.defaultGymMinutes : 0)),
    );
    final progress = TodayFocusProgress(
      sessionsDone: counted.length,
      sessionsPlanned: week.results.length,
      minutesDone: minutesDone,
      minutesPlanned: week.results.isEmpty
          ? null
          : week.results.fold<int>(0, (sum, result) => sum + result.planned.targetMinutes),
    );
    final reasons = recommendation?.reasons ?? const <String>[];
    final evidence = {...advice.evidenceIDs, ...?recommendation?.evidenceIDs}.toList()..sort();
    return TodayFocus(
      level: level,
      headline: advice.headline,
      detail: advice.detail,
      why: whyText(reasons),
      conflict: advice.mode == ScheduleAdviceMode.done
          ? null
          : conflictText(
              level: level,
              reasons: reasons,
              planned: [
                for (final item in items)
                  if (item.demanding) item.title,
              ],
            ),
      items: items,
      progress: progress,
      evidenceIDs: evidence,
    );
  }

  // Saisonplan

  static TodayFocus season({
    required TodayPlan today,
    required Recommendation recommendation,
    required bool hasMetrics,
    required PlanState plan,
    required WeeklyVolume week,
  }) {
    final items = [
      for (final item in today.items)
        TodayFocusItem(
          id: item.id,
          sport: sport(item.sport),
          title: item.title,
          target: item.caption,
          demanding: item.hardness >= 2,
          status: item.done ? SessionStatus.done : null,
          chip: item.chip,
          detail: item.detail,
        ),
    ];
    final level = hasMetrics ? recommendation.level : null;
    final progress = TodayFocusProgress(
      sessionsDone: plan.targets.fold(0, (sum, target) => sum + math.min(target.done, target.target.minimum)),
      sessionsPlanned: plan.targets.fold(0, (sum, target) => sum + target.target.minimum),
      minutesDone: week.minutes.values.fold(0.0, (sum, value) => sum + value).round(),
      minutesPlanned: null,
    );
    final reasons = hasMetrics ? recommendation.reasons : const <String>[];
    return TodayFocus(
      level: level,
      headline: recommendation.label,
      detail: today.advice,
      why: whyText(reasons),
      conflict: conflictText(
        level: level,
        reasons: reasons,
        planned: [
          for (final item in items)
            if (item.demanding && item.status == null) item.title,
        ],
      ),
      items: items,
      progress: progress,
      evidenceIDs: recommendation.evidenceIDs,
    );
  }

  static TrainingSport? sport(TodayPlanSport sport) => switch (sport) {
    TodayPlanSport.swim => TrainingSport.swim,
    TodayPlanSport.bike => TrainingSport.bike,
    TodayPlanSport.run => TrainingSport.run,
    TodayPlanSport.strength => TrainingSport.strength,
    TodayPlanSport.rest => null,
  };

  /// Unauffällige Gründe („HRV-Status ausgeglichen“) sind keine Begründung wert.
  static String? whyText(List<String> reasons) {
    final relevant = reasons
        .where((reason) => reason != 'keine Erholungswerte auffällig' && reason != 'HRV-Status ausgeglichen')
        .toList();
    return relevant.isEmpty ? null : relevant.join(' · ');
  }

  /// „Regel: locker (HRV unter Baseline) · geplant: Qualitätslauf“ – die KI darf die Regel nicht überstimmen.
  static String? conflictText({
    required RecoveryLevel? level,
    required List<String> reasons,
    required List<String> planned,
  }) {
    if (level == null || level == RecoveryLevel.normal || planned.isEmpty) return null;
    final rule = level == RecoveryLevel.pause ? 'Pause' : 'locker';
    final because = whyText(reasons);
    return 'Regel: $rule${because == null ? '' : ' ($because)'} · geplant: ${planned.join(', ')}. Es gilt die Regel.';
  }
}

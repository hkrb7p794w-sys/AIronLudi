import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../profile/schedule_advisor.dart';
import '../profile/session_match.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import 'coaching_note.dart';
import 'recommendation.dart';

/// Tagesnotiz für das persönliche Profil: dieselbe Idee wie `CoachingNote`, aber ohne Saisonplan-Werte
/// (keine FTP, Schwellenpace oder Almere). Die Empfehlung kommt aus `ScheduleAdvisor`; die KI formuliert sie nur.
abstract final class PersonalNote {
  static const evidence = [
    'recovery.hrv',
    'recovery.rhr',
    'recovery.sleep',
    'recovery.subjective',
    'intensity.distribution',
    'load.rpe',
    'strength.interference',
    'run.progression',
  ];

  static Map<String, Object?> input({
    required UserProfile profile,
    required ScheduleAdvice advice,
    required Recommendation? recommendation,
    required DailyMetrics? metrics,
    required SessionWeek? week,
    required CalendarDay today,
    required PrivacyMode privacy,
  }) {
    final results = week?.results ?? const <SessionResult>[];
    final reasons = recommendation == null
        ? const <String>[]
        : (privacy == PrivacyMode.full ? recommendation.reasons : CoachingNote.neutralReasons(recommendation, metrics));
    final event = profile.event;
    return {
      'goal': profile.goal.label,
      'sports': [for (final sport in profile.sports) sport.label],
      'weekday': Weekday.of(today).long,
      'todayItems': [
        for (final result in results)
          if (result.planned.day == today) '${result.planned.slot.title} (${result.status.label})',
      ],
      'weekDone': results.where((result) => result.status.counts).length.toDouble(),
      'weekPlanned': results.length.toDouble(),
      'missed': [
        for (final result in results)
          if (result.status == SessionStatus.missed) result.planned.slot.title,
      ],
      'vitals': CoachingNote.vitals(metrics, privacy: privacy),
      'decision': {'label': advice.headline, 'advice': advice.detail, 'reasons': reasons},
      'evidence': CoachingNote.evidenceInput(evidence),
      if (event != null) 'event': '${event.name} in ${math.max(today.daysUntil(event.date), 0)} Tagen',
    };
  }

  /// Ohne KI: Empfehlung, Begründung und Stand der Woche als feste Sätze.
  static List<String> fallback({
    required ScheduleAdvice advice,
    required Recommendation? recommendation,
    required SessionWeek? week,
  }) {
    final lines = ['${advice.headline}: ${advice.detail}'];
    if (recommendation != null && recommendation.reasons.isNotEmpty) {
      lines.add('Grund: ${recommendation.reasons.join('; ')}.');
    }
    final results = week?.results;
    if (results != null && results.isNotEmpty) {
      final done = results.where((result) => result.status.counts).length;
      lines.add('Diese Woche: $done von ${results.length} Einheiten geschafft.');
    }
    return lines;
  }
}

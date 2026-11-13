import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import 'user_profile.dart';
import 'week_schedule.dart';

/// Art der Tagesempfehlung.
enum ScheduleAdviceMode {
  /// Einheit wie geplant.
  asPlanned,

  /// Dieselbe Einheit, aber lockerer.
  lighter,

  /// Heute besser frei, ggf. mit Vorschlag zum Verschieben.
  rest,

  /// Laut Plan frei.
  restDay,

  /// Heute schon trainiert.
  done,
}

/// Empfehlung für heute, abgeleitet aus dem eigenen Wochenplan und der Erholung. Die Regeln entscheiden;
/// formuliert wird mit festen Sätzen, die KI kann sie bei Bedarf umschreiben.
final class ScheduleAdvice {
  const ScheduleAdvice({
    required this.mode,
    required this.headline,
    required this.detail,
    required this.move,
    required this.plannedTitles,
    required this.evidenceIDs,
  });

  final ScheduleAdviceMode mode;
  final String headline;
  final String detail;

  /// Vorgeschlagener Tag, auf den eine Einheit verschoben werden kann.
  final Weekday? move;
  final List<String> plannedTitles;
  final List<String> evidenceIDs;

  @override
  String toString() => 'ScheduleAdvice($mode, $headline)';
}

abstract final class ScheduleAdvisor {
  /// [recovery]: Tagesampel aus Garmin-Werten; `null`, wenn heute noch keine Werte vorliegen. [trainedToday]: Für
  /// heute ist schon eine Aktivität aufgezeichnet. [schedule]: Plan dieser Woche mit Ausnahmen (`PlanAdjustments`);
  /// Standard ist der Wochenplan des Profils.
  static ScheduleAdvice advice({
    required UserProfile profile,
    WeekSchedule? schedule,
    required CalendarDay day,
    required RecoveryLevel? recovery,
    required bool trainedToday,
  }) {
    final plan = schedule ?? profile.schedule;
    final weekday = Weekday.of(day);
    final slots = plan.slots(weekday);
    final titles = [for (final slot in slots) slot.title];
    final joined = titles.join(' + ');
    final demanding = slots.any((slot) => slot.intensity.isDemanding);
    final tomorrow = tomorrowNote(plan.slots(weekday.next), weekday.next);
    const recoveryEvidence = ['recovery.hrv', 'recovery.subjective'];

    if (slots.isEmpty) {
      final base = recovery == RecoveryLevel.pause
          ? 'Dein Plan sieht heute frei vor – gut, denn deine Erholung ist niedrig. Schlafe ausreichend und bewege '
                'dich nur locker.'
          : 'Heute ist laut deinem Plan frei. Nutze den Tag zur Erholung; ein Spaziergang ist in Ordnung.';
      return ScheduleAdvice(
        mode: ScheduleAdviceMode.restDay,
        headline: 'Ruhetag',
        detail: '$base $tomorrow',
        move: null,
        plannedTitles: const [],
        evidenceIDs: recovery == RecoveryLevel.pause ? recoveryEvidence : const [],
      );
    }

    if (trainedToday) {
      return ScheduleAdvice(
        mode: ScheduleAdviceMode.done,
        headline: 'Geschafft',
        detail: 'Heute hast du trainiert. Jetzt gut essen und erholen. $tomorrow',
        move: null,
        plannedTitles: titles,
        evidenceIDs: const [],
      );
    }

    switch (recovery) {
      case RecoveryLevel.pause:
        if (demanding) {
          // Der Plan ist zyklisch: Ein freier Tag in der nächsten Woche liegt für diese Woche in der Vergangenheit.
          final candidate = plan.nextRestDay(weekday, within: 3);
          final target = candidate != null && candidate.rawValue > weekday.rawValue ? candidate : null;
          var detail =
              'Deine Erholung ist niedrig. Mache heute nur einen lockeren Spaziergang und hole '
              '$joined nach, sobald die Erholung wieder passt.';
          if (target != null) {
            detail =
                'Deine Erholung ist niedrig. Verschiebe $joined auf ${target.long}, deinen nächsten freien Tag, '
                'und ruhe dich heute aus.';
          }
          return ScheduleAdvice(
            mode: ScheduleAdviceMode.rest,
            headline: 'Heute besser frei',
            detail: detail,
            move: target,
            plannedTitles: titles,
            evidenceIDs: recoveryEvidence,
          );
        }
        return ScheduleAdvice(
          mode: ScheduleAdviceMode.rest,
          headline: 'Heute nur ganz locker oder frei',
          detail: 'Deine Erholung ist niedrig. Statt $joined reicht heute Bewegung im Alltag oder ein Spaziergang.',
          move: null,
          plannedTitles: titles,
          evidenceIDs: recoveryEvidence,
        );
      case RecoveryLevel.locker:
        final detail = demanding
            ? 'Deine Erholung ist nur mittel. Mache $joined heute lockerer: kürzer, ohne Tempo bzw. mit leichteren '
                  'Gewichten, und höre auf deinen Körper.'
            : 'Deine Erholung ist nur mittel. Halte $joined heute ruhig und eher kurz.';
        return ScheduleAdvice(
          mode: ScheduleAdviceMode.lighter,
          headline: 'Heute lockerer',
          detail: '$detail $tomorrow',
          move: null,
          plannedTitles: titles,
          evidenceIDs: recoveryEvidence,
        );
      case RecoveryLevel.normal:
        return ScheduleAdvice(
          mode: ScheduleAdviceMode.asPlanned,
          headline: joined,
          detail: 'Deine Erholung passt – ziehe die Einheit wie geplant durch. $tomorrow',
          move: null,
          plannedTitles: titles,
          evidenceIDs: const [],
        );
      case null:
        return ScheduleAdvice(
          mode: ScheduleAdviceMode.asPlanned,
          headline: joined,
          detail: 'Für heute liegen noch keine Garmin-Werte vor. Richte dich nach deinem Gefühl. $tomorrow',
          move: null,
          plannedTitles: titles,
          evidenceIDs: const [],
        );
    }
  }

  static String tomorrowNote(List<SessionSlot> slots, Weekday weekday) => slots.isEmpty
      ? 'Morgen (${weekday.long}) ist frei.'
      : 'Morgen (${weekday.long}): ${slots.map((slot) => slot.title).join(' + ')}.';
}

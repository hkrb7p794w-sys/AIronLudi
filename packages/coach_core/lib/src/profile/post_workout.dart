import '../analysis/session_kind.dart';
import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import 'session_match.dart';
import 'week_schedule.dart';

/// Vorschlag, den nächsten Tag zu entschärfen.
final class PostWorkoutSuggestion {
  const PostWorkoutSuggestion({required this.day, required this.text, required this.schedule});

  final CalendarDay day;
  final String text;

  /// Wochenplan der betroffenen Woche mit entschärftem Tag.
  final WeekSchedule schedule;
}

/// Auswertung nach dem Training.
final class PostWorkoutReview {
  const PostWorkoutReview({
    required this.headline,
    required this.points,
    required this.tomorrow,
    required this.evidenceIDs,
  });

  final String headline;
  final List<String> points;
  final PostWorkoutSuggestion? tomorrow;
  final List<String> evidenceIDs;
}

/// Nach dem Training: Anstrengung abfragen, gegen den Plan auswerten und – wenn nötig – den nächsten Tag
/// entschärfen. Die Regeln entscheiden; die Texte sind feste Bausteine.
abstract final class PostWorkout {
  /// Ab dieser Anstrengung (1–10, Borg CR10) gilt eine Einheit als hart.
  static const hardEffort = 7;

  /// Bis zu dieser Anstrengung als locker.
  static const easyEffort = 4;

  /// Ab hier wird der nächste Tag entschärft, wenn dort Fordernes geplant ist.
  static const veryHardEffort = 8;

  /// [tomorrowSchedule] ist der Plan der Woche, in der [tomorrow] liegt (mit Ausnahmen). [planKnown] = es gibt eine
  /// Soll/Ist-Zuordnung (persönliches Profil); im Saisonplan fehlt sie, dann kein „außerplanmäßig“.
  static PostWorkoutReview review({
    required GarminActivity activity,
    required int? effort,
    required SessionResult? planned,
    bool planKnown = true,
    required CalendarDay tomorrow,
    required WeekSchedule? tomorrowSchedule,
  }) {
    final measuredHard = SessionKind.isHard(activity) && activity.sport != ActivitySport.strength;
    final feltHard = effort != null && effort >= hardEffort;
    final feltEasy = effort != null && effort <= easyEffort;
    final points = <String>[];
    final evidence = <String>{};
    var headline = 'Gut gemacht';

    if (planned != null) {
      final slot = planned.planned.slot;
      switch (planned.status) {
        case SessionStatus.partial:
          headline = 'Kürzer als geplant';
          points.add('${planned.compareText} – zählt trotzdem; nicht am nächsten Tag dranhängen.');
        case SessionStatus.substituted:
          headline = 'Anders gemacht';
          points.add('Statt ${slot.title} – zählt für die Ausdauer, die Woche bleibt im Rahmen.');
        default:
          headline = 'Wie geplant';
          points.add('${slot.title}: ${planned.compareText}.');
      }
      if (slot.intensity == SessionIntensity.easy && (measuredHard || feltHard)) {
        points.add(
          'Für eine lockere Einheit war das hart. Locker heißt: Unterhalten geht noch. Viel lockeres Training ist '
          'die Grundlage, auf der die harten Tage wirken.',
        );
        evidence.add('intensity.distribution');
      } else if (slot.intensity == SessionIntensity.hard && !measuredHard && feltEasy) {
        points.add('Lockerer als geplant – zählt als Grundlage, die Intensität nicht nachholen.');
      }
    } else if (planKnown && activity.sport != ActivitySport.strength) {
      headline = 'Außerplanmäßig';
      points.add('Nicht im Plan – zählt für Wochenumfang und Belastung.');
    }
    final duration = activity.durationSeconds;
    if (effort != null && duration != null) {
      final minutes = (duration / 60).round();
      final load = ManualActivity.estimatedLoad(minutes: minutes, effort: effort).round();
      points.add('Anstrengung $effort/10 × $minutes min ≈ Belastung $load (session RPE).');
      evidence.add('load.rpe');
    }

    PostWorkoutSuggestion? suggestion;
    final wasHard = (effort ?? 0) >= veryHardEffort || (measuredHard && (effort ?? hardEffort) >= hardEffort);
    if (tomorrowSchedule != null && wasHard) {
      final weekday = Weekday.of(tomorrow);
      final slots = tomorrowSchedule.slots(weekday);
      if (slots.any((slot) => slot.isDemandingEndurance)) {
        final adjusted = tomorrowSchedule.withSlots([
          for (final slot in slots) slot.isDemandingEndurance ? SessionSlot(slot.sport) : slot,
        ], weekday);
        final titles = slots.where((slot) => slot.isDemandingEndurance).map((slot) => slot.title).join(', ');
        suggestion = PostWorkoutSuggestion(
          day: tomorrow,
          text:
              'Morgen (${weekday.long}) $titles locker statt fordernd – zwei harte Tage '
              'hintereinander bringen wenig und kosten Erholung.',
          schedule: adjusted,
        );
        evidence.add('intensity.distribution');
      }
    }
    return PostWorkoutReview(
      headline: headline,
      points: points,
      tomorrow: suggestion,
      evidenceIDs: evidence.toList()..sort(),
    );
  }
}

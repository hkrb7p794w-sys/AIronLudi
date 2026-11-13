import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../util/german_format.dart';
import 'gym_progression.dart';
import 'gym_session.dart';
import 'routine.dart';

/// Was vor und nach dem Training angezeigt wird: Ziel für heute, nächste Routine, Vergleich mit dem letzten Mal,
/// Trainingskalender. Die Entscheidungen bleiben bei `GymProgression` – hier wird nur verständlich formuliert.
abstract final class GymTarget {
  /// „Ziel heute: 62,5 kg × 6–10 (+2,5 kg) – letztes Mal 60 × 10/10/10“.
  static String text(ExerciseProgress progress, {required bool? recovered}) {
    final range = '${progress.target.lower}–${progress.target.upper}';
    final last = 'letztes Mal ${GermanFormat.number(progress.weightKg)} × ${progress.reps.join('/')}';
    switch (progress.status) {
      case ProgressStatus.increase when recovered != false:
        final next = progress.nextWeightKg;
        if (next == null || progress.weightKg <= 0) return 'Ziel heute: mit kleinem Zusatzgewicht starten – $last';
        final plus = GermanFormat.number(next - progress.weightKg);
        return 'Ziel heute: ${GermanFormat.number(next)} kg × $range (+$plus kg) – $last';
      case ProgressStatus.restart:
        final weight = GermanFormat.number(progress.nextWeightKg ?? progress.weightKg);
        return 'Wiedereinstieg: $weight kg × $range – $last';
      case ProgressStatus.noWeight:
        return 'Ziel heute: Haltezeit steigern';
      default:
        if (progress.weightKg <= 0) return 'Ziel heute: mehr Wiederholungen als letztes Mal ($range)';
        return 'Ziel heute: ${GermanFormat.number(progress.weightKg)} kg, mehr Wiederholungen ($range) – $last';
    }
  }
}

GymSession? _latest(Iterable<GymSession> sessions) {
  GymSession? result;
  for (final session in sessions) {
    // Swift `max(by:)` behält bei Gleichstand das erste Element.
    if (result == null || result.start.isBefore(session.start)) result = session;
  }
  return result;
}

abstract final class RoutineRotation {
  static String key(Routine routine) => 'routine-${routine.id}';

  /// Nächste Routine in der Reihenfolge nach der zuletzt trainierten (A → B → A …); ohne Verlauf die erste.
  static Routine? next({required List<Routine> routines, required List<GymSession> sessions}) {
    if (routines.isEmpty) return null;
    final keys = routines.map(key).toList();
    final last = _latest(sessions.where((session) => keys.contains(session.workoutKey ?? '')));
    final index = last == null ? -1 : keys.indexOf(last.workoutKey ?? '');
    if (index < 0) return routines.first;
    return routines[(index + 1) % routines.length];
  }

  /// Grobe Dauer: je Satz 40 s Arbeit plus Pause, auf 5 Minuten gerundet.
  static int estimatedMinutes(Routine routine) {
    final seconds = routine.items.fold(0, (sum, item) => sum + item.sets * (40 + item.restSeconds));
    return math.max(5, (seconds / 60 / 5).round() * 5);
  }
}

abstract final class SessionComparison {
  /// Letzte frühere Einheit derselben Routine bzw. desselben Plans.
  static GymSession? previous(GymSession session, {required List<GymSession> sessions}) {
    final key = session.workoutKey;
    if (key == null) return null;
    return _latest(
      sessions.where(
        (other) => other.id != session.id && other.workoutKey == key && other.start.isBefore(session.start),
      ),
    );
  }

  /// Volumen gegenüber der letzten gleichen Einheit in Prozent (gerundet), `null` ohne Vergleich.
  static int? volumeChangePercent(GymSession session, {required GymSession? previous}) {
    if (previous == null || previous.volumeKg <= 0) return null;
    return ((session.volumeKg / previous.volumeKg - 1) * 100).round();
  }
}

/// Einheiten in einer Kalenderwoche.
final class GymCalendarWeek {
  const GymCalendarWeek({required this.monday, required this.sessions});

  final CalendarDay monday;
  final int sessions;

  CalendarDay get id => monday;

  @override
  bool operator ==(Object other) => other is GymCalendarWeek && other.monday == monday && other.sessions == sessions;

  @override
  int get hashCode => Object.hash(monday, sessions);

  @override
  String toString() => 'GymCalendarWeek($monday, $sessions)';
}

/// Trainingskalender: Einheiten je Woche und Serie (Wochen in Folge mit mindestens einer Einheit).
abstract final class GymCalendar {
  /// Die letzten [count] Wochen, älteste zuerst.
  static List<GymCalendarWeek> weeks({required List<GymSession> sessions, required CalendarDay today, int count = 8}) {
    final monday = today.adding(-today.weekdayIndex);
    final days = sessions.map((session) => session.day).toSet();
    return [
      for (var offset = count - 1; offset >= 0; offset--)
        () {
          final start = monday.adding(-7 * offset);
          final end = start.adding(6);
          return GymCalendarWeek(monday: start, sessions: days.where((day) => start <= day && day <= end).length);
        }(),
    ];
  }

  /// Wochen in Folge mit Training; die laufende Woche zählt erst, wenn sie eine Einheit hat.
  static int streak({required List<GymSession> sessions, required CalendarDay today}) {
    final all = weeks(sessions: sessions, today: today, count: 104);
    if (all.isNotEmpty && all.last.sessions == 0) all.removeLast();
    var count = 0;
    for (final week in all.reversed) {
      if (week.sessions <= 0) break;
      count += 1;
    }
    return count;
  }
}

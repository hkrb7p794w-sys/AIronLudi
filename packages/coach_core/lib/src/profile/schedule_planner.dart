import 'dart:math' as math;

import 'personalization.dart';
import 'schedule_check.dart';
import 'user_profile.dart';
import 'week_schedule.dart';

/// Schlägt einen Wochenplan vor: Wie viele Einheiten je Sportart zum Ziel passen und auf welche der verfügbaren
/// Tage sie sich am besten verteilen. Alles ist ein Vorschlag, den man in der App frei ändern kann.
abstract final class SchedulePlanner {
  /// Gewünschte Anzahl Einheiten je Sportart aus Ziel, Wettkampf und Erfahrung (vor dem Kürzen auf die Tage).
  static Map<TrainingSport, int> wantedCounts(UserProfile profile) {
    var wanted = <TrainingSport, int>{};
    // Jede Sportart nach ihrer eigenen Erfahrung: Erfahrung im Gym macht niemanden zum geübten Läufer.
    final runLevel = profile.level(TrainingSport.run);
    void want(TrainingSport sport, int count) {
      if (profile.trains(sport)) wanted[sport] = count;
    }

    switch (profile.goal) {
      case FitnessGoal.loseWeight:
        want(TrainingSport.strength, 2);
        want(TrainingSport.run, 3);
        want(TrainingSport.bike, 2);
        want(TrainingSport.swim, 2);
      case FitnessGoal.loseAndBuild:
        want(TrainingSport.strength, 3);
        want(TrainingSport.run, 2);
        want(TrainingSport.bike, 1);
        want(TrainingSport.swim, 1);
      case FitnessGoal.buildMuscle:
        want(TrainingSport.strength, profile.level(TrainingSport.strength) == ExperienceLevel.beginner ? 3 : 4);
        want(TrainingSport.run, 1);
        want(TrainingSport.bike, 1);
        want(TrainingSport.swim, 1);
      case FitnessGoal.gainWeight:
        want(TrainingSport.strength, 3);
        want(TrainingSport.run, 1);
        want(TrainingSport.bike, 1);
        want(TrainingSport.swim, 1);
      case FitnessGoal.improveFitness:
        want(TrainingSport.run, 3);
        want(TrainingSport.bike, 2);
        want(TrainingSport.swim, 2);
        want(TrainingSport.strength, 2);
      case FitnessGoal.maintain:
        want(TrainingSport.run, 2);
        want(TrainingSport.bike, 1);
        want(TrainingSport.swim, 1);
        want(TrainingSport.strength, 2);
    }
    want(TrainingSport.other, 1);

    if (profile.event case final event?) {
      switch (event.kind) {
        case EventKind.marathon:
          want(TrainingSport.run, runLevel == ExperienceLevel.beginner ? 3 : 4);
        case EventKind.halfMarathon || EventKind.run10k:
          want(TrainingSport.run, 3);
        case EventKind.run5k:
          want(TrainingSport.run, runLevel == ExperienceLevel.beginner ? 2 : 3);
        case EventKind.triathlon:
          want(TrainingSport.swim, 2);
          want(TrainingSport.bike, 2);
          want(TrainingSport.run, 2);
        case EventKind.other:
          break;
      }
      if (profile.trains(TrainingSport.strength)) {
        wanted[TrainingSport.strength] = math.min(wanted[TrainingSport.strength] ?? 2, 2);
      }
    }

    // Festgelegte Haupt- und Nebenziele (Paket 6) verschieben die Gewichte, z. B. mehr Kraft bei Muskelaufbau.
    if (profile.goals case final goals?) {
      wanted = Personalization.adjustCounts(wanted, goals: goals, profile: profile);
    }

    // Einsteiger:innen starten mit weniger Einheiten je Sportart.
    for (final sport in TrainingSport.values) {
      if (!sport.isEndurance || profile.level(sport) != ExperienceLevel.beginner) continue;
      if (wanted[sport] case final count?) wanted[sport] = math.min(count, 3);
    }
    return wanted;
  }

  /// Sportarten in der Reihenfolge ihrer Wichtigkeit für das Ziel (zuerst kürzen, was hinten steht).
  static List<TrainingSport> priority(UserProfile profile) {
    const strengthFirst = [
      TrainingSport.strength,
      TrainingSport.run,
      TrainingSport.bike,
      TrainingSport.swim,
      TrainingSport.other,
    ];
    const enduranceFirst = [
      TrainingSport.run,
      TrainingSport.bike,
      TrainingSport.swim,
      TrainingSport.strength,
      TrainingSport.other,
    ];
    const runFirst = [
      TrainingSport.run,
      TrainingSport.strength,
      TrainingSport.bike,
      TrainingSport.swim,
      TrainingSport.other,
    ];
    if (profile.event case final event?) {
      switch (event.kind) {
        case EventKind.triathlon:
          return enduranceFirst;
        case EventKind.marathon || EventKind.halfMarathon || EventKind.run10k || EventKind.run5k:
          return runFirst;
        case EventKind.other:
          break;
      }
    }
    if (profile.goals case final goals?) {
      switch (goals.primary) {
        case TrainingGoal.muscleGain || TrainingGoal.strength:
          return strengthFirst;
        case TrainingGoal.endurance:
          return enduranceFirst;
        default:
          break;
      }
    }
    return switch (profile.goal) {
      FitnessGoal.buildMuscle || FitnessGoal.gainWeight || FitnessGoal.loseAndBuild => strengthFirst,
      FitnessGoal.loseWeight || FitnessGoal.improveFitness || FitnessGoal.maintain => runFirst,
    };
  }

  /// Höchstens so viele Einheiten pro Woche, dass mindestens ein Tag frei bleibt.
  static const maxSessionsPerWeek = 6;

  /// Untergrenze je Sportart beim Kürzen: Kernsportarten eines Wettkampfs bleiben möglichst erhalten.
  static int minimumCount(TrainingSport sport, UserProfile profile) {
    final event = profile.event;
    if (event == null) return 1;
    return switch (event.kind) {
      EventKind.triathlon => sport.isEndurance ? 2 : 1,
      EventKind.marathon || EventKind.halfMarathon => sport == TrainingSport.run ? 3 : 1,
      EventKind.run10k || EventKind.run5k => sport == TrainingSport.run ? 2 : 1,
      EventKind.other => 1,
    };
  }

  /// Einheiten mit Intensität für [dayCount] verfügbare Tage.
  static List<SessionSlot> sessions(UserProfile profile, {required int dayCount}) {
    final counts = wantedCounts(profile);
    final order = priority(profile);
    final capacity = math.min(dayCount, maxSessionsPerWeek);
    int total() => counts.values.fold(0, (sum, count) => sum + count);
    TrainingSport? firstWhere(bool Function(TrainingSport sport) test) {
      for (final sport in order.reversed) {
        if (test(sport)) return sport;
      }
      return null;
    }

    // Kürzen: erst die unwichtigste Sportart über ihrer Untergrenze, dann Sportarten ohne Wettkampfbezug.
    // Kernsportarten eines Wettkampfs werden nur verringert, damit auch mit wenig Zeit ein sinnvoller Plan bleibt.
    while (total() > capacity) {
      bool core(TrainingSport sport) => minimumCount(sport, profile) > 1;
      final above = firstWhere((sport) => (counts[sport] ?? 0) > minimumCount(sport, profile));
      if (above != null) {
        counts[above] = (counts[above] ?? 0) - 1;
        continue;
      }
      final optional = firstWhere((sport) => (counts[sport] ?? 0) > 0 && !core(sport));
      if (optional != null) {
        counts.remove(optional);
        continue;
      }
      final most = counts.values.isEmpty ? null : counts.values.reduce(math.max);
      final largest = most != null && most > 1 ? firstWhere((sport) => counts[sport] == most) : null;
      if (largest != null) {
        counts[largest] = most! - 1;
        continue;
      }
      final any = firstWhere((sport) => (counts[sport] ?? 0) > 0);
      if (any == null) break;
      counts.remove(any);
    }

    final needsLongRun =
        profile.event != null &&
        (profile.event!.kind == EventKind.marathon || profile.event!.kind == EventKind.halfMarathon);
    final result = <SessionSlot>[];
    for (final sport in order) {
      final count = counts[sport] ?? 0;
      if (count <= 0) continue;
      if (sport.isEndurance) {
        final intensities = enduranceIntensities(
          count,
          level: profile.level(sport),
          longRun: needsLongRun && sport == TrainingSport.run,
        );
        result.addAll(intensities.map((intensity) => SessionSlot(sport, intensity)));
      } else if (sport == TrainingSport.strength) {
        result.addAll(List.filled(count, const SessionSlot(TrainingSport.strength, SessionIntensity.hard)));
      } else {
        result.addAll(List.filled(count, SessionSlot(sport)));
      }
    }
    return result;
  }

  /// Intensitäten für [count] Einheiten einer Ausdauersportart: überwiegend locker, höchstens eine intensive,
  /// eine lange. Einsteiger:innen laufen locker; eine lange Einheit nur, wenn der Wettkampf sie braucht.
  static List<SessionIntensity> enduranceIntensities(
    int count, {
    required ExperienceLevel level,
    required bool longRun,
  }) {
    const easy = SessionIntensity.easy;
    const hard = SessionIntensity.hard;
    const long = SessionIntensity.long;
    final beginner = level == ExperienceLevel.beginner;
    return switch (count) {
      1 => [easy],
      2 when beginner => longRun ? [easy, long] : [easy, easy],
      2 => [easy, long],
      3 when beginner => longRun ? [easy, easy, long] : [easy, easy, easy],
      3 => [easy, hard, long],
      _ when beginner => padded([easy, easy, easy, long], count),
      _ => padded([easy, hard, easy, long], count),
    };
  }

  /// Füllt eine Liste mit lockeren Einheiten auf [count] auf.
  static List<SessionIntensity> padded(List<SessionIntensity> base, int count) => [
    ...base,
    ...List.filled(math.max(0, count - base.length), SessionIntensity.easy),
  ];

  /// Verteilt die Einheiten so auf die verfügbaren Tage, dass die Regeln der Wochenprüfung möglichst wenig
  /// verletzt werden. Bei Gleichstand gewinnt die erste Möglichkeit (deterministisch).
  static WeekSchedule suggest({required UserProfile profile, required List<Weekday> availableDays}) {
    final days = availableDays.toSet().toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue));
    final planned = sessions(profile, dayCount: days.length);
    if (planned.isEmpty || days.isEmpty) return WeekSchedule();

    var best = WeekSchedule();
    var bestScore = 1 << 62;
    final used = List.filled(days.length, false);
    final assignment = List.filled(planned.length, 0);

    void evaluate() {
      var schedule = WeekSchedule();
      for (var sessionIndex = 0; sessionIndex < assignment.length; sessionIndex++) {
        final weekday = days[assignment[sessionIndex]];
        schedule = schedule.withSlots([...schedule.slots(weekday), planned[sessionIndex]], weekday);
      }
      final score = ScheduleCheck.penalty(schedule, profile) + preferencePenalty(schedule);
      if (score < bestScore) {
        bestScore = score;
        best = schedule;
      }
    }

    void place(int sessionIndex) {
      if (sessionIndex == planned.length) {
        evaluate();
        return;
      }
      for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
        if (used[dayIndex]) continue;
        used[dayIndex] = true;
        assignment[sessionIndex] = dayIndex;
        place(sessionIndex + 1);
        used[dayIndex] = false;
      }
    }

    place(0);
    return best;
  }

  /// Weiche Vorlieben: lange Einheiten am Wochenende, gleiche Sportart nicht an zwei Tagen hintereinander.
  static int preferencePenalty(WeekSchedule schedule) {
    var penalty = 0;
    for (final weekday in Weekday.values) {
      final slots = schedule.slots(weekday);
      if (slots.any((slot) => slot.intensity == SessionIntensity.long) &&
          weekday != Weekday.saturday &&
          weekday != Weekday.sunday) {
        penalty += 1;
      }
      for (final sport in TrainingSport.values) {
        if (sport == TrainingSport.other) continue;
        final today = slots.any((slot) => slot.sport == sport);
        final tomorrow = schedule.slots(weekday.next).any((slot) => slot.sport == sport);
        if (today && tomorrow) penalty += 1;
      }
    }
    return penalty;
  }
}

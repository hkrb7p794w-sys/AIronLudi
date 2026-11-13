import 'package:collection/collection.dart';

import 'user_profile.dart';
import 'week_schedule.dart';

enum HintSeverity {
  info,
  tip,
  warning;

  /// Gewicht für die Bewertung von Planvorschlägen.
  int get penalty => switch (this) {
    info => 0,
    tip => 3,
    warning => 10,
  };
}

/// Hinweis zum Wochenplan. Hinweise ohne [evidenceIDs] sind Praxisregeln und so gekennzeichnet.
final class ScheduleHint {
  const ScheduleHint({required this.id, required this.severity, required this.message, this.evidenceIDs = const []});

  final String id;
  final HintSeverity severity;
  final String message;
  final List<String> evidenceIDs;

  bool get isPracticeRule => evidenceIDs.isEmpty;

  @override
  String toString() => 'ScheduleHint($id)';
}

/// Prüft, ob der selbst gewählte Wochenplan zu Ziel und Erfahrung passt, und erklärt Auffälligkeiten.
abstract final class ScheduleCheck {
  static List<ScheduleHint> hints(WeekSchedule schedule, UserProfile profile) {
    final hints = <ScheduleHint>[];
    void add(String id, HintSeverity severity, String message, [List<String> evidence = const []]) =>
        hints.add(ScheduleHint(id: id, severity: severity, message: message, evidenceIDs: evidence));

    if (schedule.isEmpty) {
      add('empty', HintSeverity.info, 'Noch keine Einheiten eingetragen. Wähle, an welchen Tagen du was trainierst.');
      return hints;
    }
    final level = overallLevel(profile);
    final endurance = schedule.days.expand((day) => day).where((slot) => slot.sport.isEndurance).toList();
    final hardEndurance = endurance.where((slot) => slot.intensity == SessionIntensity.hard).length;

    // Ruhetage und Trainingsserien.
    if (schedule.restDays.isEmpty) {
      add(
        'rest',
        HintSeverity.warning,
        'Du trainierst an allen sieben Tagen. Plane mindestens einen freien Tag ein, damit sich dein Körper anpassen '
            'kann.',
      );
    } else {
      final limit = level == ExperienceLevel.beginner ? 3 : 5;
      if (schedule.longestStreak > limit) {
        add(
          'streak',
          HintSeverity.tip,
          '${schedule.longestStreak} Trainingstage hintereinander. '
              '${level == ExperienceLevel.beginner ? 'Zum Einstieg ist ein freier Tag nach spätestens drei Tagen besser.' : 'Ein freier oder sehr lockerer Tag dazwischen hilft der Erholung.'}',
        );
      }
    }

    // Zwei fordernde Ausdauertage direkt hintereinander.
    for (final weekday in Weekday.values) {
      final next = weekday.next;
      if (schedule.slots(weekday).any((slot) => slot.isDemandingEndurance) &&
          schedule.slots(next).any((slot) => slot.isDemandingEndurance)) {
        add(
          'back-to-back-${weekday.index}',
          HintSeverity.warning,
          '${weekday.long} und ${next.long}: zwei lange oder intensive Ausdauereinheiten direkt hintereinander. '
              'Lege einen lockeren oder freien Tag dazwischen.',
          ['intensity.distribution'],
        );
      }
    }

    // Intensitätsverteilung.
    if (endurance.length >= 3 && hardEndurance * 3 > endurance.length) {
      add(
        'hard-share',
        HintSeverity.tip,
        'Mehr als ein Drittel deiner Ausdauereinheiten ist intensiv. Die meisten (rund 80 %) sollten locker sein.',
        ['intensity.distribution'],
      );
    }

    // Je Sportart: Erfahrung im Gym ändert nichts an der Belastbarkeit beim Laufen.
    if (endurance
            .where(
              (slot) =>
                  slot.intensity == SessionIntensity.hard && profile.level(slot.sport) == ExperienceLevel.beginner,
            )
            .length >=
        2) {
      add(
        'beginner-hard',
        HintSeverity.tip,
        'Zum Einstieg genügt höchstens eine intensive Einheit pro Woche. Baue zuerst eine lockere Grundlage auf.',
      );
    }

    // Gewählte Sportarten ohne Termin.
    for (final sport in profile.sports.where((sport) => schedule.count(sport) == 0)) {
      add(
        'missing-${sport.rawValue}',
        HintSeverity.info,
        'Du hast ${sport.label} gewählt, aber noch keinen Tag dafür eingeplant.',
      );
    }

    // Krafttraining.
    final strength = schedule.count(TrainingSport.strength);
    if (profile.trains(TrainingSport.strength)) {
      final buildsMuscle =
          profile.goal == FitnessGoal.buildMuscle ||
          profile.goal == FitnessGoal.loseAndBuild ||
          profile.goal == FitnessGoal.gainWeight;
      if (buildsMuscle && strength == 1) {
        add(
          'strength-frequency',
          HintSeverity.tip,
          'Für Muskelaufbau sind mindestens zwei Krafttage pro Woche sinnvoll: So verteilst du die Sätze je Muskel.',
          ['gym.volume'],
        );
      }
      if (profile.goal == FitnessGoal.loseWeight && strength == 0) {
        add(
          'strength-for-loss',
          HintSeverity.tip,
          'Krafttraining nimmt kaum zusätzlich ab, hilft aber, beim Abnehmen Muskelmasse zu behalten.',
          ['weightloss.exercise'],
        );
      }
      if (strength > 4) {
        add(
          'strength-many',
          HintSeverity.info,
          'Mehr als vier Krafttage: Achte darauf, dieselben Muskeln nicht an aufeinanderfolgenden Tagen schwer zu '
              'belasten.',
        );
      }
    }

    // Schweres Krafttraining am Vortag einer langen oder intensiven Laufeinheit.
    for (final weekday in Weekday.values) {
      final heavyStrength = schedule
          .slots(weekday)
          .any((slot) => slot.sport == TrainingSport.strength && slot.intensity != SessionIntensity.easy);
      final hardRunNext = schedule
          .slots(weekday.next)
          .any((slot) => slot.sport == TrainingSport.run && slot.intensity.isDemanding);
      if (heavyStrength && hardRunNext) {
        add(
          'strength-before-run-${weekday.index}',
          HintSeverity.tip,
          'Schweres Krafttraining am ${weekday.long}, danach am ${weekday.next.long} ein langer oder intensiver Lauf: '
              'Die Beine sind oft noch müde. Wenn möglich, tausche die Reihenfolge.',
        );
      }
    }

    // Wettkampfvorbereitung.
    final event = profile.event;
    if (event != null && event.kind.isRunning && profile.trains(TrainingSport.run)) {
      final isLong = event.kind == EventKind.marathon || event.kind == EventKind.halfMarathon;
      final required = isLong ? 3 : 2;
      final runs = schedule.count(TrainingSport.run);
      if (runs < required) {
        add(
          'event-run-days',
          HintSeverity.tip,
          'Für ${event.kind.label} sind mindestens $required Lauftage pro Woche sinnvoll. Aktuell: $runs.',
        );
      }
      final hasLongRun = schedule.days
          .expand((day) => day)
          .any((slot) => slot.sport == TrainingSport.run && slot.intensity == SessionIntensity.long);
      if (isLong && !hasLongRun) {
        add('event-long-run', HintSeverity.tip, 'Plane einmal pro Woche einen langen, lockeren Lauf ein.');
      }
    }

    // Fitness und Ruhepuls.
    final aimsAtEndurance = profile.goal == FitnessGoal.improveFitness || profile.targets.restingHeartRate != null;
    if (aimsAtEndurance && profile.sports.any((sport) => sport.isEndurance) && endurance.length < 2) {
      add(
        'endurance-frequency',
        HintSeverity.tip,
        'Für bessere Fitness und einen niedrigeren Ruhepuls zählt regelmäßiges Ausdauertraining: besser mindestens '
            'zwei Einheiten pro Woche.',
        ['rhr.endurance'],
      );
    }
    if (schedule.sessionCount < 3) {
      add(
        'who-minimum',
        HintSeverity.info,
        'Die WHO empfiehlt 150–300 Minuten moderate Bewegung pro Woche. Mit weniger als drei Einheiten wird das knapp.',
        ['activity.who'],
      );
    }
    // Stabil nach Schwere sortieren (wichtigste zuerst), sonst in der Reihenfolge der Prüfungen.
    mergeSort(hints, compare: (a, b) => b.severity.index.compareTo(a.severity.index));
    return hints;
  }

  /// Bewertung eines Plans (kleiner ist besser), für den Planvorschlag.
  static int penalty(WeekSchedule schedule, UserProfile profile) =>
      hints(schedule, profile).fold(0, (sum, hint) => sum + hint.severity.penalty);

  static ExperienceLevel overallLevel(UserProfile profile) =>
      maxBy(profile.sports.map(profile.level), (ExperienceLevel level) => level.index) ?? ExperienceLevel.beginner;
}

import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../util/enum_codec.dart';
import '../util/int_range.dart';
import 'exercise_catalog.dart';

/// Eine geplante Übung im Trainingsplan.
final class PlannedExercise {
  PlannedExercise({
    required this.name,
    required this.garmin,
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.restSeconds,
  });

  String name;

  /// Garmin-Kategorie und -Übung („KATEGORIE (ÜBUNG)“) – Grundlage der Zuordnung zur kanonischen Übung.
  String garmin;
  int sets;

  /// Ziel-Wiederholungen (Obergrenze des Bereichs); `null` bei Haltübungen.
  int? reps;

  /// Startgewicht laut Plan; `null` = Körpergewicht.
  double? weightKg;
  int restSeconds;

  String get id => name;

  ExerciseRule get rule => ExerciseCatalog.classify(garmin, hasWeight: (weightKg ?? 0) > 0);

  /// Zielbereich aus dem Plan: (Plan-Wdh. − 4) bis Plan-Wdh., wie `plan_rep_ranges` im Altbestand.
  IntRange? get planRepRange => switch (reps) {
    final reps? => IntRange(math.max(1, reps - 4), math.max(reps, math.max(1, reps - 4))),
    null => null,
  };

  PlannedExercise copy() =>
      PlannedExercise(name: name, garmin: garmin, sets: sets, reps: reps, weightKg: weightKg, restSeconds: restSeconds);

  Map<String, Object?> toJson() => {
    'name': name,
    'garmin': garmin,
    'sets': sets,
    'reps': ?reps,
    'weightKg': ?weightKg,
    'restSeconds': restSeconds,
  };

  static PlannedExercise? fromJson(Object? json) {
    if (json is! Map) return null;
    final (name, garmin, sets, rest) = (json['name'], json['garmin'], json['sets'], json['restSeconds']);
    if (name is! String || garmin is! String || sets is! int || rest is! int) return null;
    return PlannedExercise(
      name: name,
      garmin: garmin,
      sets: sets,
      reps: json['reps'] is int ? json['reps'] as int : null,
      weightKg: jsonDouble(json['weightKg']),
      restSeconds: rest,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlannedExercise &&
      other.name == name &&
      other.garmin == garmin &&
      other.sets == sets &&
      other.reps == reps &&
      other.weightKg == weightKg &&
      other.restSeconds == restSeconds;

  @override
  int get hashCode => Object.hash(name, garmin, sets, reps, weightKg, restSeconds);
}

/// Eine Trainingseinheit des Plans (z. B. „Push A“).
final class Workout {
  Workout({required this.key, required this.name, required this.note, required this.exercises});

  String key;
  String name;
  String note;
  List<PlannedExercise> exercises;

  String get id => key;

  Workout copy() =>
      Workout(key: key, name: name, note: note, exercises: [for (final exercise in exercises) exercise.copy()]);

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'note': note,
    'exercises': [for (final exercise in exercises) exercise.toJson()],
  };

  static Workout? fromJson(Object? json) {
    if (json is! Map) return null;
    final (key, name, note) = (json['key'], json['name'], json['note']);
    final exercises = listStrict(json['exercises'], PlannedExercise.fromJson);
    if (key is! String || name is! String || note is! String || exercises == null) return null;
    return Workout(key: key, name: name, note: note, exercises: exercises);
  }

  @override
  bool operator ==(Object other) =>
      other is Workout &&
      other.key == key &&
      other.name == name &&
      other.note == note &&
      other.exercises.length == exercises.length &&
      [for (var index = 0; index < exercises.length; index++) other.exercises[index] == exercises[index]]
          .every((x) => x);

  @override
  int get hashCode => Object.hash(key, name, note, Object.hashAll(exercises));

  @override
  String toString() => 'Workout($key)';
}

/// Trainingsplan mit Wochentagen (`gym_plan.json` im Altbestand).
final class GymPlan {
  GymPlan({required this.workouts, required this.schedule, required this.flex});

  List<Workout> workouts;

  /// Wochentag (0 = Montag) → Einheit.
  Map<int, String> schedule;

  /// Flexible Einheiten: Schlüssel → mögliche Wochentage (erster freier Tag zählt).
  Map<String, List<int>> flex;

  Workout? workout(String key) {
    for (final workout in workouts) {
      if (workout.key == key) return workout;
    }
    return null;
  }

  /// Zielbereiche je kanonischer Übung aus dem Plan.
  Map<String, IntRange> get repRanges {
    final ranges = <String, IntRange>{};
    for (final exercise in workouts.expand((workout) => workout.exercises)) {
      if (exercise.planRepRange case final range?) ranges[exercise.rule.id] = range;
    }
    return ranges;
  }

  /// Geplante Einheiten einer Woche wie `planned_days` im Altbestand: Flexible Einheiten (Lower Di/Do) landen am
  /// ersten noch möglichen Tag und entfallen, wenn an einem ihrer Tage schon Kraft geloggt ist.
  Map<CalendarDay, String> plannedDays({
    required CalendarDay monday,
    required CalendarDay today,
    required Set<CalendarDay> doneDays,
  }) {
    final days = <CalendarDay, String>{};
    for (final MapEntry(key: weekday, value: key) in schedule.entries) {
      if (flex[key] == null) days[monday.adding(weekday)] = key;
    }
    for (final MapEntry(key: key, value: options) in flex.entries) {
      final candidates = ([...options]..sort()).map(monday.adding).toList();
      if (candidates.any(doneDays.contains)) continue;
      for (final day in candidates) {
        if (day >= today) {
          days[day] = key;
          break;
        }
      }
    }
    return days;
  }

  /// JSON wie Swift: Wörterbücher mit `Int`-Schlüsseln werden als Liste [Schlüssel, Wert, …] kodiert.
  Map<String, Object?> toJson() => {
    'workouts': [for (final workout in workouts) workout.toJson()],
    'schedule': [
      for (final entry in schedule.entries) ...[entry.key, entry.value],
    ],
    'flex': {for (final entry in flex.entries) entry.key: entry.value},
  };

  static GymPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    final workouts = listStrict(json['workouts'], Workout.fromJson);
    final rawSchedule = json['schedule'];
    final rawFlex = json['flex'];
    if (workouts == null || rawFlex is! Map) return null;
    final schedule = <int, String>{};
    if (rawSchedule is List && rawSchedule.length.isEven) {
      for (var index = 0; index < rawSchedule.length; index += 2) {
        final (key, value) = (rawSchedule[index], rawSchedule[index + 1]);
        if (key is! int || value is! String) return null;
        schedule[key] = value;
      }
    } else if (rawSchedule is Map) {
      // Swift kodiert `[Int: String]` mit String-Schlüsseln als Objekt, wenn es so geschrieben wurde.
      for (final entry in rawSchedule.entries) {
        final key = int.tryParse('${entry.key}');
        if (key == null || entry.value is! String) return null;
        schedule[key] = entry.value as String;
      }
    } else {
      return null;
    }
    final flex = <String, List<int>>{};
    for (final entry in rawFlex.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! List || !value.every((day) => day is int)) return null;
      flex[entry.key as String] = value.cast<int>();
    }
    return GymPlan(workouts: workouts, schedule: schedule, flex: flex);
  }

  // dart format off
  /// Neu erzeugt bei jedem Zugriff (Werttyp in Swift).
  static GymPlan get standard => GymPlan(
    workouts: [
      Workout(
        key: 'push',
        name: 'Push A',
        note: 'Home-Gym · nur Wiederholungen anpassen',
        exercises: [
          PlannedExercise(name: 'Flyings am hohen Kabel', garmin: 'FLYE (CABLE_CROSSOVER)', sets: 2, reps: 12, weightKg: 22.5, restSeconds: 90),
          PlannedExercise(name: 'Armstrecken am tiefen Kabel auf Schrägbank', garmin: 'TRICEPS_EXTENSION (CABLE_OVERHEAD_TRICEPS_EXTENSION)', sets: 2, reps: 12, weightKg: 32.5, restSeconds: 90),
          PlannedExercise(name: 'Bankdrücken mit Langhantel', garmin: 'BENCH_PRESS (BARBELL_BENCH_PRESS)', sets: 2, reps: 12, weightKg: 52.5, restSeconds: 120),
          PlannedExercise(name: 'Einarmiges Seitwärtsheben am tiefen Kabel', garmin: 'LATERAL_RAISE (ONE_ARM_CABLE_LATERAL_RAISE)', sets: 2, reps: 12, weightKg: 13.75, restSeconds: 90),
          PlannedExercise(name: 'Dips am Barren', garmin: 'TRICEPS_EXTENSION (BODY_WEIGHT_DIP)', sets: 2, reps: 12, weightKg: null, restSeconds: 90),
          PlannedExercise(name: 'Planks', garmin: 'PLANK (PLANK)', sets: 2, reps: null, weightKg: null, restSeconds: 60),
        ],
      ),
      Workout(
        key: 'pull',
        name: 'Pull A',
        note: 'Home-Gym · nur Wiederholungen anpassen',
        exercises: [
          PlannedExercise(name: 'Enges Rudern am Kabel sitzend', garmin: 'ROW (V_GRIP_CABLE_ROW)', sets: 2, reps: 12, weightKg: 110, restSeconds: 120),
          PlannedExercise(name: 'Curls am Kabel liegend', garmin: 'CURL (CABLE_BICEPS_CURL)', sets: 2, reps: 12, weightKg: 50, restSeconds: 90),
          PlannedExercise(name: 'Einarmiges Lat-Ziehen', garmin: 'PULL_UP (_30_DEGREE_LAT_PULLDOWN)', sets: 2, reps: 12, weightKg: 52.5, restSeconds: 90),
          PlannedExercise(name: 'Curls in Hammerhaltung am Kabel', garmin: 'CURL (CABLE_HAMMER_CURL)', sets: 2, reps: 12, weightKg: 22.5, restSeconds: 90),
          PlannedExercise(name: 'Face-Pulls am Kabel sitzend', garmin: 'ROW (FACE_PULL)', sets: 2, reps: 12, weightKg: 45, restSeconds: 90),
          PlannedExercise(name: 'Crunches am Kabel kniend', garmin: 'CRUNCH (KNEELING_CABLE_CRUNCH)', sets: 2, reps: 12, weightKg: 65, restSeconds: 60),
        ],
      ),
      Workout(
        key: 'pp',
        name: 'Push & Pull B',
        note: 'Home-Gym · nur Wiederholungen anpassen',
        exercises: [
          PlannedExercise(name: 'Curls in Hammerhaltung am Kabel', garmin: 'CURL (CABLE_HAMMER_CURL)', sets: 2, reps: 12, weightKg: 22.5, restSeconds: 90),
          PlannedExercise(name: 'Armstrecken am tiefen Kabel auf Schrägbank', garmin: 'TRICEPS_EXTENSION (CABLE_OVERHEAD_TRICEPS_EXTENSION)', sets: 2, reps: 12, weightKg: 32.5, restSeconds: 90),
          PlannedExercise(name: 'Lat-Ziehen mit breitem Griff', garmin: 'PULL_UP (WIDE_GRIP_LAT_PULLDOWN)', sets: 2, reps: 12, weightKg: 85, restSeconds: 120),
          PlannedExercise(name: 'Bankdrücken mit Langhantel', garmin: 'BENCH_PRESS (BARBELL_BENCH_PRESS)', sets: 2, reps: 12, weightKg: 52.5, restSeconds: 120),
          PlannedExercise(name: 'Reverse-Flyings am hohen Kabel', garmin: 'FLYE (SINGLE_ARM_STANDING_CABLE_REVERSE_FLYE)', sets: 2, reps: 12, weightKg: 7.5, restSeconds: 90),
          PlannedExercise(name: 'Dips am Barren', garmin: 'TRICEPS_EXTENSION (BODY_WEIGHT_DIP)', sets: 2, reps: 12, weightKg: null, restSeconds: 90),
        ],
      ),
      Workout(
        key: 'legs',
        name: 'Lower',
        note: 'nur Wiederholungen anpassen',
        exercises: [
          PlannedExercise(name: 'Beinbeugen sitzend', garmin: 'LEG_CURL (LEG_CURL)', sets: 2, reps: 12, weightKg: 110, restSeconds: 90),
          PlannedExercise(name: 'Beinstrecken', garmin: 'BANDED_EXERCISES (LEG_EXTENSION)', sets: 2, reps: 12, weightKg: 120, restSeconds: 90),
          PlannedExercise(name: 'Beinpressen sitzend', garmin: 'SQUAT (LEG_PRESS)', sets: 2, reps: 12, weightKg: 149, restSeconds: 120),
          PlannedExercise(name: 'Fersenheben am Gerät stehend', garmin: 'CALF_RAISE (WEIGHTED_STANDING_CALF_RAISE)', sets: 2, reps: 12, weightKg: 117, restSeconds: 90),
          PlannedExercise(name: 'Crunches am Gerät', garmin: 'CRUNCH (WEIGHTED_CRUNCH)', sets: 2, reps: 12, weightKg: 90, restSeconds: 60),
        ],
      ),
    ],
    schedule: {0: 'push', 1: 'legs', 2: 'pull', 4: 'pp'},
    flex: {'legs': [1, 3]},
  );
  // dart format on
}

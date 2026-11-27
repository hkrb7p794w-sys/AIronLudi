import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gym_book_import.dart';
import 'gym_session.dart';

/// Ein abgelesener Satz: Wiederholungen oder Sekunden (Haltübungen) und Gewicht in kg (0 = Körpergewicht).
final class ImportedSet {
  const ImportedSet({this.reps, this.seconds, this.weightKg = 0});

  final int? reps;
  final int? seconds;
  final double weightKg;

  bool get isTimed => (reps ?? 0) <= 0 && (seconds ?? 0) > 0;
}

/// Eine abgelesene Übung; [id] nur, wenn die KI sie einer Übung der Bibliothek zugeordnet hat.
final class ImportedExercise {
  const ImportedExercise({required this.name, this.id, this.group, required this.sets});

  final String name;
  final String? id;

  /// Muskelgruppe laut KI für Übungen ohne [id].
  final MuscleGroup? group;
  final List<ImportedSet> sets;
}

/// Antwort der Worker-Aufgabe `gym_import`: Krafttraining von Screenshots einer anderen App (WHOOP Strength Trainer,
/// Hevy, Strong …). Datum und Uhrzeit nur, wenn sie auf dem Bild standen.
final class ImportedWorkout {
  const ImportedWorkout({
    this.title = '',
    this.day,
    this.month,
    this.year,
    this.startMinutes,
    this.endMinutes,
    required this.exercises,
  });

  final String title;
  final int? day;
  final int? month;
  final int? year;

  /// Uhrzeit von Beginn und Ende in Minuten ab Mitternacht.
  final int? startMinutes;
  final int? endMinutes;
  final List<ImportedExercise> exercises;

  int get setCount => exercises.fold(0, (sum, exercise) => sum + exercise.sets.length);

  static ImportedWorkout? fromOutput(JsonValue output) {
    final exercises = [for (final raw in output['uebungen']?.arrayValue ?? const <JsonValue>[]) ?_exercise(raw)];
    if (exercises.isEmpty) return null;
    int? number(String key, int min, int max) {
      final value = output[key]?.doubleValue?.round();
      return value != null && value >= min && value <= max ? value : null;
    }

    return ImportedWorkout(
      title: (output['titel']?.textValue ?? '').trim(),
      day: number('tag', 1, 31),
      month: number('monat', 1, 12),
      year: number('jahr', 2000, 2100),
      startMinutes: _minutes(output['start']?.textValue),
      endMinutes: _minutes(output['ende']?.textValue),
      exercises: exercises,
    );
  }

  static ImportedExercise? _exercise(JsonValue raw) {
    final name = (raw['name']?.textValue ?? '').trim();
    if (name.isEmpty) return null;
    final sets = [for (final set in raw['saetze']?.arrayValue ?? const <JsonValue>[]) ?_set(set)];
    if (sets.isEmpty) return null;
    final id = raw['id']?.textValue?.trim();
    return ImportedExercise(
      name: name,
      id: id == null || id.isEmpty ? null : id,
      group: MuscleGroup.fromRaw(raw['gruppe']?.textValue),
      sets: sets,
    );
  }

  static ImportedSet? _set(JsonValue raw) {
    final reps = raw['wdh']?.doubleValue?.round();
    final seconds = raw['sekunden']?.doubleValue?.round();
    final validReps = reps != null && reps > 0 && reps <= 200 ? reps : null;
    final validSeconds = seconds != null && seconds > 0 && seconds <= 3600 ? seconds : null;
    if (validReps == null && validSeconds == null) return null;
    final weight = raw['kg']?.doubleValue ?? 0;
    return ImportedSet(
      reps: validReps,
      seconds: validSeconds,
      weightKg: weight.isFinite && weight > 0 && weight <= 1000 ? weight : 0,
    );
  }

  static int? _minutes(String? text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text?.trim() ?? '');
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  /// Tag der Einheit: mit Jahr wie abgelesen, ohne Jahr der letzte solche Tag bis [today] (Screenshots zeigen
  /// „19. Nov.“ ohne Jahr); ohne Tag `null`.
  CalendarDay? dayIn(CalendarDay today) {
    final (day, month) = (this.day, this.month);
    if (day == null || month == null) return null;
    CalendarDay? valid(int year) {
      final candidate = CalendarDay(year, month, day);
      // 31.2. o. Ä. ergäbe einen anderen Tag.
      return CalendarDay.fromDate(DateTime(year, month, day)) == candidate ? candidate : null;
    }

    if (year case final year?) return valid(year);
    final thisYear = valid(today.year);
    if (thisYear != null && thisYear <= today) return thisYear;
    return valid(today.year - 1);
  }
}

/// Ergebnis: Einheit zum Prüfen und Sichern, neu angelegte eigene Übungen.
final class GymScreenshotResult {
  const GymScreenshotResult({required this.session, required this.newCustom});

  final GymSession session;
  final List<ExerciseInfo> newCustom;
}

/// Krafttraining aus Screenshots einer anderen App übernehmen. WHOOP gibt die Sätze des Strength Trainers über seine
/// Schnittstelle nicht heraus; die KI liest sie von Screenshots ab, die App baut daraus eine Gym-Einheit. Übungen
/// ohne Gegenstück in der Bibliothek werden wie beim GymBook-Import eigene Übungen.
abstract final class GymScreenshotImport {
  /// Bibliothek für die KI: „id | Name“ (Standardübungen und eigene).
  static List<String> library({List<ExerciseInfo> custom = const []}) => [
    for (final exercise in [...ExerciseLibrary.all, ...custom]) '${exercise.id} | ${exercise.name}',
  ];

  /// Stabile Kennung je Beginn: ein zweiter Import derselben Einheit ersetzt die erste, statt sie zu verdoppeln.
  static String workoutKey(DateTime start) {
    final local = start.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'import:${CalendarDay.fromDate(local).iso}:${two(local.hour)}:${two(local.minute)}';
  }

  /// Beginn und Ende: Uhrzeit vom Screenshot, sonst [fallbackStart] (z. B. die WHOOP-Aufzeichnung des Tages) bzw.
  /// 18 Uhr; Ende vom Screenshot, sonst [fallbackEnd], sonst eine Stunde später.
  static ({DateTime start, DateTime end}) times(
    ImportedWorkout workout, {
    required CalendarDay day,
    DateTime? fallbackStart,
    DateTime? fallbackEnd,
  }) {
    DateTime at(int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
    final start = workout.startMinutes != null ? at(workout.startMinutes!) : (fallbackStart ?? at(18 * 60));
    var end = workout.endMinutes != null ? at(workout.endMinutes!) : fallbackEnd;
    if (end == null || !end.isAfter(start)) end = start.add(const Duration(hours: 1));
    return (start: start, end: end);
  }

  static GymScreenshotResult session(
    ImportedWorkout workout, {
    required DateTime start,
    required DateTime end,
    required List<ExerciseInfo> custom,
  }) {
    final known = [...custom];
    final newCustom = <ExerciseInfo>[];
    final exercises = <LoggedExercise>[];
    for (final imported in workout.exercises) {
      final info = _info(imported, custom: known, newCustom: newCustom);
      final sets = [
        for (final set in imported.sets)
          LoggedSet(reps: set.isTimed ? set.seconds! : (set.reps ?? 0), weightKg: set.weightKg),
      ];
      final index = exercises.indexWhere((exercise) => exercise.exerciseID == info.id);
      if (index >= 0) {
        exercises[index].sets.addAll(sets);
      } else {
        exercises.add(
          LoggedExercise(
            exerciseID: info.id,
            name: info.name,
            group: info.group,
            sets: sets,
            restSeconds: info.compound ? 120 : 90,
          ),
        );
      }
    }
    final key = workoutKey(start);
    return GymScreenshotResult(
      session: GymSession(
        id: GymBookImport.stableID(key),
        workoutKey: key,
        title: workout.title.isEmpty ? 'Krafttraining' : workout.title,
        start: start,
        end: end,
        exercises: exercises,
      ),
      newCustom: newCustom,
    );
  }

  static ExerciseInfo _info(
    ImportedExercise imported, {
    required List<ExerciseInfo> custom,
    required List<ExerciseInfo> newCustom,
  }) {
    if (imported.id case final id?) {
      if (ExerciseLibrary.info(id, custom: custom) case final info?) return info;
    }
    final timed = imported.sets.every((set) => set.isTimed);
    final weighted = imported.sets.any((set) => set.weightKg > 0);
    final made = ExerciseInfo.custom(
      name: imported.name,
      group: imported.group ?? MuscleGroup.other,
      equipment: weighted ? Equipment.machine : Equipment.bodyweight,
      tracking: timed
          ? ExerciseTracking.time
          : weighted
          ? ExerciseTracking.weightReps
          : ExerciseTracking.reps,
    );
    for (final item in custom) {
      if (item.id == made.id) return item;
    }
    custom.add(made);
    newCustom.add(made);
    return made;
  }
}

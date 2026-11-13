import 'dart:math' as math;

import '../nutrition/meal.dart' show newUuid;
import '../util/german_format.dart';
import 'exercise_library.dart';
import 'gym_session.dart';
import 'gym_tools.dart';

/// Änderungen an der laufenden Einheit, die im Gym oft vorkommen: Gerät belegt (später, ersetzen), Supersätze,
/// Aufwärmsätze, Gewicht für Folgesätze. Ändern die übergebene Einheit (wie `inout` in Swift).
abstract final class WorkoutEdits {
  static int _index(GymSession session, String exerciseID) =>
      session.exercises.indexWhere((exercise) => exercise.id == exerciseID);

  /// Übung ans Ende schieben („später“, z. B. Gerät belegt).
  static void moveToEnd(String exerciseID, GymSession session) {
    final index = _index(session, exerciseID);
    if (index < 0) return;
    session.exercises.add(session.exercises.removeAt(index));
  }

  /// Wie `move(fromOffsets:toOffset:)` in SwiftUI.
  static void move({required Set<int> fromOffsets, required int toOffset, required GymSession session}) {
    final sorted = fromOffsets.toList()..sort();
    final valid = sorted.where((index) => index >= 0 && index < session.exercises.length).toList();
    final moving = [for (final index in valid) session.exercises[index]];
    final before = fromOffsets.where((index) => index < toOffset).length;
    for (final index in valid.reversed) {
      session.exercises.removeAt(index);
    }
    final target = math.min(math.max(toOffset - before, 0), session.exercises.length);
    session.exercises.insertAll(target, moving);
  }

  /// Übung mit der nächsten zum Supersatz verbinden; ist sie schon in einem, wird sie herausgelöst.
  static void toggleSuperset(String exerciseID, GymSession session) {
    final index = _index(session, exerciseID);
    if (index < 0) return;
    final exercises = session.exercises;
    if (exercises[index].supersetID case final group?) {
      exercises[index].supersetID = null;
      final rest = [
        for (var other = 0; other < exercises.length; other++)
          if (exercises[other].supersetID == group) other,
      ];
      if (rest.length == 1) exercises[rest.first].supersetID = null;
      return;
    }
    final next = index + 1;
    if (next >= exercises.length) return;
    final group = exercises[next].supersetID ?? newUuid();
    exercises[index].supersetID = group;
    exercises[next].supersetID = group;
  }

  /// Übung tauschen. Ohne erledigte Sätze wird sie ersetzt (Satzzahl und Wiederholungen bleiben); sonst behält die
  /// alte Übung ihre erledigten Sätze und die neue übernimmt die offenen.
  static void replace(
    String exerciseID, {
    required ExerciseInfo info,
    required double weightKg,
    required GymSession session,
  }) {
    final index = _index(session, exerciseID);
    if (index < 0) return;
    final old = session.exercises[index];
    final open = old.sets.where((set) => !set.done).toList();
    final source = open.isEmpty ? [LoggedSet(reps: info.upperReps, weightKg: 0, done: false)] : open;
    final sets = [
      for (final set in source)
        LoggedSet(reps: set.reps > 0 ? set.reps : info.upperReps, weightKg: weightKg, done: false, kind: set.kind),
    ];
    final replacement = LoggedExercise(
      exerciseID: info.id,
      name: info.name,
      group: info.group,
      sets: sets,
      restSeconds: old.restSeconds,
      supersetID: old.supersetID,
    );
    if (old.sets.any((set) => set.done)) {
      old.sets = old.sets.where((set) => set.done).toList();
      session.exercises.insert(index + 1, replacement);
    } else {
      session.exercises[index] = replacement;
    }
  }

  /// Alternativen für dieselbe Muskelgruppe mit vorhandener Ausstattung; gleiche Art (Grund-/Isolationsübung) zuerst.
  static List<ExerciseInfo> alternatives(
    String exerciseID, {
    List<ExerciseInfo> custom = const [],
    required Set<Equipment> equipment,
  }) {
    final current = ExerciseLibrary.info(exerciseID, custom: custom);
    if (current == null) return [];
    int rank(ExerciseInfo candidate) => candidate.compound == current.compound ? 0 : 1;
    return [...ExerciseLibrary.all, ...custom]
        .where(
          (candidate) =>
              candidate.id != exerciseID &&
              candidate.group == current.group &&
              candidate.equipment.any((item) => equipment.contains(item) || item == Equipment.bodyweight),
        )
        .toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.name.compareTo(b.name);
      });
  }

  /// Aufwärmsätze vor die Arbeitssätze setzen (nur, solange die Übung noch nicht begonnen ist).
  static void insertWarmUp(List<WarmUpStep> steps, {required String exerciseID, required GymSession session}) {
    final index = _index(session, exerciseID);
    if (index < 0 || steps.isEmpty) return;
    final exercise = session.exercises[index];
    if (exercise.sets.any((set) => set.done)) return;
    exercise.sets
      ..removeWhere((set) => set.kind == SetKind.warmup)
      ..insertAll(0, [
        for (final step in steps)
          LoggedSet(reps: step.reps, weightKg: step.weightKg, done: false, kind: SetKind.warmup),
      ]);
  }

  /// Gewicht genau dieses Satzes setzen. Andere Sätze bleiben unverändert – jeder Satz ist einzeln bearbeitbar
  /// (Wunsch aus dem Gerätetest: das frühere Mitziehen der Folgesätze überschrieb gewollte Werte).
  static void setWeight(
    double weight, {
    required int set,
    required String exerciseID,
    bool allowsNegative = false,
    required GymSession session,
  }) {
    final index = _index(session, exerciseID);
    if (index < 0) return;
    final sets = session.exercises[index].sets;
    if (set < 0 || set >= sets.length) return;
    sets[set].weightKg = allowsNegative ? math.max(weight, -200) : math.max(weight, 0);
  }

  /// Übung überspringen bzw. wieder aufnehmen. Erledigte Sätze bleiben; offene werden beim Speichern verworfen.
  static void setSkipped(bool skipped, {required String exerciseID, required GymSession session}) {
    final index = _index(session, exerciseID);
    if (index < 0) return;
    session.exercises[index].skipped = skipped;
  }
}

/// Rückfrage bei unplausiblen Eingaben (625 statt 62,5 kg), damit Diagramme und Progression nicht kippen.
abstract final class SetCheck {
  static String? warning({
    required double weightKg,
    required int reps,
    required bool isTime,
    required double? previousBestKg,
  }) {
    if (weightKg > 350) return '${GermanFormat.number(weightKg)} kg ist ungewöhnlich viel. Stimmt das?';
    if (previousBestKg != null && previousBestKg > 0 && weightKg > previousBestKg * 1.5 + 10) {
      return '${GermanFormat.number(weightKg)} kg liegt weit über deinem bisherigen Höchstgewicht '
          '(${GermanFormat.number(previousBestKg)} kg). Stimmt das?';
    }
    if (isTime && reps > 600) return '$reps Sekunden sind ungewöhnlich lang. Stimmt das?';
    if (!isTime && reps > 50) return '$reps Wiederholungen sind ungewöhnlich viele. Stimmt das?';
    return null;
  }
}

/// Pausenlänge: bei schweren Grundübungen und kaum Reserve (RIR 0–1) 30 s länger. Längere Pausen zwischen
/// schweren Sätzen erhalten Leistung und Kraftzuwachs (Schoenfeld et al. 2016, Grgic et al. 2017).
abstract final class RestAdvisor {
  static const extraSeconds = 30;
  static const maximumSeconds = 300;

  static int seconds({required int base, required bool compound, required int? rir}) {
    if (!compound || rir == null || rir > 1) return base;
    return math.min(base + extraSeconds, math.max(base, maximumSeconds));
  }
}

/// Anzeige-Hilfen je Übung: Gewicht je Hantel, Wiederholungen je Seite, Zusatz- oder Hilfsgewicht.
abstract final class ExerciseUnits {
  /// Einseitige Übungen: Wiederholungen gelten je Seite.
  static const Set<String> unilateral = {
    'latziehen_einarmig',
    'rudern_kurzhantel',
    'ausfallschritt',
    'bulgarische_kniebeuge',
    'seitstuetz',
    'seitheben_kabel',
    'pallof',
  };

  static bool isUnilateral(String exerciseID) => unilateral.contains(exerciseID);

  /// Körpergewichtsübungen: positives Gewicht = Zusatz, negatives = Unterstützung.
  static bool allowsAssistance(ExerciseInfo? info) {
    if (info == null || info.equipment.isEmpty) return false;
    return info.equipment.first == Equipment.bodyweight || info.equipment.first == Equipment.pullupBar;
  }

  static bool isPerDumbbell(ExerciseInfo? info) =>
      info != null && info.equipment.isNotEmpty && info.equipment.first == Equipment.dumbbell;

  /// „62,5 kg“, „20 kg je Hantel“, „+10 kg Zusatz“, „20 kg Hilfe“, „Körpergewicht“.
  static ({String value, String unit}) weightText(double weight, {required ExerciseInfo? info}) {
    if (weight == 0) return (value: 'Körpergewicht', unit: '');
    if (allowsAssistance(info)) {
      return weight > 0
          ? (value: '+${GermanFormat.number(weight)}', unit: 'kg Zusatz')
          : (value: GermanFormat.number(-weight), unit: 'kg Hilfe');
    }
    return (value: GermanFormat.number(weight), unit: isPerDumbbell(info) ? 'kg je Hantel' : 'kg');
  }

  static String repsUnit(String exerciseID, {required bool isTime}) {
    final base = isTime ? 's' : 'Wdh.';
    return isUnilateral(exerciseID) ? '$base je Seite' : base;
  }
}

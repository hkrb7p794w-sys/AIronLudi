import 'dart:math' as math;

import '../util/german_format.dart';
import 'gym_session.dart';

/// Position eines Satzes in der laufenden Einheit.
final class FlowPosition {
  const FlowPosition({required this.exercise, required this.set});

  final int exercise;
  final int set;

  @override
  bool operator ==(Object other) => other is FlowPosition && other.exercise == exercise && other.set == set;

  @override
  int get hashCode => Object.hash(exercise, set);

  @override
  String toString() => 'FlowPosition($exercise, $set)';
}

/// Zusammenfassung beim Beenden.
final class FlowSummary {
  const FlowSummary({
    required this.minutes,
    required this.doneSets,
    required this.volumeKg,
    required this.exercises,
    required this.openSets,
  });

  final int minutes;
  final int doneSets;
  final double volumeKg;
  final int exercises;

  /// Nicht abgehakte Sätze mit eingetragenen Wiederholungen – vermutlich gemacht und vergessen.
  final int openSets;

  @override
  bool operator ==(Object other) =>
      other is FlowSummary &&
      other.minutes == minutes &&
      other.doneSets == doneSets &&
      other.volumeKg == volumeKg &&
      other.exercises == exercises &&
      other.openSets == openSets;

  @override
  int get hashCode => Object.hash(minutes, doneSets, volumeKg, exercises, openSets);
}

int? _firstOpenSet(LoggedExercise exercise) {
  for (var index = 0; index < exercise.sets.length; index++) {
    if (!exercise.sets[index].done) return index;
  }
  return null;
}

/// Ablauf der laufenden Einheit für die Fokus-Karte: welcher Satz ist jetzt dran, was kommt danach, was fehlt
/// beim Beenden. Im Gym zählt nur „Was mache ich jetzt?“ – die App sucht den Satz, nicht die Person.
abstract final class WorkoutFlow {
  /// Nächster offener Satz: zuerst in der gewählten Übung, sonst ab dort die nächste Übung mit offenem Satz
  /// (am Ende wieder von vorn – mit „Später“ verschobene Übungen kommen so zum Schluss dran). Übersprungene Übungen
  /// zählen nicht mehr; nur wenn man sie ausdrücklich wählt, steht ihr nächster Satz auf der Fokus-Karte.
  static FlowPosition? current(GymSession session, {String? preferring}) {
    final exercises = session.exercises;
    if (exercises.isEmpty) return null;
    int? preferred;
    if (preferring != null) {
      final index = exercises.indexWhere((exercise) => exercise.id == preferring);
      if (index >= 0) preferred = index;
    }
    if (preferred != null && exercises[preferred].skipped) {
      final set = _firstOpenSet(exercises[preferred]);
      return set == null ? null : FlowPosition(exercise: preferred, set: set);
    }
    final start = preferred ?? 0;
    for (var offset = 0; offset < exercises.length; offset++) {
      final index = (start + offset) % exercises.length;
      if (exercises[index].skipped) continue;
      if (_firstOpenSet(exercises[index]) case final set?) return FlowPosition(exercise: index, set: set);
    }
    return null;
  }

  /// Der Plan ist durch: Es gibt Übungen, und keine offene, nicht übersprungene Übung hat noch einen Satz.
  static bool isComplete(GymSession session) => session.exercises.isNotEmpty && current(session) == null;

  /// Die nächste andere Übung nach [index] (für die Vorschau „Danach“), ohne übersprungene und fertige.
  static int? nextExercise(int index, GymSession session) {
    final exercises = session.exercises;
    if (exercises.length <= 1) return null;
    for (var offset = 1; offset < exercises.length; offset++) {
      final candidate = (index + offset) % exercises.length;
      final exercise = exercises[candidate];
      if (!exercise.skipped && exercise.sets.any((set) => !set.done)) return candidate;
    }
    return null;
  }

  /// Text für Pausenende und Live-Aktivität: „Weiter mit Schulterdrücken“ beim Übungswechsel, sonst
  /// „Weiter mit Satz 3 · Bankdrücken“; `null`, wenn nichts mehr offen ist.
  static String? nextText(GymSession session, {required String? focus, required String? previous}) {
    final position = current(session, preferring: focus);
    if (position == null) return null;
    final exercise = session.exercises[position.exercise];
    if (exercise.id != previous || position.set == 0) return 'Weiter mit ${exercise.name}';
    return 'Weiter mit Satz ${position.set + 1} · ${exercise.name}';
  }

  /// Der Satz nach [position], als Vorschau („Als Nächstes“).
  static FlowPosition? upcoming(FlowPosition position, GymSession session) {
    final copy = session.copy();
    if (position.exercise < 0 ||
        position.exercise >= copy.exercises.length ||
        position.set < 0 ||
        position.set >= copy.exercises[position.exercise].sets.length) {
      return null;
    }
    copy.exercises[position.exercise].sets[position.set].done = true;
    final next = afterCompleting(position.exercise, copy);
    return current(copy, preferring: next.focus == null ? null : copy.exercises[next.focus!].id);
  }

  /// Nach dem Abhaken eines Satzes von Übung [index] (Satz ist schon abgehakt): welche Übung kommt, und startet
  /// eine Pause? Im Supersatz geht es ohne Pause zur nächsten Übung der Gruppe; Pause erst nach der Runde.
  static ({int? focus, bool rest}) afterCompleting(int index, GymSession session) {
    final exercises = session.exercises;
    if (index < 0 || index >= exercises.length) return (focus: null, rest: true);
    final members = supersetMembers(index, session);
    final position = members.indexOf(index);
    if (members.length > 1 && position >= 0) {
      final order = [...members.sublist(position + 1), ...members.sublist(0, position)];
      for (final next in order) {
        if (exercises[next].sets.any((set) => !set.done)) {
          // Weiter hinten in der Gruppe: ohne Pause; zurück zur ersten Übung: neue Runde nach der Pause.
          return (focus: next, rest: next < index);
        }
      }
    }
    final next = current(session, preferring: exercises[index].id);
    return (focus: next?.exercise, rest: true);
  }

  /// Indizes der Übungen im selben Supersatz (nur die Übung selbst, wenn sie keinem angehört).
  static List<int> supersetMembers(int index, GymSession session) {
    if (index < 0 || index >= session.exercises.length) return [index];
    final id = session.exercises[index].supersetID;
    if (id == null) return [index];
    return [
      for (var other = 0; other < session.exercises.length; other++)
        if (session.exercises[other].supersetID == id) other,
    ];
  }

  /// Kürzel wie „A1“, „A2“, „B1“ für Übungen in Supersätzen (Reihenfolge des ersten Auftretens).
  static Map<String, String> supersetLabels(GymSession session) {
    final letters = <String, String>{};
    final counts = <String, int>{};
    final result = <String, String>{};
    final groups = <String, int>{};
    for (final exercise in session.exercises) {
      if (exercise.supersetID case final id?) groups[id] = (groups[id] ?? 0) + 1;
    }
    for (final exercise in session.exercises) {
      final id = exercise.supersetID;
      if (id == null || (groups[id] ?? 0) <= 1) continue;
      letters.putIfAbsent(id, () => String.fromCharCode(65 + math.min(letters.length, 25)));
      counts[id] = (counts[id] ?? 0) + 1;
      result[exercise.id] = '${letters[id] ?? 'A'}${counts[id] ?? 1}';
    }
    return result;
  }

  /// Fortschritt einer Übung, z. B. „2/4“.
  static ({int done, int total}) progress(LoggedExercise exercise) =>
      (done: exercise.sets.where((set) => set.done).length, total: exercise.sets.length);

  /// Übersprungene Übungen mit noch offenen Sätzen (beim Beenden: „2 übersprungen“).
  static int skippedCount(GymSession session) =>
      session.exercises.where((exercise) => exercise.skipped && exercise.sets.any((set) => !set.done)).length;

  static FlowSummary summary(GymSession session, {DateTime? now}) {
    // Übersprungene Übungen zählen nicht als „vergessen“.
    final open = session.exercises
        .where((exercise) => !exercise.skipped)
        .fold(0, (count, exercise) => count + exercise.sets.where((set) => !set.done && set.reps > 0).length);
    final end = session.end ?? now ?? DateTime.now();
    final minutes = (end.difference(session.start).inMicroseconds / 1e6 / 60).round();
    return FlowSummary(
      minutes: math.max(0, minutes),
      doneSets: session.doneSetCount,
      volumeKg: session.volumeKg,
      exercises: session.exercises.where((exercise) => exercise.doneSets.isNotEmpty).length,
      openSets: open,
    );
  }

  /// Übernimmt alle offenen Sätze mit Wiederholungen als erledigt (übersprungene Übungen bleiben offen).
  static GymSession completingOpenSets(GymSession session) {
    final copy = session.copy();
    for (final exercise in copy.exercises) {
      if (exercise.skipped) continue;
      for (final set in exercise.sets) {
        if (set.reps > 0) set.done = true;
      }
    }
    return copy;
  }
}

/// Taste des Ziffernblocks.
sealed class NumberPadKey {
  const NumberPadKey();
}

final class NumberPadDigit extends NumberPadKey {
  const NumberPadDigit(this.digit);

  final int digit;

  @override
  bool operator ==(Object other) => other is NumberPadDigit && other.digit == digit;

  @override
  int get hashCode => digit.hashCode;
}

final class NumberPadComma extends NumberPadKey {
  const NumberPadComma();
}

final class NumberPadDelete extends NumberPadKey {
  const NumberPadDelete();
}

/// Eingabe über den großen Ziffernblock (Gewicht mit Komma, Wiederholungen ganzzahlig).
abstract final class NumberPad {
  /// Hängt eine Taste an den Text an. Gewichte erlauben ein Komma und zwei Nachkommastellen, höchstens 4 Ziffern
  /// vor dem Komma; Wiederholungen höchstens 3 Ziffern.
  static String apply(NumberPadKey key, String text, {required bool allowsDecimals}) {
    switch (key) {
      case NumberPadDelete():
        if (text.isEmpty) return text;
        final characters = text.runes.toList()..removeLast();
        return String.fromCharCodes(characters);
      case NumberPadComma():
        if (!allowsDecimals || text.contains(',')) return text;
        return '${text.isEmpty ? '0' : text},';
      case NumberPadDigit(:final digit):
        if (digit < 0 || digit > 9) return text;
        final comma = text.indexOf(',');
        if (comma >= 0) return text.length - comma - 1 < 2 ? '$text$digit' : text;
        final limit = allowsDecimals ? 4 : 3;
        if (text == '0') return '$digit';
        return text.length < limit ? '$text$digit' : text;
    }
  }

  /// `"62,5"` → 62.5; leer → `null`.
  static double? value(String text) {
    if (text.isEmpty) return null;
    final normalized = text.replaceAll(',', '.');
    // Wie `Double(_:)` in Swift: nur vollständige Zahlen, kein Leerraum.
    if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(normalized)) return null;
    return double.tryParse(normalized);
  }

  /// Startwert für den Ziffernblock (`62,5`, `8`, `0` → leer).
  static String text(double value) => value > 0 ? GermanFormat.number(value) : '';
}

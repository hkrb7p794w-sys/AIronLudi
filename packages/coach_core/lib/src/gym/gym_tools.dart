import 'dart:math' as math;

import '../profile/user_profile.dart';
import '../util/german_format.dart';
import 'exercise_library.dart';
import 'gym_session.dart';

/// Ergebnis des Scheibenrechners.
final class PlateResult {
  const PlateResult({required this.perSide, required this.remainder});

  /// Scheiben je Seite, schwerste zuerst.
  final List<double> perSide;

  /// Was mit den Scheiben nicht genau erreichbar ist (kg gesamt).
  final double remainder;

  @override
  bool operator ==(Object other) =>
      other is PlateResult && other.perSide.join(',') == perSide.join(',') && other.remainder == remainder;

  @override
  int get hashCode => Object.hash(perSide.join(','), remainder);

  @override
  String toString() => 'PlateResult($perSide, $remainder)';
}

/// Scheibenrechner: welche Scheiben je Seite auf die Langhantel gehören.
abstract final class PlateCalculator {
  static const List<double> standardPlates = [25, 20, 15, 10, 5, 2.5, 1.25];
  static const standardBar = 20.0;

  /// `null`, wenn das Gewicht unter der Stange liegt.
  static PlateResult? plates(double total, {double bar = standardBar, List<double> available = standardPlates}) {
    if (total < bar) return null;
    var side = (total - bar) / 2;
    final result = <double>[];
    for (final plate in [...available]..sort((a, b) => b.compareTo(a))) {
      while (side + 0.001 >= plate) {
        result.add(plate);
        side -= plate;
      }
    }
    return PlateResult(perSide: result, remainder: ((side * 2) * 100).roundToDouble() / 100);
  }

  static String text(PlateResult result) {
    if (result.perSide.isEmpty) return 'Nur die Stange';
    final plates = result.perSide.map(GermanFormat.number).join(' + ');
    final rest = result.remainder > 0 ? ' (${GermanFormat.number(result.remainder)} kg fehlen)' : '';
    return 'Je Seite: $plates kg$rest';
  }
}

/// Ein Aufwärmsatz.
final class WarmUpStep {
  const WarmUpStep({required this.weightKg, required this.reps});

  final double weightKg;
  final int reps;

  @override
  bool operator ==(Object other) => other is WarmUpStep && other.weightKg == weightKg && other.reps == reps;

  @override
  int get hashCode => Object.hash(weightKg, reps);

  @override
  String toString() => 'WarmUpStep($weightKg × $reps)';
}

/// Aufwärmsätze nach Übung und Arbeitsgewicht: bei schweren Grundübungen steigend bis knapp unter das Arbeitsgewicht,
/// bei schweren Isolationsübungen ein Satz, bei leichten keiner. Ist der Muskel in dieser Einheit schon gearbeitet,
/// genügt ein Einstiegssatz. Das Schema ist ein verbreiteter Praxiswert, kein Studienergebnis.
abstract final class WarmUp {
  /// Darunter lohnt bei Isolationsübungen kein eigener Aufwärmsatz.
  static const isolationMinimumKg = 15.0;

  static List<WarmUpStep> steps({
    required double working,
    required List<Equipment> equipment,
    required bool compound,
    double bar = PlateCalculator.standardBar,
    ExperienceLevel? level,
    bool warmedUp = false,
  }) {
    if (working <= 0 || equipment.isEmpty || equipment.first == Equipment.bodyweight) return [];
    final first = equipment.first;
    final step = first == Equipment.barbell ? 2.5 : 1.0;
    List<WarmUpStep> feeler(double share, int reps) {
      final weight = (working * share / step).roundToDouble() * step;
      return weight > 0 && weight < working ? [WarmUpStep(weightKg: weight, reps: reps)] : [];
    }

    if (!compound) {
      if (warmedUp || working < isolationMinimumKg) return [];
      return feeler(0.6, 10);
    }
    if (warmedUp) return working >= 20 ? feeler(0.7, 3) : [];
    if (first == Equipment.barbell) {
      if (working < math.max(40, bar * 2)) return [];
      final steps = [WarmUpStep(weightKg: bar, reps: 10)];
      final shares = <(double, int)>[(0.5, 5), (0.7, 3)];
      // Einsteiger:innen bewegen wenig Last; ein Satz nah am Arbeitsgewicht ermüdet dann nur.
      if (working >= 60 && level != ExperienceLevel.beginner) shares.add((0.85, 2));
      for (final (share, reps) in shares) {
        final weight = (working * share / 2.5).roundToDouble() * 2.5;
        if (weight > steps.last.weightKg && weight < working) steps.add(WarmUpStep(weightKg: weight, reps: reps));
      }
      return steps;
    }
    if (first == Equipment.dumbbell || first == Equipment.machine || first == Equipment.cable) {
      if (working < 12) return [];
      return [
        for (final (share, reps) in const [(0.5, 8), (0.75, 4)])
          if ((working * share).roundToDouble() case final weight when weight > 0 && weight < working)
            WarmUpStep(weightKg: weight, reps: reps),
      ];
    }
    return [];
  }

  /// Hat eine andere Übung derselben Muskelgruppe in dieser Einheit schon erledigte Sätze?
  static bool isWarmedUp(LoggedExercise exercise, {required ExerciseInfo? info, required GymSession session}) {
    if (info == null) return false;
    return session.exercises.any(
      (other) => other.id != exercise.id && other.group == info.group && other.doneSets.isNotEmpty,
    );
  }

  /// Vorschlag vor dem ersten Arbeitssatz: nur solange die Übung noch keine Aufwärm- und keine erledigten Sätze hat;
  /// Gewichte aus dem schwersten geplanten Arbeitssatz.
  static List<WarmUpStep> suggestion(
    LoggedExercise exercise, {
    required ExerciseInfo? info,
    required double bar,
    ExperienceLevel? level,
    bool warmedUp = false,
  }) {
    if (info == null || exercise.sets.any((set) => set.kind == SetKind.warmup || set.done)) return [];
    final weights = exercise.sets.where((set) => set.kind != SetKind.warmup).map((set) => set.weightKg);
    final working = weights.isEmpty ? 0.0 : weights.reduce(math.max);
    return steps(
      working: working,
      equipment: info.equipment,
      compound: info.compound,
      bar: bar,
      level: level,
      warmedUp: warmedUp,
    );
  }

  static String text(List<WarmUpStep> steps) =>
      'Aufwärmen: ${steps.map((step) => '${GermanFormat.number(step.weightKg)} kg × ${step.reps}').join(' · ')}';
}

/// Pausenauswahl und -anzeige: „45 s“, „1:30 min“, „3 min“.
abstract final class RestText {
  static const options = [30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300];

  static String format(int seconds) {
    if (seconds < 60) return '$seconds s';
    final rest = seconds % 60;
    return rest == 0 ? '${seconds ~/ 60} min' : '${seconds ~/ 60}:${rest.toString().padLeft(2, '0')} min';
  }
}

/// Halteübungen (Plank, Wandsitzen): Stoppuhr statt Eintippen. Die gemessene Zeit wird übernommen und lässt sich
/// danach korrigieren (zu spät gestoppt, Handy erst nach dem Hinlegen gestartet).
abstract final class HoldTimer {
  /// Auf ganze Sekunden gerundet, mindestens 1.
  static int seconds(DateTime start, DateTime end) => math.max(1, (end.difference(start).inMicroseconds / 1e6).round());

  /// Korrektur in ±1/±5 s, nie unter 1 s.
  static int corrected(int seconds, int delta) => math.max(1, seconds + delta);

  /// „noch 12 s“ bis zum Ziel bzw. „+8 s über Ziel“.
  static String targetText({required int elapsed, required int target}) =>
      elapsed < target ? 'noch ${target - elapsed} s bis $target s' : '+${elapsed - target} s über Ziel';
}

import '../coach/coaching_note.dart';
import '../profile/user_profile.dart';
import '../util/german_format.dart';
import 'exercise_catalog.dart';
import 'gym_progression.dart';
import 'gym_session.dart';

/// Eingabe für die KI-Hinweise zur Gewichtssteigerung (Worker-Aufgabe `gym_hints`). Entschieden haben die
/// Progressionsregeln; die KI formuliert daraus kurze Hinweise und darf nur Zahlen aus dieser Eingabe nennen.
abstract final class GymHints {
  static const evidence = ['gym.progression', 'gym.rir', 'gym.load', 'gym.frequency', 'gym.volume'];

  /// Zeile je Übung: aktueller Stand, Entscheidung und Begründung der Regel.
  static String line(ExerciseProgress item) {
    final weight = item.weightKg > 0 ? '${GermanFormat.number(item.weightKg)} kg' : 'Körpergewicht';
    final reps = item.reps.join('/');
    return '${item.name}: zuletzt $weight × $reps Wdh., Ziel ${item.target.lower}–'
        '${item.target.upper} → ${item.headline}. ${item.detail}';
  }

  static Map<String, Object?> input({
    required List<ExerciseProgress> progress,
    required bool? recovered,
    required Map<MuscleGroup, int> volume,
    required FitnessGoal? goal,
    List<String> observations = const [],
  }) {
    final recovery = switch (recovered) {
      true => 'gut',
      false => 'eingeschränkt (Steigerung erst bei guter Tagesform)',
      null => 'unbekannt',
    };
    return {
      'exercises': [for (final item in progress.take(10)) line(item)],
      'recovery': recovery,
      'volume': [for (final group in MuscleVolume.groups) '${group.rawValue}: ${volume[group] ?? 0} Sätze in 7 Tagen'],
      'evidence': CoachingNote.evidenceInput(evidence),
      // Stillstand, Volumen und Häufigkeit aus `GymCoach.observations`.
      if (observations.isNotEmpty) 'observations': observations.take(6).toList(),
      'goal': ?goal?.label,
    };
  }

  /// Regelbasierte Hinweise, wenn die KI nicht erreichbar ist: die Übungen mit Handlungsbedarf zuerst.
  static List<String> fallback(List<ExerciseProgress> progress, {List<String> observations = const [], int limit = 4}) {
    const urgent = {ProgressStatus.increase, ProgressStatus.restart, ProgressStatus.check};
    final relevant = progress.where((item) => urgent.contains(item.status)).toList();
    final items = relevant.isEmpty ? progress.take(2) : relevant.take(limit);
    return [for (final item in items) '${item.name}: ${item.headline}.', ...observations.take(2)];
  }
}

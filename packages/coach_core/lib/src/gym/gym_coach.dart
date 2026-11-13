import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/coaching_note.dart';
import '../json/json_value.dart';
import '../profile/user_profile.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import '../util/int_range.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gym_session.dart';
import 'routine.dart';

String _prefix(String text, int count) => String.fromCharCodes(text.runes.take(count));

/// Bester Satz nach (Gewicht, Wiederholungen); bei Gleichstand der erste (wie `max(by:)` in Swift).
LoggedSet? _bestSet(List<LoggedSet> sets) {
  LoggedSet? best;
  for (final set in sets) {
    if (best == null || best.weightKg < set.weightKg || (best.weightKg == set.weightKg && best.reps < set.reps)) {
      best = set;
    }
  }
  return best;
}

/// Ziel des KI-Trainingsplans.
enum PlanGoal implements RawEnum {
  muscle,
  strength,
  fitness,
  fatLoss;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    muscle => 'Muskelaufbau',
    strength => 'Kraft',
    fitness => 'Allgemeine Fitness',
    fatLoss => 'Abnehmen mit Krafterhalt',
  };

  /// Wiederholungsbereich für Grundübungen (Schoenfeld et al. 2017: Zuwachs in einem weiten Bereich).
  IntRange get repRange => switch (this) {
    strength => const IntRange(3, 6),
    muscle => const IntRange(6, 12),
    fitness || fatLoss => const IntRange(8, 15),
  };

  static PlanGoal? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Antworten aus dem Fragebogen vor dem Erstellen.
final class PlanRequest {
  PlanRequest();

  PlanGoal goal = PlanGoal.muscle;
  int daysPerWeek = 3;
  int minutesPerSession = 60;
  List<MuscleGroup> focus = [];
  String limitations = '';

  /// Übungen aus den eigenen Routinen bevorzugen.
  bool keepFavorites = true;

  /// Für diesen Plan; `null` = Angabe aus dem Profil.
  ExperienceLevel? experience;

  /// Für diesen Plan; `null` = Ausstattung aus den Einstellungen.
  Set<Equipment>? equipment;

  Map<String, Object?> toJson() => {
    'goal': goal.rawValue,
    'daysPerWeek': daysPerWeek,
    'minutesPerSession': minutesPerSession,
    'focus': [for (final group in focus) group.rawValue],
    'limitations': limitations,
    'keepFavorites': keepFavorites,
    'experience': ?experience?.rawValue,
    if (equipment case final equipment?)
      'equipment': [
        for (final item in Equipment.values)
          if (equipment.contains(item)) item.rawValue,
      ],
  };

  /// Wie das synthetisierte `Decodable`: Pflichtfelder müssen vorhanden sein.
  static PlanRequest? fromJson(Object? json) {
    if (json is! Map) return null;
    final goal = PlanGoal.fromRaw(json['goal']);
    final (days, minutes, limitations, keep) = (
      json['daysPerWeek'],
      json['minutesPerSession'],
      json['limitations'],
      json['keepFavorites'],
    );
    final focus = enumListStrict(MuscleGroup.values, json['focus']);
    if (goal == null || days is! int || minutes is! int || limitations is! String || keep is! bool || focus == null) {
      return null;
    }
    final rawExperience = json['experience'];
    final experience = enumFromRaw(ExperienceLevel.values, rawExperience);
    if (rawExperience != null && experience == null) return null;
    final rawEquipment = json['equipment'];
    final equipment = enumListStrict(Equipment.values, rawEquipment);
    if (rawEquipment != null && equipment == null) return null;
    return PlanRequest()
      ..goal = goal
      ..daysPerWeek = days
      ..minutesPerSession = minutes
      ..focus = focus
      ..limitations = limitations
      ..keepFavorites = keep
      ..experience = experience
      ..equipment = equipment?.toSet();
  }
}

/// Geprüfter KI-Plan.
final class PlanResult {
  const PlanResult({required this.routines, required this.notes, required this.corrections});

  final List<Routine> routines;
  final List<String> notes;

  /// Vom Plan der KI verworfene oder korrigierte Punkte.
  final List<String> corrections;
}

/// Regelbasierte Beobachtungen zum Krafttraining (für die KI-Hinweise und ohne KI) und der KI-Trainingsplan mit
/// Fragebogen. Die KI schlägt vor, die Regeln prüfen: nur Übungen aus der Bibliothek und der eigenen Ausstattung,
/// Sätze und Wiederholungen in festen Grenzen, Wochenvolumen je Muskel gegen die Empfehlungen.
abstract final class GymCoach {
  /// Mindest- und Zielvolumen je Muskelgruppe und Woche (Schoenfeld et al. 2017: mehr Sätze, mehr Zuwachs; 10+ als
  /// Praxisziel) und Häufigkeit (Schoenfeld et al. 2016: zweimal pro Woche).
  static const minimumWeeklySets = 10;
  static const maximumWeeklySets = 20;
  static const List<MuscleGroup> majorGroups = [
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.shoulders,
    MuscleGroup.legs,
  ];

  // Beobachtungen

  /// Hinweise aus dem Verlauf der letzten Wochen: Stillstand je Übung, Volumen und Häufigkeit je Muskel.
  static List<String> observations({required List<GymSession> sessions, required CalendarDay today}) {
    final lines = <String>[];
    final recent = sessions.where((session) => session.day >= today.adding(-42)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Stillstand: in den letzten drei Einheiten einer Übung dasselbe Gewicht und keine Wiederholung mehr.
    final byExercise = <String, List<({String name, double weight, int reps})>>{};
    for (final session in recent) {
      for (final exercise in session.exercises) {
        final best = _bestSet(exercise.doneSets);
        if (best == null) continue;
        byExercise.putIfAbsent(exercise.exerciseID, () => []).add((
          name: exercise.name,
          weight: best.weightKg,
          reps: best.reps,
        ));
      }
    }
    for (final key in byExercise.keys.toList()..sort()) {
      final history = byExercise[key]!;
      if (history.length < 3) continue;
      final last = history.sublist(history.length - 3);
      final weights = last.map((item) => item.weight).toSet();
      final (first, latest) = (last.first, last.last);
      if (weights.length == 1 && latest.reps <= first.reps && latest.weight > 0) {
        lines.add(
          '${latest.name}: seit drei Einheiten ${GermanFormat.number(latest.weight)} kg ohne mehr Wiederholungen – '
          'Stillstand. Satzzahl oder Variante ändern bzw. eine leichtere Woche einlegen.',
        );
      }
    }

    // Volumen und Häufigkeit der letzten 7 Tage je großer Muskelgruppe.
    final week = recent.where((session) => session.day > today.adding(-7)).toList();
    for (final group in majorGroups) {
      final sets = week
          .expand((session) => session.exercises)
          .where((exercise) => exerciseGroup(exercise) == group)
          .fold(0, (sum, exercise) => sum + exercise.doneSets.length);
      final days = week
          .where((session) => session.exercises.any((exercise) => exerciseGroup(exercise) == group))
          .map((session) => session.day)
          .toSet()
          .length;
      if (week.isNotEmpty && sets < minimumWeeklySets) {
        lines.add(
          '${group.rawValue}: $sets Sätze in 7 Tagen – unter $minimumWeeklySets. Für mehr Zuwachs Sätze '
          'ergänzen.',
        );
      } else if (sets > maximumWeeklySets) {
        lines.add('${group.rawValue}: $sets Sätze in 7 Tagen – mehr als $maximumWeeklySets. Auf Erholung achten.');
      }
      if (week.isNotEmpty && days == 1 && sets > 0) {
        lines.add('${group.rawValue}: nur an einem Tag trainiert – auf zwei Tage verteilen wirkt meist besser.');
      }
    }
    return lines;
  }

  static MuscleGroup exerciseGroup(LoggedExercise exercise) =>
      ExerciseLibrary.info(exercise.exerciseID)?.group ?? exercise.group;

  // KI-Trainingsplan

  /// Was vor dem Absenden auffällt: `blocking` verhindert den Plan, `hints` erklärt ungünstige Kombinationen.
  static ({List<String> blocking, List<String> hints}) planIssues(
    PlanRequest request, {
    required Set<Equipment> equipment,
  }) {
    final blocking = <String>[];
    final hints = <String>[];
    final usable = request.equipment ?? equipment;
    if (usable.isEmpty) blocking.add('Wähle mindestens eine Ausstattung, sonst gibt es keine passenden Übungen.');
    if (request.daysPerWeek >= 5 && request.minutesPerSession <= 30) {
      hints.add('Sehr viele kurze Einheiten: Drei längere Einheiten sind meist leichter unterzubringen.');
    }
    if (request.goal == PlanGoal.strength && request.minutesPerSession <= 30) {
      hints.add('Für Kraft sind lange Pausen nötig. In 30 Minuten passen nur wenige Übungen.');
    }
    if (request.focus.length > request.daysPerWeek * 2) {
      hints.add('Viele Schwerpunkte bei wenigen Tagen: Die KI kann nicht alle gleich gewichten.');
    }
    return (blocking: blocking, hints: hints);
  }

  /// Eingabe für die Worker-Aufgabe `gym_plan`.
  static Map<String, Object?> planInput({
    required PlanRequest request,
    required UserProfile profile,
    required Set<Equipment> equipment,
    required List<Routine> routines,
    required List<GymSession> sessions,
    required List<ExerciseInfo> custom,
    required CalendarDay today,
    Map<String, String> notes = const {},
  }) {
    final usable = request.equipment ?? equipment;
    final available = [...ExerciseLibrary.all, ...custom].where((exercise) => exercise.isAvailable(usable));
    final library = [
      for (final exercise in available)
        '${exercise.id} | ${exercise.name} | ${exercise.group.rawValue} | '
            '${exercise.tracking == ExerciseTracking.time ? 'Sekunden' : 'Wiederholungen'} | '
            '${exercise.compound ? 'Grundübung' : 'Isolation'}',
    ];
    final favorites = routines.expand((routine) => routine.items.map((item) => item.exerciseID)).toSet().toList()
      ..sort();
    final last = lastSets(sessions);
    final lastWeights = [
      for (final id in last.keys.toList()..sort())
        '$id: ${GermanFormat.number(last[id]!.weightKg)} kg × ${last[id]!.reps}',
    ];
    final otherSports = [
      for (final sport in profile.sports)
        if (sport != TrainingSport.strength) sport.label,
    ];
    final range = request.goal.repRange;
    final noteKeys = notes.keys.toList()..sort();
    return {
      'goal': request.goal.label,
      'days': request.daysPerWeek.clamp(1, 6).toDouble(),
      'minutes': request.minutesPerSession.clamp(20, 120).toDouble(),
      'focus': [for (final group in request.focus) group.rawValue],
      'limitations': _prefix(request.limitations, 300),
      'experience': (request.experience ?? profile.level(TrainingSport.strength)).label,
      'otherSports': otherSports,
      'library': library,
      'favorites': request.keepFavorites ? favorites : <String>[],
      'lastWeights': lastWeights.take(30).toList(),
      'repRange': '${range.lower}–${range.upper}',
      'observations': observations(sessions: sessions, today: today),
      'exerciseNotes': [for (final key in noteKeys.take(30)) '$key: ${_prefix(notes[key]!, 120)}'],
      'recentPerformance': recentPerformance(sessions),
      'evidence': CoachingNote.evidenceInput(['gym.frequency', 'gym.volume', 'gym.load', 'gym.rir', 'gym.progression']),
    };
  }

  static List<GymSession> _newestFirst(List<GymSession> sessions) =>
      [...sessions]..sort((a, b) => b.start.compareTo(a.start));

  /// Tatsächlich Geschafftes je Übung über alle Pläne hinweg: die letzten drei Einheiten, neueste zuerst.
  static List<String> recentPerformance(List<GymSession> sessions) {
    final byExercise = <String, List<String>>{};
    for (final session in _newestFirst(sessions)) {
      for (final exercise in session.exercises) {
        if ((byExercise[exercise.exerciseID]?.length ?? 0) >= 3) continue;
        final best = _bestSet(exercise.doneSets);
        if (best == null) continue;
        byExercise
            .putIfAbsent(exercise.exerciseID, () => [])
            .add('${GermanFormat.number(best.weightKg)} kg × ${best.reps}');
      }
    }
    final keys = byExercise.keys.toList()..sort();
    return [for (final key in keys.take(40)) '$key: ${byExercise[key]!.join(', ')}'];
  }

  /// Schwerster Satz je Übung aus der jeweils letzten Einheit mit Gewicht (Startgewicht für neue Routinen).
  static Map<String, LoggedSet> lastSets(List<GymSession> sessions) {
    final result = <String, LoggedSet>{};
    for (final session in _newestFirst(sessions)) {
      for (final exercise in session.exercises) {
        if (result.containsKey(exercise.exerciseID)) continue;
        LoggedSet? best;
        for (final set in exercise.doneSets) {
          if (best == null || best.weightKg < set.weightKg) best = set;
        }
        if (best != null && best.weightKg > 0) result[exercise.exerciseID] = best;
      }
    }
    return result;
  }

  /// Prüft den Vorschlag der KI (`{"routinen": [{"name", "uebungen": [{"id", "saetze", "wdh_min", "wdh_max",
  /// "pause"}]}], "hinweise": [...]}`) und ergänzt Hinweise der Regeln.
  static PlanResult validatePlan(
    JsonValue output, {
    required PlanRequest request,
    required Set<Equipment> equipment,
    required List<ExerciseInfo> custom,
    Map<String, double> lastWeights = const {},
  }) {
    final corrections = <String>[];
    final routines = <Routine>[];
    final maxExercises = math.max(3, math.min(10, request.minutesPerSession ~/ 8));
    final rawRoutines = output['routinen']?.arrayValue ?? const <JsonValue>[];
    for (final raw in rawRoutines.take(math.max(0, request.daysPerWeek))) {
      final name = _prefix(raw['name']?.stringValue ?? 'Einheit ${routines.length + 1}', 40);
      final items = <RoutineItem>[];
      for (final entry in raw['uebungen']?.arrayValue ?? const <JsonValue>[]) {
        final id = entry['id']?.stringValue;
        final info = id == null ? null : ExerciseLibrary.info(id, custom: custom);
        if (id == null || info == null) {
          corrections.add('Unbekannte Übung „${entry['id']?.stringValue ?? '?'}“ entfernt.');
          continue;
        }
        if (!info.isAvailable(equipment)) {
          corrections.add('${info.name} braucht Ausstattung, die du nicht hast – entfernt.');
          continue;
        }
        if (items.any((item) => item.exerciseID == id) || items.length >= maxExercises) continue;
        final sets = entry['saetze']?.clampedInt(-1000, 1000) ?? 3;
        final isTime = info.tracking == ExerciseTracking.time;
        final limits = isTime ? const IntRange(10, 120) : const IntRange(3, 30);
        var lower = entry['wdh_min']?.clampedInt(limits.lower, limits.upper) ?? info.lowerReps;
        var upper = entry['wdh_max']?.clampedInt(limits.lower, limits.upper) ?? info.upperReps;
        lower = math.min(math.max(lower, limits.lower), limits.upper);
        upper = math.min(math.max(upper, lower), limits.upper);
        final clampedSets = math.min(math.max(sets, 1), 5);
        if (clampedSets != sets) corrections.add('${info.name}: Sätze auf $clampedSets begrenzt.');
        final rest = entry['pause']?.clampedInt(45, 240) ?? (info.compound ? 120 : 90);
        items.add(
          RoutineItem(
            exerciseID: id,
            name: info.name,
            sets: clampedSets,
            lowerReps: lower,
            upperReps: upper,
            restSeconds: rest,
            weightKg: lastWeights[id],
          ),
        );
      }
      if (items.isNotEmpty) routines.add(Routine(name: name, items: items));
    }

    final notes = [
      for (final value
          in (output['hinweise']?.arrayValue ?? const <JsonValue>[]).map((item) => item.stringValue).nonNulls.take(5))
        _prefix(value, 300),
    ];
    // Wochenvolumen je großer Muskelgruppe prüfen (Sätze aus Haupt- und Nebengruppen zählen voll bzw. halb nicht;
    // hier nur Hauptgruppe, wie in der Übersicht der App).
    final weekly = <MuscleGroup, int>{};
    for (final routine in routines) {
      for (final MapEntry(key: group, value: sets) in routine.setsPerGroup.entries) {
        weekly[group] = (weekly[group] ?? 0) + sets;
      }
    }
    if (routines.isNotEmpty) {
      for (final group in majorGroups) {
        final sets = weekly[group] ?? 0;
        if (sets < minimumWeeklySets) {
          notes.add('${group.rawValue}: $sets Sätze pro Woche – für Muskelaufbau eher $minimumWeeklySets oder mehr.');
        } else if (sets > maximumWeeklySets) {
          notes.add('${group.rawValue}: $sets Sätze pro Woche – viel; auf Erholung achten.');
        }
      }
    }
    return PlanResult(routines: routines, notes: notes, corrections: corrections);
  }
}

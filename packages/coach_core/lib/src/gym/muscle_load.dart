import 'dart:math' as math;

import '../util/enum_codec.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gym_session.dart';
import 'routine.dart';

/// Einzelne Muskeln für die Heatmap (feiner als `MuscleGroup`).
enum Muscle implements RawEnum {
  chest,
  frontDelts,
  sideDelts,
  rearDelts,
  traps,
  lats,
  lowerBack,
  biceps,
  triceps,
  forearms,
  abs,
  obliques,
  glutes,
  quads,
  hamstrings,
  adductors,
  calves;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    chest => 'Brust',
    frontDelts => 'Vordere Schulter',
    sideDelts => 'Seitliche Schulter',
    rearDelts => 'Hintere Schulter',
    traps => 'Nacken (Trapez)',
    lats => 'Latissimus',
    lowerBack => 'Unterer Rücken',
    biceps => 'Bizeps',
    triceps => 'Trizeps',
    forearms => 'Unterarme',
    abs => 'Bauch',
    obliques => 'Seitliche Bauchmuskeln',
    glutes => 'Gesäß',
    quads => 'Oberschenkel vorn',
    hamstrings => 'Oberschenkel hinten',
    adductors => 'Adduktoren',
    calves => 'Waden',
  };

  /// Zuordnung zur bisherigen Muskelgruppe (Filter in der Bibliothek).
  MuscleGroup get group => switch (this) {
    chest => MuscleGroup.chest,
    frontDelts || sideDelts || rearDelts => MuscleGroup.shoulders,
    traps || lats || lowerBack => MuscleGroup.back,
    biceps => MuscleGroup.biceps,
    triceps => MuscleGroup.triceps,
    forearms => MuscleGroup.forearms,
    abs || obliques => MuscleGroup.core,
    glutes || quads || hamstrings || adductors || calves => MuscleGroup.legs,
  };

  static Muscle? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Wie stark eine Übung welchen Muskel beansprucht: Hauptmuskel 1, mitarbeitende Muskeln 0,5 („fractional sets“,
/// wie die Auswertung von Pelland et al. 2025). Praxis-Zuordnung, keine Messung.
abstract final class MuscleMap {
  static const primary = 1.0;
  static const secondary = 0.5;

  // dart format off
  static const Map<String, Map<Muscle, double>> table = {
    'bankdruecken': {Muscle.chest: 1.0, Muscle.triceps: 0.5, Muscle.frontDelts: 0.5},
    'kurzhantel_bankdruecken': {Muscle.chest: 1.0, Muscle.triceps: 0.5, Muscle.frontDelts: 0.5},
    'schraegbankdruecken': {Muscle.chest: 1.0, Muscle.frontDelts: 0.5, Muscle.triceps: 0.5},
    'kurzhantel_schraegbankdruecken': {Muscle.chest: 1.0, Muscle.frontDelts: 0.5, Muscle.triceps: 0.5},
    'brustpresse': {Muscle.chest: 1.0, Muscle.triceps: 0.5, Muscle.frontDelts: 0.5},
    'fliegende': {Muscle.chest: 1.0, Muscle.frontDelts: 0.5},
    'fliegende_kabel_hoch': {Muscle.chest: 1.0, Muscle.frontDelts: 0.5},
    'liegestuetze': {Muscle.chest: 1.0, Muscle.triceps: 0.5, Muscle.frontDelts: 0.5, Muscle.abs: 0.5},
    'klimmzug': {Muscle.lats: 1.0, Muscle.biceps: 0.5, Muscle.rearDelts: 0.5, Muscle.forearms: 0.5},
    'latziehen': {Muscle.lats: 1.0, Muscle.biceps: 0.5, Muscle.rearDelts: 0.5},
    'latziehen_einarmig': {Muscle.lats: 1.0, Muscle.biceps: 0.5},
    'rudern_langhantel': {Muscle.lats: 1.0, Muscle.traps: 0.5, Muscle.rearDelts: 0.5, Muscle.biceps: 0.5, Muscle.lowerBack: 0.5},
    'rudern_kurzhantel': {Muscle.lats: 1.0, Muscle.traps: 0.5, Muscle.rearDelts: 0.5, Muscle.biceps: 0.5},
    'rudern_kabel': {Muscle.lats: 1.0, Muscle.traps: 0.5, Muscle.rearDelts: 0.5, Muscle.biceps: 0.5},
    'rudern_koerpergewicht': {Muscle.lats: 1.0, Muscle.traps: 0.5, Muscle.rearDelts: 0.5, Muscle.biceps: 0.5},
    'kabel_pullover': {Muscle.lats: 1.0},
    'rueckenstrecker': {Muscle.lowerBack: 1.0, Muscle.glutes: 0.5, Muscle.hamstrings: 0.5},
    'schulterdruecken': {Muscle.frontDelts: 1.0, Muscle.sideDelts: 0.5, Muscle.triceps: 0.5},
    'kurzhantel_schulterdruecken': {Muscle.frontDelts: 1.0, Muscle.sideDelts: 0.5, Muscle.triceps: 0.5},
    'seitheben': {Muscle.sideDelts: 1.0},
    'seitheben_kabel': {Muscle.sideDelts: 1.0},
    'frontheben': {Muscle.frontDelts: 1.0},
    'reverse_fly': {Muscle.rearDelts: 1.0, Muscle.traps: 0.5},
    'reverse_fly_kabel': {Muscle.rearDelts: 1.0, Muscle.traps: 0.5},
    'face_pull': {Muscle.rearDelts: 1.0, Muscle.traps: 0.5},
    'aufrechtes_rudern': {Muscle.sideDelts: 1.0, Muscle.traps: 0.5},
    'shrugs': {Muscle.traps: 1.0},
    'bizeps_curl': {Muscle.biceps: 1.0, Muscle.forearms: 0.5},
    'kurzhantel_curl': {Muscle.biceps: 1.0, Muscle.forearms: 0.5},
    'hammer_curl': {Muscle.biceps: 1.0, Muscle.forearms: 0.5},
    'hammer_curl_kabel': {Muscle.biceps: 1.0, Muscle.forearms: 0.5},
    'kabel_curl_liegend': {Muscle.biceps: 1.0},
    'trizeps_pushdown': {Muscle.triceps: 1.0},
    'trizepsstrecken': {Muscle.triceps: 1.0},
    'trizeps_kabel_schraegbank': {Muscle.triceps: 1.0},
    'dips': {Muscle.triceps: 1.0, Muscle.chest: 0.5, Muscle.frontDelts: 0.5},
    'dips_barren': {Muscle.triceps: 1.0, Muscle.chest: 0.5, Muscle.frontDelts: 0.5},
    'handgelenk_curl': {Muscle.forearms: 1.0},
    'kniebeuge': {Muscle.quads: 1.0, Muscle.glutes: 1.0, Muscle.adductors: 0.5, Muscle.lowerBack: 0.5},
    'goblet_squat': {Muscle.quads: 1.0, Muscle.glutes: 0.5, Muscle.adductors: 0.5},
    'beinpresse': {Muscle.quads: 1.0, Muscle.glutes: 0.5, Muscle.adductors: 0.5},
    'ausfallschritt': {Muscle.quads: 1.0, Muscle.glutes: 1.0, Muscle.adductors: 0.5},
    'bulgarische_kniebeuge': {Muscle.quads: 1.0, Muscle.glutes: 1.0, Muscle.adductors: 0.5},
    'rumaenisches_kreuzheben': {Muscle.hamstrings: 1.0, Muscle.glutes: 1.0, Muscle.lowerBack: 0.5},
    'kreuzheben': {Muscle.glutes: 1.0, Muscle.hamstrings: 0.5, Muscle.quads: 0.5, Muscle.lowerBack: 0.5, Muscle.traps: 0.5, Muscle.forearms: 0.5},
    'hueftstoss': {Muscle.glutes: 1.0, Muscle.hamstrings: 0.5},
    'beinstrecken': {Muscle.quads: 1.0},
    'beinbeugen': {Muscle.hamstrings: 1.0},
    'wadenheben': {Muscle.calves: 1.0},
    'kettlebell_swing': {Muscle.glutes: 1.0, Muscle.hamstrings: 0.5, Muscle.lowerBack: 0.5},
    'plank': {Muscle.abs: 1.0, Muscle.obliques: 0.5},
    'seitstuetz': {Muscle.obliques: 1.0, Muscle.abs: 0.5},
    'dead_bug': {Muscle.abs: 1.0},
    'crunch': {Muscle.abs: 1.0},
    'crunch_geraet': {Muscle.abs: 1.0},
    'crunch_kabel': {Muscle.abs: 1.0},
    'beinheben': {Muscle.abs: 1.0},
    'pallof': {Muscle.obliques: 1.0, Muscle.abs: 0.5},
    'rotation': {Muscle.obliques: 1.0, Muscle.abs: 0.5},
  };
  // dart format on

  /// Hauptmuskel je Muskelgruppe (für eigene und unbekannte Übungen).
  static const Map<MuscleGroup, Muscle> main = {
    MuscleGroup.chest: Muscle.chest,
    MuscleGroup.back: Muscle.lats,
    MuscleGroup.shoulders: Muscle.sideDelts,
    MuscleGroup.biceps: Muscle.biceps,
    MuscleGroup.triceps: Muscle.triceps,
    MuscleGroup.legs: Muscle.quads,
    MuscleGroup.core: Muscle.abs,
    MuscleGroup.forearms: Muscle.forearms,
  };

  /// Beanspruchung einer Übung; eigene Übungen über Muskelgruppe und mitarbeitende Gruppen.
  static Map<Muscle, double> involvement(
    String exerciseID, {
    required MuscleGroup group,
    List<ExerciseInfo> custom = const [],
  }) {
    if (table[exerciseID] case final known?) return known;
    final result = <Muscle, double>{};
    final info = ExerciseLibrary.info(exerciseID, custom: custom);
    if (main[info?.group ?? group] case final muscle?) result[muscle] = primary;
    for (final other in info?.secondary ?? const <MuscleGroup>[]) {
      if (main[other] case final muscle? when result[muscle] == null) result[muscle] = secondary;
    }
    return result;
  }
}

/// Erholungsstand eines Muskels.
enum MuscleRecovery {
  /// Nennenswert belastet in den letzten 48 h: vermutlich noch in der Erholung.
  recovering,

  /// Bereit.
  ready,

  /// Länger als `neglectedDays` ohne nennenswerte Belastung (oder noch nie).
  neglected;

  String get label => switch (this) {
    recovering => 'vermutlich noch in der Erholung',
    ready => 'bereit',
    neglected => 'länger nicht trainiert',
  };
}

/// Stand eines Muskels.
final class MuscleStatus {
  const MuscleStatus({
    required this.muscle,
    required this.weeklySets,
    required this.averageWeeklySets,
    required this.lastLoaded,
    required this.recovery,
  });

  final Muscle muscle;

  /// Effektive Sätze der letzten 7 Tage.
  final double weeklySets;

  /// Effektive Sätze der letzten 28 Tage, je Woche gemittelt.
  final double averageWeeklySets;

  /// Letzte nennenswerte Belastung.
  final DateTime? lastLoaded;
  final MuscleRecovery recovery;

  String get id => muscle.rawValue;

  /// Unter dem, was als ausreichend gilt.
  bool get isLow => weeklySets < MuscleLoad.weeklyEnough;

  @override
  String toString() => 'MuscleStatus($muscle, $weeklySets, $averageWeeklySets, $recovery)';
}

/// Muskelbeanspruchung aus Arbeitssätzen: Hauptmuskel zählt einen Satz voll, mitarbeitende Muskeln halb. Ein Satz
/// zählt je Muskel genau einmal (keine Doppelzählung über Gruppen). Sätze weit weg vom Versagen (RIR 4 oder mehr)
/// und Drop-Sätze zählen halb, Aufwärmsätze nicht. Grundlage: Sätze je Muskel und Woche (Schoenfeld et al. 2017,
/// Pelland et al. 2025); die Gewichte 1/0,5 und die Regenerationsgrenzen sind Praxiswerte, keine Messung von
/// Ermüdung.
abstract final class MuscleLoad {
  /// Unter dieser Menge (Sätze je Muskel) gilt eine Einheit nicht als nennenswerte Belastung.
  static const meaningfulSets = 2.0;

  /// So lange nach nennenswerter Belastung gilt ein Muskel als „vermutlich noch in der Erholung“.
  static const recoveryHours = 48.0;

  /// Ab so vielen Tagen ohne nennenswerte Belastung: „länger nicht trainiert“.
  static const neglectedDays = 10;

  /// Ab so vielen Sätzen pro Woche gilt ein Muskel als ausreichend trainiert – wie `MuscleVolume.goodLower`.
  static const weeklyEnough = MuscleVolume.goodLower * 1.0;

  /// Volle Farbe in der Wochen-Heatmap.
  static const weeklyFull = 10.0;

  /// Wie stark ein Satz zählt.
  static double setFactor(LoggedSet set) {
    if (set.kind == SetKind.warmup || set.reps <= 0) return 0;
    if (set.kind == SetKind.drop) return 0.5;
    if (set.rir case final rir? when rir >= 4) return 0.5;
    return 1;
  }

  /// Effektive Sätze je Muskel einer Einheit (nur abgehakte Sätze).
  static Map<Muscle, double> session(GymSession session, {List<ExerciseInfo> custom = const []}) {
    final result = <Muscle, double>{};
    for (final exercise in session.exercises) {
      final sets = exercise.sets.where((set) => set.done).fold(0.0, (sum, set) => sum + setFactor(set));
      if (sets <= 0) continue;
      final involvement = MuscleMap.involvement(exercise.exerciseID, group: exercise.group, custom: custom);
      for (final MapEntry(key: muscle, value: share) in involvement.entries) {
        result[muscle] = (result[muscle] ?? 0) + sets * share;
      }
    }
    return result;
  }

  /// Geplante Sätze je Muskel einer Routine (eine Einheit).
  static Map<Muscle, double> routine(Routine routine, {List<ExerciseInfo> custom = const []}) {
    final result = <Muscle, double>{};
    for (final item in routine.items) {
      final group = ExerciseLibrary.info(item.exerciseID, custom: custom)?.group ?? MuscleGroup.other;
      for (final MapEntry(key: muscle, value: share) in MuscleMap.involvement(
        item.exerciseID,
        group: group,
        custom: custom,
      ).entries) {
        result[muscle] = (result[muscle] ?? 0) + item.sets * share;
      }
    }
    return result;
  }

  /// Stand je Muskel zu [now]: Wochensätze, Mittel über 4 Wochen, letzte Belastung, Regeneration.
  static List<MuscleStatus> status({
    required List<GymSession> sessions,
    required DateTime now,
    List<ExerciseInfo> custom = const [],
  }) {
    final week = now.subtract(const Duration(days: 7));
    final month = now.subtract(const Duration(days: 28));
    final weekly = <Muscle, double>{};
    final monthly = <Muscle, double>{};
    final last = <Muscle, DateTime>{};
    for (final item in sessions) {
      if (item.start.isAfter(now)) continue;
      final load = session(item, custom: custom);
      for (final MapEntry(key: muscle, value: sets) in load.entries) {
        if (!item.start.isBefore(week)) weekly[muscle] = (weekly[muscle] ?? 0) + sets;
        if (!item.start.isBefore(month)) monthly[muscle] = (monthly[muscle] ?? 0) + sets;
        final finished = item.end ?? item.start;
        final previous = last[muscle];
        if (sets >= meaningfulSets && (previous == null || previous.isBefore(finished))) last[muscle] = finished;
      }
    }
    return [
      for (final muscle in Muscle.values)
        () {
          final lastLoaded = last[muscle];
          final hours = lastLoaded == null ? null : now.difference(lastLoaded).inMicroseconds / 1e6 / 3600;
          final MuscleRecovery recovery;
          if (hours != null && hours < recoveryHours) {
            recovery = MuscleRecovery.recovering;
          } else if (hours != null && hours < neglectedDays * 24) {
            recovery = MuscleRecovery.ready;
          } else {
            recovery = MuscleRecovery.neglected;
          }
          return MuscleStatus(
            muscle: muscle,
            weeklySets: ((weekly[muscle] ?? 0) * 10).roundToDouble() / 10,
            averageWeeklySets: ((monthly[muscle] ?? 0) / 4 * 10).roundToDouble() / 10,
            lastLoaded: lastLoaded,
            recovery: recovery,
          );
        }(),
    ];
  }

  /// Farbstufe 0…1 für die Heatmap: 0 = nichts, 1 = viel (ab [full] Sätzen).
  static double intensity(double sets, {required double full}) {
    if (full <= 0) return 0;
    return math.min(math.max(sets / full, 0), 1);
  }
}

import 'dart:convert';
import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gym_session.dart';

/// Eine Zeile aus `ZEXERCISELOG`.
final class GymBookLogRow {
  const GymBookLogRow({
    required this.day,
    required this.secondsOfDay,
    required this.exercise,
    this.region,
    this.muscles,
    this.equipment,
    required this.frequency,
    this.frequencyUnit = 'x',
    required this.quantity,
    this.quantityUnit = 'kg',
    this.skipped = false,
    this.workout,
  });

  final String day;
  final double secondsOfDay;
  final String exercise;

  /// z. B. `020.chest`
  final String? region;

  /// z. B. `041.armFlexors|040.armExtensors`
  final String? muscles;

  /// z. B. `070.cableMachine`
  final String? equipment;
  final double? frequency;

  /// `x` Wiederholungen, `s` Sekunden, `m` Distanz
  final String? frequencyUnit;
  final double? quantity;
  final String? quantityUnit;
  final bool skipped;
  final String? workout;
}

/// Ergebnis eines Imports.
final class GymBookResult {
  const GymBookResult({required this.sessions, required this.newCustom, required this.ignoredRows});

  final List<GymSession> sessions;

  /// Neue eigene Übungen für GymBook-Übungen ohne Gegenstück in der Bibliothek.
  final List<ExerciseInfo> newCustom;

  /// Zeilen, die nicht übernommen wurden (ausgelassen, Ausdauer, ohne Wiederholungen).
  final int ignoredRows;
}

/// Verlauf aus einem GymBook-Backup („GymBook-Backup-….database“, SQLite/Core Data) übernehmen. Die App liest die
/// Zeilen aus `ZEXERCISELOG` (verbunden mit `ZEXERCISE` und `ZWORKOUT`); hier werden sie zu Einheiten.
///
/// Felder im Backup (GymBook 7.1.9): `ZDAY` = Tag (`yyyy-MM-dd`), `ZTIME` = Sekunden seit Mitternacht,
/// `ZFREQUENCYVALUE` = Wiederholungen bzw. Sekunden (`ZFREQUENCYUNIT` `x` bzw. `s`), `ZQUANTITYVALUE` = Gewicht in
/// `ZQUANTITYUNIT` (kg), `ZSKIPPED` = ausgelassen. Ausdauer-Einträge (`m`, km) gehören nicht ins Gym-Protokoll.
abstract final class GymBookImport {
  /// GymBook-Übungen mit gleichem Bewegungsablauf in der Bibliothek. Varianten mit anderem Gerät (Multipresse,
  /// Maschine statt Langhantel) bleiben eigene Übungen, weil die Gewichte nicht vergleichbar sind.
  static const Map<String, String> mapping = {
    'Dips am Barren': 'dips_barren',
    'Einarmiges Seitwärtsheben am Tiefen Kabel': 'seitheben_kabel',
    'Curls in Hammerhaltung am Kabel': 'hammer_curl_kabel',
    'Lat-Ziehen mit Breitem Griff': 'latziehen',
    'Bankdrücken mit Langhantel': 'bankdruecken',
    'Armstrecken am Kabel': 'trizeps_pushdown',
    'Enges Rudern am Kabel Sitzend': 'rudern_kabel',
    'Schrägbankdrücken mit Langhantel': 'schraegbankdruecken',
    'Armstrecken am Tiefen Kabel auf Schrägbank': 'trizeps_kabel_schraegbank',
    'Beinstrecken': 'beinstrecken',
    'Fersenheben am Gerät Stehend': 'wadenheben',
    'Crunches am Gerät': 'crunch_geraet',
    'Beinbeugen Sitzend': 'beinbeugen',
    'Beinpressen Sitzend': 'beinpresse',
    'Curls am Kabel liegend': 'kabel_curl_liegend',
    'Flyings am Hohen Kabel': 'fliegende_kabel_hoch',
    'Einarmiges Lat-Ziehen': 'latziehen_einarmig',
    'Oberkörperheben': 'rueckenstrecker',
    'Face-Pulls am Kabel Sitzend': 'face_pull',
    'Crunches am Kabel Kniend': 'crunch_kabel',
    'Reverse-Flyings am Hohen Kabel': 'reverse_fly_kabel',
    'Pallof-Press am Kabel': 'pallof',
    'Planks': 'plank',
    'Pull-Over am Kabel Sitzend': 'kabel_pullover',
    'Bulgarische Split-Kniebeugen mit Kurzhanteln': 'bulgarische_kniebeuge',
    'Rumänisches Kreuzheben mit Langhantel': 'rumaenisches_kreuzheben',
    'Beinheben am Gerät': 'beinheben',
    'Abwechselnde Curls in Hammerhaltung': 'hammer_curl',
    'Curls mit SZ-Stange': 'bizeps_curl',
  };

  /// Stabile ID je Tag und Routine, damit ein zweiter Import nichts doppelt anlegt.
  static String workoutKey({required String day, required String? workout}) => 'gymbook:$day:${workout ?? ''}';

  /// [midnight]: Mitternacht eines Tages in der gewünschten Zeitzone (Standard: Zeitzone des Geräts).
  static GymBookResult sessions(
    List<GymBookLogRow> rows, {
    required List<ExerciseInfo> custom,
    DateTime Function(CalendarDay day)? midnight,
  }) {
    final midnightOf = midnight ?? (day) => DateTime(day.year, day.month, day.day);
    final known = [...custom];
    final newCustom = <ExerciseInfo>[];
    var ignored = 0;
    final groups = <String, List<GymBookLogRow>>{};
    for (final row in rows) {
      final unit = row.frequencyUnit ?? 'x';
      final value = row.frequency;
      if (row.skipped ||
          !(unit == 'x' || unit == 's') ||
          value == null ||
          value <= 0 ||
          CalendarDay.tryParse(row.day) == null) {
        ignored += 1;
        continue;
      }
      groups.putIfAbsent(workoutKey(day: row.day, workout: row.workout), () => []).add(row);
    }

    final sessions = <GymSession>[];
    for (final MapEntry(:key, value: group) in groups.entries) {
      final sorted = [...group]..sort((a, b) => a.secondsOfDay.compareTo(b.secondsOfDay));
      final first = sorted.first;
      final day = CalendarDay.tryParse(first.day);
      if (day == null) continue;
      final start0 = midnightOf(day);
      final exercises = <LoggedExercise>[];
      for (final row in sorted) {
        final info = exerciseInfo(row, custom: known, newCustom: newCustom);
        final set = LoggedSet(reps: (row.frequency ?? 0).round(), weightKg: math.max(row.quantity ?? 0, 0));
        final index = exercises.lastIndexWhere((exercise) => exercise.exerciseID == info.id);
        if (index >= 0) {
          exercises[index].sets.add(set);
        } else {
          exercises.add(
            LoggedExercise(
              exerciseID: info.id,
              name: info.name,
              group: info.group,
              sets: [set],
              restSeconds: info.compound ? 120 : 90,
            ),
          );
        }
      }
      Duration seconds(double value) => Duration(microseconds: (value * 1e6).round());
      sessions.add(
        GymSession(
          id: stableID(key),
          workoutKey: key,
          title: first.workout?.trim() ?? 'GymBook',
          start: start0.add(seconds(first.secondsOfDay)),
          end: start0.add(seconds(sorted.last.secondsOfDay + 60)),
          exercises: exercises,
        ),
      );
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    return GymBookResult(sessions: sessions, newCustom: newCustom, ignoredRows: ignored);
  }

  /// Übung zur Zeile; neue eigene Übungen landen in [custom] und [newCustom].
  static ExerciseInfo exerciseInfo(
    GymBookLogRow row, {
    required List<ExerciseInfo> custom,
    required List<ExerciseInfo> newCustom,
  }) {
    if (mapping[row.exercise] case final id?) {
      if (ExerciseLibrary.info(id) case final info?) return info;
    }
    final tracking = row.frequencyUnit == 's' ? ExerciseTracking.time : ExerciseTracking.weightReps;
    final made = ExerciseInfo.custom(
      name: row.exercise,
      group: group(region: row.region, muscles: row.muscles),
      equipment: equipment(row.equipment),
      tracking: tracking,
    );
    for (final item in custom) {
      if (item.id == made.id) return item;
    }
    custom.add(made);
    newCustom.add(made);
    return made;
  }

  static MuscleGroup group({required String? region, required String? muscles}) {
    final area = region ?? '';
    final parts = muscles ?? '';
    if (area.endsWith('arms')) {
      return parts.contains('armFlexors') && !parts.contains('armExtensors') ? MuscleGroup.biceps : MuscleGroup.triceps;
    }
    if (area.endsWith('chest')) return MuscleGroup.chest;
    if (area.endsWith('back')) return MuscleGroup.back;
    if (area.endsWith('shoulders')) return MuscleGroup.shoulders;
    if (area.endsWith('abdomen')) return MuscleGroup.core;
    if (area.endsWith('legs') || area.endsWith('buttocks')) return MuscleGroup.legs;
    return MuscleGroup.other;
  }

  static Equipment equipment(String? text) {
    final value = text ?? '';
    if (value.contains('cable')) return Equipment.cable;
    if (value.contains('Machine') || value.contains('smith')) return Equipment.machine;
    if (value.contains('barbell') || value.contains('ezBar')) return Equipment.barbell;
    if (value.contains('dumbbell')) return Equipment.dumbbell;
    if (value.contains('kettlebell')) return Equipment.kettlebell;
    return Equipment.bodyweight;
  }

  /// UUID aus dem Schlüssel (FNV-1a, 64 Bit mit Überlauf wie `&*` in Swift), damit dieselbe Einheit immer dieselbe
  /// ID bekommt – gleiche Werte wie die Swift-App.
  static String stableID(String key) {
    // Dart-Ganzzahlen auf iOS/Android sind 64 Bit und laufen wie `UInt64` mit `&*` über.
    var first = 0xcbf29ce484222325;
    var second = 0x84222325cbf29ce4;
    const prime = 0x00000100000001b3;
    for (final byte in utf8.encode(key)) {
      first = (first ^ byte) * prime;
      second = (second ^ byte) * prime + 1;
    }
    final bytes = List<int>.filled(16, 0);
    for (var index = 0; index < 8; index++) {
      bytes[index] = (first >>> (index * 8)) & 0xFF;
      bytes[index + 8] = (second >>> (index * 8)) & 0xFF;
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join().toUpperCase();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

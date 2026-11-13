import 'dart:math' as math;

import '../nutrition/meal.dart' show newUuid;
import '../profile/user_profile.dart';
import '../util/enum_codec.dart';
import '../util/int_range.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gym_tools.dart';

final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

String? _readUuid(Object? value) => value is String && _uuid.hasMatch(value) ? value.toUpperCase() : null;

/// Eine Übung in einer Routine: Sätze, Wiederholungsbereich und Pause.
final class RoutineItem {
  RoutineItem({
    String? id,
    required this.exerciseID,
    required this.name,
    required int sets,
    required int lowerReps,
    required int upperReps,
    required this.restSeconds,
    this.weightKg,
    this.supersetWithNext = false,
  }) : id = id ?? newUuid(),
       sets = math.max(sets, 1),
       lowerReps = math.max(lowerReps, 1),
       upperReps = math.max(math.max(upperReps, lowerReps), 1);

  /// Standardwerte aus der Bibliothek.
  factory RoutineItem.fromExercise(ExerciseInfo exercise, {int sets = 3}) => RoutineItem(
    exerciseID: exercise.id,
    name: exercise.name,
    sets: sets,
    lowerReps: exercise.lowerReps,
    upperReps: exercise.upperReps,
    restSeconds: exercise.compound ? 120 : 90,
  );

  RoutineItem._decoded({
    required this.id,
    required this.exerciseID,
    required this.name,
    required this.sets,
    required this.lowerReps,
    required this.upperReps,
    required this.restSeconds,
    required this.weightKg,
    required this.supersetWithNext,
  });

  String id;
  String exerciseID;
  String name;
  int sets;
  int lowerReps;
  int upperReps;
  int restSeconds;

  /// Startgewicht, solange es für die Übung noch keinen Verlauf gibt (z. B. aus GymBook übernommen).
  double? weightKg;

  /// Mit der folgenden Übung als Supersatz (abwechselnd, Pause nach der Runde).
  bool supersetWithNext;

  /// Wie `ClosedRange` in Swift; gespeicherte Werte mit Obergrenze unter Untergrenze werden nicht korrigiert.
  IntRange get repRange => IntRange(lowerReps, math.max(lowerReps, upperReps));

  RoutineItem copy() => RoutineItem._decoded(
    id: id,
    exerciseID: exerciseID,
    name: name,
    sets: sets,
    lowerReps: lowerReps,
    upperReps: upperReps,
    restSeconds: restSeconds,
    weightKg: weightKg,
    supersetWithNext: supersetWithNext,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'exerciseID': exerciseID,
    'name': name,
    'sets': sets,
    'lowerReps': lowerReps,
    'upperReps': upperReps,
    'restSeconds': restSeconds,
    'weightKg': ?weightKg,
    'supersetWithNext': supersetWithNext,
  };

  /// Wie der eigene Swift-Decoder: Pflichtfelder streng, Startgewicht und Supersatz nachsichtig, keine Korrektur.
  static RoutineItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _readUuid(json['id']);
    final (exerciseID, name, sets) = (json['exerciseID'], json['name'], json['sets']);
    final (lower, upper, rest) = (json['lowerReps'], json['upperReps'], json['restSeconds']);
    if (id == null ||
        exerciseID is! String ||
        name is! String ||
        sets is! int ||
        lower is! int ||
        upper is! int ||
        rest is! int) {
      return null;
    }
    final superset = json['supersetWithNext'];
    return RoutineItem._decoded(
      id: id,
      exerciseID: exerciseID,
      name: name,
      sets: sets,
      lowerReps: lower,
      upperReps: upper,
      restSeconds: rest,
      weightKg: jsonDouble(json['weightKg']),
      supersetWithNext: superset is bool && superset,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoutineItem &&
      other.id == id &&
      other.exerciseID == exerciseID &&
      other.name == name &&
      other.sets == sets &&
      other.lowerReps == lowerReps &&
      other.upperReps == upperReps &&
      other.restSeconds == restSeconds &&
      other.weightKg == weightKg &&
      other.supersetWithNext == supersetWithNext;

  @override
  int get hashCode =>
      Object.hash(id, exerciseID, name, sets, lowerReps, upperReps, restSeconds, weightKg, supersetWithNext);

  @override
  String toString() => 'RoutineItem($exerciseID, $sets × $lowerReps–$upperReps)';
}

/// Eigene Trainingseinheit (wie ein Workout in GymBook).
final class Routine {
  Routine({String? id, required this.name, required this.items}) : id = id ?? newUuid();

  String id;
  String name;
  List<RoutineItem> items;

  /// Muskelgruppen mit ihren Sätzen, für die Übersicht.
  Map<MuscleGroup, int> get setsPerGroup {
    final result = <MuscleGroup, int>{};
    for (final item in items) {
      final group = ExerciseLibrary.info(item.exerciseID)?.group ?? MuscleGroup.other;
      result[group] = (result[group] ?? 0) + item.sets;
    }
    return result;
  }

  Routine copy() => Routine(id: id, name: name, items: [for (final item in items) item.copy()]);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'items': [for (final item in items) item.toJson()],
  };

  static Routine? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _readUuid(json['id']);
    final name = json['name'];
    final items = listStrict(json['items'], RoutineItem.fromJson);
    if (id == null || name is! String || items == null) return null;
    return Routine(id: id, name: name, items: items);
  }

  @override
  bool operator ==(Object other) =>
      other is Routine &&
      other.id == id &&
      other.name == name &&
      other.items.length == items.length &&
      _deepEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(items));

  @override
  String toString() => 'Routine($name, $items)';
}

/// Zielbereiche je Übung aus allen Routinen (für die Progression).
extension RoutineRanges on List<Routine> {
  Map<String, IntRange> get repRanges => {
    for (final item in expand((routine) => routine.items)) item.exerciseID: item.repRange,
  };
}

/// Vorschläge für Routinen nach Profil, Anzahl der Krafttage und Ausstattung.
///
/// Aufbau: Jeder große Muskel wird mindestens zweimal pro Woche trainiert (Schoenfeld et al. 2016). Bei 1–3 Tagen
/// Ganzkörper, bei 4 Tagen Ober-/Unterkörper, ab 5 Tagen zusätzlich Push/Pull/Beine. Wiederholungsbereiche im
/// mittleren Bereich: Muskelaufbau gelingt über ein breites Lastspektrum (Schoenfeld et al. 2017), Grundübungen
/// etwas schwerer. Sätze je Übung nach Erfahrung (Einsteiger 2, sonst 3).
abstract final class RoutineTemplates {
  /// Die vier Pläne aus GymBook (Stand 27.10.2026, aus den Screenshots des Nutzers): je 2 Sätze à 12 Wiederholungen,
  /// Planks 2 × 60 Sekunden, mit den zuletzt genutzten Gewichten als Startwert.
  static List<Routine> get gymBook {
    RoutineItem item(String id, String name, double? weight, {int reps = 12, int rest = 90}) => RoutineItem(
      exerciseID: id,
      name: name,
      sets: 2,
      lowerReps: reps == 60 ? 60 : 10,
      upperReps: reps,
      restSeconds: rest,
      weightKg: weight,
    );

    // dart format off
    return [
      Routine(
        name: 'Lower',
        items: [
          item('beinbeugen', 'Beinbeugen Sitzend', 110),
          item('beinstrecken', 'Beinstrecken', 120),
          item('beinpresse', 'Beinpressen Sitzend', 149, rest: 120),
          item('wadenheben', 'Fersenheben am Gerät Stehend', 117),
          item('crunch_geraet', 'Crunches am Gerät', 90),
        ]),
      Routine(
        name: 'Push & Pull B',
        items: [
          item('hammer_curl_kabel', 'Curls in Hammerhaltung am Kabel', 22.5),
          item('trizeps_kabel_schraegbank', 'Armstrecken am Tiefen Kabel auf Schrägbank', 32.5),
          item('latziehen', 'Lat-Ziehen mit Breitem Griff', 85, rest: 120),
          item('bankdruecken', 'Bankdrücken mit Langhantel', 52.5, rest: 120),
          item('reverse_fly_kabel', 'Reverse-Flyings am Hohen Kabel', 7.5),
          item('dips_barren', 'Dips am Barren', 79),
        ]),
      Routine(
        name: 'Pull A',
        items: [
          item('rudern_kabel', 'Enges Rudern am Kabel Sitzend', 110, rest: 120),
          item('kabel_curl_liegend', 'Curls am Kabel liegend', 50),
          item('latziehen_einarmig', 'Einarmiges Lat-Ziehen', 52.5),
          item('hammer_curl_kabel', 'Curls in Hammerhaltung am Kabel', 22.5),
          item('face_pull', 'Face-Pulls am Kabel Sitzend', 45),
          item('crunch_kabel', 'Crunches am Kabel Kniend', 65),
        ]),
      Routine(
        name: 'Push A',
        items: [
          item('fliegende_kabel_hoch', 'Flyings am Hohen Kabel', 22.5),
          item('trizeps_kabel_schraegbank', 'Armstrecken am Tiefen Kabel auf Schrägbank', 32.5),
          item('bankdruecken', 'Bankdrücken mit Langhantel', 52.5, rest: 120),
          item('seitheben_kabel', 'Einarmiges Seitwärtsheben am Tiefen Kabel', 13.75),
          item('dips_barren', 'Dips am Barren', 79),
          item('plank', 'Planks', null, reps: 60),
        ]),
    ];
  }
  // dart format on

  /// Je Platz Übungen in Reihenfolge der Vorliebe; die erste machbare wird genommen.
  // dart format off
  static const Map<String, ({String name, List<List<String>> slots})> slots = {
    'ganzkoerper_a': (
      name: 'Ganzkörper A',
      slots: [
        ['kniebeuge', 'goblet_squat', 'beinpresse', 'bulgarische_kniebeuge'],
        ['bankdruecken', 'kurzhantel_bankdruecken', 'brustpresse', 'liegestuetze'],
        ['rudern_kabel', 'rudern_kurzhantel', 'rudern_langhantel', 'rudern_koerpergewicht'],
        ['rumaenisches_kreuzheben', 'hueftstoss'],
        ['seitheben'],
        ['plank'],
      ],
    ),
    'ganzkoerper_b': (
      name: 'Ganzkörper B',
      slots: [
        ['rumaenisches_kreuzheben', 'hueftstoss', 'kettlebell_swing'],
        ['kurzhantel_schulterdruecken', 'schulterdruecken', 'seitheben'],
        ['kurzhantel_schraegbankdruecken', 'schraegbankdruecken', 'liegestuetze'],
        ['latziehen', 'klimmzug', 'rudern_kurzhantel', 'rudern_koerpergewicht'],
        ['ausfallschritt', 'bulgarische_kniebeuge', 'beinpresse'],
        ['kurzhantel_curl', 'bizeps_curl', 'hammer_curl'],
        ['trizeps_pushdown', 'trizepsstrecken', 'dips'],
        ['dead_bug', 'crunch'],
      ],
    ),
    'ganzkoerper_c': (
      name: 'Ganzkörper C',
      slots: [
        ['beinpresse', 'goblet_squat', 'bulgarische_kniebeuge'],
        ['kurzhantel_schraegbankdruecken', 'schraegbankdruecken', 'liegestuetze'],
        ['rudern_kurzhantel', 'rudern_kabel', 'rudern_koerpergewicht'],
        ['hueftstoss', 'rumaenisches_kreuzheben'],
        ['face_pull', 'reverse_fly'],
        ['seitstuetz'],
      ],
    ),
    'oberkoerper_a': (
      name: 'Oberkörper A',
      slots: [
        ['bankdruecken', 'kurzhantel_bankdruecken', 'brustpresse', 'liegestuetze'],
        ['rudern_langhantel', 'rudern_kabel', 'rudern_kurzhantel', 'rudern_koerpergewicht'],
        ['kurzhantel_schulterdruecken', 'schulterdruecken'],
        ['latziehen', 'klimmzug', 'rudern_kurzhantel'],
        ['kurzhantel_curl', 'bizeps_curl'],
        ['trizeps_pushdown', 'trizepsstrecken'],
      ],
    ),
    'unterkoerper_a': (
      name: 'Unterkörper A',
      slots: [
        ['kniebeuge', 'goblet_squat', 'beinpresse'],
        ['rumaenisches_kreuzheben', 'hueftstoss'],
        ['ausfallschritt', 'bulgarische_kniebeuge'],
        ['beinbeugen', 'hueftstoss'],
        ['wadenheben'],
        ['plank'],
      ],
    ),
    'oberkoerper_b': (
      name: 'Oberkörper B',
      slots: [
        ['kurzhantel_schraegbankdruecken', 'schraegbankdruecken', 'liegestuetze'],
        ['klimmzug', 'latziehen', 'rudern_kurzhantel'],
        ['rudern_kabel', 'rudern_kurzhantel', 'rudern_koerpergewicht'],
        ['seitheben'],
        ['face_pull', 'reverse_fly'],
        ['hammer_curl', 'kurzhantel_curl'],
        ['trizepsstrecken', 'trizeps_pushdown', 'dips'],
      ],
    ),
    'unterkoerper_b': (
      name: 'Unterkörper B',
      slots: [
        ['kreuzheben', 'rumaenisches_kreuzheben', 'kettlebell_swing'],
        ['beinpresse', 'goblet_squat', 'bulgarische_kniebeuge'],
        ['bulgarische_kniebeuge', 'ausfallschritt'],
        ['beinstrecken', 'goblet_squat'],
        ['wadenheben'],
        ['dead_bug', 'beinheben'],
      ],
    ),
    'push': (
      name: 'Push (Brust, Schultern, Trizeps)',
      slots: [
        ['bankdruecken', 'kurzhantel_bankdruecken', 'liegestuetze'],
        ['kurzhantel_schulterdruecken', 'schulterdruecken'],
        ['kurzhantel_schraegbankdruecken', 'fliegende'],
        ['seitheben'],
        ['trizeps_pushdown', 'trizepsstrecken', 'dips'],
      ],
    ),
    'pull': (
      name: 'Pull (Rücken, Bizeps)',
      slots: [
        ['klimmzug', 'latziehen'],
        ['rudern_langhantel', 'rudern_kabel', 'rudern_kurzhantel'],
        ['face_pull', 'reverse_fly'],
        ['bizeps_curl', 'kurzhantel_curl'],
        ['hammer_curl'],
      ],
    ),
    'beine': (
      name: 'Beine',
      slots: [
        ['kniebeuge', 'goblet_squat', 'beinpresse'],
        ['rumaenisches_kreuzheben', 'hueftstoss'],
        ['beinpresse', 'bulgarische_kniebeuge'],
        ['beinbeugen', 'hueftstoss'],
        ['wadenheben'],
      ],
    ),
  };
  // dart format on

  /// Welche Vorlagen bei wie vielen Krafttagen.
  static List<String> templateKeys({required int strengthDays}) => switch (strengthDays) {
    <= 2 => ['ganzkoerper_a', 'ganzkoerper_b'],
    3 => ['ganzkoerper_a', 'ganzkoerper_b', 'ganzkoerper_c'],
    4 => ['oberkoerper_a', 'unterkoerper_a', 'oberkoerper_b', 'unterkoerper_b'],
    _ => ['push', 'pull', 'beine', 'oberkoerper_a', 'unterkoerper_a'],
  };

  static List<Routine> suggest({required UserProfile profile, required Set<Equipment> equipment}) {
    final days = math.max(profile.schedule.count(TrainingSport.strength), 1);
    final level = profile.level(TrainingSport.strength);
    final sets = level == ExperienceLevel.beginner ? 2 : 3;
    return [for (final key in templateKeys(strengthDays: days)) ?routine(key, sets: sets, equipment: equipment)];
  }

  static Routine? routine(String key, {required int sets, required Set<Equipment> equipment}) {
    final template = slots[key];
    if (template == null) return null;
    final used = <String>{};
    final items = <RoutineItem>[];
    for (final options in template.slots) {
      ExerciseInfo? pick;
      for (final id in options) {
        final info = ExerciseLibrary.byID[id];
        if (info != null && info.isAvailable(equipment) && !used.contains(info.id)) {
          pick = info;
          break;
        }
      }
      if (pick == null) continue;
      used.add(pick.id);
      items.add(RoutineItem.fromExercise(pick, sets: sets));
    }
    return items.isEmpty ? null : Routine(name: template.name, items: items);
  }
}

/// Satz nach dem Eintippen von Werten automatisch abhaken (und die Pause starten).
enum CompleteOnEdit implements RawEnum {
  off,
  afterReps,
  always;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    off => 'Nie – ich tippe „Satz erledigt“',
    afterReps => 'Nach den Wiederholungen',
    always => 'Nach Gewicht oder Wiederholungen',
  };

  /// Ob eine Eingabe in diesem Feld den Satz abhakt.
  bool completes({required bool afterEditingReps}) => switch (this) {
    off => false,
    afterReps => afterEditingReps,
    always => true,
  };

  static CompleteOnEdit? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Ton am Ende der Satzpause. Eigene Töne liegen als WAV in der App, weil Mitteilungen nur solche abspielen können.
enum RestSound implements RawEnum {
  off,
  system,
  chime,
  bell,
  beep;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    off => 'Aus',
    system => 'Mitteilungston',
    chime => 'Gong',
    bell => 'Glocke',
    beep => 'Piepen',
  };

  String? get fileName => switch (this) {
    off || system => null,
    chime => 'rest-chime.wav',
    bell => 'rest-bell.wav',
    beep => 'rest-beep.wav',
  };

  static RestSound? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Gym-Einstellungen: eigene Routinen, eigene Übungen, Ausstattung.
final class GymSettings {
  GymSettings({
    List<Routine>? routines,
    List<ExerciseInfo>? customExercises,
    Set<Equipment>? equipment,
    this.tracksRIR = true,
  }) : routines = routines ?? [],
       customExercises = customExercises ?? [],
       equipment = equipment ?? {...Equipment.gym};

  List<Routine> routines;
  List<ExerciseInfo> customExercises;
  Set<Equipment> equipment;

  /// Wiederholungen in Reserve je Satz abfragen.
  bool tracksRIR;

  /// Beendete Einheiten als Krafttraining nach Garmin Connect übertragen.
  bool uploadsToGarmin = true;

  /// Ohne Aufzeichnung der Uhr nach einigen Stunden als eigene Aktivität hochladen.
  bool garminFallbackUpload = true;

  /// Bildschirm während der Einheit nicht sperren.
  bool keepsScreenOn = true;

  /// Langhantelstange in kg (Standard 20) und vorhandene Scheiben für den Scheibenrechner.
  double barKg = PlateCalculator.standardBar;
  List<double> plates = [...PlateCalculator.standardPlates];

  /// Andere Stange je Übung (z. B. SZ-Stange 10 kg für Curls).
  Map<String, double> bars = {};

  /// Notiz je Übung (Sitzhöhe, Griffbreite, Gerätenummer).
  Map<String, String> notes = {};

  /// Gemerkte Pause je Übung in Sekunden (aus ±15 s während der Einheit).
  Map<String, int> restOverrides = {};

  /// Pause und nächster Satz als Live-Aktivität auf dem Sperrbildschirm.
  bool liveActivity = true;

  /// Standardpausen in Sekunden, wenn weder die Routine noch die Übung eine eigene haben.
  int restCompound = 120;
  int restIsolation = 90;

  /// Pause nach Aufwärmsätzen (kürzer, sie ermüden kaum).
  int restWarmup = 60;

  /// Nach „Satz erledigt“ die Pause sofort starten.
  bool autoStartsRest = true;

  /// Vor dem ersten Arbeitssatz einer Grundübung Aufwärmsätze vorschlagen.
  bool suggestsWarmUp = true;

  /// Satz nach dem Eintippen von Werten abhaken.
  CompleteOnEdit completeOnEdit = CompleteOnEdit.off;

  /// Ton am Ende der Satzpause.
  RestSound restSound = RestSound.chime;

  /// Vibration am Ende der Satzpause.
  bool restHaptic = true;

  /// Vorlagenwerte der Pläne. Sie sagen nichts über einen Wunsch aus und dürfen die Einstellungen nicht überdecken.
  static const templateRestCompound = 120;
  static const templateRestIsolation = 90;

  /// Pause einer Übung. Vorrang: eigene Pause der Übung, dann eine bewusst andere Pause im Plan, dann der Standard aus
  /// den Einstellungen. Aufwärmsätze haben ihre eigene Pause ([restWarmup]).
  int rest(String exerciseID, {required bool compound, int? planned}) {
    if (restOverrides[exerciseID] case final own?) return own;
    final template = compound ? templateRestCompound : templateRestIsolation;
    if (planned != null && planned != template) return planned;
    return compound ? restCompound : restIsolation;
  }

  /// Stange für eine Übung.
  double bar(String exerciseID) => bars[exerciseID] ?? barKg;

  /// Übung zur ID inklusive eigener Übungen.
  ExerciseInfo? exercise(String id) => ExerciseLibrary.info(id, custom: customExercises);

  void addCustom(ExerciseInfo exercise) {
    customExercises
      ..removeWhere((item) => item.id == exercise.id)
      ..add(exercise);
  }

  Map<String, Object?> toJson() => {
    'routines': [for (final routine in routines) routine.toJson()],
    'customExercises': [for (final exercise in customExercises) exercise.toJson()],
    'equipment': [
      for (final item in Equipment.values)
        if (equipment.contains(item)) item.rawValue,
    ],
    'tracksRIR': tracksRIR,
    'uploadsToGarmin': uploadsToGarmin,
    'garminFallbackUpload': garminFallbackUpload,
    'keepsScreenOn': keepsScreenOn,
    'barKg': barKg,
    'plates': plates,
    'bars': bars,
    'notes': notes,
    'restOverrides': restOverrides,
    'liveActivity': liveActivity,
    'restCompound': restCompound,
    'restIsolation': restIsolation,
    'restWarmup': restWarmup,
    'autoStartsRest': autoStartsRest,
    'suggestsWarmUp': suggestsWarmUp,
    'completeOnEdit': completeOnEdit.rawValue,
    'restSound': restSound.rawValue,
    'restHaptic': restHaptic,
  };

  /// Wie der eigene Swift-Decoder: jedes Feld einzeln, Unlesbares fällt auf den Standard zurück.
  static GymSettings fromJson(Object? json) {
    final settings = GymSettings();
    if (json is! Map) return settings;
    bool flag(String key, bool fallback) => json[key] is bool ? json[key] as bool : fallback;
    int number(String key, int fallback) => json[key] is int ? json[key] as int : fallback;
    Map<String, T>? map<T>(String key, T? Function(Object?) read) {
      final raw = json[key];
      if (raw is! Map) return null;
      final result = <String, T>{};
      for (final entry in raw.entries) {
        final value = read(entry.value);
        if (entry.key is! String || value == null) return null;
        result[entry.key as String] = value;
      }
      return result;
    }

    settings
      ..routines = listStrict(json['routines'], Routine.fromJson) ?? []
      ..customExercises = listStrict(json['customExercises'], ExerciseInfo.fromJson) ?? []
      ..equipment = enumListStrict(Equipment.values, json['equipment'])?.toSet() ?? {...Equipment.gym}
      ..tracksRIR = flag('tracksRIR', true)
      ..uploadsToGarmin = flag('uploadsToGarmin', true)
      ..garminFallbackUpload = flag('garminFallbackUpload', true)
      ..keepsScreenOn = flag('keepsScreenOn', true)
      ..barKg = jsonDouble(json['barKg']) ?? PlateCalculator.standardBar
      ..plates = listStrict(json['plates'], jsonDouble) ?? [...PlateCalculator.standardPlates]
      ..bars = map('bars', jsonDouble) ?? {}
      ..notes = map('notes', (value) => value is String ? value : null) ?? {}
      ..restOverrides = map('restOverrides', (value) => value is int ? value : null) ?? {}
      ..liveActivity = flag('liveActivity', true)
      ..restCompound = number('restCompound', 120)
      ..restIsolation = number('restIsolation', 90)
      ..restWarmup = number('restWarmup', 60)
      ..autoStartsRest = flag('autoStartsRest', true)
      ..suggestsWarmUp = flag('suggestsWarmUp', true)
      ..completeOnEdit = CompleteOnEdit.fromRaw(json['completeOnEdit']) ?? CompleteOnEdit.off
      ..restSound = RestSound.fromRaw(json['restSound']) ?? RestSound.chime
      ..restHaptic = flag('restHaptic', true);
    return settings;
  }

  @override
  bool operator ==(Object other) => other is GymSettings && _deepEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(routines.length, customExercises.length, tracksRIR, barKg);
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!_deepEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

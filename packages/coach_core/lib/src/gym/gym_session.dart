import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../nutrition/meal.dart' show newUuid;
import '../util/enum_codec.dart';
import '../util/swift_date.dart';
import 'exercise_catalog.dart';

/// Art eines Satzes. Aufwärmsätze zählen nicht für Volumen, Bestleistungen und Progression.
enum SetKind implements RawEnum {
  working,
  warmup,
  drop,
  failure;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    working => 'Arbeitssatz',
    warmup => 'Aufwärmen',
    drop => 'Drop-Satz',
    failure => 'Bis zum Versagen',
  };

  /// Kürzel in der Satzliste („A“ statt der Nummer).
  String? get badge => switch (this) {
    working => null,
    warmup => 'A',
    drop => 'D',
    failure => 'V',
  };

  static SetKind? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Ein Satz: Wiederholungen (bei Haltübungen Sekunden) und Gewicht in kg. 0 = Körpergewicht; bei Übungen mit
/// Körpergewicht ist ein positiver Wert Zusatzgewicht, ein negativer Unterstützung (z. B. −20 kg am Gerät).
final class LoggedSet {
  LoggedSet({
    String? id,
    required this.reps,
    required this.weightKg,
    this.done = true,
    this.rir,
    this.kind = SetKind.working,
  }) : id = id ?? newUuid();

  /// Feste Kennung für die Anzeige (Löschen und Verschieben treffen den richtigen Satz).
  String id;
  int reps;
  double weightKg;

  /// Abgehakt: nur abgehakte Sätze zählen.
  bool done;

  /// Wiederholungen in Reserve (RIR): wie viele noch gegangen wären; `null` = nicht angegeben.
  int? rir;
  SetKind kind;

  /// Last für Volumen und 1RM: Unterstützung zählt als Körpergewicht (0).
  double get loadKg => math.max(weightKg, 0);

  LoggedSet copy() => LoggedSet(id: id, reps: reps, weightKg: weightKg, done: done, rir: rir, kind: kind);

  Map<String, Object?> toJson() => {
    'id': id,
    'reps': reps,
    'weightKg': weightKg,
    'done': done,
    'rir': ?rir,
    'kind': kind.rawValue,
  };

  /// Nachsichtig wie der eigene Swift-Decoder: fehlende oder unlesbare Kennung, Status, RIR und Art bekommen Standards.
  static LoggedSet? fromJson(Object? json) {
    if (json is! Map) return null;
    final reps = json['reps'];
    final weight = jsonDouble(json['weightKg']);
    if (reps is! int || weight == null) return null;
    final id = json['id'];
    final done = json['done'];
    final rir = json['rir'];
    return LoggedSet(
      id: id is String && _uuid.hasMatch(id) ? id.toUpperCase() : null,
      reps: reps,
      weightKg: weight,
      done: done is bool ? done : true,
      rir: rir is int ? rir : null,
      kind: SetKind.fromRaw(json['kind']) ?? SetKind.working,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LoggedSet &&
      other.id == id &&
      other.reps == reps &&
      other.weightKg == weightKg &&
      other.done == done &&
      other.rir == rir &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, reps, weightKg, done, rir, kind);

  @override
  String toString() => 'LoggedSet($reps × $weightKg, done: $done, rir: $rir, $kind)';
}

final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

String? _readUuid(Object? value) => value is String && _uuid.hasMatch(value) ? value.toUpperCase() : null;

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Eine Übung innerhalb einer Einheit.
final class LoggedExercise {
  LoggedExercise({
    String? id,
    required this.exerciseID,
    required this.name,
    required this.group,
    required this.sets,
    this.restSeconds = 90,
    this.supersetID,
    this.skipped = false,
  }) : id = id ?? newUuid();

  String id;

  /// Kanonische Übung (`ExerciseRule.id`).
  String exerciseID;
  String name;
  MuscleGroup group;
  List<LoggedSet> sets;
  int restSeconds;

  /// Gleiche Kennung = Supersatz: die Übungen wechseln sich ab, Pause erst nach der Runde.
  String? supersetID;

  /// In dieser Einheit übersprungen: der Ablauf geht daran vorbei; offene Sätze werden nicht gespeichert.
  bool skipped;

  /// Erledigte Arbeitssätze (ohne Aufwärmen) – Grundlage für Volumen, Bestleistungen und Progression.
  List<LoggedSet> get doneSets => sets.where((set) => set.done && set.reps > 0 && set.kind != SetKind.warmup).toList();

  /// Alle erledigten Sätze inklusive Aufwärmen – so wird die Einheit gespeichert.
  List<LoggedSet> get loggedSets => sets.where((set) => set.done && set.reps > 0).toList();

  LoggedExercise copy() => LoggedExercise(
    id: id,
    exerciseID: exerciseID,
    name: name,
    group: group,
    sets: [for (final set in sets) set.copy()],
    restSeconds: restSeconds,
    supersetID: supersetID,
    skipped: skipped,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'exerciseID': exerciseID,
    'name': name,
    'group': group.rawValue,
    'sets': [for (final set in sets) set.toJson()],
    'restSeconds': restSeconds,
    'supersetID': ?supersetID,
    'skipped': skipped,
  };

  /// Ältere gespeicherte Einheiten kennen `skipped` noch nicht.
  static LoggedExercise? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _readUuid(json['id']);
    final (exerciseID, name, rest) = (json['exerciseID'], json['name'], json['restSeconds']);
    final group = MuscleGroup.fromRaw(json['group']);
    final sets = listStrict(json['sets'], LoggedSet.fromJson);
    if (id == null || exerciseID is! String || name is! String || group == null || sets == null || rest is! int) {
      return null;
    }
    final rawSuperset = json['supersetID'];
    final supersetID = _readUuid(rawSuperset);
    if (rawSuperset != null && supersetID == null) return null;
    final skipped = json['skipped'];
    return LoggedExercise(
      id: id,
      exerciseID: exerciseID,
      name: name,
      group: group,
      sets: sets,
      restSeconds: rest,
      supersetID: supersetID,
      skipped: skipped is bool && skipped,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LoggedExercise &&
      other.id == id &&
      other.exerciseID == exerciseID &&
      other.name == name &&
      other.group == group &&
      _listEquals(other.sets, sets) &&
      other.restSeconds == restSeconds &&
      other.supersetID == supersetID &&
      other.skipped == skipped;

  @override
  int get hashCode => Object.hash(id, exerciseID, name, group, Object.hashAll(sets), restSeconds, supersetID, skipped);

  @override
  String toString() => 'LoggedExercise($exerciseID, $sets)';
}

/// Status der Verbindung mit Garmin Connect.
enum GarminLinkStatus implements RawEnum {
  /// Wartet auf die Aufzeichnung der Uhr (die Uhr synchronisiert oft erst später).
  pending,

  /// Sätze in die Aufzeichnung der Uhr geschrieben.
  enriched,

  /// Ohne Aufzeichnung der Uhr als eigene Aktivität hochgeladen.
  uploaded,
  failed;

  @override
  String get rawValue => name;

  static GarminLinkStatus? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Verbindung einer Einheit mit Garmin Connect: Sätze in der Aufzeichnung der Uhr oder eigene Aktivität.
final class GarminLink {
  GarminLink({required this.status, this.activityID, this.note, required this.updatedAt});

  GarminLinkStatus status;
  int? activityID;
  String? note;
  DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'status': status.rawValue,
    'activityID': ?activityID,
    'note': ?note,
    'updatedAt': swiftDateToJson(updatedAt),
  };

  static GarminLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final status = GarminLinkStatus.fromRaw(json['status']);
    final updatedAt = swiftDateFromJson(json['updatedAt']);
    if (status == null || updatedAt == null) return null;
    final activityID = json['activityID'];
    final note = json['note'];
    return GarminLink(
      status: status,
      activityID: activityID is int ? activityID : null,
      note: note is String ? note : null,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GarminLink &&
      other.status == status &&
      other.activityID == activityID &&
      other.note == note &&
      other.updatedAt.isAtSameMomentAs(updatedAt);

  @override
  int get hashCode => Object.hash(status, activityID, note, updatedAt.microsecondsSinceEpoch);
}

/// Eine Krafteinheit.
final class GymSession {
  GymSession({
    String? id,
    required this.workoutKey,
    required this.title,
    required this.start,
    this.end,
    required this.exercises,
    this.garmin,
  }) : id = id ?? newUuid();

  String id;
  String? workoutKey;
  String title;
  DateTime start;
  DateTime? end;
  List<LoggedExercise> exercises;

  /// Abgleich mit Garmin; fehlt bei älteren Einheiten.
  GarminLink? garmin;

  /// Kalendertag in der Zeitzone des Geräts.
  CalendarDay get day => CalendarDay.fromDate(start.toLocal());

  int get doneSetCount => exercises.fold(0, (sum, exercise) => sum + exercise.doneSets.length);

  /// Bewegte Last (Gewicht × Wiederholungen) in kg.
  double get volumeKg =>
      exercises.expand((exercise) => exercise.doneSets).fold(0, (sum, set) => sum + set.loadKg * set.reps);

  GymSession copy() => GymSession(
    id: id,
    workoutKey: workoutKey,
    title: title,
    start: start,
    end: end,
    exercises: [for (final exercise in exercises) exercise.copy()],
    garmin: garmin,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'workoutKey': ?workoutKey,
    'title': title,
    'start': swiftDateToJson(start),
    if (end case final end?) 'end': swiftDateToJson(end),
    'exercises': [for (final exercise in exercises) exercise.toJson()],
    'garmin': ?garmin?.toJson(),
  };

  static GymSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _readUuid(json['id']);
    final title = json['title'];
    final start = swiftDateFromJson(json['start']);
    final exercises = listStrict(json['exercises'], LoggedExercise.fromJson);
    if (id == null || title is! String || start == null || exercises == null) return null;
    final workoutKey = json['workoutKey'];
    if (workoutKey != null && workoutKey is! String) return null;
    final rawEnd = json['end'];
    final end = swiftDateFromJson(rawEnd);
    if (rawEnd != null && end == null) return null;
    final rawGarmin = json['garmin'];
    final garmin = GarminLink.fromJson(rawGarmin);
    if (rawGarmin != null && garmin == null) return null;
    return GymSession(
      id: id,
      workoutKey: workoutKey as String?,
      title: title,
      start: start,
      end: end,
      exercises: exercises,
      garmin: garmin,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GymSession &&
      other.id == id &&
      other.workoutKey == workoutKey &&
      other.title == title &&
      other.start.isAtSameMomentAs(start) &&
      other.end?.microsecondsSinceEpoch == end?.microsecondsSinceEpoch &&
      _listEquals(other.exercises, exercises) &&
      other.garmin == garmin;

  @override
  int get hashCode => Object.hash(
    id,
    workoutKey,
    title,
    start.microsecondsSinceEpoch,
    end?.microsecondsSinceEpoch,
    Object.hashAll(exercises),
    garmin,
  );

  @override
  String toString() => 'GymSession($title, $start)';
}

/// Korrekturen beim Lesen gespeicherter Einheiten, ohne die gespeicherten Daten zu ändern.
///
/// „Crunches am Kabel kniend“ aus dem Saisonplan wurde früher über den Garmin-Schlüssel `KNEELING_CABLE_CRUNCH` dem
/// Körpergewichts-Crunch zugeordnet; das Gewicht erschien dann als Zusatz zum Körpergewicht. Solche Einträge gelten
/// jetzt als Kabel-Crunch (Gerätegewicht), damit Anzeige, Volumen und Progression mit den neuen Einheiten
/// zusammenpassen.
abstract final class ExerciseAliases {
  static LoggedExercise canonical(LoggedExercise exercise) {
    if (exercise.exerciseID != 'crunch' || !exercise.name.toLowerCase().contains('kabel')) return exercise;
    return exercise.copy()..exerciseID = 'crunch_kabel';
  }

  static GymSession normalized(GymSession session) =>
      session.copy()..exercises = session.exercises.map(canonical).toList();
}

/// Sätze je Muskelgruppe der letzten 7 Tage (Karte `coach-gym`, Modus Volumen, im Altbestand).
///
/// Grün ab 5 Sätzen: solider Kraftaufbau neben Ausdauertraining; mehr Sätze bringen mehr, aber mit abnehmendem
/// Ertrag (Schoenfeld 2017, Pelland 2025).
abstract final class MuscleVolume {
  static const goodLower = 5;
  static const goodUpper = 9;
  static const List<MuscleGroup> groups = [
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.shoulders,
    MuscleGroup.biceps,
    MuscleGroup.triceps,
    MuscleGroup.legs,
    MuscleGroup.core,
  ];

  static Map<MuscleGroup, int> setsPerGroup({required List<GymSession> sessions, required CalendarDay today}) {
    final start = today.adding(-6);
    final counts = {for (final group in groups) group: 0};
    for (final session in sessions) {
      final day = session.day;
      if (day < start || today < day) continue;
      for (final exercise in session.exercises) {
        if (counts[exercise.group] case final count?) counts[exercise.group] = count + exercise.doneSets.length;
      }
    }
    return counts;
  }

  /// Tage seit dem letzten Beintraining (`null` = noch nie).
  static int? daysSinceLegs({required List<GymSession> sessions, required CalendarDay today}) {
    CalendarDay? latest;
    for (final session in sessions) {
      if (!session.exercises.any((exercise) => exercise.group == MuscleGroup.legs && exercise.doneSets.isNotEmpty)) {
        continue;
      }
      if (latest == null || latest < session.day) latest = session.day;
    }
    return latest?.daysUntil(today);
  }
}

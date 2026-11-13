import 'dart:math' as math;

import '../analysis/activity_source.dart';
import '../fit/fit_encoder.dart';
import '../gym/exercise_catalog.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_session.dart';
import '../json/json_value.dart';
import 'garmin_activity.dart';

/// Art der Übertragung.
enum StrengthSyncMode { fill, replace }

/// Nutzdaten für `PUT exerciseSets`.
final class StrengthSyncResult {
  const StrengthSyncResult({required this.payload, required this.mode, required this.sets});

  final Map<String, Object?> payload;
  final StrengthSyncMode mode;
  final int sets;
}

/// Was mit einer Einheit geschieht.
sealed class StrengthSyncAction {
  const StrengthSyncAction();

  static const upload = _SyncPlain('upload');
  static const wait = _SyncPlain('wait');
  static const none = _SyncPlain('none');
}

final class StrengthSyncEnrich extends StrengthSyncAction {
  const StrengthSyncEnrich(this.activityID);

  final int activityID;

  @override
  bool operator ==(Object other) => other is StrengthSyncEnrich && other.activityID == activityID;

  @override
  int get hashCode => activityID.hashCode;

  @override
  String toString() => 'enrich($activityID)';
}

final class _SyncPlain extends StrengthSyncAction {
  const _SyncPlain(this.name);

  final String name;

  @override
  String toString() => name;
}

/// Ein abgehakter Satz mit seiner Übung.
final class _FlatSet {
  const _FlatSet({
    required this.exerciseID,
    required this.name,
    required this.group,
    required this.set,
    required this.isTime,
  });

  final String exerciseID;
  final String name;
  final MuscleGroup? group;
  final LoggedSet set;
  final bool isTime;
}

/// Ganzzahlige Werte wie `JSONEncoder` (1 statt 1.0).
Object _number(double value) => value == value.roundToDouble() && value.abs() < 9e15 ? value.toInt() : value;

/// Sätze einer Gym-Einheit in die Krafttraining-Aktivität der Uhr schreiben – statt einer zweiten Aktivität.
///
/// Garmin Connect kann zwei Aktivitäten nicht zusammenführen. Die Connect-Webseite bearbeitet die Sätze einer
/// Krafttraining-Aktivität aber über `GET/PUT /activity-service/activity/{id}/exerciseSets` (inoffiziell; so auch
/// python-garminconnect `set_activity_exercise_sets` und strong-garmin-sync, MIT-Lizenz). Damit bleiben Kalorien,
/// Herzfrequenz und Zeit der Uhr erhalten, und die Übungen, Wiederholungen und Gewichte kommen dazu.
///
/// Zwei Arten wie bei strong-garmin-sync: **Füllen**, wenn die Uhr mindestens so viele aktive Satz-Abschnitte
/// erkannt hat wie die App Sätze (die echte Zeit je Satz bleibt), sonst **Ersetzen** durch einen Satz je App-Satz,
/// gleichmäßig über die Dauer verteilt.
abstract final class GarminStrengthSync {
  /// Höchster Abstand der Startzeiten von Einheit und Uhr-Aktivität.
  static const matchWindow = Duration(hours: 2);

  /// Längere aktive Abschnitte sind kein einzelner Satz (die Uhr hat mehrere zusammengefasst).
  static const maxSetSeconds = 600.0;

  // Übungsnamen

  /// Garmins Kategorie und Unterkategorie als Text, wie die Satz-Schnittstelle sie erwartet (FIT-Profil,
  /// `ExerciseCategory` und `*ExerciseName`). Unterkategorien, die nicht sicher im Profil stehen, bleiben leer –
  /// Garmin nimmt die Kategorie allein immer an.
  // dart format off
  static const Map<String, ({String category, String? name})> names = {
    'bankdruecken': (category: 'BENCH_PRESS', name: 'BARBELL_BENCH_PRESS'),
    'kurzhantel_bankdruecken': (category: 'BENCH_PRESS', name: 'DUMBBELL_BENCH_PRESS'),
    'schraegbankdruecken': (category: 'BENCH_PRESS', name: 'INCLINE_BARBELL_BENCH_PRESS'),
    'kurzhantel_schraegbankdruecken': (category: 'BENCH_PRESS', name: 'INCLINE_DUMBBELL_BENCH_PRESS'),
    'brustpresse': (category: 'BENCH_PRESS', name: null),
    'fliegende': (category: 'FLYE', name: 'DUMBBELL_FLYE'),
    'fliegende_kabel_hoch': (category: 'FLYE', name: 'CABLE_CROSSOVER'),
    'liegestuetze': (category: 'PUSH_UP', name: 'PUSH_UP'),
    'klimmzug': (category: 'PULL_UP', name: 'PULL_UP'),
    'latziehen': (category: 'PULL_UP', name: 'WIDE_GRIP_LAT_PULLDOWN'),
    'latziehen_einarmig': (category: 'PULL_UP', name: 'LAT_PULLDOWN'),
    'kabel_pullover': (category: 'PULL_UP', name: 'STANDING_CABLE_PULLOVER'),
    'rudern_langhantel': (category: 'ROW', name: null),
    'rudern_kurzhantel': (category: 'ROW', name: 'DUMBBELL_ROW'),
    'rudern_kabel': (category: 'ROW', name: 'SEATED_CABLE_ROW'),
    'rudern_koerpergewicht': (category: 'ROW', name: null),
    'face_pull': (category: 'ROW', name: 'FACE_PULL'),
    'rueckenstrecker': (category: 'HYPEREXTENSION', name: null),
    'schulterdruecken': (category: 'SHOULDER_PRESS', name: 'OVERHEAD_BARBELL_PRESS'),
    'kurzhantel_schulterdruecken': (category: 'SHOULDER_PRESS', name: 'SEATED_DUMBBELL_SHOULDER_PRESS'),
    'seitheben': (category: 'LATERAL_RAISE', name: null),
    'seitheben_kabel': (category: 'LATERAL_RAISE', name: 'ONE_ARM_CABLE_LATERAL_RAISE'),
    'frontheben': (category: 'LATERAL_RAISE', name: 'FRONT_RAISE'),
    'reverse_fly': (category: 'FLYE', name: null),
    'reverse_fly_kabel': (category: 'FLYE', name: 'SINGLE_ARM_STANDING_CABLE_REVERSE_FLYE'),
    'aufrechtes_rudern': (category: 'SHRUG', name: null),
    'shrugs': (category: 'SHRUG', name: 'BARBELL_SHRUG'),
    'bizeps_curl': (category: 'CURL', name: 'BARBELL_BICEPS_CURL'),
    'kurzhantel_curl': (category: 'CURL', name: null),
    'hammer_curl': (category: 'CURL', name: 'DUMBBELL_HAMMER_CURL'),
    'hammer_curl_kabel': (category: 'CURL', name: 'CABLE_HAMMER_CURL'),
    'kabel_curl_liegend': (category: 'CURL', name: 'CABLE_BICEPS_CURL'),
    'handgelenk_curl': (category: 'CURL', name: null),
    'trizeps_pushdown': (category: 'TRICEPS_EXTENSION', name: 'TRICEPS_PRESSDOWN'),
    'trizepsstrecken': (category: 'TRICEPS_EXTENSION', name: 'OVERHEAD_DUMBBELL_TRICEPS_EXTENSION'),
    'trizeps_kabel_schraegbank': (category: 'TRICEPS_EXTENSION', name: 'CABLE_OVERHEAD_TRICEPS_EXTENSION'),
    'dips': (category: 'TRICEPS_EXTENSION', name: 'BODY_WEIGHT_DIP'),
    'dips_barren': (category: 'TRICEPS_EXTENSION', name: 'WEIGHTED_DIP'),
    'kniebeuge': (category: 'SQUAT', name: 'BARBELL_BACK_SQUAT'),
    'goblet_squat': (category: 'SQUAT', name: 'GOBLET_SQUAT'),
    'beinpresse': (category: 'SQUAT', name: 'LEG_PRESS'),
    'ausfallschritt': (category: 'LUNGE', name: 'DUMBBELL_LUNGE'),
    'bulgarische_kniebeuge': (category: 'LUNGE', name: null),
    'rumaenisches_kreuzheben': (category: 'DEADLIFT', name: null),
    'kreuzheben': (category: 'DEADLIFT', name: 'BARBELL_DEADLIFT'),
    'hueftstoss': (category: 'HIP_RAISE', name: null),
    'kettlebell_swing': (category: 'HIP_RAISE', name: 'KETTLEBELL_SWING'),
    'beinstrecken': (category: 'UNKNOWN', name: null),
    'beinbeugen': (category: 'LEG_CURL', name: 'LEG_CURL'),
    'wadenheben': (category: 'CALF_RAISE', name: 'STANDING_CALF_RAISE'),
    'plank': (category: 'PLANK', name: 'PLANK'),
    'seitstuetz': (category: 'PLANK', name: 'SIDE_PLANK'),
    'dead_bug': (category: 'HIP_STABILITY', name: 'DEAD_BUG'),
    'crunch': (category: 'CRUNCH', name: 'CRUNCH'),
    'crunch_geraet': (category: 'CRUNCH', name: 'WEIGHTED_CRUNCH'),
    'crunch_kabel': (category: 'CRUNCH', name: 'CABLE_CRUNCH'),
    'beinheben': (category: 'LEG_RAISE', name: 'HANGING_LEG_RAISE'),
    'pallof': (category: 'CORE', name: null),
    'rotation': (category: 'CORE', name: 'RUSSIAN_TWIST'),
  };
  // dart format on

  /// FIT-Kategorien als Text (für eigene Übungen über `GarminExerciseMapping`).
  static const Map<int, String> categories = {
    0: 'BENCH_PRESS',
    1: 'CALF_RAISE',
    5: 'CORE',
    6: 'CRUNCH',
    7: 'CURL',
    8: 'DEADLIFT',
    9: 'FLYE',
    10: 'HIP_RAISE',
    11: 'HIP_STABILITY',
    13: 'HYPEREXTENSION',
    14: 'LATERAL_RAISE',
    15: 'LEG_CURL',
    16: 'LEG_RAISE',
    17: 'LUNGE',
    19: 'PLANK',
    21: 'PULL_UP',
    22: 'PUSH_UP',
    23: 'ROW',
    24: 'SHOULDER_PRESS',
    26: 'SHRUG',
    28: 'SQUAT',
    30: 'TRICEPS_EXTENSION',
  };

  /// Kategorie und Name für Garmin. Eigene Übungen über Name bzw. Muskelgruppe der geloggten Übung (sonst kämen sie
  /// als „Unbekannt“ an).
  static ({String category, String? name}) garminName(String exerciseID, {String name = '', MuscleGroup? group}) {
    if (names[exerciseID] case final known?) return known;
    if (GarminExerciseMapping.libraryID(name) case final id?) {
      if (names[id] case final known?) return known;
    }
    final code = GarminExerciseMapping.code(exerciseID, name: name, group: group);
    return (category: categories[code.category] ?? 'UNKNOWN', name: null);
  }

  // Ablauf

  /// So lange wartet eine Einheit auf die Aufzeichnung der Uhr, bevor sie als eigene Aktivität hochgeladen wird.
  static const fallbackDelay = Duration(hours: 3);

  /// Was mit einer Einheit geschieht: nur wartende Einheiten werden bearbeitet (ältere ohne Verbindung bleiben
  /// unberührt). Mit Aufzeichnung der Uhr: Sätze hineinschreiben; ohne: warten, nach [fallbackDelay] hochladen.
  static StrengthSyncAction action(
    GymSession session, {
    required List<GarminActivity> activities,
    required Set<int> linked,
    required DateTime now,
    required bool fallbackUpload,
  }) {
    if (session.garmin?.status != GarminLinkStatus.pending) return StrengthSyncAction.none;
    if (match(session, activities: activities, linked: linked) case final found?) {
      return StrengthSyncEnrich(found.id);
    }
    final ended = session.end ?? session.start;
    return fallbackUpload && now.difference(ended) >= fallbackDelay
        ? StrengthSyncAction.upload
        : StrengthSyncAction.wait;
  }

  // Zuordnung

  /// Die Uhr-Aktivität zu einer Einheit: Krafttraining von Garmin (keine Apple-Health- oder nachgetragene), Start
  /// höchstens 2 h entfernt, noch keiner anderen Einheit zugeordnet. Bevorzugt mit Herzfrequenz (von der Uhr
  /// aufgezeichnet, kein hochgeladener Export), dann die nächstgelegene. Startzeiten in der Zeitzone des Geräts.
  static GarminActivity? match(
    GymSession session, {
    required List<GarminActivity> activities,
    required Set<int> linked,
  }) {
    (GarminActivity, Duration)? best;
    for (final activity in activities) {
      if (activity.sport != ActivitySport.strength ||
          ActivitySource.of(activity.id) != ActivitySource.garmin ||
          linked.contains(activity.id)) {
        continue;
      }
      final start = activityStart(activity);
      if (start == null) continue;
      final distance = start.difference(session.start).abs();
      if (distance > matchWindow) continue;
      final candidate = (activity, distance);
      if (best == null) {
        best = candidate;
        continue;
      }
      final candidateWatch = activity.averageHeartRate != null;
      final bestWatch = best.$1.averageHeartRate != null;
      // Wie `min(by:)`: nur ersetzen, wenn der Kandidat echt „kleiner“ ist.
      final better = candidateWatch != bestWatch ? candidateWatch : distance < best.$2;
      if (better) best = candidate;
    }
    return best?.$1;
  }

  /// Hat die Aktivität schon Wiederholungen (vom Benutzer oder einer früheren Übertragung)?
  static bool isEnriched(JsonValue exerciseSets) => (exerciseSets['exerciseSets']?.arrayValue ?? const <JsonValue>[])
      .any((set) => (set['repetitionCount']?.doubleValue ?? 0) > 0);

  // Nutzdaten

  /// Alle abgehakten Sätze in Reihenfolge, Aufwärmsätze eingeschlossen (sie sind tatsächlich gemacht worden).
  static List<_FlatSet> _flatten(GymSession session, List<ExerciseInfo> custom) => [
    for (final exercise in session.exercises)
      for (final set in exercise.loggedSets)
        _FlatSet(
          exerciseID: exercise.exerciseID,
          name: exercise.name,
          group: exercise.group,
          set: set,
          isTime: ExerciseLibrary.info(exercise.exerciseID, custom: custom)?.tracking == ExerciseTracking.time,
        ),
  ];

  /// Nutzdaten für PUT aus der Antwort von GET ([existing]). Rein, ohne Netz.
  static StrengthSyncResult payload({
    required JsonValue existing,
    required GymSession session,
    List<ExerciseInfo> custom = const [],
    bool useNames = true,
  }) {
    final rawRoot = existing.raw;
    final root = rawRoot is Map
        ? <String, Object?>{for (final entry in rawRoot.entries) '${entry.key}': entry.value}
        : <String, Object?>{};
    var sets = [for (final set in existing['exerciseSets']?.arrayValue ?? const <JsonValue>[]) set.raw];
    final flat = _flatten(session, custom);
    final active = [
      for (var index = 0; index < sets.length; index++)
        if (JsonValue(sets[index])['setType']?.stringValue == 'ACTIVE' &&
            (JsonValue(sets[index])['duration']?.doubleValue ?? 0) <= maxSetSeconds)
          index,
    ];
    final StrengthSyncMode mode;
    if (flat.isNotEmpty && active.length >= flat.length) {
      mode = StrengthSyncMode.fill;
      for (var offset = 0; offset < flat.length; offset++) {
        final index = active[offset];
        final original = sets[index];
        if (original is! Map) continue;
        sets[index] = {
          for (final entry in original.entries) '${entry.key}': entry.value,
          ..._fields(flat[offset], useNames: useNames),
        };
      }
    } else {
      mode = StrengthSyncMode.replace;
      final range =
          span([for (final set in sets) JsonValue(set)]) ??
          (start: session.start, end: session.end ?? session.start.add(const Duration(hours: 1)));
      final total = math.max(1.0, range.end.difference(range.start).inMicroseconds / 1e6);
      final gap = total / math.max(flat.length, 1);
      sets = [
        for (var offset = 0; offset < flat.length; offset++)
          () {
            final item = flat[offset];
            // Wie im FIT-Export: 3 s je Wiederholung, mindestens 20 s – nie länger als 80 % des Abstands.
            final duration = item.isTime
                ? item.set.reps.toDouble()
                : math.max(5.0, math.min(gap * 0.8, math.max(item.set.reps * 3.0, 20.0)));
            return <String, Object?>{
              ..._fields(item, useNames: useNames),
              'setType': 'ACTIVE',
              'startTime': timeText(range.start.add(Duration(microseconds: (gap * offset * 1e6).round()))),
              'duration': _number(duration),
              'wktStepIndex': null,
              'messageIndex': offset,
            };
          }(),
      ];
    }
    root['exerciseSets'] = sets;
    return StrengthSyncResult(payload: root, mode: mode, sets: flat.length);
  }

  /// Übung, Wiederholungen und Gewicht (Gramm) eines Satzes. Halteübungen ohne Wiederholungen; Körpergewicht und
  /// Unterstützung ohne Gewicht.
  static Map<String, Object?> _fields(_FlatSet item, {required bool useNames}) {
    final garmin = garminName(item.exerciseID, name: item.name, group: item.group);
    // `probability` wie bei einer in Connect bearbeiteten Übung (die Uhr setzt ihre Erkennungssicherheit).
    return {
      'exercises': [
        {'category': garmin.category, 'name': useNames ? garmin.name : null, 'probability': 100},
      ],
      'repetitionCount': item.isTime ? null : item.set.reps,
      'weight': item.set.weightKg > 0 ? _number((item.set.weightKg * 1000).roundToDouble()) : null,
    };
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// „2026-11-02T07:30:00.0“ in UTC.
  static String timeText(DateTime date) {
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${_two(utc.month)}-${_two(utc.day)}T${_two(utc.hour)}:'
        '${_two(utc.minute)}:${_two(utc.second)}.0';
  }

  static DateTime? parseTime(String? text) {
    if (text == null) return null;
    final head = String.fromCharCodes(text.runes.take(19));
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$').firstMatch(head);
    if (match == null) return null;
    final parts = [for (var group = 1; group <= 6; group++) int.parse(match.group(group)!)];
    if (parts[1] < 1 ||
        parts[1] > 12 ||
        parts[2] < 1 ||
        parts[2] > 31 ||
        parts[3] > 23 ||
        parts[4] > 59 ||
        parts[5] > 59) {
      return null;
    }
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  /// Anfang und Ende der Satz-Abschnitte der Uhr.
  static ({DateTime start, DateTime end})? span(List<JsonValue> sets) {
    DateTime? start;
    DateTime? end;
    for (final set in sets) {
      final begin = parseTime(set['startTime']?.stringValue);
      if (begin == null) continue;
      final finish = begin.add(Duration(microseconds: ((set['duration']?.doubleValue ?? 0) * 1e6).round()));
      if (start == null || begin.isBefore(start)) start = begin;
      if (end == null || finish.isAfter(end)) end = finish;
    }
    return start == null || end == null ? null : (start: start, end: end);
  }
}

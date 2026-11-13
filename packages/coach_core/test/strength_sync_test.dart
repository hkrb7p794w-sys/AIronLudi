// Port von GarminStrengthSyncTests.swift. Startzeiten der Aktivitäten stehen wie bei Garmin in der Ortszeit; die
// Tests rechnen sie aus der Zeitzone des Rechners, damit sie überall laufen.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// 01.11.2026, 10:00 UTC.
final start = DateTime.fromMillisecondsSinceEpoch(1793527200 * 1000, isUtc: true);

String two(int value) => value.toString().padLeft(2, '0');

String localText(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}';
}

GarminActivity activity(
  int id, {
  required double minutesAfter,
  double? heartRate = 120,
  String sport = 'strength_training',
}) => GarminActivity(id)
  ..typeKey = sport
  ..startLocal = localText(start.add(Duration(seconds: (minutesAfter * 60).round())))
  ..durationSeconds = 3600
  ..averageHeartRate = heartRate
  ..calories = 300;

GymSession session() => GymSession(
  workoutKey: null,
  title: 'Push',
  start: start,
  end: start.add(const Duration(hours: 1)),
  exercises: [
    LoggedExercise(
      exerciseID: 'bankdruecken',
      name: 'Bankdrücken',
      group: MuscleGroup.chest,
      sets: [
        LoggedSet(reps: 10, weightKg: 40, kind: SetKind.warmup),
        LoggedSet(reps: 8, weightKg: 80),
        LoggedSet(reps: 8, weightKg: 80, done: false),
      ],
    ),
    LoggedExercise(
      exerciseID: 'plank',
      name: 'Plank',
      group: MuscleGroup.core,
      sets: [LoggedSet(reps: 45, weightKg: 0)],
    ),
    LoggedExercise(
      exerciseID: 'klimmzug',
      name: 'Klimmzug',
      group: MuscleGroup.back,
      sets: [LoggedSet(reps: 6, weightKg: -20)],
    ),
  ],
  garmin: GarminLink(status: GarminLinkStatus.pending, updatedAt: start),
);

JsonValue watchSets(int count) => JsonValue({
  'activityId': 123,
  'exerciseSets': [
    for (var index = 0; index < count; index++) ...[
      {
        'setType': 'ACTIVE',
        'duration': 40,
        'startTime': '2026-11-01T10:0$index:00.0',
        'repetitionCount': null,
        'exercises': <Object?>[],
        'weight': null,
      },
      {'setType': 'REST', 'duration': 20, 'startTime': '2026-11-01T10:0$index:40.0'},
    ],
  ],
});

/// Nutzdaten wie nach dem Versand (JSON hin und zurück).
JsonValue sent(StrengthSyncResult result) => JsonValue(jsonDecode(jsonEncode(result.payload)));

void main() {
  test('füllt die Sätze der Uhr der Reihe nach', () {
    final result = GarminStrengthSync.payload(existing: watchSets(5), session: session());
    expect(result.mode, StrengthSyncMode.fill);
    expect(result.sets, 4);
    final payload = sent(result);
    final sets = payload['exerciseSets']!.arrayValue!;
    expect(sets.length, 10);
    expect(payload['activityId']?.doubleValue, 123);
    // Aufwärmsatz, Arbeitssatz, Plank (ohne Wiederholungen), Klimmzug mit Unterstützung (ohne Gewicht).
    expect(sets[0]['repetitionCount']?.doubleValue, 10);
    expect(sets[0]['weight']?.doubleValue, 40000);
    expect(sets[0]['exercises']?.arrayValue?.first['category']?.stringValue, 'BENCH_PRESS');
    expect(sets[0]['exercises']?.arrayValue?.first['name']?.stringValue, 'BARBELL_BENCH_PRESS');
    expect(sets[1]['setType']?.stringValue, 'REST');
    expect(sets[2]['weight']?.doubleValue, 80000);
    expect(sets[4]['repetitionCount']?.isNull, isTrue);
    expect(sets[4]['exercises']?.arrayValue?.first['name']?.stringValue, 'PLANK');
    expect(sets[6]['weight']?.isNull, isTrue);
    expect(sets[6]['repetitionCount']?.doubleValue, 6);
    // Überzählige Abschnitte der Uhr bleiben, wie sie sind; die Zeit der Uhr bleibt erhalten.
    expect(sets[8]['repetitionCount']?.isNull, isTrue);
    expect(sets[0]['duration']?.doubleValue, 40);
  });

  test('ersetzt, wenn die Uhr Sätze zusammengefasst hat', () {
    final result = GarminStrengthSync.payload(existing: watchSets(2), session: session(), useNames: false);
    expect(result.mode, StrengthSyncMode.replace);
    final payload = sent(result);
    final sets = payload['exerciseSets']!.arrayValue!;
    expect(sets.length, 4);
    expect(sets.every((set) => set['setType']?.stringValue == 'ACTIVE'), isTrue);
    expect(sets[0]['startTime']?.stringValue, '2026-11-01T10:00:00.0');
    expect(sets[3]['messageIndex']?.doubleValue, 3);
    expect(sets[2]['duration']?.doubleValue, 45);
    expect(sets[0]['exercises']?.arrayValue?.first['name']?.isNull, isTrue);
    expect(GarminStrengthSync.isEnriched(watchSets(2)), isFalse);
    expect(GarminStrengthSync.isEnriched(payload), isTrue);
  });

  test('ohne Sätze der Uhr gilt die Zeit der Einheit', () {
    final result = GarminStrengthSync.payload(existing: JsonValue({'exerciseSets': <Object?>[]}), session: session());
    final sets = sent(result)['exerciseSets']!.arrayValue!;
    expect(sets.first['startTime']?.stringValue, '2026-11-01T10:00:00.0');
    expect(sets.last['startTime']?.stringValue, '2026-11-01T10:45:00.0');
  });

  test('ordnet die Aufzeichnung der Uhr zu, nicht den Upload oder Verknüpftes', () {
    final upload = activity(1, minutesAfter: 2, heartRate: null);
    final watch = activity(2, minutesAfter: 20);
    final far = activity(3, minutesAfter: 200);
    final run = activity(4, minutesAfter: 1, sport: 'running');
    expect(GarminStrengthSync.match(session(), activities: [upload, watch, far, run], linked: {})?.id, 2);
    expect(GarminStrengthSync.match(session(), activities: [watch, far], linked: {2}), isNull);
    expect(GarminStrengthSync.match(session(), activities: [upload], linked: {})?.id, 1);
    final health = activity(-5, minutesAfter: 0);
    expect(GarminStrengthSync.match(session(), activities: [health], linked: {}), isNull);
  });

  test('wartet, dann eigener Upload', () {
    final watch = activity(2, minutesAfter: 5);
    final end = start.add(const Duration(hours: 1));
    expect(
      GarminStrengthSync.action(session(), activities: [watch], linked: {}, now: end, fallbackUpload: true),
      const StrengthSyncEnrich(2),
    );
    expect(
      GarminStrengthSync.action(session(), activities: [], linked: {}, now: end, fallbackUpload: true),
      StrengthSyncAction.wait,
    );
    final later = end.add(GarminStrengthSync.fallbackDelay);
    expect(
      GarminStrengthSync.action(session(), activities: [], linked: {}, now: later, fallbackUpload: true),
      StrengthSyncAction.upload,
    );
    expect(
      GarminStrengthSync.action(session(), activities: [], linked: {}, now: later, fallbackUpload: false),
      StrengthSyncAction.wait,
    );
    final old = session()..garmin = null;
    expect(
      GarminStrengthSync.action(old, activities: [watch], linked: {}, now: end, fallbackUpload: true),
      StrengthSyncAction.none,
    );
  });

  test('ersetzte Sätze mit realistischer Dauer und Sicherheit', () {
    // Ohne Uhr-Abschnitte: Einheit über 60 min, 15 min Abstand je Satz.
    final result = GarminStrengthSync.payload(existing: JsonValue({'exerciseSets': <Object?>[]}), session: session());
    final sets = sent(result)['exerciseSets']!.arrayValue!;
    // 10 Wiederholungen → 30 s statt pauschal 2:00; Halteübung behält ihre Zeit.
    expect(sets[0]['duration']?.doubleValue, 30);
    expect(sets[1]['duration']?.doubleValue, 24);
    expect(sets[2]['duration']?.doubleValue, 45);
    expect(sets[3]['duration']?.doubleValue, 20);
    expect(sets[0]['exercises']?.arrayValue?.first['probability']?.doubleValue, 100);
  });

  // Eigene Übungen (auch aus dem GymBook-Import) kamen als „Unbekannt“ in Garmin an.
  test('eigene Übungen über Name, dann Muskelgruppe', () {
    expect(
      GarminStrengthSync.garminName(
        'eigen_schulterdruecken_maschine',
        name: 'Schulterdrücken Maschine',
        group: MuscleGroup.shoulders,
      ).category,
      'SHOULDER_PRESS',
    );
    expect(GarminStrengthSync.garminName('eigen_x', name: 'Butterfly', group: MuscleGroup.chest).category, 'FLYE');
    expect(
      GarminStrengthSync.garminName('eigen_x', name: 'Bench Dips', group: MuscleGroup.triceps).name,
      'BODY_WEIGHT_DIP',
    );
    expect(
      GarminStrengthSync.garminName('eigen_x', name: 'Kurzhantel Curl Schrägbank', group: MuscleGroup.biceps).category,
      'CURL',
    );
    // Ohne passendes Stichwort: Muskelgruppe der geloggten Übung.
    expect(GarminStrengthSync.garminName('eigen_x', name: 'Maschine 7', group: MuscleGroup.back).category, 'ROW');
    expect(GarminStrengthSync.garminName('eigen_x', name: 'Maschine 7', group: MuscleGroup.other).category, 'UNKNOWN');
    expect(GarminExerciseMapping.libraryID('Kabelrudern'), isNull);
    expect(GarminExerciseMapping.libraryID('Rudern sitzend'), 'rudern_kabel');
    expect(GarminExerciseMapping.libraryID('Beinbeuger (Leg Curl)'), 'beinbeugen');
    expect(GarminExerciseMapping.libraryID(''), isNull);
  });

  test('Namen für jede Übung', () {
    expect(GarminStrengthSync.garminName('crunch_kabel').category, 'CRUNCH');
    expect(GarminStrengthSync.garminName('crunch_kabel').name, 'CABLE_CRUNCH');
    expect(GarminStrengthSync.garminName('beinstrecken').category, 'UNKNOWN');
    for (final exercise in ExerciseLibrary.all) {
      expect(GarminStrengthSync.names[exercise.id], isNotNull, reason: exercise.id);
    }
  });

  test('doppelter Upload wird übergangen', () {
    final upload = activity(1, minutesAfter: 3, heartRate: null);
    final watch = activity(2, minutesAfter: 0);
    final lone = activity(3, minutesAfter: 600, heartRate: null);
    expect(StrengthDuplicates.redundant([upload, watch, lone]), {1});
    expect(ActivityFeed.entries(activities: [upload, watch], gym: []).map((entry) => entry.id), ['a2']);
  });

  test('Verknüpfung übersteht das Speichern, alte Daten bleiben lesbar', () {
    final decoded = GymSession.fromJson(jsonDecode(jsonEncode(session().toJson())))!;
    expect(decoded.garmin?.status, GarminLinkStatus.pending);
    final old = session()..garmin = null;
    expect(GymSession.fromJson(jsonDecode(jsonEncode(old.toJson())))!.garmin, isNull);
  });

  test('Gym-Eintrag aus einer Einheit (GymItem.fromSession)', () {
    final item = GymItem.fromSession(session());
    expect(item.minutes, 60);
    expect(item.sets, 3);
    expect(item.volumeKg, 80 * 8 + 0 + 0);
    expect(item.title, 'Push');
  });
}

// Port von CoachCoreTests/GymTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 10, 22);

Object? roundTrip(Object? value) => jsonDecode(jsonEncode(value));

DateTime localNoon(CalendarDay day) => DateTime(day.year, day.month, day.day, 12);

GymSession session(
  String iso,
  String exerciseID, {
  required double weight,
  required List<int> reps,
  MuscleGroup group = MuscleGroup.chest,
}) {
  final day = CalendarDay.tryParse(iso) ?? today;
  final name = ExerciseCatalog.rulesByID[exerciseID]?.name ?? exerciseID;
  return GymSession(
    workoutKey: null,
    title: 'Test',
    start: localNoon(day),
    exercises: [
      LoggedExercise(
        exerciseID: exerciseID,
        name: name,
        group: group,
        sets: [for (final count in reps) LoggedSet(reps: count, weightKg: weight)],
      ),
    ],
  );
}

void main() {
  libraryTests();
  group('Übungskatalog', () {
    // Erwartungswerte: `exercise_names.classify` im Altbestand mit dem Trainingsplan.
    test('Standardplan wie im Altbestand', () {
      final ids = GymPlan.standard.workouts.expand((workout) => workout.exercises).map((exercise) => exercise.rule.id);
      expect(ids, [
        'fliegende', 'trizepsstrecken', 'bankdruecken', 'seitheben', 'dips', 'plank', //
        'rudern_kabel', 'bizeps_curl', 'latziehen_einarmig', 'hammer_curl', 'face_pull', 'crunch_kabel',
        'hammer_curl', 'trizepsstrecken', 'latziehen', 'bankdruecken', 'reverse_fly', 'dips',
        'beinbeugen', 'beinstrecken', 'beinpresse', 'wadenheben', 'crunch_geraet',
      ]);
      expect(GymPlan.standard.repRanges['bankdruecken'], const IntRange(8, 12));
      expect(GymPlan.standard.repRanges['plank'], isNull);
    });

    test('Zuordnung beachtet Gewicht und Rückfall', () {
      expect(ExerciseCatalog.key('Row (SEATED_CABLE_ROW)'), 'ROW_SEATED_CABLE_ROW');
      expect(ExerciseCatalog.classify('PULL_UP', hasWeight: true).id, 'latziehen');
      expect(ExerciseCatalog.classify('PULL_UP', hasWeight: false).id, 'klimmzug');
      expect(ExerciseCatalog.classify('PULL_UP').id, 'klimmzug');
      final unknown = ExerciseCatalog.classify('Meine Übung');
      expect(unknown.id, 'meine_uebung');
      expect(unknown.group, MuscleGroup.other);
    });

    test('flexibler Beintag wandert auf Donnerstag', () {
      const monday = CalendarDay(2026, 10, 19);
      final plan = GymPlan.standard;
      final early = plan.plannedDays(monday: monday, today: monday, doneDays: {});
      expect(early[monday], 'push');
      expect(early[monday.adding(1)], 'legs');
      expect(early[monday.adding(3)], isNull);
      final late = plan.plannedDays(monday: monday, today: monday.adding(2), doneDays: {});
      expect(late[monday.adding(3)], 'legs');
      final done = plan.plannedDays(monday: monday, today: monday.adding(2), doneDays: {monday.adding(1)});
      expect(done.values, isNot(contains('legs')));
    });
  });

  group('Progression', () {
    ExerciseProgress? evaluate(List<GymSession> sessions, {bool? recovered}) => GymProgression.evaluate(
      sessions: sessions,
      plan: GymPlan.standard,
      today: today,
      recovered: recovered,
    ).firstOrNull;

    // Erwartungswerte aus `gym_progress.evaluate_exercise` des Altbestands (Zielbereich 8–12 laut Plan).
    test('erhöhen, wenn alle Sätze an der Obergrenze', () {
      final result = evaluate([
        session('2026-10-16', 'bankdruecken', weight: 52.5, reps: [12, 11]),
        session('2026-10-20', 'bankdruecken', weight: 52.5, reps: [12, 12]),
      ], recovered: false)!;
      expect(result.status, ProgressStatus.increase);
      expect(result.nextWeightKg, 55);
      expect(result.increasePercent, 4.8);
      expect(result.headline, 'Erhöhen auf 55 kg (+4,8 %)');
      expect(result.detail, contains('Erholung aktuell eingeschränkt'));
    });

    test('erhöhen nach zweimal knapp an der Obergrenze', () {
      final result = evaluate([
        session('2026-10-16', 'bankdruecken', weight: 52.5, reps: [11, 12]),
        session('2026-10-20', 'bankdruecken', weight: 52.5, reps: [12, 11]),
      ]);
      expect(result?.status, ProgressStatus.increase);
      expect(result?.nextWeightKg, 55);
    });

    test('aufbauen, prüfen, Wiedereinstieg, Ausgangswert, Körpergewicht', () {
      final build = evaluate([
        session('2026-10-13', 'beinpresse', weight: 149, reps: [10, 9], group: MuscleGroup.legs),
        session('2026-10-20', 'beinpresse', weight: 149, reps: [11, 9], group: MuscleGroup.legs),
      ]);
      expect(build?.status, ProgressStatus.build);
      expect(build?.nextWeightKg, 154);
      expect(build?.increasePercent, 3.4);
      expect(build?.headline, 'Bei 149 kg bleiben');

      final check = evaluate([
        session('2026-10-13', 'rudern_kabel', weight: 110, reps: [6, 5], group: MuscleGroup.back),
        session('2026-10-20', 'rudern_kabel', weight: 110, reps: [6, 6], group: MuscleGroup.back),
      ]);
      expect(check?.status, ProgressStatus.check);

      final restart = evaluate([
        session('2026-09-20', 'latziehen', weight: 85, reps: [12, 12], group: MuscleGroup.back),
      ]);
      expect(restart?.status, ProgressStatus.restart);
      expect(restart?.nextWeightKg, 77.5);
      expect(restart?.headline, 'Wiedereinstieg mit ca. 77,5 kg');

      final baseline = evaluate([
        session('2026-10-20', 'seitheben', weight: 13.75, reps: [12, 10]),
      ]);
      expect(baseline?.headline, 'Ausgangswert 13,75 kg');

      final bodyweight = evaluate([
        session('2026-10-20', 'dips', weight: 0, reps: [12, 12]),
      ]);
      expect(bodyweight?.status, ProgressStatus.increase);
      expect(bodyweight?.headline, 'Zusatzgewicht beginnen');

      expect(
        evaluate([
          session('2026-08-01', 'dips', weight: 0, reps: [12, 12]),
        ]),
        isNull,
      );
    });

    test('nächstes Gewicht wie im Altbestand', () {
      List<double> next(double weight, double step, double percent) =>
          switch (GymProgression.nextWeight(weight, step: step, percent: percent)) {
            (final a, final b) => [a, b],
            null => [],
          };
      expect(next(149, 5, 5), [154, 3.4]);
      expect(next(22.5, 1.25, 2.5), [23.75, 5.6]);
      expect(next(110, 2.5, 2.5), [112.5, 2.3]);
      expect(next(7.5, 1, 2.5), [8.5, 13.3]);
      expect(next(0, 1, 2.5), isEmpty);
    });

    test('Aufwärmsätze zählen nicht', () {
      final entry = GymProgression.summary(
        day: today,
        sets: [
          LoggedSet(reps: 10, weightKg: 20),
          LoggedSet(reps: 12, weightKg: 50),
          LoggedSet(reps: 10, weightKg: 52.5),
        ],
      );
      expect(entry?.weight, 52.5);
      expect(entry?.reps, [10]);
      expect(GymProgression.summary(day: today, sets: [LoggedSet(reps: 10, weightKg: 50, done: false)]), isNull);
    });

    test('Muskelvolumen zählt erledigte Sätze', () {
      final sessions = [
        session('2026-10-20', 'bankdruecken', weight: 52.5, reps: [12, 12, 10]),
        session('2026-10-10', 'beinpresse', weight: 149, reps: [12, 12], group: MuscleGroup.legs),
      ];
      sessions[0].exercises[0].sets[2].done = false;
      final counts = MuscleVolume.setsPerGroup(sessions: sessions, today: today);
      expect(counts[MuscleGroup.chest], 2);
      expect(counts[MuscleGroup.legs], 0);
      expect(MuscleVolume.daysSinceLegs(sessions: sessions, today: today), 12);
      expect(sessions[0].volumeKg, 52.5 * 24);
      expect(GermanFormat.number(13.75), '13,75');
      expect(GermanFormat.number(55), '55');
    });
  });

  group('JSON wie Swift', () {
    test('Einheit hin und zurück, ältere Einheiten ohne neue Felder', () {
      final original = session('2026-10-20', 'bankdruecken', weight: 52.5, reps: [12, 10])
        ..garmin = GarminLink(status: GarminLinkStatus.pending, updatedAt: DateTime.utc(2026, 10, 20, 11));
      final json = original.toJson();
      expect(json['garmin'], {'status': 'pending', 'updatedAt': '2026-10-20T11:00:00Z'});
      expect(GymSession.fromJson(roundTrip(json)), original);
      final legacy = roundTrip(json) as Map<String, Object?>;
      final exercise = (legacy['exercises']! as List).first as Map<String, Object?>;
      exercise.remove('skipped');
      final set = (exercise['sets']! as List).first as Map<String, Object?>;
      set
        ..remove('id')
        ..remove('done')
        ..remove('kind');
      final decoded = GymSession.fromJson(legacy)!;
      expect(decoded.exercises.first.skipped, isFalse);
      expect(decoded.exercises.first.sets.first.done, isTrue);
      expect(decoded.exercises.first.sets.first.kind, SetKind.working);
    });

    test('Trainingsplan mit Wochentagen', () {
      final plan = GymPlan.standard;
      final decoded = GymPlan.fromJson(roundTrip(plan.toJson()))!;
      expect(decoded.schedule, plan.schedule);
      expect(decoded.flex, plan.flex);
      expect(decoded.workouts, plan.workouts);
    });
  });
}

// Port von CoachCoreTests/GymLibraryTests.swift (Bibliothek, Statistik, RIR); Routinen, Einstellungen und Hinweise
// folgen mit Phase 2l.
GymSession librarySession(int daysAgo, String exerciseID, List<LoggedSet> sets) {
  final day = today.adding(-daysAgo);
  return GymSession(
    workoutKey: null,
    title: 'Test',
    start: day.referenceDate,
    exercises: [
      LoggedExercise(
        exerciseID: exerciseID,
        name: ExerciseLibrary.byID[exerciseID]?.name ?? exerciseID,
        group: ExerciseLibrary.byID[exerciseID]?.group ?? MuscleGroup.other,
        sets: sets,
      ),
    ],
  );
}

void libraryTests() {
  group('Übungsbibliothek', () {
    test('Kennungen eindeutig, jede Übung erklärt', () {
      expect(ExerciseLibrary.all.map((exercise) => exercise.id).toSet().length, ExerciseLibrary.all.length);
      expect(ExerciseLibrary.all.length, 59);
      for (final exercise in ExerciseLibrary.all) {
        expect(exercise.instructions.length, greaterThanOrEqualTo(2), reason: '${exercise.id} ohne Anleitung');
        expect(exercise.lowerReps, lessThanOrEqualTo(exercise.upperReps));
        expect(exercise.step, greaterThan(0));
      }
    });

    test('Garmin-Katalog behält seine Progressionswerte', () {
      expect(ExerciseCatalog.rules.length, 47);
      for (final rule in ExerciseCatalog.rules) {
        final viaLibrary = ExerciseLibrary.rule(rule.id, name: rule.name);
        expect(viaLibrary.step, ExerciseCatalog.rulesByID[rule.id]?.step);
        expect(ExerciseLibrary.info(rule.id), isNotNull, reason: '${rule.id} fehlt in der Bibliothek');
      }
      expect(ExerciseLibrary.rule('goblet_squat', name: 'Goblet Squat').reps, const IntRange(8, 12));
      expect(ExerciseLibrary.rule('unbekannt', name: 'Neu').name, 'Neu');
    });

    test('Ausstattung filtert, eigene Übungen', () {
      final bench = ExerciseLibrary.byID['bankdruecken']!;
      expect(bench.isAvailable(Equipment.gym), isTrue);
      expect(bench.isAvailable(Equipment.homeDumbbells), isFalse);
      expect(ExerciseLibrary.byID['liegestuetze']!.isAvailable(Equipment.none), isTrue);
      final own = ExerciseInfo.custom(
        name: ' Landmine Press ',
        group: MuscleGroup.shoulders,
        equipment: Equipment.barbell,
        tracking: ExerciseTracking.weightReps,
      );
      expect(own.id, 'eigen_landmine_press');
      expect(own.name, 'Landmine Press');
      expect(ExerciseLibrary.search('landmine', custom: [own]).map((item) => item.id), [own.id]);
      expect(
        ExerciseLibrary.search('Rücken')
            .every((item) => item.group == MuscleGroup.back || item.name.toLowerCase().contains('rücken')),
        isTrue,
      );
      expect(ExerciseInfo.fromJson(roundTrip(own.toJson())), own);
    });
  });

  group('Statistik', () {
    test('Epley nur bis 12 Wiederholungen', () {
      expect(GymStats.estimatedOneRepMax(weightKg: 100, reps: 1), 100);
      expect((GymStats.estimatedOneRepMax(weightKg: 60, reps: 10)! - 80).abs(), lessThan(0.001));
      expect(GymStats.estimatedOneRepMax(weightKg: 60, reps: 15), isNull);
      expect(GymStats.estimatedOneRepMax(weightKg: 0, reps: 10), isNull);
    });

    test('Verlauf, Bestwerte und neue Rekorde', () {
      final old = librarySession(7, 'bankdruecken', [
        LoggedSet(reps: 10, weightKg: 60),
        LoggedSet(reps: 8, weightKg: 60),
      ]);
      final warmup = LoggedSet(reps: 12, weightKg: 20, done: false);
      final current = librarySession(0, 'bankdruecken', [warmup, LoggedSet(reps: 8, weightKg: 62.5)]);
      final points = GymStats.history('bankdruecken', sessions: [current, old]);
      expect(points.map((point) => point.topWeightKg), [60, 62.5]);
      expect(points.last.sets.length, 1);
      final records = GymStats.records(points);
      expect(records.heaviestKg, 62.5);
      expect(records.mostReps, 10);
      expect(GymStats.newRecords(current, before: [old, current]), ['Bankdrücken: neues Höchstgewicht 62,5 kg']);
      expect(GymStats.newRecords(old, before: [old]), isEmpty);
      expect(GymStats.recentPerformances('bankdruecken', sessions: [old, current]).map((item) => item.text()), [
        '62,5 kg × 8',
        '60 kg × 10',
      ]);
    });
  });

  group('RIR in der Progression', () {
    ExerciseProgress? evaluate(List<GymSession> sessions) =>
        GymProgression.evaluateRanges(sessions: sessions, ranges: {}, today: today).firstOrNull;

    test('viel Reserve heißt jetzt erhöhen', () {
      final easy = librarySession(2, 'kurzhantel_bankdruecken', [
        for (var index = 0; index < 3; index++) LoggedSet(reps: 8, weightKg: 20, rir: 4),
      ]);
      final result = evaluate([easy])!;
      expect(result.status, ProgressStatus.increase);
      expect(result.nextWeightKg, 22.5);
      expect(result.detail, contains('Reserve'));
    });

    test('nah am Versagen: weiter Wiederholungen aufbauen', () {
      final hard = librarySession(2, 'kurzhantel_bankdruecken', [
        for (var index = 0; index < 3; index++) LoggedSet(reps: 8, weightKg: 20, rir: 1),
      ]);
      final earlier = librarySession(5, 'kurzhantel_bankdruecken', [
        for (var index = 0; index < 3; index++) LoggedSet(reps: 7, weightKg: 20),
      ]);
      expect(evaluate([earlier, hard])!.status, ProgressStatus.build);
      // Ohne RIR-Angabe greift die neue Regel nicht.
      final unknown = librarySession(2, 'kurzhantel_bankdruecken', [
        for (var index = 0; index < 3; index++) LoggedSet(reps: 8, weightKg: 20),
      ]);
      expect(evaluate([earlier, unknown])!.status, ProgressStatus.build);
    });

    test('eigene Übungen mit eigenem Bereich', () {
      final own = ExerciseInfo.custom(
        name: 'Landmine Press',
        group: MuscleGroup.shoulders,
        equipment: Equipment.barbell,
        tracking: ExerciseTracking.weightReps,
      );
      final done = librarySession(1, own.id, [
        for (var index = 0; index < 3; index++) LoggedSet(reps: 12, weightKg: 30),
      ]);
      final result = GymProgression.evaluateRanges(sessions: [done], ranges: {}, custom: [own], today: today).first;
      expect(result.status, ProgressStatus.increase);
      expect(result.target, const IntRange(8, 12));
    });
  });
}

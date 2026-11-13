// Port von GarminWorkoutTests.swift und den FIT-Fällen aus GymBookTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  group('Workouts für die Uhr', () {
    test('Intervalle aus dem Plantext', () {
      final plan = GarminWorkout.plan(
        name: 'Schwelle 4×2 km',
        sport: WorkoutSport.run,
        text: '4×2 km @ 4:20 /km, 90 s Trab',
      );
      expect(plan.steps.length, 3);
      final repeats = plan.steps[1] as RepeatStep;
      expect(repeats.count, 4);
      expect(repeats.steps.first, const ExecutableStep.interval(EndMeters(2000), note: '4×2 km @ 4:20 /km, 90 s Trab'));
      expect(repeats.steps.last, const ExecutableStep.recovery(EndSeconds(90)));
      final minutes = GarminWorkout.plan(
        name: '4×4',
        sport: WorkoutSport.run,
        text: '4×4 min bei 90–95 % HFmax, 3 min Trab',
      );
      final inner = minutes.steps[1] as RepeatStep;
      expect(inner.count, 4);
      expect(
        inner.steps.first,
        const ExecutableStep.interval(EndSeconds(240), note: '4×4 min bei 90–95 % HFmax, 3 min Trab'),
      );
      expect(inner.steps.last, const ExecutableStep.recovery(EndSeconds(180)));
    });

    test('Einzelschritte aus Dauer oder Strecke', () {
      expect(GarminWorkout.plan(name: 'Z2', sport: WorkoutSport.run, text: '50 min Zone 2').steps, [
        const ExecutableStep.interval(EndSeconds(3000), note: '50 min Zone 2'),
      ]);
      expect(GarminWorkout.plan(name: 'Z2', sport: WorkoutSport.run, text: '60–75 min Z2').steps, [
        const ExecutableStep.interval(EndSeconds(3600), note: '60–75 min Z2'),
      ]);
      expect(GarminWorkout.plan(name: 'Long', sport: WorkoutSport.run, text: '16 km locker').steps, [
        const ExecutableStep.interval(EndMeters(16000), note: '16 km locker'),
      ]);
      expect(GarminWorkout.plan(name: 'Frei', sport: WorkoutSport.bike, text: 'nach Gefühl').steps, [
        const ExecutableStep.interval(EndLapButton(), note: 'nach Gefühl'),
      ]);
    });

    test('Nutzdaten mit den Feldern von Garmin', () {
      final plan = GarminWorkout.plan(name: 'Schwelle', sport: WorkoutSport.run, text: '3×3 km @ 4:20 /km, 2 min Trab');
      final payload = JsonValue(jsonDecode(jsonEncode(GarminWorkout.payload(plan))));
      expect(payload['sportType']?['sportTypeKey']?.stringValue, 'running');
      final steps = payload['workoutSegments']!.arrayValue!.first['workoutSteps']!.arrayValue!;
      expect(steps.length, 3);
      expect(steps[0]['endCondition']?['conditionTypeKey']?.stringValue, 'lap.button');
      final group = steps[1];
      expect(group['type']?.stringValue, 'RepeatGroupDTO');
      expect(group['numberOfIterations']?.intValue, 3);
      final inner = group['workoutSteps']!.arrayValue!;
      expect(inner[0]['endCondition']?['conditionTypeKey']?.stringValue, 'distance');
      expect(inner[0]['endConditionValue']?.intValue, 3000);
      expect(inner[0]['childStepId']?.intValue, 1);
      expect(inner[1]['endCondition']?['conditionTypeKey']?.stringValue, 'time');
      expect(steps[2]['stepOrder']?.intValue, 5);
    });

    test('Schwimmplan mit Becken und Pausen', () {
      const steps = [
        SwimStep(t: 'warmup', m: 200),
        SwimStep(
          t: 'rep',
          n: 4,
          steps: [
            SwimStep(t: 'int', m: 100),
            SwimStep(t: 'rest', s: 20),
          ],
        ),
        SwimStep(t: 'cool', m: 100),
      ];
      final plan = GarminWorkout.swimPlan(name: 'CSS', text: '4×100', steps: steps);
      final payload = JsonValue(jsonDecode(jsonEncode(GarminWorkout.payload(plan))));
      expect(payload['poolLength']?.intValue, 25);
      final all = payload['workoutSegments']!.arrayValue!.first['workoutSteps']!.arrayValue!;
      final rest = all[1]['workoutSteps']!.arrayValue!.last;
      expect(rest['endCondition']?['conditionTypeKey']?.stringValue, 'fixed.rest');
      expect(rest['endConditionValue']?.intValue, 20);
    });

    test('Antwort und Kalender', () {
      expect(GarminWorkout.workoutID(JsonValue.parse('{"workoutId": 123456789, "workoutName": "x"}')), 123456789);
      const day = CalendarDay(2026, 11, 10);
      expect(GarminWorkout.scheduleBody(day)['date'], '2026-11-10');
      expect(GarminWorkout.schedulePath(5), '/workout-service/schedule/5');
      expect(WorkoutSport.of(TrainingSport.strength), isNull);
    });

    test('gesendete Workouts werden aufgeräumt', () {
      const today = CalendarDay(2026, 11, 9);
      final sent = SentWorkouts();
      sent.ids[SentWorkouts.key(name: 'A', day: today)] = 1;
      sent.ids[SentWorkouts.key(name: 'B', day: today.adding(-90))] = 2;
      sent.prune(today);
      expect(sent.ids.length, 1);
      expect(SentWorkouts.fromJson(jsonDecode(jsonEncode(sent.toJson())))?.ids, sent.ids);
    });

    test('Kurzfassung für die Vorschau', () {
      final plan = GarminWorkout.plan(name: 'S', sport: WorkoutSport.run, text: '4×2 km @ 4:20 /km, 90 s Trab');
      expect(GarminWorkout.summary(plan.steps), [
        'Aufwärmen: bis Runden-Taste',
        '4 × (Belastung: 2 km, Erholung: 90 s)',
        'Ausklang: bis Runden-Taste',
      ]);
    });
  });

  group('FIT-Export der Krafteinheit', () {
    test('jede Übung der Bibliothek hat eine Garmin-Kategorie', () {
      for (final exercise in ExerciseLibrary.all) {
        expect(
          GarminExerciseMapping.code(exercise.id).category,
          isNot(GarminExerciseMapping.unknown),
          reason: exercise.id,
        );
      }
    });

    test('Rundreise über den FIT-Dekoder', () {
      final start = DateTime.fromMillisecondsSinceEpoch(1793000000 * 1000, isUtc: true);
      final session = GymSession(
        workoutKey: null,
        title: 'Push A',
        start: start,
        end: start.add(const Duration(minutes: 45)),
        exercises: [
          LoggedExercise(
            exerciseID: 'bankdruecken',
            name: 'Bankdrücken mit Langhantel',
            group: MuscleGroup.chest,
            sets: [LoggedSet(reps: 12, weightKg: 52.5), LoggedSet(reps: 11, weightKg: 52.5)],
          ),
          LoggedExercise(
            exerciseID: 'plank',
            name: 'Planks',
            group: MuscleGroup.core,
            sets: [LoggedSet(reps: 60, weightKg: 0)],
          ),
          LoggedExercise(
            exerciseID: 'dips_barren',
            name: 'Dips am Barren',
            group: MuscleGroup.triceps,
            sets: [LoggedSet(reps: 12, weightKg: 79, done: false)],
          ),
        ],
      );
      final data = StrengthFitExport.fit(session);
      // Prüfsumme über die ganze Datei inklusive CRC ergibt 0.
      expect(FitEncoder.crc(data), 0);
      final decoded = FitDecoder.decode(data);
      final active = decoded.sets.where((set) => set.active).toList();
      expect(active.length, 3);
      expect(active[0].repetitions, 12);
      expect(active[0].weightKg, 52.5);
      expect(active[0].category, 0);
      expect(active[0].subtype, 1);
      expect(active[2].category, 19);
      expect(active[2].repetitions, isNull);
      expect(active[2].durationSeconds, 60);
      expect(decoded.sets.where((set) => !set.active).length, 2);
      expect(decoded.laps.length, 1);
    });
  });
}

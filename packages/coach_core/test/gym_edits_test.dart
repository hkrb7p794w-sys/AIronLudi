// Port von WorkoutEditsTests.swift und GymToolsTests.swift (mit GymRestSettingsTests und HoldTimerTests).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

LoggedExercise editExercise(String id, {int sets = 3, int done = 0, double weight = 50}) => LoggedExercise(
  exerciseID: id,
  name: id,
  group: MuscleGroup.chest,
  sets: [for (var index = 0; index < sets; index++) LoggedSet(reps: 8, weightKg: weight, done: index < done)],
);

GymSession editSession(List<LoggedExercise> exercises) => GymSession(
  workoutKey: null,
  title: 'Test',
  start: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  exercises: exercises,
);

void main() {
  group('Bearbeiten der laufenden Einheit', () {
    test('Supersatz wechselt ab und pausiert nach der Runde', () {
      final session = editSession([editExercise('bank'), editExercise('rudern'), editExercise('curl')]);
      WorkoutEdits.toggleSuperset(session.exercises[0].id, session);
      expect(session.exercises[0].supersetID, isNotNull);
      expect(session.exercises[0].supersetID, session.exercises[1].supersetID);
      expect(WorkoutFlow.supersetLabels(session)[session.exercises[1].id], 'A2');
      // A1 erledigt: ohne Pause zu A2.
      session.exercises[0].sets[0].done = true;
      final afterA1 = WorkoutFlow.afterCompleting(0, session);
      expect(afterA1.focus, 1);
      expect(afterA1.rest, isFalse);
      // A2 erledigt: Pause, dann wieder A1.
      session.exercises[1].sets[0].done = true;
      final afterA2 = WorkoutFlow.afterCompleting(1, session);
      expect(afterA2.focus, 0);
      expect(afterA2.rest, isTrue);
      expect(
        WorkoutFlow.upcoming(const FlowPosition(exercise: 0, set: 1), session),
        const FlowPosition(exercise: 1, set: 1),
      );
      // Auflösen: beide wieder einzeln.
      WorkoutEdits.toggleSuperset(session.exercises[1].id, session);
      expect(session.exercises.every((exercise) => exercise.supersetID == null), isTrue);
    });

    test('später und verschieben', () {
      final session = editSession([editExercise('a'), editExercise('b'), editExercise('c')]);
      List<String> ids() => session.exercises.map((exercise) => exercise.exerciseID).toList();
      WorkoutEdits.moveToEnd(session.exercises[0].id, session);
      expect(ids(), ['b', 'c', 'a']);
      WorkoutEdits.move(fromOffsets: {2}, toOffset: 0, session: session);
      expect(ids(), ['a', 'b', 'c']);
      WorkoutEdits.move(fromOffsets: {0}, toOffset: 3, session: session);
      expect(ids(), ['b', 'c', 'a']);
    });

    test('Ersetzen behält erledigte Sätze bei der alten Übung', () {
      final info = ExerciseLibrary.byID['kurzhantel_bankdruecken']!;
      final fresh = editSession([editExercise('bankdruecken')]);
      WorkoutEdits.replace(fresh.exercises[0].id, info: info, weightKg: 24, session: fresh);
      expect(fresh.exercises.length, 1);
      expect(fresh.exercises[0].exerciseID, 'kurzhantel_bankdruecken');
      expect(fresh.exercises[0].sets.length, 3);
      expect(fresh.exercises[0].sets.every((set) => set.weightKg == 24 && !set.done), isTrue);
      final started = editSession([editExercise('bankdruecken', sets: 4, done: 1)]);
      WorkoutEdits.replace(started.exercises[0].id, info: info, weightKg: 24, session: started);
      expect(started.exercises.map((exercise) => exercise.exerciseID), ['bankdruecken', 'kurzhantel_bankdruecken']);
      expect(started.exercises[0].sets.length, 1);
      expect(started.exercises[1].sets.length, 3);
    });

    test('Alternativen passen zu Muskelgruppe und Ausstattung', () {
      final options = WorkoutEdits.alternatives('bankdruecken', equipment: {Equipment.dumbbell, Equipment.bench});
      expect(options.any((item) => item.id == 'kurzhantel_bankdruecken'), isTrue);
      expect(options.any((item) => item.id == 'bankdruecken' || item.id == 'brustpresse'), isFalse);
      expect(options.every((item) => item.group == MuscleGroup.chest), isTrue);
    });

    test('Aufwärmsätze zählen nicht, Sätze bleiben unabhängig', () {
      final session = editSession([editExercise('kniebeuge', weight: 100)]);
      final id = session.exercises[0].id;
      final steps = WarmUp.steps(working: 100, equipment: [Equipment.barbell], compound: true);
      WorkoutEdits.insertWarmUp(steps, exerciseID: id, session: session);
      expect(session.exercises[0].sets.take(steps.length).every((set) => set.kind == SetKind.warmup), isTrue);
      // Aufwärmsatz leichter machen: Arbeitssätze bleiben bei 100 kg.
      WorkoutEdits.setWeight(30, set: 0, exerciseID: id, session: session);
      expect(
        session.exercises[0].sets.where((set) => set.kind == SetKind.working).every((set) => set.weightKg == 100),
        isTrue,
      );
      // Erster Arbeitssatz schwerer: nur dieser Satz ändert sich, die folgenden bleiben bei 100 kg.
      WorkoutEdits.setWeight(105, set: steps.length, exerciseID: id, session: session);
      final weights = session.exercises[0].sets.map((set) => set.weightKg).toList();
      expect(weights.sublist(weights.length - 3), [105, 100, 100]);
      for (final set in session.exercises[0].sets) {
        set.done = true;
      }
      expect(session.exercises[0].doneSets.length, 3);
      expect(session.exercises[0].loggedSets.length, 3 + steps.length);
      expect(session.volumeKg, 2440);
    });

    test('Unterstützung ist negativ, zählt aber nie als Last', () {
      final session = editSession([editExercise('klimmzug', weight: 0)]);
      final id = session.exercises[0].id;
      WorkoutEdits.setWeight(-20, set: 0, exerciseID: id, allowsNegative: true, session: session);
      expect(session.exercises[0].sets.map((set) => set.weightKg), [-20, 0, 0]);
      WorkoutEdits.setWeight(-20, set: 0, exerciseID: id, session: session);
      expect(session.exercises[0].sets[0].weightKg, 0);
      expect(LoggedSet(reps: 8, weightKg: -20).loadKg, 0);
      final pullUp = ExerciseLibrary.byID['klimmzug'];
      expect(ExerciseUnits.weightText(-20, info: pullUp).value, '20');
      expect(ExerciseUnits.weightText(-20, info: pullUp).unit, 'kg Hilfe');
      expect(ExerciseUnits.weightText(10, info: pullUp).value, '+10');
      expect(ExerciseUnits.weightText(20, info: ExerciseLibrary.byID['kurzhantel_curl']).unit, 'kg je Hantel');
      expect(ExerciseUnits.repsUnit('ausfallschritt', isTime: false), 'Wdh. je Seite');
    });

    test('Plausibilität und Pause', () {
      expect(SetCheck.warning(weightKg: 625, reps: 0, isTime: false, previousBestKg: 62.5), isNotNull);
      expect(SetCheck.warning(weightKg: 105, reps: 0, isTime: false, previousBestKg: 62.5), isNotNull);
      expect(SetCheck.warning(weightKg: 65, reps: 0, isTime: false, previousBestKg: 62.5), isNull);
      expect(SetCheck.warning(weightKg: 0, reps: 80, isTime: false, previousBestKg: null), isNotNull);
      expect(SetCheck.warning(weightKg: 0, reps: 90, isTime: true, previousBestKg: null), isNull);
      expect(RestAdvisor.seconds(base: 120, compound: true, rir: 0), 150);
      expect(RestAdvisor.seconds(base: 120, compound: true, rir: 3), 120);
      expect(RestAdvisor.seconds(base: 90, compound: false, rir: 0), 90);
    });

    test('alte Sätze sind Arbeitssätze', () {
      final set = LoggedSet.fromJson(jsonDecode('{"reps":8,"weightKg":60,"done":true}'))!;
      expect(set.kind, SetKind.working);
      expect(set.reps, 8);
      final item = RoutineItem.fromJson(
        jsonDecode(
          '{"id":"6F1C2D1E-0000-4000-8000-000000000001","exerciseID":"kniebeuge","name":"Kniebeuge","sets":3,'
          '"lowerReps":6,"upperReps":10,"restSeconds":120}',
        ),
      )!;
      expect(item.supersetWithNext, isFalse);
      final settings = GymSettings.fromJson(jsonDecode('{}'));
      expect(settings.barKg, 20);
      expect(settings.keepsScreenOn, isTrue);
    });
  });

  group('Gym-Werkzeuge', () {
    test('Scheiben je Seite', () {
      final result = PlateCalculator.plates(102.5)!;
      expect(result.perSide, [25, 15, 1.25]);
      expect(result.remainder, 0);
      expect(PlateCalculator.text(result), 'Je Seite: 25 + 15 + 1,25 kg');
      expect(PlateCalculator.plates(15), isNull);
      expect(PlateCalculator.text(PlateCalculator.plates(20)!), 'Nur die Stange');
      final odd = PlateCalculator.plates(21)!;
      expect(odd.perSide, isEmpty);
      expect(odd.remainder, 1);
    });

    test('Aufwärmen für schwere Langhantelübung', () {
      final steps = WarmUp.steps(working: 100, equipment: [Equipment.barbell], compound: true);
      expect(steps.map((step) => step.weightKg), [20, 50, 70, 85]);
      expect(steps.map((step) => step.reps), [10, 5, 3, 2]);
      expect(WarmUp.text(steps.take(2).toList()), 'Aufwärmen: 20 kg × 10 · 50 kg × 5');
    });

    test('kein Aufwärmen bei leichten Übungen', () {
      expect(WarmUp.steps(working: 30, equipment: [Equipment.barbell], compound: true), isEmpty);
      expect(WarmUp.steps(working: 20, equipment: [Equipment.dumbbell], compound: true).map((step) => step.weightKg), [
        10,
        15,
      ]);
      expect(WarmUp.steps(working: 0, equipment: [Equipment.bodyweight], compound: true), isEmpty);
    });

    test('Aufwärmvorschlag nur vor dem ersten Satz', () {
      final info = ExerciseLibrary.info('bankdruecken');
      final exercise = LoggedExercise(
        exerciseID: 'bankdruecken',
        name: 'Bankdrücken',
        group: MuscleGroup.chest,
        sets: [for (var index = 0; index < 3; index++) LoggedSet(reps: 8, weightKg: 60, done: false)],
      );
      expect(WarmUp.suggestion(exercise, info: info, bar: 20).map((step) => step.weightKg), [20, 30, 42.5, 50]);
      exercise.sets[0].done = true;
      expect(WarmUp.suggestion(exercise, info: info, bar: 20), isEmpty);
      exercise.sets[0].done = false;
      exercise.sets.insert(0, LoggedSet(reps: 10, weightKg: 20, done: false, kind: SetKind.warmup));
      expect(WarmUp.suggestion(exercise, info: info, bar: 20), isEmpty);
      expect(WarmUp.suggestion(exercise, info: null, bar: 20), isEmpty);
    });

    test('Standardpausen und Lesen', () {
      final gym = GymSettings();
      expect(gym.rest('bankdruecken', compound: true), 120);
      expect(gym.rest('seitheben', compound: false), 90);
      gym
        ..restIsolation = 75
        ..restOverrides['bankdruecken'] = 180;
      expect(gym.rest('bankdruecken', compound: true), 180);
      expect(gym.rest('seitheben', compound: false), 75);
      // Ältere Daten ohne die neuen Felder bleiben lesbar.
      final old = GymSettings.fromJson(jsonDecode('{"routines":[]}'));
      expect(old.restWarmup, 60);
      expect(old.autoStartsRest, isTrue);
      expect(old.suggestsWarmUp, isTrue);
      expect(old.completeOnEdit, CompleteOnEdit.off);
      expect(GymSettings.fromJson(jsonDecode(jsonEncode(gym.toJson()))), gym);
      expect(CompleteOnEdit.off.completes(afterEditingReps: true), isFalse);
      expect(CompleteOnEdit.afterReps.completes(afterEditingReps: true), isTrue);
      expect(CompleteOnEdit.afterReps.completes(afterEditingReps: false), isFalse);
      expect(CompleteOnEdit.always.completes(afterEditingReps: false), isTrue);
      expect(RestText.format(45), '45 s');
      expect(RestText.format(90), '1:30 min');
      expect(RestText.format(180), '3 min');
    });

    test('Stoppuhr misst und korrigiert', () {
      final start = DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true);
      expect(HoldTimer.seconds(start, start.add(const Duration(milliseconds: 44600))), 45);
      expect(HoldTimer.seconds(start, start.add(const Duration(milliseconds: 200))), 1);
      expect(HoldTimer.corrected(45, -5), 40);
      expect(HoldTimer.corrected(3, -5), 1);
      expect(HoldTimer.targetText(elapsed: 33, target: 45), 'noch 12 s bis 45 s');
      expect(HoldTimer.targetText(elapsed: 53, target: 45), '+8 s über Ziel');
    });
  });
}

// Port von WorkoutFlowTests.swift und GymFlowTests.swift (mit ActiveSessionStateTests).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

LoggedExercise flowExercise(String id, List<bool> done) => LoggedExercise(
  exerciseID: id,
  name: id,
  group: MuscleGroup.chest,
  sets: [for (final flag in done) LoggedSet(reps: 8, weightKg: 50, done: flag)],
);

GymSession flowSession() => GymSession(
  workoutKey: null,
  title: 'Push',
  start: epoch,
  exercises: [
    flowExercise('bank', [true, false, false]),
    flowExercise('rudern', [false, false]),
    flowExercise('curl', [true]),
  ],
);

String capitalized(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

LoggedExercise gymExercise(String id, {int sets = 2, int done = 0, double weight = 50}) => LoggedExercise(
  exerciseID: id,
  name: capitalized(id),
  group: MuscleGroup.chest,
  sets: [for (var index = 0; index < sets; index++) LoggedSet(reps: 8, weightKg: weight, done: index < done)],
);

GymSession gymSession(List<LoggedExercise> exercises, {DateTime? start}) =>
    GymSession(workoutKey: null, title: 'Test', start: start ?? epoch, exercises: exercises);

void main() {
  group('Ablauf', () {
    test('aktueller Satz folgt der gewählten Übung und beginnt von vorn', () {
      final session = flowSession();
      expect(WorkoutFlow.current(session), const FlowPosition(exercise: 0, set: 1));
      expect(
        WorkoutFlow.current(session, preferring: session.exercises[1].id),
        const FlowPosition(exercise: 1, set: 0),
      );
      // Fertige Übung gewählt: weiter mit der nächsten offenen, am Ende von vorn.
      expect(
        WorkoutFlow.current(session, preferring: session.exercises[2].id),
        const FlowPosition(exercise: 0, set: 1),
      );
    });

    test('Vorschau bleibt in der Übung und geht dann weiter', () {
      final session = flowSession();
      expect(
        WorkoutFlow.upcoming(const FlowPosition(exercise: 0, set: 1), session),
        const FlowPosition(exercise: 0, set: 2),
      );
      expect(
        WorkoutFlow.upcoming(const FlowPosition(exercise: 0, set: 2), session),
        const FlowPosition(exercise: 0, set: 1),
      );
      final last = session.copy();
      last.exercises[0].sets[1].done = true;
      expect(
        WorkoutFlow.upcoming(const FlowPosition(exercise: 0, set: 2), last),
        const FlowPosition(exercise: 1, set: 0),
      );
    });

    test('Zusammenfassung zählt vergessene Sätze', () {
      final session = flowSession();
      session.exercises[1].sets[1].reps = 0;
      final summary = WorkoutFlow.summary(session, now: DateTime.fromMillisecondsSinceEpoch(3000 * 1000, isUtc: true));
      expect(summary.minutes, 50);
      expect(summary.doneSets, 2);
      expect(summary.exercises, 2);
      expect(summary.openSets, 3);
      final completed = WorkoutFlow.completingOpenSets(session);
      expect(completed.doneSetCount, 5);
      expect(completed.exercises[1].sets[1].done, isFalse);
    });

    test('Ziffernblock', () {
      var text = '';
      for (final key in const <NumberPadKey>[
        NumberPadDigit(6),
        NumberPadDigit(2),
        NumberPadComma(),
        NumberPadDigit(5),
        NumberPadDigit(0),
        NumberPadDigit(1),
      ]) {
        text = NumberPad.apply(key, text, allowsDecimals: true);
      }
      expect(text, '62,50');
      expect(NumberPad.value(text), 62.5);
      expect(NumberPad.apply(const NumberPadComma(), '', allowsDecimals: true), '0,');
      expect(NumberPad.apply(const NumberPadComma(), '8', allowsDecimals: false), '8');
      expect(NumberPad.apply(const NumberPadDigit(5), '0', allowsDecimals: false), '5');
      expect(NumberPad.apply(const NumberPadDigit(1), '100', allowsDecimals: false), '100');
      expect(NumberPad.apply(const NumberPadDelete(), '62,5', allowsDecimals: true), '62,');
      expect(NumberPad.value(''), isNull);
      expect(NumberPad.text(0), '');
      expect(NumberPad.text(62.5), '62,5');
    });
  });

  group('Gym-Ablauf', () {
    test('übersprungene Übung wird übergangen und nicht vergessen', () {
      final session = gymSession([gymExercise('bank'), gymExercise('schulter'), gymExercise('curl')]);
      WorkoutEdits.setSkipped(true, exerciseID: session.exercises[0].id, session: session);
      expect(WorkoutFlow.current(session), const FlowPosition(exercise: 1, set: 0));
      expect(WorkoutFlow.nextExercise(1, session), 2);
      // Ausdrücklich gewählt, steht die übersprungene Übung trotzdem auf der Fokus-Karte.
      expect(
        WorkoutFlow.current(session, preferring: session.exercises[0].id),
        const FlowPosition(exercise: 0, set: 0),
      );
      expect(WorkoutFlow.skippedCount(session), 1);
      session.exercises[0].sets[0].reps = 8;
      // Offene Sätze der übersprungenen Übung zählen nicht als vergessen und werden nicht abgehakt.
      expect(WorkoutFlow.summary(session).openSets, 4);
      expect(WorkoutFlow.completingOpenSets(session).exercises[0].sets.every((set) => !set.done), isTrue);
    });

    test('Plan ist durch, wenn nur Übersprungenes bleibt', () {
      final session = gymSession([gymExercise('bank', done: 2), gymExercise('schulter', done: 1)]);
      expect(WorkoutFlow.isComplete(session), isFalse);
      WorkoutEdits.setSkipped(true, exerciseID: session.exercises[1].id, session: session);
      expect(WorkoutFlow.isComplete(session), isTrue);
      WorkoutEdits.setSkipped(false, exerciseID: session.exercises[1].id, session: session);
      expect(WorkoutFlow.isComplete(session), isFalse);
      expect(WorkoutFlow.isComplete(gymSession([])), isFalse);
    });

    test('Text nennt die nächste Übung', () {
      final session = gymSession([gymExercise('bankdrücken', done: 2), gymExercise('schulterdrücken')]);
      final bench = session.exercises[0].id;
      expect(WorkoutFlow.nextText(session, focus: null, previous: bench), 'Weiter mit Schulterdrücken');
      session.exercises[1].sets[0].done = true;
      final shoulder = session.exercises[1].id;
      expect(WorkoutFlow.nextText(session, focus: shoulder, previous: shoulder), 'Weiter mit Satz 2 · Schulterdrücken');
      session.exercises[1].sets[1].done = true;
      expect(WorkoutFlow.nextText(session, focus: null, previous: shoulder), isNull);
    });

    test('übersprungen fehlt in älteren Daten', () {
      final decoded = LoggedExercise.fromJson(
        jsonDecode('''
          {"id":"00000000-0000-0000-0000-000000000001","exerciseID":"bank","name":"Bank","group":"Brust",
          "sets":[{"reps":8,"weightKg":60}],"restSeconds":90}'''),
      )!;
      expect(decoded.skipped, isFalse);
      expect(decoded.sets.first.done, isTrue);
      final skipped = decoded.copy()..skipped = true;
      expect(LoggedExercise.fromJson(jsonDecode(jsonEncode(skipped.toJson())))!.skipped, isTrue);
    });

    test('letzte Leistungen, neueste zuerst mit bestem Satz', () {
      final sessions = [
        for (var index = 0; index < 7; index++)
          gymSession([
            LoggedExercise(
              exerciseID: 'bankdruecken',
              name: 'Bankdrücken',
              group: MuscleGroup.chest,
              sets: [
                LoggedSet(reps: 10, weightKg: 75.0 + index),
                LoggedSet(reps: 8, weightKg: 75.0 + index),
                LoggedSet(reps: 12, weightKg: 40, kind: SetKind.warmup),
              ],
            ),
          ], start: epoch.add(Duration(days: index, hours: 12))),
      ];
      final recent = GymStats.recentPerformances('bankdruecken', sessions: sessions);
      expect(recent.length, 5);
      expect(recent.first.weightKg, 81);
      expect(recent.first.reps, 10);
      expect(recent.first.text(), '81 kg × 10');
      expect(recent.last.weightKg, 77);
      expect(GymPerformance(day: recent[0].day, weightKg: 0, reps: 12).text(), '12 Wdh.');
      expect(GymPerformance(day: recent[0].day, weightKg: 10, reps: 8).text(allowsAssistance: true), '+10 kg × 8');
      expect(GymPerformance(day: recent[0].day, weightKg: 0, reps: 45).text(isTime: true), '45 s');
    });

    test('Kabel-Crunch ist Gerätegewicht', () {
      expect(ExerciseCatalog.classify('CRUNCH (KNEELING_CABLE_CRUNCH)', hasWeight: true).id, 'crunch_kabel');
      expect(ExerciseCatalog.classify('CRUNCH (WEIGHTED_CRUNCH)', hasWeight: true).id, 'crunch_geraet');
      expect(ExerciseCatalog.classify('CRUNCH', hasWeight: false).id, 'crunch');
      final cable = ExerciseLibrary.info('crunch_kabel');
      expect(ExerciseUnits.allowsAssistance(cable), isFalse);
      expect(ExerciseUnits.weightText(65, info: cable).value, '65');
      expect(ExerciseUnits.weightText(65, info: cable).unit, 'kg');
      // Ältere Einheiten aus dem Saisonplan: beim Lesen Kabel-Crunch, gespeicherte Daten bleiben unverändert.
      final old = gymSession([
        LoggedExercise(
          exerciseID: 'crunch',
          name: 'Crunches am Kabel kniend',
          group: MuscleGroup.core,
          sets: [LoggedSet(reps: 12, weightKg: 65)],
        ),
        LoggedExercise(
          exerciseID: 'crunch',
          name: 'Crunch',
          group: MuscleGroup.core,
          sets: [LoggedSet(reps: 20, weightKg: 0)],
        ),
      ]);
      final normalized = ExerciseAliases.normalized(old);
      expect(normalized.exercises.map((exercise) => exercise.exerciseID), ['crunch_kabel', 'crunch']);
      expect(old.exercises[0].exerciseID, 'crunch');
    });
  });

  group('Zustand der offenen Einheit', () {
    const offset = Duration(hours: 1);
    DateTime at(int day, int hour) => DateTime.utc(2026, 11, day, hour).subtract(offset);

    GymSession session(DateTime start, int doneSets) => GymSession(
      workoutKey: null,
      title: 'Push',
      start: start,
      exercises: [
        LoggedExercise(
          exerciseID: 'bench',
          name: 'Bankdrücken',
          group: MuscleGroup.chest,
          sets: [for (var index = 0; index < 3; index++) LoggedSet(reps: 10, weightKg: 50, done: index < doneSets)],
        ),
      ],
    );

    test('geöffnet, aber nicht begonnen: keine Live-Aktivität', () {
      final start = at(2, 17);
      final state = ActiveSessionState.of(
        session(start, 0),
        now: start.add(const Duration(seconds: 600)),
        utcOffset: offset,
      );
      expect(state, ActiveSessionState.notStarted);
      expect(state.showsLiveActivity, isFalse);
      expect(state.suppressesReminders, isTrue);
      expect(state.countsAsTrained, isFalse);
    });

    test('erster Satz macht sie laufend', () {
      final start = at(2, 17);
      final state = ActiveSessionState.of(
        session(start, 1),
        now: start.add(const Duration(seconds: 1200)),
        utcOffset: offset,
      );
      expect(state, ActiveSessionState.running);
      expect(state.showsLiveActivity && state.suppressesReminders && state.countsAsTrained, isTrue);
    });

    test('alte Einheiten sind verworfen oder unbeendet', () {
      final start = at(1, 18);
      final next = start.add(const Duration(hours: 15));
      final empty = ActiveSessionState.of(session(start, 0), now: next, utcOffset: offset);
      expect(empty, ActiveSessionState.abandoned);
      expect(empty.suppressesReminders, isFalse);
      final withSets = ActiveSessionState.of(session(start, 2), now: next, utcOffset: offset);
      expect(withSets, ActiveSessionState.unfinished);
      expect(withSets.showsLiveActivity, isFalse);
      expect(ActiveSessionState.of(null, now: next), ActiveSessionState.none);
      // Geöffnet vor drei Stunden, nichts gemacht: Erinnerung darf wieder kommen.
      final today = at(2, 9);
      expect(
        ActiveSessionState.of(session(today, 0), now: today.add(const Duration(hours: 3)), utcOffset: offset),
        ActiveSessionState.abandoned,
      );
    });
  });
}

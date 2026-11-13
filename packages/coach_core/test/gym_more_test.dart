// Port von MuscleLoadTests.swift, GymPaket10Tests.swift und den übrigen Teilen von GymLibraryTests.swift
// (Routinenvorlagen, KI-Hinweise, Einstellungen).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 10, 22);

GymSession librarySession(int daysAgo, String exerciseID, List<LoggedSet> sets) => GymSession(
  workoutKey: null,
  title: 'Test',
  start: today.adding(-daysAgo).referenceDate,
  exercises: [
    LoggedExercise(
      exerciseID: exerciseID,
      name: ExerciseLibrary.byID[exerciseID]?.name ?? exerciseID,
      group: ExerciseLibrary.byID[exerciseID]?.group ?? MuscleGroup.other,
      sets: sets,
    ),
  ],
);

void main() {
  group('Muskelbelastung', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1793500000 * 1000, isUtc: true);

    GymSession session(List<LoggedExercise> exercises, {required double hoursAgo}) {
      final start = now.subtract(Duration(seconds: (hoursAgo * 3600).round()));
      return GymSession(
        workoutKey: null,
        title: 'Test',
        start: start,
        end: start.add(const Duration(hours: 1)),
        exercises: exercises,
      );
    }

    LoggedExercise exercise(String id, List<LoggedSet> sets, {MuscleGroup group = MuscleGroup.chest}) =>
        LoggedExercise(exerciseID: id, name: id, group: group, sets: sets);

    List<LoggedSet> repeat(int count, LoggedSet Function() make) => [
      for (var index = 0; index < count; index++) make(),
    ];

    test('mitarbeitende Muskeln zählen halb', () {
      final bench = exercise('bankdruecken', repeat(3, () => LoggedSet(reps: 8, weightKg: 80)));
      final load = MuscleLoad.session(session([bench], hoursAgo: 1));
      expect(load[Muscle.chest], 3);
      expect(load[Muscle.triceps], 1.5);
      expect(load[Muscle.frontDelts], 1.5);
      expect(load[Muscle.lats], isNull);
    });

    test('Aufwärm-, Drop- und leichte Sätze zählen weniger', () {
      final sets = [
        LoggedSet(reps: 10, weightKg: 40, kind: SetKind.warmup),
        LoggedSet(reps: 8, weightKg: 80, rir: 2),
        LoggedSet(reps: 8, weightKg: 80, rir: 4),
        LoggedSet(reps: 12, weightKg: 60, kind: SetKind.drop),
        LoggedSet(reps: 8, weightKg: 80, done: false),
      ];
      final load = MuscleLoad.session(session([exercise('beinstrecken', sets, group: MuscleGroup.legs)], hoursAgo: 1));
      expect(load[Muscle.quads], 2);
    });

    test('jeder Satz zählt je Muskel einmal', () {
      // Kniebeuge und Hüftstoß: Gesäß zählt je Satz einmal, nicht doppelt über „Beine“ und „Gesäß“.
      final squat = exercise('kniebeuge', [LoggedSet(reps: 5, weightKg: 100)], group: MuscleGroup.legs);
      final thrust = exercise('hueftstoss', [LoggedSet(reps: 10, weightKg: 80)], group: MuscleGroup.legs);
      final load = MuscleLoad.session(session([squat, thrust], hoursAgo: 1));
      expect(load[Muscle.glutes], 2);
      expect(load[Muscle.quads], 1);
      expect(load[Muscle.hamstrings], 0.5);
    });

    test('eigene Übung nutzt die Muskelgruppen', () {
      final custom = ExerciseInfo.custom(
        name: 'Meine Presse',
        group: MuscleGroup.shoulders,
        equipment: Equipment.machine,
        tracking: ExerciseTracking.weightReps,
      );
      final involvement = MuscleMap.involvement(custom.id, group: MuscleGroup.shoulders, custom: [custom]);
      expect(involvement[Muscle.sideDelts], 1);
      expect(MuscleMap.involvement('unbekannt', group: MuscleGroup.back), {Muscle.lats: 1.0});
    });

    test('Stand zeigt Erholung und lange Pausen', () {
      final legs = exercise('kniebeuge', repeat(4, () => LoggedSet(reps: 5, weightKg: 100)), group: MuscleGroup.legs);
      final chest = exercise('bankdruecken', repeat(3, () => LoggedSet(reps: 8, weightKg: 80)));
      final single = exercise('seitheben', [LoggedSet(reps: 12, weightKg: 8)], group: MuscleGroup.shoulders);
      final sessions = [
        session([legs], hoursAgo: 20),
        session([chest, single], hoursAgo: 24 * 5),
        session([chest], hoursAgo: 24 * 20),
      ];
      final status = {for (final item in MuscleLoad.status(sessions: sessions, now: now)) item.muscle: item};
      expect(status[Muscle.quads]?.recovery, MuscleRecovery.recovering);
      expect(status[Muscle.quads]?.weeklySets, 4);
      expect(status[Muscle.chest]?.recovery, MuscleRecovery.ready);
      expect(status[Muscle.chest]?.weeklySets, 3);
      expect(status[Muscle.chest]?.averageWeeklySets, 1.5);
      expect(status[Muscle.chest]?.isLow, isTrue);
      // Ein einzelner Satz ist keine nennenswerte Belastung.
      expect(status[Muscle.sideDelts]?.recovery, MuscleRecovery.neglected);
      expect(status[Muscle.calves]?.lastLoaded, isNull);
    });

    test('Belastung einer Routine aus geplanten Sätzen', () {
      final routine = Routine(
        name: 'Push',
        items: [
          RoutineItem(
            exerciseID: 'bankdruecken',
            name: 'Bankdrücken',
            sets: 3,
            lowerReps: 6,
            upperReps: 10,
            restSeconds: 120,
          ),
          RoutineItem(
            exerciseID: 'trizeps_pushdown',
            name: 'Pushdown',
            sets: 2,
            lowerReps: 8,
            upperReps: 12,
            restSeconds: 90,
          ),
        ],
      );
      final load = MuscleLoad.routine(routine);
      expect(load[Muscle.chest], 3);
      expect(load[Muscle.triceps], 3.5);
      expect(MuscleLoad.intensity(3, full: 6), 0.5);
      expect(MuscleLoad.intensity(9, full: 6), 1);
    });

    test('jede Übung der Bibliothek hat einen Muskel', () {
      for (final exercise in ExerciseLibrary.all) {
        expect(MuscleMap.involvement(exercise.id, group: exercise.group), isNotEmpty, reason: exercise.id);
        expect(MuscleMap.table[exercise.id], isNotNull, reason: '${exercise.id} fehlt in der Muskeltabelle');
      }
    });
  });

  group('Aufwärmen, KI-Plan und Pausenton (Paket 10)', () {
    LoggedExercise exercise(MuscleGroup group, double weight, {bool done = false}) => LoggedExercise(
      exerciseID: 'bench_press',
      name: 'Übung',
      group: group,
      sets: [LoggedSet(reps: 8, weightKg: weight, done: done)],
    );

    test('schwere Grundübung bekommt mehrere steigende Sätze', () {
      final steps = WarmUp.steps(working: 120, equipment: [Equipment.barbell], compound: true);
      expect(steps.length, 4);
      final weights = steps.map((step) => step.weightKg).toList();
      expect(weights, [...weights]..sort());
      expect(steps.every((step) => step.weightKg < 120), isTrue);
    });

    test('Einsteiger lassen den schwersten Aufwärmsatz weg', () {
      final beginner = WarmUp.steps(
        working: 100,
        equipment: [Equipment.barbell],
        compound: true,
        level: ExperienceLevel.beginner,
      );
      expect(beginner.map((step) => step.weightKg), [20, 50, 70]);
    });

    test('schwere Isolation ein Satz, leichte keiner', () {
      expect(WarmUp.steps(working: 40, equipment: [Equipment.machine], compound: false), [
        const WarmUpStep(weightKg: 24, reps: 10),
      ]);
      expect(WarmUp.steps(working: 10, equipment: [Equipment.dumbbell], compound: false), isEmpty);
      expect(WarmUp.steps(working: 50, equipment: [Equipment.bodyweight], compound: false), isEmpty);
    });

    test('aufgewärmter Muskel braucht nur einen Einstiegssatz', () {
      expect(WarmUp.steps(working: 80, equipment: [Equipment.barbell], compound: true, warmedUp: true), [
        const WarmUpStep(weightKg: 55, reps: 3),
      ]);
      expect(WarmUp.steps(working: 40, equipment: [Equipment.machine], compound: false, warmedUp: true), isEmpty);
    });

    test('frühere Übung desselben Muskels zählt als aufgewärmt', () {
      final info = ExerciseLibrary.info('bankdruecken')!;
      final done = exercise(info.group, 60, done: true);
      final next = exercise(info.group, 40);
      final session = GymSession(workoutKey: null, title: 'A', start: DateTime.now(), exercises: [done, next]);
      expect(WarmUp.isWarmedUp(next, info: info, session: session), isTrue);
      final fresh = GymSession(workoutKey: null, title: 'A', start: DateTime.now(), exercises: [next]);
      expect(WarmUp.isWarmedUp(next, info: info, session: fresh), isFalse);
    });

    test('Aufwärmsätze zählen nicht als Arbeit', () {
      final logged = LoggedExercise(
        exerciseID: 'bench_press',
        name: 'Bank',
        group: MuscleGroup.chest,
        sets: [
          LoggedSet(reps: 5, weightKg: 50, kind: SetKind.warmup),
          LoggedSet(reps: 8, weightKg: 100),
        ],
      );
      expect(logged.doneSets.length, 1);
    });

    test('Planeingabe nutzt gewählte Erfahrung und Ausstattung', () {
      final request = PlanRequest()..experience = ExperienceLevel.advanced;
      Map<String, Object?> input() => GymCoach.planInput(
        request: request,
        profile: UserProfile(),
        equipment: Equipment.gym,
        routines: [],
        sessions: [],
        custom: [],
        today: const CalendarDay(2026, 11, 9),
      );
      final all = input();
      request.equipment = {Equipment.bodyweight};
      final limited = input();
      expect(all['experience'], ExperienceLevel.advanced.label);
      expect((limited['library']! as List).length, lessThan((all['library']! as List).length));
    });

    test('leere Ausstattung blockiert, ungünstige Kombinationen werden erklärt', () {
      final request = PlanRequest()..equipment = {};
      expect(GymCoach.planIssues(request, equipment: Equipment.gym).blocking, isNotEmpty);
      request.equipment = null;
      expect(GymCoach.planIssues(request, equipment: Equipment.gym).blocking, isEmpty);
      request
        ..goal = PlanGoal.strength
        ..minutesPerSession = 30;
      expect(GymCoach.planIssues(request, equipment: Equipment.gym).hints, isNotEmpty);
      expect(PlanRequest.fromJson(jsonDecode(jsonEncode(request.toJson())))?.toJson(), request.toJson());
    });

    test('alte Einstellungen bekommen den Standardton, neue bleiben erhalten', () {
      final old = GymSettings.fromJson(jsonDecode('{}'));
      expect(old.restSound, RestSound.chime);
      expect(old.restHaptic, isTrue);
      old
        ..restSound = RestSound.off
        ..restHaptic = false;
      final again = GymSettings.fromJson(jsonDecode(jsonEncode(old.toJson())));
      expect(again.restSound, RestSound.off);
      expect(again.restHaptic, isFalse);
    });

    test('nur eigene Töne haben Dateien', () {
      expect(RestSound.off.fileName, isNull);
      expect(RestSound.system.fileName, isNull);
      expect(RestSound.values.map((sound) => sound.fileName).nonNulls.every((name) => name.endsWith('.wav')), isTrue);
    });
  });

  group('Routinenvorlagen', () {
    UserProfile profile(int strengthDays, {ExperienceLevel level = ExperienceLevel.intermediate}) {
      final profile = UserProfile(sports: [TrainingSport.strength], goal: FitnessGoal.buildMuscle)
        ..setLevel(level, TrainingSport.strength);
      for (final weekday in Weekday.values.take(strengthDays)) {
        profile.schedule = profile.schedule.withSlots([
          const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
        ], weekday);
      }
      return profile;
    }

    test('jeder große Muskel zweimal pro Woche', () {
      for (var days = 1; days <= 6; days++) {
        for (final equipment in [Equipment.gym, Equipment.homeDumbbells]) {
          final routines = RoutineTemplates.suggest(profile: profile(days), equipment: equipment);
          expect(routines, isNotEmpty);
          final sessionsPerGroup = <MuscleGroup, int>{};
          for (final routine in routines) {
            for (final group
                in routine.items.map((item) => ExerciseLibrary.byID[item.exerciseID]?.group).nonNulls.toSet()) {
              sessionsPerGroup[group] = (sessionsPerGroup[group] ?? 0) + 1;
            }
            expect(
              routine.items.every((item) => ExerciseLibrary.byID[item.exerciseID]?.isAvailable(equipment) == true),
              isTrue,
            );
            expect(routine.items.map((item) => item.exerciseID).toSet().length, routine.items.length);
          }
          for (final group in [MuscleGroup.chest, MuscleGroup.back, MuscleGroup.legs, MuscleGroup.shoulders]) {
            expect(
              sessionsPerGroup[group] ?? 0,
              greaterThanOrEqualTo(2),
              reason: '$group bei $days Tagen nur ${sessionsPerGroup[group] ?? 0}×',
            );
          }
        }
      }
    });

    test('Aufteilung hängt von Tagen und Erfahrung ab', () {
      expect(RoutineTemplates.suggest(profile: profile(2), equipment: Equipment.gym).length, 2);
      expect(RoutineTemplates.suggest(profile: profile(4), equipment: Equipment.gym).first.name, 'Oberkörper A');
      expect(RoutineTemplates.suggest(profile: profile(5), equipment: Equipment.gym).length, 5);
      final beginner = RoutineTemplates.suggest(
        profile: profile(2, level: ExperienceLevel.beginner),
        equipment: Equipment.gym,
      );
      expect(beginner.expand((routine) => routine.items).every((item) => item.sets == 2), isTrue);
      final none = RoutineTemplates.suggest(profile: profile(2), equipment: Equipment.none);
      expect(none.expand((routine) => routine.items).any((item) => item.exerciseID == 'liegestuetze'), isTrue);
      expect(none.repRanges['liegestuetze'], const IntRange(8, 20));
    });

    test('GymBook-Pläne nutzen bekannte Übungen', () {
      final plans = RoutineTemplates.gymBook;
      expect(plans.map((routine) => routine.name), ['Lower', 'Push & Pull B', 'Pull A', 'Push A']);
      for (final item in plans.expand((routine) => routine.items)) {
        expect(ExerciseLibrary.info(item.exerciseID), isNotNull, reason: item.exerciseID);
      }
      expect(plans.last.items.last.repRange, const IntRange(60, 60));
      for (final item in plans.expand((routine) => routine.items)) {
        expect(item.sets, 2);
      }
      expect(plans[3].items.firstWhere((item) => item.exerciseID == 'bankdruecken').weightKg, 52.5);
      expect(plans[3].items.last.upperReps, 60);
      // Ältere gespeicherte Routinen ohne Startgewicht bleiben lesbar.
      final old = RoutineItem.fromJson(
        jsonDecode(
          '{"id":"6F2C1C4E-9A57-4B4B-9E6D-6F0B2C8C2B11","exerciseID":"plank","name":"Plank","sets":2,'
          '"lowerReps":20,"upperReps":60,"restSeconds":60}',
        ),
      );
      expect(old, isNotNull);
      expect(old!.weightKg, isNull);
    });

    test('alte Einstellungen mit dem entfernten Fokus-Schlüssel', () {
      final decoded = GymSettings.fromJson(
        jsonDecode('{"routines":[],"customExercises":[],"equipment":["cable"],"tracksRIR":true,"focusShortcuts":true}'),
      );
      expect(decoded.tracksRIR, isTrue);
      expect(decoded.equipment, {Equipment.cable});
    });
  });

  group('KI-Hinweise', () {
    test('Eingabe trägt Entscheidungen und Belege', () {
      final easy = librarySession(2, 'kurzhantel_bankdruecken', [
        for (var index = 0; index < 3; index++) LoggedSet(reps: 8, weightKg: 20, rir: 4),
      ]);
      final progress = GymProgression.evaluateRanges(sessions: [easy], ranges: {}, today: today);
      final input = GymHints.input(
        progress: progress,
        recovered: true,
        volume: {MuscleGroup.chest: 3},
        goal: FitnessGoal.buildMuscle,
      );
      final line = (input['exercises']! as List<String>).first;
      expect(line, startsWith('Kurzhantel-Bankdrücken: zuletzt 20 kg × 8/8/8 Wdh., Ziel 6–10 → Erhöhen auf 22,5 kg'));
      expect(input['recovery'], 'gut');
      expect(input['goal'], 'Muskeln aufbauen');
      expect((input['volume']! as List).first, 'Brust: 3 Sätze in 7 Tagen');
      expect((input['evidence']! as List).length, GymHints.evidence.length);
      expect(GymHints.fallback(progress), ['Kurzhantel-Bankdrücken: Erhöhen auf 22,5 kg (+12,5 %).']);
    });
  });

  group('Gym-Einstellungen', () {
    test('eigene Übungen und Ausstattung', () {
      final own = ExerciseInfo.custom(
        name: ' Landmine Press ',
        group: MuscleGroup.shoulders,
        equipment: Equipment.barbell,
        tracking: ExerciseTracking.weightReps,
      );
      final settings = GymSettings()
        ..addCustom(own)
        ..addCustom(own);
      expect(settings.customExercises.length, 1);
      expect(settings.exercise(own.id)?.group, MuscleGroup.shoulders);
      expect(ExerciseLibrary.search('landmine', custom: settings.customExercises).map((item) => item.id), [own.id]);
      final decoded = GymSettings.fromJson(jsonDecode('{"tracksRIR":false}'));
      expect(decoded.tracksRIR, isFalse);
      expect(decoded.equipment, Equipment.gym);
    });
  });
}

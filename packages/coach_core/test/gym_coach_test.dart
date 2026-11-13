// Port von GymCoachTests.swift, GymOverviewTests.swift, GymBookImportTests.swift und UserSourcesTests.swift.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  group('Gym-Coach', () {
    final monday = DateTime.fromMillisecondsSinceEpoch(1792000000 * 1000, isUtc: true);
    final today = CalendarDay.fromDate(monday.toLocal());

    GymSession session({
      required int daysAgo,
      required double weight,
      required int reps,
      int sets = 3,
      String id = 'bankdruecken',
    }) => GymSession(
      workoutKey: null,
      title: 'Push',
      start: monday.subtract(Duration(days: daysAgo)),
      exercises: [
        LoggedExercise(
          exerciseID: id,
          name: 'Bankdrücken',
          group: MuscleGroup.chest,
          sets: [for (var index = 0; index < sets; index++) LoggedSet(reps: reps, weightKg: weight)],
        ),
      ],
    );

    test('Stillstand und wenig Volumen werden gemeldet', () {
      final sessions = [
        session(daysAgo: 14, weight: 60, reps: 8),
        session(daysAgo: 7, weight: 60, reps: 8),
        session(daysAgo: 1, weight: 60, reps: 8),
      ];
      final lines = GymCoach.observations(sessions: sessions, today: today);
      expect(lines.any((line) => line.startsWith('Bankdrücken: seit drei Einheiten 60 kg')), isTrue);
      expect(lines.any((line) => line.startsWith('Brust: 3 Sätze in 7 Tagen')), isTrue);
      expect(lines.any((line) => line.startsWith('Brust: nur an einem Tag')), isTrue);
      expect(lines.any((line) => line.startsWith('Beine: 0 Sätze')), isTrue);
    });

    test('Fortschritt ist kein Stillstand', () {
      final sessions = [
        session(daysAgo: 14, weight: 60, reps: 8),
        session(daysAgo: 7, weight: 60, reps: 9),
        session(daysAgo: 1, weight: 60, reps: 10),
      ];
      final lines = GymCoach.observations(sessions: sessions, today: today);
      expect(lines.any((line) => line.contains('Stillstand')), isFalse);
      expect(GymCoach.observations(sessions: [], today: today), isEmpty);
    });

    test('Plan wird gegen Bibliothek, Ausstattung und Grenzen geprüft', () {
      final output = JsonValue.parse('''
        {"routinen": [
          {"name": "Oberkörper", "uebungen": [
            {"id": "bankdruecken", "saetze": 9, "wdh_min": 6, "wdh_max": 10, "pause": 600},
            {"id": "erfunden", "saetze": 3},
            {"id": "bankdruecken", "saetze": 3},
            {"id": "plank", "saetze": 2, "wdh_min": 30, "wdh_max": 500}
          ]},
          {"name": "Beine", "uebungen": [{"id": "kniebeuge", "saetze": 3}]},
          {"name": "Zu viel", "uebungen": [{"id": "latziehen", "saetze": 3}]}
        ], "hinweise": ["Zweimal pro Woche je Muskel."]}''');
      final request = PlanRequest()..daysPerWeek = 2;
      final result = GymCoach.validatePlan(
        output,
        request: request,
        equipment: {Equipment.machine, Equipment.cable, Equipment.bench, Equipment.barbell},
        custom: [],
        lastWeights: {'bankdruecken': 52.5},
      );
      expect(result.routines.map((routine) => routine.name), ['Oberkörper', 'Beine']);
      final upper = result.routines[0].items;
      expect(upper.map((item) => item.exerciseID), ['bankdruecken', 'plank']);
      expect(upper[0].sets, 5);
      expect(upper[0].restSeconds, 240);
      expect(upper[0].weightKg, 52.5);
      expect(upper[1].upperReps, 120);
      expect(result.corrections, contains('Unbekannte Übung „erfunden“ entfernt.'));
      expect(result.corrections, contains('Bankdrücken: Sätze auf 5 begrenzt.'));
      expect(result.notes.first, 'Zweimal pro Woche je Muskel.');
      expect(result.notes.any((note) => note.startsWith('Rücken: 0 Sätze pro Woche')), isTrue);

      // Ohne Langhantel fällt die Kniebeuge weg.
      final home = GymCoach.validatePlan(output, request: request, equipment: Equipment.homeDumbbells, custom: []);
      expect(home.routines.map((routine) => routine.name), ['Oberkörper']);
      expect(home.corrections.any((line) => line.startsWith('Kniebeuge braucht Ausstattung')), isTrue);
    });

    test('Planeingabe nennt nur machbare Übungen', () {
      final request = PlanRequest()
        ..daysPerWeek = 9
        ..focus = [MuscleGroup.chest];
      final input = GymCoach.planInput(
        request: request,
        profile: UserProfile(),
        equipment: Equipment.none,
        routines: RoutineTemplates.gymBook,
        sessions: [session(daysAgo: 1, weight: 52.5, reps: 12)],
        custom: [],
        today: today,
      );
      expect(input['days'], 6);
      final library = input['library']! as List<String>;
      expect(library.any((line) => line.startsWith('plank |')), isTrue);
      expect(library.any((line) => line.startsWith('bankdruecken |')), isFalse);
      expect(input['lastWeights'], ['bankdruecken: 52,5 kg × 12']);
      expect(input['focus'], ['Brust']);
    });
  });

  group('Gym-Übersicht', () {
    const today = CalendarDay(2026, 10, 28);

    ExerciseProgress progress(ProgressStatus status, {double weight = 60, double? next = 62.5}) => ExerciseProgress(
      exerciseID: 'bankdruecken',
      name: 'Bankdrücken',
      group: MuscleGroup.chest,
      lastDay: today.adding(-3),
      daysSince: 3,
      weightKg: weight,
      reps: [10, 10, 10],
      target: const IntRange(6, 10),
      sessions: 4,
      nextWeightKg: next,
      increasePercent: 4.2,
      status: status,
    );

    test('Zieltext erklärt den Vorschlag', () {
      expect(
        GymTarget.text(progress(ProgressStatus.increase), recovered: true),
        'Ziel heute: 62,5 kg × 6–10 (+2,5 kg) – letztes Mal 60 × 10/10/10',
      );
      // Schlechte Erholung: keine Steigerung, gleiches Gewicht.
      expect(
        GymTarget.text(progress(ProgressStatus.increase), recovered: false),
        startsWith('Ziel heute: 60 kg, mehr'),
      );
      expect(
        GymTarget.text(progress(ProgressStatus.restart, next: 54), recovered: null),
        startsWith('Wiedereinstieg: 54 kg'),
      );
      expect(
        GymTarget.text(progress(ProgressStatus.build, weight: 0, next: null), recovered: null),
        contains('Wiederholungen'),
      );
    });

    DateTime noon(CalendarDay day) => DateTime(day.year, day.month, day.day, 12);

    GymSession session(String? key, {required int daysAgo, double weight = 50}) => GymSession(
      workoutKey: key,
      title: 'x',
      start: noon(today.adding(-daysAgo)),
      exercises: [
        LoggedExercise(
          exerciseID: 'bankdruecken',
          name: 'Bankdrücken',
          group: MuscleGroup.chest,
          sets: [LoggedSet(reps: 10, weightKg: weight)],
        ),
      ],
    );

    test('Rotation nimmt die Routine nach der letzten', () {
      final squat = RoutineItem(
        exerciseID: 'kniebeuge',
        name: 'Kniebeuge',
        sets: 3,
        lowerReps: 6,
        upperReps: 10,
        restSeconds: 120,
      );
      final a = Routine(name: 'A', items: [squat]);
      final b = Routine(name: 'B', items: []);
      expect(RoutineRotation.next(routines: [a, b], sessions: [])?.name, 'A');
      final sessions = [session(RoutineRotation.key(a), daysAgo: 4), session(RoutineRotation.key(b), daysAgo: 2)];
      expect(RoutineRotation.next(routines: [a, b], sessions: sessions)?.name, 'A');
      expect(RoutineRotation.next(routines: [a, b], sessions: [sessions[0]])?.name, 'B');
      expect(RoutineRotation.estimatedMinutes(a), 10);
    });

    test('Vergleich mit der letzten gleichen Einheit', () {
      final old = session('routine-x', daysAgo: 7, weight: 50);
      final other = session('routine-y', daysAgo: 3, weight: 80);
      final current = session('routine-x', daysAgo: 0, weight: 55);
      final previous = SessionComparison.previous(current, sessions: [old, other, current]);
      expect(previous?.id, old.id);
      expect(SessionComparison.volumeChangePercent(current, previous: previous), 10);
      expect(SessionComparison.volumeChangePercent(current, previous: null), isNull);
    });

    test('Kalender und Serie', () {
      // Mittwoch 28.10.: diese Woche nichts, letzte und vorletzte Woche je eine Einheit, davor Lücke.
      final sessions = [
        for (final days in [7, 8, 14, 30]) session(null, daysAgo: days),
      ];
      final weeks = GymCalendar.weeks(sessions: sessions, today: today, count: 4);
      expect(weeks.map((week) => week.sessions), [0, 1, 2, 0]);
      expect(weeks.last.monday, const CalendarDay(2026, 10, 26));
      expect(GymCalendar.streak(sessions: sessions, today: today), 2);
      expect(GymCalendar.streak(sessions: [...sessions, session(null, daysAgo: 0)], today: today), 3);
    });
  });

  group('GymBook-Import', () {
    test('Zuordnung zeigt auf Übungen der Bibliothek', () {
      expect(GymBookImport.mapping.length, 29);
      for (final MapEntry(key: name, value: id) in GymBookImport.mapping.entries) {
        expect(ExerciseLibrary.info(id), isNotNull, reason: '$name → $id');
      }
    });

    test('Zeilen werden zu Einheiten mit Sätzen', () {
      const rows = [
        GymBookLogRow(
          day: '2026-10-23',
          secondsOfDay: 28340,
          exercise: 'Curls in Hammerhaltung am Kabel',
          frequency: 10,
          quantity: 22.5,
          workout: 'Push & Pull B',
        ),
        GymBookLogRow(
          day: '2026-10-23',
          secondsOfDay: 28613,
          exercise: 'Curls in Hammerhaltung am Kabel',
          frequency: 9,
          quantity: 22.5,
          workout: 'Push & Pull B',
        ),
        GymBookLogRow(
          day: '2026-10-23',
          secondsOfDay: 29000,
          exercise: 'Bankdrücken an Multipresse',
          region: '020.chest',
          equipment: '010.flatBench|050.smithMachine',
          frequency: 8,
          quantity: 40,
          workout: 'Push & Pull B',
        ),
        GymBookLogRow(
          day: '2026-10-23',
          secondsOfDay: 31290,
          exercise: 'Planks',
          frequency: 60,
          frequencyUnit: 's',
          quantity: null,
          workout: 'Push & Pull B',
        ),
        // ausgelassen, Ausdauer und ohne Wiederholungen: nicht übernehmen
        GymBookLogRow(
          day: '2026-10-23',
          secondsOfDay: 31300,
          exercise: 'Dips am Barren',
          frequency: 5,
          quantity: 79,
          skipped: true,
          workout: 'Push & Pull B',
        ),
        GymBookLogRow(
          day: '2024-02-06',
          secondsOfDay: 30000,
          exercise: 'Stationäres Radfahren',
          frequency: 5,
          frequencyUnit: 'm',
          quantity: 10,
          quantityUnit: 'km',
        ),
        GymBookLogRow(
          day: '2026-10-21',
          secondsOfDay: 30000,
          exercise: 'Einarmiges Lat-Ziehen',
          frequency: null,
          quantity: 50,
          workout: 'Pull A',
        ),
      ];
      final result = GymBookImport.sessions(rows, custom: []);
      expect(result.ignoredRows, 3);
      expect(result.sessions.length, 1);
      final session = result.sessions[0];
      expect(session.title, 'Push & Pull B');
      expect(session.workoutKey, 'gymbook:2026-10-23:Push & Pull B');
      expect(session.exercises.map((exercise) => exercise.exerciseID), [
        'hammer_curl_kabel',
        'eigen_bankdruecken_an_multipresse',
        'plank',
      ]);
      expect(session.exercises[0].sets.map((set) => set.reps), [10, 9]);
      expect(session.exercises[0].sets.every((set) => set.weightKg == 22.5 && set.done), isTrue);
      expect(session.exercises[2].sets.first.reps, 60);
      expect(session.end!.difference(session.start).inSeconds, 3010);
      expect(session.day, const CalendarDay(2026, 10, 23));
      // Gleiche ID wie die Swift-App (FNV-1a mit 64-Bit-Überlauf, in Python nachgerechnet).
      expect(session.id, '884F1567-4F33-48CE-AFE7-A6D47DF252F4');

      final multipresse = result.newCustom.first;
      expect(multipresse.group, MuscleGroup.chest);
      expect(multipresse.equipment, [Equipment.machine]);

      // Zweiter Import: gleiche ID, keine neue eigene Übung.
      final again = GymBookImport.sessions(rows, custom: result.newCustom);
      expect(again.sessions.first.id, session.id);
      expect(again.newCustom, isEmpty);
    });

    test('Arme werden in Bizeps und Trizeps aufgeteilt', () {
      expect(GymBookImport.group(region: '040.arms', muscles: '041.armFlexors'), MuscleGroup.biceps);
      expect(GymBookImport.group(region: '040.arms', muscles: '040.armExtensors'), MuscleGroup.triceps);
      expect(GymBookImport.group(region: '060.buttocks', muscles: '060.glutes'), MuscleGroup.legs);
      expect(GymBookImport.equipment('078.cablesMachine'), Equipment.cable);
      expect(GymBookImport.equipment('031.dumbbells'), Equipment.dumbbell);
    });
  });

  group('Eigene Quellen', () {
    final sleep = UserSource(
      citation: 'Walker 2024',
      reference: '10.1000/xyz',
      statement: 'Mehr Schlaf verbessert die Sprintleistung.',
      topics: {UserSourceTopic.recovery},
    );
    final protein = UserSource(
      citation: 'Morton et al. 2018',
      reference: 'PMID: 28698222',
      statement: 'Über 1,6 g Protein je kg brachte kaum zusätzlichen Muskelzuwachs.',
      topics: {UserSourceTopic.nutrition, UserSourceTopic.strength},
    );

    test('passende Quellen nach den Regeln der App', () {
      final input = <String, Object?>{
        'evidence': [
          {'id': 'gym.volume', 'statement': 'Mehr Sätze.'},
        ],
      };
      final gym = UserSources.inject([sleep, protein], input, task: 'gym_hints');
      final evidence = gym['evidence']! as List;
      expect(evidence.map((item) => (item as Map)['id']), ['gym.volume', sleep.evidenceID, protein.evidenceID]);
      expect(((evidence.last as Map)['statement'] as String).endsWith('(eigene Quelle: Morton et al. 2018)'), isTrue);
      expect((UserSources.inject([sleep, protein], input, task: 'nutrition_review')['evidence']! as List).length, 2);
      expect((UserSources.inject([sleep, protein], {}, task: 'coach_chat')['evidence']! as List).length, 2);
      expect(UserSources.inject([sleep], input, task: 'meal_analyze'), same(input));
    });

    test('Links und Gültigkeit', () {
      expect(sleep.url.toString(), 'https://doi.org/10.1000/xyz');
      expect(protein.url.toString(), 'https://pubmed.ncbi.nlm.nih.gov/28698222/');
      expect(UserSource(citation: '', statement: 'zu kurz').isValid, isFalse);
      expect(UserSources.isUserID(sleep.evidenceID), isTrue);
      final answer = JsonValue({
        'quellen': [sleep.evidenceID, 'erfunden'],
      });
      expect(CoachingNote.sources(answer), [sleep.evidenceID]);
      expect(UserSource.fromJson(sleep.toJson()), sleep);
    });

    test('Regeln und Quellen der App', () {
      expect(Evidence.studies.length, 75);
      expect(Evidence.rules.length, 47);
      expect(Evidence.studiesByID.length, Evidence.studies.length);
      expect(Evidence.rulesByID.length, Evidence.rules.length);
      for (final rule in Evidence.rules) {
        expect(rule.studies.length, rule.studyIDs.length, reason: '${rule.id}: unbekannte Studie');
      }
      for (final id in [...GymHints.evidence, ...CoachingNote.dailyNoteEvidence]) {
        expect(Evidence.rulesByID[id], isNotNull, reason: id);
      }
    });
  });
}

// Port von RunPlanTests.swift, InputCheckTests (SafeguardTests.swift), PostWorkoutTests (ActivityFeedTests.swift),
// den Planvorschlägen aus TrainingTodayTests.swift sowie den Planer-Fällen aus AuditR4APlanTests.swift und
// Phase78Tests.swift.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

WeekSchedule schedule(Map<Weekday, List<SessionSlot>> plan) {
  var result = WeekSchedule();
  for (final MapEntry(key: weekday, value: slots) in plan.entries) {
    result = result.withSlots(slots, weekday);
  }
  return result;
}

UserProfile person(
  List<TrainingSport> sports,
  Map<TrainingSport, ExperienceLevel> levels, {
  FitnessGoal goal = FitnessGoal.improveFitness,
  EventGoal? event,
  WeekSchedule? plan,
}) {
  final profile = UserProfile(sports: sports, goal: goal, event: event, schedule: plan);
  for (final MapEntry(key: sport, value: level) in levels.entries) {
    profile.setLevel(level, sport);
  }
  return profile;
}

void main() {
  group('Laufplan', () {
    /// Montag, 9.11.2026: Aufbauwoche; 2.11. ist eine Entlastungswoche (jede vierte ab 5.1.2026).
    const buildMonday = CalendarDay(2026, 11, 9);
    const deloadMonday = CalendarDay(2026, 11, 2);
    UserProfile runner() =>
        UserProfile(mode: ProfileMode.personal, onboardingDone: true, sports: [TrainingSport.run])
          ..setLevel(ExperienceLevel.intermediate, TrainingSport.run);
    final plan = schedule({
      Weekday.tuesday: [const SessionSlot(TrainingSport.run)],
      Weekday.thursday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
      Weekday.sunday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
    });

    /// Vier Wochen mit je 150 Minuten Laufen vor [monday].
    List<GarminActivity> history(CalendarDay monday, {double minutesPerWeek = 150}) => [
      for (var back = 1; back <= 28; back++)
        if (back % 7 == 1 || back % 7 == 4 || back % 7 == 6)
          GarminActivity(back)
            ..typeKey = 'running'
            ..startLocal = '${monday.adding(-back).iso} 07:00:00'
            // Wie in echten Wochen: ein längerer Lauf und zwei kürzere. Sonst deckelt die Einzellauf-Grenze jeden
            // Aufbau.
            ..durationSeconds = minutesPerWeek / 3 * (back % 7 == 1 ? 1.4 : 0.8) * 60,
    ];

    test('Aufbauwoche wächst höchstens um 10 %', () {
      final week = RunPlanner.week(
        profile: runner(),
        schedule: plan,
        monday: buildMonday,
        activities: history(buildMonday),
      )!;
      expect(week.phase, RunPhase.build);
      expect(week.baselineMinutes, 150);
      // Rundung auf 5 Minuten je Einheit: kleine Abweichung erlaubt.
      expect(week.totalMinutes, lessThanOrEqualTo(150 * 1.10 + 10));
      expect(week.totalMinutes, greaterThan(150));
      final long = week.sessions.firstWhere((session) => session.slot.intensity == SessionIntensity.long);
      final easy = week.sessions.firstWhere((session) => session.slot.intensity == SessionIntensity.easy);
      expect(long.minutes, greaterThan(easy.minutes));
      final hard = week.sessions.firstWhere((session) => session.slot.intensity == SessionIntensity.hard);
      expect(hard.detail, contains('Minuten'));
    });

    test('passt sich dem an, was wirklich gelaufen wurde', () {
      // Nur 60 Minuten pro Woche geschafft: Der Plan startet von dort, nicht vom Wunsch.
      final week = RunPlanner.week(
        profile: runner(),
        schedule: plan,
        monday: buildMonday,
        activities: history(buildMonday, minutesPerWeek: 60),
      )!;
      expect(week.baselineMinutes, 60);
      expect(week.totalMinutes, lessThanOrEqualTo(80));
    });

    test('Entlastung und Tapering', () {
      final deload = RunPlanner.week(
        profile: runner(),
        schedule: plan,
        monday: deloadMonday,
        activities: history(deloadMonday),
      )!;
      expect(deload.phase, RunPhase.deload);
      expect(deload.totalMinutes, lessThanOrEqualTo(150 * 0.7 + 10));
      final racer = runner()..event = EventGoal(name: '10 km', date: buildMonday.adding(6), kind: EventKind.run10k);
      final race = RunPlanner.week(
        profile: racer,
        schedule: plan,
        monday: buildMonday,
        activities: history(buildMonday),
      )!;
      expect(race.phase, RunPhase.race);
      expect(race.sessions.any((session) => session.detail.contains('Wettkampf')), isTrue);
      expect(RunPlanner.phase(buildMonday.adding(-7), event: racer.event), RunPhase.taper);
    });

    test('ohne Verlauf Startwert der Stufe, ohne Läufe kein Plan', () {
      final beginner = runner()..setLevel(ExperienceLevel.beginner, TrainingSport.run);
      final week = RunPlanner.week(profile: beginner, schedule: plan, monday: buildMonday, activities: [])!;
      expect(week.baselineMinutes, 60);
      expect(week.sessions.every((session) => session.minutes >= RunPlanner.minimumSessionMinutes), isTrue);
      final noRuns = schedule({
        Weekday.monday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
      });
      expect(RunPlanner.week(profile: runner(), schedule: noRuns, monday: buildMonday, activities: []), isNull);
    });

    test('geplanter Lauf bleibt nahe am längsten Lauf (Phase 78)', () {
      const monday = CalendarDay(2026, 11, 9);
      final saturday = schedule({
        Weekday.saturday: [const SessionSlot(TrainingSport.run)],
      });
      final profile = UserProfile(sports: [TrainingSport.run], schedule: saturday)
        ..setLevel(ExperienceLevel.advanced, TrainingSport.run);
      final runs = [
        for (var index = 0; index < 8; index++)
          GarminActivity(index)
            ..typeKey = 'running'
            ..startLocal = '${monday.adding(-2 - index * 3).iso} 07:00:00'
            ..distanceMeters = 10000
            ..durationSeconds = 3600,
      ];
      final week = RunPlanner.week(profile: profile, schedule: saturday, monday: monday, activities: runs)!;
      expect(week.sessions.first.minutes, lessThanOrEqualTo(66));
    });
  });

  group('Eingabeprüfung', () {
    /// Montag, 2.11.2026.
    const monday = CalendarDay(2026, 11, 2);
    const body = BodyProfile(weightKilograms: 72, heightCentimeters: 170, age: 30, isFemale: true);

    test('unplausible Körperwerte', () {
      expect(InputCheck.body(body), isEmpty);
      const typo = BodyProfile(weightKilograms: 720, heightCentimeters: 17, age: 300, isFemale: true);
      expect(InputCheck.body(typo).map((issue) => issue.id).toSet(), {'weight', 'height', 'age'});
    });

    test('widersprüchliche Gewichtsziele', () {
      final profile = UserProfile(
        goal: FitnessGoal.loseWeight,
        targets: const ImprovementTargets(targetWeightKilograms: 75),
      );
      final issues = InputCheck.goals(profile: profile, body: body, predictions: null, today: monday);
      expect(issues.first.id, 'target-weight-direction');
      profile.targets = const ImprovementTargets(targetWeightKilograms: 65);
      expect(InputCheck.goals(profile: profile, body: body, predictions: null, today: monday), isEmpty);
    });

    test('Zielzeit gegen die Prognose der Uhr', () {
      final predictions = RacePredictions(tenK: 3000, halfMarathon: 6600);
      final profile = UserProfile()
        ..event = EventGoal(name: 'HM', date: monday.adding(70), kind: EventKind.halfMarathon, targetSeconds: 5700);
      final veryFast = InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first;
      expect(veryFast.severity, InputSeverity.warning);
      expect(veryFast.message, contains('14 % schneller'));
      expect(veryFast.message, contains('10 Wochen'));
      profile.event = EventGoal(name: 'HM', date: monday.adding(70), kind: EventKind.halfMarathon, targetSeconds: 6200);
      expect(
        InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first.severity,
        InputSeverity.tip,
      );
      profile.event = EventGoal(name: 'HM', date: monday.adding(70), kind: EventKind.halfMarathon, targetSeconds: 6700);
      expect(
        InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first.severity,
        InputSeverity.info,
      );
      profile.event = EventGoal(name: 'HM', date: monday.adding(-1), kind: EventKind.halfMarathon, targetSeconds: 6700);
      expect(
        InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first.id,
        'event-past',
      );
    });

    test('Prognose zwischen zwei Strecken interpoliert', () {
      final predictions = RacePredictions(fiveK: 1500, tenK: 3120);
      final fifteen = InputCheck.predictedSeconds(7.5, predictions: predictions)!;
      expect(fifteen > 1500 && fifteen < 3120, isTrue);
      expect(InputCheck.predictedSeconds(10, predictions: predictions), 3120);
      expect(InputCheck.predictedSeconds(3, predictions: predictions), isNull);
      expect(InputCheck.predictedSeconds(5, predictions: null), isNull);
    });

    test('Prognosen aus der Garmin-Antwort', () {
      final predictions = RacePredictions.fromGarmin(
        JsonValue.parse('[{"calendarDate": "2026-11-01", "time5K": 1500, "time10K": 3120, "timeMarathon": 0}]'),
      )!;
      expect(predictions.fiveK, 1500);
      expect(predictions.marathon, isNull);
      expect(predictions.day, const CalendarDay(2026, 11, 1));
      expect(RacePredictions.fromGarmin(JsonValue.parse('{"time5K": 0}')), isNull);
      expect(RacePredictions.fromJson(predictions.toJson()), predictions);
    });
  });

  group('Nach dem Training', () {
    const today = CalendarDay(2026, 10, 28);

    test('harter lockerer Lauf entschärft morgen', () {
      final run = GarminActivity(1)
        ..typeKey = 'running'
        ..startLocal = '${today.iso} 07:00:00'
        ..durationSeconds = 45 * 60;
      final planned = SessionResult(
        planned: PlannedSession(day: today, slot: const SessionSlot(TrainingSport.run)),
        status: SessionStatus.done,
        activityID: 1,
        actualMinutes: 45,
      );
      final plan = schedule({
        Weekday.thursday: [
          const SessionSlot(TrainingSport.run, SessionIntensity.hard),
          const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
        ],
      });
      final review = PostWorkout.review(
        activity: run,
        effort: 8,
        planned: planned,
        tomorrow: today.adding(1),
        tomorrowSchedule: plan,
      );
      expect(review.headline, 'Wie geplant');
      expect(review.points.any((point) => point.startsWith('Für eine lockere Einheit war das hart')), isTrue);
      expect(review.points.last, 'Anstrengung 8/10 × 45 min ≈ Belastung 90 (session RPE).');
      expect(review.evidenceIDs, ['intensity.distribution', 'load.rpe']);
      expect(review.tomorrow?.schedule.slots(Weekday.thursday), [
        const SessionSlot(TrainingSport.run),
        const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
      ]);
      final easy = PostWorkout.review(
        activity: run,
        effort: 3,
        planned: planned,
        tomorrow: today.adding(1),
        tomorrowSchedule: plan,
      );
      expect(easy.tomorrow, isNull);
      expect(easy.points.length, 2);
    });

    test('außerplanmäßig und kürzer', () {
      final bike = GarminActivity(2)
        ..typeKey = 'cycling'
        ..durationSeconds = 20 * 60;
      final free = PostWorkout.review(
        activity: bike,
        effort: null,
        planned: null,
        tomorrow: today.adding(1),
        tomorrowSchedule: null,
      );
      expect(free.headline, 'Außerplanmäßig');
      final partial = SessionResult(
        planned: PlannedSession(day: today, slot: const SessionSlot(TrainingSport.bike)),
        status: SessionStatus.partial,
        activityID: 2,
        actualMinutes: 20,
      );
      final short = PostWorkout.review(
        activity: bike,
        effort: null,
        planned: partial,
        tomorrow: today.adding(1),
        tomorrowSchedule: null,
      );
      expect(short.headline, 'Kürzer als geplant');
      expect(short.points.first, startsWith('Soll 45 min · Ist 20 min'));
    });
  });

  group('Planvorschläge', () {
    /// Mittwoch, 28.10.2026.
    const today = CalendarDay(2026, 10, 28);
    const monday = CalendarDay(2026, 10, 26);

    /// Di intensiv, Do intensiv, Sa lang.
    UserProfile profile() => UserProfile(
      sports: [TrainingSport.run],
      schedule: schedule({
        Weekday.tuesday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.thursday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
      }),
    );

    WeekLoadResult warning({double increase = 0.6}) =>
        WeekLoadResult(last: 160, baseline: 100, bySport: const {}, estimatedShare: 0)
          ..increase = increase
          ..warning = 'Zu viel Belastung.';

    test('Belastung entschärft den nächsten harten Tag', () {
      final suggestion = PlanSuggestion.load(
        warning(),
        profile: profile(),
        adjustments: PlanAdjustments(),
        today: today,
      )!;
      expect(suggestion.source, PlanSuggestionSource.load);
      expect(suggestion.changes.map((change) => change.text), [
        'Do: Qualitätslauf (Tempo oder Intervalle) → Lockerer Lauf',
      ]);
      expect(suggestion.unchanged, ['Di: Qualitätslauf (Tempo oder Intervalle) bleibt', 'Sa: Langer Lauf bleibt']);
      expect(suggestion.adjustments.schedule(profile().schedule, inWeekOf: today).slots(Weekday.thursday), [
        const SessionSlot(TrainingSport.run),
      ]);
      expect(suggestion.conflicts, isEmpty);
      expect(suggestion.week, monday);
      expect(
        PlanSuggestion.load(warning(), profile: profile(), adjustments: PlanAdjustments(), today: today.adding(3)),
        isNull,
      );
    });

    test('Vorschlag zeigt neue Regelkonflikte', () {
      final base = profile();
      final after = base.schedule.withSlots([
        const SessionSlot(TrainingSport.run, SessionIntensity.hard),
      ], Weekday.wednesday);
      final suggestion = PlanSuggestion.make(
        id: 'test',
        source: PlanSuggestionSource.recovery,
        title: 'Test',
        reason: '',
        profile: base,
        adjustments: PlanAdjustments(),
        week: today,
        edit: (proposed) => proposed.setWeekPlan(after, base: base.schedule, inWeekOf: today),
      )!;
      expect(suggestion.changes.map((change) => change.weekday), [Weekday.wednesday]);
      expect(suggestion.conflicts.any((hint) => hint.id.startsWith('back-to-back')), isTrue);
      expect(
        PlanSuggestion.make(
          id: 'none',
          source: PlanSuggestionSource.recovery,
          title: '',
          reason: '',
          profile: base,
          adjustments: PlanAdjustments(),
          week: today,
          edit: (_) {},
        ),
        isNull,
      );
    });

    test('Tagesform und nächste Woche', () {
      final thursday = today.adding(1);
      const advice = ScheduleAdvice(
        mode: ScheduleAdviceMode.rest,
        headline: 'Heute frei',
        detail: 'HRV niedrig',
        move: Weekday.friday,
        plannedTitles: [],
        evidenceIDs: [],
      );
      final move = PlanSuggestion.recovery(
        advice: advice,
        profile: profile(),
        adjustments: PlanAdjustments(),
        today: thursday,
      )!;
      expect(move.changes.map((change) => change.weekday), [Weekday.thursday, Weekday.friday]);
      expect(move.adjustments.note(Weekday.thursday, inWeekOf: thursday), 'verschoben auf Freitag');
      final next = PlanSuggestion.nextWeek(
        load: warning(),
        profile: profile(),
        adjustments: PlanAdjustments(),
        today: today,
      )!;
      expect(next.week, monday.adding(7));
      expect(next.changes.map((change) => change.weekday), [Weekday.tuesday]);
      expect(next.reason, startsWith('Diese Woche lag die Belastung 60 %'));
      final noWarning = warning()..warning = null;
      expect(
        PlanSuggestion.nextWeek(load: noWarning, profile: profile(), adjustments: PlanAdjustments(), today: today),
        isNull,
      );
    });

    test('Verschieben bleibt in der Zukunft dieser Woche (R4A)', () {
      final plan = schedule({
        Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
        Weekday.sunday: [const SessionSlot(TrainingSport.run)],
      });
      final runner = person([TrainingSport.run], {TrainingSport.run: ExperienceLevel.intermediate}, plan: plan);
      final saturday = monday.adding(5);
      final advice = ScheduleAdvisor.advice(
        profile: runner,
        day: saturday,
        recovery: RecoveryLevel.pause,
        trainedToday: false,
      );
      final suggestion = PlanSuggestion.recovery(
        advice: advice,
        profile: runner,
        adjustments: PlanAdjustments(),
        today: saturday,
      );
      expect(
        suggestion?.changes.every((change) => change.weekday.rawValue >= Weekday.saturday.rawValue) ?? true,
        isTrue,
      );
    });
  });

  group('Wochenplaner (Audit R4A)', () {
    const monday = CalendarDay(2026, 10, 26);

    test('Marathon an zwei Tagen bekommt trotzdem Läufe', () {
      final event = EventGoal(name: 'Marathon', date: monday.adding(150), kind: EventKind.marathon);
      final runner = person(
        [TrainingSport.run, TrainingSport.strength],
        {TrainingSport.run: ExperienceLevel.intermediate, TrainingSport.strength: ExperienceLevel.intermediate},
        event: event,
      );
      final result = SchedulePlanner.suggest(profile: runner, availableDays: [Weekday.saturday, Weekday.sunday]);
      expect(result.sessionCount, 2);
      expect(result.count(TrainingSport.run), greaterThanOrEqualTo(1));
    });

    test('Triathlon an drei Tagen behält alle Disziplinen', () {
      final event = EventGoal(name: 'Sprint', date: monday.adding(90), kind: EventKind.triathlon);
      final athlete = person(
        [TrainingSport.swim, TrainingSport.bike, TrainingSport.run, TrainingSport.strength],
        {
          TrainingSport.swim: ExperienceLevel.intermediate,
          TrainingSport.bike: ExperienceLevel.intermediate,
          TrainingSport.run: ExperienceLevel.intermediate,
          TrainingSport.strength: ExperienceLevel.intermediate,
        },
        event: event,
      );
      final result = SchedulePlanner.suggest(
        profile: athlete,
        availableDays: [Weekday.tuesday, Weekday.thursday, Weekday.saturday],
      );
      expect(result.sessionCount, 3);
      for (final sport in [TrainingSport.swim, TrainingSport.bike, TrainingSport.run]) {
        expect(result.count(sport), 1);
      }
    });

    test('Lauf-Einsteiger mit Krafterfahrung läuft locker', () {
      final runner = person(
        [TrainingSport.run, TrainingSport.strength],
        {TrainingSport.run: ExperienceLevel.beginner, TrainingSport.strength: ExperienceLevel.advanced},
        goal: FitnessGoal.loseWeight,
      );
      final result = SchedulePlanner.suggest(
        profile: runner,
        availableDays: [Weekday.monday, Weekday.wednesday, Weekday.friday, Weekday.saturday],
      );
      final runs = result.days.expand((day) => day).where((slot) => slot.sport == TrainingSport.run).toList();
      expect(runs, isNotEmpty);
      expect(runs.every((slot) => slot.intensity == SessionIntensity.easy), isTrue);
      // Die Wochenprüfung soll die Einsteiger-Regel ebenfalls anwenden.
      final hard = schedule({
        Weekday.tuesday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.friday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
      });
      expect(ScheduleCheck.hints(hard, runner).any((hint) => hint.id == 'beginner-hard'), isTrue);
    });
  });
}

// Port von CoachCoreTests/SessionMatchTests.swift, PlanAdjustmentsTests.swift (ohne ScheduleAdvisor und
// Saisonplan-Erinnerungen, die mit ihren Modulen folgen), TrainingBreakTests.swift und den ScheduleCheck-Fällen aus
// ProfileTests.swift (ohne `everyEvidenceIDExists`, folgt mit Evidence).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

WeekSchedule plan(Map<Weekday, List<SessionSlot>> slots) {
  var result = WeekSchedule();
  for (final MapEntry(key: weekday, value: list) in slots.entries) {
    result = result.withSlots(list, weekday);
  }
  return result;
}

UserProfile person({
  List<TrainingSport> sports = const [TrainingSport.run, TrainingSport.strength],
  FitnessGoal goal = FitnessGoal.improveFitness,
  ExperienceLevel level = ExperienceLevel.beginner,
  EventGoal? event,
}) {
  final result = UserProfile(sports: sports, goal: goal, event: event);
  for (final sport in sports) {
    result.setLevel(level, sport);
  }
  return result;
}

Set<String> ids(List<ScheduleHint> hints) => hints.map((hint) => hint.id).toSet();

void main() {
  group('SessionMatcher', () {
    /// Mittwoch, 28.10.2026.
    const today = CalendarDay(2026, 10, 28);
    const monday = CalendarDay(2026, 10, 26);
    GarminActivity activity(int id, String typeKey, CalendarDay day, double minutes) => GarminActivity(id)
      ..typeKey = typeKey
      ..startLocal = '${day.iso} 07:00:00'
      ..durationSeconds = minutes * 60;
    final schedule = plan({
      Weekday.monday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
      Weekday.tuesday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
      Weekday.wednesday: [const SessionSlot(TrainingSport.run)],
      Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
    });

    test('ein Spaziergang hakt keine Intervalle ab', () {
      final planned = SessionMatcher.planned(schedule, monday: monday);
      final week = SessionMatcher.match(
        planned: planned,
        activities: [activity(1, 'walking', monday, 40)],
        today: today,
      );
      expect(week.resultsOn(monday).first.status, SessionStatus.missed);
      expect(week.extraIDs, [1]);
    });

    test('Status der Woche', () {
      final planned = SessionMatcher.planned(
        schedule,
        monday: monday,
        runMinutes: {
          Weekday.saturday: [100],
        },
      );
      expect(planned.last.targetMinutes, 100);
      final activities = [activity(1, 'cycling', monday, 60), activity(2, 'running', today, 20)];
      final week = SessionMatcher.match(
        planned: planned,
        activities: activities,
        gymDays: {monday.adding(1)},
        today: today,
      );
      expect(week.results.map((result) => result.status), [
        SessionStatus.substituted,
        SessionStatus.done,
        SessionStatus.partial,
        SessionStatus.planned,
      ]);
      expect(week.results[2].compareText, 'Soll 45 min · Ist 20 min');
      expect(week.results[0].intensityNote, 'locker statt intensiv');
      expect(week.allCounted(today), isTrue);
      expect(week.allCounted(monday.adding(5)), isFalse);
      final run = SessionMatcher.totals(
        planned: planned,
        activities: activities,
        monday: monday,
      ).firstWhere((total) => total.sport == TrainingSport.run);
      expect(run.planned, 50 + 45 + 100);
      expect(run.actual, 20);
    });

    test('verpasst und nachholen', () {
      final planned = SessionMatcher.planned(schedule, monday: monday);
      final week = SessionMatcher.match(planned: planned, activities: [], today: today);
      final missed = MissedSessions.open(week, handled: {});
      expect(missed.map((result) => result.planned.day), [monday.adding(1), monday]);
      expect(MissedSessions.open(week, handled: {missed[0].id}).length, 1);
      // Im Urlaub gilt nichts als verpasst.
      expect(MissedSessions.open(week, handled: {}, pause: TrainingBreak(monday, monday.adding(1))), isEmpty);
      expect(MissedSessions.open(week, handled: {}, pause: TrainingBreak(monday, monday)).length, 1);
      // Intervalllauf vom Montag nachholen: nicht Fr (vor dem langen Lauf am Sa), sondern Do.
      final session = week.results.first.planned;
      final profile = UserProfile.personalDraft(SeasonConfig());
      expect(
        MissedSessions.makeUpDay(session, schedule: schedule, profile: profile, today: today, makeUpsThisWeek: 0),
        Weekday.thursday,
      );
      expect(
        MissedSessions.makeUpDay(session, schedule: schedule, profile: profile, today: today, makeUpsThisWeek: 1),
        isNull,
      );
    });

    test('Gym an einem anderen Tag zählt für die Kraft-Einheit der Woche', () {
      final planned = SessionMatcher.planned(schedule, monday: monday);
      final week = SessionMatcher.match(planned: planned, activities: [], gymDays: {monday}, today: today);
      expect(week.resultsOn(monday.adding(1)).first.status, SessionStatus.done);
      expect(week.results.where((result) => result.status.counts).length, 1);
    });

    test('Uhr-Aufzeichnung und App-Einheit zählen einmal', () {
      final planned = SessionMatcher.planned(schedule, monday: monday);
      final watch = activity(7, 'strength_training', monday, 50);
      final week = SessionMatcher.match(planned: planned, activities: [watch], gymDays: {monday}, today: today);
      expect(
        week.results
            .where((result) => result.planned.slot.sport == TrainingSport.strength && result.status.counts)
            .length,
        1,
      );
      // Nur Uhr-Aufzeichnung ohne App-Einheit, an einem anderen Tag: zählt ebenfalls.
      final only = SessionMatcher.match(planned: planned, activities: [watch], today: today);
      expect(only.resultsOn(monday.adding(1)).first.status, SessionStatus.done);
      expect(only.resultsOn(monday.adding(1)).first.activityID, 7);
      expect(only.extraIDs, isNot(contains(7)));
    });

    test('zusätzliches Gym ohne offene Kraft-Einheit ändert nichts', () {
      final planned = SessionMatcher.planned(schedule, monday: monday);
      final week = SessionMatcher.match(
        planned: planned,
        activities: [],
        gymDays: {monday, monday.adding(1)},
        today: today,
      );
      expect(week.results.where((result) => result.status.counts).length, 1);
      expect(week.resultsOn(monday).first.status, SessionStatus.missed);
    });

    test('Krankheit begrenzt die Erholung', () {
      final sick = today.adding(-1);
      expect(MissedSessions.cappedRecovery(RecoveryLevel.normal, sickDay: sick, today: today), RecoveryLevel.locker);
      expect(MissedSessions.cappedRecovery(RecoveryLevel.pause, sickDay: sick, today: today), RecoveryLevel.pause);
      expect(
        MissedSessions.cappedRecovery(RecoveryLevel.normal, sickDay: today.adding(-3), today: today),
        RecoveryLevel.normal,
      );
      expect(MissedSessions.cappedRecovery(null, sickDay: sick, today: today), RecoveryLevel.locker);
    });

    test('nachgetragenes Training', () {
      final start = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000);
      final swim = ManualActivity.make(sport: TrainingSport.swim, start: start, minutes: 40, effort: 6);
      expect(ManualActivity.isManual(swim.id), isTrue);
      expect(ActivitySource.of(swim.id), ActivitySource.manual);
      expect(ManualActivity.isManual(-12345), isFalse);
      expect(swim.sport, ActivitySport.swim);
      expect(swim.durationSeconds, 2400);
      expect(swim.trainingLoad, 60);
      expect(swim.name, 'Schwimmen (nachgetragen)');
      expect(swim.day, CalendarDay.fromDate(start.toLocal()));
    });
  });

  group('PlanAdjustments', () {
    const monday = CalendarDay(2026, 10, 26);
    UserProfile runner() => person(level: ExperienceLevel.intermediate)
      ..schedule = plan({
        Weekday.tuesday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.thursday: [const SessionSlot(TrainingSport.run)],
        Weekday.friday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
        Weekday.sunday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
      });

    test('Auslassen gilt nur diese Woche', () {
      final profile = runner();
      final adjustments = PlanAdjustments()..skip(Weekday.tuesday, inWeekOf: monday.adding(1));
      final thisWeek = adjustments.schedule(profile.schedule, inWeekOf: monday.adding(3));
      expect(thisWeek.slots(Weekday.tuesday), isEmpty);
      expect(thisWeek.slots(Weekday.thursday), [const SessionSlot(TrainingSport.run)]);
      expect(adjustments.schedule(profile.schedule, inWeekOf: monday.adding(8)), profile.schedule);
      expect(adjustments.note(Weekday.tuesday, inWeekOf: monday), 'diese Woche ausgelassen');
    });

    test('Verschieben fügt am Zieltag hinzu', () {
      final profile = runner();
      final adjustments = PlanAdjustments()..move(Weekday.tuesday, to: Weekday.wednesday, inWeekOf: monday);
      final week = adjustments.schedule(profile.schedule, inWeekOf: monday);
      expect(week.slots(Weekday.tuesday), isEmpty);
      expect(week.slots(Weekday.wednesday), [const SessionSlot(TrainingSport.run, SessionIntensity.hard)]);
      expect(adjustments.note(Weekday.tuesday, inWeekOf: monday), 'verschoben auf Mittwoch');
      expect(adjustments.note(Weekday.wednesday, inWeekOf: monday), 'von Dienstag verschoben');
      expect(adjustments.note(Weekday.monday, inWeekOf: monday), isNull);
    });

    test('Verschiebungen wirken der Reihe nach', () {
      final profile = runner();
      final adjustments = PlanAdjustments()
        ..move(Weekday.tuesday, to: Weekday.wednesday, inWeekOf: monday)
        ..move(Weekday.wednesday, to: Weekday.saturday, inWeekOf: monday)
        ..move(Weekday.monday, to: Weekday.friday, inWeekOf: monday) // Montag ist frei: nichts passiert
        ..move(Weekday.thursday, to: Weekday.thursday, inWeekOf: monday); // gleicher Tag wird ignoriert
      final week = adjustments.schedule(profile.schedule, inWeekOf: monday);
      expect(week.slots(Weekday.saturday), [const SessionSlot(TrainingSport.run, SessionIntensity.hard)]);
      expect(week.slots(Weekday.friday), [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)]);
      expect(week.sessionCount, profile.schedule.sessionCount);
      expect(adjustments.changes.length, 3);
    });

    test('Rückgängig stellt den Tag wieder her', () {
      final profile = runner();
      final adjustments = PlanAdjustments()
        ..move(Weekday.tuesday, to: Weekday.wednesday, inWeekOf: monday)
        ..skip(Weekday.friday, inWeekOf: monday)
        ..undo(Weekday.wednesday, inWeekOf: monday);
      final week = adjustments.schedule(profile.schedule, inWeekOf: monday);
      expect(week.slots(Weekday.tuesday), [const SessionSlot(TrainingSport.run, SessionIntensity.hard)]);
      expect(week.slots(Weekday.friday), isEmpty);
      expect(adjustments.changes.length, 1);
    });

    test('Zurücksetzen und Aufräumen, JSON hin und zurück', () {
      final adjustments = PlanAdjustments()
        ..skip(Weekday.tuesday, inWeekOf: monday)
        ..skip(Weekday.friday, inWeekOf: monday.adding(7))
        ..reset(weekOf: monday.adding(9));
      expect(adjustments.changes.length, 1);
      adjustments.prune(before: monday.adding(7));
      expect(adjustments.changes, isEmpty);
      adjustments.skip(Weekday.sunday, inWeekOf: monday);
      expect(PlanAdjustments.fromJson(jsonDecode(jsonEncode(adjustments.toJson()))), adjustments);
      // Swift-Format: Wochentag als Zahl, `to` fehlt beim Auslassen; ältere Daten ohne Wochenpläne.
      final swift = PlanAdjustments.fromJson(
        jsonDecode('{"changes":[{"week":{"year":2026,"month":10,"day":26},"from":6}]}'),
      )!;
      expect(swift, adjustments);
    });

    test('Wochenplan für genau eine Woche ersetzt Ausnahmen', () {
      final profile = runner();
      final adjustments = PlanAdjustments()..skip(Weekday.tuesday, inWeekOf: monday);
      final custom = profile.schedule.withSlots([const SessionSlot(TrainingSport.bike)], Weekday.monday);
      adjustments.setWeekPlan(custom, base: profile.schedule, inWeekOf: monday.adding(2));
      expect(adjustments.changes, isEmpty);
      expect(adjustments.schedule(profile.schedule, inWeekOf: monday), custom);
      adjustments.setWeekPlan(profile.schedule, base: profile.schedule, inWeekOf: monday);
      expect(adjustments.weekPlans, isEmpty);
    });

    test('Verschiebe-Vorschläge meiden harte Tage direkt hintereinander', () {
      final profile = runner();
      final options = PlanMoveAdvisor.options(
        Weekday.tuesday,
        schedule: profile.schedule,
        profile: profile,
        today: monday.adding(1),
      );
      expect(options, isNotEmpty);
      expect(options.every((weekday) => weekday.index > Weekday.tuesday.index), isTrue);
      // Samstag liegt direkt vor dem langen Lauf am Sonntag und kommt nicht zuerst.
      expect(options.first, isNot(Weekday.saturday));
      expect(options.first, Weekday.wednesday);
    });

    test('keine Vorschläge am Sonntag oder an freien Tagen', () {
      final profile = runner();
      expect(
        PlanMoveAdvisor.options(Weekday.sunday, schedule: profile.schedule, profile: profile, today: monday.adding(6)),
        isEmpty,
      );
      expect(
        PlanMoveAdvisor.options(Weekday.monday, schedule: profile.schedule, profile: profile, today: monday),
        isEmpty,
      );
    });

    test('Erinnerungen folgen den Ausnahmen', () {
      final profile = runner();
      final adjustments = PlanAdjustments()
        ..skip(Weekday.thursday, inWeekOf: monday)
        ..move(Weekday.friday, to: Weekday.saturday, inWeekOf: monday);
      final reminders = ReminderPlanner.personal(
        profile: profile,
        adjustments: adjustments,
        today: monday,
        includeToday: true,
      );
      // Woche 1: Di, Sa (verschoben), So; Woche 2: Di, Do, Fr, So.
      expect(reminders.map((reminder) => reminder.day), [1, 5, 6, 8, 10, 11, 13].map(monday.adding));
      expect(reminders.first.title, 'Heute: Qualitätslauf (Tempo oder Intervalle)');
      expect(reminders.every((reminder) => reminder.canAdjust), isTrue);
      expect(reminders.first.id, 'coach.reminder.2026-10-27');
    });

    test('heute nur auf Wunsch', () {
      final profile = runner();
      final tuesday = monday.adding(1);
      expect(
        ReminderPlanner.personal(
          profile: profile,
          adjustments: PlanAdjustments(),
          today: tuesday,
          includeToday: true,
          days: 1,
        ).length,
        1,
      );
      expect(
        ReminderPlanner.personal(
          profile: profile,
          adjustments: PlanAdjustments(),
          today: tuesday,
          includeToday: false,
          days: 1,
        ),
        isEmpty,
      );
    });

    test('Text nennt den Begleiter', () {
      const reminder = TrainingReminder(day: monday, titles: ['Lockerer Lauf'], canAdjust: true);
      expect(ReminderPlanner.body(reminder), contains('verschieben'));
      expect(ReminderPlanner.body(reminder, lead: 'Daisy wartet schon.'), startsWith('Daisy wartet'));
      const season = TrainingReminder(day: monday, titles: ['Push'], canAdjust: false);
      expect(ReminderPlanner.body(season), isNot(contains('verschieben')));
    });

    test('sonntags „Nächste Woche planen“', () {
      final notes = ReminderPlanner.weekPlanning(
        mode: ProfileMode.personal,
        today: monday.adding(6),
        minutesNow: 20 * 60,
        hour: 19,
        minute: 0,
      );
      // Heute (So) ist die Uhrzeit vorbei: erst der nächste Sonntag.
      expect(notes.map((note) => note.day), [monday.adding(13)]);
      expect(notes.single.id, 'coach.reminder.weekPlanning.2026-11-08');
      expect(ListFormat.german(['A', 'B', 'C']), 'A, B und C');
    });
  });

  group('TrainingBreak', () {
    const monday = CalendarDay(2026, 11, 9);

    test('Zeitraum geordnet und inklusive', () {
      final pause = TrainingBreak(monday.adding(4), monday.adding(2));
      expect(pause.start, monday.adding(2));
      expect(pause.contains(monday.adding(2)), isTrue);
      expect(pause.contains(monday.adding(4)), isTrue);
      expect(pause.contains(monday.adding(5)), isFalse);
      expect(pause.isOver(monday.adding(4)), isFalse);
      expect(pause.isOver(monday.adding(5)), isTrue);
    });

    test('Wochenplan verliert nur Tage in der Pause', () {
      final week = plan({
        Weekday.tuesday: [const SessionSlot(TrainingSport.run)],
        Weekday.thursday: [const SessionSlot(TrainingSport.strength)],
        Weekday.saturday: [const SessionSlot(TrainingSport.run)],
      });
      final result = TrainingBreak(monday.adding(3), monday.adding(10)).removing(week, monday: monday);
      expect(result.slots(Weekday.tuesday), isNotEmpty);
      expect(result.slots(Weekday.thursday), isEmpty);
      expect(result.slots(Weekday.saturday), isEmpty);
    });
  });

  group('ScheduleCheck', () {
    const monday = CalendarDay(2026, 10, 26);

    test('leerer Plan fragt nach Einheiten', () {
      expect(ids(ScheduleCheck.hints(WeekSchedule(), person())), {'empty'});
    });

    test('verlangt einen Ruhetag', () {
      var all = WeekSchedule();
      for (final weekday in Weekday.values) {
        all = all.withSlots([const SessionSlot(TrainingSport.run)], weekday);
      }
      final hints = ScheduleCheck.hints(all, person());
      expect(hints.first.id, 'rest');
      expect(hints.first.severity, HintSeverity.warning);
      expect(hints.first.isPracticeRule, isTrue);
    });

    test('meldet harte Tage direkt hintereinander', () {
      final hints = ScheduleCheck.hints(
        plan({
          Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
          Weekday.sunday: [const SessionSlot(TrainingSport.bike, SessionIntensity.hard)],
        }),
        person(sports: [TrainingSport.run, TrainingSport.bike], level: ExperienceLevel.advanced),
      );
      final match = hints.firstWhere((hint) => hint.id == 'back-to-back-5');
      expect(match.severity, HintSeverity.warning);
      expect(match.evidenceIDs, ['intensity.distribution']);
      // Auch über die Wochengrenze: Sonntag und Montag.
      final wrap = plan({
        Weekday.sunday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
        Weekday.monday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
      });
      expect(ids(ScheduleCheck.hints(wrap, person(level: ExperienceLevel.advanced))), contains('back-to-back-6'));
    });

    test('warnt vor zu viel Intensität', () {
      final week = plan({
        Weekday.monday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.wednesday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.friday: [const SessionSlot(TrainingSport.bike)],
        Weekday.saturday: [const SessionSlot(TrainingSport.run)],
      });
      final sports = [TrainingSport.run, TrainingSport.bike];
      expect(
        ids(ScheduleCheck.hints(week, person(sports: sports, level: ExperienceLevel.advanced))),
        contains('hard-share'),
      );
      expect(ids(ScheduleCheck.hints(week, person(sports: sports))), contains('beginner-hard'));
    });

    test('zwei Krafttage für Muskelaufbau', () {
      final hints = ScheduleCheck.hints(
        plan({
          Weekday.monday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
          Weekday.thursday: [const SessionSlot(TrainingSport.run)],
        }),
        person(goal: FitnessGoal.buildMuscle),
      );
      expect(hints.firstWhere((hint) => hint.id == 'strength-frequency').evidenceIDs, ['gym.volume']);
      final loss = ScheduleCheck.hints(
        plan({
          Weekday.monday: [const SessionSlot(TrainingSport.run)],
        }),
        person(goal: FitnessGoal.loseWeight),
      );
      expect(loss.firstWhere((hint) => hint.id == 'strength-for-loss').evidenceIDs, ['weightloss.exercise']);
    });

    test('gewählte Sportarten ohne Tag', () {
      final hints = ScheduleCheck.hints(
        plan({
          Weekday.monday: [const SessionSlot(TrainingSport.run)],
        }),
        person(sports: [TrainingSport.run, TrainingSport.swim]),
      );
      expect(ids(hints), contains('missing-swim'));
      expect(ids(hints), isNot(contains('missing-run')));
    });

    test('schwere Beine vor dem langen Lauf', () {
      final before = plan({
        Weekday.friday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
        Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
      });
      expect(
        ids(ScheduleCheck.hints(before, person(level: ExperienceLevel.advanced))),
        contains('strength-before-run-4'),
      );
      final swapped = plan({
        Weekday.friday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
        Weekday.saturday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
      });
      expect(
        ids(ScheduleCheck.hints(swapped, person(level: ExperienceLevel.advanced))),
        isNot(contains('strength-before-run-4')),
      );
    });

    test('Marathon-Anforderungen', () {
      const event = EventGoal(name: 'Marathon', date: monday, kind: EventKind.marathon);
      final hints = ScheduleCheck.hints(
        plan({
          Weekday.tuesday: [const SessionSlot(TrainingSport.run)],
          Weekday.thursday: [const SessionSlot(TrainingSport.run)],
        }),
        person(sports: [TrainingSport.run], event: event),
      );
      expect(ids(hints).containsAll({'event-run-days', 'event-long-run'}), isTrue);
    });

    test('Fitness- und Ruhepuls-Ziele', () {
      final hints = ScheduleCheck.hints(
        plan({
          Weekday.tuesday: [const SessionSlot(TrainingSport.run)],
        }),
        person(sports: [TrainingSport.run]),
      );
      expect(hints.firstWhere((hint) => hint.id == 'endurance-frequency').evidenceIDs, ['rhr.endurance']);
      expect(hints.firstWhere((hint) => hint.id == 'who-minimum').evidenceIDs, ['activity.who']);
    });
  });
}

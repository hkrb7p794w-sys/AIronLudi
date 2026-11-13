// Port der „Jetzt dran“-Fälle aus TrainingTodayTests.swift und AuditR4APlanTests.swift (Planvorschläge folgen mit
// `PlanSuggestion`).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Montag, 26.10.2026.
const monday = CalendarDay(2026, 10, 26);

/// Mittwoch, 28.10.2026.
const today = CalendarDay(2026, 10, 28);

GarminActivity activity(int id, String typeKey, {required CalendarDay day, required double minutes, String? name}) =>
    GarminActivity(id)
      ..typeKey = typeKey
      ..startLocal = '${day.iso} 07:00:00'
      ..durationSeconds = minutes * 60
      ..name = name;

WeekSchedule schedule(Map<Weekday, List<SessionSlot>> plan) {
  var result = WeekSchedule();
  for (final MapEntry(key: weekday, value: slots) in plan.entries) {
    result = result.withSlots(slots, weekday);
  }
  return result;
}

UserProfile person(
  List<TrainingSport> sports,
  Map<TrainingSport, ExperienceLevel> levels,
  WeekSchedule plan, {
  FitnessGoal goal = FitnessGoal.improveFitness,
}) {
  final profile = UserProfile(sports: sports, goal: goal, schedule: plan);
  for (final MapEntry(key: sport, value: level) in levels.entries) {
    profile.setLevel(level, sport);
  }
  return profile;
}

void main() {
  group('Jetzt dran', () {
    test('Fortschrittstext', () {
      const progress = TodayFocusProgress(sessionsDone: 3, sessionsPlanned: 5, minutesDone: 140, minutesPlanned: 210);
      expect(progress.text, '3/5 Einheiten · 140/210 min');
      expect((progress.fraction - 140.0 / 210).abs(), lessThan(0.001));
      expect(
        const TodayFocusProgress(sessionsDone: 2, sessionsPlanned: 4, minutesDone: 90, minutesPlanned: null).text,
        '2/4 Einheiten · 90 min',
      );
    });

    test('Widerspruch zwischen Regel und Plan', () {
      const reasons = ['HRV-Status unausgeglichen, 7-Tage-Schnitt unter deiner Baseline'];
      expect(
        TodayFocus.conflictText(level: RecoveryLevel.locker, reasons: reasons, planned: ['Qualitätslauf']),
        'Regel: locker (HRV-Status unausgeglichen, 7-Tage-Schnitt unter deiner Baseline) · geplant: '
        'Qualitätslauf. Es gilt die Regel.',
      );
      expect(
        TodayFocus.conflictText(level: RecoveryLevel.normal, reasons: reasons, planned: ['Qualitätslauf']),
        isNull,
      );
      expect(TodayFocus.conflictText(level: RecoveryLevel.pause, reasons: [], planned: []), isNull);
      expect(TodayFocus.whyText(['HRV-Status ausgeglichen']), isNull);
    });

    test('eigener Plan zeigt heute mit Soll', () {
      // Di intensiv, Do intensiv, Sa lang.
      final plan = schedule({
        Weekday.tuesday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.thursday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
      });
      final thursday = today.adding(1);
      final planned = SessionMatcher.planned(plan, monday: monday);
      final runs = [activity(1, 'running', day: monday.adding(1), minutes: 50, name: 'Intervalle')];
      final week = SessionMatcher.match(planned: planned, activities: runs, today: thursday);
      const advice = ScheduleAdvice(
        mode: ScheduleAdviceMode.lighter,
        headline: 'Locker statt intensiv',
        detail: '',
        move: null,
        plannedTitles: [],
        evidenceIDs: [],
      );
      final focus = TodayFocus.personal(
        advice: advice,
        recommendation: const Recommendation(level: RecoveryLevel.locker, reasons: ['kurzer Schlaf (5,5 h)']),
        week: week,
        activities: runs,
        today: thursday,
      );
      final item = focus.items.first;
      expect(item.target, 'Soll 50 min · Intensiv');
      expect(item.demanding, isTrue);
      expect(focus.conflict, startsWith('Regel: locker (kurzer Schlaf (5,5 h))'));
      expect(focus.progress.sessionsDone, 1);
      expect(focus.progress.sessionsPlanned, 3);
      expect(focus.progress.minutesDone, 50);
      expect(focus.progress.minutesPlanned, 50 + 50 + 90);
    });

    test('Verschieben bleibt in der Zukunft dieser Woche (R4A)', () {
      final plan = schedule({
        Weekday.saturday: [const SessionSlot(TrainingSport.run, SessionIntensity.long)],
        Weekday.sunday: [const SessionSlot(TrainingSport.run)],
      });
      final profile = person([TrainingSport.run], {TrainingSport.run: ExperienceLevel.intermediate}, plan);
      final saturday = monday.adding(5);
      final advice = ScheduleAdvisor.advice(
        profile: profile,
        day: saturday,
        recovery: RecoveryLevel.pause,
        trainedToday: false,
      );
      // Montag liegt (für diese Woche) in der Vergangenheit.
      expect(advice.move == null || advice.move!.rawValue > Weekday.saturday.rawValue, isTrue);
    });

    test('Krafteinheiten aus der App füllen den Wochenfortschritt (R4A)', () {
      final plan = schedule({
        for (final day in [Weekday.monday, Weekday.wednesday, Weekday.friday])
          day: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
      });
      final profile = person(
        [TrainingSport.strength],
        {TrainingSport.strength: ExperienceLevel.intermediate},
        plan,
        goal: FitnessGoal.buildMuscle,
      );
      final thursday = monday.adding(3);
      final planned = SessionMatcher.planned(plan, monday: monday);
      final week = SessionMatcher.match(
        planned: planned,
        activities: [],
        gymDays: {monday, monday.adding(2)},
        today: thursday,
      );
      final advice = ScheduleAdvisor.advice(profile: profile, day: thursday, recovery: null, trainedToday: false);
      final focus = TodayFocus.personal(
        advice: advice,
        recommendation: null,
        week: week,
        activities: [],
        today: thursday,
      );
      expect(focus.progress.sessionsDone, 2);
      // 2 von 3 Krafteinheiten gemacht – der Balken darf nicht leer sein.
      expect(focus.progress.fraction, greaterThanOrEqualTo(0.5));
    });

    test('Spaziergänge füllen den Wochenfortschritt nicht (R4A)', () {
      final plan = schedule({
        for (final day in [Weekday.monday, Weekday.wednesday, Weekday.friday])
          day: [const SessionSlot(TrainingSport.run)],
      });
      final profile = person([TrainingSport.run], {TrainingSport.run: ExperienceLevel.intermediate}, plan);
      final thursday = monday.adding(3);
      final walks = [
        for (var index = 0; index < 3; index++) activity(20 + index, 'walking', day: monday.adding(index), minutes: 60),
      ];
      final planned = SessionMatcher.planned(plan, monday: monday);
      final week = SessionMatcher.match(planned: planned, activities: walks, today: thursday);
      final advice = ScheduleAdvisor.advice(profile: profile, day: thursday, recovery: null, trainedToday: false);
      final focus = TodayFocus.personal(
        advice: advice,
        recommendation: null,
        week: week,
        activities: walks,
        today: thursday,
      );
      expect(focus.progress.sessionsDone, 0);
      // Kein Lauf gemacht – „Woche geschafft“ (grüner, voller Balken) wäre falsch.
      expect(focus.progress.fraction, lessThan(0.5));
    });
  });
}

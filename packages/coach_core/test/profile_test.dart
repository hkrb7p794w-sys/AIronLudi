// Port von CoachCoreTests/ProfileTests.swift (UserProfileTests, WeekScheduleTests ohne `templateItems`,
// GoalRulesTests ohne `weeklyRateShapesTheDailyTarget`), dazu ScheduleAdvisorTests, SchedulePlannerTests und
// ProfileEvidenceTests; die übrigen Fälle stehen bei NutritionPlanner und ScheduleCheck.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Montag, 26.10.2026.
const monday = CalendarDay(2026, 10, 26);

WeekSchedule schedule(Map<Weekday, List<SessionSlot>> plan) {
  var result = WeekSchedule();
  for (final MapEntry(key: weekday, value: slots) in plan.entries) {
    result = result.withSlots(slots, weekday);
  }
  return result;
}

UserProfile profile({
  List<TrainingSport> sports = const [TrainingSport.run, TrainingSport.strength],
  FitnessGoal goal = FitnessGoal.improveFitness,
  ExperienceLevel level = ExperienceLevel.beginner,
  EventGoal? event,
  List<HealthFlag> health = const [],
}) {
  final result = UserProfile(sports: sports, goal: goal, event: event, health: health);
  for (final sport in sports) {
    result.setLevel(level, sport);
  }
  return result;
}

UserProfile decode(String json) => UserProfile.fromJson(jsonDecode(json));

void main() {
  group('UserProfile', () {
    test('liest alte und unvollständige Daten', () {
      final partial = decode('{"goal":"loseWeight"}');
      expect(partial.goal, FitnessGoal.loseWeight);
      expect(partial.mode, ProfileMode.personal);
      expect(partial.onboardingDone, isFalse);
      expect(partial.schedule.days.length, 7);
      final broken = decode('{"goal":"unbekannt","sports":["x"]}');
      expect(broken.goal, FitnessGoal.improveFitness);
      expect(broken.sports, [TrainingSport.run, TrainingSport.strength]);
    });

    test('hin und zurück bleibt alles erhalten', () {
      final original = profile(
        sports: [TrainingSport.run, TrainingSport.swim],
        goal: FitnessGoal.loseAndBuild,
        level: ExperienceLevel.intermediate,
      );
      original
        ..event = const EventGoal(name: 'Stadtlauf', date: monday, kind: EventKind.run10k, targetSeconds: 3000)
        ..targets = const ImprovementTargets(restingHeartRate: 55, targetWeightKilograms: 62, weeksToTargetWeight: 20)
        ..schedule = schedule({
          Weekday.tuesday: [const SessionSlot(TrainingSport.swim)],
          Weekday.thursday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
        })
        ..health = [HealthFlag.injury];
      final decoded = UserProfile.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(decoded, original);
      expect(decoded.level(TrainingSport.swim), ExperienceLevel.intermediate);
      expect(decoded.enduranceLevel, ExperienceLevel.intermediate);
    });

    test('bisherige Nutzer behalten den Saisonplan', () {
      final existing = ProfileMigration.initialProfile(hasExistingData: true);
      expect(existing.mode, ProfileMode.season);
      expect(existing.onboardingDone, isTrue);
      for (final sport in [TrainingSport.swim, TrainingSport.bike, TrainingSport.run, TrainingSport.strength]) {
        expect(existing.trains(sport), isTrue);
      }
      final fresh = ProfileMigration.initialProfile(hasExistingData: false);
      expect(fresh.mode, ProfileMode.personal);
      expect(fresh.onboardingDone, isFalse);
    });

    test('liest ein Profil im Format der Swift-App', () {
      // So schreibt `JSONEncoder` in Swift ein Profil (Schlüssel aus den Eigenschaften, `nil` entfällt).
      const swift =
          '{"mode":"personal","onboardingDone":true,"sports":["run","strength"],"goal":"loseWeight",'
          '"targets":{"targetWeightKilograms":72,"weeksToTargetWeight":16},"levels":{"run":"intermediate"},'
          '"schedule":[[{"sport":"run","intensity":"easy"}],[],[{"sport":"strength","intensity":"hard"}],[],[],[],[]],'
          '"health":[],"goalHistory":[],"tracker":{"usesTracker":true,"providers":["garmin"]},'
          '"goals":{"primary":"fatLoss","secondary":["strength"],"priorities":["bodyComposition"],'
          '"since":{"year":2026,"month":11,"day":1}}}';
      final decoded = decode(swift);
      expect(decoded.targets.targetWeightKilograms, 72);
      expect(decoded.level(TrainingSport.run), ExperienceLevel.intermediate);
      expect(decoded.schedule.slots(Weekday.wednesday), [
        const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
      ]);
      expect(decoded.goals?.primary, TrainingGoal.fatLoss);
      expect(decoded.tracker.providers, [DataProvider.garmin]);
      expect(decode(jsonEncode(decoded.toJson())), decoded);
    });
  });

  group('WeekSchedule', () {
    test('hat immer sieben Tage', () {
      expect(
        WeekSchedule([
          [const SessionSlot(TrainingSport.run)],
        ]).days.length,
        7,
      );
      final decoded = WeekSchedule.fromJson(jsonDecode('[[{"sport":"run","intensity":"easy"}]]'));
      expect(decoded.days.length, 7);
      expect(decoded.slots(Weekday.monday), [const SessionSlot(TrainingSport.run)]);
      expect(WeekSchedule.fromJson(jsonDecode('{"a":1}')).days.length, 7);
    });

    test('Wochentage passen zu Kalendertagen', () {
      expect(Weekday.of(monday), Weekday.monday);
      expect(Weekday.of(monday.adding(6)), Weekday.sunday);
      expect(Weekday.sunday.next, Weekday.monday);
      expect(Weekday.monday.previous, Weekday.sunday);
      expect(Weekday.friday.adding(-5), Weekday.sunday);
    });

    test('Folgen laufen über das Wochenende', () {
      final wrap = schedule({
        Weekday.saturday: [const SessionSlot(TrainingSport.run)],
        Weekday.sunday: [const SessionSlot(TrainingSport.run)],
        Weekday.monday: [const SessionSlot(TrainingSport.run)],
      });
      expect(wrap.longestStreak, 3);
      var all = WeekSchedule();
      for (final weekday in Weekday.values) {
        all = all.withSlots([const SessionSlot(TrainingSport.run)], weekday);
      }
      expect(all.longestStreak, 7);
      expect(all.restDays, isEmpty);
      expect(WeekSchedule().longestStreak, 0);
    });

    test('findet den nächsten Ruhetag', () {
      final plan = schedule({
        Weekday.monday: [const SessionSlot(TrainingSport.run)],
        Weekday.tuesday: [const SessionSlot(TrainingSport.run)],
        Weekday.wednesday: [const SessionSlot(TrainingSport.run)],
      });
      expect(plan.nextRestDay(Weekday.monday, within: 3), Weekday.thursday);
      expect(plan.nextRestDay(Weekday.monday, within: 2), isNull);
      expect(plan.nextRestDay(Weekday.wednesday, within: 1), Weekday.thursday);
    });

    test('geplanter Tagestyp der Ernährung je Einheit', () {
      expect(const SessionSlot(TrainingSport.run).plannedDayType, DayType.light);
      expect(const SessionSlot(TrainingSport.run, SessionIntensity.long).plannedDayType, DayType.hard);
      expect(const SessionSlot(TrainingSport.strength, SessionIntensity.hard).plannedDayType, DayType.light);
      // Intervalle sind kurz und kein harter Tag für die Ernährung (R2D-01).
      expect(const SessionSlot(TrainingSport.run, SessionIntensity.hard).plannedDayType, DayType.moderate);
      expect(const SessionSlot(TrainingSport.other).plannedDayType, isNull);
    });
  });

  group('GoalRules', () {
    const woman = BodyProfile(weightKilograms: 68, heightCentimeters: 168, age: 32, isFemale: true);

    test('normales Abnehmen mit 0,5 % pro Woche', () {
      final result = GoalRules.assess(profile(goal: FitnessGoal.loseWeight), woman);
      expect(result.nutritionGoal, NutritionGoal.lose);
      expect(result.weeklyChangePercent, -0.5);
      expect(result.blocksWeightChange, isFalse);
      expect(result.evidenceIDs, contains('weightloss.rate'));
    });

    test('begrenzt ehrgeizige Ziele', () {
      final person = profile(goal: FitnessGoal.loseWeight)
        ..targets = const ImprovementTargets(targetWeightKilograms: 58, weeksToTargetWeight: 4);
      final result = GoalRules.assess(person, woman);
      expect(result.weeklyChangePercent, -1.0);
      expect(result.notes.any((note) => note.contains('begrenzt')), isTrue);
      // Mittleres Tempo: 68 → 64 kg in 10 Wochen ≈ 0,59 % pro Woche.
      person.targets = const ImprovementTargets(targetWeightKilograms: 64, weeksToTargetWeight: 10);
      expect((GoalRules.assess(person, woman).weeklyChangePercent! + 0.588).abs(), lessThan(0.01));
    });

    test('sperrt Gewichtsziele für Risikogruppen', () {
      for (final flag in [HealthFlag.pregnantOrPostpartum, HealthFlag.eatingDisorder]) {
        final result = GoalRules.assess(profile(goal: FitnessGoal.loseWeight, health: [flag]), woman);
        expect(result.blocksWeightChange, isTrue);
        expect(result.nutritionGoal, NutritionGoal.maintain);
        expect(result.weeklyChangePercent, isNull);
      }
      const minor = BodyProfile(weightKilograms: 60, heightCentimeters: 170, age: 16, isFemale: true);
      expect(GoalRules.assess(profile(goal: FitnessGoal.loseWeight), minor).blocksWeightChange, isTrue);
      expect(GoalRules.assess(profile(goal: FitnessGoal.buildMuscle), minor).blocksWeightChange, isTrue);
      expect(GoalRules.assess(profile(goal: FitnessGoal.improveFitness), minor).blocksWeightChange, isFalse);
    });

    test('nie Abnehmen unter BMI 18,5', () {
      const thin = BodyProfile(weightKilograms: 50, heightCentimeters: 172, age: 25, isFemale: true);
      expect(GoalRules.bmi(thin), lessThan(18.5));
      final result = GoalRules.assess(profile(goal: FitnessGoal.loseAndBuild), thin);
      expect(result.blocksWeightChange, isTrue);
      expect(result.nutritionGoal, NutritionGoal.maintain);
      // Muskelaufbau bleibt möglich.
      expect(GoalRules.assess(profile(goal: FitnessGoal.buildMuscle), thin).blocksWeightChange, isFalse);
      // Ein Zielgewicht unter BMI 18,5 wird nicht angesteuert.
      final person = profile(goal: FitnessGoal.loseWeight)
        ..targets = const ImprovementTargets(targetWeightKilograms: 50, weeksToTargetWeight: 30);
      final second = GoalRules.assess(person, woman);
      expect(second.weeklyChangePercent, -0.5);
      expect(second.notes.any((note) => note.contains('BMI 18,5')), isTrue);
    });

    test('Muskel- und Zunahme-Ziele', () {
      final recomposition = GoalRules.assess(profile(goal: FitnessGoal.loseAndBuild), woman);
      expect(recomposition.nutritionGoal, NutritionGoal.recomposition);
      expect(recomposition.weeklyChangePercent, -0.25);
      final muscle = GoalRules.assess(profile(goal: FitnessGoal.buildMuscle), woman);
      expect(muscle.nutritionGoal, NutritionGoal.gain);
      expect(muscle.weeklyChangePercent, 0.25);
      expect(GoalRules.assess(profile(goal: FitnessGoal.gainWeight), woman).weeklyChangePercent, 0.5);
      expect(GoalRules.assess(profile(goal: FitnessGoal.maintain), woman).weeklyChangePercent, isNull);
    });

    test('Erkrankungen ergeben einen Hinweis, aber keine Sperre', () {
      final result = GoalRules.assess(profile(goal: FitnessGoal.loseWeight, health: [HealthFlag.injury]), woman);
      expect(result.blocksWeightChange, isFalse);
      expect(result.notes.any((note) => note.contains('Arzt')), isTrue);
    });

    test('Tempo-Helfer', () {
      final loss = GoalRules.weeklyLossPercent(currentKilograms: 80, targetKilograms: 72, weeks: 20);
      expect((loss.percent - 0.5).abs(), lessThan(0.001));
      expect(loss.capped, isFalse);
      expect(GoalRules.weeklyLossPercent(currentKilograms: 80, targetKilograms: 90, weeks: 10).percent, 0.5);
      final gain = GoalRules.weeklyGainPercent(currentKilograms: 60, targetKilograms: 66, weeks: 4);
      expect(gain.percent, 0.5);
      expect(gain.capped, isTrue);
    });

    test('Ausblick zum Ruhepuls', () {
      expect(GoalRules.restingHeartRateOutlook(current: null, target: 55), contains('Sobald Garmin'));
      expect(GoalRules.restingHeartRateOutlook(current: 54, target: 55), contains('bei oder unter'));
      expect(GoalRules.restingHeartRateOutlook(current: 60, target: 55), contains('Realistisch'));
      expect(GoalRules.restingHeartRateOutlook(current: 75, target: 55), contains('ambitioniert'));
    });

    test('überträgt in die Ernährungseinstellungen', () {
      final settings = NutritionSettings();
      GoalRules.apply(GoalRules.assess(profile(goal: FitnessGoal.loseWeight), woman), settings);
      expect(settings.goal, NutritionGoal.lose);
      expect(settings.weeklyWeightChangePercent, -0.5);
    });

    test('liest alte Ernährungseinstellungen', () {
      final settings = NutritionSettings.fromJson(jsonDecode('{"goal":"abnehmen"}'));
      expect(settings.goal, NutritionGoal.lose);
      expect(settings.weeklyWeightChangePercent, isNull);
      expect(settings.weightTargetsWithheld, isFalse);
      expect(settings.lastAppliedWeighInDay, isNull);
      expect(
        NutritionSettings.fromJson(jsonDecode('{"energyAdjustmentKilocalories":-900}')).energyAdjustmentKilocalories,
        -500,
      );
    });
  });

  test('jede Beleg-ID der Wochenplan-Hinweise existiert (everyEvidenceIDExists)', () {
    var all = WeekSchedule();
    for (final weekday in Weekday.values) {
      all = all.withSlots([
        const SessionSlot(TrainingSport.run, SessionIntensity.hard),
        const SessionSlot(TrainingSport.strength),
      ], weekday);
    }
    final hints = ScheduleCheck.hints(all, profile(goal: FitnessGoal.buildMuscle));
    expect(hints, isNotEmpty);
    for (final hint in hints) {
      expect(hint.evidenceIDs.every((id) => Evidence.rulesByID[id] != null), isTrue, reason: hint.id);
    }
  });

  group('Tagesempfehlung aus dem Wochenplan', () {
    final plan = schedule({
      Weekday.monday: [const SessionSlot(TrainingSport.run, SessionIntensity.hard)],
      Weekday.tuesday: [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)],
      Weekday.thursday: [const SessionSlot(TrainingSport.run)],
    });

    ScheduleAdvice advice(RecoveryLevel? level, {CalendarDay day = monday, bool trained = false}) {
      final person = profile(level: ExperienceLevel.advanced)..schedule = plan;
      return ScheduleAdvisor.advice(profile: person, day: day, recovery: level, trainedToday: trained);
    }

    test('folgt dem Plan bei guter Erholung', () {
      final result = advice(RecoveryLevel.normal);
      expect(result.mode, ScheduleAdviceMode.asPlanned);
      expect(result.headline, 'Qualitätslauf (Tempo oder Intervalle)');
      expect(result.detail, contains('Morgen (Dienstag): Krafttraining.'));
    });

    test('verschiebt harte Einheiten bei niedriger Erholung auf den nächsten freien Tag', () {
      final result = advice(RecoveryLevel.pause);
      expect(result.mode, ScheduleAdviceMode.rest);
      expect(result.move, Weekday.wednesday);
      expect(result.detail, contains('Mittwoch'));
      expect(result.evidenceIDs, ['recovery.hrv', 'recovery.subjective']);
    });

    test('macht die Einheit bei mittlerer Erholung lockerer', () {
      final result = advice(RecoveryLevel.locker);
      expect(result.mode, ScheduleAdviceMode.lighter);
      expect(result.move, isNull);
      expect(result.detail, contains('lockerer'));
    });

    test('lockere Einheiten bleiben bei niedriger Erholung locker', () {
      final result = advice(RecoveryLevel.pause, day: monday.adding(3));
      expect(result.mode, ScheduleAdviceMode.rest);
      expect(result.move, isNull);
      expect(result.headline, 'Heute nur ganz locker oder frei');
    });

    test('Ruhetage werden erkannt', () {
      final result = advice(RecoveryLevel.normal, day: monday.adding(2));
      expect(result.mode, ScheduleAdviceMode.restDay);
      expect(result.plannedTitles, isEmpty);
      expect(result.detail, contains('Morgen (Donnerstag): Lockerer Lauf.'));
      expect(advice(RecoveryLevel.pause, day: monday.adding(2)).evidenceIDs, ['recovery.hrv', 'recovery.subjective']);
    });

    test('erkennt erledigtes Training', () {
      expect(advice(RecoveryLevel.normal, trained: true).mode, ScheduleAdviceMode.done);
    });

    test('funktioniert ohne Garmin-Werte', () {
      final result = advice(null);
      expect(result.mode, ScheduleAdviceMode.asPlanned);
      expect(result.detail, contains('noch keine Garmin-Werte'));
    });

    test('ohne freien Tag in der Nähe wird nachgeholt', () {
      var busy = WeekSchedule();
      for (final weekday in Weekday.values) {
        busy = busy.withSlots([const SessionSlot(TrainingSport.run, SessionIntensity.hard)], weekday);
      }
      final person = profile(level: ExperienceLevel.advanced)..schedule = busy;
      final result = ScheduleAdvisor.advice(
        profile: person,
        day: monday,
        recovery: RecoveryLevel.pause,
        trainedToday: false,
      );
      expect(result.move, isNull);
      expect(result.detail, contains('hole'));
    });
  });

  group('Wochenplan-Vorschlag', () {
    const weekdays = [Weekday.monday, Weekday.wednesday, Weekday.friday, Weekday.saturday];
    bool hasWarning(WeekSchedule schedule, UserProfile person) =>
        ScheduleCheck.hints(schedule, person).any((hint) => hint.severity == HintSeverity.warning);

    test('nur verfügbare Tage und keine Warnungen', () {
      final person = profile(sports: [TrainingSport.run, TrainingSport.strength]);
      final result = SchedulePlanner.suggest(profile: person, availableDays: weekdays);
      expect(weekdays.toSet().containsAll(result.trainingDays), isTrue);
      expect(result.sessionCount, 4);
      expect(hasWarning(result, person), isFalse);
      expect(result.count(TrainingSport.run), 3);
      expect(result.count(TrainingSport.strength), 1);
    });

    test('Einsteiger bekommen keine intensiven Läufe', () {
      final result = SchedulePlanner.suggest(
        profile: profile(sports: [TrainingSport.run], goal: FitnessGoal.loseWeight),
        availableDays: weekdays,
      );
      expect(result.days.expand((day) => day).every((slot) => slot.intensity == SessionIntensity.easy), isTrue);
    });

    test('kürzt auf die verfügbaren Tage', () {
      final result = SchedulePlanner.suggest(
        profile: profile(
          sports: [TrainingSport.run, TrainingSport.strength, TrainingSport.swim, TrainingSport.bike],
          level: ExperienceLevel.intermediate,
        ),
        availableDays: [Weekday.tuesday, Weekday.thursday],
      );
      expect(result.sessionCount, 2);
      expect(result.count(TrainingSport.run), 1);
      expect(result.count(TrainingSport.strength), 1);
    });

    test('Muskelaufbau bekommt mehr Krafttage', () {
      UserProfile person() => profile(
        sports: [TrainingSport.run, TrainingSport.strength],
        goal: FitnessGoal.buildMuscle,
        level: ExperienceLevel.intermediate,
      );
      final result = SchedulePlanner.suggest(
        profile: person(),
        availableDays: [Weekday.monday, Weekday.tuesday, Weekday.thursday, Weekday.friday, Weekday.saturday],
      );
      expect(result.count(TrainingSport.strength), 4);
      expect(result.count(TrainingSport.run), 1);
      expect(hasWarning(result, person()), isFalse);
    });

    test('Marathonplan hat einen langen Lauf am Wochenende', () {
      final event = EventGoal(name: 'Marathon', date: monday.adding(120), kind: EventKind.marathon);
      final person = profile(
        sports: [TrainingSport.run, TrainingSport.strength],
        level: ExperienceLevel.intermediate,
        event: event,
      );
      final result = SchedulePlanner.suggest(
        profile: person,
        availableDays: [Weekday.tuesday, Weekday.wednesday, Weekday.thursday, Weekday.saturday, Weekday.sunday],
      );
      final longDays = Weekday.values
          .where((day) => result.slots(day).contains(const SessionSlot(TrainingSport.run, SessionIntensity.long)))
          .toList();
      expect(longDays.length, 1);
      expect(longDays.first == Weekday.saturday || longDays.first == Weekday.sunday, isTrue);
      expect(result.count(TrainingSport.run), 4);
      expect(result.count(TrainingSport.strength), 1);
      expect(hasWarning(result, person), isFalse);
    });

    test('Triathlon behält alle drei Disziplinen', () {
      final event = EventGoal(name: 'Sprint', date: monday.adding(90), kind: EventKind.triathlon);
      final person = profile(
        sports: [TrainingSport.swim, TrainingSport.bike, TrainingSport.run, TrainingSport.strength],
        level: ExperienceLevel.intermediate,
        event: event,
      );
      final result = SchedulePlanner.suggest(profile: person, availableDays: Weekday.values);
      for (final sport in [TrainingSport.swim, TrainingSport.bike, TrainingSport.run]) {
        expect(result.count(sport), 2);
      }
      // Auch bei sieben freien Tagen bleibt ein Ruhetag.
      expect(result.restDays.length, 1);
      expect(result.sessionCount, SchedulePlanner.maxSessionsPerWeek);
    });

    test('leere Eingaben', () {
      expect(
        SchedulePlanner.suggest(
          profile: profile(sports: []),
          availableDays: weekdays,
        ).isEmpty,
        isTrue,
      );
      expect(SchedulePlanner.suggest(profile: profile(), availableDays: []).isEmpty, isTrue);
    });

    test('ist deterministisch', () {
      final person = profile(
        sports: [TrainingSport.run, TrainingSport.strength, TrainingSport.bike],
        goal: FitnessGoal.loseWeight,
        level: ExperienceLevel.intermediate,
      );
      final first = SchedulePlanner.suggest(profile: person, availableDays: Weekday.values);
      final second = SchedulePlanner.suggest(profile: person, availableDays: Weekday.values.reversed.toList());
      expect(first, second);
    });

    test('neue Regeln zeigen auf geprüfte Studien', () {
      const ids = [
        'activity.who',
        'weightloss.rate',
        'weightloss.exercise',
        'weightloss.protein',
        'weightloss.sleep',
        'gain.surplus',
        'run.progression',
        'run.minimum',
        'rhr.endurance',
        'fitness.hiit',
        'plan.deload',
        'cycle.individual',
      ];
      for (final id in ids) {
        final rule = Evidence.rulesByID[id];
        expect(rule, isNotNull, reason: '$id fehlt');
        expect(rule!.studies.length, rule.studyIDs.length);
      }
      expect(Evidence.rulesByID['run.progression']?.strength, EvidenceStrength.practice);
    });
  });
}

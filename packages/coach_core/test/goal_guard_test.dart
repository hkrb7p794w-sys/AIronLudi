// Port der Fälle aus CoachCoreTests/GoalGuardTests.swift, die ohne NutritionPlanner auskommen; die Fälle zu den
// Tageszielen folgen mit dem Ernährungsmodul.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const day = CalendarDay(2026, 11, 3);

WeightEntry weighIn(int offset, double kilograms) =>
    WeightEntry(day: day.adding(offset), kilograms: kilograms, source: WeightSource.manual);

void main() {
  const reached = BodyProfile(weightKilograms: 69, heightCentimeters: 175, age: 35, isFemale: false);

  test('Übernehmen löscht die Anpassung, wenn gesperrt', () {
    final value = NutritionSettings()..energyAdjustmentKilocalories = -500;
    final pregnant = UserProfile(goal: FitnessGoal.loseWeight)..health = [HealthFlag.pregnantOrPostpartum];
    const body = BodyProfile(weightKilograms: 70, heightCentimeters: 170, age: 30, isFemale: true);
    GoalRules.apply(GoalRules.assess(pregnant, body), value);
    expect(value.energyAdjustmentKilocalories, 0);
    expect(value.weightTargetsWithheld, isTrue);

    final thin = NutritionSettings()..energyAdjustmentKilocalories = -500;
    const lowBMI = BodyProfile(weightKilograms: 50, heightCentimeters: 175, age: 30, isFemale: true);
    GoalRules.apply(GoalRules.assess(UserProfile(goal: FitnessGoal.loseWeight), lowBMI), thin);
    expect(thin.energyAdjustmentKilocalories, 0);
    expect(thin.weightTargetsWithheld, isFalse);
  });

  test('Schutzstufe nach Körperwerten', () {
    final settings = NutritionSettings();
    const adult = BodyProfile(weightKilograms: 70, heightCentimeters: 175, age: 30, isFemale: false);
    const minor = BodyProfile(weightKilograms: 70, heightCentimeters: 175, age: 16, isFemale: false);
    const underweight = BodyProfile(weightKilograms: 50, heightCentimeters: 175, age: 30, isFemale: false);
    expect(GoalRules.weightGuard(settings, adult), WeightGoalGuard.free);
    expect(GoalRules.weightGuard(settings, minor), WeightGoalGuard.noDeficit);
    expect(GoalRules.weightGuard(settings, underweight), WeightGoalGuard.noDeficit);
    expect(GoalRules.weightGuard(settings..weightTargetsWithheld = true, adult), WeightGoalGuard.noTargets);
  });

  test('Referenzgewicht erst ab Adipositas', () {
    const heavy = BodyProfile(weightKilograms: 120, heightCentimeters: 180, age: 40, isFemale: false);
    expect((GoalRules.referenceWeightKilograms(heavy) - 81).abs(), lessThan(0.01));
    const normal = BodyProfile(weightKilograms: 90, heightCentimeters: 180, age: 40, isFemale: false);
    expect(GoalRules.referenceWeightKilograms(normal), 90);
    expect(GoalRules.estimatedBodyFatPercent(normal), 15);
    expect(GoalRules.estimatedBodyFatPercent(heavy), greaterThan(15));
  });

  test('erreichtes Abnehmziel hält das Gewicht', () {
    final person = UserProfile(goal: FitnessGoal.loseWeight)
      ..targets = const ImprovementTargets(targetWeightKilograms: 70, weeksToTargetWeight: 10);
    final result = GoalRules.assess(person, reached);
    expect(result.weeklyChangePercent, isNull);
    expect(result.nutritionGoal, NutritionGoal.maintain);
    expect(result.blocksWeightChange, isFalse);
  });

  test('erreichtes Zunahmeziel hält das Gewicht', () {
    final person = UserProfile(goal: FitnessGoal.buildMuscle)
      ..targets = const ImprovementTargets(targetWeightKilograms: 68, weeksToTargetWeight: 10);
    expect(GoalRules.assess(person, reached).weeklyChangePercent, isNull);
  });

  test('neueste Wägung wird einmal zum aktuellen Gewicht', () {
    final value = NutritionSettings()..weightKilograms = 80;
    var changed = GoalRules.updateWeight(value, [weighIn(-3, 78.26), weighIn(-1, 77.94)], today: day);
    expect(changed, isTrue);
    expect(value.weightKilograms, 77.9);
    // Eine Eingabe in den Einstellungen bleibt, bis eine neuere Wägung kommt.
    value.weightKilograms = 75;
    changed = GoalRules.updateWeight(value, [weighIn(-3, 78.26), weighIn(-1, 77.94)], today: day);
    expect(changed, isFalse);
    expect(value.weightKilograms, 75);
    changed = GoalRules.updateWeight(value, [weighIn(0, 74.5)], today: day);
    expect(changed, isTrue);
    expect(value.weightKilograms, 74.5);
  });

  test('alte Wägungen ändern das Gewicht nicht', () {
    final value = NutritionSettings()..weightKilograms = 80;
    expect(GoalRules.updateWeight(value, [weighIn(-40, 70)], today: day), isFalse);
    expect(value.weightKilograms, 80);
  });

  test('Halten ändert sich nur beim Wechsel', () {
    final running = NutritionSettings()..weeklyWeightChangePercent = -0.5;
    const loss = GoalAssessment(
      nutritionGoal: NutritionGoal.lose,
      weeklyChangePercent: -0.3,
      notes: [],
      evidenceIDs: [],
      blocksWeightChange: false,
    );
    const hold = GoalAssessment(
      nutritionGoal: NutritionGoal.maintain,
      weeklyChangePercent: null,
      notes: [],
      evidenceIDs: [],
      blocksWeightChange: true,
    );
    expect(GoalRules.holdChanged(loss, running), isFalse);
    expect(GoalRules.holdChanged(hold, running), isTrue);
    expect(GoalRules.holdChanged(loss, NutritionSettings()), isTrue);
    expect(GoalRules.holdChanged(hold, NutritionSettings()), isFalse);
  });

  test('Coaching-Profil ohne gesperrtes Gewichtsziel', () {
    final person =
        UserProfile(
            mode: ProfileMode.personal,
            onboardingDone: true,
            sports: const [TrainingSport.run],
            goal: FitnessGoal.loseWeight,
          )
          ..goals = PersonalGoals(
            primary: TrainingGoal.fatLoss,
            secondary: const [TrainingGoal.health, TrainingGoal.fatLoss],
            since: day,
          );
    final nutrition = NutritionSettings()..weightTargetsWithheld = true;
    final safe = GoalRules.coachingProfile(person, nutrition);
    expect(safe.goal, FitnessGoal.maintain);
    expect(safe.goals?.primary, TrainingGoal.health);
    expect(safe.goals?.secondary, isEmpty);
    expect(Personalization.contextLines(safe.effectiveGoals(day)).join(' '), isNot(contains('Defizit')));
    // Das Original bleibt unverändert.
    expect(person.goal, FitnessGoal.loseWeight);
  });

  test('Coaching-Profil behält ein aktives Gewichtsziel', () {
    final person = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run],
      goal: FitnessGoal.loseWeight,
    );
    final nutrition = NutritionSettings()
      ..goal = NutritionGoal.lose
      ..weeklyWeightChangePercent = -0.5;
    expect(GoalRules.coachingProfile(person, nutrition).goal, FitnessGoal.loseWeight);
  });

  test('Gewichtsquellen: eigene Eingabe vor Garmin vor Health, unplausible Werte fallen weg', () {
    final merged = WeightTrend.merged([
      WeightEntry(day: day, kilograms: 80, source: WeightSource.health),
      WeightEntry(day: day, kilograms: 79, source: WeightSource.manual),
      WeightEntry(day: day, kilograms: 78, source: WeightSource.garmin),
      WeightEntry(day: day.adding(-1), kilograms: 400, source: WeightSource.manual),
    ]);
    expect(merged, [WeightEntry(day: day, kilograms: 79, source: WeightSource.manual)]);
  });
}

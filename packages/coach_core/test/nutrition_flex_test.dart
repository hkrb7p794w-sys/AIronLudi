// Ernährung: Tagesanpassungen (Refeed, Ruhetag, eigene kcal), eigene Makros, realistische Hochrechnung (neu in
// AIronLudi, Rückmeldung vom 17.11.2026).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

final today = CalendarDay(2026, 11, 17);

NutritionSettings settings({NutritionGoal goal = NutritionGoal.lose}) => NutritionSettings()
  ..goal = goal
  ..weightKilograms = 80
  ..heightCentimeters = 180
  ..age = 30
  ..isFemale = false
  ..bodyFatPercent = 18;

NutritionTargets targets(NutritionSettings settings, {List<TemplateItem> plan = const []}) => NutritionPlanner.compute(
  activities: const [],
  planItems: plan,
  settings: settings,
  garminProfile: null,
  day: today,
  hasGarminData: false,
);

void main() {
  group('Tagesanpassungen', () {
    test('Refeed: kein Defizit an diesem Tag, das Plus kommt als Kohlenhydrate', () {
      final base = targets(settings());
      final refeedSettings = settings()..setAdjustment(const DayAdjustment(kind: DayAdjustmentKind.refeed), day: today);
      final refeed = targets(refeedSettings);
      expect(refeed.values[Nutrient.kcal]!, greaterThan(base.values[Nutrient.kcal]!));
      expect(refeed.values[Nutrient.carbs]!, greaterThan(base.values[Nutrient.carbs]!));
      expect(refeed.values[Nutrient.protein], base.values[Nutrient.protein]);
      // Anderer Tag unverändert.
      expect(refeedSettings.adjustmentOn(today.adding(1)), isNull);
    });

    test('Eigene Anpassung: ±500 kcal, Schutzgrenzen bleiben', () {
      final plus = settings(goal: NutritionGoal.maintain)
        ..setAdjustment(const DayAdjustment(kind: DayAdjustmentKind.custom, kilocalories: 300), day: today);
      final base = targets(settings(goal: NutritionGoal.maintain)).values[Nutrient.kcal]!;
      expect(targets(plus).values[Nutrient.kcal]!, closeTo(base + 300, 5));
      final minus = settings()
        ..setAdjustment(const DayAdjustment(kind: DayAdjustmentKind.custom, kilocalories: -500), day: today);
      final lowered = targets(minus);
      // Höchstens ein Viertel Defizit bzw. Energieverfügbarkeit: nicht unter 75 % des Bedarfs.
      final need = NutritionPlanner.mifflinStJeor(lowered.profile) * 1.4;
      expect(lowered.values[Nutrient.kcal]!, greaterThanOrEqualTo(0.75 * need - 5));
      final json = DayAdjustment.fromJson({'kind': 'eigene', 'kcal': 900})!;
      expect(json.kilocalories, 500);
    });

    test('Ruhetag: geplante Einheit zählt nicht', () {
      final plan = [TemplateItem(kind: TemplateItemKind.run, text: 'Lauf', minutes: 60, plannedType: DayType.moderate)];
      final trained = targets(settings(goal: NutritionGoal.maintain), plan: plan);
      final rest = targets(
        settings(goal: NutritionGoal.maintain)
          ..setAdjustment(const DayAdjustment(kind: DayAdjustmentKind.rest), day: today),
        plan: plan,
      );
      expect(rest.dayType, DayType.restDay);
      expect(rest.values[Nutrient.kcal]!, lessThan(trained.values[Nutrient.kcal]!));
    });

    test('Eigene Makros: Protein je kg und Fettanteil, JSON und Aufräumen alter Tage', () {
      final custom = settings(goal: NutritionGoal.maintain)
        ..proteinPerKilogram = 1.6
        ..fatSharePercent = 30;
      final result = targets(custom);
      expect(result.proteinPerKilogram, 1.6);
      final kcal = result.values[Nutrient.kcal]!;
      expect(result.values[Nutrient.fat]! * 9 / kcal, greaterThanOrEqualTo(0.29));
      final copy = NutritionSettings.fromJson({...custom.toJson(), 'proteinPerKilogram': 5, 'fatSharePercent': 10});
      expect(copy.proteinPerKilogram, 2.4);
      expect(copy.fatSharePercent, 20);

      final days = settings()
        ..setAdjustment(const DayAdjustment(kind: DayAdjustmentKind.rest), day: today.adding(-20))
        ..setAdjustment(const DayAdjustment(kind: DayAdjustmentKind.refeed), day: today);
      expect(days.dayAdjustments.keys, [today.iso]);
      final restored = NutritionSettings.fromJson(days.toJson());
      expect(restored.adjustmentOn(today)?.kind, DayAdjustmentKind.refeed);
      days.setAdjustment(null, day: today);
      expect(days.dayAdjustments, isEmpty);
    });
  });

  group('Hochrechnung aus dem Gegessenen', () {
    Map<CalendarDay, double> days(List<double> values) => {
      for (var index = 0; index < values.length; index++) today.adding(-1 - index): values[index],
    };

    test('Großes Defizit: begrenzt auf 1 % Körpergewicht pro Woche statt 5 kg im Monat', () {
      // 1.300 kcal Defizit pro Tag: rechnerisch 1,18 kg pro Woche, ~4,7 kg in 4 Wochen.
      final result = IntakeForecast.compute(
        intake: days(List.filled(10, 1200)),
        maintenance: 2500,
        weightKilograms: 80,
        today: today,
      )!;
      expect(result.rawWeeklyKilograms, closeTo(-1.18, 0.01));
      expect(result.weeklyKilograms, -0.8);
      expect(result.capped, isTrue);
      expect(result.horizonKilograms, -3.2);
      expect(IntakeForecast.sentence(result), contains('etwa 3,2 kg weniger'));
    });

    test('Ausreißer glätten, unvollständige Tage weglassen, zu wenig Tage = keine Aussage', () {
      final smooth = IntakeForecast.compute(
        intake: days([2400, 2500, 2450, 6000, 2550, 300]),
        maintenance: 2500,
        weightKilograms: 80,
        today: today,
      )!;
      expect(smooth.days, 5); // 300 kcal = unvollständig
      expect(smooth.averageIntake, lessThan(2800)); // 6.000 auf +40 % begrenzt
      expect(smooth.capped, isFalse);
      expect(IntakeForecast.sentence(smooth), contains('mehr realistisch'));
      expect(
        IntakeForecast.compute(intake: days([2000, 2100, 2200]), maintenance: 2500, weightKilograms: 80, today: today),
        isNull,
      );
      final steady = IntakeForecast.compute(
        intake: days([2500, 2480, 2520, 2500]),
        maintenance: 2500,
        weightKilograms: 80,
        today: today,
      )!;
      expect(IntakeForecast.sentence(steady), contains('etwa gleich'));
      final gain = IntakeForecast.compute(
        intake: days(List.filled(7, 4000)),
        maintenance: 2500,
        weightKilograms: 80,
        today: today,
      )!;
      expect(gain.weeklyKilograms, 0.4);
    });
  });
}

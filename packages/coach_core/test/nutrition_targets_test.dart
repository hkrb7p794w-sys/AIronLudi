// Port von CoachCoreTests/NutritionTests.swift (vollständig) und den Tagesziel-Fällen aus GoalGuardTests.swift,
// ProfileTests.swift (`mapsToNutritionDayTypes`, `weeklyRateShapesTheDailyTarget`).
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const day = CalendarDay(2026, 10, 23);

GarminActivity activity(
  String typeKey, {
  required double minutes,
  double kcal = 0,
  double? load,
  CalendarDay on = day,
}) => GarminActivity((minutes * 100).round())
  ..typeKey = typeKey
  ..durationSeconds = minutes * 60
  ..calories = kcal
  ..trainingLoad = load
  ..startLocal = '${on.iso} 07:00:00';

NutritionSettings settings({
  double weight = 80,
  double height = 180,
  int age = 36,
  bool female = false,
  NutritionGoal goal = NutritionGoal.maintain,
}) => NutritionSettings()
  ..weightKilograms = weight
  ..heightCentimeters = height
  ..age = age
  ..isFemale = female
  ..goal = goal;

NutritionTargets targets(
  NutritionSettings settings, {
  List<GarminActivity> activities = const [],
  List<TemplateItem> planItems = const [],
  CalendarDay on = day,
  bool hasGarminData = true,
}) => NutritionPlanner.compute(
  activities: activities,
  planItems: planItems,
  settings: settings,
  garminProfile: null,
  day: on,
  hasGarminData: hasGarminData,
);

double kcal(NutritionTargets targets) => targets.values[Nutrient.kcal] ?? 0;

void main() {
  setUpAll(() => BLS.load(File('assets/bls.tsv').readAsStringSync()));

  group('Tagesziele (NutritionTargetTests)', () {
    test('Tagestyp nach Ausdauer, Kraft und Belastung', () {
      expect(NutritionPlanner.classify([]).type, DayType.restDay);
      expect(NutritionPlanner.classify([activity('strength_training', minutes: 45)]).type, DayType.light);
      expect(NutritionPlanner.classify([activity('running', minutes: 50)]).type, DayType.moderate);
      expect(NutritionPlanner.classify([activity('strength_training', minutes: 80)]).type, DayType.moderate);
      expect(NutritionPlanner.classify([activity('virtual_ride', minutes: 95)]).type, DayType.hard);
      expect(NutritionPlanner.classify([activity('running', minutes: 30, load: 160)]).type, DayType.hard);
      expect(NutritionPlanner.classify([activity('cycling', minutes: 250)]).type, DayType.veryHard);
      expect(NutritionPlanner.classify([activity('walking', minutes: 120)]).type, DayType.restDay);
    });

    test('geplanter Tagestyp aus der Musterwoche', () {
      expect(
        NutritionPlanner.plannedDayType([TemplateItem(kind: TemplateItemKind.strength, text: 'Push (Home-Gym)')]),
        DayType.light,
      );
      expect(
        NutritionPlanner.plannedDayType([
          TemplateItem(kind: TemplateItemKind.bike, text: 'Zwift-Einheit (Sa oder So)'),
        ]),
        DayType.moderate,
      );
      expect(
        NutritionPlanner.plannedDayType([
          TemplateItem(kind: TemplateItemKind.bike, text: 'Lange Radeinheit + Koppellauf'),
        ]),
        DayType.hard,
      );
      expect(NutritionPlanner.plannedDayType([TemplateItem(kind: TemplateItemKind.optional, text: 'locker')]), isNull);
    });

    test('berechnet Ziele wie das Add-on', () {
      final result = targets(settings(), activities: [activity('running', minutes: 60, kcal: 700, load: 90)]);
      expect(result.dayType, DayType.moderate);
      expect(result.source, TargetsSource.garmin);
      expect(result.basalMetabolicRate, 1750);
      expect(result.exerciseKilocalories, 627);
      final energy = kcal(result);
      final carbs = result.values[Nutrient.carbs]!;
      final fat = result.values[Nutrient.fat]!;
      expect((energy - 3077).abs(), lessThanOrEqualTo(2));
      expect(result.values[Nutrient.protein], 144);
      expect(carbs, inInclusiveRange(400, 480));
      expect(9 * fat / energy, greaterThanOrEqualTo(0.195));
      expect((4 * 144 + 4 * carbs + 9 * fat - energy).abs(), lessThanOrEqualTo(10));
      expect(result.values[Nutrient.water], 3400);
      expect(result.values[Nutrient.iron], 11);
      expect(result.values[Nutrient.iodine], 150);
    });

    test('geplanter harter Tag hebt die Kohlenhydrate vor dem Training', () {
      final result = targets(
        settings(),
        planItems: [TemplateItem(kind: TemplateItemKind.bike, text: 'Lange Radeinheit + Koppellauf (Sa oder So)')],
      );
      expect(result.dayType, DayType.hard);
      expect(result.source, TargetsSource.planned);
      // Geplante 90 Minuten Ausdauer (MET 7) fließen in die Energie ein; Kohlenhydrate mindestens 6 g/kg.
      expect(result.exerciseKilocalories, 720);
      expect(result.values[Nutrient.carbs]!, greaterThanOrEqualTo(480));
      expect(9 * result.values[Nutrient.fat]! / kcal(result), greaterThanOrEqualTo(0.195));
    });

    test('kein Defizit an harten Tagen, Untergrenze', () {
      final losing = settings(goal: NutritionGoal.lose);
      final rest = targets(losing);
      final maintain = targets(settings());
      expect(kcal(rest), lessThan(kcal(maintain)));
      expect(rest.proteinPerKilogram, 2.2);
      final hard = [activity('running', minutes: 100, kcal: 1100)];
      // Kein Defizit an harten Tagen; Unterschied nur durch das höhere Protein.
      expect(
        (kcal(targets(losing, activities: hard)) - kcal(targets(settings(), activities: hard))).abs(),
        lessThan(200),
      );
    });

    test('Körperwerte: Einstellungen, dann Garmin, dann Standard', () {
      final garmin = GarminProfile()
        ..weightKilograms = 70
        ..gender = 'FEMALE';
      final profile = NutritionSettings().profile(garmin, on: day);
      expect(profile.weightKilograms, 70);
      expect(profile.isFemale, isTrue);
      expect(profile.heightCentimeters, 180);
      expect(NutritionSettings().profile(null, on: day), BodyProfile.fallback);
    });

    test('Wochenplan ergibt den Tagestyp der Ernährung', () {
      var plan = WeekSchedule();
      plan = plan
          .withSlots([const SessionSlot(TrainingSport.run)], Weekday.monday)
          .withSlots([const SessionSlot(TrainingSport.run, SessionIntensity.long)], Weekday.tuesday)
          .withSlots([const SessionSlot(TrainingSport.strength, SessionIntensity.hard)], Weekday.wednesday)
          .withSlots([const SessionSlot(TrainingSport.run, SessionIntensity.hard)], Weekday.thursday)
          .withSlots([const SessionSlot(TrainingSport.other)], Weekday.friday);
      DayType? planned(Weekday weekday) => NutritionPlanner.plannedDayType(plan.templateItems(weekday));
      expect(planned(Weekday.monday), DayType.light);
      expect(planned(Weekday.tuesday), DayType.hard);
      expect(planned(Weekday.wednesday), DayType.light);
      // Intervalle sind kurz und kein harter Tag für die Ernährung (R2D-01).
      expect(planned(Weekday.thursday), DayType.moderate);
      expect(planned(Weekday.friday), isNull);
      expect(planned(Weekday.saturday), isNull);
      // Laufminuten aus dem Laufplan ersetzen die Standarddauer der Reihe nach.
      final runs = WeekSchedule().withSlots([
        const SessionSlot(TrainingSport.run),
        const SessionSlot(TrainingSport.strength),
        const SessionSlot(TrainingSport.run),
      ], Weekday.monday);
      expect(runs.templateItems(Weekday.monday, runMinutes: [30]).map((item) => item.minutes), [30, 45, 45]);
    });

    test('Wochentempo formt das Tagesziel', () {
      const monday = CalendarDay(2026, 10, 26);
      double value(NutritionGoal goal, double? rate) => kcal(
        targets(
          settings(weight: 68, height: 168, age: 32, female: true, goal: goal)..weeklyWeightChangePercent = rate,
          on: monday,
          hasGarminData: false,
        ),
      );
      final maintain = value(NutritionGoal.maintain, null);
      expect(value(NutritionGoal.lose, -0.5), lessThan(maintain));
      expect(value(NutritionGoal.lose, -0.25), greaterThan(value(NutritionGoal.lose, -0.5)));
      expect(value(NutritionGoal.gain, 0.25), greaterThan(maintain));
      // Extreme Wünsche werden auf höchstens 25 % Defizit begrenzt.
      expect(value(NutritionGoal.lose, -1.0), value(NutritionGoal.lose, -5.0));
      // Ohne Wochentempo bleibt das Verhalten wie zuvor.
      expect(value(NutritionGoal.lose, null), lessThan(maintain));
    });
  });

  group('Schutzgrenzen in den Tageszielen (GoalGuardTests)', () {
    const guardDay = CalendarDay(2026, 11, 3);
    NutritionTargets guarded(NutritionSettings value, {List<GarminActivity> activities = const []}) =>
        targets(value, activities: activities, on: guardDay);
    GarminActivity hardRun() => GarminActivity(1)
      ..typeKey = 'running'
      ..durationSeconds = 100 * 60
      ..calories = 1100
      ..startLocal = '${guardDay.iso} 07:00:00';

    test('Untergrenze greift bei negativer Anpassung', () {
      final value = settings(weight: 55, height: 170, age: 30)
        ..activityFactor = 1.2
        ..bodyFatPercent = 12
        ..energyAdjustmentKilocalories = -500;
      final result = guarded(value);
      expect(result.energyAvailabilityFloorApplied, isTrue);
      expect(kcal(result), greaterThanOrEqualTo(1452));
    });

    test('Untergrenze greift am harten Tag', () {
      final value = settings(weight: 55, height: 170, age: 30, goal: NutritionGoal.lose)
        ..activityFactor = 1.2
        ..bodyFatPercent = 12
        ..energyAdjustmentKilocalories = -500;
      final result = guarded(value, activities: [hardRun()]);
      expect(result.dayType, DayType.hard);
      expect(result.energyAvailabilityFloorApplied, isTrue);
      expect(kcal(result), greaterThanOrEqualTo(2450));
    });

    test('Defizit höchstens ein Viertel, auch mit Anpassung', () {
      final value = settings(weight: 90, height: 180, age: 35, goal: NutritionGoal.lose)
        ..weeklyWeightChangePercent = -1;
      final plain = guarded(value);
      value.energyAdjustmentKilocalories = -500;
      final adjusted = guarded(value);
      final need = kcal(guarded(settings(weight: 90, height: 180, age: 35)));
      expect(kcal(plain), greaterThanOrEqualTo(0.75 * need - 1));
      expect(kcal(adjusted), greaterThanOrEqualTo(0.75 * need - 1));
    });

    test('Abnehmen bleibt bei schweren Personen unter dem Erhaltungsbedarf', () {
      final maintain = guarded(settings(weight: 150, height: 180, age: 40));
      final lose = guarded(
        settings(weight: 150, height: 180, age: 40, goal: NutritionGoal.lose)..weeklyWeightChangePercent = -0.5,
      );
      expect(kcal(lose), lessThan(kcal(maintain)));
      expect(lose.energyAvailabilityFloorApplied, isFalse);
    });

    test('Protein ab Adipositas über das Referenzgewicht', () {
      final heavy = guarded(settings(weight: 120, height: 180, age: 40, goal: NutritionGoal.lose));
      expect((heavy.referenceWeightKilograms - 81).abs(), lessThan(0.01));
      expect((heavy.values[Nutrient.protein]! - (2.2 * 81).roundToDouble()).abs(), lessThanOrEqualTo(1));
      expect(
        guarded(settings(weight: 90, height: 180, age: 40, goal: NutritionGoal.lose)).referenceWeightKilograms,
        90,
      );
    });

    test('Mindestmengen übersteigen im Defizit nicht den Bedarf', () {
      final losing = settings(weight: 50, height: 155, age: 70, female: true, goal: NutritionGoal.lose)
        ..activityFactor = 1.2
        ..weeklyWeightChangePercent = -0.5;
      final need = NutritionPlanner.mifflinStJeor(guarded(losing).profile) * 1.2;
      expect(kcal(guarded(losing)), lessThanOrEqualTo(need + 1));
    });

    test('kein Defizit unter BMI 18,5', () {
      final maintain = guarded(settings(weight: 50, height: 170, age: 30));
      final losing = settings(weight: 50, height: 170, age: 30, goal: NutritionGoal.lose)
        ..weeklyWeightChangePercent = -0.5;
      expect(GoalRules.weightGuard(losing, guarded(losing).profile), WeightGoalGuard.noDeficit);
      expect(kcal(guarded(losing)), greaterThanOrEqualTo(kcal(maintain) - 1));
    });

    test('Minderjährige ohne Defizit und Überschuss', () {
      final maintain = guarded(settings(weight: 70, height: 175, age: 16));
      final losing = settings(weight: 70, height: 175, age: 16, goal: NutritionGoal.lose)
        ..weeklyWeightChangePercent = -0.5
        ..energyAdjustmentKilocalories = -300;
      expect(kcal(guarded(losing)), kcal(maintain));
      final gaining = settings(weight: 70, height: 175, age: 16, goal: NutritionGoal.gain)
        ..weeklyWeightChangePercent = 0.25;
      expect(kcal(guarded(gaining)), kcal(maintain));
    });

    test('gesperrte Ziele ignorieren Ziel und Anpassung', () {
      final maintain = guarded(settings(weight: 70, height: 170, age: 30, female: true));
      final value = settings(weight: 70, height: 170, age: 30, female: true, goal: NutritionGoal.lose)
        ..weeklyWeightChangePercent = -0.5
        ..energyAdjustmentKilocalories = -500
        ..weightTargetsWithheld = true;
      expect(kcal(guarded(value)), kcal(maintain));
    });

    test('Jugendliche bekommen mehr Calcium', () {
      expect(guarded(settings(weight: 60, height: 170, age: 16, female: true)).values[Nutrient.calcium], 1200);
      expect(guarded(settings(weight: 60, height: 170, age: 30, female: true)).values[Nutrient.calcium], 1000);
    });

    test('doppeltes Krafttraining zählt einmal', () {
      final export = GarminActivity(10)
        ..typeKey = 'strength_training'
        ..durationSeconds = 3600
        ..calories = 400
        ..startLocal = '${guardDay.iso} 18:00:00';
      final watch = export.copy();
      final recorded = GarminActivity(11)
        ..typeKey = 'strength_training'
        ..durationSeconds = 3600
        ..calories = 400
        ..averageHeartRate = 120
        ..startLocal = '${guardDay.iso} 18:30:00';
      expect(StrengthDuplicates.redundant([watch, recorded]), {10});
      final single = guarded(settings(), activities: [recorded]);
      final both = guarded(settings(), activities: [watch, recorded]);
      expect(both.exerciseKilocalories, single.exerciseKilocalories);
    });
  });

  group('Mahlzeiten (MealTests)', () {
    test('liest die Analyse des Workers', () {
      final output = JsonValue.parse('''
        {"titel": "Rührei mit Brot", "kategorie": "fruehstueck", "hinweis": "Ölmenge geschätzt",
         "items": [
           {"name": "Rührei", "menge_g": 120, "menge_text": "2 Eier", "getraenk": false, "sicherheit": "mittel",
            "gruppe": "ei", "barcode": null,
            "naehrwerte_100g": {"kcal": 150, "protein_g": 10, "carbs_g": 1, "fat_g": 11, "water_g": 75,
              "iron_mg": null}},
           {"name": "Kaffee", "menge_g": 200, "getraenk": true, "naehrwerte_100g": {"kcal": 2}},
           {"name": "ohne Menge", "menge_g": 0}
         ]}''');
      final analysis = MealAnalysis.fromOutput(output)!;
      expect(analysis.title, 'Rührei mit Brot');
      expect(analysis.category, MealCategory.breakfast);
      expect(analysis.items.length, 2);
      final egg = analysis.items[0];
      expect(egg.amounts[Nutrient.kcal], 180);
      expect(egg.per100g[Nutrient.water], 75);
      expect(egg.per100g[Nutrient.iron], isNull);
      expect(egg.confidence, 'mittel');
      expect(analysis.items[1].isDrink, isTrue);
      // Kaffee kommt aus dem BLS (1 kcal je 100 ml), Rührei bleibt KI-Schätzung (kein eindeutiger Grundeintrag).
      expect(analysis.items[1].source, MealItemSource.bls);
      expect(egg.source, MealItemSource.ai);
      expect(NutritionSummary.totals(analysis.items)[Nutrient.kcal], 182);
    });

    test('leere Analyse wird abgelehnt', () {
      expect(MealAnalysis.fromOutput(const JsonValue({'items': <Object?>[]})), isNull);
      expect(MealAnalysis.fromOutput(JsonValue.nullValue), isNull);
    });

    test('Mahlzeit nach Uhrzeit', () {
      expect(MealCategory.guess(hour: 7, minute: 30), MealCategory.breakfast);
      expect(MealCategory.guess(hour: 12, minute: 0), MealCategory.lunch);
      expect(MealCategory.guess(hour: 15, minute: 30), MealCategory.snack);
      expect(MealCategory.guess(hour: 19, minute: 0), MealCategory.dinner);
      expect(MealCategory.guess(hour: 23, minute: 0), MealCategory.snack);
    });

    test('Nährwerte hin und zurück', () {
      final values = NutrientValues()
        ..[Nutrient.protein] = 12.5
        ..[Nutrient.vitaminD] = 1.2;
      expect(values.toJson().containsKey('vitd_ug'), isTrue);
      expect(NutrientValues.fromJson(values.toJson()), values);
      expect(NutritionSummary.percent(50, 200), 25);
      expect(NutritionSummary.percent(50, null), isNull);
    });
  });

  group('Open Food Facts (OpenFoodFactsTests)', () {
    test('gültige und ungültige Barcodes', () {
      for (final code in ['4006381333931', '40170725', '036000291452', '4000417025005']) {
        expect(OpenFoodFacts.isValidBarcode(code), isTrue, reason: code);
      }
      for (final code in ['4006381333932', '1234', '40063813339x1', '']) {
        expect(OpenFoodFacts.isValidBarcode(code), isFalse, reason: code);
      }
    });

    test('liest ein Produkt mit Einheitenumrechnung', () {
      final json = JsonValue.parse('''
        {"status": 1, "product": {"product_name_de": "Skyr Natur", "brands": "Milbona, Lidl", "serving_quantity": 150,
          "nutriments": {"energy-kcal_100g": 63, "proteins_100g": 11, "carbohydrates_100g": 4, "fat_100g": 0.2,
            "sodium_100g": 0.04, "calcium_100g": 0.15, "vitamin-d_100g": 0.0000001, "iodine_100g": 0.00001}}}''');
      final product = OpenFoodFacts.product(json, barcode: '4056489123456')!;
      expect(product.name, 'Skyr Natur');
      expect(product.brand, 'Milbona');
      expect(product.servingGrams, 150);
      expect(product.per100g[Nutrient.kcal], 63);
      expect((product.per100g[Nutrient.sodium]! - 40).abs(), lessThan(0.001));
      expect((product.per100g[Nutrient.calcium]! - 150).abs(), lessThan(0.001));
      expect((product.per100g[Nutrient.vitaminD]! - 0.1).abs(), lessThan(0.0001));
      expect((product.per100g[Nutrient.iodine]! - 10).abs(), lessThan(0.0001));
      final item = product.item();
      expect(item.name, 'Skyr Natur (Milbona)');
      expect(item.grams, 150);
      expect(item.source, MealItemSource.openFoodFacts);
    });

    test('Kilojoule-Rückfall und unbekanntes Produkt', () {
      final kj = JsonValue.parse(
        '{"status": 1, "product": {"product_name": "X", "nutriments": {"energy_100g": 418.4}}}',
      );
      expect(OpenFoodFacts.product(kj, barcode: '1')?.per100g[Nutrient.kcal], 100);
      final unknown = JsonValue.parse('{"status": 0, "status_verbose": "product not found"}');
      expect(OpenFoodFacts.product(unknown, barcode: '1'), isNull);
      expect(
        OpenFoodFacts.productUri('4006381333931').toString(),
        startsWith('https://world.openfoodfacts.org/api/v2/product/4006381333931?fields='),
      );
    });
  });

  test('Garmin-Aktivität: Liste lesen, Details ergänzen, JSON wie Swift', () {
    final list = JsonValue.parse('''
      [{"activityId": 123, "activityName": "Morgenlauf", "activityType": {"typeKey": "running"},
        "startTimeLocal": "2026-10-23 07:00:00", "duration": 3600, "distance": 10000, "averageHR": 145,
        "hrTimeInZone_1": 60, "hrTimeInZone_2": 600, "hrTimeInZone_3": 2000, "hrTimeInZone_4": 800, "hrTimeInZone_5": 140,
        "averageRunningCadenceInStepsPerMinute": 172}]''');
    final parsed = GarminActivityParser.activities(list).single;
    expect(parsed.id, 123);
    expect(parsed.sport, ActivitySport.run);
    expect(parsed.day, day);
    expect(parsed.secondsInZones, [60, 600, 2000, 800, 140]);
    expect(parsed.averageCadence, 172);
    final detail = GarminActivityParser.detail(
      JsonValue.parse('{"summaryDTO": {"averageHR": 999, "maxHR": 170, "activityTrainingLoad": 95}}'),
      parsed,
    );
    expect(detail.averageHeartRate, 145, reason: 'vorhandene Werte bleiben');
    expect(detail.maxHeartRate, 170);
    expect(detail.trainingLoad, 95);
    expect(GarminActivity.fromJson(detail.toJson()), detail);
    expect(ActivitySport.fromTypeKey('lap_swimming'), ActivitySport.swim);
    expect(ActivitySport.fromTypeKey('indoor_cycling'), ActivitySport.bike);
    expect(ActivitySport.fromTypeKey('strength_training'), ActivitySport.strength);
    expect(ActivitySource.of(5), ActivitySource.garmin);
    expect(ActivitySource.of(-5), ActivitySource.health);
    expect(ActivitySource.of(-(1 << 62) - 1), ActivitySource.manual);
  });

  test('Garmin-Profil aus den Einstellungen', () {
    final profile = GarminProfile.fromSettings(
      JsonValue.parse('{"userData": {"weight": 78500, "height": 182, "birthDate": "1990-11-20", "gender": "male"}}'),
    );
    expect(profile.weightKilograms, 78.5);
    expect(profile.heightCentimeters, 182);
    expect(profile.gender, 'MALE');
    expect(profile.ageOn(const CalendarDay(2026, 11, 19)), 35);
    expect(profile.ageOn(const CalendarDay(2026, 11, 20)), 36);
  });
}

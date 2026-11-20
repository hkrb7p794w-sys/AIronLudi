// Prüfung der Ernährungsrechnung (Audit vom 20.11.2026, docs/decisions.md): Ziele (Grundumsatz, Bedarf, Ziel-Anpassung,
// Makros, Mikros) und Ist-Werte (Skalierung, Einheiten, Lücken, Tagessumme).
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const day = CalendarDay(2026, 11, 20);

/// Testpersonen: Mann 80 kg, 180 cm, 30 J.; Frau 62 kg, 166 cm, 30 J. (PAL 1,4).
NutritionSettings person({required bool female, NutritionGoal goal = NutritionGoal.maintain}) => NutritionSettings()
  ..weightKilograms = female ? 62 : 80
  ..heightCentimeters = female ? 166 : 180
  ..age = 30
  ..isFemale = female
  ..goal = goal;

GarminActivity workout(String typeKey, {required double minutes, required double kcal}) =>
    GarminActivity(minutes.round())
      ..typeKey = typeKey
      ..durationSeconds = minutes * 60
      ..calories = kcal
      ..startLocal = '${day.iso} 07:00:00';

NutritionTargets plan(NutritionSettings settings, {List<GarminActivity> activities = const []}) =>
    NutritionPlanner.compute(
      activities: activities,
      planItems: const [],
      settings: settings,
      garminProfile: null,
      day: day,
      hasGarminData: true,
    );

double kcalOf(NutritionTargets targets) => targets.values[Nutrient.kcal]!;

/// Bedarf ohne Ziel-Anpassung: Grundumsatz × PAL + Training (netto).
double need(NutritionTargets targets, {double pal = 1.4}) {
  final bmr = NutritionPlanner.mifflinStJeor(targets.profile);
  return bmr * pal + targets.exerciseKilocalories;
}

final days = <String, List<GarminActivity>>{
  'Ruhetag': [],
  'Kraft 45 min': [workout('strength_training', minutes: 45, kcal: 300)],
  'Lauf 60 min': [workout('running', minutes: 60, kcal: 700)],
  'Rad 120 min': [workout('cycling', minutes: 120, kcal: 1500)],
  'Rad 5 h': [workout('cycling', minutes: 300, kcal: 3500)],
};

void main() {
  setUpAll(() => BLS.load(File('assets/bls.tsv').readAsStringSync()));

  group('Grundumsatz und Bedarf', () {
    test('Mifflin-St Jeor mit kg, cm und Jahren', () {
      // 10 × 80 + 6,25 × 180 − 5 × 30 + 5 = 1780; Frau: 620 + 1037,5 − 150 − 161 = 1346,5.
      expect(NutritionPlanner.mifflinStJeor(person(female: false).profile(null, on: day)), 1780);
      expect(NutritionPlanner.mifflinStJeor(person(female: true).profile(null, on: day)), 1346.5);
      expect(plan(person(female: false)).basalMetabolicRate, 1780);
    });

    test('Training zählt netto, nicht doppelt mit dem PAL', () {
      // 700 kcal laut Uhr (brutto) − Grundbedarf × PAL für 60 min (1780 × 1,4 / 24 ≈ 104) = 596.
      final run = plan(person(female: false), activities: [workout('running', minutes: 60, kcal: 700)]);
      expect(run.exerciseKilocalories, 596);
      // Eine Einheit, die nicht mehr verbraucht als der Alltag in derselben Zeit, bringt nichts dazu.
      final walk = plan(person(female: false), activities: [workout('running', minutes: 60, kcal: 90)]);
      expect(walk.exerciseKilocalories, 0);
      // Ein höherer PAL senkt den Netto-Anteil des Trainings: der Alltag in dieser Stunde ist schon enthalten.
      final active = plan(
        person(female: false)..activityFactor = 1.8,
        activities: [workout('running', minutes: 60, kcal: 700)],
      );
      expect(active.exerciseKilocalories, lessThan(run.exerciseKilocalories));
    });
  });

  group('Ziel-Anpassung', () {
    for (final female in [false, true]) {
      final who = female ? 'Frau' : 'Mann';
      for (final MapEntry(key: label, value: activities) in days.entries) {
        test('$who, $label: Abnehmen nie über, Aufbauen nie unter dem Bedarf', () {
          final maintain = plan(person(female: female), activities: activities);
          final lose = plan(
            person(female: female, goal: NutritionGoal.lose),
            activities: activities,
          );
          final recomp = plan(
            person(female: female, goal: NutritionGoal.recomposition),
            activities: activities,
          );
          final gain = plan(
            person(female: female, goal: NutritionGoal.gain),
            activities: activities,
          );
          final base = need(maintain);
          // Höchstens 4 kcal Rundung (ganze Gramm).
          expect(kcalOf(maintain), inInclusiveRange(base - 4, base));
          expect(kcalOf(lose), lessThanOrEqualTo(base));
          expect(kcalOf(recomp), lessThanOrEqualTo(base));
          // Defizit höchstens ein Viertel und nie unter dem Grundumsatz.
          expect(kcalOf(lose), greaterThanOrEqualTo(0.75 * base - 4));
          expect(kcalOf(lose), greaterThanOrEqualTo(lose.basalMetabolicRate - 4));
          // Aufbau: moderater Überschuss an jedem Tag (10 % des Bedarfs ohne Sport ≈ 190–250 kcal).
          final surplus = kcalOf(gain) - base;
          expect(surplus, inInclusiveRange(150, 350));
        });
      }
    }

    test('Abnehmen am Ruhetag: 15 % Defizit', () {
      final maintain = plan(person(female: false));
      final lose = plan(person(female: false, goal: NutritionGoal.lose));
      // 2492 × 0,85 = 2118.
      expect(kcalOf(lose), inInclusiveRange(2114, 2118));
      expect(kcalOf(maintain) - kcalOf(lose), inInclusiveRange(300, 500));
    });

    test('Wochentempo Aufbauen: fester Überschuss, auch am harten Tag', () {
      final gaining = person(female: false, goal: NutritionGoal.gain)..weeklyWeightChangePercent = 0.25;
      // 0,25 % × 80 kg × 7700 / 7 = 220 kcal je Tag.
      for (final activities in days.values) {
        final surplus = kcalOf(plan(gaining, activities: activities)) - need(plan(gaining, activities: activities));
        expect(surplus, inInclusiveRange(216, 220));
      }
    });

    test('Untergrenze: nie unter dem Grundumsatz, auch bei niedrigem PAL und viel Defizit', () {
      final value = person(female: true, goal: NutritionGoal.lose)
        ..activityFactor = 1.2
        ..bodyFatPercent = 32
        ..weeklyWeightChangePercent = -1
        ..energyAdjustmentKilocalories = -500;
      final result = plan(value);
      // 30 kcal × 42,2 kg fettfreie Masse = 1265 läge unter dem Grundumsatz (1346,5): Energie auf den Grundumsatz.
      expect(result.energyAvailabilityFloorApplied, isTrue);
      expect(kcalOf(result), greaterThanOrEqualTo(1343));
      // Darauf die Mindestmengen (136 g Protein, 130 g Kohlenhydrate am Ruhetag, 0,7 g/kg Fett ≈ 1455 kcal) –
      // das Defizit zum Bedarf von 1616 kcal bleibt.
      expect(kcalOf(result), inInclusiveRange(1440, 1460));
      expect(result.values[Nutrient.carbs]!, inInclusiveRange(130, 132));
      expect(result.values[Nutrient.fat]!, greaterThanOrEqualTo(43));
    });
  });

  group('Makros', () {
    for (final goal in NutritionGoal.values) {
      for (final MapEntry(key: label, value: activities) in days.entries) {
        test('${goal.label}, $label: kcal = 4 × P + 4 × KH + 9 × F, Fett ≥ 20 %', () {
          final result = plan(person(female: false, goal: goal), activities: activities);
          final (protein, carbs, fat) = (
            result.values[Nutrient.protein]!,
            result.values[Nutrient.carbs]!,
            result.values[Nutrient.fat]!,
          );
          expect(kcalOf(result), 4 * protein + 4 * carbs + 9 * fat);
          expect(9 * fat / kcalOf(result), greaterThanOrEqualTo(0.195));
          expect(protein, (goal.proteinPerKilogram * 80).roundToDouble());
          // Fett mindestens 0,7 g/kg. Kohlenhydrate mindestens 3 g/kg, am Ruhetag im Defizit 2 g/kg.
          expect(fat, greaterThanOrEqualTo(0.7 * 80 - 0.5));
          final restDeficit = result.dayType == DayType.restDay && goal.adjustPercent < 0;
          expect(carbs, greaterThanOrEqualTo((restDeficit ? 2 : 3) * 80 - 1));
        });
      }
    }

    test('lange Ausdauer: Kohlenhydrate nach Tagestyp (8–10 g/kg)', () {
      final result = plan(person(female: false), activities: days['Rad 5 h']!);
      expect(result.dayType, DayType.veryHard);
      expect(result.values[Nutrient.carbs]!, greaterThanOrEqualTo(8 * 80));
    });

    test('eigene Gramm: Energie folgt den Gramm, Untergrenze hebt KH und Fett', () {
      final custom = person(female: false, goal: NutritionGoal.lose)
        ..macroMode = MacroMode.grams
        ..macros = const MacroGoal(protein: 180, carbs: 100, fat: 30);
      final result = plan(custom);
      // 180 × 4 + 100 × 4 + 30 × 9 = 1390 < 0,75 × 2492 → angehoben, Protein bleibt.
      expect(result.values[Nutrient.protein], 180);
      expect(kcalOf(result), greaterThanOrEqualTo(0.75 * 2492 - 4));
      expect(
        kcalOf(result),
        4 * result.values[Nutrient.protein]! + 4 * result.values[Nutrient.carbs]! + 9 * result.values[Nutrient.fat]!,
      );
      expect(result.macroNotes, isNotEmpty);
    });

    test('eigene Prozent mit eigener Energie: Anteile und Summe passen', () {
      final custom = person(female: false)
        ..macroMode = MacroMode.percent
        ..macros = const MacroGoal(protein: 30, carbs: 40, fat: 30, kilocalories: 2600);
      final result = plan(custom);
      expect(kcalOf(result), inInclusiveRange(2596, 2600));
      expect(result.values[Nutrient.protein], (0.30 * 2600 / 4).roundToDouble());
      expect(result.values[Nutrient.fat], (0.30 * 2600 / 9).roundToDouble());
    });
  });

  group('Mikronährstoffe und Flüssigkeit', () {
    test('feste Referenzwerte bleiben bei jedem Ziel und Tagestyp gleich', () {
      final reference = plan(person(female: true)).values;
      for (final goal in NutritionGoal.values) {
        for (final activities in days.values) {
          final values = plan(person(female: true, goal: goal), activities: activities).values;
          for (final nutrient in [
            Nutrient.fiber,
            Nutrient.potassium,
            Nutrient.magnesium,
            Nutrient.calcium,
            Nutrient.iron,
            Nutrient.zinc,
            Nutrient.vitaminD,
            Nutrient.vitaminB12,
            Nutrient.vitaminC,
            Nutrient.iodine,
            Nutrient.omega3,
          ]) {
            expect(values[nutrient], reference[nutrient], reason: '${goal.label} ${nutrient.label}');
          }
        }
      }
    });

    test('Einheiten der Referenzwerte (DGE): mg und µg nicht vertauscht', () {
      final woman = plan(person(female: true)).values;
      final man = plan(person(female: false)).values;
      expect(woman[Nutrient.iron], 16); // mg
      expect(man[Nutrient.iron], 11);
      // Nach der Menopause (ab 51 angenommen) 14 mg (DGE/ÖGE 2024).
      expect(plan(person(female: true)..age = 55).values[Nutrient.iron], 14);
      expect(plan(person(female: false)..age = 55).values[Nutrient.iron], 11);
      expect(man[Nutrient.magnesium], 350); // mg
      expect(woman[Nutrient.calcium], 1000); // mg
      expect(woman[Nutrient.vitaminD], 20); // µg (= 800 IE)
      expect(woman[Nutrient.vitaminB12], 4); // µg
      expect(woman[Nutrient.iodine], 150); // µg
      expect(woman[Nutrient.fiber], 30); // g
      expect(Nutrient.vitaminD.unit, 'µg');
      expect(Nutrient.iron.unit, 'mg');
    });

    test('Natrium: Richtwert plus Schweißverlust, weder Ziel noch Grenze', () {
      expect(plan(person(female: false)).values[Nutrient.sodium], 1500);
      // 60 min Lauf: +500 mg; 45 min Kraft: +200 mg (gerundet auf 50).
      expect(plan(person(female: false), activities: days['Lauf 60 min']!).values[Nutrient.sodium], 2000);
      expect(plan(person(female: false), activities: days['Kraft 45 min']!).values[Nutrient.sodium], 1700);
      expect(plan(person(female: false), activities: days['Rad 5 h']!).values[Nutrient.sodium], 4000);
      expect(Nutrient.sodium.isReference, isTrue);
      expect(Nutrient.sodium.isUpperLimit, isFalse);
      expect(Nutrient.sugar.isUpperLimit, isTrue);
    });

    test('Flüssigkeit: 35 ml/kg plus Training, Zucker und gesättigte Fette als 10 % der Energie', () {
      final rest = plan(person(female: false)).values;
      expect(rest[Nutrient.water], 2800); // 35 × 80
      final run = plan(person(female: false), activities: days['Lauf 60 min']!).values;
      expect(run[Nutrient.water], 3400); // + 10 ml je Minute Ausdauer
      expect(rest[Nutrient.sugar], (0.10 * rest[Nutrient.kcal]! / 4).roundToDouble());
      expect(rest[Nutrient.saturatedFat], (0.10 * rest[Nutrient.kcal]! / 9).roundToDouble());
    });
  });

  group('Ist-Werte aus Lebensmitteln', () {
    MealItem food(String name, double grams, Map<Nutrient, double> per100g, {bool drink = false}) => MealItem(
      name: name,
      grams: grams,
      source: MealItemSource.manual,
      per100g: NutrientValues(per100g),
      isDrink: drink,
    );

    test('Werte je 100 g werden auf die gegessene Menge umgerechnet', () {
      final oats = food('Haferflocken', 250, {Nutrient.kcal: 370, Nutrient.protein: 13.5, Nutrient.iron: 4.2});
      expect(oats.amounts[Nutrient.kcal], 925);
      expect(oats.amounts[Nutrient.protein], closeTo(33.75, 1e-9));
      expect(oats.amounts[Nutrient.iron], closeTo(10.5, 1e-9));
      final bar = food('Riegel', 35, {Nutrient.kcal: 400})..portion = const Portion('Riegel', 35);
      expect(bar.amounts[Nutrient.kcal], 140);
      bar.setPortions(2);
      expect(bar.amounts[Nutrient.kcal], 280);
    });

    test('Open Food Facts: Packungsportion, Einheiten g → mg/µg', () {
      final json = JsonValue.parse('''
        {"status": 1, "product": {"product_name": "Proteinriegel", "serving_quantity": 45, "serving_size": "1 Riegel (45 g)",
          "nutriments": {"energy-kcal_100g": 380, "proteins_100g": 30, "carbohydrates_100g": 35, "sugars_100g": 5,
            "fat_100g": 12, "salt_100g": 0.5, "magnesium_100g": 0.2, "vitamin-b12_100g": 0.0000025}}}''');
      final product = OpenFoodFacts.product(json, barcode: '4006381333931')!;
      final item = product.item();
      expect(item.grams, 45);
      expect(item.portion, const Portion('Riegel', 45));
      expect(item.amounts[Nutrient.kcal], closeTo(171, 1e-9));
      // Nur Salz angegeben: 0,5 g Salz / 2,5 = 0,2 g = 200 mg Natrium je 100 g.
      expect(product.per100g[Nutrient.sodium], closeTo(200, 1e-9));
      expect(product.per100g[Nutrient.magnesium], closeTo(200, 1e-9));
      expect(product.per100g[Nutrient.vitaminB12], closeTo(2.5, 1e-9));
    });

    test('Open Food Facts: unmögliche Werte (Faktor 1.000) gelten als unbekannt', () {
      final json = JsonValue.parse('''
        {"status": 1, "product": {"product_name": "Tippfehler",
          "nutriments": {"energy-kcal_100g": 250, "proteins_100g": 8, "carbohydrates_100g": 30, "sugars_100g": 45,
            "fat_100g": 10, "sodium_100g": 400, "calcium_100g": 0.12}}}''');
      final product = OpenFoodFacts.product(json, barcode: '1')!;
      // 400 g Natrium je 100 g (mg ins Gramm-Feld getippt) und mehr Zucker als Kohlenhydrate.
      expect(product.per100g[Nutrient.sodium], isNull);
      expect(product.per100g[Nutrient.sugar], isNull);
      expect(product.per100g[Nutrient.calcium], closeTo(120, 1e-9));
      final impossible = JsonValue.parse(
        '{"status": 1, "product": {"product_name": "X", "nutriments": {"energy-kcal_100g": 3700}}}',
      );
      expect(OpenFoodFacts.product(impossible, barcode: '1'), isNull);
    });

    test('KI-Schätzung und Etikett-Foto: dieselbe Plausibilitätsprüfung', () {
      final estimate = MealAnalysis.item(
        JsonValue.parse('''
          {"name": "Unbekanntes Gericht xyz", "menge_g": 300,
           "naehrwerte_100g": {"kcal": 150, "protein_g": 8, "iron_mg": 120000, "vitd_ug": 2}}'''),
      )!;
      expect(estimate.per100g[Nutrient.iron], isNull);
      expect(estimate.per100g[Nutrient.vitaminD], 2);
      final label = NutritionLabel.item(
        JsonValue.parse('{"name": "Müsli", "naehrwerte_100g": {"kcal": 380, "fat_g": 6, "satfat_g": 9}}'),
      )!;
      expect(label.per100g[Nutrient.saturatedFat], isNull);
      expect(label.per100g[Nutrient.fat], 6);
    });

    test('Tagessumme: fehlende Werte sind unbekannt, nicht 0', () {
      final items = [
        food('Haferflocken', 80, {Nutrient.kcal: 370, Nutrient.protein: 13.5, Nutrient.iron: 4.2}),
        food('Milch', 200, {Nutrient.kcal: 64, Nutrient.protein: 3.3, Nutrient.water: 87}, drink: true),
        food('Riegel', 45, {Nutrient.kcal: 380, Nutrient.protein: 30}),
      ];
      final intake = FoodAggregation.of(items);
      expect(intake.itemCount, 3);
      expect(intake.totals[Nutrient.kcal], closeTo(296 + 128 + 171, 1e-9));
      expect(intake.totals[Nutrient.protein], closeTo(10.8 + 6.6 + 13.5, 1e-9));
      // Eisen nur bei den Haferflocken: Summe ist eine Untergrenze.
      expect(intake.totals[Nutrient.iron], closeTo(3.36, 1e-9));
      expect(intake.isPartial(Nutrient.iron), isTrue);
      expect(intake.missingCount(Nutrient.iron), 2);
      // Vitamin D hat niemand: unbekannt.
      expect(intake.isUnknown(Nutrient.vitaminD), isTrue);
      expect(intake.totals[Nutrient.vitaminD], isNull);
      // Flüssigkeit wie im Wasser-Ring: Wasseranteil der Milch.
      expect(intake.totals[Nutrient.water], closeTo(174, 1e-9));
      expect(intake.isUnknown(Nutrient.kcal), isFalse);
      expect(intake.missingCount(Nutrient.kcal), 0);
    });

    test('Tagessumme: Getränk ohne Wasserwert zählt mit seiner Menge, Bearbeiten und Löschen rechnen neu', () {
      final water = MealItem.water(milliliters: 500);
      final juice = food('Saft', 250, {Nutrient.kcal: 45}, drink: true);
      final bread = food('Brot', 60, {Nutrient.kcal: 240});
      var intake = FoodAggregation.of([water, juice, bread]);
      expect(intake.totals[Nutrient.water], 750);
      expect(intake.missingCount(Nutrient.water), 1); // nur das Brot
      expect(intake.totals[Nutrient.kcal], closeTo(112.5 + 144, 1e-9));
      bread.grams = 120;
      intake = FoodAggregation.of([water, juice, bread]);
      expect(intake.totals[Nutrient.kcal], closeTo(112.5 + 288, 1e-9));
      intake = FoodAggregation.of([water, bread]);
      expect(intake.totals[Nutrient.kcal], closeTo(288, 1e-9));
      expect(FoodAggregation.of(const []).itemCount, 0);
      expect(FoodAggregation.of(const []).isUnknown(Nutrient.iron), isFalse);
    });

    test('Rezept: Nährwerte je 100 g des fertigen Gerichts und je Portion', () {
      final recipe = OwnRecipe(
        name: 'Chili',
        ingredients: [
          food('Hackfleisch', 500, {Nutrient.kcal: 250, Nutrient.protein: 20}),
          food('Bohnen', 500, {Nutrient.kcal: 100, Nutrient.protein: 7}),
        ],
        cookedGrams: 1250,
        portions: 5,
      );
      // 1750 kcal auf 1250 g = 140 kcal je 100 g; Portion 250 g = 350 kcal = ein Fünftel.
      expect(recipe.per100g[Nutrient.kcal], closeTo(140, 1e-9));
      expect(recipe.item().grams, 250);
      expect(recipe.item().amounts[Nutrient.kcal], closeTo(350, 1e-9));
      expect(recipe.item().amounts[Nutrient.protein], closeTo(135 / 5, 1e-9));
    });
  });

  group('Auswertungen über Tage', () {
    MealItem food(String name, double grams, Map<Nutrient, double> per100g) =>
        MealItem(name: name, grams: grams, source: MealItemSource.manual, per100g: NutrientValues(per100g));

    test('Bedarf ohne Ziel und eigene Makros für den Verbrauchsabgleich', () {
      final run = days['Lauf 60 min']!;
      final maintain = plan(person(female: false), activities: run);
      final custom = person(female: false, goal: NutritionGoal.lose)
        ..macroMode = MacroMode.grams
        ..macros = const MacroGoal(protein: 200, carbs: 150, fat: 60)
        ..energyAdjustmentKilocalories = -300;
      final result = plan(custom, activities: run);
      // 1780 × 1,4 + 596 = 3088 – unabhängig von Ziel, Anpassung und eigenen Gramm.
      expect(maintain.maintenanceKilocalories, 3088);
      expect(result.maintenanceKilocalories, 3088);
      expect(kcalOf(result), isNot(3088));
    });

    test('reines Wasser hat keine Lücken, andere Lücken zählen nach Energie', () {
      final intake = FoodAggregation.of([
        MealItem.water(milliliters: 500),
        food('Haferflocken', 100, {Nutrient.kcal: 370, Nutrient.iron: 4.2, Nutrient.iodine: 1}),
        food('Gurke', 50, {Nutrient.kcal: 12, Nutrient.iron: 0.2}),
        food('Riegel', 50, {Nutrient.kcal: 400}),
      ]);
      expect(intake.itemCount, 3);
      expect(intake.missingCount(Nutrient.iron), 1);
      // Gurke ohne Jod: 6 von 576 kcal (1 %) → Summe taugt; Riegel ohne Eisen: 200 kcal (35 %) → nicht.
      expect(intake.completeTotals[Nutrient.iron], isNull);
      expect(intake.completeTotals[Nutrient.kcal], closeTo(576, 1e-9));
      final small = FoodAggregation.of([
        food('Haferflocken', 100, {Nutrient.kcal: 370, Nutrient.iodine: 1}),
        food('Gurke', 50, {Nutrient.kcal: 12}),
      ]);
      expect(small.completeTotals[Nutrient.iodine], closeTo(1, 1e-9));
      expect(small.completeTotals[Nutrient.vitaminD], isNull);
    });

    test('Lückenliste: unbekannte Werte täuschen keinen Mangel vor', () {
      final goals = NutrientValues({Nutrient.iron: 15, Nutrient.fiber: 30});
      final known = NutrientValues({Nutrient.kcal: 2000, Nutrient.fiber: 18});
      // Eisen an keinem Tag bekannt: keine Eisen-Lücke; Ballaststoffe bekannt und zu niedrig.
      expect(RecipePlanner.gaps(dailyTotals: [known, known, known], targets: goals), [
        'Ballaststoffe: im Schnitt 18 von 30 g (60 %)',
      ]);
      // Nur an zwei Tagen bekannt: zu wenig für eine Aussage.
      final withIron = NutrientValues({Nutrient.kcal: 2000, Nutrient.fiber: 30, Nutrient.iron: 5});
      expect(RecipePlanner.gaps(dailyTotals: [withIron, withIron, known], targets: goals), isEmpty);
    });

    test('Budget: mit Lücken „höchstens“ übrig', () {
      final targets = NutrientValues({Nutrient.protein: 150});
      final items = [
        food('Hähnchen', 200, {Nutrient.kcal: 110, Nutrient.protein: 23}),
        MealItem(
          name: 'Restaurant',
          grams: 100,
          source: MealItemSource.manual,
          per100g: NutrientValues({Nutrient.kcal: 800}),
        ),
      ];
      final intake = FoodAggregation.of(items);
      final line = NutritionBudget.line(Nutrient.protein, targets: targets, totals: intake.totals, intake: intake)!;
      expect(line.partial, isTrue);
      expect(NutritionBudget.remainingText(line), 'noch höchstens 104 g');
      final full = NutritionBudget.line(Nutrient.protein, targets: targets, totals: intake.totals)!;
      expect(NutritionBudget.remainingText(full), 'noch 104 g');
    });
  });
}

// Fuel Planner: herkömmliche Lebensmittel statt (oder neben) Sportnahrung. Nährwerte je 100 g aus dem BLS 4.0
// (Code je Lebensmittel, per Test gegen `assets/bls.tsv` geprüft); der Fruktose-Anteil ist eine eigene Schätzung aus
// der Zuckerzusammensetzung (der BLS-Auszug enthält keine Fruktose). Spezifikation 10 (docs/FUEL_PLANNER_SCIENCE.md).
import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../nutrition/bls.dart';
import '../nutrition/meal.dart';
import '../nutrition/nutrient.dart';
import 'fuel_plan.dart';
import 'fuel_product.dart';
import 'fuel_scenario.dart';

/// Ein Lebensmittel mit Werten je 100 g (BLS) und einer üblichen Portion.
final class FuelFood {
  const FuelFood({
    required this.id,
    required this.name,
    required this.bls,
    required this.portion,
    required this.portionGrams,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sodium,
    this.fructoseShare = 0,
    this.caffeinePer100 = 0,
    this.isDrink = false,
    this.alwaysAtHome = false,
  });

  final String id;
  final String name;

  /// Code im Bundeslebensmittelschlüssel 4.0.
  final String bls;

  /// „Scheibe“, „EL“, „Glas (250 ml)“ …
  final String portion;
  final double portionGrams;

  // Je 100 g bzw. 100 ml (BLS).
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  /// mg
  final double sodium;

  /// Anteil Fruktose an den Kohlenhydraten (eigene Schätzung).
  final double fructoseShare;

  /// mg je 100 ml (Cola ≈ 10 mg).
  final double caffeinePer100;
  final bool isDrink;

  /// Salz und Wasser: immer da, auch wenn „nur was ich zu Hause habe“ gilt.
  final bool alwaysAtHome;

  FuelAmounts amounts(double grams) {
    final f = grams / 100;
    return FuelAmounts(
      carbs: carbs * f,
      fructose: carbs * f * fructoseShare,
      fructoseKnownCarbs: carbs * f,
      protein: protein * f,
      fat: fat * f,
      fluid: isDrink ? grams : 0,
      sodium: sodium * f,
      caffeine: caffeinePer100 * f,
    );
  }

  /// Position fürs Ernährungstagebuch mit den BLS-Werten.
  MealItem item(double grams) => MealItem(
    name: name,
    grams: (grams * 10).roundToDouble() / 10,
    isDrink: isDrink,
    source: MealItemSource.bls,
    blsCode: bls,
    portion: Portion(portion, portionGrams),
    per100g: NutrientValues({
      Nutrient.kcal: kcal,
      Nutrient.protein: protein,
      Nutrient.carbs: carbs,
      Nutrient.fat: fat,
      Nutrient.fiber: fiber,
      Nutrient.sodium: sodium,
    }),
  );

  /// Abgleich mit dem BLS (für Tests): stimmen die hinterlegten Werte mit der Tabelle überein?
  bool matches(BLSFood food) {
    bool close(double? value, double expected) => (value ?? 0).toStringAsFixed(1) == expected.toStringAsFixed(1);
    final v = food.per100g;
    return food.code == bls &&
        close(v[Nutrient.kcal], kcal) &&
        close(v[Nutrient.protein], protein) &&
        close(v[Nutrient.carbs], carbs) &&
        close(v[Nutrient.fat], fat) &&
        close(v[Nutrient.fiber], fiber) &&
        close(v[Nutrient.sodium], sodium);
  }
}

/// Alle Lebensmittel des Planers (Werte aus dem BLS 4.0, je 100 g).
abstract final class FuelFoods {
  // Kohlenhydrate für Mahlzeiten.
  static const toast = FuelFood(
    id: 'toast',
    name: 'Toastbrot',
    bls: 'B314000',
    portion: 'Scheibe',
    portionGrams: 25,
    kcal: 261,
    protein: 8.29,
    carbs: 46.8,
    fat: 3.59,
    fiber: 3.947,
    sodium: 598,
  );
  static const roll = FuelFood(
    id: 'roll',
    name: 'Weizenbrötchen',
    bls: 'B511000',
    portion: 'Brötchen',
    portionGrams: 55,
    kcal: 280,
    protein: 10.09,
    carbs: 53.97,
    fat: 1.81,
    fiber: 3.6,
    sodium: 731,
  );
  static const honey = FuelFood(
    id: 'honey',
    name: 'Honig',
    bls: 'S120000',
    portion: 'EL',
    portionGrams: 20,
    kcal: 305,
    protein: 0.4,
    carbs: 74.09,
    fat: 0,
    fiber: 0,
    sodium: 3,
    fructoseShare: 0.5,
  );
  static const jam = FuelFood(
    id: 'jam',
    name: 'Konfitüre',
    bls: 'S132000',
    portion: 'EL',
    portionGrams: 20,
    kcal: 234,
    protein: 0.4,
    carbs: 56.3,
    fat: 0.2,
    fiber: 1.1,
    sodium: 3,
    fructoseShare: 0.45,
  );
  static const oats = FuelFood(
    id: 'oats',
    name: 'Haferflocken',
    bls: 'C133000',
    portion: 'Portion (50 g)',
    portionGrams: 50,
    kcal: 348,
    protein: 13.22,
    carbs: 53.3,
    fat: 6.65,
    fiber: 10.98,
    sodium: 1.98,
  );
  static const rice = FuelFood(
    id: 'rice',
    name: 'Reis, gekocht',
    bls: 'C352032',
    portion: 'Portion (150 g)',
    portionGrams: 150,
    kcal: 117,
    protein: 3.3,
    carbs: 24.8,
    fat: 0.35,
    fiber: 0.61,
    sodium: 9.77,
  );
  static const pasta = FuelFood(
    id: 'pasta',
    name: 'Nudeln, gekocht',
    bls: 'E401032',
    portion: 'Portion (150 g)',
    portionGrams: 150,
    kcal: 146,
    protein: 5.4,
    carbs: 28.68,
    fat: 0.702,
    fiber: 1.494,
    sodium: 0.7,
  );
  static const potatoes = FuelFood(
    id: 'potatoes',
    name: 'Salzkartoffeln',
    bls: 'X610042',
    portion: 'Portion (200 g)',
    portionGrams: 200,
    kcal: 75,
    protein: 1.84,
    carbs: 16.08,
    fat: 0.09,
    fiber: 1.318,
    sodium: 74.8,
  );
  static const riceCakes = FuelFood(
    id: 'riceCakes',
    name: 'Reiswaffeln',
    bls: 'C532700',
    portion: 'Waffel',
    portionGrams: 8,
    kcal: 371,
    protein: 8,
    carbs: 77.47,
    fat: 2.42,
    fiber: 3.63,
    sodium: 5,
  );
  static const rusk = FuelFood(
    id: 'rusk',
    name: 'Zwieback',
    bls: 'D038000',
    portion: 'Scheibe',
    portionGrams: 10,
    kcal: 414,
    protein: 11.05,
    carbs: 72.21,
    fat: 7.86,
    fiber: 4.62,
    sodium: 269,
    fructoseShare: 0.1,
  );
  static const riceMilk = FuelFood(
    id: 'riceMilk',
    name: 'Milchreis',
    bls: 'X810033',
    portion: 'Portion (200 g)',
    portionGrams: 200,
    kcal: 140,
    protein: 4.89,
    carbs: 22.4,
    fat: 3.22,
    fiber: 0.6,
    sodium: 43,
    fructoseShare: 0.1,
  );

  // Obst und Säfte.
  static const banana = FuelFood(
    id: 'banana',
    name: 'Banane',
    bls: 'F503100',
    portion: 'Banane',
    portionGrams: 120,
    kcal: 79,
    protein: 1.319,
    carbs: 15.89,
    fat: 0.4,
    fiber: 2,
    sodium: 0.52,
    fructoseShare: 0.3,
  );
  static const appleJuice = FuelFood(
    id: 'appleJuice',
    name: 'Apfelsaft',
    bls: 'F110600',
    portion: 'Glas (250 ml)',
    portionGrams: 250,
    kcal: 44,
    protein: 0.097,
    carbs: 10.59,
    fat: 0,
    fiber: 0.31,
    sodium: 6,
    fructoseShare: 0.55,
    isDrink: true,
  );
  static const orangeJuice = FuelFood(
    id: 'orangeJuice',
    name: 'Orangensaft',
    bls: 'F603600',
    portion: 'Glas (250 ml)',
    portionGrams: 250,
    kcal: 41,
    protein: 0.75,
    carbs: 8.5,
    fat: 0,
    fiber: 0.31,
    sodium: 2,
    fructoseShare: 0.3,
    isDrink: true,
  );
  static const dates = FuelFood(
    id: 'dates',
    name: 'Datteln, getrocknet',
    bls: 'F504400',
    portion: 'Dattel',
    portionGrams: 8,
    kcal: 356,
    protein: 2.64,
    carbs: 79.3,
    fat: 0.36,
    fiber: 11.16,
    sodium: 4.7,
    fructoseShare: 0.45,
  );
  static const raisins = FuelFood(
    id: 'raisins',
    name: 'Rosinen',
    bls: 'F840100',
    portion: 'Handvoll (30 g)',
    portionGrams: 30,
    kcal: 288,
    protein: 2.7,
    carbs: 61.8,
    fat: 1,
    fiber: 5.4,
    sodium: 11,
    fructoseShare: 0.5,
  );

  // Süßes und Salziges für unterwegs.
  static const gummies = FuelFood(
    id: 'gummies',
    name: 'Fruchtgummi',
    bls: 'S361000',
    portion: 'Handvoll (25 g)',
    portionGrams: 25,
    kcal: 312,
    protein: 4.8,
    carbs: 70.7,
    fat: 0.3,
    fiber: 1.01,
    sodium: 57,
    fructoseShare: 0.2,
  );
  static const pretzels = FuelFood(
    id: 'pretzels',
    name: 'Salzbrezeln',
    bls: 'D064000',
    portion: 'Handvoll (30 g)',
    portionGrams: 30,
    kcal: 389,
    protein: 11.54,
    carbs: 73.72,
    fat: 4.3,
    fiber: 4.17,
    sodium: 1610,
  );
  static const cola = FuelFood(
    id: 'cola',
    name: 'Cola',
    bls: 'N330000',
    portion: 'Glas (250 ml)',
    portionGrams: 250,
    kcal: 41,
    protein: 0,
    carbs: 10.3,
    fat: 0,
    fiber: 0,
    sodium: 1,
    fructoseShare: 0.5,
    caffeinePer100: 10,
    isDrink: true,
  );
  static const appleSpritzer = FuelFood(
    id: 'appleSpritzer',
    name: 'Apfelschorle',
    bls: 'N256000',
    portion: 'Flasche (500 ml)',
    portionGrams: 500,
    kcal: 26,
    protein: 0.056,
    carbs: 6.139,
    fat: 0,
    fiber: 0.18,
    sodium: 5,
    fructoseShare: 0.55,
    isDrink: true,
  );
  static const salt = FuelFood(
    id: 'salt',
    name: 'Speisesalz',
    bls: 'R111000',
    portion: 'Prise (1 g)',
    portionGrams: 1,
    kcal: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    fiber: 0,
    sodium: 38140,
    alwaysAtHome: true,
  );

  // Protein.
  static const milk = FuelFood(
    id: 'milk',
    name: 'Milch 3,5 %',
    bls: 'M111300',
    portion: 'Glas (250 ml)',
    portionGrams: 250,
    kcal: 62,
    protein: 3.55,
    carbs: 4.03,
    fat: 3.49,
    fiber: 0,
    sodium: 34.9,
    isDrink: true,
  );
  static const yogurt = FuelFood(
    id: 'yogurt',
    name: 'Joghurt',
    bls: 'M141300',
    portion: 'Becher (150 g)',
    portionGrams: 150,
    kcal: 67,
    protein: 3.98,
    carbs: 4.13,
    fat: 3.46,
    fiber: 0,
    sodium: 40,
  );
  static const skyr = FuelFood(
    id: 'skyr',
    name: 'Skyr',
    bls: 'M710100',
    portion: 'Becher (150 g)',
    portionGrams: 150,
    kcal: 64,
    protein: 10.35,
    carbs: 3.19,
    fat: 0.84,
    fiber: 0.18,
    sodium: 33.3,
  );
  static const quark = FuelFood(
    id: 'quark',
    name: 'Magerquark',
    bls: 'M713100',
    portion: 'Portion (125 g)',
    portionGrams: 125,
    kcal: 66,
    protein: 11.85,
    carbs: 3.68,
    fat: 0.18,
    fiber: 0,
    sodium: 33.6,
  );
  static const egg = FuelFood(
    id: 'egg',
    name: 'Ei',
    bls: 'E111100',
    portion: 'Ei',
    portionGrams: 60,
    kcal: 135,
    protein: 13.18,
    carbs: 0.34,
    fat: 9,
    fiber: 0,
    sodium: 154,
  );
  static const chicken = FuelFood(
    id: 'chicken',
    name: 'Hähnchenbrust, gebraten',
    bls: 'Y562032',
    portion: 'Portion (120 g)',
    portionGrams: 120,
    kcal: 145,
    protein: 30.73,
    carbs: 0,
    fat: 2.44,
    fiber: 0,
    sodium: 156.2,
  );
  static const tuna = FuelFood(
    id: 'tuna',
    name: 'Thunfisch im eigenen Saft',
    bls: 'T121902',
    portion: 'Dose (130 g)',
    portionGrams: 130,
    kcal: 95,
    protein: 22.87,
    carbs: 0,
    fat: 0.41,
    fiber: 0,
    sodium: 360,
  );

  static const all = [
    toast,
    roll,
    honey,
    jam,
    oats,
    rice,
    pasta,
    potatoes,
    riceCakes,
    rusk,
    riceMilk,
    banana,
    appleJuice,
    orangeJuice,
    dates,
    raisins,
    gummies,
    pretzels,
    cola,
    appleSpritzer,
    salt,
    milk,
    yogurt,
    skyr,
    quark,
    egg,
    chicken,
    tuna,
  ];

  /// Zur Auswahl „Habe ich zu Hause“ (ohne Salz – das hat jeder).
  static List<FuelFood> get choosable => [
    for (final food in all)
      if (!food.alwaysAtHome) food,
  ];

  static FuelFood? byId(String id) => all.firstWhereOrNull((food) => food.id == id);
}

/// Ein Teil eines Snacks bzw. einer Mahlzeit: Lebensmittel und Menge in g.
typedef FuelFoodPart = ({FuelFood food, double grams});

/// Alltags-Snack für unterwegs (ein oder mehrere Lebensmittel), als Produkt im Zeitstrahl nutzbar.
final class FuelSnack {
  const FuelSnack({required this.id, required this.name, required this.parts, required this.tip, this.heavy = false});

  final String id;
  final String name;
  final List<FuelFoodPart> parts;

  /// Wie man es mitnimmt und isst.
  final String tip;

  /// Feste Kost (Brot, Banane, Brezeln): eher in der ersten Hälfte und auf dem Rad.
  final bool heavy;

  static const idPrefix = 'food.';

  String get productId => '$idPrefix$id';

  bool get isDrink => parts.first.food.isDrink;

  FuelAmounts get amounts => FuelAmounts.sum(parts.map((part) => part.food.amounts(part.grams)));

  bool availableWith(Set<String> home) => parts.every((part) => part.food.alwaysAtHome || home.contains(part.food.id));

  /// Als Produkt für den Planer.
  FuelProduct get product {
    final a = amounts;
    final volume = isDrink ? parts.where((part) => part.food.isDrink).fold(0.0, (sum, part) => sum + part.grams) : 0.0;
    return FuelProduct(
      id: productId,
      name: name,
      kind: isDrink ? FuelProductKind.drink : (heavy ? FuelProductKind.food : FuelProductKind.chew),
      carbs: _tenth(a.carbs),
      servingLabel: isDrink ? 'Flasche' : 'Portion',
      servingGrams: parts.fold(0.0, (sum, part) => sum + part.grams),
      volumeMilliliters: volume,
      fructose: _tenth(a.fructose),
      sodium: a.sodium.roundToDouble(),
      caffeine: a.caffeine.roundToDouble(),
      protein: _tenth(a.protein),
      fat: _tenth(a.fat),
      builtIn: true,
    );
  }

  /// Positionen fürs Tagebuch (je Lebensmittel mit BLS-Werten) für [servings] Portionen.
  List<MealItem> items(double servings) => [for (final part in parts) part.food.item(part.grams * servings)];

  static double _tenth(double value) => (value * 10).roundToDouble() / 10;
}

abstract final class FuelSnacks {
  static const spritzer = FuelSnack(
    id: 'spritzer',
    name: 'Apfelschorle mit einer Prise Salz',
    parts: [(food: FuelFoods.appleSpritzer, grams: 500), (food: FuelFoods.salt, grams: 1)],
    tip: 'Saft und Wasser 1 : 1, eine Prise Salz (1 g ≈ 380 mg Natrium) – schluckweise alle 10–15 min.',
  );
  static const cola = FuelSnack(
    id: 'cola',
    name: 'Cola (250 ml)',
    parts: [(food: FuelFoods.cola, grams: 250)],
    tip: 'Eher im letzten Drittel, mit etwas Kohlensäure-Verlust (offen lassen) bekömmlicher; enthält Koffein.',
  );
  static const banana = FuelSnack(
    id: 'banana',
    name: 'Banane',
    parts: [(food: FuelFoods.banana, grams: 120)],
    tip: 'Halbiert und angeschält in der Trikottasche; eher in ruhigen Phasen.',
    heavy: true,
  );
  static const dates = FuelSnack(
    id: 'dates',
    name: 'Datteln (3 Stück)',
    parts: [(food: FuelFoods.dates, grams: 24)],
    tip: 'Entsteint in einem kleinen Beutel; gut kauen und mit Wasser nachspülen.',
  );
  static const gummies = FuelSnack(
    id: 'gummies',
    name: 'Fruchtgummi (Handvoll)',
    parts: [(food: FuelFoods.gummies, grams: 25)],
    tip: 'Im Zipbeutel; über ein paar Minuten verteilt kauen, mit Wasser.',
  );
  static const honey = FuelSnack(
    id: 'honey',
    name: 'Honig im Fläschchen (1 EL)',
    parts: [(food: FuelFoods.honey, grams: 20)],
    tip: 'Wie ein Gel: in einer kleinen Quetschflasche, mit 150–200 ml Wasser nachspülen.',
  );
  static const pretzels = FuelSnack(
    id: 'pretzels',
    name: 'Salzbrezeln (Handvoll)',
    parts: [(food: FuelFoods.pretzels, grams: 30)],
    tip: 'Bringen viel Natrium; trocken – nur mit Getränk, eher auf dem Rad.',
    heavy: true,
  );
  static const jamToast = FuelSnack(
    id: 'jamToast',
    name: 'Toast mit Konfitüre (1 Scheibe)',
    parts: [(food: FuelFoods.toast, grams: 25), (food: FuelFoods.jam, grams: 20)],
    tip: 'Zusammengeklappt in Alufolie, in mundgerechten Stücken; auf dem Rad in der ersten Hälfte.',
    heavy: true,
  );
  static const riceCakes = FuelSnack(
    id: 'riceCakes',
    name: 'Reiswaffeln mit Honig (2 Stück)',
    parts: [(food: FuelFoods.riceCakes, grams: 16), (food: FuelFoods.honey, grams: 20)],
    tip: 'Mit Honig bestrichen und zusammengeklappt in Folie; bröselt wenig.',
    heavy: true,
  );

  static const all = [spritzer, cola, banana, dates, gummies, honey, pretzels, jamToast, riceCakes];

  static FuelSnack? byProductId(String id) => all.firstWhereOrNull((snack) => snack.productId == id);

  /// Übliche Auswahl je Sportart (Getränk zuerst).
  static List<FuelSnack> defaults(FuelSport sport) => switch (sport) {
    FuelSport.run => const [spritzer, gummies, dates, honey],
    FuelSport.bike => const [spritzer, banana, jamToast, pretzels, dates],
    FuelSport.swim => const [spritzer, banana],
    FuelSport.triathlon => const [spritzer, banana, pretzels, gummies],
    FuelSport.hybrid => const [spritzer, gummies, dates],
    FuelSport.strength => const [spritzer],
  };

  /// Auswahl für den Plan: übliche Snacks; mit „nur was ich zu Hause habe“ die verfügbaren, sonst alle verfügbaren
  /// passenden Snacks (dann deckt der Plan den Bedarf ggf. nur annähernd).
  static List<FuelSnack> choose(FuelSport sport, {Set<String>? home}) {
    final preferred = defaults(sport);
    if (home == null) return preferred;
    final available = [
      for (final snack in preferred)
        if (snack.availableWith(home)) snack,
    ];
    final others = [
      for (final snack in all)
        if (!preferred.contains(snack) && snack.availableWith(home) && snack != cola) snack,
    ];
    return [...available, ...others];
  }
}

/// Rolle eines Teils einer Mahlzeit beim Skalieren.
enum FuelMealRole { carbs, protein, fixed }

final class FuelMealPart {
  const FuelMealPart(this.food, this.role, {this.min = 0, required this.max, this.step = 1});

  final FuelFood food;
  final FuelMealRole role;

  /// Portionen (in Portionen des Lebensmittels).
  final double min;
  final double max;
  final double step;
}

/// Wann eine Mahlzeit passt.
enum FuelMealSlot {
  meal('Mahlzeit'),
  snack('Snack'),
  booster('Schnelle Kohlenhydrate'),
  post('Danach'),
  refuel('Schnell auffüllen');

  const FuelMealSlot(this.label);

  final String label;
}

final class FuelMealTemplate {
  const FuelMealTemplate(this.id, this.name, this.slots, this.parts);

  final String id;
  final String name;
  final Set<FuelMealSlot> slots;
  final List<FuelMealPart> parts;
}

/// Ein konkreter Vorschlag: Lebensmittel mit Portionen, was er liefert und wie gut er das Ziel trifft.
final class FuelMealSuggestion {
  const FuelMealSuggestion({
    required this.template,
    required this.portions,
    required this.amounts,
    required this.target,
    required this.missing,
  });

  final FuelMealTemplate template;

  /// Lebensmittel → Portionen (nur > 0).
  final Map<FuelFood, double> portions;
  final FuelAmounts amounts;
  final FuelAmounts target;

  /// Lebensmittel, die laut „Zuhause“ fehlen.
  final List<FuelFood> missing;

  double? get carbCoverage => target.carbs <= 0 ? null : amounts.carbs / target.carbs;
  double? get proteinCoverage => target.protein <= 0 ? null : amounts.protein / target.protein;

  bool get isComplete => missing.isEmpty;

  /// Trifft die Kohlenhydrate auf ±15 %.
  bool get covers => (carbCoverage ?? 1) >= 0.85 && (carbCoverage ?? 1) <= 1.15;

  /// „3 Scheiben Toastbrot · 2 EL Honig · 1 Banane“.
  String get text =>
      [for (final MapEntry(key: food, value: count) in portions.entries) FuelMeals.amountText(food, count)].join(' · ');

  List<MealItem> get items => [
    for (final MapEntry(key: food, value: count) in portions.entries) food.item(food.portionGrams * count),
  ];
}

/// Vorschläge mit herkömmlichen Lebensmitteln für Mahlzeiten vorher und danach (Spezifikation 10.2).
abstract final class FuelMeals {
  static const templates = [
    FuelMealTemplate(
      'toastHoney',
      'Toast mit Honig, Banane und Saft',
      {FuelMealSlot.meal},
      [
        FuelMealPart(FuelFoods.toast, FuelMealRole.carbs, min: 2, max: 8),
        FuelMealPart(FuelFoods.honey, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.appleJuice, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.skyr, FuelMealRole.protein, max: 1),
      ],
    ),
    FuelMealTemplate(
      'porridge',
      'Haferbrei mit Banane und Honig',
      {FuelMealSlot.meal},
      [
        FuelMealPart(FuelFoods.oats, FuelMealRole.carbs, min: 1, max: 2),
        FuelMealPart(FuelFoods.milk, FuelMealRole.protein, min: 1, max: 2),
        FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.honey, FuelMealRole.carbs, max: 4),
        FuelMealPart(FuelFoods.orangeJuice, FuelMealRole.carbs, max: 2),
      ],
    ),
    FuelMealTemplate(
      'rollsJam',
      'Brötchen mit Konfitüre und Ei',
      {FuelMealSlot.meal},
      [
        FuelMealPart(FuelFoods.roll, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.jam, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.egg, FuelMealRole.protein, max: 2),
        FuelMealPart(FuelFoods.orangeJuice, FuelMealRole.carbs, max: 2),
      ],
    ),
    FuelMealTemplate(
      'riceMilk',
      'Milchreis mit Banane',
      {FuelMealSlot.meal, FuelMealSlot.post},
      [
        FuelMealPart(FuelFoods.riceMilk, FuelMealRole.carbs, min: 1, max: 3),
        FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.skyr, FuelMealRole.protein, max: 2),
      ],
    ),
    FuelMealTemplate(
      'banana',
      'Banane',
      {FuelMealSlot.snack, FuelMealSlot.booster},
      [FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, min: 0.5, max: 3, step: 0.5)],
    ),
    FuelMealTemplate(
      'riceCakesHoney',
      'Reiswaffeln mit Honig',
      {FuelMealSlot.snack, FuelMealSlot.refuel},
      [
        FuelMealPart(FuelFoods.riceCakes, FuelMealRole.carbs, min: 2, max: 8),
        FuelMealPart(FuelFoods.honey, FuelMealRole.carbs, min: 1, max: 3),
      ],
    ),
    FuelMealTemplate(
      'toastJam',
      'Toast mit Konfitüre',
      {FuelMealSlot.snack, FuelMealSlot.refuel},
      [
        FuelMealPart(FuelFoods.toast, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.jam, FuelMealRole.carbs, min: 1, max: 4),
      ],
    ),
    FuelMealTemplate(
      'rusk',
      'Zwieback',
      {FuelMealSlot.snack},
      [FuelMealPart(FuelFoods.rusk, FuelMealRole.carbs, min: 2, max: 8)],
    ),
    FuelMealTemplate(
      'dates',
      'Datteln',
      {FuelMealSlot.booster},
      [FuelMealPart(FuelFoods.dates, FuelMealRole.carbs, min: 2, max: 6)],
    ),
    FuelMealTemplate(
      'gummies',
      'Fruchtgummi',
      {FuelMealSlot.booster},
      [FuelMealPart(FuelFoods.gummies, FuelMealRole.carbs, min: 0.5, max: 2, step: 0.5)],
    ),
    FuelMealTemplate(
      'honey',
      'Honig',
      {FuelMealSlot.booster},
      [FuelMealPart(FuelFoods.honey, FuelMealRole.carbs, min: 1, max: 3)],
    ),
    FuelMealTemplate(
      'bananaMilk',
      'Bananenmilch mit Haferflocken',
      {FuelMealSlot.post},
      [
        FuelMealPart(FuelFoods.milk, FuelMealRole.protein, min: 1, max: 3),
        FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, min: 1, max: 3),
        FuelMealPart(FuelFoods.oats, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.honey, FuelMealRole.carbs, max: 3),
      ],
    ),
    FuelMealTemplate(
      'pastaChicken',
      'Nudeln mit Hähnchen',
      {FuelMealSlot.post},
      [
        FuelMealPart(FuelFoods.pasta, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.chicken, FuelMealRole.protein, max: 2),
        FuelMealPart(FuelFoods.appleJuice, FuelMealRole.carbs, max: 2),
      ],
    ),
    FuelMealTemplate(
      'riceTuna',
      'Reis mit Thunfisch',
      {FuelMealSlot.post},
      [
        FuelMealPart(FuelFoods.rice, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.tuna, FuelMealRole.protein, max: 2),
        FuelMealPart(FuelFoods.orangeJuice, FuelMealRole.carbs, max: 2),
      ],
    ),
    FuelMealTemplate(
      'skyrOats',
      'Skyr mit Haferflocken, Banane und Honig',
      {FuelMealSlot.post},
      [
        FuelMealPart(FuelFoods.skyr, FuelMealRole.protein, min: 1, max: 3),
        FuelMealPart(FuelFoods.oats, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, max: 2),
        FuelMealPart(FuelFoods.honey, FuelMealRole.carbs, max: 4),
      ],
    ),
    FuelMealTemplate(
      'potatoesQuark',
      'Kartoffeln mit Quark',
      {FuelMealSlot.post},
      [
        FuelMealPart(FuelFoods.potatoes, FuelMealRole.carbs, min: 1, max: 4),
        FuelMealPart(FuelFoods.quark, FuelMealRole.protein, max: 2),
        FuelMealPart(FuelFoods.appleJuice, FuelMealRole.carbs, max: 2),
      ],
    ),
    FuelMealTemplate(
      'juiceRiceCakes',
      'Saft und Reiswaffeln',
      {FuelMealSlot.refuel},
      [
        FuelMealPart(FuelFoods.appleJuice, FuelMealRole.carbs, min: 1, max: 3),
        FuelMealPart(FuelFoods.riceCakes, FuelMealRole.carbs, max: 6),
      ],
    ),
    FuelMealTemplate(
      'bananaJuice',
      'Banane und Saft',
      {FuelMealSlot.refuel, FuelMealSlot.snack},
      [
        FuelMealPart(FuelFoods.banana, FuelMealRole.carbs, min: 1, max: 3),
        FuelMealPart(FuelFoods.orangeJuice, FuelMealRole.carbs, max: 2),
      ],
    ),
  ];

  /// Für welchen Zeitpunkt? `null` = keine Mahlzeit (Wasser, Koffein).
  static FuelMealSlot? slotOf(FuelStep step) => switch (step.phase) {
    FuelPhase.intra => null,
    FuelPhase.pre when step.amounts.carbs <= 0 => null,
    FuelPhase.pre =>
      step.minute <= -120 ? FuelMealSlot.meal : (step.minute <= -60 ? FuelMealSlot.snack : FuelMealSlot.booster),
    FuelPhase.post => step.title == 'Regenerationsmahlzeit' ? FuelMealSlot.post : FuelMealSlot.refuel,
  };

  /// Bis zu [limit] Vorschläge, beste zuerst: vollständig vorhandene vor solchen mit fehlenden Zutaten, dann die
  /// nach Kohlenhydraten (und Protein) genaueren. [home] `null` = keine Einschränkung.
  static List<FuelMealSuggestion> suggest(FuelStep step, {Set<String>? home, int limit = 3}) {
    final slot = slotOf(step);
    if (slot == null) return const [];
    final target = FuelAmounts(carbs: step.amounts.carbs, protein: step.amounts.protein);
    final fitting = [
      for (final template in templates)
        if (template.slots.contains(slot)) template,
    ];
    final suggestions = [for (final template in fitting) compose(template, target, home: home)];
    // Nur mit Vorhandenem: zusätzlich alles Passende, was da ist, kombiniert – deckt oft am meisten ab.
    if (home != null) {
      final parts = <FuelFood, FuelMealPart>{};
      for (final part in fitting.expand((template) => template.parts)) {
        if (!part.food.alwaysAtHome && !home.contains(part.food.id)) continue;
        final known = parts[part.food];
        if (known == null || part.max > known.max) {
          parts[part.food] = FuelMealPart(part.food, part.role, max: part.max, step: part.step);
        }
      }
      if (parts.isNotEmpty) {
        suggestions.add(
          compose(
            FuelMealTemplate('home', 'Aus dem, was du da hast', {slot}, parts.values.toList()),
            target,
            home: home,
          ),
        );
      }
    }
    double score(FuelMealSuggestion x) {
      final carbs = (1 - (x.carbCoverage ?? 1)).abs();
      final protein = target.protein <= 0 ? 0.0 : math.max(0.0, 1 - (x.proteinCoverage ?? 1)) * 0.5;
      return carbs + protein + (x.isComplete ? 0 : 1);
    }

    suggestions.sort((a, b) => score(a).compareTo(score(b)));
    // Kaum brauchbare Vorschläge (unter 50 %) nur, wenn es nichts Besseres gibt.
    final useful = [
      for (final x in suggestions)
        if ((x.carbCoverage ?? 1) >= 0.5) x,
    ];
    return (useful.isEmpty ? suggestions.take(1) : useful.take(limit)).toList();
  }

  /// Skaliert eine Vorlage auf das Ziel: zuerst Protein, dann Kohlenhydrate schrittweise mit dem Teil, der die
  /// Abweichung am stärksten verringert. Mit [home] bleiben fehlende Lebensmittel bei 0, wo möglich.
  static FuelMealSuggestion compose(FuelMealTemplate template, FuelAmounts target, {Set<String>? home}) {
    bool available(FuelFood food) => home == null || food.alwaysAtHome || home.contains(food.id);
    final portions = <FuelMealPart, double>{
      // Was zu Hause fehlt, fällt weg – der Vorschlag deckt dann ggf. nur annähernd.
      for (final part in template.parts) part: available(part.food) ? part.min : 0,
    };
    FuelAmounts total() => FuelAmounts.sum([
      for (final MapEntry(:key, :value) in portions.entries) key.food.amounts(key.food.portionGrams * value),
    ]);
    bool canGrow(FuelMealPart part) => available(part.food) && portions[part]! + part.step <= part.max + 1e-9;

    if (target.protein > 0) {
      for (final part in template.parts.where((p) => p.role == FuelMealRole.protein)) {
        while (canGrow(part)) {
          final perStep = part.food.amounts(part.food.portionGrams * part.step).protein;
          if (total().protein + perStep / 2 > target.protein) break;
          portions[part] = portions[part]! + part.step;
        }
      }
    }
    // Gleichmäßig wachsen: unter den Teilen, die die Abweichung verringern, der bisher am wenigsten ausgeschöpfte.
    double fill(FuelMealPart part) => part.max <= part.min ? 1 : (portions[part]! - part.min) / (part.max - part.min);
    while (true) {
      final gap = (target.carbs - total().carbs).abs();
      FuelMealPart? best;
      for (final part in template.parts.where((p) => p.role == FuelMealRole.carbs && canGrow(p))) {
        final added = part.food.amounts(part.food.portionGrams * part.step).carbs;
        final next = (target.carbs - total().carbs - added).abs();
        if (next >= gap - 0.01) continue;
        if (best == null || fill(part) < fill(best) - 1e-9) best = part;
      }
      if (best == null) break;
      portions[best] = portions[best]! + best.step;
    }
    final used = {
      for (final MapEntry(:key, :value) in portions.entries)
        if (value > 0) key.food: value,
    };
    return FuelMealSuggestion(
      template: template,
      portions: used,
      amounts: total(),
      target: target,
      missing: [
        for (final food in used.keys)
          if (!available(food)) food,
      ],
    );
  }

  /// „3 Scheiben Toastbrot“, „½ Banane“, „2 Gläser (250 ml) Apfelsaft“.
  static String amountText(FuelFood food, double count) {
    final number = count == 0.5
        ? '½'
        : count == count.roundToDouble()
        ? '${count.round()}'
        : '$count'.replaceAll('.', ',');
    final words = food.portion.split(' ');
    final unit = count > 1 ? (_plural[words.first] ?? words.first) : words.first;
    final portion = [unit, ...words.skip(1)].join(' ');
    // Zählbares heißt wie die Portion: „2 Bananen“, „3 Datteln“.
    if (_countable.contains(words.first)) return '$number $portion';
    return '$number $portion ${food.name}';
  }

  static const _countable = {'Banane', 'Ei', 'Brötchen', 'Dattel'};

  static const _plural = {
    'Banane': 'Bananen',
    'Ei': 'Eier',
    'Dattel': 'Datteln',
    'Scheibe': 'Scheiben',
    'Waffel': 'Waffeln',
    'Glas': 'Gläser',
    'Portion': 'Portionen',
    'Dose': 'Dosen',
    'Flasche': 'Flaschen',
    'Prise': 'Prisen',
  };
}

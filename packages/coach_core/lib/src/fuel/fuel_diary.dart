// Fuel Planner: Plan → Einträge fürs Ernährungstagebuch (Spezifikation 7). Vorher und danach als Platzhalter
// „(Plan)“ mit den Makros plus Wasser, unterwegs mit den echten Produkten und Mengen. Platzhalter werden ersetzt,
// sobald die echte Mahlzeit eingetragen wird – so zählt nichts doppelt.
import 'dart:math' as math;

import '../nutrition/meal.dart';
import '../nutrition/nutrient.dart';
import 'fuel_plan.dart';
import 'fuel_product.dart';

final class FuelDiaryEntry {
  const FuelDiaryEntry({required this.phase, required this.title, required this.minute, required this.items});

  final FuelPhase phase;
  final String title;

  /// Zeitpunkt in Minuten ab Start der Einheit (vorher negativ).
  final int minute;
  final List<MealItem> items;

  NutrientValues get totals => NutritionSummary.totals(items);
}

abstract final class FuelDiary {
  /// Endung des Platzhalters („Vor dem Training (Plan)“).
  static const placeholderSuffix = '(Plan)';

  /// Eine echte Mahlzeit ersetzt einen Platzhalter, wenn sie höchstens so weit entfernt liegt …
  static const replaceWindow = Duration(minutes: 90);

  /// … und mindestens so viel Energie hat (sonst wäre es nur ein Kaffee): 100 kcal bzw. 30 % des Platzhalters.
  static const replaceMinKilocalories = 100.0;
  static const replaceMinShare = 0.3;

  static final _marker = RegExp(r'\[fuel:([^:\]]+):(pre|intra|post)\]');

  /// Hinweis der Mahlzeit mit Markierung: erkennt Einträge eines Plans wieder (erneut übernehmen ersetzt sie).
  static String hint(String planID, FuelPhase phase) => phase == FuelPhase.intra
      ? 'Aus dem Fuel Planner. [fuel:$planID:${phase.name}]'
      : 'Platzhalter aus dem Fuel Planner – wird ersetzt, sobald du deine echte Mahlzeit einträgst. '
            '[fuel:$planID:${phase.name}]';

  /// Hinweis eines bearbeiteten Eintrags (ohne Markierung: wird weder ersetzt noch erneut überschrieben).
  static const editedHint = 'Aus dem Fuel Planner, von dir angepasst.';

  /// Hinweis ohne die technische Markierung (für die Anzeige).
  static String visibleHint(String hint) => hint.replaceAll(_marker, '').trim();

  /// Plan und Phase aus dem Hinweis; `null` ohne Markierung.
  static ({String planID, FuelPhase phase})? marker(String hint) {
    final match = _marker.firstMatch(hint);
    if (match == null) return null;
    return (planID: match.group(1)!, phase: FuelPhase.values.byName(match.group(2)!));
  }

  /// Noch ein Platzhalter (vorher/danach) und nicht schon durch echte Lebensmittel ersetzt?
  static bool isPlaceholder({required String hint, required List<MealItem> items}) {
    final found = marker(hint);
    return found != null &&
        found.phase != FuelPhase.intra &&
        items.any((item) => item.name.endsWith(placeholderSuffix));
  }

  /// Ersetzt die echte Mahlzeit den Platzhalter (gleicher Tag vorausgesetzt)?
  static bool replaces({
    required DateTime placeholderAt,
    required double placeholderKilocalories,
    required DateTime mealAt,
    required double mealKilocalories,
    bool mealIsWaterOnly = false,
  }) =>
      !mealIsWaterOnly &&
      mealAt.difference(placeholderAt).abs() <= replaceWindow &&
      mealKilocalories >= math.max(replaceMinKilocalories, replaceMinShare * placeholderKilocalories);

  static String title(FuelPhase phase) => switch (phase) {
    FuelPhase.pre => 'Vor dem Training',
    FuelPhase.intra => 'Verpflegung unterwegs',
    FuelPhase.post => 'Nach dem Training',
  };

  static List<FuelDiaryEntry> entries(FuelPlan plan, {Set<FuelPhase> phases = const {...FuelPhase.values}}) => [
    for (final phase in FuelPhase.values)
      if (phases.contains(phase)) ?entry(plan, phase),
  ];

  static FuelDiaryEntry? entry(FuelPlan plan, FuelPhase phase) {
    final steps = plan.steps(phase);
    if (steps.isEmpty) return null;
    final items = phase == FuelPhase.intra ? _intraItems(steps) : _macroItems(plan.total(phase), phase);
    if (items.isEmpty) return null;
    final minute = switch (phase) {
      FuelPhase.pre => steps.first.minute,
      FuelPhase.intra => 0,
      FuelPhase.post => plan.scenario.minutes,
    };
    return FuelDiaryEntry(phase: phase, title: title(phase), minute: minute, items: items);
  }

  static List<MealItem> _macroItems(FuelAmounts amounts, FuelPhase phase) => [
    if (amounts.kilocalories > 0)
      MealItem(
        name: '${title(phase)} $placeholderSuffix',
        grams: 100,
        amountText: '1 Portion',
        portion: const Portion('Portion', 100),
        source: MealItemSource.manual,
        per100g: NutrientValues({
          Nutrient.kcal: amounts.kilocalories.roundToDouble(),
          Nutrient.carbs: amounts.carbs,
          Nutrient.protein: amounts.protein,
          Nutrient.fat: amounts.fat,
          if (amounts.sodium > 0) Nutrient.sodium: amounts.sodium,
        }),
      ),
    if (amounts.fluid > 0) MealItem.water(milliliters: amounts.fluid),
  ];

  static List<MealItem> _intraItems(List<FuelStep> steps) {
    final servings = <FuelProduct, double>{};
    var water = 0.0;
    for (final step in steps) {
      water += step.water;
      for (final portion in step.portions) {
        servings[portion.product] = (servings[portion.product] ?? 0) + portion.servings;
      }
    }
    return [
      for (final MapEntry(key: product, value: count) in servings.entries) _productItem(product, count),
      if (water > 0) MealItem.water(milliliters: water),
    ];
  }

  static MealItem _productItem(FuelProduct product, double servings) {
    final amounts = FuelAmounts.ofProduct(product, servings);
    final perServing = product.isDrink
        ? product.volumeMilliliters
        : (product.servingGrams > 0 ? product.servingGrams : 1);
    final grams = ((perServing * servings) * 10).roundToDouble() / 10;
    double per100(double value) => grams <= 0 ? 0 : value / grams * 100;
    return MealItem(
      name: product.name,
      grams: grams,
      isDrink: product.isDrink,
      source: MealItemSource.manual,
      group: 'Sportnahrung',
      portion: product.isDrink ? null : Portion(product.serving, perServing.toDouble()),
      per100g: NutrientValues({
        Nutrient.kcal: per100(amounts.kilocalories),
        Nutrient.carbs: per100(amounts.carbs),
        Nutrient.protein: per100(amounts.protein),
        Nutrient.fat: per100(amounts.fat),
        if (amounts.sodium > 0) Nutrient.sodium: per100(amounts.sodium),
      }),
    );
  }
}

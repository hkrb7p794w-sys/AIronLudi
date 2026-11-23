// Fuel Planner: Plan → Einträge fürs Ernährungstagebuch (Spezifikation 7). Vorher und danach als Makro-Eintrag
// „(Plan)“ plus Wasser, unterwegs mit den echten Produkten und Mengen.
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
        name: '${title(phase)} (Plan)',
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

import 'hydration.dart';
import 'meal.dart';
import 'nutrient.dart';

/// Ist-Werte eines Tages (oder einer Mahlzeit) mit Angabe, wie vollständig sie sind.
///
/// Fehlende Werte sind unbekannt, nicht 0: Hat eine Position keinen Eisenwert (Open Food Facts nennt oft nur die
/// Pflichtangaben), ist die Summe eine Untergrenze. Hat keine Position einen Wert, ist der Nährstoff unbekannt – die
/// App darf dann keinen Mangel anzeigen.
final class FoodIntake {
  const FoodIntake({required this.totals, required this.missing, required this.itemCount});

  static final empty = FoodIntake(totals: NutrientValues(), missing: const {}, itemCount: 0);

  /// Summe aller Positionen (Menge × Wert je 100 g / 100). Flüssigkeit wie im Wasser-Ring (`Hydration`).
  final NutrientValues totals;

  /// Zahl der Positionen ohne Wert je Nährstoff (nur Nährstoffe mit mindestens einer Lücke).
  final Map<Nutrient, int> missing;

  /// Zahl der gezählten Positionen (Menge > 0).
  final int itemCount;

  int missingCount(Nutrient nutrient) => missing[nutrient] ?? 0;

  /// Keine Position hat einen Wert: unbekannt statt 0.
  bool isUnknown(Nutrient nutrient) => itemCount > 0 && missingCount(nutrient) >= itemCount;

  /// Einige Positionen ohne Wert: die Summe ist eine Untergrenze.
  bool isPartial(Nutrient nutrient) => missingCount(nutrient) > 0 && !isUnknown(nutrient);
}

/// Summiert Positionen zu Ist-Werten (Tag, Mahlzeit). Einziger Weg für die Tagessumme, damit Übersicht, Widget und
/// Coach dieselben Zahlen zeigen.
abstract final class FoodAggregation {
  static FoodIntake of(Iterable<MealItem> items) {
    final counted = items.where((item) => item.grams > 0).toList();
    if (counted.isEmpty) return FoodIntake.empty;
    final totals = NutritionSummary.totals(counted);
    // Getränke ohne Wasserwert zählen mit ihrer Menge (1 ml ≈ 1 g), wie im Wasser-Ring.
    totals[Nutrient.water] = Hydration.total(counted).total;
    final missing = <Nutrient, int>{};
    for (final nutrient in Nutrient.values) {
      final count = counted.where((item) {
        if (item.per100g[nutrient] != null) return false;
        return !(nutrient == Nutrient.water && item.isDrink);
      }).length;
      if (count > 0) missing[nutrient] = count;
    }
    return FoodIntake(totals: totals, missing: missing, itemCount: counted.length);
  }
}

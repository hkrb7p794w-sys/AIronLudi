import 'hydration.dart';
import 'meal.dart';
import 'nutrient.dart';

/// Ist-Werte eines Tages (oder einer Mahlzeit) mit Angabe, wie vollständig sie sind.
///
/// Fehlende Werte sind unbekannt, nicht 0: Hat eine Position keinen Eisenwert (Open Food Facts nennt oft nur die
/// Pflichtangaben), ist die Summe eine Untergrenze. Hat keine Position einen Wert, ist der Nährstoff unbekannt – die
/// App darf dann keinen Mangel anzeigen.
final class FoodIntake {
  const FoodIntake({
    required this.totals,
    required this.missing,
    required this.itemCount,
    this.missingKilocalories = const {},
  });

  static final empty = FoodIntake(totals: NutrientValues(), missing: const {}, itemCount: 0);

  /// Anteil der Energie, den Positionen ohne Wert höchstens haben dürfen, damit eine Summe als vollständig gilt.
  static const completeShare = 0.1;

  /// Summe aller Positionen (Menge × Wert je 100 g / 100). Flüssigkeit wie im Wasser-Ring (`Hydration`).
  final NutrientValues totals;

  /// Zahl der Positionen ohne Wert je Nährstoff (nur Nährstoffe mit mindestens einer Lücke).
  final Map<Nutrient, int> missing;

  /// Gezählte Positionen (Menge > 0). Reines Wasser zählt nur bei der Flüssigkeit – es hat keine anderen Nährstoffe.
  final int itemCount;

  /// Energie der Positionen ohne Wert je Nährstoff.
  final Map<Nutrient, double> missingKilocalories;

  int missingCount(Nutrient nutrient) => missing[nutrient] ?? 0;

  /// Keine Position hat einen Wert: unbekannt statt 0.
  bool isUnknown(Nutrient nutrient) => itemCount > 0 && missingCount(nutrient) >= itemCount;

  /// Einige Positionen ohne Wert: die Summe ist eine Untergrenze.
  bool isPartial(Nutrient nutrient) => missingCount(nutrient) > 0 && !isUnknown(nutrient);

  /// Summen, die für Auswertungen über Tage (Lücken, Mittelwerte) taugen: Nährstoffe, deren fehlende Positionen
  /// zusammen mehr als 10 % der Energie ausmachen, fallen weg – eine Untergrenze würde sonst einen Mangel vortäuschen.
  NutrientValues get completeTotals {
    final result = totals.copy();
    final energy = totals[Nutrient.kcal] ?? 0;
    for (final nutrient in missing.keys) {
      if (nutrient == Nutrient.water) continue;
      final share = energy > 0 ? (missingKilocalories[nutrient] ?? 0) / energy : 1.0;
      if (isUnknown(nutrient) || share > completeShare) result[nutrient] = null;
    }
    return result;
  }
}

/// Summiert Positionen zu Ist-Werten (Tag, Mahlzeit). Einziger Weg für die Tagessumme, damit Übersicht, KI-Auswertung
/// und Lückenliste dieselben Zahlen nutzen.
abstract final class FoodAggregation {
  /// Wasser-Eintrag ohne weitere Nährwerte (Schnell-Eintrag „Wasser“).
  static bool isPlainWater(MealItem item) =>
      item.isDrink && item.per100g.values.keys.every((nutrient) => nutrient == Nutrient.water);

  static FoodIntake of(Iterable<MealItem> items) {
    final counted = items.where((item) => item.grams > 0).toList();
    if (counted.isEmpty) return FoodIntake.empty;
    final totals = NutritionSummary.totals(counted);
    // Getränke ohne Wasserwert zählen mit ihrer Menge (1 ml ≈ 1 g), wie im Wasser-Ring.
    totals[Nutrient.water] = Hydration.total(counted).total;
    final foods = counted.where((item) => !isPlainWater(item)).toList();
    final missing = <Nutrient, int>{};
    final missingKilocalories = <Nutrient, double>{};
    for (final nutrient in Nutrient.values) {
      final gaps = foods.where((item) {
        if (item.per100g[nutrient] != null) return false;
        return !(nutrient == Nutrient.water && item.isDrink);
      }).toList();
      if (gaps.isEmpty) continue;
      missing[nutrient] = gaps.length;
      missingKilocalories[nutrient] = gaps.fold(0.0, (sum, item) => sum + (item.amounts[Nutrient.kcal] ?? 0));
    }
    return FoodIntake(
      totals: totals,
      missing: missing,
      itemCount: foods.length,
      missingKilocalories: missingKilocalories,
    );
  }
}

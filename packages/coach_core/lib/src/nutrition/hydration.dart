import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';

/// Flüssigkeit eines Tages, getrennt nach Getränken und Essen.
final class HydrationTotal {
  const HydrationTotal({this.drinks = 0, this.food = 0});

  final double drinks;
  final double food;

  double get total => drinks + food;

  @override
  bool operator ==(Object other) => other is HydrationTotal && other.drinks == drinks && other.food == food;

  @override
  int get hashCode => Object.hash(drinks, food);

  @override
  String toString() => 'HydrationTotal(drinks: $drinks, food: $food)';
}

/// Flüssigkeit des Tages aus allem, was eingetragen ist: Getränke (Wasser, Kaffee, Saft, Milch …) und das Wasser in
/// Lebensmitteln (Suppe, Obst, Joghurt). Das Ziel von ~35 ml je kg (`NutritionPlanner`) entspricht der gesamten
/// Wasserzufuhr; laut EFSA (2010) stammen davon üblicherweise rund 20 % aus Lebensmitteln.
abstract final class Hydration {
  /// Wasser einer Position in ml: der Wasserwert je 100 g (BLS, KI, Open Food Facts) oder bei Getränken ohne Angabe
  /// die Menge selbst (1 ml ≈ 1 g). Lebensmittel ohne Angabe zählen nicht (keine Schätzung).
  static double milliliters(MealItem item) {
    final water = item.per100g[Nutrient.water];
    if (water != null) return (water < 0 ? 0 : water) * item.grams / 100;
    return item.isDrink ? (item.grams < 0 ? 0 : item.grams) : 0;
  }

  static HydrationTotal total(Iterable<MealItem> items) {
    var drinks = 0.0;
    var food = 0.0;
    for (final item in items) {
      if (item.isDrink) {
        drinks += milliliters(item);
      } else {
        food += milliliters(item);
      }
    }
    return HydrationTotal(drinks: drinks, food: food);
  }
}

/// Kalorienziel je Mahlzeit für Übersicht und Widget (wie gängige Ernährungs-Apps): Frühstück 25 %, Mittag 35 %,
/// Abend 30 %, Snacks 10 % der Tagesenergie. Eine Orientierung, keine Regel – gezählt wird der Tag.
abstract final class MealSplit {
  static const order = [MealCategory.breakfast, MealCategory.lunch, MealCategory.dinner, MealCategory.snack];

  static double share(MealCategory category) => switch (category) {
    MealCategory.breakfast => 0.25,
    MealCategory.lunch => 0.35,
    MealCategory.dinner => 0.30,
    MealCategory.snack || MealCategory.other => 0.10,
  };

  /// „Sonstiges“ zählt zu den Snacks.
  static MealCategory slot(MealCategory category) => category == MealCategory.other ? MealCategory.snack : category;

  static double? target(MealCategory category, {double? dayKilocalories}) =>
      dayKilocalories == null ? null : (dayKilocalories * share(slot(category))).roundToDouble();
}

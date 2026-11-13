import 'dart:math' as math;

import '../nutrition/hydration.dart';
import '../nutrition/meal_category.dart';
import 'widget_snapshot.dart';

/// Kopfzeile der Mahlzeiten-Anzeigen (Homescreen-Widget, Karte auf dem Sperrbildschirm): ein Satz, der zum Stand
/// des Tages passt – was eingetragen ist, was als Nächstes ansteht, wie viel übrig ist, wie die Serie steht.
/// Feste Regeln, keine KI. Kein Druck: nichts droht mit Verlust, und ohne Kalorienziel (z. B. gesperrte
/// Gewichtsziele) nennt der Satz keine Kalorien.
abstract final class MealHeadline {
  /// Kurze Namen, damit der Satz in eine Zeile passt.
  static String name(MealCategory category) => switch (category) {
    MealCategory.breakfast => 'Frühstück',
    MealCategory.lunch => 'Mittagessen',
    MealCategory.dinner => 'Abendessen',
    MealCategory.snack || MealCategory.other => 'Snack',
  };

  /// [meals]: Mahlzeiten des Tages in fester Reihenfolge (`MealSplit.order`). [kcalRemaining]: übrige Kalorien
  /// (negativ = darüber); `null` ohne Ziel. [streak]: Serie der Mahlzeiten. [hour]: Stunde des Tages (0–23), für den
  /// Satz vor dem ersten Eintrag.
  static String text({
    required List<WidgetMealPart> meals,
    required double? kcalRemaining,
    double? kcalTarget,
    required WidgetStreak? streak,
    required int hour,
  }) {
    final mains = meals
        .where((meal) => meal.category != MealCategory.snack && meal.category != MealCategory.other)
        .toList();
    final logged = meals.where((meal) => meal.kcal > 0).toList();
    final loggedMains = mains.where((meal) => meal.kcal > 0).toList();
    final days = streak?.days ?? 0;

    // Noch nichts eingetragen: nach Tageszeit, mit laufender Serie der nächste Tag.
    if (logged.isEmpty) {
      if (days >= 2) return 'Tag ${days + 1} der Serie – los geht’s';
      if (hour < 10) return 'Guten Morgen – Frühstück eintragen?';
      if (hour < 15) return 'Mittagessen eintragen?';
      if (hour < 21) return 'Heute noch nichts eingetragen';
      return 'Noch kurz den Tag eintragen?';
    }

    // Alle Hauptmahlzeiten eingetragen: Tagesbilanz.
    if (mains.isNotEmpty && loggedMains.length == mains.length) {
      if (kcalRemaining == null) {
        return days >= 3 ? 'Alles eingetragen – Tag $days der Serie' : 'Alles eingetragen – stark!';
      }
      final tolerance = math.max((kcalTarget ?? 2000) * 0.07, 100);
      if (kcalRemaining.abs() <= tolerance) return 'Tagesziel getroffen – stark!';
      if (kcalRemaining > 0) return 'Alles eingetragen · noch ${kcalRemaining.round()} kcal frei';
      return 'Alles eingetragen · ${(-kcalRemaining).round()} kcal über Ziel';
    }

    // Dazwischen: die nächste offene Hauptmahlzeit nach der zuletzt eingetragenen, sonst die erste offene.
    final lastIndex = mains.lastIndexWhere((meal) => meal.kcal > 0);
    WidgetMealPart? open;
    for (final meal in mains.skip(lastIndex + 1)) {
      if (meal.kcal <= 0) {
        open = meal;
        break;
      }
    }
    open ??= mains.where((meal) => meal.kcal <= 0).firstOrNull;
    if (open == null) {
      // Nur ein Snack eingetragen (keine Hauptmahlzeiten in der Liste).
      return 'Eingetragen – weiter so!';
    }
    final next = name(open.category);
    if (loggedMains.isEmpty) return 'Snack notiert – $next eintragen?';
    if (loggedMains.length == mains.length - 1) {
      if (kcalRemaining != null && kcalRemaining > 0) return 'Noch ${kcalRemaining.round()} kcal – $next fehlt';
      return 'Fast komplett – $next fehlt noch';
    }
    if (streak != null && streak.isRunning) return 'Tag ${streak.days} der Serie – $next steht an';
    return 'Guter Start – $next steht an';
  }

  /// Satz für einen Widget-Stand.
  static String forSnapshot(WidgetSnapshot snapshot, {required int hour}) {
    final nutrition = snapshot.nutrition;
    if (nutrition == null) return 'Mahlzeiten';
    final meals =
        nutrition.meals ??
        [for (final category in MealSplit.order) WidgetMealPart(category: category, kcal: 0, target: null)];
    return text(
      meals: meals,
      kcalRemaining: nutrition.kcalRemaining,
      kcalTarget: nutrition.kcalTarget,
      streak: snapshot.mealStreak,
      hour: hour,
    );
  }
}

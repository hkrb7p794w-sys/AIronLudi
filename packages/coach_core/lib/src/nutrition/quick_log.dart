import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import 'food_search.dart';
import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';

/// Eine gespeicherte Mahlzeit, unabhängig von der Datenbank (für Vorschläge, Suche und Wochenansicht).
final class MealEntry {
  const MealEntry({
    required this.day,
    required this.date,
    required this.category,
    required this.title,
    required this.items,
  });

  final CalendarDay day;
  final DateTime date;
  final MealCategory category;
  final String title;
  final List<MealItem> items;
}

/// Ein Vorschlag „wie immer“.
final class MealSuggestion {
  MealSuggestion({
    required this.id,
    required this.title,
    required this.category,
    required this.items,
    required this.count,
    required this.lastDate,
  });

  final String id;
  String title;
  final MealCategory category;
  List<MealItem> items;
  int count;
  DateTime lastDate;

  double get kilocalories => NutritionSummary.totals(items)[Nutrient.kcal] ?? 0;
}

int _byCountThenDate(MealSuggestion a, MealSuggestion b) {
  final byCount = b.count.compareTo(a.count);
  return byCount != 0 ? byCount : b.lastDate.compareTo(a.lastDate);
}

/// Schnell eintragen: Was isst die Person um diese Zeit meistens, was gab es gestern?
/// Wiederkehrendes Essen soll ein Tipp sein statt Suchen, Menge prüfen, Speichern.
abstract final class MealSuggestions {
  /// Gleiche Mahlzeit = gleiche Lebensmittel mit etwa gleicher Menge (auf 10 g gerundet).
  static String signature(Iterable<MealItem> items) =>
      (items.map((item) => '${FoodSearch.normalized(item.name)}@${(item.grams / 10).round()}').toList()..sort()).join(
        '|',
      );

  /// Häufigste Mahlzeiten dieser Kategorie aus den letzten [lookbackDays] Tagen; was heute schon in derselben
  /// Kategorie eingetragen ist, wird nicht noch einmal vorgeschlagen.
  static List<MealSuggestion> frequent(
    List<MealEntry> entries, {
    required MealCategory category,
    required CalendarDay today,
    int lookbackDays = 60,
    int limit = 5,
  }) {
    final start = today.adding(-lookbackDays);
    final loggedToday = {
      for (final entry in entries)
        if (entry.day == today && entry.category == category) signature(entry.items),
    };
    final groups = <String, MealSuggestion>{};
    for (final entry in entries) {
      if (entry.category != category || entry.day < start || entry.day >= today || entry.items.isEmpty) continue;
      final key = signature(entry.items);
      if (loggedToday.contains(key)) continue;
      final existing = groups[key];
      if (existing != null) {
        existing.count += 1;
        if (entry.date.isAfter(existing.lastDate)) {
          existing
            ..lastDate = entry.date
            ..title = entry.title
            ..items = entry.items;
        }
      } else {
        groups[key] = MealSuggestion(
          id: key,
          title: entry.title,
          category: category,
          items: entry.items,
          count: 1,
          lastDate: entry.date,
        );
      }
    }
    final sorted = groups.values.toList();
    mergeSort(sorted, compare: _byCountThenDate);
    return sorted.take(limit).toList();
  }

  /// Mahlzeiten von gestern in dieser Kategorie („wie gestern“).
  static List<MealEntry> yesterday(
    List<MealEntry> entries, {
    required MealCategory category,
    required CalendarDay today,
  }) {
    final day = today.adding(-1);
    final result = entries.where((entry) => entry.day == day && entry.category == category).toList();
    mergeSort(result, compare: (a, b) => a.date.compareTo(b.date));
    return result;
  }
}

/// Eine Zeile „noch übrig“.
final class BudgetLine {
  const BudgetLine({required this.nutrient, required this.actual, required this.target});

  final Nutrient nutrient;
  final double actual;
  final double target;

  Nutrient get id => nutrient;

  /// Positiv = noch übrig, negativ = darüber.
  double get remaining => target - actual;
  double get progress => target > 0 ? math.min(actual / target, 1) : 0;

  /// Bei Obergrenzen (Zucker, gesättigte Fette) ist „darüber“ ein Warnsignal, bei Energie ab 10 %.
  bool get isOver =>
      nutrient.isUpperLimit ? actual > target : actual > target * (nutrient == Nutrient.kcal ? 1.1 : 1.25);

  @override
  bool operator ==(Object other) =>
      other is BudgetLine && other.nutrient == nutrient && other.actual == actual && other.target == target;

  @override
  int get hashCode => Object.hash(nutrient, actual, target);
}

/// Was heute noch übrig ist – die Frage beim Essen ist „wie viel Protein fehlt noch?“, nicht „wie viel Prozent“.
abstract final class NutritionBudget {
  static const main = [Nutrient.protein, Nutrient.carbs, Nutrient.fat];

  static BudgetLine? line(Nutrient nutrient, {required NutrientValues targets, required NutrientValues totals}) {
    final target = targets[nutrient];
    if (target == null || target <= 0) return null;
    return BudgetLine(nutrient: nutrient, actual: totals[nutrient] ?? 0, target: target);
  }

  /// „noch 62 g“ bzw. „18 g drüber“.
  static String remainingText(BudgetLine line) {
    final amount = line.remaining.abs().round();
    return line.remaining >= 0 ? 'noch $amount ${line.nutrient.unit}' : '$amount ${line.nutrient.unit} drüber';
  }
}

/// Schnell-Einträge (Port der `MealItem`-Erweiterung aus `QuickLog.swift`).
extension QuickMealItem on MealItem {
  /// Schnell-Eintrag ohne Lebensmittel (z. B. Restaurant): die Werte gelten für die ganze Portion.
  static MealItem quick({
    String name = 'Schnell-Eintrag',
    required double kilocalories,
    double? protein,
    double? carbs,
    double? fat,
  }) {
    final values = NutrientValues({Nutrient.kcal: math.max(kilocalories, 0)});
    values[Nutrient.protein] = protein == null ? null : math.max(protein, 0);
    values[Nutrient.carbs] = carbs == null ? null : math.max(carbs, 0);
    values[Nutrient.fat] = fat == null ? null : math.max(fat, 0);
    // 100 g „Portion“: Nährwerte je 100 g = Werte der Portion.
    return MealItem(
      name: name,
      grams: 100,
      source: MealItemSource.manual,
      per100g: values,
      amountText: 'Schätzung',
      confidence: 'niedrig',
    );
  }

  bool get isQuickEstimate => source == MealItemSource.manual && amountText == 'Schätzung';
}

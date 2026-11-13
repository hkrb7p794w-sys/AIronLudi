import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../profile/plan_adjustments.dart';
import '../util/enum_codec.dart';
import '../util/text_prefix.dart';
import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';
import 'nutrition_settings.dart';
import 'quick_log.dart';
import 'recipe_plan.dart';

/// „Was esse ich jetzt?“ – drei Vorschläge passend zu dem, was heute noch übrig ist. Die KI schlägt Gerichte vor,
/// die App prüft Ernährungsweise und Allergene und skaliert die Mengen auf das Ziel dieser Mahlzeit.
abstract final class MealNow {
  /// Größte sinnvolle Mahlzeit; mehr Rest wird auf weitere Mahlzeiten verteilt.
  static const maximumKilocalories = 900.0;
  static const minimumKilocalories = 150.0;
  static const scaleLower = 0.5;
  static const scaleUpper = 1.6;

  /// Energieziel dieser Mahlzeit; `null`, wenn heute kaum noch etwas übrig ist.
  static double? targetKilocalories(double remaining) {
    if (remaining < minimumKilocalories) return null;
    return math.min(remaining, maximumKilocalories);
  }

  static Map<String, Object?> input({
    required NutrientValues remaining,
    required MealCategory category,
    required Diet diet,
    required RecipePreferences preferences,
    required List<String> pantry,
    required List<String> favorites,
  }) {
    final kcal = targetKilocalories(remaining[Nutrient.kcal] ?? 0) ?? minimumKilocalories;
    final share = kcal / math.max(remaining[Nutrient.kcal] ?? kcal, kcal);
    double grams(Nutrient nutrient) => math.max(0, ((remaining[nutrient] ?? 0) * share).roundToDouble());
    final allergens = preferences.allergens.toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue));
    return {
      'mahlzeit': category.rawValue,
      'kcal': kcal.roundToDouble(),
      'protein_g': grams(Nutrient.protein),
      'carbs_g': grams(Nutrient.carbs),
      'fat_g': grams(Nutrient.fat),
      'diet': diet.rawValue,
      'allergens': [for (final allergen in allergens) allergen.label],
      'dislikes': textPrefix(preferences.dislikes, 200),
      'maxMinutes': preferences.maxMinutes.toDouble(),
      'pantry': pantry.take(30).toList(),
      'favorites': favorites.take(15).toList(),
    };
  }

  /// Antwort `{"gerichte": [...]}` prüfen und auf das Ziel skalieren (auf 5 g gerundet).
  static ({List<Recipe> recipes, List<String> notes}) suggestions(
    JsonValue output, {
    required double targetKilocalories,
    required Diet diet,
    required Set<Allergen> allergens,
  }) {
    final notes = <String>[];
    final recipes = [
      for (final raw in output['gerichte']?.arrayValue ?? const <JsonValue>[])
        if (RecipePlanner.recipe(raw) case final recipe?
            when RecipePlanner.accept(recipe, diet: diet, allergens: allergens, notes: notes))
          scaled(recipe, targetKilocalories),
    ];
    return (recipes: recipes.take(3).toList(), notes: notes);
  }

  static Recipe scaled(Recipe recipe, double kcal) {
    final total = recipe.totals[Nutrient.kcal] ?? 0;
    if (total <= 0 || kcal <= 0) return recipe;
    final factor = (kcal / total).clamp(scaleLower, scaleUpper);
    return recipe.copy()..ingredients = RecipePlanner.scaledItems(recipe.ingredients, factor);
  }
}

/// Eigenes Rezept für Meal-Prep: Zutaten für den ganzen Topf, gekochtes Gewicht und Portionen. Eingetragen wird eine
/// Portion oder eine Menge in Gramm vom Topf; der Zähler zeigt, wie viele Portionen noch da sind.
final class OwnRecipe {
  OwnRecipe({
    String? id,
    required this.name,
    required this.ingredients,
    this.cookedGrams,
    int portions = 1,
    this.remainingPortions,
  }) : id = id ?? newUuid(),
       portions = math.max(portions, 1);

  /// Rezept aus einer gespeicherten Mahlzeit (eine Portion).
  factory OwnRecipe.fromMeal(String title, List<MealItem> items) => OwnRecipe(name: title, ingredients: items);

  final String id;
  String name;
  List<MealItem> ingredients;

  /// Gewicht des fertigen Gerichts (gekocht); `null` = Summe der Zutaten.
  double? cookedGrams;
  int portions;

  /// Noch übrige Portionen vom letzten Kochen; `null` = kein Vorrat.
  double? remainingPortions;

  double get totalGrams => switch (cookedGrams) {
    final cooked? when cooked > 0 => cooked,
    _ => ingredients.fold(0.0, (sum, item) => sum + item.grams),
  };

  NutrientValues get totals => NutritionSummary.totals(ingredients);

  /// Nährwerte je 100 g des fertigen Gerichts.
  NutrientValues get per100g => totalGrams > 0 ? totals.scaledToGrams(100 * 100 / totalGrams) : NutrientValues();

  /// Eine Position „Chili“ mit [grams] vom Topf (Standard: eine Portion).
  MealItem item({double? grams}) {
    final portionGrams = totalGrams / portions;
    return MealItem(
      name: name,
      grams: grams ?? portionGrams,
      source: MealItemSource.manual,
      per100g: per100g,
      portion: Portion('Portion', (portionGrams * 10).roundToDouble() / 10),
    );
  }

  /// Nach dem Eintragen: Vorrat um die gegessene Menge verringern.
  void consume(double grams) {
    final remaining = remainingPortions;
    if (remaining == null || totalGrams <= 0) return;
    final eaten = grams / (totalGrams / portions);
    remainingPortions = math.max(0, ((remaining - eaten) * 10).roundToDouble() / 10);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'ingredients': [for (final item in ingredients) item.toJson()],
    'cookedGrams': ?cookedGrams,
    'portions': portions,
    'remainingPortions': ?remainingPortions,
  };

  /// Wie das synthetisierte `Decodable` (ohne die Mindestzahl an Portionen, die gilt nur beim Anlegen).
  static OwnRecipe? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, name, portions) = (json['id'], json['name'], json['portions']);
    final ingredients = listStrict(json['ingredients'], MealItem.fromJson);
    if (id is! String || name is! String || portions is! int || ingredients == null) return null;
    final (cooked, remaining) = (json['cookedGrams'], json['remainingPortions']);
    if ((cooked != null && cooked is! num) || (remaining != null && remaining is! num)) return null;
    return OwnRecipe(
      id: id,
      name: name,
      ingredients: ingredients,
      cookedGrams: (cooked as num?)?.toDouble(),
      remainingPortions: (remaining as num?)?.toDouble(),
    )..portions = portions;
  }

  @override
  bool operator ==(Object other) =>
      other is OwnRecipe &&
      other.id == id &&
      other.name == name &&
      const ListEquality<MealItem>().equals(other.ingredients, ingredients) &&
      other.cookedGrams == cookedGrams &&
      other.portions == portions &&
      other.remainingPortions == remainingPortions;

  @override
  int get hashCode => Object.hash(id, name, cookedGrams, portions, remainingPortions);
}

/// Ein Tag der Ernährungswoche.
final class NutritionWeekDay {
  const NutritionWeekDay({
    required this.day,
    required this.kilocalories,
    required this.protein,
    required this.targetKilocalories,
    required this.targetProtein,
    required this.trained,
    required this.logged,
  });

  final CalendarDay day;
  final double kilocalories;
  final double protein;
  final double? targetKilocalories;
  final double? targetProtein;
  final bool trained;
  final bool logged;

  CalendarDay get id => day;
}

/// Zusammenfassung der Ernährungswoche.
final class NutritionWeekSummary {
  const NutritionWeekSummary({
    required this.days,
    required this.averageKilocalories,
    required this.averageTargetKilocalories,
    required this.averageProtein,
  });

  final List<NutritionWeekDay> days;

  /// Nur Tage mit Einträgen.
  final double? averageKilocalories;
  final double? averageTargetKilocalories;
  final double? averageProtein;
}

/// Woche auf einen Blick: Energie je Tag gegen das Ziel, Protein im Schnitt, Trainingstage.
abstract final class NutritionWeek {
  static NutritionWeekSummary summary({
    required List<MealEntry> entries,
    required CalendarDay monday,
    required Map<CalendarDay, NutrientValues> targets,
    required Set<CalendarDay> trainedDays,
    required CalendarDay today,
  }) {
    final days = <NutritionWeekDay>[];
    for (var offset = 0; offset < 7; offset++) {
      final day = monday.adding(offset);
      if (day > today) continue;
      final items = entries.where((entry) => entry.day == day).expand((entry) => entry.items).toList();
      final totals = NutritionSummary.totals(items);
      days.add(
        NutritionWeekDay(
          day: day,
          kilocalories: totals[Nutrient.kcal] ?? 0,
          protein: totals[Nutrient.protein] ?? 0,
          targetKilocalories: targets[day]?[Nutrient.kcal],
          targetProtein: targets[day]?[Nutrient.protein],
          trained: trainedDays.contains(day),
          logged: items.isNotEmpty,
        ),
      );
    }
    final logged = days.where((day) => day.logged).toList();
    double? average(List<double> values) =>
        values.isEmpty ? null : (values.fold(0.0, (sum, value) => sum + value) / values.length).roundToDouble();
    return NutritionWeekSummary(
      days: days,
      averageKilocalories: average([for (final day in logged) day.kilocalories]),
      averageTargetKilocalories: average([for (final day in logged) ?day.targetKilocalories]),
      averageProtein: average([for (final day in logged) day.protein]),
    );
  }
}

/// Abendliche Auswertung (Erweiterung von `ReminderPlanner` in Swift).
abstract final class NutritionReviewReminder {
  static const nutritionReviewHour = 20;

  /// Abends kurz Ernährung und Training auswerten (freiwillig, Standard aus).
  static List<ScheduledNote> nutritionReview({
    required CalendarDay today,
    required int minutesNow,
    int hour = nutritionReviewHour,
    int days = 7,
  }) => [
    for (var offset = 0; offset < math.max(days, 1); offset++)
      if (!(offset == 0 && minutesNow >= hour * 60))
        ScheduledNote(
          kind: ScheduledNoteKind.nutritionReview,
          day: today.adding(offset),
          hour: hour,
          minute: 0,
          title: 'Tag auswerten',
          body: 'Kurz schauen: Hat das Essen heute zum Training gepasst? Fehlt noch Protein?',
        ),
  ];
}

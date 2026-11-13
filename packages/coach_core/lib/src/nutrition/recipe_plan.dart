import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/coaching_note.dart';
import '../json/json_value.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';
import '../util/swift_date.dart';
import '../util/text_prefix.dart';
import 'food_search.dart';
import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';
import 'nutrition_planner.dart';
import 'nutrition_settings.dart';

final _nonLetter = RegExp(r'[^\p{L}]+', unicode: true);

/// Allergene und Unverträglichkeiten (Auswahl der 14 kennzeichnungspflichtigen Allergene der EU-LMIV).
enum Allergen implements RawEnum {
  gluten('Gluten'),
  lactose('Laktose / Milch'),
  nuts('Schalenfrüchte (Nüsse)'),
  peanuts('Erdnüsse'),
  egg('Ei'),
  soy('Soja'),
  fish('Fisch'),
  shellfish('Krebstiere und Weichtiere'),
  sesame('Sesam');

  const Allergen(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;
}

List<Allergen> _sortedAllergens(Iterable<Allergen> allergens) =>
    allergens.toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue));

/// Wünsche für die Rezeptideen.
final class RecipePreferences {
  RecipePreferences({
    Set<Allergen>? allergens,
    this.dislikes = '',
    this.maxMinutes = 30,
    this.snacks = true,
    this.servings = 1,
    this.mealPrep = false,
  }) : allergens = allergens ?? {};

  Set<Allergen> allergens;

  /// Freitext, z. B. „keine Pilze, wenig Koriander“.
  String dislikes;

  /// Höchstens so viele Minuten Zubereitung pro Gericht.
  int maxMinutes;

  /// Zusätzlich ein Snack pro Tag.
  bool snacks;

  /// Für wie viele Personen eingekauft wird.
  int servings;

  /// Abends für den nächsten Mittag mitkochen.
  bool mealPrep;

  Map<String, Object?> toJson() => {
    'allergens': [for (final allergen in _sortedAllergens(allergens)) allergen.rawValue],
    'dislikes': dislikes,
    'maxMinutes': maxMinutes,
    'snacks': snacks,
    'servings': servings,
    'mealPrep': mealPrep,
  };

  /// Tolerant wie in Swift: unlesbare Felder bekommen ihren Standard, mindestens eine Person.
  static RecipePreferences fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    final rawAllergens = map['allergens'];
    final allergens = enumListStrict(Allergen.values, rawAllergens)?.toSet() ?? <Allergen>{};
    final (dislikes, maxMinutes, snacks, servings, mealPrep) = (
      map['dislikes'],
      map['maxMinutes'],
      map['snacks'],
      map['servings'],
      map['mealPrep'],
    );
    return RecipePreferences(
      allergens: allergens,
      dislikes: dislikes is String ? dislikes : '',
      maxMinutes: maxMinutes is int ? maxMinutes : 30,
      snacks: snacks is bool ? snacks : true,
      servings: math.max(servings is int ? servings : 1, 1),
      mealPrep: mealPrep is bool ? mealPrep : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecipePreferences &&
      const SetEquality<Allergen>().equals(other.allergens, allergens) &&
      other.dislikes == dislikes &&
      other.maxMinutes == maxMinutes &&
      other.snacks == snacks &&
      other.servings == servings &&
      other.mealPrep == mealPrep;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(allergens), dislikes, maxMinutes, snacks, servings, mealPrep);
}

/// Ziele eines Tages der kommenden Woche, aus Wochenplan und Ernährungszielen (regelbasiert).
final class RecipeDayTarget {
  const RecipeDayTarget({
    required this.day,
    required this.sessions,
    required this.dayType,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory RecipeDayTarget.fromTargets({
    required CalendarDay day,
    required List<String> sessions,
    required NutritionTargets targets,
  }) => RecipeDayTarget(
    day: day,
    sessions: sessions,
    dayType: targets.dayType,
    kcal: targets.values[Nutrient.kcal] ?? 0,
    protein: targets.values[Nutrient.protein] ?? 0,
    carbs: targets.values[Nutrient.carbs] ?? 0,
    fat: targets.values[Nutrient.fat] ?? 0,
  );

  final CalendarDay day;
  final List<String> sessions;
  final DayType dayType;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  CalendarDay get id => day;

  @override
  bool operator ==(Object other) =>
      other is RecipeDayTarget &&
      other.day == day &&
      const ListEquality<String>().equals(other.sessions, sessions) &&
      other.dayType == dayType &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(day, dayType, kcal, protein, carbs, fat);
}

/// Ein Rezept: Zutaten mit Menge und Nährwerten je 100 g (KI-Schätzung wie bei der Mahlzeiten-Analyse).
final class Recipe {
  Recipe({
    String? id,
    required this.meal,
    required this.title,
    required this.minutes,
    required this.ingredients,
    required this.steps,
  }) : id = id ?? newUuid();

  final String id;
  MealCategory meal;
  String title;
  int minutes;
  List<MealItem> ingredients;
  List<String> steps;

  /// Nährwerte aus den Zutaten berechnet.
  NutrientValues get totals => NutritionSummary.totals(ingredients);

  Recipe copy() => Recipe(
    id: id,
    meal: meal,
    title: title,
    minutes: minutes,
    ingredients: [for (final item in ingredients) item.copy()],
    steps: [...steps],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'meal': meal.rawValue,
    'title': title,
    'minutes': minutes,
    'ingredients': [for (final item in ingredients) item.toJson()],
    'steps': steps,
  };

  static Recipe? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, rawMeal, title, minutes) = (json['id'], json['meal'], json['title'], json['minutes']);
    final meal = rawMeal is String ? MealCategory.fromRaw(rawMeal) : null;
    final ingredients = listStrict(json['ingredients'], MealItem.fromJson);
    final steps = listStrict(json['steps'], (value) => value is String ? value : null);
    if (id is! String || meal == null || title is! String || minutes is! int || ingredients == null || steps == null) {
      return null;
    }
    return Recipe(id: id, meal: meal, title: title, minutes: minutes, ingredients: ingredients, steps: steps);
  }

  @override
  bool operator ==(Object other) =>
      other is Recipe &&
      other.id == id &&
      other.meal == meal &&
      other.title == title &&
      other.minutes == minutes &&
      const ListEquality<MealItem>().equals(other.ingredients, ingredients) &&
      const ListEquality<String>().equals(other.steps, steps);

  @override
  int get hashCode => Object.hash(id, meal, title, minutes);

  @override
  String toString() => 'Recipe($title)';
}

/// Rezepte eines Tages.
final class RecipeDay {
  RecipeDay({required this.day, required this.recipes, required this.scale});

  final CalendarDay day;
  List<Recipe> recipes;

  /// Faktor, mit dem die Mengen ans Tagesziel angepasst wurden.
  final double scale;

  CalendarDay get id => day;

  NutrientValues get totals => recipes.fold(NutrientValues(), (sum, recipe) => sum + recipe.totals);

  Map<String, Object?> toJson() => {
    'day': day.toJson(),
    'recipes': [for (final recipe in recipes) recipe.toJson()],
    'scale': scale,
  };

  static RecipeDay? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawDay = json['day'];
    final recipes = listStrict(json['recipes'], Recipe.fromJson);
    final scale = jsonDouble(json['scale']);
    if (rawDay is! Map || recipes == null || scale == null) return null;
    final CalendarDay day;
    try {
      day = CalendarDay.fromJson(rawDay.cast<String, Object?>());
    } on Object {
      return null;
    }
    return RecipeDay(day: day, recipes: recipes, scale: scale);
  }

  @override
  bool operator ==(Object other) =>
      other is RecipeDay &&
      other.day == day &&
      const ListEquality<Recipe>().equals(other.recipes, recipes) &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(day, scale);
}

/// Rezeptideen für einen Zeitraum.
final class WeeklyRecipePlan {
  WeeklyRecipePlan({required this.created, required this.days, required this.source, required this.notes});

  DateTime created;
  List<RecipeDay> days;
  String source;

  /// Hinweise der Prüfung (verworfene Rezepte, Abweichungen vom Tagesziel).
  List<String> notes;

  RecipeDay? day(CalendarDay day) => days.firstWhereOrNull((entry) => entry.day == day);

  /// Neue Tage übernehmen; vorhandene Tage bleiben, soweit sie nicht ersetzt werden.
  WeeklyRecipePlan adding(WeeklyRecipePlan other) {
    final replaced = {for (final day in other.days) day.day};
    final merged = [...days.where((day) => !replaced.contains(day.day)), ...other.days];
    mergeSort(merged, compare: (a, b) => a.day.compareTo(b.day));
    return WeeklyRecipePlan(
      created: other.created,
      days: merged,
      source: source.contains(other.source) ? source : [source, other.source].join(', '),
      notes: [...notes, ...other.notes.where((note) => !notes.contains(note))],
    );
  }

  Map<String, Object?> toJson() => {
    'created': swiftDateToJson(created),
    'days': [for (final day in days) day.toJson()],
    'source': source,
    'notes': notes,
  };

  static WeeklyRecipePlan? fromJson(Object? json) {
    if (json is! Map) return null;
    final created = swiftDateFromJson(json['created']);
    final days = listStrict(json['days'], RecipeDay.fromJson);
    final source = json['source'];
    final notes = listStrict(json['notes'], (value) => value is String ? value : null);
    if (created == null || days == null || source is! String || notes == null) return null;
    return WeeklyRecipePlan(created: created, days: days, source: source, notes: notes);
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklyRecipePlan &&
      other.created.isAtSameMomentAs(created) &&
      const ListEquality<RecipeDay>().equals(other.days, days) &&
      other.source == source &&
      const ListEquality<String>().equals(other.notes, notes);

  @override
  int get hashCode => Object.hash(created.microsecondsSinceEpoch, source);
}

/// Eine Zeile der Einkaufsliste.
final class ShoppingItem {
  const ShoppingItem({required this.name, required this.grams, this.group});

  final String name;
  final double grams;

  /// Lebensmittelgruppe der KI (für die Supermarkt-Abteilung).
  final String? group;

  String get id => name.toLowerCase();
  ShoppingAisle get aisle => ShoppingAisle.of(name: name, group: group);

  @override
  bool operator ==(Object other) =>
      other is ShoppingItem && other.name == name && other.grams == grams && other.group == group;

  @override
  int get hashCode => Object.hash(name, grams, group);

  @override
  String toString() => 'ShoppingItem($name, $grams g)';
}

/// Einkaufsliste nach Supermarkt-Abteilung (aus der Lebensmittelgruppe der KI bzw. dem Namen).
enum ShoppingAisle implements RawEnum {
  produce('Obst und Gemüse'),
  cooled('Kühlregal'),
  meatFish('Fleisch und Fisch'),
  bakery('Brot und Backwaren'),
  dry('Nudeln, Reis, Hülsenfrüchte, Nüsse'),
  spices('Öl, Gewürze, Saucen'),
  frozen('Tiefkühl'),
  drinks('Getränke'),
  other('Sonstiges');

  const ShoppingAisle(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;

  static ShoppingAisle of({required String name, required String? group}) => switch (group) {
    'gemuese' || 'obst' => produce,
    'milch' || 'ei' => cooled,
    'fleisch' || 'fisch' || 'fisch_fett' => meatFish,
    'vollkorn' || 'getreide' || 'kartoffel' || 'huelsenfruechte' || 'nuesse' => byName(name) ?? dry,
    'fett' => spices,
    'getraenk' || 'alkohol' => drinks,
    _ => byName(name) ?? other,
  };

  static ShoppingAisle? byName(String name) {
    final lower = FoodSearch.normalized(name);
    if (['brot', 'broetchen', 'toast', 'wrap', 'tortilla'].any(lower.contains)) return bakery;
    if (['tiefkuehl', 'tk-', 'gefroren'].any(lower.contains)) return frozen;
    const spiceWords = ['oel', 'salz', 'pfeffer', 'gewuerz', 'sauce', 'sosse', 'essig', 'bruehe', 'senf', 'honig'];
    if (spiceWords.any(lower.contains)) return spices;
    return null;
  }
}

/// Sortierung wie `localizedCompare` auf Deutsch: Groß-/Kleinschreibung egal, Umlaute wie ihr Grundbuchstabe.
int germanCompare(String a, String b) {
  String key(String text) =>
      text.toLowerCase().replaceAll('ä', 'a').replaceAll('ö', 'o').replaceAll('ü', 'u').replaceAll('ß', 'ss');
  final byKey = key(a).compareTo(key(b));
  return byKey != 0 ? byKey : a.compareTo(b);
}

typedef HiddenIngredient = ({String keyword, Set<Allergen> allergens, String? animal});

/// Rezeptideen für die kommende Woche. Die Regeln legen die Tagesziele fest (Energie, Protein, Kohlenhydrate nach
/// Trainingstag) und prüfen jede Antwort der KI: Ernährungsweise und Allergene, Mengen passend zum Tagesziel.
abstract final class RecipePlanner {
  static const evidence = ['nutrition.energy', 'nutrition.carbs', 'nutrition.protein', 'nutrition.reds'];

  /// Mengen werden höchstens um diesen Faktor angepasst; darüber passt das Rezept nicht zum Tag.
  static const scaleLower = 0.75;
  static const scaleUpper = 1.33;
  static const tolerance = 0.15;

  /// Längster Zeitraum, für den Rezepte auf einmal erstellt werden.
  static const maxPeriodDays = 14;

  // Eingabe für die KI

  static Map<String, Object?> input({
    required List<RecipeDayTarget> days,
    required RecipePreferences preferences,
    required Diet diet,
    required String goal,
    required List<String> gaps,
    required List<String> favorites,
  }) => {
    'days': [
      for (final target in days)
        {
          'datum': target.day.iso,
          'wochentag': Weekday.of(target.day).long,
          // Ohne Einheiten (frei gewählter Zeitraum): Die Rezepte hängen nicht am Trainingsplan.
          'training': target.sessions.isEmpty ? 'nicht berücksichtigt' : target.sessions.join(' + '),
          'tagestyp': target.dayType.label,
          'kcal': target.kcal.roundToDouble(),
          'protein_g': target.protein.roundToDouble(),
          'kohlenhydrate_g': target.carbs.roundToDouble(),
          'fett_g': target.fat.roundToDouble(),
        },
    ],
    'diet': diet.rawValue,
    'dietLabel': diet.label,
    'goal': goal,
    'allergens': [for (final allergen in _sortedAllergens(preferences.allergens)) allergen.label],
    'dislikes': textPrefix(preferences.dislikes, 200),
    'maxMinutes': preferences.maxMinutes.toDouble(),
    'snacks': preferences.snacks,
    'mealPrep': preferences.mealPrep,
    'gaps': gaps,
    'favorites': favorites.take(15).toList(),
    'evidence': CoachingNote.evidenceInput(evidence),
  };

  // Antwort prüfen

  /// Liest die Antwort der Worker-Aufgabe `weekly_recipes`, verwirft unpassende Rezepte und passt die Mengen an
  /// das Tagesziel an.
  static WeeklyRecipePlan? plan(
    JsonValue output, {
    required List<RecipeDayTarget> targets,
    required Diet diet,
    required Set<Allergen> allergens,
    required String source,
    required DateTime created,
  }) {
    final rawDays = output['tage']?.arrayValue;
    if (rawDays == null) return null;
    final notes = <String>[];
    final days = <RecipeDay>[];
    // Schreibt die KI das Datum anders, zählt die Reihenfolge – sonst blieben Tage ohne Rezepte.
    final datesMatch = targets.any((target) => rawDays.any((raw) => raw['datum']?.stringValue == target.day.iso));
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final raw = datesMatch || rawDays.length != targets.length
          ? rawDays.firstWhereOrNull((day) => day['datum']?.stringValue == target.day.iso)
          : rawDays[index];
      var recipes = (raw?['gerichte']?.arrayValue ?? const <JsonValue>[]).map(recipe).nonNulls.toList();
      final before = recipes.length;
      recipes = recipes.where((recipe) => _accept(recipe, diet: diet, allergens: allergens, notes: notes)).toList();
      if (recipes.isEmpty) {
        if (before == 0) notes.add('${Weekday.of(target.day).long}: keine Rezepte erhalten.');
        continue;
      }
      days.add(fit(target, recipes, notes));
    }
    if (days.isEmpty) return null;
    return WeeklyRecipePlan(created: created, days: days, source: source, notes: notes);
  }

  /// Prüft Ernährungsweise, Allergene und Nährwerte; Verworfenes landet mit Grund in [notes].
  static bool _accept(
    Recipe recipe, {
    required Diet diet,
    required Set<Allergen> allergens,
    required List<String> notes,
  }) {
    final problems = recipeViolations(recipe, diet: diet, allergens: allergens);
    if (problems.isNotEmpty) {
      notes.add('„${recipe.title}“ verworfen: enthält ${problems.join(', ')}.');
      return false;
    }
    final item = recipe.ingredients.firstWhereOrNull(implausible);
    if (item != null) {
      notes.add('„${recipe.title}“ verworfen: unstimmige Nährwerte bei „${item.name}“.');
      return false;
    }
    return true;
  }

  /// Wie [_accept] für „Was esse ich jetzt?“.
  static bool accept(
    Recipe recipe, {
    required Diet diet,
    required Set<Allergen> allergens,
    required List<String> notes,
  }) => _accept(recipe, diet: diet, allergens: allergens, notes: notes);

  static Recipe? recipe(JsonValue value) {
    final title = value['titel']?.stringValue;
    final rawItems = value['zutaten']?.arrayValue;
    if (title == null || title.isEmpty || rawItems == null) return null;
    final items = rawItems.map(MealAnalysis.item).nonNulls.toList();
    if (items.isEmpty || !items.any((item) => (item.per100g[Nutrient.kcal] ?? 0) > 0)) return null;
    final meal = MealCategory.fromRaw(value['mahlzeit']?.stringValue) ?? MealCategory.other;
    final minutes = value['minuten']?.clampedInt(0, 1440) ?? 0;
    final steps = [for (final step in value['zubereitung']?.arrayValue ?? const <JsonValue>[]) ?step.stringValue]
        .take(8)
        .toList();
    return Recipe(
      meal: meal,
      title: textPrefix(title, 60),
      minutes: math.max(minutes, 0),
      ingredients: items,
      steps: steps,
    );
  }

  /// Mengen auf 5 g gerundet, mindestens 5 g.
  static List<MealItem> scaledItems(List<MealItem> items, double factor) => [
    for (final item in items) item.copy()..grams = math.max(5, (item.grams * factor / 5).roundToDouble() * 5),
  ];

  /// Mengen so skalieren, dass die Tagesenergie zum Ziel passt (in Grenzen), auf 5 g gerundet.
  static RecipeDay fit(RecipeDayTarget target, List<Recipe> recipes, List<String> notes) {
    final total = recipes.fold(0.0, (sum, recipe) => sum + (recipe.totals[Nutrient.kcal] ?? 0));
    if (total <= 0 || target.kcal <= 0) return RecipeDay(day: target.day, recipes: recipes, scale: 1);
    final scale = (target.kcal / total).clamp(scaleLower, scaleUpper);
    final scaled = [for (final recipe in recipes) recipe.copy()..ingredients = scaledItems(recipe.ingredients, scale)];
    final result = RecipeDay(day: target.day, recipes: scaled, scale: (scale * 100).roundToDouble() / 100);
    final kcal = result.totals[Nutrient.kcal] ?? 0;
    if ((kcal - target.kcal).abs() / target.kcal > tolerance) {
      notes.add(
        '${Weekday.of(target.day).long}: Rezepte ergeben ca. ${kcal.round()} statt ${target.kcal.round()} kcal – '
        'Portionen anpassen.',
      );
    }
    return result;
  }

  // Ernährungsweise und Allergene

  static const meat = [
    'fleisch', 'hähnchen', 'hühnchen', 'huhn', 'pute', 'truthahn', 'rind', 'schwein', 'speck', 'schinken', 'salami', //
    'wurst', 'würstchen', 'hack', 'lamm', 'kalb', 'ente', 'chorizo', 'bacon', 'gyros', 'leber',
  ];
  static const fish = [
    'fisch', 'lachs', 'thunfisch', 'forelle', 'kabeljau', 'seelachs', 'hering', 'makrele', 'sardine', 'sardelle', //
    'dorsch', 'zander', 'pangasius', 'scholle', 'rotbarsch',
  ];
  static const shellfish = [
    'garnele',
    'shrimp',
    'krabbe',
    'muschel',
    'hummer',
    'scampi',
    'languste',
    'krebs',
    'tintenfisch',
    'calamari',
  ];
  static const dairy = [
    'milch', 'joghurt', 'quark', 'käse', 'sahne', 'butter', 'skyr', 'mozzarella', 'parmesan', 'feta', 'schmand', //
    'ricotta', 'molke', 'kefir', 'ghee', 'mascarpone', 'halloumi', 'whey',
  ];
  static const plantPrefixes = [
    'hafer',
    'soja',
    'mandel',
    'kokos',
    'reis',
    'erbsen',
    'cashew',
    'erdnuss',
    'nuss',
    'dinkel',
    'pflanz',
    'vegan',
  ];
  static const gluten = [
    'weizen', 'dinkel', 'roggen', 'gerste', 'hafer', 'nudel', 'pasta', 'spaghetti', 'penne', 'brot', 'brötchen', //
    'couscous', 'bulgur', 'seitan', 'mehl', 'grieß', 'toast', 'tortilla', 'wrap', 'semmel', 'lasagne', 'gnocchi',
  ];
  static const glutenFree = [
    'glutenfrei', 'buchweizen', 'reismehl', 'maismehl', 'reisnudel', 'glasnudel', 'polenta', 'kichererbsenmehl', //
    'mandelmehl', 'kokosmehl',
  ];
  static const nuts = [
    'mandel',
    'walnuss',
    'haselnuss',
    'cashew',
    'pistazie',
    'pekannuss',
    'macadamia',
    'paranuss',
    'nüsse',
    'nuss',
  ];
  static const soy = ['soja', 'tofu', 'edamame', 'tempeh', 'miso'];
  static const sesame = ['sesam', 'tahin'];

  /// Zutaten mit typischerweise versteckten Allergenen bzw. tierischen Bestandteilen.
  static const List<HiddenIngredient> hidden = [
    (keyword: 'pesto', allergens: {Allergen.lactose, Allergen.nuts}, animal: 'Milchprodukte'),
    (keyword: 'worcester', allergens: {Allergen.fish}, animal: 'Fisch'),
    (keyword: 'caesar', allergens: {Allergen.fish, Allergen.egg, Allergen.lactose}, animal: 'Fisch'),
    (keyword: 'mayonnaise', allergens: {Allergen.egg}, animal: 'Ei'),
    (keyword: 'mayo', allergens: {Allergen.egg}, animal: 'Ei'),
    (keyword: 'remoulade', allergens: {Allergen.egg}, animal: 'Ei'),
    (keyword: 'aioli', allergens: {Allergen.egg}, animal: 'Ei'),
    (keyword: 'marzipan', allergens: {Allergen.nuts}, animal: null),
    (keyword: 'nougat', allergens: {Allergen.nuts, Allergen.lactose}, animal: 'Milchprodukte'),
    (keyword: 'praline', allergens: {Allergen.nuts}, animal: null),
    (keyword: 'hummus', allergens: {Allergen.sesame}, animal: null),
    (keyword: 'sojasauce', allergens: {Allergen.soy, Allergen.gluten}, animal: null),
    (keyword: 'sojasoße', allergens: {Allergen.soy, Allergen.gluten}, animal: null),
    (keyword: 'teriyaki', allergens: {Allergen.soy, Allergen.gluten}, animal: null),
    (keyword: 'fischsauce', allergens: {Allergen.fish}, animal: 'Fisch'),
    (keyword: 'austernsauce', allergens: {Allergen.shellfish}, animal: 'Fisch'),
    (keyword: 'milchschokolade', allergens: {Allergen.lactose}, animal: 'Milchprodukte'),
    (keyword: 'panko', allergens: {Allergen.gluten}, animal: null),
  ];

  static List<String> words(String text) => text.toLowerCase().split(_nonLetter).where((w) => w.isNotEmpty).toList();

  static bool containsAny(String name, List<String> keywords, {List<String> except = const []}) =>
      words(name).any((word) => keywords.any(word.contains) && !except.any(word.contains));

  static bool isEgg(String name) => words(name).any(
    (word) =>
        word == 'ei' ||
        word.startsWith('eier') ||
        word.startsWith('eigelb') ||
        word.startsWith('eiklar') ||
        (word.endsWith('ei') && word.runes.length > 3 && !word.endsWith('brei')),
  );

  static bool isDairy(String name) =>
      words(name).any((word) => dairy.any(word.contains) && !plantPrefixes.any(word.startsWith));

  /// Was an einer Zutat nicht zu Ernährungsweise oder Allergenen passt.
  static List<String> violations(String name, {required Diet diet, required Set<Allergen> allergens}) {
    final lower = name.toLowerCase();
    final result = <String>[];
    final plantBased = lower.contains('vegan') || lower.contains('vegetarisch');
    if (!plantBased) {
      // Pflanzliche Ersatzprodukte wie „Sojahack“ oder „Erbsenwurst“ zählen nicht als Fleisch.
      if (diet != Diet.omnivore && containsAny(name, meat, except: const ['soja', 'erbsen', 'tofu', 'seitan'])) {
        result.add('Fleisch');
      }
      if ((diet == Diet.vegetarian || diet == Diet.vegan) &&
          (containsAny(name, fish) || containsAny(name, shellfish))) {
        result.add('Fisch');
      }
      if (diet == Diet.vegan) {
        if (isEgg(name)) result.add('Ei');
        if (isDairy(name)) result.add('Milchprodukte');
        if (containsAny(name, const ['honig'])) result.add('Honig');
      }
    }
    for (final item in hidden) {
      if (!lower.contains(item.keyword)) continue;
      final animal = item.animal;
      if (animal != null && !plantBased) {
        final conflict = animal == 'Fisch' ? diet == Diet.vegetarian || diet == Diet.vegan : diet == Diet.vegan;
        if (conflict) result.add(animal);
      }
      for (final allergen in _sortedAllergens(item.allergens)) {
        if (allergens.contains(allergen)) result.add(allergen.label);
      }
    }
    for (final allergen in _sortedAllergens(allergens)) {
      final hit = switch (allergen) {
        Allergen.gluten => containsAny(name, gluten) && !glutenFree.any(lower.contains),
        Allergen.lactose => isDairy(name) && !lower.contains('laktosefrei'),
        Allergen.nuts => containsAny(name, nuts, except: const ['erdnuss', 'muskatnuss', 'kokosnuss']),
        Allergen.peanuts => lower.contains('erdnuss'),
        Allergen.egg => isEgg(name),
        Allergen.soy => containsAny(name, soy),
        Allergen.fish => containsAny(name, fish),
        Allergen.shellfish => containsAny(name, shellfish),
        Allergen.sesame => containsAny(name, sesame),
      };
      if (hit) result.add(allergen.label);
    }
    final seen = <String>{};
    return result.where(seen.add).toList();
  }

  static List<String> recipeViolations(Recipe recipe, {required Diet diet, required Set<Allergen> allergens}) {
    final seen = <String>{};
    return recipe.ingredients
        .expand((item) => violations(item.name, diet: diet, allergens: allergens))
        .where(seen.add)
        .toList();
  }

  /// Unstimmige Nährwerte je 100 g: mehr als 900 kcal, mehr als 100 g eines Makronährstoffs, zusammen über 105 g
  /// oder Energie, die nicht zu Protein, Kohlenhydraten und Fett passt (4/4/9 kcal je g, ±25 % bzw. ±40 kcal).
  static bool implausible(MealItem item) {
    final values = item.per100g;
    final kcal = values[Nutrient.kcal] ?? 0;
    final protein = values[Nutrient.protein];
    final carbs = values[Nutrient.carbs];
    final fat = values[Nutrient.fat];
    if (kcal > 900 || kcal < 0) return true;
    for (final value in [protein, carbs, fat].nonNulls) {
      if (value > 100 || value < 0) return true;
    }
    if ((protein ?? 0) + (carbs ?? 0) + (fat ?? 0) > 105) return true;
    if (protein != null && carbs != null && fat != null) {
      final fromMacros = 4 * protein + 4 * carbs + 9 * fat;
      if ((kcal - fromMacros).abs() > math.max(0.25 * math.max(kcal, fromMacros), 40)) return true;
    }
    return false;
  }

  // Auswertung bisheriger Mahlzeiten und Einkaufsliste

  /// Nährstoffe, die in den letzten Tagen im Schnitt unter 80 % des Ziels lagen (nur Tage mit erfassten Mahlzeiten).
  static List<String> gaps({required List<NutrientValues> dailyTotals, required NutrientValues targets}) {
    if (dailyTotals.length < 3) return [];
    const watched = [
      Nutrient.protein,
      Nutrient.fiber,
      Nutrient.omega3,
      Nutrient.calcium,
      Nutrient.iron,
      Nutrient.iodine,
      Nutrient.magnesium,
    ];
    return [
      for (final nutrient in watched)
        if (targets[nutrient] case final target? when target > 0)
          if (dailyTotals.fold(0.0, (sum, day) => sum + (day[nutrient] ?? 0)) / dailyTotals.length case final average
              when average < 0.8 * target)
            '${nutrient.label}: im Schnitt ${average.round()} von ${target.round()} ${nutrient.unit} '
                '(${(average / target * 100).round()} %)',
    ];
  }

  /// Einkaufsliste: gleiche Zutaten aller Rezepte im Zeitraum zusammengefasst, für [servings] Personen.
  /// Ohne [from]/[to] der ganze Plan.
  static List<ShoppingItem> shoppingList(
    WeeklyRecipePlan plan, {
    required int servings,
    CalendarDay? from,
    CalendarDay? to,
  }) {
    final sums = <String, ({String name, double grams, String? group})>{};
    final days = plan.days.where((day) => (from == null || day.day >= from) && (to == null || day.day <= to));
    for (final item in days.expand((day) => day.recipes).expand((recipe) => recipe.ingredients)) {
      final key = item.name.toLowerCase().trim();
      final current = sums[key] ?? (name: item.name, grams: 0.0, group: item.group);
      sums[key] = (
        name: current.name,
        grams: current.grams + item.grams * math.max(servings, 1),
        group: current.group ?? item.group,
      );
    }
    return [
      for (final sum in sums.values)
        ShoppingItem(name: sum.name, grams: (sum.grams / 5).roundToDouble() * 5, group: sum.group),
    ]..sort((a, b) => germanCompare(a.name, b.name));
  }

  /// Tage eines frei gewählten Zeitraums (1 bis 14 Tage ab [start]).
  static List<CalendarDay> period({required CalendarDay start, required int days}) => [
    for (var index = 0; index < days.clamp(1, maxPeriodDays); index++) start.adding(index),
  ];

  /// Gleiche Ziele für jeden Tag des Zeitraums: der Durchschnitt einer typischen Woche ([reference], aus Plan und
  /// Ernährungszielen). So hängen die Rezepte nicht an einzelnen Trainingstagen, und die Energie passt im Schnitt.
  static List<RecipeDayTarget> uniformTargets({
    required List<CalendarDay> days,
    required List<RecipeDayTarget> reference,
  }) {
    if (reference.isEmpty) return [];
    double mean(double Function(RecipeDayTarget) value) =>
        (reference.fold(0.0, (sum, target) => sum + value(target)) / reference.length).roundToDouble();
    // Häufigster Tagestyp der Woche; bei Gleichstand der ruhigere.
    final counts = <DayType, int>{};
    for (final target in reference) {
      counts[target.dayType] = (counts[target.dayType] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => a.value != b.value ? b.value.compareTo(a.value) : a.key.index.compareTo(b.key.index));
    final dayType = ranked.firstOrNull?.key ?? DayType.light;
    return [
      for (final day in days)
        RecipeDayTarget(
          day: day,
          sessions: const [],
          dayType: dayType,
          kcal: mean((target) => target.kcal),
          protein: mean((target) => target.protein),
          carbs: mean((target) => target.carbs),
          fat: mean((target) => target.fat),
        ),
    ];
  }

  /// Tage des Zeitraums, für die der Plan (noch) keine Rezepte hat.
  static List<RecipeDayTarget> missing(List<RecipeDayTarget> targets, {required WeeklyRecipePlan? plan}) =>
      targets.where((target) => plan?.day(target.day)?.recipes.isEmpty ?? true).toList();
}

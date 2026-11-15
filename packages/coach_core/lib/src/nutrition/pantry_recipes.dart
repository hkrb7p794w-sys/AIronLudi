import '../json/json_value.dart';
import '../util/text_prefix.dart';
import 'meal_category.dart';
import 'meal_planning.dart';
import 'nutrient.dart';
import 'nutrition_settings.dart';
import 'recipe_plan.dart';

/// Ein Vorschlag aus dem Kühlschrank-Foto: Rezept und die kleinen Zutaten, die auf dem Foto nicht zu sehen waren.
final class PantryRecipe {
  PantryRecipe({required this.recipe, required this.missing});

  final Recipe recipe;

  /// Höchstens [PantryRecipes.maxMissing] Standardzutaten („Butter“, „Salz“), nach denen die App fragt.
  final List<String> missing;
}

/// Stand eines Vorschlags nach den Antworten auf die Rückfragen.
enum PantryRecipeStatus {
  /// Alles da (nichts fehlt oder alles bestätigt).
  ready,

  /// Mindestens eine Rückfrage ist offen.
  waiting,

  /// Eine fehlende Zutat ist nicht da.
  blocked,
}

/// Antwort der KI auf ein Foto: erkannte Lebensmittel und Gerichte.
final class PantryResult {
  PantryResult({required this.detected, required this.recipes, required this.notes});

  /// Erkannte Lebensmittel – die Person kann sie korrigieren, bevor sie neu fragt.
  final List<String> detected;
  final List<PantryRecipe> recipes;

  /// Verworfene Gerichte mit Grund.
  final List<String> notes;
}

/// Rezepte aus einem Foto von Kühlschrank oder Vorratsschrank (Worker-Aufgabe `pantry_recipes`). Die KI erkennt die
/// Lebensmittel und schlägt Gerichte vor; fehlen für ein naheliegendes Gericht nur ein oder zwei kleine
/// Standardzutaten, nennt sie diese unter `fehlt`, statt das Gericht zu verwerfen. Die App fragt dann „Ist noch Butter
/// da?“. Feste Regeln: Ernährungsweise und Allergene wie bei allen Rezepten, mehr als zwei fehlende Zutaten verwirft
/// die App, Zutaten aus dem Vorrat gelten als da.
abstract final class PantryRecipes {
  static const task = 'pantry_recipes';
  static const maxMissing = 2;
  static const maxRecipes = 4;
  static const maxQuestions = 4;

  /// Vergleich von Zutaten ohne Groß-/Kleinschreibung und Leerzeichen am Rand.
  static String key(String name) => name.trim().toLowerCase();

  static Map<String, Object?> input({
    required MealCategory category,
    required double? targetKilocalories,
    required Diet diet,
    required RecipePreferences preferences,
    required List<String> pantry,
    List<String> detected = const [],
    Set<String> confirmed = const {},
    Set<String> denied = const {},
  }) {
    final allergens = preferences.allergens.toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue));
    List<String> sorted(Iterable<String> values) => [for (final value in values) textPrefix(value, 60)]..sort();
    return {
      'mahlzeit': category.rawValue,
      'kcal': ?targetKilocalories?.roundToDouble(),
      'diet': diet.rawValue,
      'dietLabel': diet.label,
      'allergens': [for (final allergen in allergens) allergen.label],
      'dislikes': textPrefix(preferences.dislikes, 200),
      'maxMinutes': preferences.maxMinutes.toDouble(),
      // Vorrat aus der Einkaufsliste („Habe ich da“) gilt als vorhanden, auch wenn er nicht im Bild ist.
      'vorrat': pantry.take(30).toList(),
      // Bei einer zweiten Anfrage: korrigierte Liste statt neu erkennen, und die Antworten auf die Rückfragen.
      'erkannt': sorted(detected.take(40)),
      'bestaetigt': sorted(confirmed),
      'nicht_da': sorted(denied),
      'max_fehlend': maxMissing,
      'anzahl': maxRecipes,
    };
  }

  /// Antwort `{"erkannt": [...], "gerichte": [{…, "fehlt": [...]}]}` prüfen. `null`, wenn sie nichts Lesbares enthält.
  static PantryResult? result(
    JsonValue output, {
    required Diet diet,
    required Set<Allergen> allergens,
    required List<String> pantry,
    Set<String> confirmed = const {},
    double? targetKilocalories,
  }) {
    final detected = <String>[];
    final seen = <String>{};
    for (final raw in output['erkannt']?.arrayValue ?? const <JsonValue>[]) {
      final name = raw.stringValue?.trim();
      if (name == null || name.isEmpty || !seen.add(key(name))) continue;
      detected.add(textPrefix(name, 60));
      if (detected.length >= 40) break;
    }
    final rawRecipes = output['gerichte']?.arrayValue;
    if (rawRecipes == null && detected.isEmpty) return null;
    final known = {
      for (final name in [...pantry, ...detected, ...confirmed]) key(name),
    };
    final notes = <String>[];
    final recipes = <PantryRecipe>[];
    for (final raw in rawRecipes ?? const <JsonValue>[]) {
      final parsed = RecipePlanner.recipe(raw);
      if (parsed == null || !RecipePlanner.accept(parsed, diet: diet, allergens: allergens, notes: notes)) continue;
      final missing = <String>[];
      for (final item in raw['fehlt']?.arrayValue ?? const <JsonValue>[]) {
        final name = item.stringValue?.trim();
        if (name == null || name.isEmpty || known.contains(key(name))) continue;
        if (missing.any((other) => key(other) == key(name))) continue;
        missing.add(textPrefix(name, 40));
      }
      if (missing.length > maxMissing) {
        notes.add('„${parsed.title}“ verworfen: Es fehlen zu viele Zutaten (${missing.join(', ')}).');
        continue;
      }
      final recipe = targetKilocalories == null ? parsed : MealNow.scaled(parsed, targetKilocalories);
      recipes.add(PantryRecipe(recipe: recipe, missing: missing));
      if (recipes.length >= maxRecipes) break;
    }
    return PantryResult(detected: detected, recipes: recipes, notes: notes);
  }

  static PantryRecipeStatus status(PantryRecipe recipe, {required Set<String> confirmed, required Set<String> denied}) {
    final yes = {for (final name in confirmed) key(name)};
    final no = {for (final name in denied) key(name)};
    if (recipe.missing.any((name) => no.contains(key(name)))) return PantryRecipeStatus.blocked;
    if (recipe.missing.every((name) => yes.contains(key(name)))) return PantryRecipeStatus.ready;
    return PantryRecipeStatus.waiting;
  }

  /// Offene Rückfragen: fehlende Zutaten der noch möglichen Gerichte, die häufigste zuerst (eine Antwort klärt dann
  /// mehrere Gerichte), höchstens [maxQuestions].
  static List<String> questions(
    List<PantryRecipe> recipes, {
    required Set<String> confirmed,
    required Set<String> denied,
  }) {
    final answered = {
      for (final name in [...confirmed, ...denied]) key(name),
    };
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final recipe in recipes) {
      if (status(recipe, confirmed: confirmed, denied: denied) == PantryRecipeStatus.blocked) continue;
      for (final name in recipe.missing) {
        final id = key(name);
        if (answered.contains(id)) continue;
        counts[id] = (counts[id] ?? 0) + 1;
        names.putIfAbsent(id, () => name);
      }
    }
    final order = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return [for (final id in order.take(maxQuestions)) names[id]!];
  }

  /// „Ist noch Butter da?“
  static String question(String ingredient) => 'Ist noch $ingredient da?';

  /// Gerichte, für die eine Zutat gebraucht wird – für den Text unter der Frage.
  static List<String> neededFor(String ingredient, List<PantryRecipe> recipes) => [
    for (final recipe in recipes)
      if (recipe.missing.any((name) => key(name) == key(ingredient))) recipe.recipe.title,
  ];

  /// Energie eines Vorschlags (für die Anzeige).
  static double kilocalories(PantryRecipe recipe) => recipe.recipe.totals[Nutrient.kcal] ?? 0;
}

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../util/german_format.dart';
import '../util/swift_date.dart';
import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';
import 'quick_log.dart';

/// Eine als Favorit gespeicherte Mahlzeit – eine Vorlage, getrennt von Rezepten (`OwnRecipe`) und vom Tagebuch:
/// Eintragen legt immer eine Kopie an, Änderungen am Tagebuch-Eintrag ändern den Favoriten nicht.
final class FavoriteMeal {
  FavoriteMeal({String? id, required this.title, required List<MealItem> items, this.category, DateTime? created})
    : id = id ?? newUuid(),
      // Vorlage ohne Portionsanpassung: Menge = was ursprünglich geplant war.
      items = items.map(MealPortion.restored).toList(),
      created = created ?? DateTime.now();

  FavoriteMeal._raw({
    required this.id,
    required this.title,
    required this.items,
    required this.category,
    required this.created,
  });

  final String id;
  String title;
  List<MealItem> items;
  MealCategory? category;
  final DateTime created;

  double get kilocalories => NutritionSummary.totals(items)[Nutrient.kcal] ?? 0;
  String get signature => MealSuggestions.signature(items);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'items': [for (final item in items) item.toJson()],
    'category': ?category?.rawValue,
    'created': swiftDateToJson(created),
  };

  /// Wie das synthetisierte `Decodable` (Positionen unverändert, ohne erneutes Zurücksetzen).
  static FavoriteMeal? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final rawItems = json['items'];
    final created = swiftDateFromJson(json['created']);
    final rawCategory = json['category'];
    final category = rawCategory is String ? MealCategory.fromRaw(rawCategory) : null;
    if (id is! String || title is! String || rawItems is! List || created == null) return null;
    if (rawCategory != null && category == null) return null;
    final items = <MealItem>[];
    for (final raw in rawItems) {
      final item = MealItem.fromJson(raw);
      if (item == null) return null;
      items.add(item);
    }
    return FavoriteMeal._raw(id: id, title: title, items: items, category: category, created: created);
  }

  @override
  bool operator ==(Object other) =>
      other is FavoriteMeal &&
      other.id == id &&
      other.title == title &&
      const ListEquality<MealItem>().equals(other.items, items) &&
      other.category == category &&
      other.created.isAtSameMomentAs(created);

  @override
  int get hashCode => Object.hash(id, title, category);
}

/// Was beim Erfassen sofort zur Auswahl steht.
abstract final class MealShortcuts {
  /// Zuletzt erfasste Mahlzeiten, neueste zuerst, jede Zusammenstellung nur einmal.
  static List<MealEntry> recent(List<MealEntry> entries, {int limit = 8}) {
    final sorted = [...entries];
    mergeSort(sorted, compare: (a, b) => b.date.compareTo(a.date));
    final seen = <String>{};
    final result = <MealEntry>[];
    for (final entry in sorted) {
      if (entry.items.isEmpty) continue;
      if (!seen.add(MealSuggestions.signature(entry.items.map(MealPortion.restored)))) continue;
      result.add(entry);
      if (result.length == limit) break;
    }
    return result;
  }

  /// Häufigste Mahlzeiten über alle Kategorien (letzte 60 Tage), mindestens zweimal gegessen.
  static List<MealSuggestion> frequent(List<MealEntry> entries, {required CalendarDay today, int limit = 8}) {
    final merged = <String, MealSuggestion>{};
    for (final category in MealCategory.values) {
      for (final suggestion in MealSuggestions.frequent(
        entries,
        category: category,
        today: today.adding(1),
        limit: limit,
      )) {
        final existing = merged[suggestion.id];
        if (existing != null) {
          existing.count += suggestion.count;
        } else {
          merged[suggestion.id] = suggestion;
        }
      }
    }
    final result = merged.values.where((suggestion) => suggestion.count >= 2).toList();
    mergeSort(
      result,
      compare: (a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.lastDate.compareTo(a.lastDate);
      },
    );
    return result.take(limit).toList();
  }

  /// Ist diese Zusammenstellung schon ein Favorit?
  static FavoriteMeal? favorite(List<MealItem> items, {required List<FavoriteMeal> favorites}) {
    final key = MealSuggestions.signature(items.map(MealPortion.restored));
    return favorites.firstWhereOrNull((favorite) => favorite.signature == key);
  }
}

/// Nachträglich weniger (oder mehr) gegessen: Mengen anteilig ändern, die ursprüngliche Menge bleibt je Position
/// gespeichert (`plannedGrams`). Nährwerte je 100 g bleiben gleich, daher stimmen alle Summen proportional.
/// Gilt nur für den Tagebuch-Eintrag – Rezepte und Favoriten sind eigene Kopien.
abstract final class MealPortion {
  static const presets = [0.25, 0.5, 0.75, 1.0];

  /// Anteil gegessen bezogen auf die ursprüngliche Menge (1 = alles).
  static double eatenFraction(List<MealItem> items) {
    final planned = plannedGrams(items);
    if (planned <= 0) return 1;
    return items.fold(0.0, (sum, item) => sum + item.grams) / planned;
  }

  /// Ursprüngliche Gesamtmenge.
  static double plannedGrams(List<MealItem> items) =>
      items.fold(0.0, (sum, item) => sum + (item.plannedGrams ?? item.grams));

  /// Alle Positionen auf [fraction] der ursprünglichen Menge setzen. Mehrfaches Anpassen rechnet immer von der
  /// ursprünglichen Menge aus (75 %, dann 50 % = 50 %, nicht 37,5 %); 100 % stellt den Ausgangszustand her.
  static List<MealItem> adjusted(List<MealItem> items, double fraction) {
    final clamped = fraction.clamp(0.05, 3.0);
    return [
      for (final item in items)
        () {
          final base = item.plannedGrams ?? item.grams;
          return item.copy()
            ..grams = (base * clamped * 10).roundToDouble() / 10
            ..plannedGrams = (clamped - 1).abs() < 0.001 ? null : base;
        }(),
    ];
  }

  /// Position mit ursprünglicher Menge (für Vorlagen und Vergleiche).
  static MealItem restored(MealItem item) {
    final copy = item.copy();
    if (item.plannedGrams case final planned?) copy.grams = planned;
    copy.plannedGrams = null;
    return copy;
  }

  /// „75 % von 500 g“.
  static String label(List<MealItem> items) =>
      '${(eatenFraction(items) * 100).round()} % von ${GermanFormat.number(plannedGrams(items).roundToDouble())} g';
}

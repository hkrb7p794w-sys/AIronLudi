import 'package:collection/collection.dart';

import 'meal.dart';
import 'meal_library.dart';
import 'nutrient.dart';

final _code = RegExp(r'^[a-z0-9]{10}$');

/// Eine Position einer geteilten Mahlzeit.
final class SharedMealItem {
  const SharedMealItem({
    required this.name,
    required this.grams,
    required this.isDrink,
    required this.source,
    required this.per100g,
    this.amountText,
  });

  final String name;
  final double grams;
  final bool isDrink;
  final String source;
  final Map<String, double> per100g;
  final String? amountText;

  Map<String, Object?> toJson() => {
    'name': name,
    'grams': grams,
    'isDrink': isDrink,
    'source': source,
    'per100g': per100g,
    'amountText': ?amountText,
  };

  static SharedMealItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final (name, grams, isDrink, source, rawValues, amountText) = (
      json['name'],
      json['grams'],
      json['isDrink'],
      json['source'],
      json['per100g'],
      json['amountText'],
    );
    if (name is! String || grams is! num || isDrink is! bool || source is! String || rawValues is! Map) return null;
    if (amountText != null && amountText is! String) return null;
    final values = <String, double>{};
    for (final entry in rawValues.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! num) return null;
      values[entry.key as String] = value.toDouble();
    }
    return SharedMealItem(
      name: name,
      grams: grams.toDouble(),
      isDrink: isDrink,
      source: source,
      per100g: values,
      amountText: amountText as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SharedMealItem &&
      other.name == name &&
      other.grams == grams &&
      other.isDrink == isDrink &&
      other.source == source &&
      const MapEquality<String, double>().equals(other.per100g, per100g) &&
      other.amountText == amountText;

  @override
  int get hashCode => Object.hash(name, grams, isDrink, source, amountText);
}

/// Eine geteilte Mahlzeit: nur Titel und Positionen (Menge, Nährwerte je 100 g, Herkunft der Werte) – kein Name, kein
/// Datum, keine Gesundheitsdaten. Beim Empfänger wird daraus immer ein neuer Tagebuch-Eintrag oder Favorit.
final class SharedMeal {
  const SharedMeal._({required this.title, required this.items, this.expiresAt});

  /// Zum Teilen: ursprüngliche Mengen (vor einer Portionsanpassung), Nährwerte wie gespeichert.
  factory SharedMeal({required String title, required List<MealItem> items}) => SharedMeal._(
    title: title,
    items: [
      for (final item in items.map(MealPortion.restored))
        SharedMealItem(
          name: item.name,
          grams: item.grams,
          isDrink: item.isDrink,
          source: item.source.rawValue,
          per100g: item.per100g.toJson(),
          amountText: item.amountText,
        ),
    ],
  );

  final String title;
  final List<SharedMealItem> items;
  final String? expiresAt;

  /// Positionen für das eigene Tagebuch (neue IDs).
  List<MealItem> get mealItems => [
    for (final shared in items)
      MealItem(
        name: shared.name,
        grams: shared.grams,
        source: MealItemSource.fromRaw(shared.source) ?? MealItemSource.manual,
        per100g: NutrientValues({
          for (final entry in shared.per100g.entries) ?Nutrient.fromRaw(entry.key): entry.value,
        }),
        isDrink: shared.isDrink,
        amountText: shared.amountText,
      ),
  ];

  double get kilocalories => NutritionSummary.totals(mealItems)[Nutrient.kcal] ?? 0;

  Map<String, Object?> toJson() => {
    'title': title,
    'items': [for (final item in items) item.toJson()],
    'expiresAt': ?expiresAt,
  };

  static SharedMeal? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['title'];
    final rawItems = json['items'];
    final expiresAt = json['expiresAt'];
    if (title is! String || rawItems is! List || (expiresAt != null && expiresAt is! String)) return null;
    final items = <SharedMealItem>[];
    for (final raw in rawItems) {
      final item = SharedMealItem.fromJson(raw);
      if (item == null) return null;
      items.add(item);
    }
    return SharedMeal._(title: title, items: items, expiresAt: expiresAt as String?);
  }

  @override
  bool operator ==(Object other) =>
      other is SharedMeal &&
      other.title == title &&
      const ListEquality<SharedMealItem>().equals(other.items, items) &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(title, expiresAt);
}

abstract final class MealShare {
  /// Code aus `coach://meal/<code>`, `https://…/m/<code>` oder einem eingetippten Code.
  static String? code(String text) {
    final trimmed = text.trim().toLowerCase();
    if (isValid(trimmed)) return trimmed;
    final url = Uri.tryParse(trimmed);
    if (url == null) return null;
    final parts = url.pathSegments.where((part) => part.isNotEmpty && part != '/').toList();
    if (url.scheme == 'coach' && url.host == 'meal' && parts.isNotEmpty && isValid(parts.last)) return parts.last;
    if (parts.length == 2 && parts[0] == 'm' && isValid(parts[1])) return parts[1];
    return null;
  }

  static bool isValid(String code) => _code.hasMatch(code);

  /// Text für Nachrichten-Apps: Link (öffnet die App) und Code zum Eintippen.
  static String message({required String title, required double kilocalories, Uri? link, required String code}) => [
    'Mahlzeit „$title“ (${kilocalories.round()} kcal) für AIronLudi:',
    ?link?.toString(),
    'Oder in der App unter Ernährung › „Geteilte Mahlzeit öffnen“ den Code $code eingeben.',
    'Der Code gilt 7 Tage.',
  ].join('\n');
}

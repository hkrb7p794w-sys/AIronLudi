import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import 'bls.dart';
import 'food_search.dart';
import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';
import 'open_food_facts.dart';
import 'quick_log.dart';

/// Herkunft eines Treffers der Produktsuche.
enum ProductSource {
  own('Eigene'),
  bls('Lebensmittel'),
  openFoodFacts('Markenprodukte');

  const ProductSource(this.label);

  final String label;
}

/// Treffer der Produktsuche: eigenes Lebensmittel, BLS-Eintrag oder Produkt aus Open Food Facts.
final class FoodProduct {
  const FoodProduct({
    required this.id,
    required this.name,
    required this.source,
    required this.per100g,
    required this.item,
    required this.defaultGrams,
    this.brand,
    this.servingGrams,
    this.servingText,
  });

  factory FoodProduct.bls(BLSFood food) => FoodProduct(
    id: 'bls:${food.code}',
    name: food.name,
    source: ProductSource.bls,
    per100g: food.per100g,
    defaultGrams: 100,
    item: ({double grams = 100}) => food.item(grams: grams),
  );

  factory FoodProduct.openFoodFacts(OpenFoodFactsProduct product) => FoodProduct(
    id: 'barcode:${product.barcode}',
    name: product.name,
    brand: product.brand,
    source: ProductSource.openFoodFacts,
    per100g: product.per100g,
    servingGrams: product.servingGrams,
    servingText: product.servingText,
    defaultGrams: product.servingGrams ?? 100,
    item: ({double grams = 100}) => product.item(grams: grams),
  );

  factory FoodProduct.own(MealItem food) => FoodProduct(
    id: 'own:${food.name}',
    name: food.name,
    source: ProductSource.own,
    per100g: food.per100g,
    servingGrams: food.portion?.grams,
    servingText: food.portion?.name,
    // Zuletzt gegessene Menge.
    defaultGrams: food.grams > 0 ? food.grams : food.portion?.grams ?? 100,
    item: ({double grams = 100}) => food.copy()
      ..id = newUuid()
      ..grams = grams,
  );

  final String id;
  final String name;
  final String? brand;
  final ProductSource source;
  final NutrientValues per100g;

  /// Portion laut Packung bzw. eigenem Eintrag (g), z. B. 45 g für einen Riegel.
  final double? servingGrams;
  final String? servingText;

  /// Menge für „+“: zuletzt gegessen (eigene), Packungsportion (Markenprodukte), sonst 100 g.
  final double defaultGrams;

  /// Position für die Mahlzeit mit dieser Menge.
  final MealItem Function({double grams}) item;

  String get title => brand == null ? name : '$name ($brand)';

  /// Nährwert für [grams] Gramm.
  double? amount(Nutrient nutrient, double grams) => switch (per100g[nutrient]) {
    final value? => value * grams / 100,
    null => null,
  };
}

/// Filter der Produktsuche: Herkunft und zwei schnelle Nährwert-Filter (je 100 g).
final class ProductFilter {
  const ProductFilter({this.sources = const {}, this.highProtein = false, this.lowCalorie = false});

  /// Leer = alle Herkünfte.
  final Set<ProductSource> sources;

  /// Mindestens 15 g Protein je 100 g.
  final bool highProtein;

  /// Höchstens 100 kcal je 100 g.
  final bool lowCalorie;

  static const proteinMinimum = 15.0;
  static const kilocaloriesMaximum = 100.0;

  bool includes(ProductSource source) => sources.isEmpty || sources.contains(source);

  bool matches(FoodProduct product) {
    if (!includes(product.source)) return false;
    if (highProtein && (product.per100g[Nutrient.protein] ?? 0) < proteinMinimum) return false;
    if (lowCalorie && (product.per100g[Nutrient.kcal] ?? double.infinity) > kilocaloriesMaximum) return false;
    return true;
  }

  ProductFilter copyWith({Set<ProductSource>? sources, bool? highProtein, bool? lowCalorie}) => ProductFilter(
    sources: sources ?? this.sources,
    highProtein: highProtein ?? this.highProtein,
    lowCalorie: lowCalorie ?? this.lowCalorie,
  );
}

/// Produktsuche über eigene Lebensmittel, den BLS (offline) und Open Food Facts (online, Markenprodukte).
abstract final class ProductSearch {
  /// Vorschläge ohne Suchbegriff: einzelne Lebensmittel, die um diese Zeit (gleiche Mahlzeit) am häufigsten gegessen
  /// wurden, mit der zuletzt gegessenen Menge; aufgefüllt mit dem Häufigsten der anderen Mahlzeiten. Wasser zählt nicht.
  static List<MealItem> picks(
    List<MealEntry> entries, {
    required MealCategory category,
    required CalendarDay today,
    int lookbackDays = 60,
    int limit = 8,
  }) {
    final start = today.adding(-lookbackDays);
    ({int count, DateTime last, MealItem item}) merge(
      ({int count, DateTime last, MealItem item})? old,
      MealEntry entry,
      MealItem item,
    ) => old == null
        ? (count: 1, last: entry.date, item: item)
        : (
            count: old.count + 1,
            last: entry.date.isAfter(old.last) ? entry.date : old.last,
            item: entry.date.isAfter(old.last) ? item : old.item,
          );
    final same = <String, ({int count, DateTime last, MealItem item})>{};
    final other = <String, ({int count, DateTime last, MealItem item})>{};
    for (final entry in entries) {
      if (entry.day < start || entry.day > today) continue;
      for (final item in entry.items) {
        if (item.name.trim().isEmpty || item.grams <= 0 || FoodSearch.normalized(item.name) == 'wasser') continue;
        final key = FoodSearch.normalized(item.name);
        final groups = entry.category == category ? same : other;
        groups[key] = merge(groups[key], entry, item);
      }
    }
    int byUse(({int count, DateTime last, MealItem item}) a, ({int count, DateTime last, MealItem item}) b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : b.last.compareTo(a.last);
    }

    final ranked = [...(same.values.toList()..sort(byUse)), ...(other.values.toList()..sort(byUse))];
    final seen = <String>{};
    return [
      for (final group in ranked)
        if (seen.add(FoodSearch.normalized(group.item.name))) group.item,
    ].take(limit).toList();
  }

  /// Open Food Facts erst ab drei Zeichen (Suchanfragen sind dort auf etwa 10 je Minute begrenzt).
  static const onlineMinimumLength = 3;

  /// Suche bei Open Food Facts, Produkte aus Deutschland zuerst (Unterdomäne `de`), nur benötigte Felder.
  static Uri searchUri(String query, {int pageSize = 24}) => Uri.https('de.openfoodfacts.org', '/cgi/search.pl', {
    'search_terms': query.trim(),
    'search_simple': '1',
    'action': 'process',
    'json': '1',
    'page_size': '$pageSize',
    'fields': OpenFoodFacts.fields,
  });

  /// Produkte der Antwort; ohne Kalorienangabe oder Barcode fallen sie weg, Doppelte (gleicher Barcode) einmal.
  static List<OpenFoodFactsProduct> searchResults(JsonValue json) {
    final seen = <String>{};
    return [
      for (final product in json['products']?.arrayValue ?? const <JsonValue>[])
        if (product['code']?.stringValue case final code? when code.isNotEmpty && seen.add(code))
          ?OpenFoodFacts.product(JsonValue({'status': 1, 'product': product.raw}), barcode: code),
    ];
  }

  /// Lokale Treffer (eigene Lebensmittel zuerst, dann BLS), gefiltert.
  static List<FoodProduct> local(String query, {required List<MealItem> own, required ProductFilter filter}) {
    if (FoodSearch.normalized(query).isEmpty) return [];
    final words = FoodSearch.normalized(query).split(' ').where((word) => word.isNotEmpty).toList();
    return [
      if (filter.includes(ProductSource.own))
        for (final food in own)
          if (words.every(FoodSearch.normalized(food.name).contains)) FoodProduct.own(food),
      if (filter.includes(ProductSource.bls))
        for (final food in BLS.search(query, limit: 30)) FoodProduct.bls(food),
    ].where(filter.matches).toList();
  }
}

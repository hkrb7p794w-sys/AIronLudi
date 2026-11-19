// Produktsuche: Open-Food-Facts-Suche lesen, lokale Treffer (eigene, BLS), Filter, Portion und Menge.
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => BLS.load(File('assets/bls.tsv').readAsStringSync()));

  test('Suche bei Open Food Facts: Adresse, Treffer ohne Kalorien und Doppelte fallen weg', () {
    final uri = ProductSearch.searchUri(' Skyr ');
    expect(uri.host, 'de.openfoodfacts.org');
    expect(uri.queryParameters['search_terms'], 'Skyr');
    expect(uri.queryParameters['json'], '1');
    final results = ProductSearch.searchResults(
      JsonValue({
        'count': 3,
        'products': [
          {
            'code': '4000000000001',
            'product_name_de': 'Skyr Natur',
            'brands': 'Molkerei, Handel',
            'serving_quantity': 150,
            'serving_size': '1 Becher (150 g)',
            'nutriments': {'energy-kcal_100g': 63, 'proteins_100g': 11, 'carbohydrates_100g': 4, 'fat_100g': 0.2},
          },
          {
            'code': '4000000000001',
            'product_name': 'Doppelt',
            'nutriments': {'energy-kcal_100g': 63},
          },
          {'code': '4000000000002', 'product_name': 'Ohne Nährwerte', 'nutriments': <String, Object?>{}},
          {
            'product_name': 'Ohne Barcode',
            'nutriments': {'energy-kcal_100g': 10},
          },
        ],
      }),
    );
    expect(results, hasLength(1));
    final product = FoodProduct.openFoodFacts(results.single);
    expect(product.title, 'Skyr Natur (Molkerei)');
    expect(product.source, ProductSource.openFoodFacts);
    expect(product.servingGrams, 150);
    expect(product.amount(Nutrient.protein, 150), closeTo(16.5, 0.01));
    final item = product.item(grams: 200);
    expect((item.grams, item.barcode, item.source), (200, '4000000000001', MealItemSource.openFoodFacts));
  });

  test('Volltextsuche (Search-a-licious): Adresse und Treffer unter „hits“ mit Markenliste', () {
    final uri = ProductSearch.fullTextUri(' Nutella ');
    expect(uri.host, 'search.openfoodfacts.org');
    expect(uri.path, '/search');
    expect(uri.queryParameters['q'], 'Nutella');
    expect(uri.queryParameters['fields'], OpenFoodFacts.fields);
    final results = ProductSearch.searchResults(
      JsonValue({
        'count': 2,
        'hits': [
          {
            'code': '3017620422003',
            'product_name': 'Nutella',
            'brands': ['Ferrero', 'Nutella'],
            'serving_quantity': '15',
            'serving_size': '15 g',
            'nutriments': {'energy-kcal_100g': 539, 'proteins_100g': 6.3, 'carbohydrates_100g': 57.5, 'fat_100g': 30.9},
          },
          {'code': '3017620422004', 'product_name': 'Ohne Nährwerte'},
        ],
      }),
    );
    final product = FoodProduct.openFoodFacts(results.single);
    expect(product.title, 'Nutella (Ferrero)');
    expect(product.defaultGrams, 15);
    expect(product.per100g[Nutrient.kcal], 539);
    expect(product.amount(Nutrient.fat, 100), closeTo(30.9, 0.01));
    expect(product.amount(Nutrient.carbs, 15), closeTo(8.625, 0.001));
  });

  test('lokal: eigene Lebensmittel zuerst, dann BLS; Filter nach Herkunft und Nährwerten', () {
    final own = [
      MealItem(
        name: 'Mein Proteinriegel',
        grams: 45,
        source: MealItemSource.manual,
        per100g: NutrientValues({Nutrient.kcal: 380, Nutrient.protein: 33}),
        portion: const Portion('Riegel', 45),
      ),
    ];
    final all = ProductSearch.local('riegel', own: own, filter: const ProductFilter());
    expect(all.first.source, ProductSource.own);
    expect(all.first.servingGrams, 45);
    final copy = all.first.item(grams: 90);
    expect(copy.grams, 90);
    expect(own.single.grams, 45);

    final haferflocken = ProductSearch.local('haferflocken', own: own, filter: const ProductFilter());
    expect(haferflocken, isNotEmpty);
    expect(haferflocken.every((product) => product.source == ProductSource.bls), isTrue);
    expect(
      ProductSearch.local(
        'riegel',
        own: own,
        filter: const ProductFilter(sources: {ProductSource.bls}),
      ).any((product) => product.source == ProductSource.own),
      isFalse,
    );
    final lowCalorie = ProductSearch.local('gurke', own: own, filter: const ProductFilter(lowCalorie: true));
    expect(lowCalorie, isNotEmpty);
    expect(lowCalorie.every((product) => (product.per100g[Nutrient.kcal] ?? 0) <= 100), isTrue);
    final protein = ProductSearch.local('riegel', own: own, filter: const ProductFilter(highProtein: true));
    expect(protein.every((product) => (product.per100g[Nutrient.protein] ?? 0) >= 15), isTrue);
    expect(ProductSearch.local('  ', own: own, filter: const ProductFilter()), isEmpty);
  });

  test('Vorschläge: um diese Zeit Häufiges zuerst, mit der letzten Menge; Wasser zählt nicht', () {
    final today = CalendarDay(2026, 11, 19);
    MealItem food(String name, double grams) => MealItem(
      name: name,
      grams: grams,
      source: MealItemSource.manual,
      per100g: NutrientValues({Nutrient.kcal: 100}),
    );
    MealEntry entry(int daysAgo, MealCategory category, List<MealItem> items) {
      final day = today.adding(-daysAgo);
      return MealEntry(
        day: day,
        date: DateTime(day.year, day.month, day.day, 12),
        category: category,
        title: items.first.name,
        items: items,
      );
    }

    final entries = [
      entry(3, MealCategory.lunch, [food('Skyr', 150), food('Wasser', 500)]),
      entry(2, MealCategory.lunch, [food('Skyr', 200), food('Haferflocken', 60)]),
      entry(1, MealCategory.lunch, [food('Banane', 120)]),
      entry(1, MealCategory.dinner, [food('Nudeln', 125), food('Nudeln', 125)]),
      entry(5, MealCategory.dinner, [food('Nudeln', 100)]),
      entry(90, MealCategory.lunch, [food('Alt', 100)]),
    ];
    final picks = ProductSearch.picks(entries, category: MealCategory.lunch, today: today);
    expect(picks.map((item) => item.name), ['Skyr', 'Banane', 'Haferflocken', 'Nudeln']);
    expect(picks.first.grams, 200);
    expect(FoodProduct.own(picks.first).defaultGrams, 200);
    expect(ProductSearch.picks(entries, category: MealCategory.lunch, today: today, limit: 2), hasLength(2));
  });
}

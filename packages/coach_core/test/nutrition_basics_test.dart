// Port der Wasser- und Mahlzeiten-Fälle aus CoachCoreTests/AppRouteTests.swift (MealWidgetRuleTests) sowie
// Prüfungen, dass die JSON-Formate zu Swift passen (Sicherungen und geteilte Mahlzeiten).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  test('Wasser zählt Getränke und das Wasser im Essen', () {
    final coffee = MealItem(
      name: 'Kaffee',
      grams: 250,
      source: MealItemSource.bls,
      per100g: NutrientValues({Nutrient.water: 98}),
      isDrink: true,
    );
    final juice = MealItem(
      name: 'Saft',
      grams: 200,
      source: MealItemSource.ai,
      per100g: NutrientValues({Nutrient.kcal: 45}),
      isDrink: true,
    );
    final soup = MealItem(
      name: 'Suppe',
      grams: 300,
      source: MealItemSource.bls,
      per100g: NutrientValues({Nutrient.water: 90}),
    );
    final bread = MealItem(
      name: 'Brot',
      grams: 50,
      source: MealItemSource.manual,
      per100g: NutrientValues({Nutrient.kcal: 250}),
    );
    final total = Hydration.total([coffee, juice, soup, bread, MealItem.water(milliliters: 500)]);
    expect(total.drinks, 245 + 200 + 500);
    expect(total.food, 270);
    expect(total.total, 1215);
  });

  test('Mahlzeiten-Anteile ergeben den Tag', () {
    final sum = MealSplit.order
        .map((category) => MealSplit.target(category, dayKilocalories: 2000)!)
        .reduce((a, b) => a + b);
    expect(sum, 2000);
    expect(MealSplit.target(MealCategory.other, dayKilocalories: 2000), 200);
    expect(MealSplit.target(MealCategory.lunch), isNull);
  });

  test('MealItem liest und schreibt das Swift-Format', () {
    // So schreibt die Swift-App eine Position (synthetisiertes Codable, fehlende Optionale entfallen).
    const swift =
        '{"id":"0F8E3B5C-2D4A-4F6B-9C1D-7E2A3B4C5D6E","name":"Brot","grams":60,"isDrink":false,'
        '"source":"KI","per100g":{"kcal":250,"protein_g":8.5,"unbekannt_x":1},'
        '"portion":{"name":"Scheibe","grams":30},"searchTerm":"Brot"}';
    final item = MealItem.fromJson(jsonDecode(swift))!;
    expect(item.id, '0F8E3B5C-2D4A-4F6B-9C1D-7E2A3B4C5D6E');
    expect(item.source, MealItemSource.ai);
    expect(item.per100g[Nutrient.protein], 8.5);
    expect(item.portion, const Portion('Scheibe', 30));
    expect(item.amountText, isNull);
    final written = item.toJson();
    expect(written.containsKey('amountText'), isFalse);
    expect(written['per100g'], {'kcal': 250, 'protein_g': 8.5});
    expect(MealItem.fromJson(jsonDecode(jsonEncode(written))), item);
  });

  test('neue IDs im Swift-Format (Großbuchstaben)', () {
    final id = MealItem.water(milliliters: 250).id;
    expect(RegExp(r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$').hasMatch(id), isTrue);
  });

  test('Barcode-Prüfziffer und Open-Food-Facts-Antwort', () {
    expect(OpenFoodFacts.isValidBarcode('4006381333931'), isTrue);
    expect(OpenFoodFacts.isValidBarcode('4006381333932'), isFalse);
    expect(OpenFoodFacts.isValidBarcode('12345'), isFalse);
    final json = JsonValue({
      'status': 1,
      'product': {
        'product_name_de': 'Haferriegel',
        'brands': 'Marke A, Marke B',
        'serving_quantity': 45,
        'serving_size': '1 Riegel (45 g)',
        'nutriments': {'energy_100g': 1674, 'proteins_100g': 10, 'sodium_100g': 0.2},
      },
    });
    final product = OpenFoodFacts.product(json, barcode: '4006381333931')!;
    expect(product.name, 'Haferriegel');
    expect(product.brand, 'Marke A');
    expect(product.per100g[Nutrient.kcal], 400);
    expect(product.per100g[Nutrient.sodium], 200);
    final item = product.item();
    expect(item.name, 'Haferriegel (Marke A)');
    expect(item.grams, 45);
    expect(item.portion, const Portion('Riegel', 45));
    expect(OpenFoodFacts.product(const JsonValue({'status': 0}), barcode: '1'), isNull);
  });

  test('JsonValue sucht tolerant wie in Swift', () {
    final json = JsonValue.parse('{"b":{"x":{"value":null}},"a":[{"value":5}],"value2":"7"}');
    expect(json.firstValue(['value'])?.doubleValue, 5);
    expect(json['value2']?.doubleValue, 7);
    expect(json['value2']?.intValue, 7);
    expect(const JsonValue(3.0).stringValue, '3');
    expect(const JsonValue(2.5).stringValue, '2.5');
    expect(const JsonValue(1e20).clampedInt(0, 100), 100);
    expect(json.objects('value').length, 2);
    expect(json.keyPaths(), ['a[].value', 'b.x.value', 'value2']);
    expect(const JsonValue({'a': 1}), const JsonValue({'a': 1.0}));
  });

  test('deutsche Zahlen', () {
    expect(GermanFormat.decimal(4.5), '4,5');
    expect(GermanFormat.decimal(6.04), '6');
    expect(GermanFormat.number(13.75), '13,75');
    expect(GermanFormat.number(52.5), '52,5');
    expect(GermanFormat.number(55), '55');
    expect(GermanFormat.date(const CalendarDay(2026, 3, 7)), '07.03.2026');
    expect(GermanFormat.minutesSeconds(305), '5:05');
  });
}

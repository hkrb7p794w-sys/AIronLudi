import '../json/json_value.dart';
import 'meal.dart';
import 'nutrient.dart';

/// Produkt aus Open Food Facts.
final class OpenFoodFactsProduct {
  const OpenFoodFactsProduct({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.servingGrams,
    required this.servingText,
    required this.per100g,
  });

  final String barcode;
  final String name;
  final String? brand;
  final double? servingGrams;

  /// Packungsangabe zur Portion, z. B. „1 Riegel (45 g)“.
  final String? servingText;
  final NutrientValues per100g;

  MealItem item({double? grams}) => MealItem(
    name: brand == null ? name : '$name ($brand)',
    grams: grams ?? servingGrams ?? 100,
    source: MealItemSource.openFoodFacts,
    per100g: per100g.copy(),
    barcode: barcode,
    portion: PortionGuess.serving(text: servingText, grams: servingGrams),
  );
}

/// Open Food Facts – Produktabfrage per Barcode (API v2).
///
/// Regeln laut OFF-Doku: eigener User-Agent, höchstens 15 Produktabfragen je Minute. Daten unter Open Database
/// License (ODbL), © Open Food Facts contributors. Werte in `nutriments` sind je 100 g; Mineralstoffe und Vitamine
/// stehen dort in Gramm.
abstract final class OpenFoodFacts {
  static const userAgent = 'AIronLudi/2.0 (Flutter; privat)';
  static const fields =
      'code,product_name,product_name_de,generic_name_de,brands,quantity,serving_quantity,serving_size,nutriments';

  /// Prüfziffer nach GS1 für EAN-8, UPC-A, EAN-13 und GTIN-14.
  static bool isValidBarcode(String text) {
    if (!RegExp(r'^[0-9]+$').hasMatch(text) || !const [8, 12, 13, 14].contains(text.length)) return false;
    final digits = text.split('').map(int.parse).toList();
    final check = digits.last;
    final body = digits.sublist(0, digits.length - 1).reversed.toList();
    var sum = 0;
    for (var offset = 0; offset < body.length; offset++) {
      sum += body[offset] * (offset.isEven ? 3 : 1);
    }
    return (10 - sum % 10) % 10 == check;
  }

  static Uri productUri(String barcode) =>
      Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode', {'fields': fields});

  static const _mapping = <(String, Nutrient, double)>[
    ('energy-kcal', Nutrient.kcal, 1),
    ('proteins', Nutrient.protein, 1),
    ('carbohydrates', Nutrient.carbs, 1),
    ('sugars', Nutrient.sugar, 1),
    ('fat', Nutrient.fat, 1),
    ('saturated-fat', Nutrient.saturatedFat, 1),
    ('fiber', Nutrient.fiber, 1),
    ('sodium', Nutrient.sodium, 1000),
    ('potassium', Nutrient.potassium, 1000),
    ('magnesium', Nutrient.magnesium, 1000),
    ('calcium', Nutrient.calcium, 1000),
    ('iron', Nutrient.iron, 1000),
    ('zinc', Nutrient.zinc, 1000),
    ('vitamin-d', Nutrient.vitaminD, 1000000),
    ('vitamin-b12', Nutrient.vitaminB12, 1000000),
    ('vitamin-c', Nutrient.vitaminC, 1000),
    ('iodine', Nutrient.iodine, 1000000),
  ];

  /// Liest die API-Antwort. `null`, wenn das Produkt unbekannt ist oder keine Kalorienangabe hat.
  static OpenFoodFactsProduct? product(JsonValue json, {required String barcode}) {
    final product = json['product'];
    final nutriments = product?['nutriments'];
    if (json['status']?.doubleValue == 0 || product == null || nutriments == null) return null;
    final values = NutrientValues();
    for (final (key, nutrient, factor) in _mapping) {
      final value = nutriments['${key}_100g']?.doubleValue;
      if (value != null && value >= 0) values[nutrient] = value * factor;
    }
    if (values[Nutrient.kcal] == null) {
      final kilojoule = nutriments['energy_100g']?.doubleValue;
      if (kilojoule != null) values[Nutrient.kcal] = (kilojoule / 4.184).roundToDouble();
    }
    final omega3 = [
      'eicosapentaenoic-acid',
      'docosahexaenoic-acid',
    ].map((key) => nutriments['${key}_100g']?.doubleValue).nonNulls.toList();
    if (omega3.isNotEmpty) values[Nutrient.omega3] = omega3.reduce((a, b) => a + b) * 1000;
    if (values[Nutrient.kcal] == null) return null;
    final names = [
      'product_name_de',
      'product_name',
      'generic_name_de',
    ].map((key) => product[key]?.stringValue).nonNulls;
    final name = names.where((candidate) => candidate.trim().isNotEmpty).firstOrNull ?? 'Produkt $barcode';
    final brand = product['brands']?.stringValue?.split(',').first.trim();
    final serving = product['serving_quantity']?.doubleValue;
    return OpenFoodFactsProduct(
      barcode: barcode,
      name: name,
      brand: brand == null || brand.isEmpty ? null : brand,
      servingGrams: serving != null && serving > 0 ? serving : null,
      servingText: product['serving_size']?.stringValue,
      per100g: values,
    );
  }
}

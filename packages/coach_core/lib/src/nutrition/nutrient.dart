import 'package:collection/collection.dart';

/// Kanonische Nährwerte (wie `nutrients.py` im Altbestand). Alle Quellen – KI-Schätzung, Open Food Facts, BLS,
/// eigene Eingaben – werden auf diese Schlüssel und Einheiten normalisiert. Die Rohwerte stehen in Sicherungen.
enum Nutrient {
  kcal('kcal', 'Kalorien', 'kcal'),
  protein('protein_g', 'Protein', 'g'),
  carbs('carbs_g', 'Kohlenhydrate', 'g'),
  sugar('sugar_g', 'davon Zucker', 'g'),
  fat('fat_g', 'Fett', 'g'),
  saturatedFat('satfat_g', 'davon gesättigt', 'g'),
  fiber('fiber_g', 'Ballaststoffe', 'g'),
  water('water_ml', 'Flüssigkeit', 'ml'),
  sodium('sodium_mg', 'Natrium', 'mg'),
  potassium('potassium_mg', 'Kalium', 'mg'),
  magnesium('magnesium_mg', 'Magnesium', 'mg'),
  calcium('calcium_mg', 'Calcium', 'mg'),
  iron('iron_mg', 'Eisen', 'mg'),
  zinc('zinc_mg', 'Zink', 'mg'),
  vitaminD('vitd_ug', 'Vitamin D', 'µg'),
  vitaminB12('b12_ug', 'Vitamin B12', 'µg'),
  vitaminC('vitc_mg', 'Vitamin C', 'mg'),
  iodine('iodine_ug', 'Jod', 'µg'),
  omega3('omega3_mg', 'Omega-3 (EPA+DHA)', 'mg');

  const Nutrient(this.rawValue, this.label, this.unit);

  final String rawValue;
  final String label;
  final String unit;

  static Nutrient? fromRaw(String raw) => values.firstWhereOrNull((nutrient) => nutrient.rawValue == raw);

  bool get isMacro => switch (this) {
    kcal || protein || carbs || sugar || fat || saturatedFat || fiber => true,
    _ => false,
  };

  /// Obergrenze statt Mindestziel (Zucker, gesättigte Fette) bzw. nur Referenz (Natrium).
  bool get isUpperLimit => this == sugar || this == saturatedFat || this == sodium;
}

/// Nährwerte als Zuordnung Nährstoff → Menge. Fehlende Werte sind unbekannt, nicht 0.
final class NutrientValues {
  NutrientValues([Map<Nutrient, double> values = const {}])
    : _values = {
        for (final entry in values.entries)
          if (entry.value.isFinite) entry.key: entry.value,
      };

  final Map<Nutrient, double> _values;

  Map<Nutrient, double> get values => Map.unmodifiable(_values);

  double? operator [](Nutrient nutrient) => _values[nutrient];

  /// Setzt oder löscht (`null`, nicht endlich) einen Wert.
  void operator []=(Nutrient nutrient, double? value) {
    if (value == null || !value.isFinite) {
      _values.remove(nutrient);
    } else {
      _values[nutrient] = value;
    }
  }

  bool get isEmpty => _values.isEmpty;

  NutrientValues copy() => NutrientValues(_values);

  /// Werte je 100 g auf eine Menge umrechnen.
  NutrientValues scaledToGrams(double grams) =>
      NutrientValues(_values.map((nutrient, value) => MapEntry(nutrient, value * grams / 100)));

  NutrientValues operator +(NutrientValues other) {
    final merged = Map<Nutrient, double>.of(_values);
    for (final entry in other._values.entries) {
      merged[entry.key] = (merged[entry.key] ?? 0) + entry.value;
    }
    return NutrientValues(merged);
  }

  /// JSON wie in Swift: Objekt mit den Rohwerten als Schlüssel. Unbekannte Schlüssel werden beim Lesen übergangen.
  Map<String, double> toJson() => {for (final entry in _values.entries) entry.key.rawValue: entry.value};

  static NutrientValues fromJson(Object? json) {
    final result = NutrientValues();
    if (json is Map) {
      for (final entry in json.entries) {
        final nutrient = Nutrient.fromRaw(entry.key as String);
        final value = entry.value;
        if (nutrient != null && value is num) result[nutrient] = value.toDouble();
      }
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is NutrientValues && const MapEquality<Nutrient, double>().equals(_values, other._values);

  @override
  int get hashCode => const MapEquality<Nutrient, double>().hash(_values);

  @override
  String toString() => 'NutrientValues($_values)';
}

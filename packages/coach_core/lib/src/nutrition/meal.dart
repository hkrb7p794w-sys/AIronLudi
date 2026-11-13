import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../json/json_value.dart';
import '../util/german_format.dart';
import 'bls.dart';
import 'meal_category.dart';
import 'nutrient.dart';
import 'open_food_facts.dart';

/// Herkunft der Nährwerte einer Position. Die Rohwerte stehen in Sicherungen und geteilten Mahlzeiten.
enum MealItemSource {
  ai('KI'),
  openFoodFacts('Open Food Facts'),
  manual('Eigene Angabe'),
  bls('BLS 4.0');

  const MealItemSource(this.rawValue);

  final String rawValue;

  static MealItemSource? fromRaw(String? raw) => values.firstWhereOrNull((source) => source.rawValue == raw);
}

/// Neue ID im Format von Swift (`UUID().uuidString`: Großbuchstaben).
String newUuid() => const Uuid().v4().toUpperCase();

/// Portion eines Lebensmittels: „Scheibe“ à 30 g, „Riegel“ à 45 g. Wer isst, denkt in Stück, nicht in Gramm.
final class Portion {
  const Portion(this.name, this.grams);

  final String name;
  final double grams;

  Map<String, Object?> toJson() => {'name': name, 'grams': grams};

  static Portion? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final grams = json['grams'];
    if (name is! String || grams is! num) return null;
    return Portion(name, grams.toDouble());
  }

  @override
  bool operator ==(Object other) => other is Portion && other.name == name && other.grams == grams;

  @override
  int get hashCode => Object.hash(name, grams);

  @override
  String toString() => 'Portion($name, $grams)';
}

/// Eine Position einer Mahlzeit.
final class MealItem {
  MealItem({
    required this.name,
    required this.grams,
    required this.source,
    required this.per100g,
    String? id,
    this.amountText,
    this.isDrink = false,
    this.confidence,
    this.group,
    this.barcode,
    this.portion,
    this.blsCode,
    this.searchTerm,
    this.plannedGrams,
  }) : id = id ?? newUuid();

  /// Wasser als Getränk (Schnell-Eintrag), Menge in ml.
  factory MealItem.water({required double milliliters}) => MealItem(
    name: 'Wasser',
    grams: milliliters,
    source: MealItemSource.manual,
    per100g: NutrientValues({Nutrient.water: 100}),
    isDrink: true,
  );

  String id;
  String name;
  double grams;
  String? amountText;
  bool isDrink;

  /// `hoch`, `mittel`, `niedrig` (Einschätzung der KI).
  String? confidence;
  String? group;
  String? barcode;
  MealItemSource source;
  NutrientValues per100g;

  /// Portion des Lebensmittels (z. B. „Scheibe“ à 30 g), damit Mengen in Stück statt Gramm eingegeben werden.
  Portion? portion;

  /// Lebensmittel aus dem Bundeslebensmittelschlüssel, dessen Nährwerte übernommen wurden.
  String? blsCode;

  /// Generische Bezeichnung der KI für die Suche im BLS (z. B. „Hühnerei gekocht“).
  String? searchTerm;

  /// Menge vor einer Portionsanpassung („nur 75 % gegessen“); `null` = nie angepasst.
  double? plannedGrams;

  NutrientValues get amounts => per100g.scaledToGrams(grams);

  /// Menge in Portionen (z. B. 1,5 Scheiben); `null` ohne bekannte Portion.
  double? get portionCount {
    final portion = this.portion;
    if (portion == null || portion.grams <= 0) return null;
    return grams / portion.grams;
  }

  void setPortions(double count) {
    final portion = this.portion;
    if (portion == null || portion.grams <= 0) return;
    grams = _roundTenth(count * portion.grams);
  }

  /// Menge mit Faktor (½ Rezept, doppelte Portion).
  MealItem scaledBy(double factor) => copy()..grams = _roundTenth(grams * factor);

  /// „2 × Scheibe (60 g)“ bzw. „150 g“.
  String get amountLabel {
    final unit = isDrink ? 'ml' : 'g';
    final portion = this.portion;
    final count = portionCount;
    if (portion == null || count == null) return '${GermanFormat.number(grams)} $unit';
    return '${PortionGuess.format(count)} × ${portion.name} (${GermanFormat.number(grams.roundToDouble())} $unit)';
  }

  static double _roundTenth(double value) {
    final rounded = (value * 10).roundToDouble() / 10;
    return rounded < 0 ? 0 : rounded;
  }

  MealItem copy() => MealItem(
    id: id,
    name: name,
    grams: grams,
    source: source,
    per100g: per100g.copy(),
    amountText: amountText,
    isDrink: isDrink,
    confidence: confidence,
    group: group,
    barcode: barcode,
    portion: portion,
    blsCode: blsCode,
    searchTerm: searchTerm,
    plannedGrams: plannedGrams,
  );

  /// JSON wie das synthetisierte `Codable` in Swift (fehlende Optionale entfallen).
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'grams': grams,
    'amountText': ?amountText,
    'isDrink': isDrink,
    'confidence': ?confidence,
    'group': ?group,
    'barcode': ?barcode,
    'source': source.rawValue,
    'per100g': per100g.toJson(),
    'portion': ?portion?.toJson(),
    'blsCode': ?blsCode,
    'searchTerm': ?searchTerm,
    'plannedGrams': ?plannedGrams,
  };

  static MealItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final grams = json['grams'];
    final source = MealItemSource.fromRaw(json['source'] as String?);
    if (name is! String || grams is! num || source == null) return null;
    return MealItem(
      id: json['id'] as String?,
      name: name,
      grams: grams.toDouble(),
      source: source,
      per100g: NutrientValues.fromJson(json['per100g']),
      amountText: json['amountText'] as String?,
      isDrink: json['isDrink'] as bool? ?? false,
      confidence: json['confidence'] as String?,
      group: json['group'] as String?,
      barcode: json['barcode'] as String?,
      portion: Portion.fromJson(json['portion']),
      blsCode: json['blsCode'] as String?,
      searchTerm: json['searchTerm'] as String?,
      plannedGrams: (json['plannedGrams'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MealItem &&
      other.id == id &&
      other.name == name &&
      other.grams == grams &&
      other.amountText == amountText &&
      other.isDrink == isDrink &&
      other.confidence == confidence &&
      other.group == group &&
      other.barcode == barcode &&
      other.source == source &&
      other.per100g == per100g &&
      other.portion == portion &&
      other.blsCode == blsCode &&
      other.searchTerm == searchTerm &&
      other.plannedGrams == plannedGrams;

  @override
  int get hashCode => Object.hash(id, name, grams, source, per100g);

  @override
  String toString() => 'MealItem($name, $grams, ${source.rawValue})';
}

/// Ergebnis der KI-Analyse einer Mahlzeit (Foto oder Text).
final class MealAnalysis {
  MealAnalysis._({
    required this.title,
    required this.category,
    required this.hint,
    required this.items,
    required this.possiblyMissing,
  });

  final String title;
  final MealCategory? category;
  final String hint;
  final List<MealItem> items;

  /// Oft übersehene Bestandteile, die nicht sicher zu sehen waren („Bratöl“, „Soße“) – zum Antippen beim Ergänzen.
  final List<String> possiblyMissing;

  /// Liest die Antwort der Worker-Aufgabe `meal_analyze`; `null` ohne verwertbare Positionen.
  static MealAnalysis? fromOutput(JsonValue output) {
    final rawItems = output['items']?.arrayValue;
    if (rawItems == null) return null;
    final items = rawItems.map(item).nonNulls.toList();
    if (items.isEmpty) return null;
    final title = output['titel']?.stringValue ?? '';
    return MealAnalysis._(
      title: title.length > 60 ? title.substring(0, 60) : title,
      category: MealCategory.fromRaw(output['kategorie']?.stringValue),
      hint: output['hinweis']?.stringValue ?? '',
      items: items,
      possiblyMissing: missing(output),
    );
  }

  static List<String> missing(JsonValue output) {
    // Nur echte Texte (keine Zahlen, die `stringValue` sonst umwandelt).
    return (output['vielleicht_vergessen']?.arrayValue ?? const <JsonValue>[])
        .map((value) => value.textValue)
        .nonNulls
        .map((text) {
          final trimmed = text.trim();
          return trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
        })
        .where((text) => text.isNotEmpty)
        .take(4)
        .toList();
  }

  /// Antwort von `meal_amend`: nur die neuen Positionen (dürfen leer sein) und ein Hinweis. Die bestehenden Positionen
  /// bleiben unangetastet – die App hängt die neuen an.
  static ({List<MealItem> items, String hint}) amendment(JsonValue output) => (
    items: (output['items']?.arrayValue ?? const <JsonValue>[]).map(item).nonNulls.toList(),
    hint: output['hinweis']?.stringValue ?? '',
  );

  static MealItem? item(JsonValue value) {
    final name = value['name']?.stringValue;
    final grams = value['menge_g']?.doubleValue;
    if (name == null || name.isEmpty || grams == null || grams <= 0 || grams > 5000) return null;
    final per100g = NutrientValues();
    final nutrients = value['naehrwerte_100g']?.objectValue;
    if (nutrients != null) {
      for (final nutrient in Nutrient.values) {
        final key = nutrient == Nutrient.water ? 'water_g' : nutrient.rawValue;
        final amount = nutrients[key]?.doubleValue;
        if (amount != null && amount.isFinite && amount >= 0) per100g[nutrient] = amount;
      }
    }
    final item = MealItem(name: name, grams: grams, source: MealItemSource.ai, per100g: per100g)
      ..amountText = value['menge_text']?.stringValue
      ..isDrink = value['getraenk']?.boolValue == true
      ..confidence = value['sicherheit']?.stringValue
      ..group = value['gruppe']?.stringValue;
    final barcode = value['barcode']?.stringValue;
    item.barcode = barcode != null && OpenFoodFacts.isValidBarcode(barcode) ? barcode : null;
    item.portion = PortionGuess.fromAmountText(item.amountText, grams: grams);
    final searchTerm = value['suchbegriff']?.stringValue;
    item.searchTerm = searchTerm == null || searchTerm.length <= 80 ? searchTerm : searchTerm.substring(0, 80);
    return BLS.enrich(item);
  }
}

/// Summe einer Liste von Positionen und Fortschritt gegenüber den Tageszielen.
abstract final class NutritionSummary {
  static NutrientValues totals(Iterable<MealItem> items) =>
      items.fold(NutrientValues(), (sum, item) => sum + item.amounts);

  /// Anteil des Ziels in Prozent (bei Obergrenzen: Anteil der Grenze).
  static int? percent(double? value, double? target) {
    if (target == null || target <= 0) return null;
    return ((value ?? 0) / target * 100).round();
  }
}

abstract final class PortionGuess {
  /// Einheiten, die keine Portion sind.
  static const massUnits = {'g', 'gramm', 'kg', 'ml', 'l', 'liter', 'mg', 'cl'};

  /// Plural → Singular für die häufigsten Portionen.
  static const singular = {
    'scheiben': 'Scheibe',
    'stück': 'Stück',
    'stücke': 'Stück',
    'eier': 'Ei',
    'gläser': 'Glas',
    'tassen': 'Tasse',
    'becher': 'Becher',
    'portionen': 'Portion',
    'riegel': 'Riegel',
    'brötchen': 'Brötchen',
    'packungen': 'Packung',
    'dosen': 'Dose',
    'flaschen': 'Flasche',
    'bananen': 'Banane',
    'äpfel': 'Apfel',
    'esslöffel': 'EL',
    'el': 'EL',
    'teelöffel': 'TL',
    'tl': 'TL',
    'handvoll': 'Handvoll',
    'schalen': 'Schale',
    'schüsseln': 'Schüssel',
    'teller': 'Teller',
    'kugeln': 'Kugel',
    'würfel': 'Würfel',
    'beutel': 'Beutel',
    'kapseln': 'Kapsel',
  };

  static const words = {'ein': 1.0, 'eine': 1.0, 'einen': 1.0, 'zwei': 2.0, 'drei': 3.0, 'vier': 4.0, 'halbe': 0.5};

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _punctuation = RegExp(r'^[\p{P}]+|[\p{P}]+$', unicode: true);

  /// Aus der KI-Angabe „2 Scheiben“ und 60 g → Scheibe à 30 g. Reine Gewichtsangaben („150 g“) ergeben nichts.
  static Portion? fromAmountText(String? amountText, {required double grams}) {
    final text = amountText?.trim();
    if (text == null || text.isEmpty || grams <= 0) return null;
    final parts = text.replaceAll('(', ' ').split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final count = number(parts[0]);
    if (count == null || count <= 0) return null;
    final unit = parts[1].replaceAll(_punctuation, '');
    if (unit.isEmpty || massUnits.contains(unit.toLowerCase()) || !_letter.hasMatch(unit[0])) return null;
    final name = singular[unit.toLowerCase()] ?? unit;
    return Portion(name, (grams / count * 10).roundToDouble() / 10);
  }

  /// Aus der Packungsangabe „1 Riegel (45 g)“ bzw. nur der Portionsmenge → „Portion“.
  static Portion? serving({String? text, double? grams}) {
    if (grams == null || grams <= 0) return null;
    return fromAmountText(text, grams: grams) ?? Portion('Portion', grams);
  }

  static double? number(String? text) {
    if (text == null) return null;
    final lower = text.toLowerCase();
    final word = words[lower];
    if (word != null) return word;
    if (lower == '½') return 0.5;
    if (lower.endsWith('½')) {
      final whole = double.tryParse(lower.substring(0, lower.length - 1));
      if (whole != null) return whole + 0.5;
    }
    return double.tryParse(lower.replaceAll(',', '.'));
  }

  /// 0,5 → „½“, 1,5 → „1½“, 2 → „2“, 1,25 → „1,25“.
  static String format(double count) {
    final rounded = (count * 100).roundToDouble() / 100;
    final whole = rounded.floorToDouble();
    if ((rounded - whole - 0.5).abs() < 0.01) return whole == 0 ? '½' : '${whole.toInt()}½';
    return GermanFormat.number(rounded);
  }

  /// Schnelltasten im Entwurf.
  static const quickCounts = [0.5, 1.0, 1.5, 2.0];
}

/// Lücken und Widersprüche in Nährwerten (Open Food Facts ist oft unvollständig).
abstract final class NutrientCheck {
  /// Wie viele Positionen keinen Wert für den Nährstoff haben – leere Werte zählen sonst still als 0.
  static int missing(Nutrient nutrient, Iterable<MealItem> items) =>
      items.where((item) => item.per100g[nutrient] == null).length;

  /// Energie aus den Makros (4 kcal/g Protein und KH, 9 kcal/g Fett, 2 kcal/g Ballaststoffe).
  static double? energyFromMacros(NutrientValues values) {
    final protein = values[Nutrient.protein];
    final carbs = values[Nutrient.carbs];
    final fat = values[Nutrient.fat];
    if (protein == null || carbs == null || fat == null) return null;
    return protein * 4 + carbs * 4 + fat * 9 + (values[Nutrient.fiber] ?? 0) * 2;
  }

  /// Hinweis, wenn kcal und Makros um mehr als 15 % auseinanderliegen (ab 20 kcal je 100 g).
  static String? energyMismatch(NutrientValues values) {
    final kcal = values[Nutrient.kcal];
    final computed = energyFromMacros(values);
    if (kcal == null || computed == null) return null;
    final larger = kcal > computed ? kcal : computed;
    if (larger < 20 || (kcal - computed).abs() / larger <= 0.15) return null;
    return 'Laut Makros etwa ${computed.round()} kcal je 100 g, eingetragen ${kcal.round()}. Bitte Etikett prüfen.';
  }
}

/// Antwort der Worker-Aufgabe `nutrition_label`: Nährwerttabelle vom Foto (Werte je 100 g wie auf dem Etikett).
abstract final class NutritionLabel {
  static MealItem? item(JsonValue output) {
    final per100g = NutrientValues();
    final nutrients = output['naehrwerte_100g']?.objectValue;
    if (nutrients != null) {
      for (final nutrient in Nutrient.values) {
        final key = nutrient == Nutrient.water ? 'water_g' : nutrient.rawValue;
        final amount = nutrients[key]?.doubleValue;
        if (amount != null && amount >= 0) per100g[nutrient] = amount;
      }
    }
    if (per100g[Nutrient.kcal] == null) return null;
    final rawName = output['name']?.stringValue ?? '';
    final name = rawName.length > 80 ? rawName.substring(0, 80) : rawName;
    final portionValue = output['portion_g']?.doubleValue;
    final portionGrams = portionValue != null && portionValue > 0 ? portionValue : null;
    final item = MealItem(name: name, grams: portionGrams ?? 100, source: MealItemSource.manual, per100g: per100g)
      ..isDrink = output['getraenk']?.boolValue == true;
    if (portionGrams != null) {
      final rawPortion = output['portion_name']?.stringValue;
      final portionName = rawPortion == null || rawPortion.isEmpty
          ? 'Portion'
          : (rawPortion.length > 30 ? rawPortion.substring(0, 30) : rawPortion);
      item.portion = Portion(portionName, portionGrams);
    }
    return item;
  }
}

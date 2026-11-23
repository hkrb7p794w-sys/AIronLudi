// Fuel Planner: Produkte für unterwegs (Gels, Getränke, eigene Mischungen, Riegel, Salztabletten) mit Nährwerten je
// Portion. Spezifikation 6 (docs/FUEL_PLANNER_SCIENCE.md).
import 'package:collection/collection.dart';

import '../nutrition/meal.dart';
import '../util/enum_codec.dart';

enum FuelProductKind implements RawEnum {
  gel('Gel', 'Gel'),
  drink('Getränk', 'Flasche'),
  drinkMix('Eigene Mischung', 'Flasche'),
  bar('Riegel', 'Riegel'),
  chew('Kaudragees', 'Portion'),
  food('Essen', 'Stück'),
  electrolyte('Salztablette', 'Tablette');

  const FuelProductKind(this.label, this.servingLabel);

  final String label;

  /// Übliche Bezeichnung einer Portion.
  final String servingLabel;

  bool get isDrink => this == drink || this == drinkMix;

  /// Wird in ganzen Portionen gegessen (Gel, Riegel …).
  bool get isSolid => this == gel || this == bar || this == chew || this == food;

  @override
  String get rawValue => name;
}

/// Eigene Getränkemischung je Flasche. Kohlenhydrate wie auf üblichen Etiketten: Maltodextrin ≈ 95 %, Dextrose als
/// Monohydrat ≈ 91 %, Fruktose und Haushaltszucker 100 % (Zucker zur Hälfte Fruktose). Kochsalz enthält 39,3 %
/// Natrium.
final class FuelMix {
  const FuelMix({
    this.maltodextrin = 0,
    this.dextrose = 0,
    this.fructose = 0,
    this.sucrose = 0,
    this.salt = 0,
    required this.waterMilliliters,
    this.caffeineMilligrams = 0,
  });

  final double maltodextrin;
  final double dextrose;
  final double fructose;
  final double sucrose;

  /// Kochsalz in g.
  final double salt;
  final double waterMilliliters;
  final double caffeineMilligrams;

  static const sodiumPerGramSalt = 393.0;

  /// Ab dieser Konzentration (g je 100 ml) leert sich der Magen langsamer.
  static const highConcentration = 10.0;

  double get carbs => maltodextrin * 0.95 + dextrose * 0.91 + fructose + sucrose;
  double get fructoseGrams => fructose + sucrose / 2;
  double get sodium => salt * sodiumPerGramSalt;
  double get powderGrams => maltodextrin + dextrose + fructose + sucrose + salt;

  /// Kohlenhydrate je 100 ml.
  double get concentration => waterMilliliters > 0 ? carbs / waterMilliliters * 100 : 0;

  Map<String, Object?> toJson() => {
    'maltodextrin': maltodextrin,
    'dextrose': dextrose,
    'fructose': fructose,
    'sucrose': sucrose,
    'salt': salt,
    'water': waterMilliliters,
    'caffeine': caffeineMilligrams,
  };

  static FuelMix? fromJson(Object? json) {
    if (json is! Map) return null;
    double read(String key) => (jsonDouble(json[key]) ?? 0).clamp(0, 5000).toDouble();
    final water = read('water');
    if (water <= 0) return null;
    return FuelMix(
      maltodextrin: read('maltodextrin'),
      dextrose: read('dextrose'),
      fructose: read('fructose'),
      sucrose: read('sucrose'),
      salt: read('salt'),
      waterMilliliters: water,
      caffeineMilligrams: read('caffeine'),
    );
  }
}

/// Ein Produkt mit Werten je Portion.
final class FuelProduct {
  const FuelProduct({
    required this.id,
    required this.name,
    required this.kind,
    required this.carbs,
    this.servingLabel,
    this.servingGrams = 0,
    this.volumeMilliliters = 0,
    this.fructose,
    this.sodium = 0,
    this.caffeine = 0,
    this.protein = 0,
    this.fat = 0,
    this.mix,
    this.builtIn = false,
  });

  /// Eigene Mischung: Werte aus den Zutaten.
  factory FuelProduct.fromMix({required String id, required String name, required FuelMix mix}) => FuelProduct(
    id: id,
    name: name,
    kind: FuelProductKind.drinkMix,
    carbs: _tenth(mix.carbs),
    servingGrams: mix.waterMilliliters,
    volumeMilliliters: mix.waterMilliliters,
    fructose: _tenth(mix.fructoseGrams),
    sodium: mix.sodium.roundToDouble(),
    caffeine: mix.caffeineMilligrams,
    mix: mix,
  );

  final String id;
  final String name;
  final FuelProductKind kind;

  /// Bezeichnung einer Portion; ohne: die der Art („Gel“, „Flasche“).
  final String? servingLabel;

  /// Gewicht einer Portion in g (bei Getränken ml).
  final double servingGrams;

  /// Inhalt einer Flasche bzw. Portion bei Getränken (ml), sonst 0.
  final double volumeMilliliters;
  final double carbs;

  /// Davon Fruktose (g); `null` = unbekannt.
  final double? fructose;
  final double sodium;
  final double caffeine;
  final double protein;
  final double fat;
  final FuelMix? mix;

  /// Mitgeliefert (nicht änderbar).
  final bool builtIn;

  String get serving => (servingLabel?.trim().isNotEmpty ?? false) ? servingLabel!.trim() : kind.servingLabel;

  double get kilocalories => 4 * carbs + 4 * protein + 9 * fat;

  /// Fruktose-Anteil an den Kohlenhydraten (0–1); `null` ohne Angabe.
  double? get fructoseShare => fructose == null || carbs <= 0 ? null : (fructose! / carbs).clamp(0, 1).toDouble();

  bool get isDrink => kind.isDrink && volumeMilliliters > 0;

  double get carbsPerMilliliter => isDrink ? carbs / volumeMilliliters : 0;
  double get sodiumPerMilliliter => isDrink ? sodium / volumeMilliliters : 0;

  /// Kohlenhydrate je 100 ml (Getränke).
  double get concentration => isDrink ? carbs / volumeMilliliters * 100 : 0;

  FuelProduct copyWith({
    String? id,
    String? name,
    FuelProductKind? kind,
    double? carbs,
    String? servingLabel,
    double? servingGrams,
    double? volumeMilliliters,
    double? Function()? fructose,
    double? sodium,
    double? caffeine,
    double? protein,
    double? fat,
  }) => FuelProduct(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    carbs: carbs ?? this.carbs,
    servingLabel: servingLabel ?? this.servingLabel,
    servingGrams: servingGrams ?? this.servingGrams,
    volumeMilliliters: volumeMilliliters ?? this.volumeMilliliters,
    fructose: fructose == null ? this.fructose : fructose(),
    sodium: sodium ?? this.sodium,
    caffeine: caffeine ?? this.caffeine,
    protein: protein ?? this.protein,
    fat: fat ?? this.fat,
    mix: mix,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.rawValue,
    'carbs': carbs,
    'serving': ?servingLabel,
    'grams': servingGrams,
    'volume': volumeMilliliters,
    'fructose': ?fructose,
    'sodium': sodium,
    'caffeine': caffeine,
    'protein': protein,
    'fat': fat,
    'mix': ?mix?.toJson(),
  };

  static FuelProduct? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final kind = enumFromRaw(FuelProductKind.values, json['kind']);
    if (id is! String || id.startsWith(FuelProducts.builtInPrefix) || name is! String || name.trim().isEmpty) {
      return null;
    }
    if (kind == null) return null;
    final mix = FuelMix.fromJson(json['mix']);
    if (kind == FuelProductKind.drinkMix && mix != null) return FuelProduct.fromMix(id: id, name: name, mix: mix);
    double read(String key) => (jsonDouble(json[key]) ?? 0).clamp(0, 5000).toDouble();
    final serving = json['serving'];
    final fructose = jsonDouble(json['fructose']);
    final carbs = read('carbs');
    return FuelProduct(
      id: id,
      name: name.trim(),
      kind: kind,
      carbs: carbs,
      servingLabel: serving is String && serving.trim().isNotEmpty ? serving.trim() : null,
      servingGrams: read('grams'),
      volumeMilliliters: kind.isDrink ? read('volume') : 0,
      fructose: fructose?.clamp(0, carbs).toDouble(),
      sodium: read('sodium'),
      caffeine: read('caffeine'),
      protein: read('protein'),
      fat: read('fat'),
    );
  }
}

double _tenth(double value) => (value * 10).roundToDouble() / 10;

/// Mitgelieferte, markenneutrale Produkte mit typischen Werten (wie auf gängigen Etiketten).
abstract final class FuelProducts {
  static const builtInPrefix = 'builtin.';

  static const classicGel = FuelProduct(
    id: '${builtInPrefix}gel',
    name: 'Gel klassisch (2:1)',
    kind: FuelProductKind.gel,
    carbs: 25,
    servingGrams: 40,
    fructose: 8,
    sodium: 50,
    builtIn: true,
  );

  static const highCarbGel = FuelProduct(
    id: '${builtInPrefix}gel40',
    name: 'Gel hochdosiert (1:0,8)',
    kind: FuelProductKind.gel,
    carbs: 40,
    servingGrams: 60,
    fructose: 18,
    sodium: 100,
    builtIn: true,
  );

  static const caffeineGel = FuelProduct(
    id: '${builtInPrefix}gelcaffeine',
    name: 'Koffein-Gel',
    kind: FuelProductKind.gel,
    carbs: 25,
    servingGrams: 40,
    fructose: 8,
    sodium: 50,
    caffeine: 75,
    builtIn: true,
  );

  static const isoDrink = FuelProduct(
    id: '${builtInPrefix}iso',
    name: 'Iso-Drink 6 %',
    kind: FuelProductKind.drink,
    carbs: 30,
    servingGrams: 500,
    volumeMilliliters: 500,
    fructose: 10,
    sodium: 250,
    builtIn: true,
  );

  static const highCarbDrink = FuelProduct(
    id: '${builtInPrefix}drink80',
    name: 'Kohlenhydrat-Drink hochdosiert (1:0,8)',
    kind: FuelProductKind.drink,
    carbs: 80,
    servingGrams: 500,
    volumeMilliliters: 500,
    fructose: 36,
    sodium: 500,
    builtIn: true,
  );

  static const bar = FuelProduct(
    id: '${builtInPrefix}bar',
    name: 'Energieriegel',
    kind: FuelProductKind.bar,
    carbs: 40,
    servingGrams: 55,
    fructose: 10,
    sodium: 100,
    protein: 3,
    fat: 3,
    builtIn: true,
  );

  static const chews = FuelProduct(
    id: '${builtInPrefix}chews',
    name: 'Kaudragees (½ Beutel)',
    kind: FuelProductKind.chew,
    carbs: 24,
    servingGrams: 30,
    fructose: 8,
    sodium: 50,
    builtIn: true,
  );

  static const banana = FuelProduct(
    id: '${builtInPrefix}banana',
    name: 'Banane',
    kind: FuelProductKind.food,
    carbs: 25,
    servingGrams: 120,
    fructose: 6,
    sodium: 1,
    protein: 1,
    fat: 0.3,
    builtIn: true,
  );

  static const saltTablet = FuelProduct(
    id: '${builtInPrefix}salt',
    name: 'Salztablette',
    kind: FuelProductKind.electrolyte,
    carbs: 0,
    servingGrams: 1,
    sodium: 250,
    builtIn: true,
  );

  static const all = [classicGel, highCarbGel, caffeineGel, isoDrink, highCarbDrink, bar, chews, banana, saltTablet];

  static FuelProduct? byId(String id) => all.firstWhereOrNull((product) => product.id == id);

  /// Neue ID für eigene Produkte.
  static String newId() => newUuid();
}

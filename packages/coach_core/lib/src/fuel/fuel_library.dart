// Fuel Planner: alles eines Benutzers unter `coach.fuelPlanner` – Profil, eigene Produkte und Mischungen,
// gespeicherte Pläne. Gehört genau einem `username`; ein fremder Stand wird weder geladen noch überschrieben
// (wie die Favoriten des Routenplaners). Spezifikation 8.
import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../util/swift_date.dart';
import 'fuel_product.dart';
import 'fuel_scenario.dart';
import 'fuel_stock.dart';

/// Ein gespeicherter Plan: Szenario und gewählte Produkte; der Plan selbst wird jedes Mal neu gerechnet.
final class SavedFuelPlan {
  const SavedFuelPlan({
    required this.id,
    required this.scenario,
    required this.productIDs,
    required this.savedAt,
    this.loggedAt,
    this.loggedMealIDs = const [],
    this.everyday = false,
    this.mealChoices = const {},
    this.consumedStock = const {},
  });

  final String id;
  final FuelScenario scenario;
  final List<String> productIDs;
  final DateTime savedAt;

  /// Zuletzt ins Ernährungstagebuch übernommen.
  final DateTime? loggedAt;

  /// Die dabei angelegten Mahlzeiten (erneut übernehmen ersetzt sie, „Rückgängig“ entfernt sie).
  final List<String> loggedMealIDs;

  /// Unterwegs mit Alltagslebensmitteln statt Sportnahrung.
  final bool everyday;

  /// Gewählter Vorschlag je Zeitpunkt (Schlüssel `phase:minute` → Vorlage).
  final Map<String, String> mealChoices;

  /// Beim Übernehmen aus dem Vorrat genommen (wird bei erneutem Übernehmen bzw. „Rückgängig“ zurückgebucht).
  final Map<String, double> consumedStock;

  /// Nicht mehr im Tagebuch.
  SavedFuelPlan unlogged() => SavedFuelPlan(
    id: id,
    scenario: scenario,
    productIDs: productIDs,
    savedAt: savedAt,
    everyday: everyday,
    mealChoices: mealChoices,
  );

  SavedFuelPlan copyWith({
    FuelScenario? scenario,
    List<String>? productIDs,
    DateTime? savedAt,
    DateTime? loggedAt,
    List<String>? loggedMealIDs,
    bool? everyday,
    Map<String, String>? mealChoices,
    Map<String, double>? consumedStock,
  }) => SavedFuelPlan(
    id: id,
    scenario: scenario ?? this.scenario,
    productIDs: productIDs ?? this.productIDs,
    savedAt: savedAt ?? this.savedAt,
    loggedAt: loggedAt ?? this.loggedAt,
    loggedMealIDs: loggedMealIDs ?? this.loggedMealIDs,
    everyday: everyday ?? this.everyday,
    mealChoices: mealChoices ?? this.mealChoices,
    consumedStock: consumedStock ?? this.consumedStock,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'scenario': scenario.toJson(),
    'products': productIDs,
    'savedAt': swiftDateToJson(savedAt),
    if (loggedAt case final logged?) 'loggedAt': swiftDateToJson(logged),
    if (loggedMealIDs.isNotEmpty) 'loggedMeals': loggedMealIDs,
    if (everyday) 'everyday': true,
    if (mealChoices.isNotEmpty) 'meals': mealChoices,
    if (consumedStock.isNotEmpty) 'consumed': consumedStock,
  };

  static SavedFuelPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final scenario = FuelScenario.fromJson(json['scenario']);
    final saved = swiftDateFromJson(json['savedAt']);
    final products = json['products'];
    if (id is! String || scenario == null || saved == null) return null;
    return SavedFuelPlan(
      id: id,
      scenario: scenario,
      productIDs: [
        if (products is List)
          for (final item in products)
            if (item is String) item,
      ],
      savedAt: saved,
      loggedAt: swiftDateFromJson(json['loggedAt']),
      loggedMealIDs: [
        if (json['loggedMeals'] case final List<Object?> ids)
          for (final item in ids)
            if (item is String) item,
      ],
      everyday: json['everyday'] == true,
      mealChoices: {
        if (json['meals'] case final Map<Object?, Object?> meals)
          for (final MapEntry(:key, :value) in meals.entries)
            if (key is String && value is String) key: value,
      },
      consumedStock: {
        if (json['consumed'] case final Map<Object?, Object?> consumed)
          for (final MapEntry(:key, :value) in consumed.entries)
            if (key is String && value is num && value > 0) key: value.toDouble(),
      },
    );
  }
}

final class FuelLibrary {
  FuelLibrary({
    required this.username,
    this.profile = const FuelProfile(),
    List<FuelProduct>? products,
    List<SavedFuelPlan>? plans,
    Map<String, FuelStock>? stock,
  }) : products = products ?? [],
       plans = plans ?? [],
       stock = stock ?? {};

  final String username;
  FuelProfile profile;

  /// Eigene Produkte und Mischungen.
  final List<FuelProduct> products;

  /// Neueste zuerst.
  final List<SavedFuelPlan> plans;

  /// Vorrat je Produkt-ID.
  final Map<String, FuelStock> stock;

  /// Vorrat setzen; Anzahl 0 entfernt ihn.
  void setStock(String productID, FuelStock? value) {
    if (value == null || value.count <= 0) {
      stock.remove(productID);
    } else {
      stock[productID] = value;
    }
  }

  /// Verbrauch abbuchen; negative Werte buchen zurück.
  void consume(Map<String, double> used) {
    for (final MapEntry(:key, :value) in used.entries) {
      final current = stock[key];
      if (current == null && value > 0) continue;
      final count = (current?.count ?? 0) - value;
      // Leer bleibt der Eintrag (mit Mindesthaltbarkeit) stehen, damit „Rückgängig“ sie nicht verliert.
      stock[key] = FuelStock(count: count < 0 ? 0 : count, bestBefore: current?.bestBefore);
    }
  }

  /// Nutzbarer Vorrat am [day] (nicht abgelaufen, Produkt bekannt).
  Map<String, double> usableStock(CalendarDay day) => {
    for (final MapEntry(:key, :value) in stock.entries)
      if (value.count > 0 && !value.expiredOn(day) && product(key) != null) key: value.count,
  };

  /// Mindesthaltbarkeit des nutzbaren Vorrats.
  Map<String, CalendarDay> bestBefore(CalendarDay day) => {
    for (final MapEntry(:key, :value) in stock.entries)
      if (value.bestBefore case final date? when !value.expiredOn(day)) key: date,
  };

  /// Abgelaufene Produkte im Vorrat.
  List<FuelProduct> expired(CalendarDay day) => [
    for (final MapEntry(:key, :value) in stock.entries)
      if (value.count > 0 && value.expiredOn(day)) ?product(key),
  ];

  static const maxProducts = 100;
  static const maxPlans = 60;

  /// Eigene vor den mitgelieferten.
  List<FuelProduct> get allProducts => [...products, ...FuelProducts.all];

  FuelProduct? product(String id) => products.firstWhereOrNull((p) => p.id == id) ?? FuelProducts.byId(id);

  /// Produkte zu IDs in deren Reihenfolge; unbekannte fallen weg.
  List<FuelProduct> resolve(Iterable<String> ids) => [for (final id in ids) ?product(id)];

  void saveProduct(FuelProduct product) {
    if (product.builtIn || product.id.startsWith(FuelProducts.builtInPrefix)) return;
    final index = products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      products[index] = product;
    } else {
      products.insert(0, product);
      if (products.length > maxProducts) products.removeRange(maxProducts, products.length);
    }
  }

  void deleteProduct(String id) {
    products.removeWhere((p) => p.id == id);
    stock.remove(id);
    profile = profile.copyWith(
      setup: [
        for (final item in profile.setup)
          if (item != id) item,
      ],
    );
  }

  /// Neu bzw. ersetzt, vorn einsortiert.
  void savePlan(SavedFuelPlan plan) {
    plans
      ..removeWhere((p) => p.id == plan.id)
      ..insert(0, plan);
    if (plans.length > maxPlans) plans.removeRange(maxPlans, plans.length);
  }

  void deletePlan(String id) => plans.removeWhere((p) => p.id == id);

  /// Gespeicherter Plan zu einer Einheit des Ausdauerplans.
  SavedFuelPlan? planForSlot(String slotID) => plans.firstWhereOrNull((p) => p.scenario.slotID == slotID);

  Map<String, Object?> toJson() => {
    'username': username,
    'profile': profile.toJson(),
    'products': [for (final product in products) product.toJson()],
    'plans': [for (final plan in plans) plan.toJson()],
    if (stock.isNotEmpty) 'stock': {for (final MapEntry(:key, :value) in stock.entries) key: value.toJson()},
  };

  /// Gehört der Stand einem anderen Benutzer, `null`.
  static FuelLibrary? fromJson(Object? json, {required String username}) {
    if (json is! Map || json['username'] != username) return null;
    final products = json['products'];
    final plans = json['plans'];
    return FuelLibrary(
      username: username,
      profile: FuelProfile.fromJson(json['profile']),
      products: [
        if (products is List)
          for (final item in products) ?FuelProduct.fromJson(item),
      ],
      plans: [
        if (plans is List)
          for (final item in plans) ?SavedFuelPlan.fromJson(item),
      ],
      stock: {
        if (json['stock'] case final Map<Object?, Object?> stock)
          for (final MapEntry(:key, :value) in stock.entries)
            if (key is String)
              if (FuelStock.fromJson(value) case final entry? when entry.count > 0) key: entry,
      },
    );
  }
}

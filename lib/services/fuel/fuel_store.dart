import 'dart:async';
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/settings/settings_store.dart';
import '../../data/storage.dart';
import '../../data/users/current_user.dart';
import '../providers.dart';

/// Fuel Planner des aktiven Benutzers unter `coach.fuelPlanner` (Profil, eigene Produkte, gespeicherte Pläne). Der
/// Stand trägt den `username`: Ein Stand eines anderen Benutzers (z. B. aus einer eingespielten Sicherung) wird weder
/// geladen noch überschrieben – so vermischt sich nichts zwischen Benutzern.
final class FuelStore extends ChangeNotifier {
  FuelStore(this._store, {required this.username, DateTime Function()? now}) : _now = now ?? DateTime.now {
    _load();
    _subscription = _store.changes.where((key) => key == SettingsKeys.fuelPlanner).listen((_) {
      // Eingespielte Sicherung bzw. Änderung von außen; eigene Schreibvorgänge ändern nichts.
      final stored = jsonEncode(_store.json(SettingsKeys.fuelPlanner));
      if (stored == jsonEncode(_library.toJson())) return;
      _load();
      notifyListeners();
    });
  }

  final SettingsStore _store;
  final DateTime Function() _now;
  final String username;
  late FuelLibrary _library;
  StreamSubscription<String>? _subscription;

  void _load() {
    _library =
        FuelLibrary.fromJson(_store.json(SettingsKeys.fuelPlanner), username: username) ??
        FuelLibrary(username: username);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  /// Liegt unter dem Schlüssel ein Stand eines anderen Benutzers? Dann wird nichts gespeichert.
  bool get hasForeignData =>
      _store.contains(SettingsKeys.fuelPlanner) &&
      FuelLibrary.fromJson(_store.json(SettingsKeys.fuelPlanner), username: username) == null;

  FuelProfile get profile => _library.profile;
  List<FuelProduct> get ownProducts => List.unmodifiable(_library.products);
  List<FuelProduct> get allProducts => _library.allProducts;
  List<SavedFuelPlan> get plans => List.unmodifiable(_library.plans);

  FuelProduct? product(String id) => _library.product(id);
  List<FuelProduct> resolve(Iterable<String> ids) => _library.resolve(ids);
  SavedFuelPlan? planForSlot(String slotID) => _library.planForSlot(slotID);
  SavedFuelPlan? plan(String id) => _library.plans.where((plan) => plan.id == id).firstOrNull;

  Future<void> _persist() async {
    if (hasForeignData) throw StateError('Der Verpflegungsplan gehört einem anderen Benutzer.');
    notifyListeners();
    await _store.setJson(SettingsKeys.fuelPlanner, _library.toJson());
  }

  Future<void> saveProfile(FuelProfile profile) {
    _library.profile = profile;
    return _persist();
  }

  Future<void> saveProduct(FuelProduct product) {
    _library.saveProduct(product);
    return _persist();
  }

  Future<void> deleteProduct(String id) {
    _library.deleteProduct(id);
    return _persist();
  }

  /// Speichert das Szenario mit den Produkten (neu oder unter [id]) und gibt die ID zurück.
  Future<String> savePlan(
    FuelScenario scenario,
    List<String> productIDs, {
    String? id,
    bool everyday = false,
    Map<String, String> mealChoices = const {},
  }) async {
    final existing = id == null ? null : plan(id);
    final saved = SavedFuelPlan(
      id: id ?? newUuid(),
      scenario: scenario,
      productIDs: productIDs,
      savedAt: _now(),
      loggedAt: existing?.loggedAt,
      loggedMealIDs: existing?.loggedMealIDs ?? const [],
      everyday: everyday,
      mealChoices: mealChoices,
      consumedStock: existing?.consumedStock ?? const {},
    );
    _library.savePlan(saved);
    await _persist();
    return saved.id;
  }

  Future<void> deletePlan(String id) {
    _library.deletePlan(id);
    return _persist();
  }

  /// Ins Tagebuch übernommen, mit den angelegten Mahlzeiten und dem aus dem Vorrat Genommenen. Was beim letzten
  /// Übernehmen abgebucht wurde, wird vorher zurückgebucht (sonst zählte es doppelt).
  Future<void> markLogged(String id, List<String> mealIDs, {Map<String, double> consumed = const {}}) async {
    final existing = plan(id);
    if (existing == null) return;
    _library
      ..consume({for (final MapEntry(:key, :value) in existing.consumedStock.entries) key: -value})
      ..consume(consumed)
      ..savePlan(existing.copyWith(loggedAt: _now(), loggedMealIDs: mealIDs, consumedStock: consumed));
    await _persist();
  }

  /// „Rückgängig“: früheren Stand wiederherstellen (vorher nicht im Tagebuch bzw. mit den alten Einträgen); der Vorrat
  /// bekommt das zuletzt Abgebuchte zurück und verliert wieder, was der frühere Stand abgebucht hatte.
  Future<void> restoreLogged(SavedFuelPlan previous) async {
    final current = plan(previous.id);
    if (current == null) return;
    _library
      ..consume({for (final MapEntry(:key, :value) in current.consumedStock.entries) key: -value})
      ..consume(previous.consumedStock)
      ..savePlan(previous);
    await _persist();
  }

  // Vorrat

  Map<String, FuelStock> get stock => Map.unmodifiable(_library.stock);

  Map<String, double> usableStock(CalendarDay day) => _library.usableStock(day);
  Map<String, CalendarDay> bestBefore(CalendarDay day) => _library.bestBefore(day);
  List<FuelProduct> expired(CalendarDay day) => _library.expired(day);

  Future<void> setStock(String productID, FuelStock? value) {
    _library.setStock(productID, value);
    return _persist();
  }

  /// Produkte für einen Plan: die gewählten und – mit „Vorrat zuerst“ – alles Vorrätige, das unterwegs passt.
  List<FuelProduct> setupWithStock(List<String> ids, CalendarDay day) {
    final chosen = resolve(ids);
    if (!profile.useStockFirst) return chosen;
    final known = {for (final product in chosen) product.id};
    return [
      ...chosen,
      for (final id in usableStock(day).keys)
        if (!known.contains(id))
          if (product(id) case final product?
              when product.isDrink || product.kind.isSolid || product.kind == FuelProductKind.electrolyte)
            product,
    ];
  }

  /// Wie viele gespeicherte Pläne ein Produkt nutzen (Hinweis beim Löschen).
  int plansUsing(String productID) => _library.plans.where((plan) => plan.productIDs.contains(productID)).length;
}

final fuelStoreProvider = ChangeNotifierProvider<FuelStore>(
  (ref) => FuelStore(ref.watch(settingsStoreProvider), username: ref.watch(currentUserProvider).username),
);

/// Körpergewicht und Alter für den Plan: Ernährungseinstellungen › Uhr › Standardwerte.
final fuelBodyProvider = Provider<({double weight, int age})>((ref) {
  final settings = ref.watch(coachSettingsProvider);
  final garmin = ref.watch(appModelProvider).sync.profile;
  final body = settings.nutrition.profile(garmin, on: CalendarDay.today());
  return (weight: body.weightKilograms, age: body.age);
});

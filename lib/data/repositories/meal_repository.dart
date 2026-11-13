import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'json_bytes.dart';

/// Eine gespeicherte Mahlzeit (wie `MealRecord`).
final class StoredMeal {
  StoredMeal({
    String? id,
    required this.day,
    required this.createdAt,
    required this.category,
    required this.title,
    this.hint = '',
    required this.items,
  }) : id = id ?? newUuid();

  final String id;
  CalendarDay day;
  DateTime createdAt;
  MealCategory category;
  String title;
  String hint;
  List<MealItem> items;

  /// Nur Wasser (Glas-Knopf) – erscheint nicht in der Mahlzeitenliste.
  bool get isWater => items.isNotEmpty && items.every((item) => item.isDrink && item.name == 'Wasser');

  MealEntry get entry => MealEntry(day: day, date: createdAt, category: category, title: title, items: items);
}

/// Eigenes bzw. zuletzt genutztes Lebensmittel (wie `FoodRecord`, auch Open-Food-Facts-Zwischenspeicher je Barcode).
final class StoredFood {
  const StoredFood({
    required this.key,
    required this.name,
    required this.item,
    required this.lastUsed,
    required this.useCount,
  });

  final String key;
  final String name;

  /// `null`, wenn die gespeicherten Daten nicht lesbar sind.
  final MealItem? item;
  final DateTime lastUsed;
  final int useCount;

  /// Kandidat für `FoodSearch.rank` (ID wie in Swift: `food:<Schlüssel>`).
  FoodSearchCandidate get candidate =>
      FoodSearchCandidate(id: 'food:$key', title: name, useCount: useCount, lastUsed: lastUsed);
}

/// Mahlzeiten und eigene Lebensmittel.
final class MealRepository {
  MealRepository(this._db);

  final CoachDatabase _db;

  static StoredMeal? _meal(MealRow row) {
    final day = CalendarDay.tryParse(row.dayKey);
    if (day == null) return null;
    return StoredMeal(
      id: row.id,
      day: day,
      createdAt: row.createdAt,
      category: MealCategory.fromRaw(row.categoryRaw) ?? MealCategory.other,
      title: row.title,
      hint: row.hint,
      items: decodeJson(row.itemsPayload, (json) => listStrict(json, MealItem.fromJson)) ?? [],
    );
  }

  Future<List<StoredMeal>> all() async => [
    for (final row in await (_db.select(
      _db.mealRecords,
    )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get())
      ?_meal(row),
  ];

  Future<List<StoredMeal>> range({required CalendarDay from, required CalendarDay to}) async {
    final query = _db.select(_db.mealRecords)
      ..where((t) => t.dayKey.isBetweenValues(from.iso, to.iso))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return [for (final row in await query.get()) ?_meal(row)];
  }

  Future<List<StoredMeal>> day(CalendarDay day) => range(from: day, to: day);

  /// Mahlzeiten ohne Wasser als `MealEntry` (für Vorschläge, Suche, Woche).
  static List<MealEntry> entries(Iterable<StoredMeal> meals) => [
    for (final meal in meals)
      if (!meal.isWater) meal.entry,
  ];

  Future<void> save(StoredMeal meal) => _db
      .into(_db.mealRecords)
      .insertOnConflictUpdate(
        MealRecordsCompanion.insert(
          id: meal.id,
          dayKey: meal.day.iso,
          createdAt: meal.createdAt,
          categoryRaw: meal.category.rawValue,
          title: meal.title,
          hint: meal.hint,
          itemsPayload: encodeJson([for (final item in meal.items) item.toJson()]),
        ),
      );

  Future<void> delete(String id) => (_db.delete(_db.mealRecords)..where((t) => t.id.equals(id))).go();

  // Eigene Lebensmittel

  /// Schlüssel wie in Swift: Barcode, sonst der Name in Kleinbuchstaben.
  static String foodKey(MealItem item) =>
      item.barcode == null ? 'name:${item.name.toLowerCase()}' : 'barcode:${item.barcode}';

  /// Lebensmittel für Vorschläge, Suche und KI-Hinweise merken (wie `remember` im Swift-ViewModel): neue anlegen,
  /// bei bekannten Menge und Portion übernehmen („du nimmst meist 40 g“); eigene Nährwerte bleiben, nur von der KI
  /// geschätzte werden durch bessere ersetzt. Nutzung zählen.
  Future<void> rememberFoods(Iterable<MealItem> items, {DateTime? at}) => _db.transaction(() async {
    final now = at ?? DateTime.now();
    for (final item in items) {
      final key = foodKey(item);
      final existing = await (_db.select(_db.foodRecords)..where((t) => t.key.equals(key))).getSingleOrNull();
      var payload = encodeJson(item.toJson());
      if (existing != null) {
        payload = existing.payload;
        final stored = decodeJson(existing.payload, MealItem.fromJson);
        if (stored != null) {
          stored
            ..grams = item.grams
            ..portion = item.portion ?? stored.portion;
          if (stored.source == MealItemSource.ai && item.source != MealItemSource.ai) stored.per100g = item.per100g;
          payload = encodeJson(stored.toJson());
        }
      }
      await _db
          .into(_db.foodRecords)
          .insertOnConflictUpdate(
            FoodRecordsCompanion.insert(
              key: key,
              name: existing?.name ?? item.name,
              payload: payload,
              lastUsed: now,
              useCount: (existing?.useCount ?? 0) + 1,
            ),
          );
    }
  });

  /// Speichert ein Lebensmittel (z. B. Open-Food-Facts-Zwischenspeicher je Barcode), ohne die Nutzung zu zählen.
  Future<void> storeFood(MealItem item, {DateTime? at}) async {
    final key = foodKey(item);
    final existing = await (_db.select(_db.foodRecords)..where((t) => t.key.equals(key))).getSingleOrNull();
    await _db
        .into(_db.foodRecords)
        .insertOnConflictUpdate(
          FoodRecordsCompanion.insert(
            key: key,
            name: item.name,
            payload: encodeJson(item.toJson()),
            lastUsed: existing?.lastUsed ?? at ?? DateTime.now(),
            useCount: existing?.useCount ?? 0,
          ),
        );
  }

  Future<MealItem?> food(String key) async {
    final row = await (_db.select(_db.foodRecords)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row == null ? null : decodeJson(row.payload, MealItem.fromJson);
  }

  /// Eigene Lebensmittel, häufig genutzte zuerst (wie `@Query(sort: \FoodRecord.useCount, order: .reverse)`).
  Future<List<StoredFood>> foods() async {
    final query = _db.select(_db.foodRecords)
      ..orderBy([(t) => OrderingTerm(expression: t.useCount, mode: OrderingMode.desc)]);
    return [
      for (final row in await query.get())
        StoredFood(
          key: row.key,
          name: row.name,
          item: decodeJson(row.payload, MealItem.fromJson),
          lastUsed: row.lastUsed,
          useCount: row.useCount,
        ),
    ];
  }

  /// Namen der am häufigsten genutzten Lebensmittel (Hinweis an die KI-Analyse).
  Future<List<String>> frequentFoodNames({int limit = 15}) async {
    final query = _db.select(_db.foodRecords)
      ..orderBy([(t) => OrderingTerm(expression: t.useCount, mode: OrderingMode.desc)])
      ..limit(limit);
    return [for (final row in await query.get()) row.name];
  }

  Future<void> deleteFood(String key) => (_db.delete(_db.foodRecords)..where((t) => t.key.equals(key))).go();
}

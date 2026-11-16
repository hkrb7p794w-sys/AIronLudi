import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../repositories/json_bytes.dart';
import '../repositories/meal_repository.dart';
import '../settings/coach_settings.dart';
import '../settings/settings_store.dart';

/// Ergebnis des Einspielens.
final class RestoreResult {
  const RestoreResult({this.gym = 0, this.meals = 0, this.foods = 0, this.settings = 0, this.extras});

  final int gym;
  final int meals;
  final int foods;
  final int settings;

  /// Nur Android-Sicherung: Pläne, eigene Übungen, Favoriten, Rezepte und Gewichte (statt Einstellungen).
  final int? extras;

  String get text => switch (extras) {
    final extras? =>
      '$gym Krafteinheiten, $meals Mahlzeiten, $foods Lebensmittel und $extras Pläne, Übungen, Favoriten, Rezepte und '
          'Gewichte ergänzt.',
    null =>
      '$gym Krafteinheiten, $meals Mahlzeiten und $foods Lebensmittel ergänzt, $settings Einstellungen übernommen.',
  };
}

/// Datensicherung: erstellt eine `AppBackup`-Datei aus Einstellungen und Datenbank und spielt sie zusammenführend ein
/// (wie `BackupService` der Swift-App, gleiches Dateiformat). Automatisch sichert die App höchstens einmal je
/// `AppBackup.autoInterval` in einen selbst gewählten Ordner.
final class BackupService {
  BackupService(this._db, this._settings, {this.owner});

  final CoachDatabase _db;
  final SettingsStore _settings;

  /// Benutzername für den Dateinamen der Ordner-Sicherung; `null` für den ursprünglichen Benutzer (Dateiname wie in
  /// der Swift-App). So überschreiben sich zwei Benutzer im selben Ordner nicht gegenseitig.
  final String? owner;

  // Erstellen

  Future<AppBackup> make({DateTime? now}) async {
    final gym = await _db.select(_db.gymSessionRecords).get();
    final meals = await _db.select(_db.mealRecords).get();
    final foods = await _db.select(_db.foodRecords).get();
    return AppBackup(
      createdAt: now ?? DateTime.now(),
      settings: _settings.backedUp,
      gym: [
        for (final row in gym)
          BackupGym(
            id: row.id,
            payload: row.payload,
            savedToHealth: row.savedToHealth,
            uploadedToGarmin: row.uploadedToGarmin,
          ),
      ],
      meals: [
        for (final row in meals)
          BackupMeal(
            id: row.id,
            dayKey: row.dayKey,
            createdAt: row.createdAt,
            category: row.categoryRaw,
            title: row.title,
            hint: row.hint,
            items: row.itemsPayload,
          ),
      ],
      foods: [
        for (final row in foods)
          BackupFood(
            key: row.key,
            name: row.name,
            payload: row.payload,
            lastUsed: row.lastUsed,
            useCount: row.useCount,
          ),
      ],
    );
  }

  /// Dateiname zum Teilen, z. B. `IronLudi-Sicherung-2026-11-13.json`.
  static String shareFileName(DateTime createdAt) {
    final local = createdAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'IronLudi-Sicherung-${local.year}-${two(local.month)}-${two(local.day)}.json';
  }

  /// `IronLudi-Sicherung.json` bzw. je weiterem Benutzer `IronLudi-Sicherung-<benutzername>.json`.
  static String folderFileName(String? owner, {bool previous = false}) {
    if (owner == null) return previous ? AppBackup.previousFileName : AppBackup.fileName;
    return 'IronLudi-Sicherung-$owner${previous ? '-vorher' : ''}.json';
  }

  /// Schreibt in den Ordner; die bisherige Sicherung bleibt als „…-vorher.json“ erhalten.
  static Future<File> write(AppBackup backup, {required Directory folder, String? owner}) async {
    final file = File(p.join(folder.path, folderFileName(owner)));
    final previous = File(p.join(folder.path, folderFileName(owner, previous: true)));
    if (file.existsSync()) {
      if (previous.existsSync()) await previous.delete();
      await file.rename(previous.path);
    }
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(backup.encoded(), flush: true);
    return temporary.rename(file.path);
  }

  // Einspielen

  /// Führt zusammen: Krafteinheiten und Mahlzeiten über ihre ID, Lebensmittel über ihren Schlüssel – Vorhandenes
  /// bleibt unverändert. Einstellungen werden ersetzt. Einträge, deren Inhalt nicht lesbar ist, fallen weg (wie in
  /// Swift).
  Future<RestoreResult> restore(AppBackup backup) async {
    var (gymCount, mealCount, foodCount) = (0, 0, 0);
    await _db.transaction(() async {
      final gymIDs = {for (final row in await _db.select(_db.gymSessionRecords).get()) row.id};
      for (final entry in AppBackup.missing(backup.gym, key: (BackupGym item) => item.id, existing: gymIDs)) {
        final session = _decode(entry.payload, GymSession.fromJson);
        if (session == null) continue;
        await _db
            .into(_db.gymSessionRecords)
            .insert(
              GymSessionRecordsCompanion.insert(
                id: entry.id,
                dayKey: session.day.iso,
                start: session.start,
                payload: entry.payload,
                savedToHealth: Value(entry.savedToHealth),
                uploadedToGarmin: Value(entry.uploadedToGarmin),
              ),
            );
        gymCount += 1;
      }

      final mealIDs = {for (final row in await _db.select(_db.mealRecords).get()) row.id};
      for (final entry in AppBackup.missing(backup.meals, key: (BackupMeal item) => item.id, existing: mealIDs)) {
        final day = CalendarDay.tryParse(entry.dayKey);
        final items = _decode(entry.items, (json) => listStrict(json, MealItem.fromJson));
        if (day == null || items == null) continue;
        await _db
            .into(_db.mealRecords)
            .insert(
              MealRecordsCompanion.insert(
                id: entry.id,
                dayKey: entry.dayKey,
                createdAt: entry.createdAt,
                categoryRaw: (MealCategory.fromRaw(entry.category) ?? MealCategory.other).rawValue,
                title: entry.title,
                hint: entry.hint,
                itemsPayload: entry.items,
              ),
            );
        mealCount += 1;
      }

      final foodKeys = {for (final row in await _db.select(_db.foodRecords).get()) row.key};
      for (final entry in AppBackup.missing(backup.foods, key: (BackupFood item) => item.key, existing: foodKeys)) {
        if (_decode(entry.payload, MealItem.fromJson) == null) continue;
        await _db
            .into(_db.foodRecords)
            .insert(
              FoodRecordsCompanion.insert(
                key: entry.key,
                name: entry.name,
                payload: entry.payload,
                lastUsed: entry.lastUsed,
                useCount: entry.useCount,
              ),
            );
        foodCount += 1;
      }
    });
    final settings = await _settings.restore(backup.settings);
    return RestoreResult(gym: gymCount, meals: mealCount, foods: foodCount, settings: settings);
  }

  /// Sicherung der bisherigen Android-App einspielen (`KotlinBackup`). Wie [restore] zusammenführend: Vorhandenes
  /// bleibt, Trainings und Mahlzeiten über ihre Kennung, Lebensmittel über ihren Schlüssel, Pläne, eigene Übungen,
  /// Favoriten und Rezepte über ihre Kennung, Gewichte je Tag. Einstellungen nur, wo hier noch nichts eingerichtet
  /// ist (Körperwerte ohne Gewicht, Rezept-Wünsche im Standard, keine Mahlzeiten-Erinnerung an). Ziel und Tempo
  /// kommen aus der Einrichtung, damit die Schutzgrenzen gelten.
  Future<RestoreResult> restoreKotlin(KotlinBackup backup, CoachSettings settings) async {
    var (gymCount, mealCount, foodCount, other) = (0, 0, 0, 0);
    await _db.transaction(() async {
      final gymIDs = {for (final row in await _db.select(_db.gymSessionRecords).get()) row.id};
      for (final session in backup.sessions) {
        if (!gymIDs.add(session.id)) continue;
        await _db
            .into(_db.gymSessionRecords)
            .insert(
              GymSessionRecordsCompanion.insert(
                id: session.id,
                dayKey: session.day.iso,
                start: session.start,
                payload: encodeJson(session.toJson()),
              ),
            );
        gymCount += 1;
      }
      final mealIDs = {for (final row in await _db.select(_db.mealRecords).get()) row.id};
      for (final meal in backup.meals) {
        if (!mealIDs.add(meal.id)) continue;
        await _db
            .into(_db.mealRecords)
            .insert(
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
        mealCount += 1;
      }
      final foodKeys = {for (final row in await _db.select(_db.foodRecords).get()) row.key};
      final now = DateTime.now();
      for (final item in backup.foods) {
        final key = MealRepository.foodKey(item);
        if (!foodKeys.add(key)) continue;
        await _db
            .into(_db.foodRecords)
            .insert(
              FoodRecordsCompanion.insert(
                key: key,
                name: item.name,
                payload: encodeJson(item.toJson()),
                lastUsed: now,
                useCount: 1,
              ),
            );
        foodCount += 1;
      }
    });

    // Gym: Pläne und eigene Übungen ergänzen, Pause und „Bildschirm anlassen“ wie in der alten App.
    final gym = settings.gym;
    for (final exercise in backup.customExercises) {
      if (gym.customExercises.any((other) => other.id == exercise.id)) continue;
      gym.customExercises.add(exercise);
      other += 1;
    }
    for (final routine in backup.routines) {
      if (gym.routines.any((existing) => existing.id == routine.id)) continue;
      gym.routines.add(routine);
      other += 1;
    }
    if (backup.restSeconds case final rest? when rest > 0) {
      gym
        ..restCompound = rest
        ..restIsolation = rest;
    }
    if (backup.keepScreenOn case final on?) gym.keepsScreenOn = on;
    settings.gym = gym;

    final favorites = [...settings.favoriteMeals];
    for (final favorite in backup.favorites) {
      if (favorites.any((existing) => existing.id == favorite.id)) continue;
      favorites.add(favorite);
      other += 1;
    }
    settings.favoriteMeals = favorites;
    final recipes = [...settings.ownRecipes];
    for (final recipe in backup.ownRecipes) {
      if (recipes.any((existing) => existing.id == recipe.id)) continue;
      recipes.add(recipe);
      other += 1;
    }
    settings.ownRecipes = recipes;
    final weights = [...settings.weights];
    for (final entry in backup.weights) {
      if (weights.any((existing) => existing.day == entry.day && existing.source == entry.source)) continue;
      weights.add(entry);
      other += 1;
    }
    weights.sort((a, b) => a.day.compareTo(b.day));
    settings.weights = weights;

    if (backup.body case final body? when settings.nutrition.weightKilograms == null) {
      final nutrition = settings.nutrition.copy()
        ..weightKilograms = body.weightKilograms
        ..heightCentimeters = body.heightCentimeters
        ..age = body.age
        ..isFemale = body.isFemale
        ..activityFactor = body.activityFactor
        ..bodyFatPercent = body.bodyFatPercent;
      if (body.diet case final diet?) nutrition.diet = diet;
      settings.nutrition = nutrition;
    }
    if (backup.recipePreferences case final preferences?
        when jsonEncode(settings.recipes.toJson()) == jsonEncode(RecipePreferences().toJson())) {
      settings.recipes = preferences;
    }
    if (backup.reminders case final meals? when !settings.reminders.meals.anyEnabled) {
      final reminders = settings.reminders.copy()..meals = meals;
      if (backup.reviewReminder case final review?) reminders.nutritionReview = review;
      settings.reminders = reminders;
    }
    return RestoreResult(gym: gymCount, meals: mealCount, foods: foodCount, extras: other);
  }

  static T? _decode<T>(List<int> bytes, T? Function(Object?) read) {
    try {
      return read(jsonDecode(utf8.decode(bytes)));
    } on Object {
      return null;
    }
  }

  // Automatisch

  /// Sichert in den gewählten Ordner, wenn fällig. [force]: auch wenn die letzte Sicherung noch frisch ist.
  Future<bool> backupToFolder({DateTime? now, bool force = false}) async {
    final path = _settings.string(SettingsKeys.backupFolder);
    if (path == null) return false;
    final current = now ?? DateTime.now();
    final last = _settings.doubleValue(SettingsKeys.backupLastAuto);
    final lastDate = last == null ? null : DateTime.fromMicrosecondsSinceEpoch((last * 1e6).round(), isUtc: true);
    if (!force && !AppBackup.isDue(last: lastDate, now: current)) return false;
    try {
      await write(
        await make(now: current),
        folder: Directory(path),
        owner: owner,
      );
      await _settings.setDouble(SettingsKeys.backupLastAuto, current.microsecondsSinceEpoch / 1e6);
      await _settings.remove(SettingsKeys.backupLastError);
      return true;
    } on Object catch (error) {
      await _settings.setString(SettingsKeys.backupLastError, '$error');
      return false;
    }
  }
}

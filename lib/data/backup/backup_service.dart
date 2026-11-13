import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../settings/settings_store.dart';

/// Ergebnis des Einspielens.
final class RestoreResult {
  const RestoreResult({this.gym = 0, this.meals = 0, this.foods = 0, this.settings = 0});

  final int gym;
  final int meals;
  final int foods;
  final int settings;

  String get text =>
      '$gym Krafteinheiten, $meals Mahlzeiten und $foods Lebensmittel ergänzt, $settings Einstellungen übernommen.';
}

/// Datensicherung: erstellt eine `AppBackup`-Datei aus Einstellungen und Datenbank und spielt sie zusammenführend ein
/// (wie `BackupService` der Swift-App, gleiches Dateiformat). Automatisch sichert die App höchstens einmal je
/// `AppBackup.autoInterval` in einen selbst gewählten Ordner.
final class BackupService {
  BackupService(this._db, this._settings);

  final CoachDatabase _db;
  final SettingsStore _settings;

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

  /// Schreibt in den Ordner; die bisherige Sicherung bleibt als „…-vorher.json“ erhalten.
  static Future<File> write(AppBackup backup, {required Directory folder}) async {
    final file = File(p.join(folder.path, AppBackup.fileName));
    final previous = File(p.join(folder.path, AppBackup.previousFileName));
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
      await write(await make(now: current), folder: Directory(path));
      await _settings.setDouble(SettingsKeys.backupLastAuto, current.microsecondsSinceEpoch / 1e6);
      await _settings.remove(SettingsKeys.backupLastError);
      return true;
    } on Object catch (error) {
      await _settings.setString(SettingsKeys.backupLastError, '$error');
      return false;
    }
  }
}

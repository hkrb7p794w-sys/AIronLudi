import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';

/// Schlüssel der Einstellungen, wie in der Swift-App (`CoachSettings` und die übrigen UserDefaults-Schlüssel). Die
/// Namen dürfen sich nicht ändern: Sicherungen und der Umzug von der Swift-App hängen daran.
abstract final class SettingsKeys {
  static const season = 'coach.season';
  static const privacy = 'coach.privacy';
  static const ai = 'coach.ai';
  static const aiUsage = 'coach.aiUsage';
  static const insights = 'coach.insights';
  static const customPrompts = 'coach.customPrompts';
  static const favoriteMeals = 'coach.favoriteMeals';
  static const nutritionDashboard = 'coach.nutritionDashboard';
  static const nutrition = 'coach.nutrition';
  static const heartRate = 'coach.heartRate';
  static const competition = 'coach.competitionDecisions';
  static const tests = 'coach.tests';
  static const profile = 'coach.profile';
  static const adjustments = 'coach.planAdjustments';
  static const reminders = 'coach.reminders';
  static const companion = 'coach.companion';
  static const league = 'coach.league';
  static const gym = 'coach.gym';
  static const recipes = 'coach.recipes';
  static const weights = 'coach.weights';
  static const sleep = 'coach.sleep';
  static const healthDashboard = 'coach.healthDashboard';
  static const mobility = 'coach.mobility';
  static const sentWorkouts = 'coach.sentWorkouts';
  static const sources = 'coach.sources';
  static const importedNotes = 'coach.importedNotes';
  static const userSources = 'coach.userSources';
  static const ownRecipes = 'coach.ownRecipes';
  static const pantry = 'coach.pantry';
  static const cookPartners = 'coach.cookPartners';
  static const cookRelease = 'coach.cookRelease';
  static const showsEvidence = 'coach.showsEvidence';
  static const illness = 'coach.illnessDay';
  static const trainingBreak = 'coach.trainingBreak';
  static const handledMissed = 'coach.handledMissed';
  static const efforts = 'coach.efforts';
  static const closedReviews = 'coach.closedReviews';
  static const dismissedSuggestions = 'coach.dismissedSuggestions';
  static const wakeAlarm = 'coach.wakeAlarm';
  static const demo = 'coach.demo';

  /// Worker-Adresse (gehört zur Sicherung, `AppBackup.isBackedUp`).
  static const workerURL = 'ai.workerURL';

  // Gerätestand, nicht in der Sicherung.
  static const garminLastSync = 'garmin.lastSync';
  static const garminProfile = 'garmin.profile';
  static const garminProfileDate = 'garmin.profileDate';
  static const garminWeights = 'garmin.weights';
  static const garminRacePredictions = 'garmin.racePredictions';
  static const garminKeyExpiry = 'garmin.keyExpiry';
  static const garminActivityBackfill = 'garmin.activityBackfill';
  static const garminReportFailures = 'garmin.reportFailures';
  static const healthLastImport = 'health.lastImport';
  static const healthImportEnabled = 'health.importEnabled';
  static const healthWeights = 'health.weights';
  static const healthRecordingFailures = 'health.recordingFailures';
  static const gymActiveSession = 'gym.activeSession';
  static const gymShowsList = 'gym.showsList';
  static const gymRestPanelCollapsed = 'gym.restPanelCollapsed';
  static const pendingAnalyses = 'nutrition.pendingAnalyses';
  static const socialSharedPosts = 'social.sharedPosts';
  static const socialAutoShare = 'social.autoShare';
  static const socialAutoShareSince = 'social.autoShareSince';
  static const backupLastAuto = 'backup.lastAuto';
  static const backupLastError = 'backup.lastError';
  static const backupFolder = 'backup.folder';
}

/// Einstellungen in der Datenbank, wie die UserDefaults der Swift-App: je Schlüssel ein typisierter Wert
/// ([BackupValue]). Strukturierte Werte liegen als JSON-Bytes vor. Gelesen wird aus einem Zwischenspeicher, der beim
/// Start geladen wird; Schreiben ändert ihn sofort und speichert im Hintergrund.
final class SettingsStore {
  SettingsStore._(this._db, this._values);

  final CoachDatabase _db;
  final Map<String, BackupValue> _values;
  final _changes = StreamController<String>.broadcast();

  /// Lädt alle Einstellungen aus der Datenbank.
  static Future<SettingsStore> open(CoachDatabase db) async {
    final rows = await db.select(db.settingRecords).get();
    final values = <String, BackupValue>{};
    for (final row in rows) {
      final value = _decode(row);
      if (value != null) values[row.key] = value;
    }
    return SettingsStore._(db, values);
  }

  /// Geänderte Schlüssel (für Provider, die neu lesen müssen).
  Stream<String> get changes => _changes.stream;

  Iterable<String> get keys => _values.keys;

  BackupValue? raw(String key) => _values[key];

  bool contains(String key) => _values.containsKey(key);

  // Lesen

  String? string(String key) => switch (_values[key]) {
    BackupString(:final value) => value,
    _ => null,
  };

  /// Wahrheitswert; fehlt er, `false` (wie `UserDefaults.bool`).
  bool boolValue(String key) => switch (_values[key]) {
    BackupBool(:final value) => value,
    BackupInt(:final value) => value != 0,
    _ => false,
  };

  int? intValue(String key) => switch (_values[key]) {
    BackupInt(:final value) => value,
    BackupDouble(:final value) => value.truncate(),
    _ => null,
  };

  double? doubleValue(String key) => switch (_values[key]) {
    BackupDouble(:final value) => value,
    BackupInt(:final value) => value.toDouble(),
    _ => null,
  };

  Uint8List? data(String key) => switch (_values[key]) {
    BackupData(:final bytes) => bytes,
    _ => null,
  };

  /// JSON-Wert eines Schlüssels; `null`, wenn er fehlt oder kein gültiges JSON ist.
  Object? json(String key) {
    final bytes = data(key);
    if (bytes == null) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  /// Gelesener und umgewandelter Wert, sonst [fallback] (wie `try? JSONDecoder().decode(…) ?? Standard`).
  T read<T>(String key, T? Function(Object? json) decode, T fallback) {
    final json = this.json(key);
    if (json == null) return fallback;
    try {
      return decode(json) ?? fallback;
    } on Object {
      return fallback;
    }
  }

  // Schreiben

  Future<void> setValue(String key, BackupValue? value) async {
    if (value == null) {
      _values.remove(key);
      _changes.add(key);
      await (_db.delete(_db.settingRecords)..where((row) => row.key.equals(key))).go();
      return;
    }
    _values[key] = value;
    _changes.add(key);
    await _db.into(_db.settingRecords).insertOnConflictUpdate(_encode(key, value));
  }

  Future<void> setString(String key, String? value) => setValue(key, value == null ? null : BackupString(value));

  Future<void> setBool(String key, bool value) => setValue(key, BackupBool(value));

  Future<void> setInt(String key, int? value) => setValue(key, value == null ? null : BackupInt(value));

  Future<void> setDouble(String key, double? value) => setValue(key, value == null ? null : BackupDouble(value));

  /// Speichert einen JSON-Wert (Map, Liste, Zahl, Text) bzw. ein Objekt mit `toJson()` als JSON-Bytes.
  Future<void> setJson(String key, Object? value) =>
      setValue(key, value == null ? null : BackupData(utf8.encode(jsonEncode(value))));

  Future<void> remove(String key) => setValue(key, null);

  /// Alle Werte, die zur Sicherung gehören (`AppBackup.isBackedUp`).
  Map<String, BackupValue> get backedUp => {
    for (final MapEntry(:key, :value) in _values.entries)
      if (AppBackup.isBackedUp(key)) key: value,
  };

  /// Einstellungen aus einer Sicherung übernehmen (ersetzen); nur Schlüssel, die zur Sicherung gehören.
  Future<int> restore(Map<String, BackupValue> settings) async {
    var count = 0;
    await _db.transaction(() async {
      for (final MapEntry(:key, :value) in settings.entries) {
        if (!AppBackup.isBackedUp(key)) continue;
        _values[key] = value;
        await _db.into(_db.settingRecords).insertOnConflictUpdate(_encode(key, value));
        count += 1;
      }
    });
    for (final key in settings.keys) {
      _changes.add(key);
    }
    return count;
  }

  Future<void> close() => _changes.close();

  static SettingRecordsCompanion _encode(String key, BackupValue value) => SettingRecordsCompanion.insert(
    key: key,
    type: value.type,
    value: switch (value) {
      BackupData(:final bytes) => bytes,
      BackupString(:final value) => utf8.encode(value),
      BackupBool(:final value) => utf8.encode('$value'),
      BackupInt(:final value) => utf8.encode('$value'),
      BackupDouble(:final value) => utf8.encode('$value'),
    },
  );

  static BackupValue? _decode(SettingRow row) {
    final text = row.type == 'data' ? null : utf8.decode(row.value, allowMalformed: true);
    return switch (row.type) {
      'data' => BackupData(row.value),
      'string' => BackupString(text!),
      'bool' => BackupBool(text == 'true'),
      'int' => switch (int.tryParse(text!)) {
        final value? => BackupInt(value),
        null => null,
      },
      'double' => switch (double.tryParse(text!)) {
        final value? => BackupDouble(value),
        null => null,
      },
      _ => null,
    };
  }
}

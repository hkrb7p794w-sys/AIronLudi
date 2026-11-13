import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../util/swift_date.dart';
import '../util/swift_json.dart';

/// Ein gesicherter Einstellungswert (wie `UserDefaults`: Daten, Text, Wahrheitswert, Ganzzahl oder Kommazahl).
sealed class BackupValue {
  const BackupValue();

  String get type;
  Object get jsonValue;

  Map<String, Object?> toJson() => {'type': type, 'value': jsonValue};

  /// `null` bei unbekanntem Typ oder unpassendem Wert (Swift wirft dann einen Fehler).
  static BackupValue? fromJson(Object? json) {
    if (json is! Map) return null;
    final value = json['value'];
    return switch (json['type']) {
      'data' when value is String => _decodeData(value),
      'string' when value is String => BackupString(value),
      'bool' when value is bool => BackupBool(value),
      'int' when value is int => BackupInt(value),
      'double' when value is num => BackupDouble(value.toDouble()),
      _ => null,
    };
  }

  static BackupData? _decodeData(String base64Text) {
    try {
      return BackupData(base64.decode(base64Text));
    } on FormatException {
      return null;
    }
  }
}

final class BackupData extends BackupValue {
  BackupData(List<int> bytes) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;

  @override
  String get type => 'data';

  /// `Data` kodiert Swift als Base64.
  @override
  Object get jsonValue => base64.encode(bytes);

  @override
  bool operator ==(Object other) => other is BackupData && const ListEquality<int>().equals(other.bytes, bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}

final class BackupString extends BackupValue {
  const BackupString(this.value);

  final String value;

  @override
  String get type => 'string';

  @override
  Object get jsonValue => value;

  @override
  bool operator ==(Object other) => other is BackupString && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class BackupBool extends BackupValue {
  const BackupBool(this.value);

  final bool value;

  @override
  String get type => 'bool';

  @override
  Object get jsonValue => value;

  @override
  bool operator ==(Object other) => other is BackupBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class BackupInt extends BackupValue {
  const BackupInt(this.value);

  final int value;

  @override
  String get type => 'int';

  @override
  Object get jsonValue => value;

  @override
  bool operator ==(Object other) => other is BackupInt && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class BackupDouble extends BackupValue {
  const BackupDouble(this.value);

  final double value;

  @override
  String get type => 'double';

  @override
  Object get jsonValue => value;

  @override
  bool operator ==(Object other) => other is BackupDouble && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

Uint8List? _bytes(Object? value) {
  if (value is! String) return null;
  try {
    return base64.decode(value);
  } on FormatException {
    return null;
  }
}

/// Eine gesicherte Krafteinheit.
final class BackupGym {
  BackupGym({required this.id, required List<int> payload, required this.savedToHealth, required this.uploadedToGarmin})
    : payload = Uint8List.fromList(payload);

  final String id;

  /// `GymSession` als JSON, unverändert aus der Datenbank.
  final Uint8List payload;
  final bool savedToHealth;
  final bool uploadedToGarmin;

  Map<String, Object?> toJson() => {
    'id': id,
    'payload': base64.encode(payload),
    'savedToHealth': savedToHealth,
    'uploadedToGarmin': uploadedToGarmin,
  };

  static BackupGym? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, payload, health, garmin) = (
      json['id'],
      _bytes(json['payload']),
      json['savedToHealth'],
      json['uploadedToGarmin'],
    );
    if (id is! String || payload == null || health is! bool || garmin is! bool) return null;
    return BackupGym(id: id, payload: payload, savedToHealth: health, uploadedToGarmin: garmin);
  }

  @override
  bool operator ==(Object other) =>
      other is BackupGym &&
      other.id == id &&
      const ListEquality<int>().equals(other.payload, payload) &&
      other.savedToHealth == savedToHealth &&
      other.uploadedToGarmin == uploadedToGarmin;

  @override
  int get hashCode => Object.hash(id, savedToHealth, uploadedToGarmin);
}

/// Eine gesicherte Mahlzeit.
final class BackupMeal {
  BackupMeal({
    required this.id,
    required this.dayKey,
    required this.createdAt,
    required this.category,
    required this.title,
    required this.hint,
    required List<int> items,
  }) : items = Uint8List.fromList(items);

  final String id;
  final String dayKey;
  final DateTime createdAt;
  final String category;
  final String title;
  final String hint;

  /// `[MealItem]` als JSON.
  final Uint8List items;

  Map<String, Object?> toJson() => {
    'id': id,
    'dayKey': dayKey,
    'createdAt': swiftDateToJson(createdAt),
    'category': category,
    'title': title,
    'hint': hint,
    'items': base64.encode(items),
  };

  static BackupMeal? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, dayKey, category, title, hint) = (
      json['id'],
      json['dayKey'],
      json['category'],
      json['title'],
      json['hint'],
    );
    final createdAt = json['createdAt'] is String ? swiftDateFromJson(json['createdAt']) : null;
    final items = _bytes(json['items']);
    if (id is! String ||
        dayKey is! String ||
        createdAt == null ||
        category is! String ||
        title is! String ||
        hint is! String ||
        items == null) {
      return null;
    }
    return BackupMeal(
      id: id,
      dayKey: dayKey,
      createdAt: createdAt,
      category: category,
      title: title,
      hint: hint,
      items: items,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupMeal &&
      other.id == id &&
      other.dayKey == dayKey &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      other.category == category &&
      other.title == title &&
      other.hint == hint &&
      const ListEquality<int>().equals(other.items, items);

  @override
  int get hashCode => Object.hash(id, dayKey, category, title);
}

/// Ein gesichertes eigenes Lebensmittel.
final class BackupFood {
  BackupFood({
    required this.key,
    required this.name,
    required List<int> payload,
    required this.lastUsed,
    required this.useCount,
  }) : payload = Uint8List.fromList(payload);

  final String key;
  final String name;

  /// `MealItem` als JSON.
  final Uint8List payload;
  final DateTime lastUsed;
  final int useCount;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'payload': base64.encode(payload),
    'lastUsed': swiftDateToJson(lastUsed),
    'useCount': useCount,
  };

  static BackupFood? fromJson(Object? json) {
    if (json is! Map) return null;
    final (key, name, useCount) = (json['key'], json['name'], json['useCount']);
    final payload = _bytes(json['payload']);
    final lastUsed = json['lastUsed'] is String ? swiftDateFromJson(json['lastUsed']) : null;
    if (key is! String || name is! String || payload == null || lastUsed == null || useCount is! int) return null;
    return BackupFood(key: key, name: name, payload: payload, lastUsed: lastUsed, useCount: useCount);
  }

  @override
  bool operator ==(Object other) =>
      other is BackupFood &&
      other.key == key &&
      other.name == name &&
      const ListEquality<int>().equals(other.payload, payload) &&
      other.lastUsed.isAtSameMomentAs(lastUsed) &&
      other.useCount == useCount;

  @override
  int get hashCode => Object.hash(key, name, useCount);
}

/// Fehler beim Einlesen einer Sicherung.
sealed class BackupFailure implements Exception {
  const BackupFailure();

  String get message;

  @override
  String toString() => message;
}

final class BackupUnreadable extends BackupFailure {
  const BackupUnreadable();

  @override
  String get message => 'Die Datei ist keine IronLudi-Sicherung oder beschädigt.';

  @override
  bool operator ==(Object other) => other is BackupUnreadable;

  @override
  int get hashCode => 0;
}

final class BackupNewerVersion extends BackupFailure {
  const BackupNewerVersion(this.version);

  final int version;

  @override
  String get message =>
      'Die Sicherung stammt aus einer neueren App-Version (Format $version). Bitte erst AIronLudi aktualisieren.';

  @override
  bool operator ==(Object other) => other is BackupNewerVersion && other.version == version;

  @override
  int get hashCode => version.hashCode;
}

/// Datensicherung der App als eine JSON-Datei: Einstellungen, Krafteinheiten, Mahlzeiten und eigene Lebensmittel.
/// Nicht enthalten: Zugangsdaten aus dem sicheren Speicher (Garmin, App-Token) und Garmin-/Health-Daten, die beim
/// nächsten Abruf ohnehin wiederkommen. Einspielen führt zusammen: Vorhandenes bleibt, Fehlendes kommt dazu;
/// Einstellungen werden ersetzt. Das Format ist das der Swift-App (Umzug in beide Richtungen).
final class AppBackup {
  AppBackup({
    this.version = currentVersion,
    required this.createdAt,
    required this.settings,
    required this.gym,
    required this.meals,
    required this.foods,
  });

  static const currentVersion = 1;
  static const fileName = 'IronLudi-Sicherung.json';
  static const previousFileName = 'IronLudi-Sicherung-vorher.json';

  /// Automatische Sicherung höchstens so oft.
  static const autoInterval = Duration(hours: 20);

  final int version;
  final DateTime createdAt;
  final Map<String, BackupValue> settings;
  final List<BackupGym> gym;
  final List<BackupMeal> meals;
  final List<BackupFood> foods;

  /// Gesichert werden die App-Einstellungen (`coach.…`) und die Worker-Adresse. Nicht: Abrufstände von Garmin und
  /// Health (sonst fehlten nach dem Einspielen ältere Aktivitäten), der laufende Wecker und die gerade offene
  /// Krafteinheit.
  static bool isBackedUp(String key) {
    if (key == 'ai.workerURL') return true;
    return key.startsWith('coach.') && !excludedKeys.contains(key);
  }

  static const excludedKeys = {'coach.wakeAlarm'};

  Map<String, Object?> toJson() => {
    'version': version,
    'createdAt': swiftDateToJson(createdAt),
    'settings': {for (final MapEntry(:key, :value) in settings.entries) key: value.toJson()},
    'gym': [for (final item in gym) item.toJson()],
    'meals': [for (final item in meals) item.toJson()],
    'foods': [for (final item in foods) item.toJson()],
  };

  /// JSON wie in Swift (`.iso8601`, `.sortedKeys`).
  List<int> encoded() => utf8.encode(swiftSortedJson(toJson()));

  /// Wirft [BackupFailure].
  static AppBackup decode(List<int> data) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } on FormatException {
      throw const BackupUnreadable();
    }
    if (json is! Map || json['version'] is! int) throw const BackupUnreadable();
    final version = json['version'] as int;
    if (version > currentVersion) throw BackupNewerVersion(version);
    final createdAt = json['createdAt'] is String ? swiftDateFromJson(json['createdAt']) : null;
    final rawSettings = json['settings'];
    final gym = _list(json['gym'], BackupGym.fromJson);
    final meals = _list(json['meals'], BackupMeal.fromJson);
    final foods = _list(json['foods'], BackupFood.fromJson);
    if (createdAt == null || rawSettings is! Map || gym == null || meals == null || foods == null) {
      throw const BackupUnreadable();
    }
    final settings = <String, BackupValue>{};
    for (final MapEntry(:key, :value) in rawSettings.entries) {
      final decoded = BackupValue.fromJson(value);
      if (key is! String || decoded == null) throw const BackupUnreadable();
      settings[key] = decoded;
    }
    return AppBackup(version: version, createdAt: createdAt, settings: settings, gym: gym, meals: meals, foods: foods);
  }

  static List<T>? _list<T>(Object? json, T? Function(Object?) read) {
    if (json is! List) return null;
    final result = <T>[];
    for (final item in json) {
      final value = read(item);
      if (value == null) return null;
      result.add(value);
    }
    return result;
  }

  /// Kurzbeschreibung für die Bestätigung vor dem Einspielen.
  String get summary =>
      '${gym.length} Krafteinheiten, ${meals.length} Mahlzeiten, ${foods.length} eigene Lebensmittel, '
      '${settings.length} Einstellungen';

  /// Automatische Sicherung fällig (nie gesichert oder länger als [autoInterval] her).
  static bool isDue({required DateTime? last, required DateTime now}) {
    if (last == null) return true;
    return now.difference(last) >= autoInterval || last.isAfter(now);
  }

  /// Was beim Zusammenführen dazukommt: nur Einträge, deren Schlüssel noch fehlt, ohne Doppelte in der Datei.
  static List<T> missing<T, K>(List<T> items, {required K Function(T) key, required Set<K> existing}) {
    final seen = {...existing};
    return [
      for (final item in items)
        if (seen.add(key(item))) item,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is AppBackup &&
      other.version == version &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      const MapEquality<String, BackupValue>().equals(other.settings, settings) &&
      const ListEquality<BackupGym>().equals(other.gym, gym) &&
      const ListEquality<BackupMeal>().equals(other.meals, meals) &&
      const ListEquality<BackupFood>().equals(other.foods, foods);

  @override
  int get hashCode => Object.hash(version, createdAt.millisecondsSinceEpoch, settings.length, gym.length);
}

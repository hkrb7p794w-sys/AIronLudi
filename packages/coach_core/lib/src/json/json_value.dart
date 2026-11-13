import 'dart:convert';

import 'package:collection/collection.dart';

/// Beliebiges JSON, tolerant gelesen (Port von `JSONValue`).
///
/// Die Antwortformate der Garmin Personal API und der KI sind nicht dokumentiert und können sich ändern. Statt
/// starrer Strukturen werden Felder deshalb über mehrere mögliche Namen und in verschachtelten Ebenen gesucht.
final class JsonValue {
  /// Hüllt einen Wert aus `jsonDecode` ein (Map, List, String, num, bool oder null).
  const JsonValue(this.raw);

  static const JsonValue nullValue = JsonValue(null);

  /// Liest JSON-Text; wirft bei ungültigem JSON (wie `JSONValue(data:)`).
  factory JsonValue.parse(String text) => JsonValue(jsonDecode(text));

  final Object? raw;

  bool get isNull => raw == null;

  JsonValue? operator [](String key) {
    final value = raw;
    if (value is Map && value.containsKey(key)) return JsonValue(value[key]);
    return null;
  }

  Map<String, JsonValue>? get objectValue {
    final value = raw;
    if (value is! Map) return null;
    return {for (final entry in value.entries) entry.key as String: JsonValue(entry.value)};
  }

  List<JsonValue>? get arrayValue {
    final value = raw;
    if (value is! List) return null;
    return [for (final element in value) JsonValue(element)];
  }

  double? get doubleValue {
    final value = raw;
    if (value is num) return value.toDouble();
    if (value is String) return _parseSwiftDouble(value);
    return null;
  }

  int? get intValue {
    final value = doubleValue;
    if (value == null || !value.isFinite) return null;
    return value.round();
  }

  /// Ganzzahl in festen Grenzen. Fremde Zahlen (KI, Import) können riesig sein.
  int? clampedInt(int lower, int upper) {
    final value = doubleValue;
    if (value == null || value.isNaN) return null;
    return value.clamp(lower.toDouble(), upper.toDouble()).truncate();
  }

  /// Text; Zahlen werden wie in Swift umgewandelt (ganze Zahlen ohne Nachkommastellen).
  String? get stringValue {
    final value = raw;
    if (value is String) return value;
    if (value is num) {
      final number = value.toDouble();
      if (number.isFinite && number == number.roundToDouble() && number.abs() < 9e15) return number.toInt().toString();
      return number.toString();
    }
    return null;
  }

  /// Nur echter Text (keine umgewandelten Zahlen).
  String? get textValue => raw is String ? raw as String : null;

  bool? get boolValue => raw is bool ? raw as bool : null;

  /// Sucht den ersten Wert unter einem der Schlüssel, zuerst auf der obersten Ebene, dann in die Tiefe
  /// (Breitensuche, Schlüssel alphabetisch). `null` zählt als nicht gefunden.
  JsonValue? firstValue(List<String> keys) {
    final queue = <Object?>[raw];
    var index = 0;
    while (index < queue.length) {
      final current = queue[index];
      index += 1;
      if (current is Map) {
        for (final key in keys) {
          if (current.containsKey(key) && current[key] != null) return JsonValue(current[key]);
        }
        final sortedKeys = current.keys.cast<String>().toList()..sort();
        queue.addAll(sortedKeys.map((key) => current[key]));
      } else if (current is List) {
        queue.addAll(current);
      }
    }
    return null;
  }

  /// Alle Objekte im Baum, die den Schlüssel enthalten (äußerste zuerst, verschachtelte Treffer innerhalb eines
  /// Treffers werden nicht doppelt geliefert).
  List<Map<String, JsonValue>> objects(String key) {
    final value = raw;
    if (value is Map) {
      if (value.containsKey(key)) return [JsonValue(value).objectValue!];
      final sortedKeys = value.keys.cast<String>().toList()..sort();
      return [for (final child in sortedKeys) ...JsonValue(value[child]).objects(key)];
    }
    if (value is List) return [for (final child in value) ...JsonValue(child).objects(key)];
    return const [];
  }

  /// Schlüsselpfade aller Blätter, z. B. `hrvSummary.status` oder `[].calendarDate` (Diagnose).
  List<String> keyPaths({int limit = 200}) {
    final result = <String>[];
    final seen = <String>{};
    void walk(Object? value, String path) {
      if (result.length >= limit) return;
      if (value is Map) {
        final sortedKeys = value.keys.cast<String>().toList()..sort();
        for (final key in sortedKeys) {
          walk(value[key], path.isEmpty ? key : '$path.$key');
        }
      } else if (value is List) {
        for (final child in value.take(3)) {
          walk(child, '$path[]');
        }
      } else if (seen.add(path)) {
        result.add(path);
      }
    }

    walk(raw, '');
    return result;
  }

  String encode() => jsonEncode(raw);

  @override
  bool operator ==(Object other) =>
      other is JsonValue && const DeepCollectionEquality().equals(_normalized(raw), _normalized(other.raw));

  @override
  int get hashCode => const DeepCollectionEquality().hash(_normalized(raw));

  @override
  String toString() => encode();

  /// Zahlen vergleichen wie in Swift (`Double`): 1 == 1.0.
  static Object? _normalized(Object? value) => switch (value) {
    final int number => number.toDouble(),
    final Map<Object?, Object?> map => {for (final entry in map.entries) entry.key: _normalized(entry.value)},
    final List<Object?> list => [for (final element in list) _normalized(element)],
    _ => value,
  };

  /// `Double(String)` in Swift: kein Leerraum, kein Komma, „inf“/„nan“ erlaubt.
  static double? _parseSwiftDouble(String text) {
    if (text.isEmpty || text.trim() != text) return null;
    return double.tryParse(text);
  }
}

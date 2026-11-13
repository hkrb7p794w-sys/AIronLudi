/// Enums mit dem Rohwert aus Swift (`rawValue`), wie er in Sicherungen und Einstellungen steht.
abstract interface class RawEnum {
  String get rawValue;
}

/// Wert zu einem Rohwert oder `null` (unbekannte Werte aus neueren Versionen werden übergangen).
T? enumFromRaw<T extends RawEnum>(List<T> values, Object? raw) {
  for (final value in values) {
    if (value.rawValue == raw) return value;
  }
  return null;
}

/// Liste von Rohwerten lesen; Unbekanntes fällt weg.
List<T> enumListFromRaw<T extends RawEnum>(List<T> values, Object? raw) =>
    raw is List ? raw.map((item) => enumFromRaw(values, item)).nonNulls.toList() : <T>[];

/// Liste wie das synthetisierte `Decodable` in Swift: ein unbekannter Wert macht die ganze Liste ungültig (`null`).
List<T>? enumListStrict<T extends RawEnum>(List<T> values, Object? raw) {
  if (raw is! List) return null;
  final result = <T>[];
  for (final item in raw) {
    final value = enumFromRaw(values, item);
    if (value == null) return null;
    result.add(value);
  }
  return result;
}

/// Liste von Objekten streng lesen: scheitert ein Element, ist die ganze Liste ungültig (`null`).
List<T>? listStrict<T>(Object? raw, T? Function(Object?) read) {
  if (raw is! List) return null;
  final result = <T>[];
  for (final item in raw) {
    final value = read(item);
    if (value == null) return null;
    result.add(value);
  }
  return result;
}

double? jsonDouble(Object? value) => value is num ? value.toDouble() : null;

int? jsonInt(Object? value) => value is num && value.isFinite ? value.round() : null;

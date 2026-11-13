/// Zeitpunkte wie in den Sicherungen der Swift-App (`JSONEncoder.dateEncodingStrategy = .iso8601`):
/// „2026-11-02T07:30:00Z“, ohne Sekundenbruchteile, immer UTC.
String swiftDateToJson(DateTime date) {
  final utc = date.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}Z';
}

/// Liest ISO-8601-Zeitpunkte; Zahlen gelten wie beim Standard-`JSONDecoder` als Sekunden seit dem 1.1.2001 (UTC).
DateTime? swiftDateFromJson(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is num && value.isFinite) {
    return DateTime.utc(2001).add(Duration(microseconds: (value * 1000000).round()));
  }
  return null;
}

/// Zeitpunkt wie der Standard-`JSONEncoder` in Swift (`.deferredToDate`): Sekunden seit dem 1.1.2001 (UTC). Nötig für
/// Dateien, die native Swift-Teile lesen (Widgets, Live-Aktivität).
double swiftReferenceDateToJson(DateTime date) => date.toUtc().difference(DateTime.utc(2001)).inMicroseconds / 1000000;

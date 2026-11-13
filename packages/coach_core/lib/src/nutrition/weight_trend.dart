import '../calendar/calendar_day.dart';
import '../util/enum_codec.dart';

enum WeightSource implements RawEnum {
  manual,
  garmin,
  health;

  @override
  String get rawValue => name;
}

/// Eine Wägung (eigene Eingabe, Garmin oder Apple Health / Health Connect).
final class WeightEntry {
  const WeightEntry({required this.day, required this.kilograms, required this.source});

  final CalendarDay day;
  final double kilograms;
  final WeightSource source;

  String get id => '${day.iso}-${source.rawValue}';

  Map<String, Object?> toJson() => {'day': day.toJson(), 'kilograms': kilograms, 'source': source.rawValue};

  static WeightEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = json['day'];
    final kilograms = jsonDouble(json['kilograms']);
    final source = enumFromRaw(WeightSource.values, json['source']);
    if (day is! Map || kilograms == null || source == null) return null;
    return WeightEntry(day: CalendarDay.fromJson(day.cast<String, Object?>()), kilograms: kilograms, source: source);
  }

  @override
  bool operator ==(Object other) =>
      other is WeightEntry && other.day == day && other.kilograms == kilograms && other.source == source;

  @override
  int get hashCode => Object.hash(day, kilograms, source);

  @override
  String toString() => 'WeightEntry($day, $kilograms, ${source.rawValue})';
}

/// Gewichtsverlauf (Port von `WeightTrend`). Hier zunächst das Zusammenführen der Quellen, das die Schutzgrenzen
/// brauchen; Trendlinie, Abgleich mit dem Plan und Nachsteuerung folgen mit dem Ernährungsmodul.
abstract final class WeightTrend {
  static const minimumEntries = 8;
  static const minimumSpanDays = 14;
  static const windowDays = 28;
  static const tolerancePercent = 0.25;
  static const maxStepKilocalories = 250.0;
  static const maxTotalKilocalories = 500.0;

  /// Ein Wert pro Tag: eigene Eingaben vor Garmin, Garmin vor Apple Health. Bei gleicher Quelle gilt der letzte.
  static List<WeightEntry> merged(Iterable<WeightEntry> entries) {
    int rank(WeightSource source) => switch (source) {
      WeightSource.manual => 2,
      WeightSource.garmin => 1,
      WeightSource.health => 0,
    };
    final byDay = <CalendarDay, WeightEntry>{};
    for (final entry in entries) {
      if (entry.kilograms < 25 || entry.kilograms > 300) continue;
      final existing = byDay[entry.day];
      if (existing != null && rank(existing.source) > rank(entry.source)) continue;
      byDay[entry.day] = entry;
    }
    return byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }
}

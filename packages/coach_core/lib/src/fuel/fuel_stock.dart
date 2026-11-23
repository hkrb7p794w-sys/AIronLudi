// Fuel Planner: Vorrat an Produkten (Gels, Riegel, Pulver …) je Benutzer mit Mindesthaltbarkeit. Der Planer braucht
// den Vorrat zuerst auf (bald ablaufendes zuerst) und zeigt, was zu kaufen ist. Spezifikation 11.
import '../calendar/calendar_day.dart';
import '../util/enum_codec.dart';

final class FuelStock {
  const FuelStock({required this.count, this.bestBefore});

  /// Portionen (Gels, Riegel) bzw. Flaschen/Portionen Pulver.
  final double count;

  /// Mindesthaltbarkeit (frühestes Datum, wenn mehrere Packungen).
  final CalendarDay? bestBefore;

  /// Abgelaufen am [day]?
  bool expiredOn(CalendarDay day) => bestBefore != null && bestBefore! < day;

  /// Läuft innerhalb von [days] Tagen ab dem [day] ab?
  bool expiresSoon(CalendarDay day, {int days = 30}) =>
      bestBefore != null && !expiredOn(day) && day.daysUntil(bestBefore!) <= days;

  FuelStock copyWith({double? count, CalendarDay? Function()? bestBefore}) =>
      FuelStock(count: count ?? this.count, bestBefore: bestBefore == null ? this.bestBefore : bestBefore());

  Map<String, Object?> toJson() => {'count': count, 'bestBefore': ?bestBefore?.iso};

  static FuelStock? fromJson(Object? json) {
    if (json is! Map) return null;
    final count = jsonDouble(json['count']);
    if (count == null || count < 0) return null;
    final day = json['bestBefore'];
    return FuelStock(count: count, bestBefore: day is String ? CalendarDay.tryParse(day) : null);
  }
}

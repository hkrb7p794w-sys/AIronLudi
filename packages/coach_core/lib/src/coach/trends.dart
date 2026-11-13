import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import 'season_plan.dart';

/// Ein Messwert an einem Tag – Grundlage der Verlaufsgrafiken.
final class DayValue {
  const DayValue({required this.day, required this.value});

  final CalendarDay day;
  final double value;

  String get id => day.iso;

  @override
  bool operator ==(Object other) => other is DayValue && other.day == day && other.value == value;

  @override
  int get hashCode => Object.hash(day, value);

  @override
  String toString() => 'DayValue($day, $value)';
}

/// Verlauf eines Werts über einen Zeitraum, wie die Karte `coach-trend` im Altbestand: aktueller Wert, Schnitt des
/// Zeitraums und Veränderung gegenüber dem Zeitraum davor.
final class MetricTrend {
  /// [values]: alle bekannten Werte (beliebige Reihenfolge, Tage ohne Wert fehlen einfach); [days]: Länge des Zeitraums
  /// bis einschließlich [today].
  factory MetricTrend(List<DayValue> values, {required int days, required CalendarDay today}) {
    final start = today.adding(-(days - 1));
    final previousStart = start.adding(-days);
    final sorted = [...values]..sort((a, b) => a.day.compareTo(b.day));
    final points = sorted.where((value) => start <= value.day && value.day <= today).toList();
    return MetricTrend._(
      points: points,
      latest: points.isEmpty ? null : points.last,
      average: _mean(points),
      previousAverage: _mean(sorted.where((value) => previousStart <= value.day && value.day < start).toList()),
    );
  }

  const MetricTrend._({
    required this.points,
    required this.latest,
    required this.average,
    required this.previousAverage,
  });

  final List<DayValue> points;
  final DayValue? latest;
  final double? average;
  final double? previousAverage;

  /// Veränderung des Schnitts gegenüber dem vorherigen gleich langen Zeitraum.
  double? get change => average == null || previousAverage == null ? null : average! - previousAverage!;

  static double? _mean(List<DayValue> values) =>
      values.isEmpty ? null : values.fold<double>(0, (sum, value) => sum + value.value) / values.length;

  /// Werte eines Felds aus den Tageswerten.
  static List<DayValue> values(List<DailyMetrics> days, double? Function(DailyMetrics metrics) field) => [
    for (final metrics in days)
      if (field(metrics) case final value?) DayValue(day: metrics.day, value: value),
  ];
}

/// Kilometer und Einheiten je Woche und Sportart für die Wochenbalken.
final class WeekVolume {
  const WeekVolume({required this.monday, required this.volume});

  final CalendarDay monday;
  final WeeklyVolume volume;

  String get id => monday.iso;

  /// Die letzten [weeks] Wochen bis einschließlich der Woche von [today], älteste zuerst.
  static List<WeekVolume> history(List<GarminActivity> activities, {required CalendarDay today, required int weeks}) {
    final thisMonday = today.adding(-today.weekdayIndex);
    return [
      for (var offset = weeks - 1; offset >= 0; offset--)
        WeekVolume(
          monday: thisMonday.adding(-7 * offset),
          volume: WeeklyVolume.from(activities, weekContaining: thisMonday.adding(-7 * offset)),
        ),
    ];
  }
}

/// VO2max-Werte aus Aktivitäten (Garmin schreibt sie nur nach qualifizierenden Einheiten) und dem Profil.
abstract final class VO2MaxHistory {
  /// Je Tag der höchste Wert aus Lauf- bzw. Radeinheiten.
  static List<DayValue> values(List<GarminActivity> activities, {required ActivitySport sport}) {
    final best = <CalendarDay, double>{};
    for (final activity in activities.where((activity) => activity.sport == sport)) {
      final day = activity.day;
      final value = activity.vo2Max;
      if (day == null || value == null || value <= 10) continue;
      final current = best[day] ?? 0;
      best[day] = value > current ? value : current;
    }
    return [for (final entry in best.entries) DayValue(day: entry.key, value: entry.value)]
      ..sort((a, b) => a.day.compareTo(b.day));
  }
}

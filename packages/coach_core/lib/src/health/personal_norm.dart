import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';

/// Lage eines Werts zum persönlichen Bereich.
enum NormPosition { below, within, above }

/// Persönlicher Normalbereich eines Werts: Mittelwert ± eine Standardabweichung der letzten Wochen (heute nicht
/// mitgezählt). Rund zwei Drittel der eigenen Tage liegen darin – ein Wert außerhalb ist für diese Person
/// auffällig, auch wenn er allgemein „normal“ wäre (Plews et al. 2013 für HRV; dasselbe Prinzip für Ruhepuls,
/// Schlaf und Body Battery).
final class PersonalNorm {
  const PersonalNorm({required this.mean, required this.low, required this.high, required this.count});

  final double mean;
  final double low;
  final double high;

  /// Anzahl Tage, aus denen der Bereich stammt.
  final int count;

  /// Mindestens so viele Tage, sonst gibt es keinen persönlichen Bereich (dann gilt nur der allgemeine Richtwert).
  static const minimumDays = 7;
  static const windowDays = 30;

  /// Bereich aus den Tagen vor [today] (bis [window] Tage zurück).
  static PersonalNorm? fromDays(
    List<DailyMetrics> days, {
    required CalendarDay today,
    int window = windowDays,
    required double? Function(DailyMetrics metrics) field,
  }) {
    final start = today.adding(-window);
    return of([
      for (final metrics in days)
        if (metrics.day >= start && metrics.day < today) ?field(metrics),
    ]);
  }

  static PersonalNorm? of(List<double> values) {
    if (values.length < minimumDays) return null;
    final mean = values.fold(0.0, (sum, value) => sum + value) / values.length;
    final variance = values.fold(0.0, (sum, value) => sum + (value - mean) * (value - mean)) / (values.length - 1);
    // Untergrenze für die Spanne, damit ein sehr gleichmäßiger Verlauf nicht jede Kleinigkeit meldet.
    final spread = math.max(math.sqrt(variance), mean.abs() * 0.03);
    double round(double value) => (value * 10).roundToDouble() / 10;
    return PersonalNorm(mean: round(mean), low: round(mean - spread), high: round(mean + spread), count: values.length);
  }

  NormPosition position(double value) {
    if (value < low) return NormPosition.below;
    if (value > high) return NormPosition.above;
    return NormPosition.within;
  }

  @override
  bool operator ==(Object other) =>
      other is PersonalNorm && other.mean == mean && other.low == low && other.high == high && other.count == count;

  @override
  int get hashCode => Object.hash(mean, low, high, count);

  @override
  String toString() => 'PersonalNorm($mean, $low–$high, $count)';
}

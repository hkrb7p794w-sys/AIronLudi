import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';

/// HRV-Trend für Quellen ohne Garmins „HRV-Status“ (WHOOP: RMSSD, Apple Health: SDNN, Health Connect: RMSSD).
///
/// Maßgeblich ist wie beim Garmin-Status der 7-Tage-Schnitt, nicht die Einzelnacht: Mittelwert von ln(HRV) über die
/// letzten sieben Tage gegen die eigene Basis (Tag −60 bis −8) mit ihrer Streuung (Plews et al. 2013, Int J Sports
/// Physiol Perform 8:688–691; ln-Transformation wegen der schiefen Verteilung). Unter „Basis − 1 SD“ gilt als
/// auffällig. Die Schwelle 1 SD ist eine Annahme (Plews nutzt teils 0,5 SD als kleinste relevante Änderung); bewusst
/// vorsichtiger, weil die App sonst bei Messrauschen häufig herabstufen würde.
final class HrvTrend {
  const HrvTrend({required this.weekAverage, required this.baselineAverage, required this.baselineLow});

  /// 7-Tage-Schnitt (ms, zurückgerechnet aus ln).
  final double weekAverage;

  /// Mittel der Basis (ms).
  final double baselineAverage;

  /// Untere Grenze der Basis (Basis − 1 SD, ms).
  final double baselineLow;

  bool get isBelowBaseline => weekAverage < baselineLow;

  /// Mindestens 4 Werte in den letzten 7 Tagen und 14 in der Basis; sonst `null`.
  static HrvTrend? of(List<DailyMetrics> days, {required CalendarDay day}) {
    double? lnOf(DailyMetrics metrics) => switch (metrics.hrvLastNightAverage) {
      final v? when v > 0 => math.log(v),
      _ => null,
    };
    final week = <double>[];
    final base = <double>[];
    for (final metrics in days) {
      final offset = day.daysUntil(metrics.day);
      final value = lnOf(metrics);
      if (value == null) continue;
      if (offset <= 0 && offset > -7) week.add(value);
      if (offset <= -8 && offset >= -60) base.add(value);
    }
    if (week.length < 4 || base.length < 14) return null;
    double mean(List<double> values) => values.reduce((a, b) => a + b) / values.length;
    final baseMean = mean(base);
    final sd = math.sqrt(base.map((v) => (v - baseMean) * (v - baseMean)).reduce((a, b) => a + b) / (base.length - 1));
    return HrvTrend(
      weekAverage: math.exp(mean(week)),
      baselineAverage: math.exp(baseMean),
      baselineLow: math.exp(baseMean - sd),
    );
  }
}

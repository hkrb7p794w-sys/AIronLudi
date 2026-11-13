import 'dart:math' as math;

final class ZoomPreset {
  const ZoomPreset(this.label, this.days);

  final String label;

  /// `null` = alles
  final double? days;

  String get id => label;
}

/// Zoom und Ausschnitt für Verlaufsdiagramme: sichtbare Spanne in Tagen (per Knopf oder zwei Fingern) und die Y-Achse
/// passend zu den gerade sichtbaren Punkten, damit auch lange Verläufe lesbar bleiben.
abstract final class ChartZoom {
  static const presets = [
    ZoomPreset('1 M', 30),
    ZoomPreset('3 M', 91),
    ZoomPreset('1 J', 365),
    ZoomPreset('Alles', null),
  ];
  static const minimumDays = 14.0;
  static const _day = Duration.millisecondsPerDay / 1000;

  /// Gesamte Spanne der Daten in Tagen (mindestens [minimumDays]).
  static double spanDays(List<DateTime> dates) {
    if (dates.isEmpty) return minimumDays;
    final first = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    return math.max(last.difference(first).inMilliseconds / 1000 / _day + 1, minimumDays);
  }

  /// Sichtbare Tage zwischen zwei Wochen und der ganzen Spanne.
  static double clamp(double days, {required double span}) =>
      math.min(math.max(days, minimumDays), math.max(span, minimumDays));

  /// Standard: drei Monate, bei kürzerem Verlauf alles.
  static double initialDays(double span) => clamp(math.min(91, span), span: span);

  /// Start des sichtbaren Ausschnitts, sodass er am letzten Punkt endet.
  static DateTime initialStart(List<DateTime> dates, {required double days}) {
    final last = dates.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : dates.reduce((a, b) => a.isAfter(b) ? a : b);
    return last.add(Duration(milliseconds: ((-days * _day + _day / 2) * 1000).round()));
  }

  /// Y-Bereich der sichtbaren Werte mit 10 % Luft (mindestens [minimumPadding]); ohne sichtbare Werte der ganze
  /// Bereich.
  static ({double low, double high}) yDomain(
    List<({DateTime date, double value})> points, {
    required DateTime from,
    required double days,
    bool includesZero = false,
    double minimumPadding = 1,
  }) {
    final end = from.add(Duration(milliseconds: (days * _day * 1000).round()));
    final visible = points
        .where((point) => !point.date.isBefore(from) && !point.date.isAfter(end))
        .map((point) => point.value)
        .toList();
    final values = visible.isEmpty ? points.map((point) => point.value).toList() : visible;
    if (values.isEmpty) return (low: 0, high: 1);
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    if (includesZero) low = math.min(low, 0);
    final padding = math.max((high - low) * 0.1, math.max(high.abs() * 0.05, minimumPadding));
    high += padding;
    if (!includesZero) low -= padding;
    return (low: low, high: high);
  }

  /// Punkte nur zeigen, solange sie nicht zu dicht liegen.
  static bool showsPoints({required double days, required int count, required double span}) =>
      count * days / math.max(span, 1) <= 40;
}

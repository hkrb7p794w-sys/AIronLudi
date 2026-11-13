import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../util/german_format.dart';
import 'personal_norm.dart';

/// Ein Tag im Verlauf der Body Battery.
final class BodyBatteryDay {
  const BodyBatteryDay({
    required this.day,
    this.high,
    this.low,
    this.wake,
    this.charged,
    this.drained,
    this.sleepHours,
    this.stress,
  });

  final CalendarDay day;
  final double? high;
  final double? low;
  final double? wake;
  final double? charged;
  final double? drained;
  final double? sleepHours;
  final double? stress;

  String get id => day.iso;
}

/// Ein Zusammenhang in Worten.
final class BodyBatteryRelation {
  const BodyBatteryRelation({required this.id, required this.text});

  final String id;
  final String text;

  @override
  String toString() => 'BodyBatteryRelation($id, $text)';
}

/// Übersicht der Body Battery.
final class BodyBatterySummary {
  const BodyBatterySummary({
    required this.current,
    required this.currentMinute,
    required this.currentDay,
    required this.wake,
    required this.curve,
    required this.history,
    required this.wakeNorm,
    required this.relations,
  });

  /// Letzter Messwert und seine Uhrzeit (Minuten nach Mitternacht), falls aus dem Verlauf bekannt.
  final double? current;
  final int? currentMinute;
  final CalendarDay? currentDay;
  final double? wake;
  final List<BodyBatterySample> curve;
  final List<BodyBatteryDay> history;

  /// Persönlicher Bereich des Aufwachwerts (letzte 30 Tage).
  final PersonalNorm? wakeNorm;
  final List<BodyBatteryRelation> relations;

  bool get hasData => current != null || history.isNotEmpty;
}

/// Body Battery (Garmin, 0–100): aktueller Stand, Wert beim Aufwachen, Verlauf und der Zusammenhang mit Schlaf und
/// Stress – nur aus gemessenen Werten. Apple Health kennt keinen vergleichbaren Wert; ohne Garmin bleibt alles leer.
abstract final class BodyBatteryAnalysis {
  /// Aufwachwert: Garmins `bodyBatteryAtWakeTime`, sonst der Verlaufswert zur Aufwachzeit, sonst der Höchstwert am
  /// Vormittag (die Batterie lädt nachts und ist morgens am höchsten).
  static double? wakeValue(DailyMetrics metrics) {
    if (metrics.bodyBatteryAtWake case final wake?) return wake;
    final curve = metrics.bodyBatteryCurve;
    if (curve == null || curve.isEmpty) return null;
    if (metrics.sleepEndMinutes case final end?) {
      final minute = end.toInt();
      final sample = curve.lastWhere(
        (sample) => sample.minute <= minute && minute - sample.minute <= 60,
        orElse: () => const BodyBatterySample(minute: -1, value: -1),
      );
      if (sample.minute >= 0) return sample.value.toDouble();
    }
    final morning = curve.where((sample) => sample.minute <= 12 * 60).map((sample) => sample.value);
    return morning.isEmpty ? null : morning.reduce(math.max).toDouble();
  }

  static BodyBatterySummary summary({
    required List<DailyMetrics> days,
    required CalendarDay today,
    int historyDays = 30,
  }) {
    final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
    final start = today.adding(-(historyDays - 1));
    final history = <BodyBatteryDay>[];
    for (final metrics in sorted) {
      if (metrics.day < start || metrics.day > today) continue;
      final day = BodyBatteryDay(
        day: metrics.day,
        high: metrics.bodyBatteryHigh,
        low: metrics.bodyBatteryLow,
        wake: wakeValue(metrics),
        charged: metrics.bodyBatteryCharged,
        drained: metrics.bodyBatteryDrained,
        sleepHours: metrics.sleepHours,
        stress: metrics.stressAverage,
      );
      if (day.high == null && day.wake == null && day.charged == null) continue;
      history.add(day);
    }
    final latest = sorted.reversed
        .where((metrics) => metrics.day <= today && metrics.day >= today.adding(-1) && _hasBattery(metrics))
        .firstOrNull;
    final curve = latest?.bodyBatteryCurve ?? const <BodyBatterySample>[];
    final wakeValues = [
      for (final day in history)
        if (day.day < today) ?day.wake,
    ];
    final todayMetrics = sorted.reversed.where((metrics) => metrics.day == today).firstOrNull;
    return BodyBatterySummary(
      current: curve.isNotEmpty ? curve.last.value.toDouble() : latest?.bodyBatteryLatest,
      currentMinute: curve.isEmpty ? null : curve.last.minute,
      currentDay: latest?.day,
      wake: todayMetrics == null ? null : wakeValue(todayMetrics),
      curve: curve,
      history: history,
      wakeNorm: PersonalNorm.of(wakeValues),
      relations: relations(history),
    );
  }

  static bool _hasBattery(DailyMetrics metrics) =>
      metrics.bodyBatteryLatest != null || (metrics.bodyBatteryCurve?.isNotEmpty ?? false);

  /// Mindestens so viele Tage je Vergleichsgruppe.
  static const minimumGroup = 3;

  /// Zusammenhang mit Schlaf (Aufladung nach langen und kurzen Nächten) und Stress (Verbrauch an Tagen mit viel und
  /// wenig Stress). Nur ein Vergleich eigener Tage, keine Kausalaussage.
  static List<BodyBatteryRelation> relations(List<BodyBatteryDay> history, {double sleepTarget = 7}) {
    final result = <BodyBatteryRelation>[];
    final sleepDays = history.where((day) => day.charged != null && day.sleepHours != null).toList();
    final long = [
      for (final day in sleepDays)
        if ((day.sleepHours ?? 0) >= sleepTarget) ?day.charged,
    ];
    final short = [
      for (final day in sleepDays)
        if ((day.sleepHours ?? 0) < sleepTarget) ?day.charged,
    ];
    if (long.length >= minimumGroup && short.length >= minimumGroup) {
      final (a, b) = (_average(long), _average(short));
      final hours = GermanFormat.decimal(sleepTarget);
      result.add(
        BodyBatteryRelation(
          id: 'sleep',
          text: (a - b).abs() < 5
              ? 'Nach Nächten ab $hours h lädt sie kaum mehr auf als nach kürzeren (+${a.toInt()} zu +${b.toInt()}).'
              : 'Nach Nächten ab $hours h Schlaf lädt sie im Schnitt um ${a.toInt()} auf, nach kürzeren um ${b.toInt()}.',
        ),
      );
    }
    final stressDays = history.where((day) => day.drained != null && day.stress != null).toList();
    if (stressDays.length >= minimumGroup * 2) {
      final levels = stressDays.map((day) => day.stress!).toList()..sort();
      final median = levels[levels.length ~/ 2];
      final high = [
        for (final day in stressDays)
          if ((day.stress ?? 0) >= median) ?day.drained,
      ];
      final low = [
        for (final day in stressDays)
          if ((day.stress ?? 0) < median) ?day.drained,
      ];
      if (high.length >= minimumGroup && low.length >= minimumGroup) {
        final (a, b) = (_average(high), _average(low));
        result.add(
          BodyBatteryRelation(
            id: 'stress',
            text: (a - b).abs() < 5
                ? 'Stress und Verbrauch hängen bei dir kaum zusammen (−${a.toInt()} zu −${b.toInt()}).'
                : 'An Tagen mit mehr Stress (Ø ab ${median.toInt()}) verbraucht sie im Schnitt ${a.toInt()}, '
                      'an ruhigeren ${b.toInt()}.',
          ),
        );
      }
    }
    return result;
  }

  static double _average(List<double> values) =>
      (values.fold(0.0, (sum, value) => sum + value) / values.length).roundToDouble();

  /// Einordnung eines Stands (Garmin: 0–25 niedrig, 26–50 mittel, 51–75 hoch, 76–100 sehr hoch).
  static String band(double value) {
    if (value < 26) return 'niedrig';
    if (value < 51) return 'mittel';
    if (value < 76) return 'hoch';
    return 'sehr hoch';
  }
}

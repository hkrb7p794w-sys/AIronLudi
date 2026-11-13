import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../profile/goal_rules.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';

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

/// Trendlinie der Wägungen.
final class WeightTrendResult {
  const WeightTrendResult({
    required this.trendKilograms,
    required this.weeklyPercent,
    required this.entries,
    required this.spanDays,
  });

  /// Gewicht laut Trendlinie heute.
  final double trendKilograms;

  /// Änderung pro Woche in % des Körpergewichts (negativ = Abnahme).
  final double weeklyPercent;
  final int entries;
  final int spanDays;

  @override
  bool operator ==(Object other) =>
      other is WeightTrendResult &&
      other.trendKilograms == trendKilograms &&
      other.weeklyPercent == weeklyPercent &&
      other.entries == entries &&
      other.spanDays == spanDays;

  @override
  int get hashCode => Object.hash(trendKilograms, weeklyPercent, entries, spanDays);

  @override
  String toString() => 'WeightTrendResult($trendKilograms kg, $weeklyPercent %/Woche, $entries, $spanDays)';
}

enum WeightAdviceKind implements RawEnum {
  onTrack,
  eatMore,
  eatLess,
  tooFast;

  @override
  String get rawValue => name;
}

/// Vorschlag aus dem Vergleich von Verlauf und Plan.
final class WeightTrendAdvice {
  const WeightTrendAdvice({
    required this.kind,
    required this.message,
    required this.kilocalories,
    required this.evidenceIDs,
  });

  final WeightAdviceKind kind;
  final String message;

  /// Vorgeschlagene Änderung der Tagesenergie in kcal (0 = nichts ändern).
  final double kilocalories;
  final List<String> evidenceIDs;

  @override
  String toString() => 'WeightTrendAdvice(${kind.rawValue}, $kilocalories kcal, $message)';
}

/// Gewichtsverlauf: Zusammenführen der Quellen, Trendlinie, Abgleich mit dem Plan und Nachsteuerung.
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

  /// Lineare Regression über die letzten 28 Tage; `null`, wenn zu wenige Wägungen vorliegen.
  static WeightTrendResult? trend(Iterable<WeightEntry> entries, {required CalendarDay today}) {
    final start = today.adding(-(windowDays - 1));
    final recent = merged(entries).where((entry) => entry.day >= start && entry.day <= today).toList();
    if (recent.length < minimumEntries) return null;
    final first = recent.first;
    final last = recent.last;
    final span = first.day.daysUntil(last.day);
    if (span < minimumSpanDays) return null;
    final xs = [for (final entry in recent) first.day.daysUntil(entry.day).toDouble()];
    final ys = [for (final entry in recent) entry.kilograms];
    final meanX = xs.fold(0.0, (sum, x) => sum + x) / xs.length;
    final meanY = ys.fold(0.0, (sum, y) => sum + y) / ys.length;
    var covariance = 0.0;
    var variance = 0.0;
    for (var index = 0; index < xs.length; index++) {
      covariance += (xs[index] - meanX) * (ys[index] - meanY);
      variance += (xs[index] - meanX) * (xs[index] - meanX);
    }
    if (variance <= 0) return null;
    final slope = covariance / variance;
    final todayX = first.day.daysUntil(today).toDouble();
    final trend = meanY + slope * (todayX - meanX);
    return WeightTrendResult(
      trendKilograms: (trend * 10).roundToDouble() / 10,
      weeklyPercent: (slope * 7 / trend * 100 * 100).roundToDouble() / 100,
      entries: recent.length,
      spanDays: span,
    );
  }

  /// Vergleich des Verlaufs mit dem geplanten Tempo. [plannedPercent] negativ = abnehmen, `null` = Gewicht halten.
  /// [safety]: Schutzstufe aus `GoalRules.weightGuard`; ohne Ziele kein Vorschlag, bei `noDeficit` nie weniger essen.
  static WeightTrendAdvice advice({
    required WeightTrendResult result,
    required double? plannedPercent,
    required double currentAdjustment,
    WeightGoalGuard safety = WeightGoalGuard.free,
  }) {
    if (safety == WeightGoalGuard.noTargets) {
      return const WeightTrendAdvice(
        kind: WeightAdviceKind.onTrack,
        message: 'Die App macht dir hier keine Vorschläge zu Kalorien oder Gewicht.',
        kilocalories: 0,
        evidenceIDs: ['nutrition.reds'],
      );
    }
    final planned = plannedPercent ?? 0;
    final difference = result.weeklyPercent - planned;
    final actual = GermanFormat.number(result.weeklyPercent.abs());
    final direction = result.weeklyPercent < 0 ? 'ab' : 'zu';
    const evidence = ['weightloss.rate', 'weight.trend'];
    // Schutz: schneller als 1 % pro Woche abnehmen ist nie gewollt.
    if (result.weeklyPercent < -GoalRules.maxLossPercentPerWeek) {
      final kcal = step(-difference, weight: result.trendKilograms, current: currentAdjustment, minimum: 100);
      return WeightTrendAdvice(
        kind: WeightAdviceKind.tooFast,
        message:
            'Du nimmst gerade etwa $actual % pro Woche ab – schneller als die Obergrenze von 1 %. Iss täglich '
            'etwa ${kcal.truncate()} kcal mehr, damit du Muskeln behältst.',
        kilocalories: kcal,
        evidenceIDs: evidence,
      );
    }
    if (difference.abs() <= tolerancePercent) {
      return WeightTrendAdvice(
        kind: WeightAdviceKind.onTrack,
        message: 'Dein Gewicht entwickelt sich wie geplant (etwa $actual % pro Woche $direction). Weiter so.',
        kilocalories: 0,
        evidenceIDs: evidence,
      );
    }
    final kcal = step(-difference, weight: result.trendKilograms, current: currentAdjustment, minimum: 50);
    if (safety == WeightGoalGuard.noDeficit && kcal < 0) {
      return WeightTrendAdvice(
        kind: WeightAdviceKind.onTrack,
        message:
            'Dein Gewicht ändert sich um etwa $actual % pro Woche $direction. Die App schlägt dir kein Defizit vor.',
        kilocalories: 0,
        evidenceIDs: const ['nutrition.reds'],
      );
    }
    if (kcal == 0) {
      return const WeightTrendAdvice(
        kind: WeightAdviceKind.onTrack,
        message:
            'Der Verlauf weicht etwas vom Plan ab, die Anpassung ist aber schon ausgeschöpft. Prüfe, ob alle '
            'Mahlzeiten erfasst sind.',
        kilocalories: 0,
        evidenceIDs: evidence,
      );
    }
    final planText = plannedPercent == null
        ? 'geplant: halten'
        : 'geplant ${GermanFormat.number(plannedPercent.abs())} % ${plannedPercent < 0 ? 'ab' : 'zu'}';
    return WeightTrendAdvice(
      kind: kcal > 0 ? WeightAdviceKind.eatMore : WeightAdviceKind.eatLess,
      message:
          'Dein Gewicht ändert sich um etwa $actual % pro Woche $direction ($planText). Vorschlag: täglich '
          '${kcal > 0 ? '${kcal.truncate()} kcal mehr' : '${(-kcal).truncate()} kcal weniger'}. In zwei Wochen prüft '
          'die App erneut.',
      kilocalories: kcal,
      evidenceIDs: evidence,
    );
  }

  /// kcal pro Tag aus der Abweichung in % pro Woche (7.700 kcal je kg als Näherung), begrenzt und auf 50 gerundet.
  static double step(
    double percentPerWeek, {
    required double weight,
    required double current,
    required double minimum,
  }) {
    final raw = percentPerWeek / 100 * weight * 7700 / 7;
    var value = math.min(math.max(raw, -maxStepKilocalories), maxStepKilocalories);
    if (value.abs() < minimum) value = value < 0 ? -minimum : minimum;
    final total = math.min(math.max(current + value, -maxTotalKilocalories), maxTotalKilocalories);
    return ((total - current) / 50).roundToDouble() * 50;
  }

  /// Wägungen aus Garmin Connect (`/weight-service/weight/range`, Gewicht in Gramm), tolerant gelesen.
  static List<WeightEntry> garminEntries(JsonValue json) {
    final result = <WeightEntry>[];
    void walk(JsonValue value) {
      if (value.objectValue case final object?) {
        final dateText =
            object['calendarDate']?.stringValue ?? object['summaryDate']?.stringValue ?? object['date']?.stringValue;
        final grams = object['weight']?.doubleValue;
        final day = dateText == null ? null : CalendarDay.tryParse(dateText);
        if (grams != null && day != null) {
          final kilograms = grams > 500 ? grams / 1000 : grams;
          result.add(
            WeightEntry(day: day, kilograms: (kilograms * 10).roundToDouble() / 10, source: WeightSource.garmin),
          );
        }
        object.values.forEach(walk);
      } else if (value.arrayValue case final items?) {
        items.forEach(walk);
      }
    }

    walk(json);
    return merged(result);
  }
}

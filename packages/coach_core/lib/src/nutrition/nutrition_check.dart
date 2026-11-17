import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../profile/goal_rules.dart';
import '../profile/plan_adjustments.dart';
import '../util/german_format.dart';
import 'weight_trend.dart';

/// Wöchentlicher Ernährungs-Check-in (Anregung: MacroFactor, Paket 13): Einmal pro Kalenderwoche erinnert die App
/// daran, Gewichtstrend und gemessenen Verbrauch anzusehen und die Tagesziele bei Bedarf anzupassen. Die Anpassung
/// selbst bleibt eine Entscheidung der Person (`Expenditure.adjustment`, `WeightTrend`); die App ändert nichts
/// von allein.
abstract final class NutritionCheckIn {
  /// Daten der letzten Tage, ohne die der Check-in nichts zeigen könnte.
  static const dataWindowDays = 14;

  /// Fällig, wenn in dieser Woche (ab Montag) noch kein Check-in war, Gewichtsziele erlaubt sind und es in den
  /// letzten zwei Wochen Wägungen oder Mahlzeiten gibt.
  static bool isDue({
    required CalendarDay today,
    required CalendarDay? last,
    required bool withheld,
    required List<CalendarDay> weighIns,
    required List<CalendarDay> mealDays,
  }) {
    if (withheld) return false;
    final monday = PlanAdjustments.monday(today);
    if (last != null && last >= monday) return false;
    final start = today.adding(-dataWindowDays);
    bool recent(CalendarDay day) => day >= start && day <= today;
    return weighIns.any(recent) || mealDays.any(recent);
  }
}

/// Ergebnis der Verbrauchsschätzung.
final class ExpenditureResult {
  const ExpenditureResult({
    required this.kilocalories,
    required this.averageIntake,
    required this.loggedDays,
    required this.excludedDays,
    required this.kilogramsPerWeek,
    required this.plausible,
  });

  /// Geschätzter Verbrauch in kcal pro Tag (auf 10 gerundet).
  final double kilocalories;
  final double averageIntake;
  final int loggedDays;
  final int excludedDays;

  /// Gewichtsänderung laut Trend in kg pro Woche.
  final double kilogramsPerWeek;

  /// `false`, wenn das Ergebnis außerhalb von 1,1–3,5 × Grundumsatz liegt (meist Lücken beim Erfassen).
  final bool plausible;

  @override
  bool operator ==(Object other) =>
      other is ExpenditureResult &&
      other.kilocalories == kilocalories &&
      other.averageIntake == averageIntake &&
      other.loggedDays == loggedDays &&
      other.excludedDays == excludedDays &&
      other.kilogramsPerWeek == kilogramsPerWeek &&
      other.plausible == plausible;

  @override
  int get hashCode => Object.hash(kilocalories, averageIntake, loggedDays, excludedDays, kilogramsPerWeek, plausible);

  @override
  String toString() => 'ExpenditureResult($kilocalories kcal, $loggedDays Tage, plausibel: $plausible)';
}

/// Tatsächlicher Energieverbrauch aus erfasster Ernährung und Gewichtsverlauf (Intake-Balance-Methode):
/// Verbrauch = mittlere Zufuhr − Änderung der Körperreserven. Mit Gewichtsdaten lag die Methode nah an der
/// tatsächlichen Zufuhr (Gilmore et al. 2014; Sanghvi et al. 2015). Sie ist nur so gut wie die Erfassung:
/// Selbstauskünfte unterschätzen die Zufuhr oft deutlich (Lichtman et al. 1992). Tage mit offensichtlich
/// unvollständiger Erfassung zählen deshalb nicht, und unplausible Ergebnisse werden nicht verwendet.
abstract final class Expenditure {
  static const windowDays = 28;
  static const minimumLoggedDays = 14;

  /// Tage unter diesem Anteil des Medians gelten als unvollständig erfasst.
  static const incompleteShare = 0.5;

  /// Ab dieser Abweichung von der Formel schlägt die App eine Anpassung vor (kcal pro Tag).
  static const minimumDifference = 150.0;

  /// [intake]: erfasste kcal je Tag (Tage ohne Eintrag fehlen). Der heutige Tag zählt nicht, er ist noch offen.
  static ExpenditureResult? estimate({
    required Map<CalendarDay, double> intake,
    required List<WeightEntry> weights,
    required CalendarDay today,
    required double basalMetabolicRate,
  }) {
    final start = today.adding(-windowDays);
    final days = [
      for (final MapEntry(key: day, :value) in intake.entries)
        if (day >= start && day < today && value > 0) value,
    ];
    if (days.isEmpty) return null;
    final sorted = [...days]..sort();
    final median = sorted[sorted.length ~/ 2];
    final included = days.where((value) => value >= incompleteShare * median).toList();
    if (included.length < minimumLoggedDays) return null;
    final trend = WeightTrend.trend(weights, today: today.adding(-1));
    if (trend == null) return null;
    final average = included.fold(0.0, (sum, value) => sum + value) / included.length;
    final perWeek = trend.weeklyPercent / 100 * trend.trendKilograms;
    final kilocalories = average - perWeek / 7 * 7700;
    final plausible = kilocalories >= 1.1 * basalMetabolicRate && kilocalories <= 3.5 * basalMetabolicRate;
    return ExpenditureResult(
      kilocalories: (kilocalories / 10).roundToDouble() * 10,
      averageIntake: average.roundToDouble(),
      loggedDays: included.length,
      excludedDays: days.length - included.length,
      kilogramsPerWeek: (perWeek * 100).roundToDouble() / 100,
      plausible: plausible,
    );
  }

  /// Vorschlag für die gesamte Anpassung der Tagesenergie: Unterschied zwischen gemessenem Verbrauch und dem
  /// Bedarf laut Formel ([formulaMaintenance], ohne Ziel und Anpassung), auf 50 gerundet und auf ±500 begrenzt.
  /// `null`, wenn das Ergebnis unplausibel ist oder sich kaum etwas ändern würde.
  /// [safety]: ohne Ziele kein Vorschlag, bei `noDeficit` keine Senkung.
  static double? adjustment(
    ExpenditureResult result, {
    required double formulaMaintenance,
    required double current,
    WeightGoalGuard safety = WeightGoalGuard.free,
  }) {
    if (!result.plausible || safety == WeightGoalGuard.noTargets) return null;
    final difference = result.kilocalories - formulaMaintenance;
    if (difference.abs() < minimumDifference) return current == 0 ? null : 0;
    const limit = WeightTrend.maxTotalKilocalories;
    final proposal = (math.min(math.max(difference, -limit), limit) / 50).roundToDouble() * 50;
    if (safety == WeightGoalGuard.noDeficit && proposal < 0) return null;
    return (proposal - current).abs() >= 100 ? proposal : null;
  }
}

/// Ein Punkt der Gewichtsprognose.
final class ForecastPoint {
  const ForecastPoint({required this.weeks, required this.day, required this.kilograms});

  final int weeks;
  final CalendarDay day;
  final double kilograms;

  int get id => weeks;

  @override
  bool operator ==(Object other) =>
      other is ForecastPoint && other.weeks == weeks && other.day == day && other.kilograms == kilograms;

  @override
  int get hashCode => Object.hash(weeks, day, kilograms);

  @override
  String toString() => 'ForecastPoint($weeks Wochen, $kilograms kg)';
}

/// Ergebnis der Gewichtsprognose.
final class WeightForecastResult {
  const WeightForecastResult({
    required this.weeklyPercent,
    required this.weeklyKilograms,
    required this.dailyDeficit,
    required this.deficitCapped,
    required this.points,
    required this.target,
    required this.weeksToTarget,
    required this.targetDay,
    required this.floorKilograms,
  });

  /// Geplantes Tempo in % pro Woche (positiv = Abnahme).
  final double weeklyPercent;
  final double weeklyKilograms;

  /// Geschätztes Defizit pro Tag in kcal.
  final double dailyDeficit;

  /// Defizit wurde auf 25 % des Bedarfs begrenzt.
  final bool deficitCapped;
  final List<ForecastPoint> points;
  final double? target;
  final int? weeksToTarget;
  final CalendarDay? targetDay;

  /// Untergrenze (BMI 18,5).
  final double floorKilograms;
}

/// Prognose beim Abnehmen: erwartetes Gewicht nach 4, 8 und 12 Wochen und bis zum Zielgewicht, mit dem dafür
/// geschätzten Kaloriendefizit. Gesund und nachhaltig heißt: das Tempo aus `GoalRules` (Standard 0,5 %, höchstens
/// 1 % des Körpergewichts pro Woche), ein Defizit von höchstens 25 % des Bedarfs (wie in `NutritionPlanner`) und
/// nie unter BMI 18,5. 7.700 kcal je kg sind eine Näherung; der Körper passt sich an (Hall et al. 2011), deshalb
/// steuert die App anhand der Waage nach.
abstract final class WeightForecast {
  static const kilocaloriesPerKilogram = 7700.0;
  static const maximumDeficitShare = 0.25;
  static const horizons = [4, 8, 12];

  /// [weeklyChangePercent]: geplante Änderung pro Woche (negativ = abnehmen), z. B. `-0.5`.
  /// [maintenanceKilocalories]: geschätzter Tagesbedarf ohne Ziel, für die 25-%-Grenze.
  static WeightForecastResult? compute({
    required double currentKilograms,
    required double weeklyChangePercent,
    required double heightCentimeters,
    required double? maintenanceKilocalories,
    required double? target,
    required CalendarDay today,
  }) {
    if (currentKilograms <= 0 || weeklyChangePercent >= 0) return null;
    final meters = heightCentimeters / 100;
    final floor = meters > 0 ? (GoalRules.minimumBMI * meters * meters * 10).ceilToDouble() / 10 : 0.0;
    var percent = math.min(-weeklyChangePercent, GoalRules.maxLossPercentPerWeek);
    var deficit = percent / 100 * currentKilograms * kilocaloriesPerKilogram / 7;
    var capped = false;
    final maintenance = maintenanceKilocalories;
    if (maintenance != null && maintenance > 0 && deficit > maintenance * maximumDeficitShare) {
      deficit = maintenance * maximumDeficitShare;
      percent = deficit * 7 / kilocaloriesPerKilogram / currentKilograms * 100;
      capped = true;
    }
    final goal = target == null ? null : math.max(target, floor);
    double weight(int weeks) {
      // Tempo in % des jeweils aktuellen Gewichts: wer leichter wird, verliert pro Woche etwas weniger.
      final projected = currentKilograms * math.pow(1 - percent / 100, weeks);
      return math.max(math.max(projected, goal ?? floor), floor);
    }

    final points = [
      for (final weeks in horizons)
        ForecastPoint(weeks: weeks, day: today.adding(weeks * 7), kilograms: (weight(weeks) * 10).roundToDouble() / 10),
    ];
    int? weeksToTarget;
    if (goal != null && goal < currentKilograms && percent > 0) {
      weeksToTarget = (math.log(goal / currentKilograms) / math.log(1 - percent / 100)).ceil();
    }
    return WeightForecastResult(
      weeklyPercent: (percent * 100).roundToDouble() / 100,
      weeklyKilograms: (currentKilograms * percent / 100 * 100).roundToDouble() / 100,
      dailyDeficit: (deficit / 10).roundToDouble() * 10,
      deficitCapped: capped,
      points: points,
      target: goal,
      weeksToTarget: weeksToTarget,
      targetDay: weeksToTarget == null ? null : today.adding(weeksToTarget * 7),
      floorKilograms: floor,
    );
  }
}

/// Ergebnis der Hochrechnung „Wenn du weiter so isst“.
final class IntakeForecastResult {
  const IntakeForecastResult({
    required this.days,
    required this.averageIntake,
    required this.maintenance,
    required this.weeklyKilograms,
    required this.rawWeeklyKilograms,
    required this.capped,
    required this.horizonDays,
  });

  /// Erfasste Tage, die eingeflossen sind.
  final int days;

  /// Geglätteter Schnitt der Zufuhr (kcal pro Tag).
  final double averageIntake;

  /// Bedarf, gegen den gerechnet wurde (kcal pro Tag).
  final double maintenance;

  /// Erwartete Änderung pro Woche in kg (negativ = Abnahme), physiologisch begrenzt.
  final double weeklyKilograms;

  /// Rechnerischer Wert ohne Begrenzung (für den Hinweis).
  final double rawWeeklyKilograms;

  /// Begrenzt, weil das rechnerische Tempo nicht als Körpergewebe erreichbar bzw. nicht nachhaltig wäre.
  final bool capped;
  final int horizonDays;

  double get dailyBalance => averageIntake - maintenance;

  /// Erwartete Änderung bis zum Ende des Zeitraums (kg).
  double get horizonKilograms => (weeklyKilograms * horizonDays / 7 * 10).roundToDouble() / 10;
}

/// Hochrechnung aus dem tatsächlich Gegessenen – realistisch statt linear: Schnitt der letzten 14 erfassten Tage, einzelne
/// Ausreißer auf ±40 % des Medians begrenzt (ein Festessen oder ein vergessener Eintrag kippt die Prognose nicht),
/// 7.700 kcal je kg Körpergewebe, und höchstens so viel Veränderung, wie als Fett- bzw. Muskelgewebe erreichbar ist:
/// Abnahme bis 1 %, Zunahme bis 0,5 % des Körpergewichts pro Woche (`GoalRules`). Der Körper passt sich an (Hall et al.
/// 2011), die Waage zeigt anfangs vor allem Wasser und Glykogen – deshalb keine Hochrechnung über mehr als 4 Wochen.
abstract final class IntakeForecast {
  static const windowDays = 14;
  static const minimumDays = 4;
  static const outlierShare = 0.4;
  static const horizonDays = 28;

  /// [intake]: erfasste kcal je Tag; heute zählt nicht (noch offen). Unvollständige Tage (unter der Hälfte des Medians)
  /// fallen weg.
  static IntakeForecastResult? compute({
    required Map<CalendarDay, double> intake,
    required double maintenance,
    required double weightKilograms,
    required CalendarDay today,
  }) {
    if (maintenance <= 0 || weightKilograms <= 0) return null;
    final start = today.adding(-windowDays);
    final values = [
      for (final MapEntry(key: day, :value) in intake.entries)
        if (day >= start && day < today && value > 0) value,
    ];
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final median = sorted[sorted.length ~/ 2];
    final complete = values.where((value) => value >= Expenditure.incompleteShare * median).toList();
    if (complete.length < minimumDays) return null;
    final low = median * (1 - outlierShare);
    final high = median * (1 + outlierShare);
    final average = complete.fold(0.0, (sum, value) => sum + value.clamp(low, high)) / complete.length;
    final raw = (average - maintenance) * 7 / WeightForecast.kilocaloriesPerKilogram;
    final maxLoss = GoalRules.maxLossPercentPerWeek / 100 * weightKilograms;
    final maxGain = GoalRules.maxGainPercentPerWeek / 100 * weightKilograms;
    final bounded = raw.clamp(-maxLoss, maxGain);
    return IntakeForecastResult(
      days: complete.length,
      averageIntake: average.roundToDouble(),
      maintenance: maintenance.roundToDouble(),
      weeklyKilograms: (bounded * 100).roundToDouble() / 100,
      rawWeeklyKilograms: (raw * 100).roundToDouble() / 100,
      capped: bounded != raw,
      horizonDays: horizonDays,
    );
  }

  /// Kurzer Satz für Ansicht und KI.
  static String sentence(IntakeForecastResult result) {
    final kg = result.horizonKilograms;
    final amount = GermanFormat.decimal(kg.abs());
    final change = kg.abs() < 0.2
        ? 'bleibt dein Gewicht in 4 Wochen etwa gleich'
        : kg < 0
        ? 'sind in 4 Wochen etwa $amount kg weniger realistisch'
        : 'sind in 4 Wochen etwa $amount kg mehr realistisch';
    return 'Wenn du weiter so isst wie in den letzten ${result.days} erfassten Tagen, $change.';
  }
}

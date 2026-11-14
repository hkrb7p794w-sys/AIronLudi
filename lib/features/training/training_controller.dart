import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Kachel mit Titel und Wert.
final class TrainingTile {
  const TrainingTile(this.title, this.value);

  final String title;
  final String value;

  @override
  bool operator ==(Object other) => other is TrainingTile && other.title == title && other.value == value;

  @override
  int get hashCode => Object.hash(title, value);

  @override
  String toString() => 'TrainingTile($title, $value)';
}

/// Verlauf einer Kennzahl über 28 Tage.
final class TrendCard {
  const TrendCard({
    required this.title,
    required this.unit,
    required this.digits,
    required this.higherIsBetter,
    required this.trend,
  });

  final String title;
  final String unit;
  final int digits;

  /// Höher ist besser (für die Farbe der Veränderung); `null` = neutral.
  final bool? higherIsBetter;
  final MetricTrend trend;
}

/// Verläufe und Kennzahlen wie im Home-Assistant-Dashboard (Erholung, Laufen/Rad/Schwimmen, Herzfrequenz).
/// Gerechnet wird in `coach_core`; hier wird nur zusammengestellt (Port von `TrainingViewModel`).
final class TrainingController extends ChangeNotifier {
  CalendarDay today = CalendarDay.today();
  List<TrendCard> recovery = const [];
  List<TrainingTile> tiles = const [];
  DailyMetrics? sleepStages;
  List<WeekVolume> weeks = const [];
  MetricTrend? vo2Run;
  MetricTrend? vo2Bike;
  HeartRateZoneReport? zones;

  /// FIT-Auswertungen (aerobe Kopplung, Runden für den Pace-Check).
  List<ActivityAnalysis> analyses = const [];
  double? restingHeartRate;

  void update({
    required List<DailyMetrics> days,
    required List<GarminActivity> activities,
    required GarminProfile? profile,
    required JsonValue? watchZones,
    required HeartRateOverrides overrides,
    List<ActivityAnalysis> analyses = const [],
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(now ?? DateTime.now());
    this.today = today;
    final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
    TrendCard card(
      String title,
      String unit,
      double? Function(DailyMetrics metrics) field, {
      int digits = 0,
      required bool? higherIsBetter,
    }) => TrendCard(
      title: title,
      unit: unit,
      digits: digits,
      higherIsBetter: higherIsBetter,
      trend: MetricTrend(MetricTrend.values(sorted, field), days: 28, today: today),
    );
    recovery = [
      card('HRV · 7-Tage-Schnitt', 'ms', (metrics) => metrics.hrvWeeklyAverage, higherIsBetter: null),
      card('Ruhepuls', 'bpm', (metrics) => metrics.restingHeartRate, higherIsBetter: false),
      card('Schlaf', 'h', (metrics) => metrics.sleepHours, digits: 1, higherIsBetter: null),
      card('Body Battery (Höchstwert)', '', (metrics) => metrics.bodyBatteryHigh, higherIsBetter: true),
    ].where((card) => card.trend.points.isNotEmpty).toList();

    DailyMetrics? lastWhere(bool Function(DailyMetrics metrics) test) => sorted.lastWhere(test, orElse: () => _none);
    DailyMetrics? found(DailyMetrics? value) => identical(value, _none) ? null : value;
    final latest =
        found(lastWhere((metrics) => metrics.day == today)) ??
        found(lastWhere((metrics) => metrics.day == today.adding(-1)));
    sleepStages = found(lastWhere((metrics) => metrics.deepSleepSeconds != null && metrics.day >= today.adding(-1)));
    final runVO2 = VO2MaxHistory.values(activities, sport: ActivitySport.run);
    final bikeVO2 = VO2MaxHistory.values(activities, sport: ActivitySport.bike);
    vo2Run = runVO2.isEmpty ? null : MetricTrend(runVO2, days: 180, today: today);
    vo2Bike = bikeVO2.isEmpty ? null : MetricTrend(bikeVO2, days: 180, today: today);
    final vo2 =
        profile?.vo2MaxRunning ??
        runVO2.lastOrNull?.value ??
        found(lastWhere((metrics) => metrics.vo2Max != null))?.vo2Max;
    tiles = tilesFor(latest: latest, vo2Max: vo2, vo2MaxBike: profile?.vo2MaxCycling ?? bikeVO2.lastOrNull?.value);

    this.analyses = analyses;
    restingHeartRate = found(lastWhere((metrics) => metrics.restingHeartRate != null))?.restingHeartRate;
    weeks = WeekVolume.history(activities, today: today, weeks: 12);
    zones = HeartRateZoneCalculator.report(
      activities: activities,
      watchZonesJSON: watchZones,
      profile: profile,
      overrides: overrides,
      today: today,
    );
    notifyListeners();
  }

  static final _none = DailyMetrics(const CalendarDay(1, 1, 1));

  /// Pace-Check mit der eingestellten Schwellenpace; ohne Ruhepuls wie im Altbestand 50 bpm.
  PaceResult paceCheck({required int thresholdPace}) => PaceCheck.evaluate(
    ActivityAnalysisPlanner.paceSessions(analyses, today: today),
    thresholdPace: thresholdPace,
    lthr: zones?.run.lactateThreshold?.toDouble(),
    maxHeartRate: zones?.maxHeartRate?.toDouble(),
    restingHeartRate: restingHeartRate ?? 50,
  );

  List<ActivityAnalysis> decoupled(DecouplingSport sport) => ActivityAnalysisPlanner.decoupled(analyses, sport: sport);

  List<ActivityAnalysis> get skippedDecoupling => ActivityAnalysisPlanner.skipped(analyses);

  /// Garmins Readiness-Stufen auf Deutsch.
  static const readinessLevelGerman = {
    'PRIME': 'Top',
    'HIGH': 'Hoch',
    'MODERATE': 'Mittel',
    'LOW': 'Niedrig',
    'POOR': 'Schlecht',
  };

  static List<TrainingTile> tilesFor({
    required DailyMetrics? latest,
    required double? vo2Max,
    required double? vo2MaxBike,
  }) {
    String? text(double? value, [String unit = '', int digits = 0]) {
      if (value == null) return null;
      // Wie `.number.precision(.fractionLength(digits))` in Swift: feste Nachkommastellen, deutsche Gruppierung.
      final number = NumberFormat.decimalPatternDigits(locale: 'de_DE', decimalDigits: digits).format(value);
      return unit.isEmpty ? number : '$number $unit';
    }

    final metrics = latest;
    final battery = switch (metrics?.bodyBatteryHigh) {
      final high? =>
        '${high.toInt()}${metrics?.bodyBatteryLow == null ? '' : ' / ${metrics!.bodyBatteryLow!.toInt()}'}',
      null => null,
    };
    final flow = metrics?.bodyBatteryCharged != null && metrics?.bodyBatteryDrained != null
        ? '+${metrics!.bodyBatteryCharged!.toInt()} / −${metrics.bodyBatteryDrained!.toInt()}'
        : null;
    final readiness = switch (metrics?.trainingReadiness) {
      final score? =>
        '${score.toInt()}${metrics?.trainingReadinessLevel == null ? '' : ' · ${readinessLevelGerman[metrics!.trainingReadinessLevel!.toUpperCase()] ?? metrics.trainingReadinessLevel}'}',
      null => null,
    };
    final heart = metrics?.minHeartRate != null && metrics?.maxHeartRate != null
        ? '${metrics!.minHeartRate!.toInt()} / ${metrics.maxHeartRate!.toInt()} bpm'
        : null;
    final load = switch (metrics?.acuteLoad) {
      final acute? => '${acute.toInt()} / ${metrics?.chronicLoad == null ? '–' : '${metrics!.chronicLoad!.toInt()}'}',
      null => null,
    };
    final candidates = <(String, String?)>[
      ('Training Readiness', readiness),
      (
        'Trainingsstatus',
        metrics?.trainingStatus == null ? null : GarminConnectMetrics.trainingStatusGerman(metrics!.trainingStatus!),
      ),
      ('Endurance Score', text(metrics?.enduranceScore)),
      ('Body Battery (hoch / tief)', battery),
      ('Geladen / verbraucht', flow),
      ('Schlaf-Score', text(metrics?.sleepScore)),
      ('HRV letzte Nacht', text(metrics?.hrvLastNightAverage, 'ms')),
      (
        'HRV-Status',
        metrics?.hrvStatus == null ? null : RecoveryEvaluator.hrvStatusGerman[metrics!.hrvStatus!] ?? metrics.hrvStatus,
      ),
      ('Stress (Ø)', text(metrics?.stressAverage)),
      ('Atemfrequenz', text(metrics?.respirationWaking ?? metrics?.respirationSleep, '/min', 1)),
      ('SpO2', text(metrics?.spo2Average, '%')),
      ('VO2max Laufen', text(vo2Max, '', 1)),
      ('VO2max Rad', text(vo2MaxBike, '', 1)),
      ('Fitnessalter', text(metrics?.fitnessAge, 'J.', 1)),
      ('Schritte', text(metrics?.steps)),
      ('Ruhekalorien', text(metrics?.restingKilocalories, 'kcal')),
      ('Puls tief / hoch', heart),
      ('Regenerationszeit', text(metrics?.recoveryHours, 'h')),
      ('Belastung akut / chronisch', load),
    ];
    return [
      for (final (title, value) in candidates)
        if (value != null) TrainingTile(title, value),
    ];
  }
}

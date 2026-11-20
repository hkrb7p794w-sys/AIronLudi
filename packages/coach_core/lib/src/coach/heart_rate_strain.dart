import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import 'heart_rate_zones.dart';

/// Woher der Strain des Tages stammt.
enum StrainSource {
  /// Vom Anbieter selbst berechnet (WHOOP-Zyklus).
  whoop('WHOOP'),

  /// Aus dem Pulsverlauf über den ganzen Tag berechnet (Garmin, Apple Health / Health Connect).
  heartRate('Puls ganztags'),

  /// Ohne Pulsverlauf: aus den Trainings geschätzt (Belastungspunkte).
  workouts('aus Trainings');

  const StrainSource(this.label);

  final String label;
}

/// Ergebnis der Berechnung aus dem Pulsverlauf.
final class HeartRateStrainResult {
  const HeartRateStrainResult({
    required this.strain,
    required this.load,
    required this.zoneMinutes,
    required this.restingHeartRate,
    required this.maxHeartRate,
  });

  /// 0–21 wie bei WHOOP.
  final double strain;

  /// Gewichtete Minuten (Herz-Kreislauf-Belastung).
  final double load;

  /// Minuten je Bereich: 0 = unter 50 % (davon zählt nur Bewegung ab 30 %), 1–5 = Zonen 50–60 … 90–100 %
  /// der Herzfrequenzreserve.
  final List<double> zoneMinutes;
  final double restingHeartRate;
  final double maxHeartRate;
}

/// Strain wie bei WHOOP: Herz-Kreislauf-Belastung über den **ganzen Tag**, nicht nur im Training. Jede Minute zählt
/// nach ihrem Anteil an der Herzfrequenzreserve (HRR = (Puls − Ruhepuls) / (HFmax − Ruhepuls)), gewichtet nach den
/// Zonen, die auch WHOOP nutzt (50–60 … 90–100 % HRR; Gewicht 1 … 5, Edwards). Alltagsbewegung (30–50 % HRR) zählt
/// mit 0,1, Ruhe darunter gar nicht. Die Summe wird auf die Skala 0–21 gebracht: Sie wächst anfangs schnell und wird
/// nach oben immer schwerer zu steigern – wie bei WHOOP (21 = „All out“).
///
/// WHOOP veröffentlicht seine Formel nicht; Gewichte und Skala sind an WHOOPs Einordnung angelehnt (leicht 0–9,
/// mittel 10–13, hoch 14–17, all out 18–21). Bei Ruhepuls 55 und HFmax 190: ruhiger Tag mit 3 h Alltagsbewegung ≈ 4,
/// dazu 1 h lockerer Lauf ≈ 13, 1 h zügig ≈ 15, 1 h Intervalle ≈ 17, Marathon ≈ 21. Die Werte von WHOOP selbst haben
/// Vorrang (`StrainSource.whoop`).
abstract final class HeartRateStrain {
  static const maximum = 21.0;

  /// Gewichtete Minuten, bei denen der Strain 1 − 1/e ≈ 63 % von 21 erreicht.
  static const scale = 170.0;

  /// Zonen-Untergrenzen in % HRR und ihr Gewicht je Minute.
  static const zones = [(0.5, 1.0), (0.6, 2.0), (0.7, 3.0), (0.8, 4.0), (0.9, 5.0)];

  /// Alltagsbewegung (30–50 % HRR): kleines Gewicht.
  static const activityFloor = 0.3;
  static const activityWeight = 0.1;

  /// Längste Lücke, die ein Messwert überbrückt (Minuten); dazwischen fehlen Daten (Uhr abgelegt).
  static const maxGapMinutes = 10;

  /// Dauer des letzten Messwerts (Minuten), wie das übliche Raster der Uhren.
  static const lastSampleMinutes = 2;

  /// Ohne eigene HFmax-Angabe und ohne Messung.
  static const defaultMaxHeartRate = 190.0;

  /// Ohne Ruhepuls des Tages.
  static const defaultRestingHeartRate = 60.0;

  /// 0–21 aus gewichteten Minuten.
  static double strainOf(double load) =>
      load <= 0 ? 0 : (maximum * (1 - math.exp(-load / scale)) * 10).roundToDouble() / 10;

  /// Gewichtete Minuten zu einem Strain (Umkehrung von [strainOf]) – um Geplantes oben draufzurechnen.
  static double loadOf(double strain) =>
      strain <= 0 ? 0 : -scale * math.log(1 - math.min(strain, maximum - 0.01) / maximum);

  /// Gewicht je Minute bei [reserve] (Anteil der Herzfrequenzreserve).
  static double weight(double reserve) {
    var result = reserve >= activityFloor ? activityWeight : 0.0;
    for (final (floor, value) in zones) {
      if (reserve >= floor) result = value;
    }
    return result;
  }

  /// Bereich 0–5 eines Anteils der Herzfrequenzreserve.
  static int zone(double reserve) => zones.lastIndexWhere((entry) => reserve >= entry.$1) + 1;

  /// HFmax für die Herzfrequenzreserve: eigener Wert (Einstellungen), sonst der höchste bestätigte bzw. höchste
  /// gemessene Puls aus Lauf- und Radeinheiten der letzten 12 Monate, sonst nach Alter (Tanaka: 208 − 0,7 × Alter),
  /// sonst `null` (dann [defaultMaxHeartRate]).
  static double? maxHeartRate({
    required HeartRateOverrides overrides,
    required List<GarminActivity> activities,
    required CalendarDay today,
    int? age,
  }) {
    if (overrides.valid(overrides.maxHeartRate) case final own?) return own.toDouble();
    final observed = HeartRateZoneCalculator.observedMax(activities, today: today);
    if ((observed.confirmed ?? observed.peak) case final measured?) return measured.toDouble();
    if (age != null && age >= 10 && age <= 100) return (208 - 0.7 * age).roundToDouble();
    return null;
  }

  /// Raster der Pulsverläufe (Minuten), wie Garmin `dailyHeartRate`.
  static const bucketMinutes = 2;

  /// Einzelne Messwerte (z. B. Apple Health: im Training alle paar Sekunden, sonst alle paar Minuten) als Verlauf je
  /// Kalendertag in Ortszeit: Mittelwert je 2-Minuten-Fenster.
  static Map<CalendarDay, List<HeartRateSample>> curves(Iterable<(DateTime time, double bpm)> samples) {
    final buckets = <CalendarDay, Map<int, (double, int)>>{};
    for (final (time, bpm) in samples) {
      if (bpm < 25 || bpm > 240) continue;
      final local = time.toLocal();
      final minute = (local.hour * 60 + local.minute) ~/ bucketMinutes * bucketMinutes;
      final day = buckets[CalendarDay.fromDate(local)] ??= {};
      final (sum, count) = day[minute] ?? (0.0, 0);
      day[minute] = (sum + bpm, count + 1);
    }
    return {
      for (final MapEntry(key: day, value: minutes) in buckets.entries)
        day: [
          for (final minute in minutes.keys.toList()..sort())
            HeartRateSample(minute: minute, bpm: (minutes[minute]!.$1 / minutes[minute]!.$2).round()),
        ],
    };
  }

  /// Rechnet den Strain aus dem Pulsverlauf eines Tages. `null` ohne verwertbare Messwerte.
  static HeartRateStrainResult? compute(List<HeartRateSample> curve, {double? restingHeartRate, double? maxHeartRate}) {
    final samples = [
      for (final sample in curve)
        if (sample.bpm >= 25 && sample.bpm <= 240 && sample.minute >= 0 && sample.minute < 24 * 60) sample,
    ]..sort((a, b) => a.minute.compareTo(b.minute));
    if (samples.isEmpty) return null;
    final measuredMax = samples.map((sample) => sample.bpm).reduce(math.max).toDouble();
    final resting = restingHeartRate != null && restingHeartRate >= 30 && restingHeartRate <= 120
        ? restingHeartRate
        : defaultRestingHeartRate;
    // HFmax nie unter dem heute gemessenen Höchstwert (sonst lägen Minuten über 100 %).
    final maximumHeartRate = math.max(maxHeartRate ?? defaultMaxHeartRate, measuredMax);
    final reserve = maximumHeartRate - resting;
    if (reserve <= 10) return null;
    final minutes = List<double>.filled(zones.length + 1, 0);
    var load = 0.0;
    for (var index = 0; index < samples.length; index++) {
      final duration = index + 1 < samples.length
          ? math.min(samples[index + 1].minute - samples[index].minute, maxGapMinutes).toDouble()
          : lastSampleMinutes.toDouble();
      if (duration <= 0) continue;
      final share = (samples[index].bpm - resting) / reserve;
      minutes[zone(share)] += duration;
      load += duration * weight(share);
    }
    return HeartRateStrainResult(
      strain: strainOf(load),
      load: load,
      zoneMinutes: minutes,
      restingHeartRate: resting,
      maxHeartRate: maximumHeartRate,
    );
  }
}

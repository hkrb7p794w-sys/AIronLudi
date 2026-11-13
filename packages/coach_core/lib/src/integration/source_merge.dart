import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../health/health_import.dart';
import '../util/fnv.dart';
import 'data_provider.dart';

/// Ergebnis der Zusammenführung von Tageswerten.
final class MetricsMergeResult {
  const MetricsMergeResult({required this.metrics, required this.sources});

  final DailyMetrics metrics;

  /// Welche Quelle je Datenart gewonnen hat.
  final Map<DataKind, DataProvider> sources;
}

/// Führt Tageswerte mehrerer Anbieter zusammen: je Datenart genau eine Quelle (die erste mit Werten in der
/// Reihenfolge der Einstellungen), immer als ganze Gruppe. So mischt die App nie Schlafdauer von WHOOP mit
/// Schlafphasen von Garmin, zählt Kalorien nicht doppelt und zeigt keine widersprüchlichen Werte nebeneinander.
abstract final class MetricsMerge {
  /// Datenarten, die Tageswerte tragen (Aktivitäten werden getrennt zusammengeführt).
  static const dailyKinds = [
    DataKind.sleep,
    DataKind.hrv,
    DataKind.restingHeartRate,
    DataKind.stress,
    DataKind.calories,
    DataKind.steps,
    DataKind.trainingLoad,
    DataKind.recovery,
    DataKind.body,
  ];

  static MetricsMergeResult merge(
    Map<DataProvider, DailyMetrics> perProvider, {
    required CalendarDay day,
    required SourcePreferences preferences,
  }) {
    final metrics = DailyMetrics(day);
    final sources = <DataKind, DataProvider>{};
    final connected = perProvider.keys.toSet();
    for (final kind in dailyKinds) {
      for (final provider in preferences.order(kind, connected: connected)) {
        final values = perProvider[provider];
        if (values == null || !hasValues(kind, values)) continue;
        copy(kind, from: values, into: metrics);
        sources[kind] = provider;
        break;
      }
    }
    return MetricsMergeResult(metrics: metrics, sources: sources);
  }

  static bool hasValues(DataKind kind, DailyMetrics m) => switch (kind) {
    DataKind.sleep => m.sleepSeconds != null || m.sleepScore != null || m.deepSleepSeconds != null,
    DataKind.hrv => m.hrvLastNightAverage != null || m.hrvWeeklyAverage != null || m.hrvStatus != null,
    DataKind.restingHeartRate => m.restingHeartRate != null,
    DataKind.stress => m.stressAverage != null,
    DataKind.calories => m.activeKilocalories != null || m.totalKilocalories != null || m.restingKilocalories != null,
    DataKind.steps => m.steps != null,
    DataKind.trainingLoad => m.acuteLoad != null || m.trainingStatus != null,
    DataKind.recovery =>
      m.bodyBatteryHigh != null ||
          m.bodyBatteryLatest != null ||
          m.bodyBatteryCurve != null ||
          m.trainingReadiness != null ||
          m.recoveryHours != null,
    DataKind.body =>
      m.vo2Max != null ||
          m.fitnessAge != null ||
          m.enduranceScore != null ||
          m.spo2Average != null ||
          m.respirationWaking != null,
    DataKind.activities || DataKind.workoutHeartRate => false,
  };

  /// Kopiert die ganze Gruppe einer Datenart.
  static void copy(DataKind kind, {required DailyMetrics from, required DailyMetrics into}) {
    final (m, t) = (from, into);
    switch (kind) {
      case DataKind.sleep:
        t
          ..sleepSeconds = m.sleepSeconds
          ..sleepScore = m.sleepScore
          ..deepSleepSeconds = m.deepSleepSeconds
          ..lightSleepSeconds = m.lightSleepSeconds
          ..remSleepSeconds = m.remSleepSeconds
          ..awakeSleepSeconds = m.awakeSleepSeconds
          ..sleepStartMinutes = m.sleepStartMinutes
          ..sleepEndMinutes = m.sleepEndMinutes
          ..sleepStress = m.sleepStress
          ..respirationSleep = m.respirationSleep;
      case DataKind.hrv:
        t
          ..hrvLastNightAverage = m.hrvLastNightAverage
          ..hrvWeeklyAverage = m.hrvWeeklyAverage
          ..hrvStatus = m.hrvStatus
          ..hrvBaselineLow = m.hrvBaselineLow
          ..hrvBaselineHigh = m.hrvBaselineHigh;
      case DataKind.restingHeartRate:
        t
          ..restingHeartRate = m.restingHeartRate
          ..minHeartRate = m.minHeartRate
          ..maxHeartRate = m.maxHeartRate;
      case DataKind.stress:
        t.stressAverage = m.stressAverage;
      case DataKind.calories:
        t
          ..activeKilocalories = m.activeKilocalories
          ..totalKilocalories = m.totalKilocalories
          ..restingKilocalories = m.restingKilocalories;
      case DataKind.steps:
        t.steps = m.steps;
      case DataKind.trainingLoad:
        t
          ..acuteLoad = m.acuteLoad
          ..chronicLoad = m.chronicLoad
          ..trainingStatus = m.trainingStatus;
      case DataKind.recovery:
        t
          ..bodyBatteryHigh = m.bodyBatteryHigh
          ..bodyBatteryLow = m.bodyBatteryLow
          ..bodyBatteryLatest = m.bodyBatteryLatest
          ..bodyBatteryCharged = m.bodyBatteryCharged
          ..bodyBatteryDrained = m.bodyBatteryDrained
          ..bodyBatteryAtWake = m.bodyBatteryAtWake
          ..bodyBatteryCurve = m.bodyBatteryCurve
          ..trainingReadiness = m.trainingReadiness
          ..trainingReadinessLevel = m.trainingReadinessLevel
          ..recoveryHours = m.recoveryHours;
      case DataKind.body:
        t
          ..vo2Max = m.vo2Max
          ..fitnessAge = m.fitnessAge
          ..enduranceScore = m.enduranceScore
          ..spo2Average = m.spo2Average
          ..spo2Lowest = m.spo2Lowest
          ..respirationWaking = m.respirationWaking;
      case DataKind.activities || DataKind.workoutHeartRate:
        break;
    }
  }
}

/// Plan der Aktivitäten ohne Doppelte.
final class ActivityMergePlan {
  const ActivityMergePlan({required this.kept, required this.superseded});

  /// Behaltene Aktivitäten.
  final List<GarminActivity> kept;

  /// Ersetzte Aktivität → die behaltene.
  final Map<int, int> superseded;
}

typedef TimedActivity = ({GarminActivity activity, DateTime? start, DateTime? end});

/// Aktivitäten mehrerer Anbieter ohne Doppelte: Dieselbe Einheit (gleiche Sportart, Start höchstens 10 Minuten
/// auseinander oder mehr als die Hälfte überlappend) bleibt nur von der bevorzugten Quelle – samt Kalorien,
/// Herzfrequenz und Trainingsbelastung. Doppelte werden nicht gelöscht, sondern als ersetzt markiert, damit ein
/// späterer Abruf sie nicht wieder anlegt.
abstract final class ActivityMerge {
  /// Anbieter einer Aktivität. Ältere Einträge haben kein Feld: negative IDs kamen aus Apple Health.
  static DataProvider provider(GarminActivity activity) =>
      activity.provider ?? (activity.id < 0 ? DataProvider.appleHealth : DataProvider.garmin);

  /// [utcOffset] ersetzt für Tests die Zeitzone des Geräts (Swift: `TimeZone`).
  static ActivityMergePlan plan(
    List<GarminActivity> activities, {
    required SourcePreferences preferences,
    required Set<DataProvider> connected,
    Duration? utcOffset,
  }) {
    final order = preferences.order(DataKind.activities, connected: {...connected, ...activities.map(provider)});
    int rank(GarminActivity activity) {
      final index = order.indexOf(provider(activity));
      return index < 0 ? order.length : index;
    }

    // Bevorzugte Quelle zuerst, bei gleicher Quelle die längere (vollständigere) Aufzeichnung.
    final sorted = [...activities]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final byDuration = (b.durationSeconds ?? 0).compareTo(a.durationSeconds ?? 0);
        if (byDuration != 0) return byDuration;
        return a.id.compareTo(b.id);
      });
    final kept = <TimedActivity>[];
    final superseded = <int, int>{};
    for (final activity in sorted) {
      final start = switch (activity.startLocal) {
        final text? => HealthImport.date(text, utcOffset: utcOffset),
        null => null,
      };
      final end = start?.add(Duration(microseconds: ((activity.durationSeconds ?? 0) * 1e6).round()));
      final timed = (activity: activity, start: start, end: end);
      final match = kept
          .where((other) => provider(other.activity) != provider(activity) && sameSession(other, timed))
          .firstOrNull;
      if (match != null) {
        superseded[activity.id] = match.activity.id;
      } else {
        kept.add(timed);
      }
    }
    return ActivityMergePlan(kept: [for (final entry in kept) entry.activity], superseded: superseded);
  }

  static bool sameSession(TimedActivity a, TimedActivity b) {
    final (aStart, aEnd, bStart, bEnd) = (a.start, a.end, b.start, b.end);
    if (aStart == null || aEnd == null || bStart == null || bEnd == null) return false;
    final (sportA, sportB) = (a.activity.sport, b.activity.sport);
    if (sportA != sportB && sportA != ActivitySport.other && sportB != ActivitySport.other) return false;
    double seconds(Duration duration) => duration.inMicroseconds / 1e6;
    if (seconds(aStart.difference(bStart)).abs() <= 600) return true;
    final earliestEnd = aEnd.isBefore(bEnd) ? aEnd : bEnd;
    final latestStart = aStart.isAfter(bStart) ? aStart : bStart;
    final overlap = seconds(earliestEnd.difference(latestStart));
    final shorter = math.min(seconds(aEnd.difference(aStart)), seconds(bEnd.difference(bStart)));
    return shorter > 0 && overlap > shorter / 2;
  }

  /// Stabile, negative ID für Aktivitäten ohne Garmin-ID (Garmin-IDs sind positiv). Je Anbieter ein eigener
  /// Bereich, damit gleiche externe IDs verschiedener Anbieter nicht kollidieren.
  static int localID({required DataProvider provider, required String externalID}) {
    final hash = fnv1a64Text('${provider.rawValue}:$externalID');
    return -(hash % BigInt.from(4000000000000000000)).toInt() - 1;
  }
}

import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';

/// Ein Wert des Body-Battery-Tagesverlaufs: Minuten nach Mitternacht (Ortszeit) und Stand 0–100.
final class BodyBatterySample {
  const BodyBatterySample({required this.minute, required this.value});

  final int minute;
  final int value;

  Map<String, Object?> toJson() => {'minute': minute, 'value': value};

  static BodyBatterySample? fromJson(Object? json) {
    if (json is! Map) return null;
    final minute = jsonInt(json['minute']);
    final value = jsonInt(json['value']);
    return minute == null || value == null ? null : BodyBatterySample(minute: minute, value: value);
  }

  @override
  bool operator ==(Object other) => other is BodyBatterySample && other.minute == minute && other.value == value;

  @override
  int get hashCode => Object.hash(minute, value);

  @override
  String toString() => 'BodyBatterySample($minute, $value)';
}

/// Erholungs- und Tageswerte eines Kalendertags, zusammengeführt aus mehreren Garmin-Endpunkten. Alle Werte optional:
/// Nicht jede Uhr liefert alles, und die Personal API ist nicht vollständig dokumentiert.
///
/// Feldbedeutungen wie in Swift (`DailyMetrics.swift`): HRV-Status `BALANCED`/`UNBALANCED`/`LOW`/`POOR`/`NONE`,
/// Atemfrequenz in Atemzügen pro Minute, SpO2 in Prozent, Einschlaf-/Aufwachzeit in Minuten nach Mitternacht
/// (Ortszeit), Training Readiness 0–100 nur über den Garmin-Connect-Zugang, Regenerationszeit in Stunden.
final class DailyMetrics {
  DailyMetrics(this.day);

  final CalendarDay day;
  double? restingHeartRate;
  double? hrvLastNightAverage;
  double? hrvWeeklyAverage;
  String? hrvStatus;
  double? hrvBaselineLow;
  double? hrvBaselineHigh;
  double? sleepSeconds;
  double? sleepScore;
  double? bodyBatteryHigh;
  double? bodyBatteryLow;
  double? bodyBatteryLatest;
  double? stressAverage;
  double? steps;
  double? activeKilocalories;
  double? totalKilocalories;
  double? respirationWaking;
  double? respirationSleep;
  double? spo2Average;
  double? spo2Lowest;
  double? bodyBatteryCharged;
  double? bodyBatteryDrained;
  double? deepSleepSeconds;
  double? lightSleepSeconds;
  double? remSleepSeconds;
  double? awakeSleepSeconds;
  double? sleepStress;
  double? fitnessAge;
  double? vo2Max;
  double? trainingReadiness;
  String? trainingReadinessLevel;
  String? trainingStatus;
  double? enduranceScore;
  double? sleepStartMinutes;
  double? sleepEndMinutes;
  double? bodyBatteryAtWake;
  List<BodyBatterySample>? bodyBatteryCurve;
  double? restingKilocalories;
  double? minHeartRate;
  double? maxHeartRate;
  double? recoveryHours;
  double? acuteLoad;
  double? chronicLoad;

  double? get sleepHours {
    final seconds = sleepSeconds;
    return seconds == null ? null : (seconds / 360).roundToDouble() / 10;
  }

  /// Vorhandene Werte von [other] überschreiben fehlende oder ältere Werte.
  DailyMetrics merging(DailyMetrics other) => DailyMetrics(day)
    ..restingHeartRate = other.restingHeartRate ?? restingHeartRate
    ..hrvLastNightAverage = other.hrvLastNightAverage ?? hrvLastNightAverage
    ..hrvWeeklyAverage = other.hrvWeeklyAverage ?? hrvWeeklyAverage
    ..hrvStatus = other.hrvStatus ?? hrvStatus
    ..hrvBaselineLow = other.hrvBaselineLow ?? hrvBaselineLow
    ..hrvBaselineHigh = other.hrvBaselineHigh ?? hrvBaselineHigh
    ..sleepSeconds = other.sleepSeconds ?? sleepSeconds
    ..sleepScore = other.sleepScore ?? sleepScore
    ..bodyBatteryHigh = other.bodyBatteryHigh ?? bodyBatteryHigh
    ..bodyBatteryLow = other.bodyBatteryLow ?? bodyBatteryLow
    ..bodyBatteryLatest = other.bodyBatteryLatest ?? bodyBatteryLatest
    ..stressAverage = other.stressAverage ?? stressAverage
    ..steps = other.steps ?? steps
    ..activeKilocalories = other.activeKilocalories ?? activeKilocalories
    ..totalKilocalories = other.totalKilocalories ?? totalKilocalories
    ..respirationWaking = other.respirationWaking ?? respirationWaking
    ..respirationSleep = other.respirationSleep ?? respirationSleep
    ..spo2Average = other.spo2Average ?? spo2Average
    ..spo2Lowest = other.spo2Lowest ?? spo2Lowest
    ..bodyBatteryCharged = other.bodyBatteryCharged ?? bodyBatteryCharged
    ..bodyBatteryDrained = other.bodyBatteryDrained ?? bodyBatteryDrained
    ..deepSleepSeconds = other.deepSleepSeconds ?? deepSleepSeconds
    ..lightSleepSeconds = other.lightSleepSeconds ?? lightSleepSeconds
    ..remSleepSeconds = other.remSleepSeconds ?? remSleepSeconds
    ..awakeSleepSeconds = other.awakeSleepSeconds ?? awakeSleepSeconds
    ..sleepStress = other.sleepStress ?? sleepStress
    ..fitnessAge = other.fitnessAge ?? fitnessAge
    ..vo2Max = other.vo2Max ?? vo2Max
    ..trainingReadiness = other.trainingReadiness ?? trainingReadiness
    ..trainingReadinessLevel = other.trainingReadinessLevel ?? trainingReadinessLevel
    ..trainingStatus = other.trainingStatus ?? trainingStatus
    ..enduranceScore = other.enduranceScore ?? enduranceScore
    ..sleepStartMinutes = other.sleepStartMinutes ?? sleepStartMinutes
    ..sleepEndMinutes = other.sleepEndMinutes ?? sleepEndMinutes
    ..bodyBatteryAtWake = other.bodyBatteryAtWake ?? bodyBatteryAtWake
    ..bodyBatteryCurve = other.bodyBatteryCurve ?? bodyBatteryCurve
    ..restingKilocalories = other.restingKilocalories ?? restingKilocalories
    ..minHeartRate = other.minHeartRate ?? minHeartRate
    ..maxHeartRate = other.maxHeartRate ?? maxHeartRate
    ..recoveryHours = other.recoveryHours ?? recoveryHours
    ..acuteLoad = other.acuteLoad ?? acuteLoad
    ..chronicLoad = other.chronicLoad ?? chronicLoad;

  DailyMetrics copy() => DailyMetrics(day)
    ..restingHeartRate = restingHeartRate
    ..hrvLastNightAverage = hrvLastNightAverage
    ..hrvWeeklyAverage = hrvWeeklyAverage
    ..hrvStatus = hrvStatus
    ..hrvBaselineLow = hrvBaselineLow
    ..hrvBaselineHigh = hrvBaselineHigh
    ..sleepSeconds = sleepSeconds
    ..sleepScore = sleepScore
    ..bodyBatteryHigh = bodyBatteryHigh
    ..bodyBatteryLow = bodyBatteryLow
    ..bodyBatteryLatest = bodyBatteryLatest
    ..stressAverage = stressAverage
    ..steps = steps
    ..activeKilocalories = activeKilocalories
    ..totalKilocalories = totalKilocalories
    ..respirationWaking = respirationWaking
    ..respirationSleep = respirationSleep
    ..spo2Average = spo2Average
    ..spo2Lowest = spo2Lowest
    ..bodyBatteryCharged = bodyBatteryCharged
    ..bodyBatteryDrained = bodyBatteryDrained
    ..deepSleepSeconds = deepSleepSeconds
    ..lightSleepSeconds = lightSleepSeconds
    ..remSleepSeconds = remSleepSeconds
    ..awakeSleepSeconds = awakeSleepSeconds
    ..sleepStress = sleepStress
    ..fitnessAge = fitnessAge
    ..vo2Max = vo2Max
    ..trainingReadiness = trainingReadiness
    ..trainingReadinessLevel = trainingReadinessLevel
    ..trainingStatus = trainingStatus
    ..enduranceScore = enduranceScore
    ..sleepStartMinutes = sleepStartMinutes
    ..sleepEndMinutes = sleepEndMinutes
    ..bodyBatteryAtWake = bodyBatteryAtWake
    ..bodyBatteryCurve = bodyBatteryCurve
    ..restingKilocalories = restingKilocalories
    ..minHeartRate = minHeartRate
    ..maxHeartRate = maxHeartRate
    ..recoveryHours = recoveryHours
    ..acuteLoad = acuteLoad
    ..chronicLoad = chronicLoad;

  /// Namen der befüllten Felder – für die Diagnose in der App.
  List<String> get presentFields {
    final fields = <(String, Object?)>[
      ('Ruhepuls', restingHeartRate),
      ('HRV letzte Nacht', hrvLastNightAverage),
      ('HRV 7 Tage', hrvWeeklyAverage),
      ('HRV-Status', hrvStatus),
      ('HRV-Baseline', hrvBaselineLow),
      ('Schlafdauer', sleepSeconds),
      ('Schlaf-Score', sleepScore),
      ('Body Battery', bodyBatteryHigh),
      ('Stress', stressAverage),
      ('Schritte', steps),
      ('Aktive kcal', activeKilocalories),
      ('Atemfrequenz', respirationWaking ?? respirationSleep),
      ('SpO2', spo2Average),
      ('Schlafphasen', deepSleepSeconds),
      ('Fitnessalter', fitnessAge),
      ('VO2max', vo2Max),
      ('Training Readiness', trainingReadiness),
      ('Trainingsstatus', trainingStatus),
      ('Endurance Score', enduranceScore),
      ('Body-Battery-Verlauf', bodyBatteryCurve),
      ('Ruhekalorien', restingKilocalories),
      ('Höchster Puls', maxHeartRate),
      ('Regenerationszeit', recoveryHours),
      ('Akute Belastung', acuteLoad),
    ];
    return [
      for (final (name, value) in fields)
        if (value != null) name,
    ];
  }

  Map<String, Object?> toJson() => {
    'day': day.toJson(),
    'restingHeartRate': ?restingHeartRate,
    'hrvLastNightAverage': ?hrvLastNightAverage,
    'hrvWeeklyAverage': ?hrvWeeklyAverage,
    'hrvStatus': ?hrvStatus,
    'hrvBaselineLow': ?hrvBaselineLow,
    'hrvBaselineHigh': ?hrvBaselineHigh,
    'sleepSeconds': ?sleepSeconds,
    'sleepScore': ?sleepScore,
    'bodyBatteryHigh': ?bodyBatteryHigh,
    'bodyBatteryLow': ?bodyBatteryLow,
    'bodyBatteryLatest': ?bodyBatteryLatest,
    'stressAverage': ?stressAverage,
    'steps': ?steps,
    'activeKilocalories': ?activeKilocalories,
    'totalKilocalories': ?totalKilocalories,
    'respirationWaking': ?respirationWaking,
    'respirationSleep': ?respirationSleep,
    'spo2Average': ?spo2Average,
    'spo2Lowest': ?spo2Lowest,
    'bodyBatteryCharged': ?bodyBatteryCharged,
    'bodyBatteryDrained': ?bodyBatteryDrained,
    'deepSleepSeconds': ?deepSleepSeconds,
    'lightSleepSeconds': ?lightSleepSeconds,
    'remSleepSeconds': ?remSleepSeconds,
    'awakeSleepSeconds': ?awakeSleepSeconds,
    'sleepStress': ?sleepStress,
    'fitnessAge': ?fitnessAge,
    'vo2Max': ?vo2Max,
    'trainingReadiness': ?trainingReadiness,
    'trainingReadinessLevel': ?trainingReadinessLevel,
    'trainingStatus': ?trainingStatus,
    'enduranceScore': ?enduranceScore,
    'sleepStartMinutes': ?sleepStartMinutes,
    'sleepEndMinutes': ?sleepEndMinutes,
    'bodyBatteryAtWake': ?bodyBatteryAtWake,
    'bodyBatteryCurve': ?bodyBatteryCurve?.map((sample) => sample.toJson()).toList(),
    'restingKilocalories': ?restingKilocalories,
    'minHeartRate': ?minHeartRate,
    'maxHeartRate': ?maxHeartRate,
    'recoveryHours': ?recoveryHours,
    'acuteLoad': ?acuteLoad,
    'chronicLoad': ?chronicLoad,
  };

  static DailyMetrics? fromJson(Object? json) {
    if (json is! Map || json['day'] is! Map) return null;
    return DailyMetrics(CalendarDay.fromJson((json['day'] as Map).cast<String, Object?>()))
      ..restingHeartRate = jsonDouble(json['restingHeartRate'])
      ..hrvLastNightAverage = jsonDouble(json['hrvLastNightAverage'])
      ..hrvWeeklyAverage = jsonDouble(json['hrvWeeklyAverage'])
      ..hrvStatus = json['hrvStatus'] is String ? json['hrvStatus'] as String : null
      ..hrvBaselineLow = jsonDouble(json['hrvBaselineLow'])
      ..hrvBaselineHigh = jsonDouble(json['hrvBaselineHigh'])
      ..sleepSeconds = jsonDouble(json['sleepSeconds'])
      ..sleepScore = jsonDouble(json['sleepScore'])
      ..bodyBatteryHigh = jsonDouble(json['bodyBatteryHigh'])
      ..bodyBatteryLow = jsonDouble(json['bodyBatteryLow'])
      ..bodyBatteryLatest = jsonDouble(json['bodyBatteryLatest'])
      ..stressAverage = jsonDouble(json['stressAverage'])
      ..steps = jsonDouble(json['steps'])
      ..activeKilocalories = jsonDouble(json['activeKilocalories'])
      ..totalKilocalories = jsonDouble(json['totalKilocalories'])
      ..respirationWaking = jsonDouble(json['respirationWaking'])
      ..respirationSleep = jsonDouble(json['respirationSleep'])
      ..spo2Average = jsonDouble(json['spo2Average'])
      ..spo2Lowest = jsonDouble(json['spo2Lowest'])
      ..bodyBatteryCharged = jsonDouble(json['bodyBatteryCharged'])
      ..bodyBatteryDrained = jsonDouble(json['bodyBatteryDrained'])
      ..deepSleepSeconds = jsonDouble(json['deepSleepSeconds'])
      ..lightSleepSeconds = jsonDouble(json['lightSleepSeconds'])
      ..remSleepSeconds = jsonDouble(json['remSleepSeconds'])
      ..awakeSleepSeconds = jsonDouble(json['awakeSleepSeconds'])
      ..sleepStress = jsonDouble(json['sleepStress'])
      ..fitnessAge = jsonDouble(json['fitnessAge'])
      ..vo2Max = jsonDouble(json['vo2Max'])
      ..trainingReadiness = jsonDouble(json['trainingReadiness'])
      ..trainingReadinessLevel = json['trainingReadinessLevel'] is String
          ? json['trainingReadinessLevel'] as String
          : null
      ..trainingStatus = json['trainingStatus'] is String ? json['trainingStatus'] as String : null
      ..enduranceScore = jsonDouble(json['enduranceScore'])
      ..sleepStartMinutes = jsonDouble(json['sleepStartMinutes'])
      ..sleepEndMinutes = jsonDouble(json['sleepEndMinutes'])
      ..bodyBatteryAtWake = jsonDouble(json['bodyBatteryAtWake'])
      ..bodyBatteryCurve = json['bodyBatteryCurve'] is List
          ? (json['bodyBatteryCurve'] as List).map(BodyBatterySample.fromJson).nonNulls.toList()
          : null
      ..restingKilocalories = jsonDouble(json['restingKilocalories'])
      ..minHeartRate = jsonDouble(json['minHeartRate'])
      ..maxHeartRate = jsonDouble(json['maxHeartRate'])
      ..recoveryHours = jsonDouble(json['recoveryHours'])
      ..acuteLoad = jsonDouble(json['acuteLoad'])
      ..chronicLoad = jsonDouble(json['chronicLoad']);
  }

  @override
  bool operator ==(Object other) =>
      other is DailyMetrics && const DeepCollectionEquality().equals(other.toJson(), toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());

  @override
  String toString() => 'DailyMetrics($day)';
}

/// Tageswerte je Kalendertag.
typedef DayMap = Map<CalendarDay, DailyMetrics>;

/// Liest Tageswerte aus den Antworten der Personal API.
///
/// Feldnamen: wie in den Connect-Endpunkten, auf denen die Personal API aufsetzt (bekannt aus python-garminconnect und
/// dem Altbestand, z. B. `hrvSummary.status`, `dailySleepDTO.sleepTimeSeconds`). Jeder Wert hat mehrere Kandidaten,
/// damit kleine Formatänderungen nichts kaputt machen.
abstract final class GarminMetricsParser {
  /// `/usersummary-service/v2/dailysummaries`: Objekt mit Daten-Array, je Tag ein Eintrag.
  static DayMap dailySummaries(JsonValue json) => _records(json, (record, metrics) {
    metrics
      ..restingHeartRate = _positive(
        _first(record, ['restingHeartRate', 'restingHeartRateValue', 'currentDayRestingHeartRate']),
      )
      ..steps = _nonNegative(_first(record, ['totalSteps']))
      ..stressAverage = _nonNegative(_first(record, ['averageStressLevel', 'avgStressLevel']))
      ..bodyBatteryHigh = _nonNegative(_first(record, ['bodyBatteryHighestValue', 'highestBodyBattery']))
      ..bodyBatteryLow = _nonNegative(_first(record, ['bodyBatteryLowestValue', 'lowestBodyBattery']))
      ..bodyBatteryLatest = _nonNegative(_first(record, ['bodyBatteryMostRecentValue']))
      ..activeKilocalories = _nonNegative(_first(record, ['activeKilocalories']))
      ..totalKilocalories = _nonNegative(_first(record, ['totalKilocalories']))
      ..bodyBatteryCharged = _nonNegative(_first(record, ['bodyBatteryChargedValue']))
      ..bodyBatteryDrained = _nonNegative(_first(record, ['bodyBatteryDrainedValue']))
      ..respirationWaking = _positive(_first(record, ['avgWakingRespirationValue', 'averageRespirationValue']))
      ..spo2Average = _positive(_first(record, ['averageSpo2', 'averageSpO2', 'avgSpo2']))
      ..spo2Lowest = _positive(_first(record, ['lowestSpo2', 'lowestSpO2']))
      ..bodyBatteryAtWake = _nonNegative(_first(record, ['bodyBatteryAtWakeTime']))
      ..restingKilocalories = _positive(_first(record, ['bmrKilocalories']))
      ..minHeartRate = _positive(_first(record, ['minHeartRate', 'minHeartRateInBeatsPerMinute']))
      ..maxHeartRate = _positive(_first(record, ['maxHeartRate', 'maxHeartRateInBeatsPerMinute']));
  });

  /// `/hrv-service/hrv/{date}` (`hrvSummary`) und `/hrv-service/hrv/daily/{start}/{end}`.
  static DayMap hrv(JsonValue json) => _records(json, (record, metrics) {
    metrics
      ..hrvLastNightAverage = _positive(_first(record, ['lastNightAvg', 'lastNightAverage']))
      ..hrvWeeklyAverage = _positive(_first(record, ['weeklyAvg', 'weeklyAverage']))
      ..hrvStatus = _first(record, ['status', 'hrvStatus'])?.stringValue?.toUpperCase()
      ..hrvBaselineLow = _positive(_first(record, ['balancedLow']))
      ..hrvBaselineHigh = _positive(_first(record, ['balancedUpper', 'balancedHigh']));
  });

  /// `/sleep-service/sleep/dailySleep` (`dailySleepDTO`) und `dailySleepSummariesByDate`.
  static DayMap sleep(JsonValue json) => _records(json, (record, metrics) {
    metrics.sleepSeconds = _positive(_first(record, ['sleepTimeSeconds', 'totalSleepSeconds', 'sleepDurationSeconds']));
    final scores = _first(record, ['sleepScores']);
    if (scores != null) metrics.sleepScore = _positive(scores['overall']?['value'] ?? scores.firstValue(['value']));
    metrics
      ..sleepScore = metrics.sleepScore ?? _positive(_first(record, ['overallSleepScore', 'sleepScore']))
      ..deepSleepSeconds = _nonNegative(_first(record, ['deepSleepSeconds']))
      ..lightSleepSeconds = _nonNegative(_first(record, ['lightSleepSeconds']))
      ..remSleepSeconds = _nonNegative(_first(record, ['remSleepSeconds']))
      ..awakeSleepSeconds = _nonNegative(_first(record, ['awakeSleepSeconds']))
      ..respirationSleep = _positive(_first(record, ['averageRespirationValue', 'avgSleepRespirationValue']))
      ..spo2Average = _positive(_first(record, ['averageSpO2Value', 'averageSpo2Value']))
      ..spo2Lowest = _positive(_first(record, ['lowestSpO2Value', 'lowestSpo2Value']))
      ..sleepStress = _nonNegative(_first(record, ['avgSleepStress']));
    // Connect: `sleepStartTimestampLocal` (ms, Ortszeit als UTC kodiert); Personal API: Start in s + Versatz.
    final startLocal = _first(record, ['sleepStartTimestampLocal'])?.doubleValue;
    final start = _first(record, ['startTimeInSeconds'])?.doubleValue;
    final offset = _first(record, ['startTimeOffsetInSeconds'])?.doubleValue ?? 0;
    if (startLocal != null) {
      metrics.sleepStartMinutes = minutesOfDay(startLocal);
    } else if (start != null) {
      metrics.sleepStartMinutes = minutesOfDay((start + offset) * 1000);
    }
    final endLocal = _first(record, ['sleepEndTimestampLocal'])?.doubleValue;
    final duration = _first(record, ['durationInSeconds'])?.doubleValue;
    if (endLocal != null) {
      metrics.sleepEndMinutes = minutesOfDay(endLocal);
    } else if (start != null && duration != null) {
      metrics.sleepEndMinutes = minutesOfDay((start + duration + offset) * 1000);
    }
  });

  /// Minuten nach Mitternacht aus einem Zeitstempel, dessen Uhrzeit bereits Ortszeit ist.
  static double? minutesOfDay(double milliseconds) {
    if (milliseconds <= 0) return null;
    final seconds = (milliseconds / 1000) % 86400;
    return (seconds / 60).roundToDouble();
  }

  /// `/wellness-service/wellness/bodyBattery/reports/daily`: Liste mit einem Eintrag je Tag. Der Tag steht unter `date`
  /// (nicht `calendarDate` wie sonst), die Werte in `bodyBatteryValuesArray` als `[Zeitstempel GMT in ms, Wert]` –
  /// oder, laut `bodyBatteryValueDescriptorDTOList`, mit Status an Stelle 1 und dem Wert an Stelle 2.
  ///
  /// [offsetSeconds] liefert den Versatz zur Ortszeit für einen Zeitstempel, falls die Antwort keinen nennt (Standard:
  /// Zeitzone des Geräts).
  static DayMap bodyBattery(JsonValue json, {int Function(int milliseconds)? offsetSeconds}) {
    final result = <CalendarDay, DailyMetrics>{};
    final entries = [...json.objects('bodyBatteryValuesArray'), ...json.objects('charged')];
    for (final record in entries) {
      final text = (record['calendarDate'] ?? record['date'])?.stringValue;
      final day = text == null ? null : CalendarDay.tryParse(text.length > 10 ? text.substring(0, 10) : text);
      if (day == null) continue;
      final samples = bodyBatterySamples(record, offsetSeconds: offsetSeconds);
      final values = samples.map((sample) => sample.value.toDouble()).toList();
      final metrics = DailyMetrics(day)
        ..bodyBatteryHigh = values.isEmpty
            ? _nonNegative(_first(record, ['bodyBatteryHighestValue']))
            : values.reduce(math.max)
        ..bodyBatteryLow = values.isEmpty
            ? _nonNegative(_first(record, ['bodyBatteryLowestValue']))
            : values.reduce(math.min)
        ..bodyBatteryLatest = values.isEmpty
            ? _nonNegative(_first(record, ['bodyBatteryMostRecentValue']))
            : values.last
        ..bodyBatteryCharged = _nonNegative(record['charged'])
        ..bodyBatteryDrained = _nonNegative(record['drained'])
        ..bodyBatteryCurve = samples.isEmpty ? null : samples;
      result[day] = result[day]?.merging(metrics) ?? metrics;
    }
    return result;
  }

  /// Werte als Ortszeit-Minuten, je Viertelstunde der letzte Wert. Der Versatz zur Ortszeit kommt aus
  /// `startTimestampLocal`/`startTimestampGMT` (stimmt auch auf Reisen), sonst aus [offsetSeconds].
  static List<BodyBatterySample> bodyBatterySamples(
    Map<String, JsonValue> record, {
    int Function(int milliseconds)? offsetSeconds,
  }) {
    var timeIndex = 0;
    var valueIndex = 1;
    for (final descriptor in record['bodyBatteryValueDescriptorDTOList']?.arrayValue ?? const <JsonValue>[]) {
      final index = descriptor['bodyBatteryValueDescriptorIndex']?.doubleValue;
      final key = descriptor['bodyBatteryValueDescriptorKey']?.stringValue;
      if (index == null || key == null) continue;
      if (key == 'timestamp') timeIndex = index.truncate();
      if (key == 'bodyBatteryLevel') valueIndex = index.truncate();
    }
    double? offset;
    final local = record['startTimestampLocal']?.stringValue;
    final gmt = record['startTimestampGMT']?.stringValue;
    final localSeconds = local == null ? null : gmtSeconds(local);
    final gmtValue = gmt == null ? null : gmtSeconds(gmt);
    if (localSeconds != null && gmtValue != null) offset = localSeconds - gmtValue;
    final buckets = <int, int>{};
    for (final entry in record['bodyBatteryValuesArray']?.arrayValue ?? const <JsonValue>[]) {
      final row = entry.arrayValue;
      if (row == null || row.length <= math.max(timeIndex, valueIndex)) continue;
      final milliseconds = row[timeIndex].doubleValue;
      final raw = row[valueIndex].doubleValue;
      if (milliseconds == null || raw == null || raw < 0 || raw > 100) continue;
      final seconds = milliseconds / 1000;
      final shift =
          offset ??
          (offsetSeconds?.call(milliseconds.round()) ??
                  DateTime.fromMillisecondsSinceEpoch(milliseconds.round()).timeZoneOffset.inSeconds)
              .toDouble();
      final minute = (((seconds + shift) % 86400 + 86400) % 86400 / 60).truncate();
      buckets[minute ~/ 15] = raw.round();
    }
    final keys = buckets.keys.toList()..sort();
    return [for (final key in keys) BodyBatterySample(minute: key * 15, value: buckets[key] ?? 0)];
  }

  /// „2026-04-21T00:00:00.0“ als Sekunden (ohne Zeitzone gelesen, nur für Differenzen).
  static double? gmtSeconds(String text) {
    final head = text.length > 19 ? text.substring(0, 19) : text;
    final parts = head.split(RegExp(r'[-T:]')).map(int.tryParse).nonNulls.toList();
    if (parts.length != 6) return null;
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).millisecondsSinceEpoch / 1000;
  }

  /// `/usersummary-service/stats/stress/daily/{start}/{end}`.
  static DayMap stress(JsonValue json) => _records(json, (record, metrics) {
    metrics.stressAverage = _nonNegative(
      _first(record, ['averageStressLevel', 'avgStressLevel', 'overallStressLevel']),
    );
  });

  /// `/wellness-service/wellness/daily/spo2acclimation/{date}`.
  static DayMap spo2(JsonValue json) => _records(json, (record, metrics) {
    metrics
      ..spo2Average = _positive(
        _first(record, ['averageSpO2', 'averageSpo2', 'avgSpO2', 'averageSPO2', 'dailyAverageSpO2']),
      )
      ..spo2Lowest = _positive(_first(record, ['lowestSpO2', 'lowestSpo2', 'minSpO2']));
  });

  /// `/fitnessage-service/fitnessage/v2/{date}`. Die Antwort hat nicht immer `calendarDate`, daher mit Tag.
  static DayMap fitnessAge(JsonValue json, CalendarDay day) {
    final metrics = DailyMetrics(day)
      ..fitnessAge = _positive(json.firstValue(['fitnessAge']))
      ..vo2Max = _positive(json.firstValue(['vo2Max', 'vo2MaxValue', 'vO2MaxValue']));
    if (metrics.fitnessAge == null && metrics.vo2Max == null) return {};
    return {day: metrics};
  }

  /// Führt mehrere Teilergebnisse zusammen (spätere überschreiben frühere, wenn befüllt).
  static DayMap merge(List<DayMap> maps) {
    final result = <CalendarDay, DailyMetrics>{};
    for (final map in maps) {
      for (final MapEntry(key: day, value: metrics) in map.entries) {
        result[day] = result[day]?.merging(metrics) ?? metrics;
      }
    }
    return result;
  }

  static DayMap _records(JsonValue json, void Function(Map<String, JsonValue> record, DailyMetrics metrics) fill) {
    final result = <CalendarDay, DailyMetrics>{};
    for (final record in json.objects('calendarDate')) {
      final text = record['calendarDate']?.stringValue;
      final day = text == null ? null : CalendarDay.tryParse(text);
      if (day == null) continue;
      final metrics = DailyMetrics(day);
      fill(record, metrics);
      result[day] = result[day]?.merging(metrics) ?? metrics;
    }
    return result;
  }

  /// Erster vorhandener Wert unter einem der Schlüssel, auch verschachtelt.
  static JsonValue? _first(Map<String, JsonValue> record, List<String> keys) =>
      JsonValue({for (final entry in record.entries) entry.key: entry.value.raw}).firstValue(keys);

  /// Garmin nutzt negative Werte (-1, -2) für „kein Wert“.
  static double? _nonNegative(JsonValue? value) {
    final number = value?.doubleValue;
    return number != null && number >= 0 ? number : null;
  }

  static double? _positive(JsonValue? value) {
    final number = value?.doubleValue;
    return number != null && number > 0 ? number : null;
  }
}

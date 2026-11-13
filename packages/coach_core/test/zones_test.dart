// Port von CoachCoreTests/MetricsAndZonesTests.swift (ohne die Pfade der Garmin-Endpunkte, die mit dem Garmin-Modul
// folgen).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 10, 22);

GarminActivity activity(
  int id,
  String type, {
  required int daysAgo,
  double? maxHR,
  double? averageHR,
  double minutes = 45,
  double km = 10,
  List<double>? zones,
  double? vo2,
}) => GarminActivity(id)
  ..typeKey = type
  ..startLocal = '${today.adding(-daysAgo).iso} 07:00:00'
  ..maxHeartRate = maxHR
  ..averageHeartRate = averageHR
  ..durationSeconds = minutes * 60
  ..distanceMeters = km * 1000
  ..secondsInZones = zones
  ..vo2Max = vo2;

void main() {
  group('weitere Garmin-Werte', () {
    test('Tageszusammenfassung mit SpO2, Atmung und Body-Battery-Fluss', () {
      final metrics = GarminMetricsParser.dailySummaries(
        JsonValue.parse('''
          [{"calendarDate": "2026-10-22", "averageSpo2": 95, "lowestSpo2": 89, "avgWakingRespirationValue": 14.5,
            "bodyBatteryChargedValue": 62, "bodyBatteryDrainedValue": 48}]'''),
      )[today]!;
      expect(metrics.spo2Average, 95);
      expect(metrics.spo2Lowest, 89);
      expect(metrics.respirationWaking, 14.5);
      expect(metrics.bodyBatteryCharged, 62);
      expect(metrics.bodyBatteryDrained, 48);
    });

    test('Schlafphasen und Nachtwerte', () {
      final metrics = GarminMetricsParser.sleep(
        JsonValue.parse('''
          {"dailySleepDTO": {"calendarDate": "2026-10-22", "sleepTimeSeconds": 27000, "deepSleepSeconds": 5400,
            "lightSleepSeconds": 14400, "remSleepSeconds": 7200, "awakeSleepSeconds": 900,
            "averageRespirationValue": 13.2, "averageSpO2Value": 94, "lowestSpO2Value": 88, "avgSleepStress": 12}}'''),
      )[today]!;
      expect(metrics.deepSleepSeconds, 5400);
      expect(metrics.remSleepSeconds, 7200);
      expect(metrics.awakeSleepSeconds, 900);
      expect(metrics.respirationSleep, 13.2);
      expect(metrics.spo2Average, 94);
      expect(metrics.sleepStress, 12);
      expect(metrics.presentFields, contains('Schlafphasen'));
    });

    test('Fitnessalter und SpO2', () {
      final fitness = GarminMetricsParser.fitnessAge(
        JsonValue.parse('{"chronologicalAge": 36, "fitnessAge": 29.4, "components": {"vo2Max": 54.0}}'),
        today,
      )[today]!;
      expect(fitness.fitnessAge, 29.4);
      expect(fitness.vo2Max, 54);
      expect(
        GarminMetricsParser.spo2(
          JsonValue.parse('{"calendarDate": "2026-10-22", "averageSpO2": 96, "lowestSpO2": 90}'),
        )[today]?.spo2Average,
        96,
      );
    });

    test('Zeit in Zonen je Aktivität', () {
      final activities = GarminActivityParser.activities(
        JsonValue.parse('''
          [{"activityId": 1, "activityType": {"typeKey": "running"}, "hrTimeInZone_1": 300, "hrTimeInZone_2": 1800,
            "hrTimeInZone_3": 600, "hrTimeInZone_4": 0, "hrTimeInZone_5": 0},
           {"activityId": 2, "activityType": {"typeKey": "running"}, "hrTimeInZone_1": 300}]'''),
      );
      expect(activities[0].secondsInZones, [300, 1800, 600, 0, 0]);
      expect(activities[1].secondsInZones, isNull);
    });
  });

  group('Pulszonen', () {
    test('Friel-Zonen wie im Altbestand', () {
      final zones = HeartRateZoneCalculator.frielZones(threshold: 170, sport: ActivitySport.run, maxHeartRate: 190);
      expect(zones.map((zone) => zone.name), ['Z1', 'Z2', 'Z3', 'Z4', 'Z5a', 'Z5b', 'Z5c']);
      expect(zones.map((zone) => zone.low), [null, 145, 153, 162, 170, 176, 181]);
      expect(zones.map((zone) => zone.high), [144, 152, 161, 169, 175, 180, 190]);
      final coach = CoachZones(
        sport: ActivitySport.run,
        lactateThreshold: 170,
        source: '',
        isApproximate: false,
        zones: zones,
      );
      expect(coach.easyLimit, 152);
      expect(coach.fiveZones.last, HeartRateZone(name: 'Z5', use: 'Schwelle+', low: 170, high: 190));
    });

    test('Zonen der Uhr', () {
      final zones = HeartRateZoneCalculator.watchZones(
        JsonValue.parse('''
          [{"trainingMethod": "HR_MAX", "sport": "DEFAULT", "zone1Floor": 95, "zone2Floor": 114, "zone3Floor": 133,
            "zone4Floor": 152, "zone5Floor": 171, "maxHeartRateUsed": 190, "restingHeartRateUsed": 48,
            "lactateThresholdHeartRateUsed": 168},
           {"sport": "CYCLING", "zone1Floor": 90}]'''),
      );
      expect(zones.length, 1);
      expect(zones[0].maxHeartRate, 190);
      expect(zones[0].lactateThreshold, 168);
      expect(zones[0].zones.map((zone) => zone.high), [113, 132, 151, 170, 190]);
      expect(zones[0].methodText, '% HFmax');
    });

    test('Höchstpuls braucht Bestätigung', () {
      final observed = HeartRateZoneCalculator.observedMax([
        activity(1, 'running', daysAgo: 3, maxHR: 201), // Ausreißer
        activity(2, 'running', daysAgo: 10, maxHR: 186),
        activity(3, 'road_biking', daysAgo: 20, maxHR: 184),
        activity(4, 'strength_training', daysAgo: 1, maxHR: 199), // zählt nicht
        activity(5, 'running', daysAgo: 400, maxHR: 195), // zu alt
      ], today: today);
      expect(observed.confirmed, 186);
      expect(observed.peak, 201);
      expect(observed.count, 3);
    });

    test('eigene Werte vor Garmin', () {
      final profile = GarminProfile()..lactateThresholdHeartRate = 168;
      final activities = [
        activity(1, 'running', daysAgo: 3, maxHR: 188),
        activity(2, 'running', daysAgo: 5, maxHR: 187),
      ];
      final automatic = HeartRateZoneCalculator.report(
        activities: activities,
        watchZonesJSON: null,
        profile: profile,
        overrides: const HeartRateOverrides(),
        today: today,
      );
      expect(automatic.maxHeartRate, 188);
      expect(automatic.maxHeartRateSource, 'bestätigter Messwert (12 Monate)');
      expect(automatic.run.lactateThreshold, 168);
      expect(automatic.run.source, 'Garmin (Laktatschwelle)');
      expect(automatic.bike.isApproximate, isTrue);
      expect(automatic.hints.any((hint) => hint.startsWith('Für das Rad')), isTrue);
      final own = HeartRateZoneCalculator.report(
        activities: activities,
        watchZonesJSON: null,
        profile: profile,
        overrides: const HeartRateOverrides(maxHeartRate: 192, thresholdRun: 0, thresholdBike: 160),
        today: today,
      );
      expect(own.maxHeartRate, 192);
      expect(own.run.lactateThreshold, 168);
      expect(own.bike.lactateThreshold, 160);
      expect(own.bike.isApproximate, isFalse);
    });

    test('Schätzung ohne Schwelle', () {
      final report = HeartRateZoneCalculator.report(
        activities: [],
        watchZonesJSON: null,
        profile: null,
        overrides: const HeartRateOverrides(maxHeartRate: 190),
        today: today,
      );
      expect(report.run.lactateThreshold, 171);
      expect(report.run.isApproximate, isTrue);
      expect(report.run.source, 'Schätzung (90 % HFmax)');
    });

    test('Verteilung und Hinweis zum lockeren Anteil', () {
      const hard = <double>[0, 600, 1800, 600, 0];
      final activities = [
        for (var index = 0; index < 6; index++)
          activity(index, 'running', daysAgo: index * 3, averageHR: 160, minutes: 50, zones: hard),
      ];
      final distribution = HeartRateZoneCalculator.distribution(activities, today: today);
      expect(distribution.run?.easyPercent, 20);
      expect(distribution.run?.moderatePercent, 60);
      expect(distribution.run?.hardPercent, 20);
      expect(distribution.bike, isNull);
      expect(distribution.perWeek, isNotEmpty);
      final report = HeartRateZoneCalculator.report(
        activities: activities,
        watchZonesJSON: null,
        profile: null,
        overrides: const HeartRateOverrides(maxHeartRate: 190, thresholdRun: 170),
        today: today,
      );
      expect(report.hints.any((hint) => hint.startsWith('Laufen: 0 % der Zeit')), isTrue);
    });
  });

  group('Verläufe', () {
    test('Trend gegenüber dem Zeitraum davor', () {
      final values = [
        for (var offset = 0; offset < 14; offset++) DayValue(day: today.adding(-offset), value: offset < 7 ? 60 : 50),
      ];
      final trend = MetricTrend(values, days: 7, today: today);
      expect(trend.points.length, 7);
      expect(trend.latest?.day, today);
      expect(trend.average, 60);
      expect(trend.previousAverage, 50);
      expect(trend.change, 10);
      expect(MetricTrend([], days: 7, today: today).change, isNull);
    });

    test('Wochenumfang und VO2max', () {
      final activities = [
        activity(1, 'running', daysAgo: 0, km: 10, vo2: 52),
        activity(2, 'running', daysAgo: 1, km: 8, vo2: 53),
        activity(3, 'running', daysAgo: 14, km: 12),
        activity(4, 'virtual_ride', daysAgo: 7, km: 30, vo2: 55),
      ];
      final history = WeekVolume.history(activities, today: today, weeks: 4);
      expect(history.length, 4);
      expect(history.last.monday, today.adding(-today.weekdayIndex));
      expect(history.map((week) => week.volume.kilometers[ActivitySport.run] ?? 0), [0, 12, 0, 18]);
      expect(VO2MaxHistory.values(activities, sport: ActivitySport.run).map((value) => value.value), [53, 52]);
      expect(VO2MaxHistory.values(activities, sport: ActivitySport.bike).length, 1);
    });
  });
}

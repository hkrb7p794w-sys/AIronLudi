// Port von HealthImportTests.swift und HealthRecordingTests.swift. Berlin im Oktober 2026 (vor dem 25.10.) entspricht
// UTC+2. Der Fall `reportWorksLikeForAGarminFile` folgt mit `ActivityReportBuilder`.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const berlin = Duration(hours: 2);

DateTime date(int day, int hour, [int minute = 0]) => DateTime.utc(2026, 10, day, hour, minute).subtract(berlin);

HealthRecordingInput run({HealthInterval? pause}) {
  final input = HealthRecordingInput(start: 1000, end: 2200);
  for (var time = 1000.0; time < 2200; time += 3) {
    final paused = pause != null && pause.start <= time && time < pause.end;
    if (!paused) input.distance.add(HealthAmount(start: time, end: time + 3, value: 9));
  }
  input.heartRate = [
    for (var time = 1000.0; time <= 2200; time += 5) HealthSample(time: time, value: time < 1600 ? 140 : 150),
  ];
  if (pause != null) input.pauses = [pause];
  return input;
}

void main() {
  group('Health-Import', () {
    test('Tageswerte werden geprüft und umgerechnet', () {
      final values = HealthDayValues(const CalendarDay(2026, 10, 20))
        ..restingHeartRate = 52
        ..hrvSDNN = 48
        ..steps = 9876
        ..activeKilocalories = 640
        ..basalKilocalories = 1750
        ..oxygenSaturation = 0.97
        ..vo2Max = 300;
      final metrics = HealthImport.metrics(values, includeHRV: false);
      expect(metrics.restingHeartRate, 52);
      expect(metrics.hrvLastNightAverage, isNull);
      expect(metrics.totalKilocalories, 2390);
      expect(metrics.spo2Average, 97);
      expect(metrics.vo2Max, isNull);
      expect(HealthImport.metrics(values, includeHRV: true).hrvLastNightAverage, 48);
    });

    test('Garmin-Werte gewinnen', () {
      const day = CalendarDay(2026, 10, 20);
      final garmin = DailyMetrics(day)..restingHeartRate = 50;
      final health = DailyMetrics(day)
        ..restingHeartRate = 55
        ..steps = 8000;
      final filled = HealthImport.fill(garmin, health);
      expect(filled.restingHeartRate, 50);
      expect(filled.steps, 8000);
      expect(HealthImport.fill(null, health), same(health));
    });

    test('Schlaf: Phasen der Uhr bevorzugt, Nickerchen zählen nicht', () {
      const watch = 'com.apple.health.watch';
      final samples = [
        // iPhone: nur unspezifischer Schlaf
        SleepSample(start: date(20, 22, 30), end: date(21, 7), stage: SleepStage.asleep, source: 'iphone'),
        SleepSample(start: date(20, 23), end: date(21, 1), stage: SleepStage.core, source: watch),
        SleepSample(start: date(21, 1), end: date(21, 2), stage: SleepStage.deep, source: watch),
        SleepSample(start: date(21, 2), end: date(21, 2, 15), stage: SleepStage.awake, source: watch),
        SleepSample(start: date(21, 2, 15), end: date(21, 5), stage: SleepStage.core, source: watch),
        SleepSample(start: date(21, 5), end: date(21, 6, 30), stage: SleepStage.rem, source: watch),
        // Nickerchen am Nachmittag
        SleepSample(start: date(21, 14), end: date(21, 15), stage: SleepStage.core, source: watch),
      ];
      final nights = HealthImport.sleep(samples, utcOffset: berlin);
      final night = nights[const CalendarDay(2026, 10, 21)];
      expect(nights.length, 1);
      expect(night?.sleepSeconds, 26100);
      expect(night?.deepSleepSeconds, 3600);
      expect(night?.remSleepSeconds, 5400);
      expect(night?.awakeSleepSeconds, 900);
      expect(night?.sleepStartMinutes, 1380);
      expect(night?.sleepEndMinutes, 390);
    });

    test('überlappende Proben zählen einmal', () {
      final samples = [
        SleepSample(start: date(20, 23), end: date(21, 3), stage: SleepStage.asleep, source: 'a'),
        SleepSample(start: date(21, 2), end: date(21, 6), stage: SleepStage.asleep, source: 'a'),
      ];
      expect(HealthImport.asleepSeconds(samples), 25200);
    });

    test('Workouts ohne Doppel mit Garmin und der eigenen App', () {
      final garminRun = GarminActivity(123)
        ..typeKey = 'running'
        ..startLocal = '2026-10-20 18:02:00'
        ..durationSeconds = 3000;
      final run = HealthWorkout(
        uuid: newUuid(),
        typeKey: 'running',
        start: date(20, 18),
        end: date(20, 18, 50),
        distanceMeters: 10000,
        sourceName: 'Garmin Connect',
        sourceBundle: 'com.garmin.connect.mobile',
      );
      final ride = HealthWorkout(
        uuid: newUuid(),
        typeKey: 'cycling',
        start: date(21, 7),
        end: date(21, 8),
        distanceMeters: 30000,
        kilocalories: 600,
        averageHeartRate: 140,
        sourceName: 'Apple Watch',
        sourceBundle: 'com.apple.health',
      );
      final gym = HealthWorkout(
        uuid: newUuid(),
        typeKey: 'strength_training',
        start: date(22, 18),
        end: date(22, 19),
        sourceName: 'Coach',
        sourceBundle: 'io.github.hkrb7p794w.coach',
      );
      final result = HealthImport.newActivities(
        [run, ride, gym],
        existing: [garminRun],
        ownBundle: 'io.github.hkrb7p794w.coach',
        utcOffset: berlin,
      );
      expect(result.length, 1);
      final activity = result[0];
      expect(activity.id, lessThan(0));
      expect(activity.id, HealthImport.activityID(ride.uuid));
      expect(activity.sport, ActivitySport.bike);
      expect(activity.startLocal, '2026-10-21 07:00:00');
      expect(activity.day, const CalendarDay(2026, 10, 21));
      expect(activity.name, 'Radfahren · Apple Watch');
      expect((activity.averageSpeed! * 100).roundToDouble() / 100, 8.33);
      expect(ManualActivity.isManual(activity.id), isFalse);
    });

    test('Wägungen: letzte je Tag, Garmin hat Vorrang', () {
      final entries = HealthImport.weights([
        (date: date(20, 7), kilograms: 80.04),
        (date: date(20, 21), kilograms: 81.0),
        (date: date(21, 7), kilograms: 79.6),
      ], utcOffset: berlin);
      expect(entries.map((entry) => entry.kilograms), [81, 79.6]);
      const day = CalendarDay(2026, 10, 21);
      final merged = WeightTrend.merged([
        ...entries,
        const WeightEntry(day: day, kilograms: 79.9, source: WeightSource.garmin),
      ]);
      expect(merged.last.kilograms, 79.9);
    });
  });

  group('Aufzeichnung aus Health', () {
    test('Messpunkte im 5-Sekunden-Raster', () {
      final fit = HealthRecording.fit(run());
      expect(fit.records.length, 241);
      expect(fit.records.first.distance, 0);
      expect((fit.records.last.distance! - 3600).abs(), lessThan(1));
      expect(fit.records[10].heartRate, 140);
      expect(fit.records[200].heartRate, 150);
      expect(fit.records.skip(1).every((record) => ((record.speed ?? 0) - 3).abs() < 0.01), isTrue);
    });

    test('Pausen bleiben eine Lücke', () {
      final fit = HealthRecording.fit(run(pause: const HealthInterval(start: 1300, end: 1600)));
      expect(fit.records.any((record) => record.timestamp >= 1300 && record.timestamp < 1600), isFalse);
    });

    test('Runden mit Zeit, Strecke und Puls', () {
      final input = run()
        ..laps = const [HealthInterval(start: 1000, end: 1600), HealthInterval(start: 1600, end: 2200)];
      final laps = HealthRecording.fit(input).laps;
      expect(laps.length, 2);
      expect(laps[0].timerSeconds, 600);
      expect((laps[0].distanceMeters! - 1800).abs(), lessThan(1));
      expect((laps[0].averageSpeed! - 3).abs(), lessThan(0.01));
      expect(laps[0].averageHeartRate, lessThan(141));
      expect(laps[1].maxHeartRate, 150);
    });

    test('Orte und veraltete Werte', () {
      final input = HealthRecordingInput(start: 0, end: 120)
        ..heartRate = const [HealthSample(time: 0, value: 120)]
        ..locations = const [
          HealthLocation(time: 0, latitude: 52.37, longitude: 5.22, altitude: 3),
          HealthLocation(time: 100, latitude: 52.38, longitude: 5.23, altitude: 4),
        ];
      final fit = HealthRecording.fit(input);
      expect(fit.records.length, 25);
      expect(fit.records[2].heartRate, 120);
      // Nach 30 s ohne neuen Wert bleibt die Stelle leer statt einen alten Puls fortzuschreiben.
      expect(fit.records[10].heartRate, isNull);
      expect(fit.records[0].latitude, 52.37);
      expect(fit.records[10].latitude, isNull);
      expect(fit.records[20].altitude, 4);
      expect(fit.records[0].distance, isNull);
      expect(HealthRecording.fit(HealthRecordingInput(start: 5, end: 5)).records, isEmpty);
    });
  });
}

// Port von SleepCoachTests.swift, HealthAccessDiagnosisTests.swift und BodyBatteryTests.swift (Body-Battery-Kurve,
// Tageszusammenfassung, Analyse und persönlicher Bereich; Readiness steht in garmin_test.dart).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const april21 = CalendarDay(2026, 4, 21);

void main() {
  group('Schlaf-Coach', () {
    const today = CalendarDay(2026, 11, 10);
    List<DailyMetrics> nights(List<double> hours, {List<double>? starts}) => [
      for (var index = 0; index < hours.length; index++)
        DailyMetrics(today.adding(-index))
          ..sleepSeconds = hours[index] * 3600
          ..sleepStartMinutes = starts?[index],
    ];

    test('genug Schlaf: Zeiten beibehalten', () {
      final report = SleepCoach.report(
        days: nights([8, 8.2, 7.9, 8.1, 8]),
        settings: SleepSettings(),
        goal: null,
        today: today,
      )!;
      expect(report.tonightMinutes, 480);
      // Aufstehen 6:30, 8 Stunden Schlaf, 15 Minuten Einschlafen → 22:15.
      expect(SleepCoach.clock(report.bedtimeMinutes), '22:15');
      expect(report.tips.map((tip) => tip.id), ['good']);
    });

    test('kurze Nächte: früher ins Bett', () {
      final report = SleepCoach.report(
        days: nights([6, 6.5, 6, 6.2, 6.4, 6, 6.3]),
        settings: SleepSettings(),
        goal: FitnessGoal.loseWeight,
        today: today,
      )!;
      expect(report.averageHours, lessThan(7));
      expect(report.shortNights, 7);
      // Defizit über 10 Stunden → höchstens 60 Minuten extra.
      expect(report.tonightMinutes, 540);
      expect(SleepCoach.clock(report.bedtimeMinutes), '21:15');
      expect(report.tips.map((tip) => tip.id), ['short', 'weight']);
    });

    test('unregelmäßige Einschlafzeiten', () {
      // Einschlafzeiten zwischen 22:00 und 1:30.
      final report = SleepCoach.report(
        days: nights([8, 8, 8, 8, 8, 8], starts: [1320, 90, 1350, 60, 1330, 45]),
        settings: SleepSettings(),
        goal: null,
        today: today,
      )!;
      expect(report.bedtimeSpreadMinutes, greaterThan(SleepCoach.irregularMinutes));
      expect(report.tips.any((tip) => tip.id == 'regular'), isTrue);
    });

    test('braucht drei Nächte, Einstellungen werden begrenzt', () {
      expect(SleepCoach.report(days: nights([8, 8]), settings: SleepSettings(), goal: null, today: today), isNull);
      final decoded = SleepSettings.fromJson(jsonDecode('{"targetHours": 12, "wakeHour": 30}'));
      expect(decoded.targetHours, 9);
      expect(decoded.wakeHour, 23);
      final settings = SleepSettings()
        ..usesFreeDayTime = true
        ..state = GermanState.by
        ..alarm = SleepAlarm(minutes: 300, onlyDay: today);
      final again = SleepSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
      expect(again.state, GermanState.by);
      expect(again.alarm, settings.alarm);
      expect(again.wakeMinutesOn(today), 300);
    });

    test('freier Tag und Feiertag', () {
      final settings = SleepSettings()
        ..usesFreeDayTime = true
        ..state = GermanState.by
        ..freeWakeHour = 9;
      // 24.12.2026 ist Donnerstag, der 25.12. ein Feiertag.
      final report = SleepCoach.report(
        days: [
          for (var index = 0; index < 4; index++)
            DailyMetrics(const CalendarDay(2026, 12, 24).adding(-index))..sleepSeconds = 8 * 3600,
        ],
        settings: settings,
        goal: null,
        today: const CalendarDay(2026, 12, 24),
      )!;
      expect(report.nextDayIsFree, isTrue);
      expect(report.nextHoliday, '1. Weihnachtstag');
      expect(report.tips.first.id, 'free');
      expect(report.tips.any((tip) => tip.id == 'social-jetlag'), isTrue);
      expect(report.nextWakeMinutes, 540);
    });

    test('Schlafzeiten aus Garmin Connect', () {
      // 2026-11-10 23:15 Ortszeit als UTC-kodierte Millisekunden.
      const start = 1794352500000.0;
      final json = JsonValue({
        'dailySleepDTO': {
          'calendarDate': '2026-11-11',
          'sleepTimeSeconds': 27000,
          'sleepStartTimestampLocal': start,
          'sleepEndTimestampLocal': start + 27000000,
        },
      });
      final metrics = GarminMetricsParser.sleep(json)[const CalendarDay(2026, 11, 11)];
      expect(metrics?.sleepStartMinutes, 1395);
      expect(metrics?.sleepEndMinutes, 405);
    });
  });

  group('Feiertage', () {
    test('Ostern und Feiertage je Bundesland', () {
      expect(GermanHolidays.easter(2026), const CalendarDay(2026, 4, 5));
      expect(GermanHolidays.easter(2027), const CalendarDay(2027, 3, 28));
      expect(GermanHolidays.name(const CalendarDay(2026, 6, 4), state: GermanState.by), 'Fronleichnam');
      expect(GermanHolidays.name(const CalendarDay(2026, 6, 4), state: GermanState.be), isNull);
      expect(GermanHolidays.name(const CalendarDay(2026, 11, 18), state: GermanState.sn), 'Buß- und Bettag');
      expect(GermanHolidays.name(const CalendarDay(2026, 3, 8), state: GermanState.be), 'Frauentag');
      expect(GermanHolidays.name(const CalendarDay(2017, 10, 31), state: GermanState.ni), isNull);
      expect(GermanHolidays.name(const CalendarDay(2026, 10, 31), state: GermanState.ni), 'Reformationstag');
    });
  });

  group('Weckplan', () {
    test('Aufstehzeit, Schlafdauer und Tageslabel', () {
      expect(WakePlan.wakeIfSleepingNow(nowMinutes: 23 * 60 + 2, sleepMinutes: 480).text, '7:20');
      expect(WakePlan.sleepMinutes(bedtimeMinutes: 22 * 60 + 15, wake: WakeTime(hour: 6, minute: 30)), 480);
      expect(WakeTime(hour: 30, minute: -5), WakeTime(hour: 23, minute: 0));
      final now = DateTime(2026, 11, 10, 22);
      final next = WakePlan.nextDate(WakeTime(hour: 6, minute: 30), now: now);
      expect(next, DateTime(2026, 11, 11, 6, 30));
      expect(WakePlan.dayLabel(next, now: now), 'morgen');
      expect(WakePlan.dayLabel(DateTime(2026, 11, 10, 23), now: now), 'heute');
      expect(WakePlan.dayLabel(DateTime(2026, 11, 13, 6), now: now), 'am Freitag');
      expect(WakeRepeat.weekdays.calendarWeekdays, [2, 3, 4, 5, 6]);
    });
  });

  group('Zugriff auf Health', () {
    const missingEntitlement = HealthErrorInfo(
      domain: 'com.apple.healthkit',
      code: 4,
      message: 'Missing com.apple.developer.healthkit entitlement.',
    );

    test('Gerät ohne Health gewinnt', () {
      expect(
        HealthAccessDiagnosis.evaluate(
          isHealthDataAvailable: false,
          authorizationError: missingEntitlement,
          workoutShareStatus: WorkoutShareStatus.authorized,
          readableWorkouts: 3,
        ),
        HealthAccessDiagnosis.unavailable,
      );
    });

    test('fehlendes Entitlement aus Anfrage oder Abfrage', () {
      final fromAuthorization = HealthAccessDiagnosis.evaluate(
        isHealthDataAvailable: true,
        authorizationError: missingEntitlement,
        workoutShareStatus: null,
        readableWorkouts: null,
      );
      expect(fromAuthorization, HealthAccessDiagnosis.missingEntitlement);
      expect(fromAuthorization.isUsable, isFalse);
      expect(
        HealthAccessDiagnosis.evaluate(
          isHealthDataAvailable: true,
          authorizationError: null,
          workoutShareStatus: WorkoutShareStatus.notDetermined,
          readableWorkouts: null,
          queryError: missingEntitlement,
        ),
        HealthAccessDiagnosis.missingEntitlement,
      );
    });

    test('andere Fehler, Freigabe und Status', () {
      expect(
        HealthAccessDiagnosis.evaluate(
          isHealthDataAvailable: true,
          authorizationError: const HealthErrorInfo(
            domain: 'com.apple.healthkit',
            code: 3,
            message: 'Invalid argument',
          ),
          workoutShareStatus: null,
          readableWorkouts: null,
        ),
        const HealthFailed('Invalid argument (com.apple.healthkit 3)'),
      );
      final working = HealthAccessDiagnosis.evaluate(
        isHealthDataAvailable: true,
        authorizationError: null,
        workoutShareStatus: WorkoutShareStatus.authorized,
        readableWorkouts: 12,
      );
      expect(working, const HealthWorking(12));
      expect(working.isUsable, isTrue);
      expect(working.detail, contains('12 Workouts'));
      expect(
        HealthAccessDiagnosis.evaluate(
          isHealthDataAvailable: true,
          authorizationError: null,
          workoutShareStatus: WorkoutShareStatus.authorized,
          readableWorkouts: 7,
          queryError: const HealthErrorInfo(domain: 'com.apple.healthkit', code: 5, message: 'Not determined'),
        ),
        const HealthWorking(null),
      );
      for (final (status, expected) in [
        (WorkoutShareStatus.denied, HealthAccessDiagnosis.denied),
        (WorkoutShareStatus.notDetermined, HealthAccessDiagnosis.notDetermined),
      ]) {
        expect(
          HealthAccessDiagnosis.evaluate(
            isHealthDataAvailable: true,
            authorizationError: null,
            workoutShareStatus: status,
            readableWorkouts: null,
          ),
          expected,
        );
      }
    });
  });

  group('Body Battery', () {
    test('Bericht mit Tag unter date: Verlauf in Ortszeit', () {
      final response = JsonValue.parse('''
        [{"date": "2026-04-21", "charged": 58, "drained": 32,
          "startTimestampGMT": "2026-04-20T22:00:00.0", "startTimestampLocal": "2026-04-21T00:00:00.0",
          "bodyBatteryValuesArray": [[1776722400000, 30], [1776744600000, 80], [1776745200000, 82],
            [1776783600000, 45], [1776783700000, -1]]}]''');
      final metrics = GarminMetricsParser.bodyBattery(response)[april21]!;
      expect(metrics.bodyBatteryCharged, 58);
      expect(metrics.bodyBatteryDrained, 32);
      expect(metrics.bodyBatteryHigh, 82);
      expect(metrics.bodyBatteryLow, 30);
      expect(metrics.bodyBatteryLatest, 45);
      // 22:00 GMT = 0:00 Ortszeit (+2 h), 4:10 → Viertelstunde 6:00, 4:20 → 6:15, 15:00 → 17:00.
      expect(metrics.bodyBatteryCurve, const [
        BodyBatterySample(minute: 0, value: 30),
        BodyBatterySample(minute: 360, value: 80),
        BodyBatterySample(minute: 375, value: 82),
        BodyBatterySample(minute: 1020, value: 45),
      ]);
    });

    test('Beschreibungsliste verschiebt den Wert', () {
      final response = JsonValue.parse('''
        [{"date": "2026-04-21",
          "bodyBatteryValueDescriptorDTOList": [
            {"bodyBatteryValueDescriptorIndex": 0, "bodyBatteryValueDescriptorKey": "timestamp"},
            {"bodyBatteryValueDescriptorIndex": 1, "bodyBatteryValueDescriptorKey": "bodyBatteryStatus"},
            {"bodyBatteryValueDescriptorIndex": 2, "bodyBatteryValueDescriptorKey": "bodyBatteryLevel"}],
          "bodyBatteryValuesArray": [[1776744600000, "MEASURED", 40], [1776783600000, "MEASURED", 70]]}]''');
      final metrics = GarminMetricsParser.bodyBattery(response, offsetSeconds: (_) => 0)[april21]!;
      expect(metrics.bodyBatteryCurve?.map((sample) => sample.value), [40, 70]);
      expect(metrics.bodyBatteryCurve?.map((sample) => sample.minute), [240, 900]);
    });

    test('Tageszusammenfassung mit Aufwachwert, Ruhekalorien und Pulsbereich', () {
      final metrics = GarminMetricsParser.dailySummaries(
        JsonValue.parse(
          '{"calendarDate": "2026-04-21", "bodyBatteryAtWakeTime": 74, "bmrKilocalories": 1720, '
          '"minHeartRate": 44, "maxHeartRate": 162}',
        ),
      )[april21]!;
      expect(metrics.bodyBatteryAtWake, 74);
      expect(metrics.restingKilocalories, 1720);
      expect(metrics.minHeartRate, 44);
      expect(metrics.maxHeartRate, 162);
    });

    test('Health-Import behält die Ruhekalorien', () {
      final values = HealthDayValues(april21)
        ..activeKilocalories = 600
        ..basalKilocalories = 1700;
      final metrics = HealthImport.metrics(values, includeHRV: false);
      expect(metrics.restingKilocalories, 1700);
      expect(metrics.totalKilocalories, 2300);
    });

    test('Aufwachwert: Garmin, dann Verlauf zur Aufwachzeit', () {
      final metrics = DailyMetrics(april21)
        ..bodyBatteryCurve = const [
          BodyBatterySample(minute: 300, value: 70),
          BodyBatterySample(minute: 405, value: 78),
          BodyBatterySample(minute: 600, value: 85),
        ]
        ..sleepEndMinutes = 410;
      expect(BodyBatteryAnalysis.wakeValue(metrics), 78);
      metrics.sleepEndMinutes = null;
      expect(BodyBatteryAnalysis.wakeValue(metrics), 85);
      metrics.bodyBatteryAtWake = 76;
      expect(BodyBatteryAnalysis.wakeValue(metrics), 76);
      expect(BodyBatteryAnalysis.wakeValue(DailyMetrics(april21)), isNull);
    });

    test('ohne Garmin leer', () {
      final day = DailyMetrics(april21)..restingHeartRate = 50;
      final summary = BodyBatteryAnalysis.summary(days: [day], today: april21);
      expect(summary.hasData, isFalse);
      expect(summary.relations, isEmpty);
    });

    test('Verlauf, Bereich und Zusammenhänge', () {
      final days = [
        for (var offset = 0; offset < 14; offset++)
          () {
            final long = offset.isEven;
            return DailyMetrics(april21.adding(-offset))
              ..sleepSeconds = long ? 8 * 3600 : 5.5 * 3600
              ..bodyBatteryCharged = long ? 70 : 40
              ..stressAverage = long ? 20 : 45
              ..bodyBatteryDrained = long ? 50 : 75
              ..bodyBatteryHigh = long ? 90 : 60
              ..bodyBatteryAtWake = long ? 88 : 58;
          }(),
      ];
      final summary = BodyBatteryAnalysis.summary(days: days, today: april21);
      expect(summary.history.length, 14);
      expect(summary.wake, 88);
      // 13 Vortage: 6 lange (88) und 7 kurze (58) Nächte.
      final norm = summary.wakeNorm!;
      expect(norm.count, 13);
      expect(norm.mean > 70 && norm.mean < 73, isTrue);
      expect(summary.relations.map((relation) => relation.id), ['sleep', 'stress']);
      expect(summary.relations[0].text, contains('um 70'));
      expect(summary.relations[1].text, contains('75'));
    });

    test('Zusammenhänge brauchen genug Tage je Gruppe', () {
      final history = [
        for (var offset = 0; offset < 4; offset++)
          BodyBatteryDay(
            day: april21.adding(-offset),
            high: 80,
            low: 20,
            wake: 70,
            charged: 60,
            drained: 50,
            sleepHours: 8,
            stress: 30,
          ),
      ];
      expect(BodyBatteryAnalysis.relations(history), isEmpty);
      expect(BodyBatteryAnalysis.band(25), 'niedrig');
      expect(BodyBatteryAnalysis.band(76), 'sehr hoch');
    });

    test('persönlicher Bereich braucht sieben Tage', () {
      expect(PersonalNorm.of([50, 51, 52]), isNull);
      final norm = PersonalNorm.of([48, 50, 52, 49, 51, 50, 50])!;
      expect(norm.mean, 50);
      expect(norm.position(44), NormPosition.below);
      expect(norm.position(50.5), NormPosition.within);
      expect(norm.position(56), NormPosition.above);
      // Heute zählt nicht mit.
      final days = [
        for (var offset = 0; offset < 8; offset++)
          DailyMetrics(april21.adding(-offset))..restingHeartRate = offset == 0 ? 80 : 50,
      ];
      expect(PersonalNorm.fromDays(days, today: april21, field: (metrics) => metrics.restingHeartRate)?.mean, 50);
    });
  });
}

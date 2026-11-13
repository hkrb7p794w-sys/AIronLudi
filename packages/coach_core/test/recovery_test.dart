// Port von RecommendationTests (CoachTests.swift), FitnessFormTests.swift, den Tageswert-Fällen aus
// GarminParsingTests.swift, den Ampel-Fällen aus Phase77Tests.swift, LoadCheckTests (SafeguardTests.swift), den
// Laufbelastungs-Fällen aus Phase78Tests.swift und den Belastungs-/Planzahl-Fällen aus PersonalizationTests.swift.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

DailyMetrics metrics({String? hrv, double? weekly, double? low, double? rhr, double? sleepHours}) =>
    DailyMetrics(const CalendarDay(2026, 10, 23))
      ..hrvStatus = hrv
      ..hrvWeeklyAverage = weekly
      ..hrvBaselineLow = low
      ..restingHeartRate = rhr
      ..sleepSeconds = sleepHours == null ? null : sleepHours * 3600;

void main() {
  group('Tagesampel (RecommendationTests)', () {
    test('ohne Daten normal', () {
      final result = RecoveryEvaluator.evaluate(metrics(), restingHeartRate7DayAverage: null);
      expect(result.level, RecoveryLevel.normal);
      expect(result.reasons, ['keine Erholungswerte auffällig']);
    });

    test('niedrige HRV heißt Ruhetag', () {
      final result = RecoveryEvaluator.evaluate(metrics(hrv: 'LOW'), restingHeartRate7DayAverage: null);
      expect(result.level, RecoveryLevel.pause);
      expect(result.label, 'Ruhetag oder sehr locker');
    });

    test('unausgeglichen unter der Baseline heißt locker', () {
      final below = RecoveryEvaluator.evaluate(
        metrics(hrv: 'UNBALANCED', weekly: 50, low: 55),
        restingHeartRate7DayAverage: null,
      );
      expect(below.level, RecoveryLevel.locker);
      final above = RecoveryEvaluator.evaluate(
        metrics(hrv: 'UNBALANCED', weekly: 75, low: 55),
        restingHeartRate7DayAverage: null,
      );
      expect(above.level, RecoveryLevel.normal);
      expect(above.reasons.first, contains('über der Baseline'));
    });

    test('erhöhter Ruhepuls', () {
      final result = RecoveryEvaluator.evaluate(metrics(hrv: 'BALANCED', rhr: 55), restingHeartRate7DayAverage: 49.6);
      expect(result.level, RecoveryLevel.locker);
      expect(result.reasons, contains('Ruhepuls 55 bpm, 5 über deinem 7-Tage-Schnitt'));
      expect(
        RecoveryEvaluator.evaluate(metrics(rhr: 54), restingHeartRate7DayAverage: 49.6).level,
        RecoveryLevel.normal,
      );
    });

    test('Schlafgrenzen', () {
      for (final (hours, expected) in [
        (4.5, RecoveryLevel.pause),
        (5.5, RecoveryLevel.locker),
        (6.0, RecoveryLevel.normal),
      ]) {
        expect(
          RecoveryEvaluator.evaluate(metrics(sleepHours: hours), restingHeartRate7DayAverage: null).level,
          expected,
          reason: '$hours h',
        );
      }
    });

    test('das schlechteste Signal gewinnt', () {
      final result = RecoveryEvaluator.evaluate(
        metrics(hrv: 'POOR', rhr: 60, sleepHours: 5.5),
        restingHeartRate7DayAverage: 50,
        readinessScore: 40,
      );
      expect(result.level, RecoveryLevel.pause);
      expect(result.reasons.length, 4);
      expect(result.reasons, contains('kurzer Schlaf (5,5 h)'));
      expect(result.reasons, contains('Readiness 40 (Garmin-Stufe „Low“)'));
    });

    test('Mittelwert über die Tage vor heute', () {
      const today = CalendarDay(2026, 10, 23);
      final history = [
        for (var offset = 0; offset <= 8; offset++)
          DailyMetrics(today.adding(-offset))..restingHeartRate = 50.0 + offset,
      ];
      // Tage 1…7 vor heute: 51…57 → 54
      expect(RecoveryEvaluator.average((day) => day.restingHeartRate, history, from: 1, to: 7, today: today), 54);
      expect(RecoveryEvaluator.average((day) => day.restingHeartRate, [], from: 1, to: 7, today: today), isNull);
    });
  });

  group('Ampel für heute (Phase77Tests)', () {
    const today = CalendarDay(2026, 11, 9);

    test('nur Schritte ergeben keine Ampel', () {
      final state = RecoveryEvaluator.today(days: [DailyMetrics(today)..steps = 8000], form: [], today: today);
      expect(state.isKnown, isFalse);
      expect(state.level, isNull);
    });

    test('Ruhepuls zählt nur mit Schnitt', () {
      final day = DailyMetrics(today)..restingHeartRate = 50;
      expect(RecoveryEvaluator.today(days: [day], form: [], today: today).isKnown, isFalse);
      final week = [
        for (var offset = 1; offset <= 7; offset++) DailyMetrics(today.adding(-offset))..restingHeartRate = 50,
      ];
      expect(RecoveryEvaluator.today(days: [day, ...week], form: [], today: today).level, RecoveryLevel.normal);
    });

    test('ohne Nachtwerte von heute gilt die letzte Nacht', () {
      final morning = DailyMetrics(today)..steps = 300;
      final night = DailyMetrics(today.adding(-1))..sleepSeconds = 4 * 3600;
      final state = RecoveryEvaluator.today(days: [morning, night], form: [], today: today);
      expect(state.metrics?.day, night.day);
      expect(state.level, RecoveryLevel.pause);
    });

    test('kurzer Schlaf wird nicht aufgerundet', () {
      final result = RecoveryEvaluator.evaluate(
        DailyMetrics(today)..sleepSeconds = (4 * 60 + 57) * 60,
        restingHeartRate7DayAverage: null,
      );
      expect(result.reasons.first, 'nur 4,9 h Schlaf');
    });

    test('sehr negative Form ergibt höchstens locker', () {
      final start = today.adding(-60);
      final activities = [
        for (var offset = 0; offset < 54; offset++)
          GarminActivity(offset)
            ..typeKey = 'running'
            ..startLocal = '${start.adding(offset).iso} 07:00:00'
            ..trainingLoad = 40,
        for (var offset = 54; offset <= 60; offset++)
          GarminActivity(offset)
            ..typeKey = 'running'
            ..startLocal = '${start.adding(offset).iso} 07:00:00'
            ..trainingLoad = 250,
      ];
      final state = RecoveryEvaluator.todayFromActivities(
        days: [DailyMetrics(today)..sleepSeconds = 8 * 3600],
        activities: activities,
        today: today,
      );
      expect(state.level, RecoveryLevel.locker);
      expect(state.recommendation.isLimitedByForm, isTrue);
      // Eine Pause bleibt eine Pause.
      final pause = RecoveryEvaluator.today(
        days: [DailyMetrics(today)..sleepSeconds = 4 * 3600],
        form: FitnessForm.seriesUntil(activities, today: today),
        today: today,
      );
      expect(pause.level, RecoveryLevel.pause);
    });
  });

  group('Fitness und Form (FitnessFormTests)', () {
    const start = CalendarDay(2026, 9, 1);
    GarminActivity activity(CalendarDay day, double load, int id) => GarminActivity(id)
      ..typeKey = 'running'
      ..startLocal = '${day.iso} 07:00:00'
      ..trainingLoad = load;

    test('gleiche Belastung pendelt sich ein, Form null', () {
      final activities = [for (var offset = 0; offset < 120; offset++) activity(start.adding(offset), 100, offset)];
      final points = FitnessForm.series(activities, from: start, to: start.adding(119));
      final last = points.last;
      expect((last.fitness - 100).abs(), lessThan(10));
      expect((last.fatigue - 100).abs(), lessThan(0.5));
      expect(last.form.abs(), lessThan(10));
      expect(FitnessForm.isReliable(points), isTrue);
    });

    test('Ruhetage machen frisch', () {
      // Sechs Wochen Training, dann eine Woche Pause: Ermüdung fällt schneller als Fitness.
      final activities = [for (var offset = 0; offset < 42; offset++) activity(start.adding(offset), 80, offset)];
      final last = FitnessForm.series(activities, from: start, to: start.adding(49)).last;
      expect(last.fatigue, lessThan(last.fitness));
      expect(last.form, greaterThan(0));
      expect(FormZone.of(last.formPercent!), FormZone.fresh);
    });

    test('Belastungsspitze ist Aufbau oder sehr hoch', () {
      final activities = [
        for (var offset = 0; offset < 42; offset++) activity(start.adding(offset), 50, offset),
        for (var offset = 42; offset < 49; offset++) activity(start.adding(offset), 150, offset),
      ];
      final percent = FitnessForm.series(activities, from: start, to: start.adding(49)).last.formPercent!;
      expect([FormZone.productive, FormZone.high], contains(FormZone.of(percent)));
    });

    test('Zonen und leerer Verlauf', () {
      expect(FormZone.of(10), FormZone.fresh);
      expect(FormZone.of(0), FormZone.neutral);
      expect(FormZone.of(-20), FormZone.productive);
      expect(FormZone.of(-40), FormZone.high);
      expect(FitnessForm.seriesUntil([], today: start), isEmpty);
    });
  });

  group('Garmin-Tageswerte (GarminParsingTests)', () {
    const day = CalendarDay(2026, 10, 22);

    test('Tageszusammenfassung', () {
      final map = GarminMetricsParser.dailySummaries(
        JsonValue.parse('''
          {"data": [
            {"calendarDate": "2026-10-22", "totalSteps": 10234, "restingHeartRate": 48,
             "averageStressLevel": 27, "bodyBatteryHighestValue": 88, "bodyBatteryLowestValue": 21,
             "bodyBatteryMostRecentValue": 35, "activeKilocalories": 812, "totalKilocalories": 2650},
            {"calendarDate": "2026-10-21", "totalSteps": 8000, "restingHeartRate": 50, "averageStressLevel": -1}
          ]}'''),
      );
      expect(map.length, 2);
      final today = map[day]!;
      expect(today.restingHeartRate, 48);
      expect(today.steps, 10234);
      expect(today.stressAverage, 27);
      expect(today.bodyBatteryHigh, 88);
      expect(today.bodyBatteryLow, 21);
      expect(today.bodyBatteryLatest, 35);
      expect(today.activeKilocalories, 812);
      expect(map[day.adding(-1)]?.stressAverage, isNull);
    });

    test('HRV eines Tages mit Baseline', () {
      final metrics = GarminMetricsParser.hrv(
        JsonValue.parse('''
          {"userProfilePk": 1, "hrvSummary": {"calendarDate": "2026-10-22", "weeklyAvg": 62, "lastNightAvg": 58,
           "status": "balanced", "baseline": {"lowUpper": 50, "balancedLow": 55, "balancedUpper": 70}},
           "hrvReadings": [{"hrvValue": 57, "readingTimeGMT": "2026-10-22T01:00:00.0"}]}'''),
      )[day]!;
      expect(metrics.hrvLastNightAverage, 58);
      expect(metrics.hrvWeeklyAverage, 62);
      expect(metrics.hrvStatus, 'BALANCED');
      expect(metrics.hrvBaselineLow, 55);
      expect(metrics.hrvBaselineHigh, 70);
    });

    test('HRV mehrerer Tage', () {
      final map = GarminMetricsParser.hrv(
        JsonValue.parse('''
          {"hrvSummaries": [
            {"calendarDate": "2026-10-21", "weeklyAvg": 60, "lastNightAvg": 61, "status": "UNBALANCED",
             "baseline": {"balancedLow": 55, "balancedUpper": 70}},
            {"calendarDate": "2026-10-22", "weeklyAvg": 62, "lastNightAvg": 58, "status": "BALANCED"}
          ]}'''),
      );
      expect(map.length, 2);
      expect(map[day.adding(-1)]?.hrvStatus, 'UNBALANCED');
      expect(map[day]?.hrvBaselineLow, isNull);
    });

    test('Schlaf mit Dauer, Score und Zeiten', () {
      final metrics = GarminMetricsParser.sleep(
        JsonValue.parse('''
          {"dailySleepDTO": {"calendarDate": "2026-10-22", "sleepTimeSeconds": 26100,
            "sleepScores": {"overall": {"value": 81, "qualifierKey": "GOOD"}},
            "sleepStartTimestampLocal": 1761089400000, "sleepEndTimestampLocal": 1761116400000},
           "restingHeartRate": 47}'''),
      )[day]!;
      expect(metrics.sleepSeconds, 26100);
      expect(metrics.sleepHours, 7.3);
      expect(metrics.sleepScore, 81);
      expect(metrics.sleepStartMinutes, 23 * 60 + 30);
      expect(metrics.sleepEndMinutes, 7 * 60);
    });

    test('Body Battery aus den Werten', () {
      final metrics = GarminMetricsParser.bodyBattery(
        JsonValue.parse(
          '''
          [{"calendarDate": "2026-10-22", "charged": 60, "drained": 55,
            "bodyBatteryValuesArray": [[1761091200000, 30], [1761105600000, 92], [1761148800000, 41], [1761150000000, -1]]}]''',
        ),
        offsetSeconds: (_) => 7200,
      )[day]!;
      expect(metrics.bodyBatteryHigh, 92);
      expect(metrics.bodyBatteryLow, 30);
      expect(metrics.bodyBatteryLatest, 41);
      expect(metrics.bodyBatteryCharged, 60);
      // Mitternacht UTC mit 2 h Versatz: 02:00 Ortszeit.
      expect(metrics.bodyBatteryCurve?.first, const BodyBatterySample(minute: 120, value: 30));
    });

    test('Zusammenführen behält Werte aller Quellen', () {
      final summary = DailyMetrics(day)..restingHeartRate = 48;
      final hrv = DailyMetrics(day)..hrvStatus = 'LOW';
      final sleep = DailyMetrics(day)..sleepSeconds = 20000;
      final merged = GarminMetricsParser.merge([
        {day: summary},
        {day: hrv},
        {day: sleep},
      ])[day]!;
      expect(merged.restingHeartRate, 48);
      expect(merged.hrvStatus, 'LOW');
      expect(merged.sleepSeconds, 20000);
      expect(merged.presentFields, ['Ruhepuls', 'HRV-Status', 'Schlafdauer']);
      expect(DailyMetrics.fromJson(merged.toJson()), merged);
    });

    test('unbekannte Form ergibt keine Einträge', () {
      expect(GarminMetricsParser.dailySummaries(JsonValue.parse('{"message": "nope"}')), isEmpty);
      expect(GarminMetricsParser.sleep(JsonValue.nullValue), isEmpty);
    });

    test('Fitnessalter und VO2max', () {
      final map = GarminMetricsParser.fitnessAge(JsonValue.parse('{"fitnessAge": 31.5, "vo2MaxValue": 52}'), day);
      expect(map[day]?.fitnessAge, 31.5);
      expect(map[day]?.vo2Max, 52);
      expect(GarminMetricsParser.fitnessAge(JsonValue.parse('{}'), day), isEmpty);
    });
  });

  group('Laufumfang (LoadCheckTests, Phase78Tests)', () {
    GarminActivity run(int daysAgo, double km, CalendarDay monday) => GarminActivity(daysAgo * 10 + km.toInt())
      ..typeKey = 'running'
      ..startLocal = '${monday.adding(-daysAgo).iso} 08:00:00'
      ..distanceMeters = km * 1000;

    test('warnt bei steilem Anstieg', () {
      const monday = CalendarDay(2026, 11, 2);
      final baseline = [
        for (final days in [8, 12, 15, 19, 22, 26]) run(days, 10, monday),
      ];
      expect(LoadCheck.running([...baseline, run(1, 10, monday), run(3, 10, monday)], today: monday).warning, isNull);
      final steep = LoadCheck.running([
        ...baseline,
        run(1, 12, monday),
        run(3, 12, monday),
        run(5, 12, monday),
      ], today: monday);
      expect(steep.warning, isNotNull);
      expect(steep.baselineKilometers, 20);
      expect(steep.lastWeekKilometers, 36);
    });

    test('keine Warnung bei kleinen Umfängen', () {
      const monday = CalendarDay(2026, 11, 2);
      expect(LoadCheck.running([run(10, 2, monday), run(1, 4, monday)], today: monday).warning, isNull);
    });

    test('Einzellauf weit über dem längsten', () {
      const monday = CalendarDay(2026, 11, 9);
      expect(LoadCheck.running([run(12, 10, monday), run(1, 12, monday)], today: monday).warning, contains('längster'));
      expect(LoadCheck.singleRunWarning([run(12, 10, monday), run(1, 11, monday)], today: monday), isNull);
      expect(LoadCheck.singleRunWarning([run(12, 10, monday), run(6, 14, monday)], today: monday), isNull);
    });
  });

  group('Belastung und Planzahlen aus den Zielen', () {
    const today = CalendarDay(2026, 11, 2);

    test('Erholung als Priorität macht die Belastungsgrenze strenger', () {
      expect(
        Personalization.maxLoadIncrease(PersonalGoals(primary: TrainingGoal.muscleGain, since: today)),
        WeekLoad.maxIncrease,
      );
      expect(Personalization.maxLoadIncrease(PersonalGoals(primary: TrainingGoal.recovery, since: today)), 0.20);
      expect(
        Personalization.maxLoadIncrease(
          PersonalGoals(primary: TrainingGoal.endurance, priorities: const [FocusArea.health], since: today),
        ),
        0.20,
      );
    });

    test('Planzahlen folgen Haupt- und Nebenzielen', () {
      final profile = UserProfile(sports: const [TrainingSport.run, TrainingSport.strength])
        ..setLevel(ExperienceLevel.intermediate, TrainingSport.run)
        ..setLevel(ExperienceLevel.intermediate, TrainingSport.strength);
      final base = {TrainingSport.run: 2, TrainingSport.strength: 2};
      final muscle = Personalization.adjustCounts(
        base,
        goals: PersonalGoals(primary: TrainingGoal.muscleGain, since: today),
        profile: profile,
      );
      expect(muscle[TrainingSport.strength], 4);
      final endurance = Personalization.adjustCounts(
        base,
        goals: PersonalGoals(primary: TrainingGoal.endurance, since: today),
        profile: profile,
      );
      expect(endurance[TrainingSport.run], 3);
      final health = Personalization.adjustCounts(
        {TrainingSport.run: 4, TrainingSport.strength: 3},
        goals: PersonalGoals(primary: TrainingGoal.health, since: today),
        profile: profile,
      );
      expect(health, {TrainingSport.run: 2, TrainingSport.strength: 2});
    });

    test('geschätzte Belastung ohne Wert der Uhr', () {
      final easy = GarminActivity(1)
        ..typeKey = 'running'
        ..durationSeconds = 3600;
      expect(WeekLoad.load(easy), (value: 60.0, estimated: true));
      final measured = easy.copy()..trainingLoad = 85;
      expect(WeekLoad.load(measured), (value: 85.0, estimated: false));
      final intervals = easy.copy()..name = 'Intervalle 6x800';
      expect(WeekLoad.load(intervals).value, 120);
      expect(SessionKind.of(intervals), SessionKind.vo2);
    });
  });
}

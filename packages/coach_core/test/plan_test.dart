// Port von DisciplineTests.swift und PlanScheduleTests.swift.
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

SeasonSchedule loadSchedule() => SeasonSchedule.load(File('assets/season-plan.json').readAsStringSync())!;

void main() {
  // Erwartungswerte wie im HA-Dashboard (Stand 14.10.2026: Rad Z2 100–134 W, Sweet Spot 157–167 W,
  // Schwelle 169–187 W, Renntempo 134–139 W).
  group('Disziplinen', () {
    const today = CalendarDay(2026, 10, 26);

    test('Schwimm-Paces und CSS-Test', () {
      expect(SwimPaces.rows(130).map((row) => row.value), [
        '2:06–2:08',
        '2:10',
        '2:11–2:12',
        '2:13–2:14',
        '2:14–2:16',
        '2:10–2:13',
      ]);
      expect(SwimPaces.css(time400: 520, time200: 260), 130);
      expect(SwimPaces.css(time400: 200, time200: 260), isNull);
      expect(SwimPaces.css(time400: 1000, time200: 100), isNull);
    });

    test('Rad-Zonen wie im Dashboard', () {
      final rows = {for (final row in BikeZones.rows(178)) row.label: row.value};
      expect(rows['Z2 Grundlage'], '100–134 W');
      expect(rows['Sweet Spot'], '157–167 W');
      expect(rows['Z4 Schwelle'], '169–187 W');
      expect(rows['Renntempo'], '134–139 W');
    });

    test('Lauf-Paces', () {
      expect(RunPaces.rows(SeasonConfig.standard).map((row) => row.value), [
        '6:00–6:35',
        '5:25',
        '5:42',
        '4:55',
        '4:32–4:37',
      ]);
    });

    test('Rennschätzung', () {
      final tests = [TestRecord(kind: TestKind.css, value: 130, day: today.adding(-10))];
      final estimate = RaceEstimate(config: SeasonConfig.standard, tests: tests, today: today);
      expect(RaceEstimate.hoursMinutes(estimate.totalMinutes), '5:54');
      expect(estimate.corridorText, 'Im Zielkorridor 5:30–6:00.');
      expect(estimate.freshness.map((item) => item.isFresh), [true, false, false]);
      expect(estimate.allFresh, isFalse);
      expect((estimate.savings.bike - 6.06).abs(), lessThan(0.01));
      expect((estimate.savings.swim - 1.58).abs(), lessThan(0.01));
    });

    test('Marathon-Ausblick', () {
      final config = SeasonConfig.standard;
      final outlook = MarathonOutlook(
        config: config,
        halfMarathonSeconds: 6300,
        schedule: loadSchedule(),
        today: today,
      );
      expect(outlook.daysToRace, 188);
      expect(MarathonOutlook.hoursMinutesFromSeconds(outlook.targetSeconds), '3:48');
      expect(outlook.predicted, (low: 13545, high: 13860));
      expect(outlook.targetTooFast, isFalse);
      expect(outlook.ladder.length, 17);
      expect(outlook.ladder.first.longRun, '16 km');
      expect(outlook.ladder.any((week) => week.longRun == 'Halbmarathon-Test'), isTrue);
      expect(outlook.ladder.last.longRun, '🏁 Marathon');
      config.marathonPaceSecondsPerKm = 310;
      expect(
        MarathonOutlook(config: config, halfMarathonSeconds: 6300, schedule: null, today: today).targetTooFast,
        isTrue,
      );
    });

    test('Testverlauf: einer je Tag und Art', () {
      var records = <TestRecord>[];
      records = TestHistory.adding(TestRecord(kind: TestKind.ftp, value: 170, day: today.adding(-30)), records);
      records = TestHistory.adding(TestRecord(kind: TestKind.ftp, value: 175, day: today), records);
      records = TestHistory.adding(TestRecord(kind: TestKind.ftp, value: 178, day: today), records);
      expect(records.length, 2);
      expect(TestHistory.latest(TestKind.ftp, records)?.value, 178);
      expect(TestHistory.values(TestKind.ftp, records).map((value) => value.value), [170, 178]);
      expect(TestRecord.fromJson(records.first.toJson()), records.first);
    });
  });

  group('Saisonplan', () {
    test('lädt alle Wochen mit Schwimmschritten', () {
      final plan = loadSchedule();
      expect(plan.weeks.length, 48);
      expect(plan.weeks.first.w, '2026-10-12');
      expect(plan.weeks.every((week) => week.ss?.isNotEmpty ?? false), isTrue);
      expect(plan.zw.length, greaterThanOrEqualTo(16));
      expect(plan.phases['Grundlage']?.mw.startsWith('Mo Push'), isTrue);
      const thursday = CalendarDay(2026, 10, 29);
      expect(plan.week(thursday)?.w, '2026-10-26');
      expect(plan.index(thursday), 2);
      expect(SeasonSchedule.load('kaputt'), isNull);
    });

    // Erwartungswerte wie im HA-Dashboard (Stand 14.10.2026): Intervall 4:32–4:37, locker 6:00–6:35.
    test('Platzhalter nutzen die Testwerte', () {
      final tokens = PlanTokens(SeasonConfig.standard);
      expect(tokens.fill('§T§ /km'), '4:55 /km');
      expect(tokens.fill('§I§'), '4:32–4:37');
      expect(tokens.fill('§E§'), '6:00–6:35');
      expect(tokens.fill('§S0§ · §S+2§ · §S-4§'), '2:10 · 2:12 · 2:06');
      expect(tokens.fill('§W88§–§W92§ W'), '157–164 W');
      expect(tokens.fill('§MP§ und §R§'), '5:25 und 5:42');
      expect(tokens.fill('§X§ bleibt'), '§X§ bleibt');
      expect(tokens.fill('ohne Platzhalter'), 'ohne Platzhalter');
      expect(tokens.fill('offen § am Ende'), 'offen § am Ende');
    });

    test('Einheiten einer Woche', () {
      final plan = loadSchedule();
      final week = plan.weeks.firstWhere((week) => week.w == '2026-10-26');
      final units = plan.units(week, config: SeasonConfig.standard);
      expect(units.map((unit) => unit.kind), [
        PlannedUnitKind.bike,
        PlannedUnitKind.bikeOptional,
        PlannedUnitKind.swim,
        PlannedUnitKind.quality,
        PlannedUnitKind.easyRun,
        PlannedUnitKind.gym,
        PlannedUnitKind.gym,
        PlannedUnitKind.gym,
        PlannedUnitKind.gym,
      ]);
      expect(units[0].title, 'Z03 Sweet Spot 2×20');
      expect(units[0].detail, contains('157–164 W'));
      expect(units[3].title, 'Schwelle 3×2,5 km');
      expect(units[3].detail, contains('4:55 /km'));
      expect(units[2].swimMeters, 2000);
      expect(SwimStepText.equipment(units[2].swimSteps), ['Pull-Buoy']);
      final lines = SwimStepText.lines(units[2].swimSteps, tokens: PlanTokens(SeasonConfig.standard));
      expect(lines.first, 'Ein 200 m · locker einschwimmen');
      expect(lines, contains('400 m · @ 2:14–2:16 /100 m · mit Pull-Buoy, nur Arme · (Pull-Buoy)'));
    });

    test('Wettkampf-Lauf lässt sich ablehnen', () {
      final plan = loadSchedule();
      final week = plan.weeks.firstWhere((week) => week.w == '2027-01-11');
      final open = plan
          .units(week, config: SeasonConfig.standard)
          .firstWhere((unit) => unit.kind == PlannedUnitKind.quality);
      expect(open.title, '🏁 Marathontempo 2×4 km');
      expect(open.decision, PlannedUnitDecision.open);
      expect(open.detail, contains('5:25 /km'));
      final key = SeasonSchedule.decisionKey(week, PlannedUnitKind.quality);
      expect(key, 'wk-lauf-2027-01-11-q');
      final rejected = plan
          .units(week, config: SeasonConfig.standard, decisions: {key: PlannedUnitDecision.rejected})
          .firstWhere((unit) => unit.kind == PlannedUnitKind.quality);
      expect(rejected.title, 'Intervall 4×4 min');
      expect(rejected.decision, PlannedUnitDecision.rejected);
      final longRun = plan
          .units(week, config: SeasonConfig.standard)
          .firstWhere((unit) => unit.kind == PlannedUnitKind.longRun);
      expect(longRun.title, 'Longrun 18 km');
    });

    test('Fortschritt hakt erledigte Einheiten ab', () {
      final plan = loadSchedule();
      final week = plan.weeks.firstWhere((week) => week.w == '2027-01-11');
      GarminActivity activity(int id, String type, int day, {required double km}) => GarminActivity(id)
        ..typeKey = type
        ..startLocal = '2027-01-${day.toString().padLeft(2, '0')} 08:00:00'
        ..distanceMeters = km * 1000;
      final activities = [
        activity(1, 'running', 17, km: 17),
        activity(2, 'running', 13, km: 9),
        activity(3, 'lap_swimming', 12, km: 2),
        activity(4, 'indoor_cycling', 12, km: 0),
        activity(5, 'running', 20, km: 9),
      ];
      final units = PlanProgress.mark(
        plan.units(week, config: SeasonConfig.standard),
        week: week,
        activities: activities,
        gymDays: [const CalendarDay(2027, 1, 11)],
      );
      final done = <PlannedUnitKind, bool>{};
      for (final unit in units) {
        done.putIfAbsent(unit.kind, () => unit.done);
      }
      expect(done[PlannedUnitKind.longRun], isTrue);
      expect(done[PlannedUnitKind.quality], isTrue);
      expect(done[PlannedUnitKind.easyRun], isFalse);
      expect(done[PlannedUnitKind.swim], isTrue);
      expect(done[PlannedUnitKind.bike], isFalse);
      expect(units.where((unit) => unit.kind == PlannedUnitKind.gym && unit.done).length, 1);
    });
  });
}

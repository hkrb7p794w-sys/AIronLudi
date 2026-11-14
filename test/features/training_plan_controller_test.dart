// Port von `TrainingViewModelTests` und `PlanViewModelTests`.
import 'dart:io';

import 'package:aironludi/features/plan/plan_controller.dart';
import 'package:aironludi/features/training/training_controller.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter_test/flutter_test.dart';

SeasonSchedule loadSchedule() =>
    SeasonSchedule.load(File('packages/coach_core/assets/season-plan.json').readAsStringSync())!;

void main() {
  test('Training: Verläufe, Kacheln und Zonen', () {
    final now = DateTime(2026, 10, 22, 12);
    final today = CalendarDay.fromDate(now);
    final days = [
      for (var offset = 0; offset < 10; offset++)
        DailyMetrics(today.adding(-offset))
          ..restingHeartRate = 50
          ..hrvWeeklyAverage = 60
          ..spo2Average = 95
          ..respirationWaking = 14,
    ];
    final run = GarminActivity(1)
      ..typeKey = 'running'
      ..startLocal = '${today.iso} 07:00:00'
      ..distanceMeters = 10000
      ..vo2Max = 52;
    final profile = GarminProfile()..lactateThresholdHeartRate = 168;

    final controller = TrainingController()
      ..update(
        days: days,
        activities: [run],
        profile: profile,
        watchZones: null,
        overrides: HeartRateOverrides(),
        now: now,
      );

    expect([for (final card in controller.recovery) card.title], ['HRV · 7-Tage-Schnitt', 'Ruhepuls']);
    expect(controller.tiles, contains(const TrainingTile('SpO2', '95 %')));
    expect(controller.tiles.any((tile) => tile.title == 'VO2max Laufen'), isTrue);
    expect(controller.tiles, contains(const TrainingTile('Atemfrequenz', '14,0 /min')));
    expect(controller.weeks.length, 12);
    expect(controller.weeks.last.volume.kilometers[ActivitySport.run], 10);
    expect(controller.zones?.run.lactateThreshold, 168);
  });

  test('Plan: startet in der aktuellen Woche und blättert', () {
    final now = DateTime(2026, 10, 29, 12);
    final controller = PlanController(schedule: loadSchedule(), now: now)
      ..update(activities: const [], gymDays: const [], config: SeasonConfig.standard, decisions: const {}, now: now);

    expect(controller.week?.w, '2026-10-26');
    expect(controller.isCurrentWeek, isTrue);
    expect(controller.weekTitle, 'KW 44');
    expect(controller.weekRange, '26.10. – 01.11.');
    expect(controller.units.first.title, 'Z03 Sweet Spot 2×20');
    expect(controller.requiredCount, 8);

    controller.step(1);
    expect(controller.week?.w, '2026-11-02');
    expect(controller.isCurrentWeek, isFalse);
    controller.show(controller.currentWeekIndex);
    expect(controller.isCurrentWeek, isTrue);
  });

  test('Plan: vor der Saison die erste Woche', () {
    final controller = PlanController(schedule: loadSchedule(), now: DateTime(2026, 1, 5, 12));
    expect(controller.weekIndex, 0);
    expect(controller.canGoBack, isFalse);
  });

  test('ISO-Kalenderwoche über den Jahreswechsel', () {
    final controller = PlanController(schedule: loadSchedule(), now: DateTime(2026, 12, 31, 12));
    controller.show(controller.currentWeekIndex);
    expect(controller.week?.w, '2026-12-28');
    expect(controller.weekTitle, 'KW 53');
  });
}

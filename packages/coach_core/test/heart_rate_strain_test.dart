// Strain wie bei WHOOP: Puls über den ganzen Tag, Zonen der Herzfrequenzreserve, Skala 0–21.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Verlauf im 2-Minuten-Raster: [blocks] = (Minuten, Puls) hintereinander ab [start] (Minuten nach Mitternacht).
List<HeartRateSample> _curve(List<(int, int)> blocks, {int start = 7 * 60}) {
  final samples = <HeartRateSample>[];
  var minute = start;
  for (final (duration, bpm) in blocks) {
    for (var offset = 0; offset < duration; offset += 2) {
      samples.add(HeartRateSample(minute: minute + offset, bpm: bpm));
    }
    minute += duration;
  }
  return samples;
}

double _strain(List<(int, int)> blocks) =>
    HeartRateStrain.compute(_curve(blocks), restingHeartRate: 55, maxHeartRate: 190)!.strain;

void main() {
  // Ruhepuls 55, HFmax 190 → Reserve 135: 30 % = 96, 50 % = 123, 60 % = 136, 70 % = 150, 80 % = 163, 90 % = 177.
  const quietDay = [(600, 70), (180, 100), (20, 125)];

  test('Gewichte je Zone: Ruhe 0, Alltag 0,1, Zonen 1–5 Gewicht 1–5', () {
    expect(HeartRateStrain.weight(0.2), 0);
    expect(HeartRateStrain.weight(0.35), 0.1);
    expect(HeartRateStrain.weight(0.5), 1);
    expect(HeartRateStrain.weight(0.65), 2);
    expect(HeartRateStrain.weight(0.75), 3);
    expect(HeartRateStrain.weight(0.85), 4);
    expect(HeartRateStrain.weight(0.95), 5);
    expect(HeartRateStrain.weight(1.2), 5);
    expect([0.1, 0.55, 0.92].map(HeartRateStrain.zone), [0, 1, 5]);
  });

  test('Skala wie WHOOP: ruhiger Tag leicht, Lauf mittel bis hoch, Marathon all out', () {
    expect(_strain(quietDay), inInclusiveRange(3, 6));
    expect(_strain([...quietDay, (60, 140)]), inInclusiveRange(11, 13.9)); // 1 h locker (Zone 2)
    expect(_strain([...quietDay, (60, 155)]), inInclusiveRange(14, 16)); // 1 h zügig (Zone 3)
    expect(_strain([...quietDay, (60, 168)]), inInclusiveRange(16, 18)); // 1 h Intervalle (Zone 4)
    expect(_strain([...quietDay, (210, 160)]), greaterThanOrEqualTo(20)); // Marathon
    expect(_strain([...quietDay, (600, 185)]), lessThanOrEqualTo(21));
    // Nach oben immer schwerer: die zweite Stunde bringt weniger als die erste.
    final one = _strain([...quietDay, (60, 155)]) - _strain(quietDay);
    final two = _strain([...quietDay, (120, 155)]) - _strain([...quietDay, (60, 155)]);
    expect(two, lessThan(one));
  });

  test('Lücken (Uhr abgelegt) zählen höchstens 10 min; HFmax nie unter dem gemessenen Höchstwert', () {
    final gap = HeartRateStrain.compute(
      const [HeartRateSample(minute: 600, bpm: 150), HeartRateSample(minute: 780, bpm: 70)],
      restingHeartRate: 55,
      maxHeartRate: 190,
    )!;
    expect(gap.zoneMinutes[3], 10);
    expect(gap.load, 30);
    final above = HeartRateStrain.compute(
      const [HeartRateSample(minute: 600, bpm: 200)],
      restingHeartRate: 50,
      maxHeartRate: 180,
    )!;
    expect(above.maxHeartRate, 200);
    expect(above.zoneMinutes[5], 2);
    expect(HeartRateStrain.compute(const [], maxHeartRate: 190), isNull);
    // Ohne Ruhepuls und HFmax: 60 bzw. 190.
    final defaults = HeartRateStrain.compute(const [HeartRateSample(minute: 10, bpm: 80)])!;
    expect((defaults.restingHeartRate, defaults.maxHeartRate), (60, 190));
    expect(HeartRateStrain.strainOf(HeartRateStrain.loadOf(12.5)), closeTo(12.5, 0.05));
  });

  test('Einzelmessungen (Health) → 2-Minuten-Verlauf je Tag in Ortszeit', () {
    final curves = HeartRateStrain.curves([
      (DateTime(2026, 11, 20, 8, 0, 10), 100),
      (DateTime(2026, 11, 20, 8, 1, 50), 110),
      (DateTime(2026, 11, 20, 8, 2, 0), 120),
      (DateTime(2026, 11, 19, 23, 59), 60),
      (DateTime(2026, 11, 20, 9), 300), // unplausibel
    ]);
    expect(curves[const CalendarDay(2026, 11, 20)], const [
      HeartRateSample(minute: 480, bpm: 105),
      HeartRateSample(minute: 482, bpm: 120),
    ]);
    expect(curves[const CalendarDay(2026, 11, 19)], const [HeartRateSample(minute: 1438, bpm: 60)]);
  });

  test('HFmax: eigener Wert, sonst gemessen, sonst nach Alter', () {
    const today = CalendarDay(2026, 11, 20);
    GarminActivity run(int id, int max) => GarminActivity(id)
      ..typeKey = 'running'
      ..startLocal = '2026-10-0$id 07:00:00'
      ..maxHeartRate = max.toDouble();
    expect(
      HeartRateStrain.maxHeartRate(
        overrides: const HeartRateOverrides(maxHeartRate: 186),
        activities: [run(1, 192)],
        today: today,
      ),
      186,
    );
    expect(
      HeartRateStrain.maxHeartRate(overrides: const HeartRateOverrides(), activities: [run(1, 192)], today: today),
      192,
    );
    expect(
      HeartRateStrain.maxHeartRate(overrides: const HeartRateOverrides(), activities: const [], today: today, age: 40),
      180,
    );
    expect(
      HeartRateStrain.maxHeartRate(overrides: const HeartRateOverrides(), activities: const [], today: today),
      isNull,
    );
  });

  test('Garmin dailyHeartRate: Minuten ab Mitternacht Ortszeit, Lücken ohne Wert übersprungen', () {
    final midnight = DateTime.utc(2026, 11, 19, 23).millisecondsSinceEpoch;
    final map = GarminMetricsParser.dailyHeartRate(
      JsonValue({
        'calendarDate': '2026-11-20',
        'startTimestampGMT': '2026-11-19T23:00:00.0',
        'restingHeartRate': 52,
        'maxHeartRate': 161,
        'minHeartRate': 47,
        'heartRateValues': [
          [midnight, 55],
          [midnight + 120000, null],
          [midnight + 8 * 3600000, 140],
        ],
      }),
      const CalendarDay(2026, 11, 20),
    );
    final day = map[const CalendarDay(2026, 11, 20)]!;
    expect(day.heartRateCurve, const [HeartRateSample(minute: 0, bpm: 55), HeartRateSample(minute: 480, bpm: 140)]);
    expect((day.restingHeartRate, day.maxHeartRate, day.minHeartRate), (52, 161, 47));
    // Kompakt gespeichert und wieder gelesen.
    expect(day.toJson()['heartRateCurve'], [0, 55, 480, 140]);
    expect(DailyMetrics.fromJson(day.toJson()), day);
    expect(
      GarminMetricsParser.dailyHeartRate(JsonValue(<String, Object?>{}), const CalendarDay(2026, 11, 20)),
      isEmpty,
    );
  });

  test('Quellen: WHOOP-Strain vor Garmin-Pulsverlauf, als eigene Datenart', () {
    const day = CalendarDay(2026, 11, 20);
    final garmin = DailyMetrics(day)
      ..acuteLoad = 300
      ..heartRateCurve = _curve(quietDay);
    final whoop = DailyMetrics(day)..dayStrain = 9.4;
    final merged = MetricsMerge.merge(
      {DataProvider.garmin: garmin, DataProvider.whoop: whoop},
      day: day,
      preferences: SourcePreferences(primary: DataProvider.garmin),
    );
    expect(merged.sources[DataKind.strain], DataProvider.whoop);
    expect(merged.sources[DataKind.trainingLoad], DataProvider.garmin);
    expect((merged.metrics.dayStrain, merged.metrics.heartRateCurve), (9.4, null));
    final garminOnly = MetricsMerge.merge({DataProvider.garmin: garmin}, day: day, preferences: SourcePreferences());
    expect(garminOnly.metrics.heartRateCurve, hasLength(400));
  });

  group('Tages-Strain und Ring', () {
    const today = CalendarDay(2026, 11, 20);
    DailyStrain compute({DailyMetrics? metrics, List<SessionSlot> planned = const []}) => DailyStrainRules.compute(
      activities: const [],
      plannedToday: planned,
      recovery: null,
      today: today,
      todayMetrics: metrics,
      maxHeartRate: 190,
    );

    test('ohne Pulsverlauf aus den Trainings (wie bisher)', () {
      final strain = compute();
      expect((strain.measured, strain.source), (null, StrainSource.workouts));
      expect(TodayKpis.strain(strain).caption, 'von 21');
    });

    test('Pulsverlauf zählt auch ohne Training; Geplantes obendrauf', () {
      final metrics = DailyMetrics(today)
        ..restingHeartRate = 55
        ..heartRateCurve = _curve(quietDay);
      final strain = compute(metrics: metrics);
      expect(strain.source, StrainSource.heartRate);
      expect(strain.measured, greaterThan(3));
      final kpi = TodayKpis.strain(strain);
      expect(kpi.value, GermanFormat.decimal(strain.measured!));
      expect(kpi.caption, 'Puls ganztags');
      final withPlan = TodayKpis.strain(compute(metrics: metrics, planned: const [SessionSlot(TrainingSport.run)]));
      expect(withPlan.value, kpi.value);
      expect(withPlan.caption, startsWith('+'));
      expect(withPlan.secondaryFraction, greaterThan(withPlan.fraction));
    });

    test('WHOOP-Wert hat Vorrang; Werte von gestern zählen nicht', () {
      final whoop = DailyMetrics(today)
        ..dayStrain = 11.2
        ..heartRateCurve = _curve(quietDay);
      expect((compute(metrics: whoop).measured, compute(metrics: whoop).source), (11.2, StrainSource.whoop));
      expect(TodayKpis.strain(compute(metrics: whoop)).caption, 'WHOOP');
      final yesterday = DailyMetrics(today.adding(-1))..dayStrain = 15;
      expect(compute(metrics: yesterday).measured, isNull);
    });
  });
}

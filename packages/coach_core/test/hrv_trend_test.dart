// HRV-Trend für Quellen ohne Garmins HRV-Status (Roast B-08): 7-Tage-Schnitt von ln(HRV) gegen die eigene Basis.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 11, 24);

List<DailyMetrics> history({required double base, required double week, double wobble = 4}) => [
  for (var offset = 60; offset >= 0; offset--)
    DailyMetrics(today.adding(-offset))
      ..hrvLastNightAverage = (offset < 7 ? week : base) + (offset.isEven ? wobble : -wobble),
];

void main() {
  test('zu wenig Werte: kein Trend', () {
    expect(HrvTrend.of(history(base: 60, week: 60).sublist(50), day: today), isNull);
  });

  test('Woche deutlich unter der Basis → locker, mit Zahlen im Grund', () {
    final days = history(base: 62, week: 45);
    final trend = HrvTrend.of(days, day: today)!;
    expect(trend.isBelowBaseline, isTrue);
    expect(trend.baselineAverage, closeTo(62, 1));
    final state = RecoveryEvaluator.today(days: days, form: const [], today: today);
    expect(state.recommendation.level, RecoveryLevel.locker);
    expect(state.recommendation.reasons.first, startsWith('HRV 7-Tage-Schnitt 45 ms, unter deinem üblichen Bereich'));
  });

  test('Woche im Bereich → keine Herabstufung', () {
    final days = history(base: 62, week: 60);
    expect(HrvTrend.of(days, day: today)!.isBelowBaseline, isFalse);
    final state = RecoveryEvaluator.today(days: days, form: const [], today: today);
    expect(state.recommendation.level, RecoveryLevel.normal);
    expect(state.recommendation.reasons, contains('HRV 7-Tage-Schnitt im üblichen Bereich'));
  });

  test('Garmins HRV-Status hat Vorrang vor dem eigenen Trend', () {
    final days = history(base: 62, week: 45);
    days.last.hrvStatus = 'BALANCED';
    final state = RecoveryEvaluator.today(days: days, form: const [], today: today);
    expect(state.recommendation.reasons, contains('HRV-Status ausgeglichen'));
    expect(state.recommendation.level, RecoveryLevel.normal);
  });
}

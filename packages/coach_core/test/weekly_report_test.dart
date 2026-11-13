// Port von WeeklyReportTests.swift und WeightTrendTests (SafeguardTests.swift) sowie dem Vorschlags-Test aus
// GoalGuardTests.swift.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Mittwoch, 11.11.2026; berichtet wird die Woche ab Montag, 2.11.
const today = CalendarDay(2026, 11, 11);
const monday = CalendarDay(2026, 11, 2);

GarminActivity run(CalendarDay day, {required double minutes, required double kilometers, required int id}) =>
    GarminActivity(id)
      ..typeKey = 'running'
      ..startLocal = '${day.iso} 07:00:00'
      ..durationSeconds = minutes * 60
      ..distanceMeters = kilometers * 1000
      ..trainingLoad = minutes;

/// Täglich gewogen mit leichtem Rauschen: [perWeek] kg Änderung pro Woche.
List<WeightEntry> entries({required double start, required double perWeek, int days = 28}) => [
  for (var offset = 0; offset < days; offset++)
    WeightEntry(
      day: monday.adding(offset - days + 1),
      kilograms: start + perWeek * offset / 7 + (offset.isEven ? 0.3 : -0.3),
      source: WeightSource.manual,
    ),
];

void main() {
  group('Wochenbericht', () {
    test('letzte Woche gegen die Vorwoche', () {
      final activities = [
        run(monday, minutes: 60, kilometers: 10, id: 1),
        run(monday.adding(2), minutes: 60, kilometers: 10, id: 2),
        run(monday.adding(-5), minutes: 40, kilometers: 6, id: 3),
      ];
      final night = DailyMetrics(monday.adding(1))..sleepSeconds = 6 * 3600;
      final report = WeeklyReport.lastWeek(
        activities: activities,
        days: [night],
        gymDays: [monday.adding(4)],
        today: today,
      );
      expect(report.monday, monday);
      expect(report.week.sessions, 3);
      expect(report.week.minutes, 120);
      expect(report.week.kilometers[ActivitySport.run], 20);
      expect(report.previous.minutes, 40);
      expect(report.highlights.any((line) => line.contains('Deutlich mehr Trainingszeit')), isTrue);
      expect(report.highlights.any((line) => line.contains('Stunden Schlaf')), isTrue);
    });

    test('leere Woche bekommt einen Hinweis', () {
      final report = WeeklyReport.lastWeek(activities: [], days: [], gymDays: [], today: today);
      expect(report.week.sessions, 0);
      expect(report.highlights.first, contains('Keine Einheit'));
    });
  });

  group('Gewichtstrend', () {
    test('braucht genug Wägungen', () {
      expect(WeightTrend.trend(entries(start: 80, perWeek: -0.4, days: 7), today: monday), isNull);
      expect(WeightTrend.trend(entries(start: 80, perWeek: -0.4).take(5), today: monday), isNull);
    });

    test('im Plan, zu schnell und zu langsam', () {
      // 80 kg, −0,4 kg pro Woche ≈ −0,5 % → wie geplant.
      final onTrack = WeightTrend.trend(entries(start: 80, perWeek: -0.4), today: monday)!;
      expect((onTrack.weeklyPercent + 0.5).abs(), lessThan(0.1));
      expect(
        WeightTrend.advice(result: onTrack, plannedPercent: -0.5, currentAdjustment: 0).kind,
        WeightAdviceKind.onTrack,
      );

      // −1 kg pro Woche ≈ −1,3 % → zu schnell, mehr essen.
      final fast = WeightTrend.trend(entries(start: 80, perWeek: -1.0), today: monday)!;
      final fastAdvice = WeightTrend.advice(result: fast, plannedPercent: -0.5, currentAdjustment: 0);
      expect(fastAdvice.kind, WeightAdviceKind.tooFast);
      expect(fastAdvice.kilocalories > 0 && fastAdvice.kilocalories <= WeightTrend.maxStepKilocalories, isTrue);

      // Gewicht steigt trotz Abnehmziel → weniger essen, in 50er-Schritten.
      final gaining = WeightTrend.trend(entries(start: 80, perWeek: 0.2), today: monday)!;
      final less = WeightTrend.advice(result: gaining, plannedPercent: -0.5, currentAdjustment: 0);
      expect(less.kind, WeightAdviceKind.eatLess);
      expect(less.kilocalories, lessThan(0));
      expect(less.kilocalories % 50, 0);
      // Gesamtgrenze ±500 kcal.
      expect(WeightTrend.advice(result: gaining, plannedPercent: -0.5, currentAdjustment: -500).kilocalories, 0);
    });

    test('Garmin-Wägungen werden gelesen', () {
      const json = JsonValue({
        'dailyWeightSummaries': [
          {
            'summaryDate': '2026-11-01',
            'latestWeight': {'weight': 72360, 'calendarDate': '2026-11-01'},
          },
        ],
      });
      expect(WeightTrend.garminEntries(json), [
        WeightEntry(day: monday.adding(-1), kilograms: 72.4, source: WeightSource.garmin),
      ]);
    });

    test('mit Schutzgrenze nie weniger essen', () {
      const gaining = WeightTrendResult(trendKilograms: 60, weeklyPercent: 1, entries: 10, spanDays: 20);
      expect(
        WeightTrend.advice(result: gaining, plannedPercent: null, currentAdjustment: 0).kind,
        WeightAdviceKind.eatLess,
      );
      final noDeficit = WeightTrend.advice(
        result: gaining,
        plannedPercent: null,
        currentAdjustment: 0,
        safety: WeightGoalGuard.noDeficit,
      );
      expect(noDeficit.kilocalories, 0);
      final withheld = WeightTrend.advice(
        result: gaining,
        plannedPercent: null,
        currentAdjustment: 0,
        safety: WeightGoalGuard.noTargets,
      );
      expect(withheld.kilocalories, 0);
      expect(withheld.message, isNot(contains('kcal')));
    });
  });
}

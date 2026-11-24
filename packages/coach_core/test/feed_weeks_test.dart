// Verlauf nach Wochen (Roast Stufe 4 / PR 21).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

FeedEntry entry(CalendarDay day, {double? seconds, int? gymMinutes}) => FeedEntry(
  id: day.iso,
  day: day,
  sortKey: day.iso,
  title: 'Einheit',
  sport: ActivitySport.run,
  sources: const [],
  activity: seconds == null ? null : (GarminActivity(1)..durationSeconds = seconds),
  gym: gymMinutes == null
      ? null
      : GymItem(id: 'g', title: 'Gym', start: DateTime(2026, 11, 23, 7), minutes: gymMinutes, sets: 9, volumeKg: 3000),
  values: const [],
  intensity: null,
  planned: null,
);

void main() {
  test('Wochen ab Montag, neueste zuerst, mit Anzahl und Dauer', () {
    final weeks = FeedWeek.group([
      entry(const CalendarDay(2026, 11, 24), seconds: 3000),
      entry(const CalendarDay(2026, 11, 23), gymMinutes: 55),
      entry(const CalendarDay(2026, 11, 22), seconds: 9000),
    ]);
    expect(weeks.map((week) => week.monday), [const CalendarDay(2026, 11, 23), const CalendarDay(2026, 11, 16)]);
    expect(weeks.first.minutes, 50 + 55);
    expect(weeks.first.header, 'KW 48 · 23.–29.11. · 2 Einheiten · 1:45 h');
    expect(weeks.last.header, 'KW 47 · 16.–22.11. · 1 Einheit · 2:30 h');
  });

  test('Woche über den Monatswechsel und KW 1', () {
    final week = FeedWeek.group([entry(const CalendarDay(2026, 12, 29), seconds: 600)]).single;
    expect(week.header, 'KW 53 · 28.12.–3.1. · 1 Einheit · 0:10 h');
    final first = FeedWeek.group([entry(const CalendarDay(2027, 1, 5))]).single;
    expect(first.isoWeek, 1);
    expect(first.header, 'KW 1 · 4.–10.1. · 1 Einheit');
  });
}

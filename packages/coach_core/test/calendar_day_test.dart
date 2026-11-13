import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  group('CalendarDay', () {
    test('liest ISO-Datum, auch mit Uhrzeit', () {
      expect(CalendarDay.tryParse('2026-10-23'), const CalendarDay(2026, 10, 23));
      expect(CalendarDay.tryParse('2026-10-23T00:00:00.0'), const CalendarDay(2026, 10, 23));
      expect(CalendarDay.tryParse('2026-13-01'), isNull);
      expect(CalendarDay.tryParse('2026-10'), isNull);
      expect(CalendarDay.tryParse('kein Datum'), isNull);
      expect(const CalendarDay(2026, 3, 7).iso, '2026-03-07');
    });

    test('rechnet über Monats-, Jahres- und Sommerzeitgrenzen', () {
      expect(const CalendarDay(2026, 10, 31).adding(1), const CalendarDay(2026, 11, 1));
      expect(const CalendarDay(2026, 1, 1).adding(-1), const CalendarDay(2025, 12, 31));
      expect(const CalendarDay(2028, 2, 28).adding(1), const CalendarDay(2028, 2, 29));
      // Zeitumstellung am 25.10.2026 (Europa) verschiebt nichts.
      expect(const CalendarDay(2026, 10, 24).daysUntil(const CalendarDay(2026, 10, 26)), 2);
      expect(const CalendarDay(2026, 10, 26).daysUntil(const CalendarDay(2026, 10, 24)), -2);
    });

    test('vergleicht und dient als Schlüssel', () {
      expect(const CalendarDay(2026, 1, 2) < const CalendarDay(2026, 2, 1), isTrue);
      expect({const CalendarDay(2026, 1, 2), CalendarDay.tryParse('2026-01-02')}.length, 1);
      final day = const CalendarDay(2026, 5, 9);
      expect(CalendarDay.fromJson(day.toJson()), day);
    });
  });

  group('DateRange', () {
    test('ordnet Anfang und Ende und zählt Tage', () {
      final range = DateRange(const CalendarDay(2026, 10, 10), const CalendarDay(2026, 10, 1));
      expect(range.start, const CalendarDay(2026, 10, 1));
      expect(range.dayCount, 10);
      expect(DateRange.last(7, endingOn: const CalendarDay(2026, 10, 7)).start, const CalendarDay(2026, 10, 1));
      expect(DateRange.last(0, endingOn: const CalendarDay(2026, 10, 7)).dayCount, 1);
    });

    test('teilt in Blöcke, neueste zuerst', () {
      final chunks = DateRange(const CalendarDay(2026, 10, 1), const CalendarDay(2026, 10, 10)).chunks(4);
      expect(chunks.map((chunk) => chunk.toString()), [
        '2026-10-07…2026-10-10',
        '2026-10-03…2026-10-06',
        '2026-10-01…2026-10-02',
      ]);
    });
  });

  test('Mahlzeit nach Uhrzeit', () {
    expect(MealCategory.guess(hour: 7, minute: 0), MealCategory.breakfast);
    expect(MealCategory.guess(hour: 10, minute: 30), MealCategory.lunch);
    expect(MealCategory.guess(hour: 15, minute: 0), MealCategory.snack);
    expect(MealCategory.guess(hour: 19, minute: 0), MealCategory.dinner);
    expect(MealCategory.guess(hour: 23, minute: 0), MealCategory.snack);
  });
}

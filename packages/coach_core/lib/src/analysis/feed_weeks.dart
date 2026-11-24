import '../calendar/calendar_day.dart';
import 'activity_feed.dart';

/// Woche im Verlauf (Roast Stufe 4 / PR 21): Aktivitäten von Montag bis Sonntag mit Anzahl und Dauer.
final class FeedWeek {
  const FeedWeek({required this.monday, required this.entries});

  final CalendarDay monday;
  final List<FeedEntry> entries;

  /// Trainingsminuten (Aufzeichnung bzw. Gym-Einheit; ohne Angabe zählt der Eintrag nicht mit).
  int get minutes => entries.fold(0, (sum, entry) {
    final seconds = entry.activity?.durationSeconds;
    if (seconds != null) return sum + (seconds / 60).round();
    return sum + (entry.gym?.minutes ?? 0);
  });

  /// ISO-Kalenderwoche (Woche mit dem ersten Donnerstag ist KW 1).
  int get isoWeek {
    final thursday = monday.adding(3);
    final january4 = CalendarDay(thursday.year, 1, 4);
    final firstMonday = january4.adding(-january4.weekdayIndex);
    return firstMonday.daysUntil(monday) ~/ 7 + 1;
  }

  /// „KW 47 · 23.–29.11.“
  String get title {
    final sunday = monday.adding(6);
    String dm(CalendarDay day) => '${day.day}.${day.month}.';
    final range = monday.month == sunday.month ? '${monday.day}.–${dm(sunday)}' : '${dm(monday)}–${dm(sunday)}';
    return 'KW $isoWeek · $range';
  }

  /// „KW 47 · 23.–29.11. · 6 Einheiten · 4:10 h“.
  String get header {
    final count = entries.length == 1 ? '1 Einheit' : '${entries.length} Einheiten';
    final time = minutes == 0 ? '' : ' · ${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h';
    return '$title · $count$time';
  }

  /// Einträge nach Wochen, neueste zuerst; innerhalb der Woche in der gegebenen Reihenfolge.
  static List<FeedWeek> group(List<FeedEntry> entries) {
    final weeks = <CalendarDay, List<FeedEntry>>{};
    for (final entry in entries) {
      (weeks[entry.day.adding(-entry.day.weekdayIndex)] ??= []).add(entry);
    }
    final mondays = weeks.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final monday in mondays) FeedWeek(monday: monday, entries: weeks[monday]!)];
  }
}

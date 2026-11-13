import '../calendar/calendar_day.dart';
import '../util/german_format.dart';
import 'week_schedule.dart';

/// Urlaub oder Trainingspause über mehrere Tage (Anregung: MCI, Paket 13). Im Zeitraum gibt es keine Erinnerungen an
/// Einheiten, nichts zählt als verpasst, und Begleiter und Rangliste werten die Tage nicht als geplant.
final class TrainingBreak {
  TrainingBreak(CalendarDay a, CalendarDay b) : start = a <= b ? a : b, end = a <= b ? b : a;

  final CalendarDay start;
  final CalendarDay end;

  bool contains(CalendarDay day) => day >= start && day <= end;

  /// Vorbei: danach nicht mehr anzeigen.
  bool isOver(CalendarDay today) => today > end;

  /// Wochenplan ohne die Tage im Zeitraum ([monday] = Montag der Woche).
  WeekSchedule removing(WeekSchedule schedule, {required CalendarDay monday}) {
    var result = schedule;
    for (final weekday in Weekday.values) {
      if (contains(monday.adding(weekday.index))) result = result.withSlots(const [], weekday);
    }
    return result;
  }

  String get label => '${GermanFormat.date(start)} bis ${GermanFormat.date(end)}';

  Map<String, Object?> toJson() => {'start': start.toJson(), 'end': end.toJson()};

  static TrainingBreak? fromJson(Object? json) {
    if (json is! Map || json['start'] is! Map || json['end'] is! Map) return null;
    return TrainingBreak(
      CalendarDay.fromJson((json['start'] as Map).cast<String, Object?>()),
      CalendarDay.fromJson((json['end'] as Map).cast<String, Object?>()),
    );
  }

  @override
  bool operator ==(Object other) => other is TrainingBreak && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

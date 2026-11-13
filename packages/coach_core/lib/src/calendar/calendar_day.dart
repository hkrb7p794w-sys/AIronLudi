/// Kalendertag ohne Uhrzeit und Zeitzone (Garmins `calendarDate`, z. B. `2026-10-23`).
final class CalendarDay implements Comparable<CalendarDay> {
  const CalendarDay(this.year, this.month, this.day);

  /// Tag des Zeitpunkts in dessen Zeitzone (lokal oder UTC, wie das `DateTime` vorliegt).
  factory CalendarDay.fromDate(DateTime date) => CalendarDay(date.year, date.month, date.day);

  /// Heute in der lokalen Zeitzone.
  factory CalendarDay.today([DateTime? now]) => CalendarDay.fromDate(now ?? DateTime.now());

  final int year;
  final int month;
  final int day;

  /// Liest `yyyy-MM-dd`, auch mit angehängter Uhrzeit (`2026-10-23T00:00:00.0`). Ungültig: `null`.
  static CalendarDay? tryParse(String text) {
    final head = text.length > 10 ? text.substring(0, 10) : text;
    final parts = head.split('-').where((part) => part.isNotEmpty).toList();
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return CalendarDay(year, month, day);
  }

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// Mittag UTC des Tages – stabil für Datumsrechnung ohne Sommerzeit-Effekte.
  DateTime get referenceDate => DateTime.utc(year, month, day, 12);

  CalendarDay adding(int days) => CalendarDay.fromDate(DateTime.utc(year, month, day + days, 12));

  /// Anzahl Tage von `this` bis [other] (positiv, wenn [other] später liegt).
  int daysUntil(CalendarDay other) => (other.referenceDate.difference(referenceDate).inHours / 24).round();

  bool operator <(CalendarDay other) => compareTo(other) < 0;
  bool operator <=(CalendarDay other) => compareTo(other) <= 0;
  bool operator >(CalendarDay other) => compareTo(other) > 0;
  bool operator >=(CalendarDay other) => compareTo(other) >= 0;

  @override
  int compareTo(CalendarDay other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDay && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;

  /// JSON wie in Swift (`Codable` einer Struktur mit drei Feldern).
  Map<String, Object?> toJson() => {'year': year, 'month': month, 'day': day};

  static CalendarDay fromJson(Map<String, Object?> json) =>
      CalendarDay(json['year']! as int, json['month']! as int, json['day']! as int);
}

/// Geschlossener Datumsbereich (beide Tage inklusive), wie ihn die Garmin-Endpunkte erwarten.
final class DateRange {
  DateRange(CalendarDay a, CalendarDay b) : start = a <= b ? a : b, end = a <= b ? b : a;

  /// Die letzten [days] Tage bis einschließlich [end].
  factory DateRange.last(int days, {required CalendarDay endingOn}) =>
      DateRange(endingOn.adding(-((days < 1 ? 1 : days) - 1)), endingOn);

  final CalendarDay start;
  final CalendarDay end;

  int get dayCount => start.daysUntil(end) + 1;

  /// Teilt den Bereich in Blöcke von höchstens [maxDays] Tagen (neueste zuerst), weil Garmin größere Bereiche mit
  /// 400/500 ohne Inhalt ablehnt.
  List<DateRange> chunks(int maxDays) {
    if (maxDays <= 0) return [this];
    final result = <DateRange>[];
    var chunkEnd = end;
    while (chunkEnd >= start) {
      final candidate = chunkEnd.adding(-(maxDays - 1));
      final chunkStart = candidate < start ? start : candidate;
      result.add(DateRange(chunkStart, chunkEnd));
      chunkEnd = chunkStart.adding(-1);
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start…$end';
}

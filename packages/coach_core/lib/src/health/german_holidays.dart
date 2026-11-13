import '../calendar/calendar_day.dart';
import '../util/enum_codec.dart';

/// Bundesländer für die gesetzlichen Feiertage.
enum GermanState implements RawEnum {
  bw('Baden-Württemberg'),
  by('Bayern'),
  be('Berlin'),
  bb('Brandenburg'),
  hb('Bremen'),
  hh('Hamburg'),
  he('Hessen'),
  mv('Mecklenburg-Vorpommern'),
  ni('Niedersachsen'),
  nw('Nordrhein-Westfalen'),
  rp('Rheinland-Pfalz'),
  sl('Saarland'),
  sn('Sachsen'),
  st('Sachsen-Anhalt'),
  sh('Schleswig-Holstein'),
  th('Thüringen');

  const GermanState(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;

  static GermanState? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Gesetzliche Feiertage je Bundesland und Jahr. Feiertage, die nur in einzelnen Gemeinden gelten (Fronleichnam in
/// Teilen von Sachsen und Thüringen, Mariä Himmelfahrt in Teilen Bayerns, Augsburger Friedensfest), zählen nicht.
abstract final class GermanHolidays {
  /// Ostersonntag (Gaußsche Osterformel in der Fassung von Meeus/Jones/Butcher).
  static CalendarDay easter(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return CalendarDay(year, month, day);
  }

  static Map<CalendarDay, String> all({required int year, required GermanState state}) {
    CalendarDay date(int month, int day) => CalendarDay(year, month, day);
    final easterDay = easter(year);
    final result = <CalendarDay, String>{
      date(1, 1): 'Neujahr',
      easterDay.adding(-2): 'Karfreitag',
      easterDay.adding(1): 'Ostermontag',
      date(5, 1): 'Tag der Arbeit',
      easterDay.adding(39): 'Christi Himmelfahrt',
      easterDay.adding(50): 'Pfingstmontag',
      date(10, 3): 'Tag der Deutschen Einheit',
      date(12, 25): '1. Weihnachtstag',
      date(12, 26): '2. Weihnachtstag',
    };
    bool any(List<GermanState> states) => states.contains(state);
    if (any(const [GermanState.bw, GermanState.by, GermanState.st])) result[date(1, 6)] = 'Heilige Drei Könige';
    if ((state == GermanState.be && year >= 2019) || (state == GermanState.mv && year >= 2023)) {
      result[date(3, 8)] = 'Frauentag';
    }
    if (any(const [GermanState.bw, GermanState.by, GermanState.he, GermanState.nw, GermanState.rp, GermanState.sl])) {
      result[easterDay.adding(60)] = 'Fronleichnam';
    }
    if (state == GermanState.sl) result[date(8, 15)] = 'Mariä Himmelfahrt';
    if (state == GermanState.th && year >= 2019) result[date(9, 20)] = 'Weltkindertag';
    if (any(const [GermanState.bb, GermanState.mv, GermanState.sn, GermanState.st, GermanState.th]) ||
        (any(const [GermanState.hb, GermanState.hh, GermanState.ni, GermanState.sh]) && year >= 2018)) {
      result[date(10, 31)] = 'Reformationstag';
    }
    if (any(const [GermanState.bw, GermanState.by, GermanState.nw, GermanState.rp, GermanState.sl])) {
      result[date(11, 1)] = 'Allerheiligen';
    }
    if (state == GermanState.sn) {
      // Mittwoch vor dem 23. November.
      var day = date(11, 22);
      while (day.weekdayIndex != 2) {
        day = day.adding(-1);
      }
      result[day] = 'Buß- und Bettag';
    }
    return result;
  }

  static String? name(CalendarDay day, {required GermanState state}) => all(year: day.year, state: state)[day];
}

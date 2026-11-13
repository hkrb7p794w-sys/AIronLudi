import '../calendar/calendar_day.dart';

/// Zahlen und Daten in deutscher Schreibweise (Port von `GermanFormat`).
abstract final class GermanFormat {
  /// Eine Nachkommastelle mit Komma, ohne „,0“ bei ganzen Zahlen: 4,5 / 6.
  static String decimal(double value) {
    final rounded = (value * 10).roundToDouble() / 10;
    if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
    return rounded.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Bis zu zwei Nachkommastellen mit Komma, ohne Nullen am Ende: 52,5 / 13,75 / 55.
  static String number(double value) {
    final rounded = (value * 100).roundToDouble() / 100;
    if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
    var text = rounded.toStringAsFixed(2);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    return text.replaceAll('.', ',');
  }

  /// `dd.MM.yyyy`
  static String date(CalendarDay day) => '${_two(day.day)}.${_two(day.month)}.${day.year.toString().padLeft(4, '0')}';

  /// `m:ss`
  static String minutesSeconds(int seconds) => '${seconds ~/ 60}:${_two(seconds % 60)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

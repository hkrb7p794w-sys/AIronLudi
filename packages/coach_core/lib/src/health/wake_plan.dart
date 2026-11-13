import '../coach/sleep_coach.dart';
import '../util/enum_codec.dart';

/// Uhrzeit des Weckers (Ortszeit).
final class WakeTime {
  WakeTime({required int hour, required int minute}) : hour = hour.clamp(0, 23), minute = minute.clamp(0, 59);

  factory WakeTime.fromMinutes(int minutes) {
    final value = (minutes % 1440 + 1440) % 1440;
    return WakeTime(hour: value ~/ 60, minute: value % 60);
  }

  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;
  String get text => SleepCoach.clock(minutes);

  Map<String, Object?> toJson() => {'hour': hour, 'minute': minute};

  /// Wie das synthetisierte `Decodable` (ohne Grenzen beim Lesen).
  static WakeTime? fromJson(Object? json) {
    if (json is! Map || json['hour'] is! int || json['minute'] is! int) return null;
    return WakeTime._raw(json['hour'] as int, json['minute'] as int);
  }

  WakeTime._raw(this.hour, this.minute);

  @override
  bool operator ==(Object other) => other is WakeTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => text;
}

/// Wiederholung des Weckers.
enum WakeRepeat implements RawEnum {
  once,
  weekdays,
  daily;

  @override
  String get rawValue => name;

  String get label => switch (this) {
    once => 'Einmalig',
    weekdays => 'Mo–Fr',
    daily => 'Täglich',
  };

  /// Wochentage wie `weekdays` bzw. `Calendar` in Swift (1 = Sonntag … 7 = Samstag); leer = einmalig.
  List<int> get calendarWeekdays => switch (this) {
    once => const [],
    WakeRepeat.weekdays => const [2, 3, 4, 5, 6],
    daily => const [1, 2, 3, 4, 5, 6, 7],
  };

  static WakeRepeat? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Aufstehzeit für den Wecker: aus der Weckzeit des Schlaf-Coaches oder „jetzt ins Bett“ plus Schlafbedarf.
/// Gestellt wird eine Uhrzeit (Ortszeit), kein fester Zeitpunkt – so bleibt der Wecker nach einem Zeitzonenwechsel
/// oder der Zeitumstellung auf derselben Uhrzeit.
abstract final class WakePlan {
  /// Wer jetzt ins Bett geht: jetzt + Einschlafzeit + Schlafbedarf, auf 5 Minuten aufgerundet.
  static WakeTime wakeIfSleepingNow({
    required int nowMinutes,
    required int sleepMinutes,
    int latency = SleepCoach.latencyMinutes,
  }) {
    final raw = nowMinutes + latency + sleepMinutes;
    return WakeTime.fromMinutes((raw / 5).ceil() * 5);
  }

  /// Schlafdauer bis zur Weckzeit, wenn man um [bedtimeMinutes] ins Bett geht (ohne Einschlafzeit).
  static int sleepMinutes({
    required int bedtimeMinutes,
    required WakeTime wake,
    int latency = SleepCoach.latencyMinutes,
  }) => ((wake.minutes - bedtimeMinutes - latency) % 1440 + 1440) % 1440;

  /// Nächster Zeitpunkt mit dieser Uhrzeit nach [now] (für „morgen 6:30“) in der Zeitzone des Geräts; berücksichtigt
  /// Zeitumstellungen.
  static DateTime nextDate(WakeTime time, {required DateTime now}) {
    final local = now.toLocal();
    var candidate = DateTime(local.year, local.month, local.day, time.hour, time.minute);
    var offset = 0;
    while (!candidate.isAfter(local)) {
      offset += 1;
      candidate = DateTime(local.year, local.month, local.day + offset, time.hour, time.minute);
    }
    return candidate;
  }

  /// „heute 23:00“, „morgen 6:30“ oder Wochentag.
  static String dayLabel(DateTime date, {required DateTime now}) {
    final (target, current) = (date.toLocal(), now.toLocal());
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    if (same(target, current)) return 'heute';
    if (same(target, DateTime(current.year, current.month, current.day + 1))) return 'morgen';
    const names = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    return 'am ${names[target.weekday - 1]}';
  }
}

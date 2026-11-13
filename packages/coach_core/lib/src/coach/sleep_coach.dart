import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../health/german_holidays.dart';
import '../profile/user_profile.dart';
import '../util/german_format.dart';

/// Der in der App gestellte Wecker. Der Wecker der Uhr-App ist für Apps nicht lesbar.
final class SleepAlarm {
  const SleepAlarm({required this.minutes, this.onlyDay, this.weekdaysOnly = false});

  final int minutes;

  /// Bei einem einmaligen Wecker der Tag, an dem er klingelt.
  final CalendarDay? onlyDay;
  final bool weekdaysOnly;

  bool rings(CalendarDay day) {
    if (onlyDay case final only?) return only == day;
    return !weekdaysOnly || day.weekdayIndex < 5;
  }

  Map<String, Object?> toJson() => {'minutes': minutes, 'onlyDay': ?onlyDay?.toJson(), 'weekdaysOnly': weekdaysOnly};

  static SleepAlarm? fromJson(Object? json) {
    if (json is! Map) return null;
    final (minutes, weekdaysOnly, rawDay) = (json['minutes'], json['weekdaysOnly'], json['onlyDay']);
    if (minutes is! int || weekdaysOnly is! bool) return null;
    CalendarDay? day;
    if (rawDay is Map<String, Object?>) {
      try {
        day = CalendarDay.fromJson(rawDay);
      } on Object {
        return null;
      }
    } else if (rawDay != null) {
      return null;
    }
    return SleepAlarm(minutes: minutes, onlyDay: day, weekdaysOnly: weekdaysOnly);
  }

  @override
  bool operator ==(Object other) =>
      other is SleepAlarm && other.minutes == minutes && other.onlyDay == onlyDay && other.weekdaysOnly == weekdaysOnly;

  @override
  int get hashCode => Object.hash(minutes, onlyDay, weekdaysOnly);
}

/// Einstellungen des Schlaf-Coaches: gewünschte Schlafdauer, Weckzeit und Erinnerung vor dem Zubettgehen.
final class SleepSettings {
  SleepSettings();

  /// Gewünschte Schlafdauer in Stunden (7–9, Empfehlung für Erwachsene).
  double targetHours = 8;
  int wakeHour = 6;
  int wakeMinute = 30;

  /// Mitteilung 30 Minuten vor der empfohlenen Schlafenszeit.
  bool reminder = false;

  /// An freien Tagen (Wochenende, Feiertag) eine andere Aufstehzeit.
  bool usesFreeDayTime = false;
  int freeWakeHour = 8;
  int freeWakeMinute = 0;

  /// Für die Feiertage; ohne Angabe zählen nur Wochenenden als frei.
  GermanState? state;

  /// Gestellter Wecker; er geht den eingestellten Aufstehzeiten vor.
  SleepAlarm? alarm;

  int get wakeMinutes => wakeHour * 60 + wakeMinute;
  int get freeWakeMinutes => freeWakeHour * 60 + freeWakeMinute;

  /// Feiertag an diesem Tag laut Bundesland.
  String? holiday(CalendarDay day) => state == null ? null : GermanHolidays.name(day, state: state!);

  bool isFree(CalendarDay day) => day.weekdayIndex >= 5 || holiday(day) != null;

  /// Aufstehzeit an einem Tag, Minuten nach Mitternacht.
  int wakeMinutesOn(CalendarDay day) {
    if (alarm case final alarm? when alarm.rings(day)) return alarm.minutes;
    return usesFreeDayTime && isFree(day) ? freeWakeMinutes : wakeMinutes;
  }

  Map<String, Object?> toJson() => {
    'targetHours': targetHours,
    'wakeHour': wakeHour,
    'wakeMinute': wakeMinute,
    'reminder': reminder,
    'usesFreeDayTime': usesFreeDayTime,
    'freeWakeHour': freeWakeHour,
    'freeWakeMinute': freeWakeMinute,
    'state': ?state?.rawValue,
    'alarm': ?alarm?.toJson(),
  };

  /// Wie der eigene Swift-Decoder: Werte werden auf ihre Grenzen gesetzt, Unlesbares fällt auf den Standard zurück.
  static SleepSettings fromJson(Object? json) {
    final settings = SleepSettings();
    if (json is! Map) return settings;
    int number(String key, int fallback, int lower, int upper) =>
        (json[key] is int ? json[key] as int : fallback).clamp(lower, upper);
    bool flag(String key) => json[key] is bool && json[key] as bool;
    final hours = json['targetHours'];
    return settings
      ..targetHours = (hours is num ? hours.toDouble() : 8.0).clamp(7.0, 9.0)
      ..wakeHour = number('wakeHour', 6, 0, 23)
      ..wakeMinute = number('wakeMinute', 30, 0, 59)
      ..reminder = flag('reminder')
      ..usesFreeDayTime = flag('usesFreeDayTime')
      ..freeWakeHour = number('freeWakeHour', 8, 0, 23)
      ..freeWakeMinute = number('freeWakeMinute', 0, 0, 59)
      ..state = GermanState.fromRaw(json['state'])
      ..alarm = SleepAlarm.fromJson(json['alarm']);
  }
}

/// Hinweis des Schlaf-Coaches.
final class SleepTip {
  const SleepTip({required this.id, required this.text, required this.evidenceIDs});

  final String id;
  final String text;
  final List<String> evidenceIDs;

  @override
  String toString() => 'SleepTip($id, $text)';
}

/// Bericht des Schlaf-Coaches.
final class SleepReport {
  const SleepReport({
    required this.nights,
    required this.averageHours,
    required this.shortNights,
    required this.debtHours,
    required this.tonightMinutes,
    required this.bedtimeMinutes,
    required this.bedtimeSpreadMinutes,
    required this.tips,
    this.nextDayIsFree = false,
    this.nextHoliday,
    this.nextWakeMinutes = 0,
  });

  final int nights;
  final double averageHours;
  final int shortNights;

  /// Fehlende Stunden der letzten 7 Nächte gegenüber dem Ziel.
  final double debtHours;

  /// Schlafbedarf heute Nacht in Minuten.
  final int tonightMinutes;

  /// Empfohlene Zeit zum Hinlegen, Minuten nach Mitternacht.
  final int bedtimeMinutes;

  /// Streuung der Einschlafzeit in Minuten (nur mit mindestens 4 bekannten Zeiten).
  final double? bedtimeSpreadMinutes;
  final List<SleepTip> tips;

  /// Gilt morgen die Aufstehzeit für freie Tage?
  final bool nextDayIsFree;

  /// Name des Feiertags morgen.
  final String? nextHoliday;

  /// Aufstehzeit morgen, Minuten nach Mitternacht.
  final int nextWakeMinutes;
}

/// Schlaf-Coach wie bei Whoop, aber mit offenen Regeln: Schlafbedarf für heute Nacht, empfohlene Schlafenszeit,
/// Regelmäßigkeit und Hinweise. Grundlage: 7–9 Stunden für Erwachsene (Watson et al. 2015), mehr Schlaf verbesserte
/// Leistung bei Sportlern (Mah et al. 2011), regelmäßige Schlafzeiten (Windred et al. 2024).
abstract final class SleepCoach {
  /// Zeit zum Einschlafen, die zur Bettzeit dazukommt (Praxiswert).
  static const latencyMinutes = 15;

  /// Nachholen nach kurzen Nächten: ein Viertel des Defizits der letzten 7 Nächte, höchstens 60 Minuten
  /// (Praxiswert, kein Studienergebnis).
  static const maxExtraMinutes = 60.0;

  /// Ab dieser Streuung der Einschlafzeit (Standardabweichung in Minuten) gilt der Schlaf als unregelmäßig.
  static const irregularMinutes = 60.0;

  /// Bericht aus den letzten 7 Nächten bis einschließlich [today] (Garmin ordnet die Nacht dem Aufwachtag zu).
  static SleepReport? report({
    required List<DailyMetrics> days,
    required SleepSettings settings,
    required FitnessGoal? goal,
    required CalendarDay today,
  }) {
    final start = today.adding(-6);
    final nights = days
        .where((metrics) => metrics.day >= start && metrics.day <= today && (metrics.sleepSeconds ?? 0) > 0)
        .toList();
    if (nights.length < 3) return null;
    final hours = [for (final night in nights) (night.sleepSeconds ?? 0) / 3600];
    final average = hours.fold(0.0, (sum, value) => sum + value) / hours.length;
    final debt = hours.fold(0.0, (sum, value) => sum + math.max(0.0, settings.targetHours - value));
    final extra = math.min(debt * 60 / 4, maxExtraMinutes);
    final tonight = ((settings.targetHours * 60 + extra) / 5).round() * 5;
    final tomorrow = today.adding(1);
    final wake = settings.wakeMinutesOn(tomorrow);
    final nextIsFree = settings.usesFreeDayTime && settings.isFree(tomorrow);
    final bedtime = ((wake - tonight - latencyMinutes) % 1440 + 1440) % 1440;

    // Einschlafzeiten relativ zu 12 Uhr, damit 23:30 und 0:30 nah beieinander liegen.
    final starts = [
      for (final night in nights)
        if (night.sleepStartMinutes case final minutes?) (minutes + 720).remainder(1440),
    ];
    double? spread;
    if (starts.length >= 4) {
      final mean = starts.fold(0.0, (sum, value) => sum + value) / starts.length;
      spread = math
          .sqrt(starts.fold(0.0, (sum, value) => sum + (value - mean) * (value - mean)) / starts.length)
          .roundToDouble();
    }

    final tips = <SleepTip>[];
    final shortNights = hours.where((value) => value < 7).length;
    if (average < 7) {
      tips.add(
        SleepTip(
          id: 'short',
          text:
              'Im Schnitt ${GermanFormat.decimal(average)} Stunden – weniger als die empfohlenen 7. Gehe heute um '
              '${clock(bedtime)} ins Bett, um wieder auf ${GermanFormat.decimal(tonight / 60)} Stunden '
              'zu kommen.',
          evidenceIDs: const ['recovery.sleep', 'sleep.extension'],
        ),
      );
      if (goal?.losesWeight ?? false) {
        tips.add(
          const SleepTip(
            id: 'weight',
            text: 'Gerade beim Abnehmen hilft ausreichend Schlaf, Muskeln zu erhalten.',
            evidenceIDs: ['weightloss.sleep'],
          ),
        );
      }
    } else if (extra >= 15) {
      tips.add(
        SleepTip(
          id: 'catch-up',
          text:
              'Einige Nächte waren kürzer als dein Ziel. Heute etwa ${extra.toInt()} Minuten früher ins Bett hilft '
              'beim Aufholen.',
          evidenceIDs: const ['sleep.extension'],
        ),
      );
    } else {
      tips.add(
        const SleepTip(
          id: 'good',
          text: 'Dein Schlaf passt zu deinem Ziel. Bleib bei deinen Zeiten.',
          evidenceIDs: ['recovery.sleep'],
        ),
      );
    }
    if (spread != null && spread > irregularMinutes) {
      tips.add(
        SleepTip(
          id: 'regular',
          text:
              'Deine Einschlafzeit schwankt um etwa ${spread.toInt()} Minuten. Feste Zeiten – auch am Wochenende – '
              'machen den Schlaf erholsamer.',
          evidenceIDs: const ['sleep.regularity'],
        ),
      );
    }
    if (nextIsFree) {
      final reason = settings.holiday(tomorrow) ?? 'Morgen ist frei';
      tips.insert(
        0,
        SleepTip(
          id: 'free',
          text: '$reason: Aufstehen gegen ${clock(wake)}, Schlafenszeit ${clock(bedtime)}.',
          evidenceIDs: const ['sleep.regularity'],
        ),
      );
      if (settings.freeWakeMinutes - settings.wakeMinutes > 90) {
        tips.add(
          const SleepTip(
            id: 'social-jetlag',
            text: 'Mehr als anderthalb Stunden später als unter der Woche macht den Montag schwerer.',
            evidenceIDs: ['sleep.regularity'],
          ),
        );
      }
    }
    return SleepReport(
      nights: nights.length,
      averageHours: (average * 10).roundToDouble() / 10,
      shortNights: shortNights,
      debtHours: (debt * 10).roundToDouble() / 10,
      tonightMinutes: tonight,
      bedtimeMinutes: bedtime,
      bedtimeSpreadMinutes: spread,
      tips: tips,
      nextDayIsFree: nextIsFree,
      nextHoliday: settings.holiday(tomorrow),
      nextWakeMinutes: wake,
    );
  }

  /// „22:15“
  static String clock(int minutes) {
    final value = (minutes % 1440 + 1440) % 1440;
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }
}

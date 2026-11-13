import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import 'load_check.dart';
import 'user_profile.dart';
import 'week_schedule.dart';

/// Art der Laufwoche.
enum RunPhase {
  build,
  deload,
  taper,
  race;

  String get label => switch (this) {
    build => 'Aufbauwoche',
    deload => 'Entlastungswoche',
    taper => 'Tapering',
    race => 'Wettkampfwoche',
  };
}

/// Eine Laufeinheit der Woche.
final class RunSession {
  const RunSession({required this.weekday, required this.slot, required this.minutes, required this.detail});

  final Weekday weekday;
  final SessionSlot slot;
  final int minutes;

  /// Inhalt in einem Satz, z. B. „5 × 3 Minuten zügig, 2 Minuten Trabpause“.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is RunSession &&
      other.weekday == weekday &&
      other.slot == slot &&
      other.minutes == minutes &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(weekday, slot, minutes, detail);

  @override
  String toString() => 'RunSession($weekday, ${slot.id}, $minutes, $detail)';
}

/// Laufwoche.
final class RunWeek {
  const RunWeek({
    required this.monday,
    required this.phase,
    required this.baselineMinutes,
    required this.totalMinutes,
    required this.sessions,
  });

  final CalendarDay monday;
  final RunPhase phase;

  /// Wochenschnitt der letzten vier Wochen (Minuten), Grundlage der Steigerung.
  final int baselineMinutes;
  final int totalMinutes;
  final List<RunSession> sessions;
}

/// Konkrete Laufwoche für persönliche Profile: Minuten je Einheit und Inhalt der Qualitätseinheit, mit vorsichtiger
/// Steigerung aus dem tatsächlichen Umfang der letzten Wochen (Garmin). Regeln:
/// - Ausgangspunkt ist der Wochenschnitt der letzten vier Wochen, nicht der Plan: Wer weniger geschafft hat, startet
///   von dort (passt sich an wie Runna).
/// - Höchstens 10 % mehr als dieser Schnitt; die feste 10-%-Regel schützt zwar nicht nachweislich (Buist 2007), über
///   30 % Steigerung wurden aber mehr Verletzungen beobachtet (Nielsen 2014) – 10 % hält großen Abstand.
/// - Jede vierte Woche ist eine Entlastungswoche mit 70 % (Bell et al. 2023: übliche Praxis, kein festes Maß).
/// - Vor einem Wettkampf zwei Wochen Tapering: 70 %, dann 50 % (Umfang um 40–60 % senken, Wang et al. 2023).
/// - Der lange Lauf ist etwa 1,4-mal so lang wie ein lockerer, die Qualitätseinheit (mit Ein- und Auslaufen) etwa
///   0,9-mal (Praxiswerte).
abstract final class RunPlanner {
  static const maxIncrease = 0.10;
  static const deloadShare = 0.70;
  static const minimumSessionMinutes = 20;
  static const _anchor = CalendarDay(2026, 1, 5);

  /// Startumfang ohne Garmin-Verlauf (Minuten pro Woche) nach Erfahrung.
  static double startMinutes(ExperienceLevel level) => switch (level) {
    ExperienceLevel.beginner => 60,
    ExperienceLevel.intermediate => 120,
    ExperienceLevel.advanced => 180,
  };

  /// Obergrenze pro Woche nach Erfahrung (Minuten).
  static double capMinutes(ExperienceLevel level) => switch (level) {
    ExperienceLevel.beginner => 180,
    ExperienceLevel.intermediate => 330,
    ExperienceLevel.advanced => 480,
  };

  static Iterable<GarminActivity> _runs(List<GarminActivity> activities, CalendarDay start, CalendarDay monday) =>
      activities.where((activity) {
        final day = activity.day;
        return activity.sport == ActivitySport.run && day != null && start <= day && day < monday;
      });

  /// Lauf-Minuten pro Woche im Schnitt der vier vollen Wochen vor [monday]; `null` ohne Läufe.
  static double? baseline(List<GarminActivity> activities, {required CalendarDay before}) {
    final runs = _runs(activities, before.adding(-28), before).toList();
    if (runs.isEmpty) return null;
    return runs.fold(0.0, (sum, run) => sum + (run.durationSeconds ?? 0)) / 60 / 4;
  }

  /// Dauer des längsten Laufs der 30 Tage vor [before]; `null` ohne Läufe.
  static double? longestRunMinutes(List<GarminActivity> activities, {required CalendarDay before}) {
    final durations = _runs(activities, before.adding(-30), before).map((run) => run.durationSeconds).nonNulls;
    return durations.isEmpty ? null : durations.reduce(math.max) / 60;
  }

  /// Woche im 4er-Rhythmus seit Montag, 5.1.2026 (0–3).
  static int _cycleWeek(CalendarDay monday) => ((_anchor.daysUntil(monday) ~/ 7).remainder(4) + 4) % 4;

  static RunPhase phase(CalendarDay monday, {required EventGoal? event}) {
    if (event != null) {
      final days = monday.daysUntil(event.date);
      if (days >= 0 && days < 7) return RunPhase.race;
      if (days >= 7 && days < 14) return RunPhase.taper;
    }
    // Feste Zählung ab Montag, 5.1.2026: jede vierte Woche entlastet.
    return _cycleWeek(monday) == 3 ? RunPhase.deload : RunPhase.build;
  }

  /// Woche ab [monday] (Montag) für die Laufeinheiten des Wochenplans; `null`, wenn keine Laufeinheit geplant ist.
  static RunWeek? week({
    required UserProfile profile,
    required WeekSchedule schedule,
    required CalendarDay monday,
    required List<GarminActivity> activities,
  }) {
    final runDays = [
      for (final weekday in Weekday.values)
        for (final slot in schedule.slots(weekday))
          if (slot.sport == TrainingSport.run) (weekday, slot),
    ];
    if (runDays.isEmpty) return null;
    final level = profile.level(TrainingSport.run);
    final kilometers = profile.currentRunKilometersPerWeek;
    final fallback = kilometers != null ? kilometers * 6.5 : startMinutes(level);
    final base = baseline(activities, before: monday) ?? fallback;
    final weekPhase = phase(monday, event: profile.event);
    // Steigerung nur in Aufbauwochen; nie über die Obergrenze der Erfahrungsstufe (außer man läuft schon mehr).
    final cap = math.max(capMinutes(level), base);
    final build = math.min(base * (1 + maxIncrease), cap);
    final total = switch (weekPhase) {
      RunPhase.build => build,
      RunPhase.deload => base * deloadShare,
      RunPhase.taper => base * 0.7,
      RunPhase.race => base * 0.5,
    };
    final sessions = distribute(
      total: total,
      runDays: runDays,
      level: level,
      monday: monday,
      phase: weekPhase,
      event: profile.event,
      longest: longestRunMinutes(activities, before: monday),
    );
    return RunWeek(
      monday: monday,
      phase: weekPhase,
      baselineMinutes: base.round(),
      totalMinutes: sessions.fold(0, (sum, session) => sum + session.minutes),
      sessions: sessions,
    );
  }

  static List<RunSession> distribute({
    required double total,
    required List<(Weekday, SessionSlot)> runDays,
    required ExperienceLevel level,
    required CalendarDay monday,
    required RunPhase phase,
    required EventGoal? event,
    double? longest,
  }) {
    // Mit nur einer Laufeinheit ist sie die ganze Woche; sonst Anteile nach Gewicht (locker 1, Qualität 0,9, lang 1,4).
    final single = runDays.length == 1;
    SessionIntensity role(SessionSlot slot) => single ? SessionIntensity.easy : slot.intensity;
    double weight(SessionIntensity intensity) => switch (intensity) {
      SessionIntensity.easy => 1,
      SessionIntensity.hard => 0.9,
      SessionIntensity.long => 1.4,
    };
    final unit = total / runDays.fold(0.0, (sum, entry) => sum + weight(role(entry.$2)));
    final week = _cycleWeek(monday);
    return [
      for (final (weekday, slot) in runDays)
        () {
          final intensity = role(slot);
          // Keine Einheit weit über dem längsten Lauf der letzten 30 Tage (Frandsen et al. 2025).
          final minutes = math.min(
            unit * weight(intensity),
            longest == null ? double.infinity : longest * LoadCheck.singleRunLimit,
          );
          var detail = switch (intensity) {
            SessionIntensity.long => 'Ruhig und gleichmäßig, du kannst dich dabei unterhalten.',
            SessionIntensity.hard => quality(level, week: week, phase: phase),
            SessionIntensity.easy => 'Locker im Gesprächstempo.',
          };
          if (phase == RunPhase.race && event != null && Weekday.of(event.date) == weekday) {
            detail = 'Wettkampf: ${event.name}. Viel Erfolg!';
          }
          final rounded = math.max((minutes / 5).round() * 5, minimumSessionMinutes);
          return RunSession(weekday: weekday, slot: slot, minutes: rounded, detail: detail);
        }(),
    ];
  }

  /// Inhalt der Qualitätseinheit, wöchentlich leicht steigend (Praxiswerte); ohne Pace, nach Gefühl und Puls.
  static String quality(ExperienceLevel level, {required int week, required RunPhase phase}) {
    if (phase == RunPhase.taper || phase == RunPhase.race) {
      return 'Kurz und zügig: 4 × 1 Minute flott, 2 Minuten locker – frisch bleiben.';
    }
    if (phase == RunPhase.deload) return 'Locker mit 6 kurzen Steigerungen (20 Sekunden) zum Schluss.';
    final index = math.min(week, 2);
    return switch (level) {
      ExperienceLevel.beginner => const [
        '6 × 1 Minute zügig, 2 Minuten gehen oder traben.',
        '8 × 1 Minute zügig, 2 Minuten traben.',
        '5 × 2 Minuten zügig, 2 Minuten traben.',
      ][index],
      ExperienceLevel.intermediate => const [
        '5 × 3 Minuten zügig, 2 Minuten Trabpause.',
        '4 × 4 Minuten zügig, 3 Minuten Trabpause.',
        '3 × 8 Minuten an der Schwelle, 2 Minuten Trabpause.',
      ][index],
      ExperienceLevel.advanced => const [
        '6 × 3 Minuten zügig, 2 Minuten Trabpause.',
        '5 × 4 Minuten zügig, 3 Minuten Trabpause.',
        '3 × 10 Minuten an der Schwelle, 2 Minuten Trabpause.',
      ][index],
    };
  }
}

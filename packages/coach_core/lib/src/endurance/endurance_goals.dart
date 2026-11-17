import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/season_plan.dart';
import '../profile/personalization.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import 'endurance_plan.dart';

/// Ein Wettkampf, den die App schon kennt (Einrichtung bzw. Saisonplan), als Ziel für den Ausdauerplan.
final class KnownGoal {
  const KnownGoal({required this.name, required this.day, required this.event, this.targetMinutes, this.source = ''});

  final String name;
  final CalendarDay day;

  /// Art des Wettkampfs; `null`, wenn sie sich aus den Angaben nicht ableiten lässt (dann wählt die Person).
  final EnduranceEvent? event;
  final int? targetMinutes;

  /// Woher das Ziel stammt („Deine Ziele“, „Saisonplan“).
  final String source;

  String get id => '${day.iso}|$name';
}

/// Vorgaben für den Ausdauerplan aus dem, was die Person in der App schon gepflegt hat: Wettkampf aus der Einrichtung
/// bzw. die Rennen des Saisonplans (nur im Modus Saisonplan – keine Saisonwerte für andere Personen), Sportarten,
/// Ziele und Wochenplan. Regeln, deterministisch; die Person kann alles ändern.
abstract final class EnduranceGoals {
  /// Bekannte Wettkämpfe ab heute, der nächste zuerst.
  static List<KnownGoal> known(UserProfile profile, SeasonConfig season, {required CalendarDay today}) {
    final result = <KnownGoal>[];
    if (profile.mode == ProfileMode.season) {
      result
        ..add(
          KnownGoal(
            name: season.mainRaceName,
            day: season.mainRaceDate,
            event: EnduranceEvent.triMiddle,
            targetMinutes: firstClock(season.raceGoal),
            source: 'Saisonplan',
          ),
        )
        ..add(
          KnownGoal(
            name: 'Marathon',
            day: season.marathonDate,
            event: EnduranceEvent.marathon,
            targetMinutes: (season.marathonPaceSecondsPerKm * 42.195 / 60).round(),
            source: 'Saisonplan',
          ),
        );
    }
    if (profile.event case final event?) {
      final goal = KnownGoal(
        name: event.name.trim().isEmpty ? event.kind.label : event.name.trim(),
        day: event.date,
        event: eventOf(event, profile),
        targetMinutes: event.targetSeconds == null ? null : (event.targetSeconds! / 60).round(),
        source: 'Deine Ziele',
      );
      if (!result.any((other) => other.day == goal.day)) result.add(goal);
    }
    return [
      for (final goal in result..sort((a, b) => a.day.compareTo(b.day)))
        if (goal.day > today) goal,
    ];
  }

  /// Art des Wettkampfs aus der Einrichtung. Beim Triathlon entscheidet der Name (Sprint, olympisch, 70.3/Mittel,
  /// Langdistanz), sonst olympisch; „Anderer Wettkampf“ nur, wenn genau eine Ausdauersportart trainiert wird.
  static EnduranceEvent? eventOf(EventGoal event, UserProfile profile) {
    switch (event.kind) {
      case EventKind.run5k:
        return EnduranceEvent.run5k;
      case EventKind.run10k:
        return EnduranceEvent.run10k;
      case EventKind.halfMarathon:
        return EnduranceEvent.halfMarathon;
      case EventKind.marathon:
        return EnduranceEvent.marathon;
      case EventKind.triathlon:
        final name = event.name.toLowerCase();
        if (name.contains('sprint')) return EnduranceEvent.triSprint;
        if (name.contains('70.3') || name.contains('mittel') || name.contains('half') || name.contains('almere')) {
          return EnduranceEvent.triMiddle;
        }
        if (name.contains('ironman') || name.contains('lang') || name.contains('full') || name.contains('140.6')) {
          return EnduranceEvent.triFull;
        }
        return EnduranceEvent.triOlympic;
      case EventKind.other:
        final endurance = profile.sports.where((sport) => sport.isEndurance).toList();
        if (endurance.length != 1) return null;
        return switch (endurance.single) {
          TrainingSport.bike => EnduranceEvent.bikeEvent,
          TrainingSport.swim => EnduranceEvent.swimEvent,
          _ => null,
        };
    }
  }

  /// Erste Uhrzeit „h:mm“ im Text in Minuten („Finish in 5:30–6:00 h“ → 330).
  static int? firstClock(String text) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  static EnduranceSport? _sport(TrainingSport sport) => switch (sport) {
    TrainingSport.run => EnduranceSport.run,
    TrainingSport.bike => EnduranceSport.bike,
    TrainingSport.swim => EnduranceSport.swim,
    TrainingSport.strength || TrainingSport.other => null,
  };

  /// Ausdauersportarten des Profils (Reihenfolge wie im Profil).
  static List<EnduranceSport> sports(UserProfile profile) => [for (final sport in profile.sports) ?_sport(sport)];

  /// Trainingstage aus dem Wochenplan: Tage mit Ausdauereinheit, sonst alle Trainingstage, sonst Di/Do/Sa/So.
  static List<Weekday> days(UserProfile profile) {
    final schedule = profile.schedule;
    final endurance = [
      for (final day in Weekday.values)
        if (schedule.slots(day).any((slot) => slot.sport.isEndurance)) day,
    ];
    if (endurance.isNotEmpty) return endurance;
    if (schedule.trainingDays.isNotEmpty) return schedule.trainingDays;
    return const [Weekday.tuesday, Weekday.thursday, Weekday.saturday, Weekday.sunday];
  }

  /// Tag der langen Einheit: wo im Wochenplan eine lange Einheit steht, sonst der letzte Trainingstag.
  static Weekday longDay(UserProfile profile, List<Weekday> days) {
    for (final day in Weekday.values) {
      if (profile.schedule
          .slots(day)
          .any((slot) => slot.intensity == SessionIntensity.long && slot.sport.isEndurance)) {
        return day;
      }
    }
    return days.isEmpty ? Weekday.sunday : days.last;
  }

  /// Zeit je Woche aus dem Wochenplan (locker 45, hart 60, lang 100 min je Ausdauereinheit), in halben Stunden,
  /// mindestens 2 h; ohne Ausdauereinheiten nach Erfahrung (3, 5 bzw. 7 h).
  static int weeklyMinutes(UserProfile profile) {
    var minutes = 0;
    for (final day in Weekday.values) {
      for (final slot in profile.schedule.slots(day)) {
        if (!slot.sport.isEndurance) continue;
        minutes += switch (slot.intensity) {
          SessionIntensity.easy => 45,
          SessionIntensity.hard => 60,
          SessionIntensity.long => 100,
        };
      }
    }
    if (minutes == 0) {
      minutes = switch (profile.enduranceLevel) {
        ExperienceLevel.beginner => 180,
        ExperienceLevel.intermediate => 300,
        ExperienceLevel.advanced => 420,
      };
    }
    return math.max(120, (minutes / 30).round() * 30);
  }

  /// Schwerpunkt eines Zeitraum-Plans aus den Zielen: Gesundheit, Regeneration und allgemeine Fitness bauen
  /// Grundlage auf, sonst Formsteigerung.
  static PeriodFocus focus(UserProfile profile, {required CalendarDay today}) {
    final primary = profile.effectiveGoals(today).primary;
    return switch (primary) {
      TrainingGoal.health ||
      TrainingGoal.recovery ||
      TrainingGoal.generalFitness ||
      TrainingGoal.fatLoss => PeriodFocus.base,
      _ => PeriodFocus.fitness,
    };
  }

  /// Begründung der Vorgaben für die Ansicht.
  static String explanation(UserProfile profile, {required CalendarDay today, KnownGoal? goal}) {
    final goals = profile.effectiveGoals(today);
    final parts = [
      if (goal != null) 'Ziel: ${goal.name} am ${_date(goal.day)} (${goal.source})',
      'Hauptziel: ${goals.primary.label}',
      if (profile.schedule.trainingDays.isNotEmpty) 'Tage und Zeit aus deinem Wochenplan',
    ];
    return '${parts.join(' · ')}.';
  }

  static String _date(CalendarDay day) =>
      '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';

  /// Vorschlag für einen neuen Plan: mit bekanntem Wettkampf auf diesen hin, sonst für einen Zeitraum von 8 Wochen.
  static TrainingPlanRequest suggestion(
    UserProfile profile,
    SeasonConfig season, {
    required String username,
    required CalendarDay today,
    AthleteThresholds thresholds = const AthleteThresholds(),
    KnownGoal? goal,
  }) {
    final chosen = goal ?? known(profile, season, today: today).where((goal) => goal.event != null).firstOrNull;
    final days = EnduranceGoals.days(profile);
    final sports = EnduranceGoals.sports(profile);
    return TrainingPlanRequest(
      username: username,
      mode: chosen?.event == null ? PlanningMode.period : PlanningMode.goal,
      sports: sports.isEmpty ? const [EnduranceSport.run] : sports,
      start: today,
      weeklyMinutes: weeklyMinutes(profile),
      days: days,
      longDay: longDay(profile, days),
      focus: focus(profile, today: today),
      event: chosen?.event,
      eventDay: chosen?.event == null ? null : chosen!.day,
      eventName: chosen?.event == null ? null : chosen!.name,
      targetMinutes: chosen?.event == null ? null : chosen!.targetMinutes,
      thresholds: thresholds,
    );
  }

  /// Passt der Plan nicht mehr zum Ziel in der App (anderer Wettkampf oder anderes Datum)? Dann der neue Wettkampf.
  static KnownGoal? changedGoal(EndurancePlan plan, List<KnownGoal> known) {
    final next = known.where((goal) => goal.event != null).firstOrNull;
    if (next == null) return null;
    final request = plan.request;
    if (request.mode == PlanningMode.goal && request.eventDay == next.day && request.event == next.event) return null;
    if (request.mode == PlanningMode.goal && known.any((goal) => goal.day == request.eventDay)) return null;
    return next;
  }
}

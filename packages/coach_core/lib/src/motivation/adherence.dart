import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../profile/plan_adjustments.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';

enum AdherenceDay implements RawEnum {
  /// Geplant und trainiert.
  done,

  /// Geplant, Tag vorbei, nicht trainiert.
  missed,

  /// Geplant, heute oder später.
  open,

  /// Frei (oder diese Woche ausgelassen).
  rest,

  /// Frei, aber trainiert.
  extra;

  @override
  String get rawValue => name;
}

/// Wie gut eine Woche zum eigenen Plan passt. Gezählt werden geplante Trainingstage, an denen trainiert wurde;
/// zusätzliches Training bringt nichts extra (kein Anreiz zum Übertraining), ausgelassene Tage zählen nicht als
/// geplant (ehrliches Auslassen statt Durchziehen trotz schlechter Erholung).
final class WeekAdherence {
  const WeekAdherence({required this.monday, required this.days});

  final CalendarDay monday;
  final List<AdherenceDay> days;

  int get planned =>
      days.where((day) => day == AdherenceDay.done || day == AdherenceDay.missed || day == AdherenceDay.open).length;
  int get done => days.where((day) => day == AdherenceDay.done).length;
  int get missed => days.where((day) => day == AdherenceDay.missed).length;

  /// Alles Geplante erledigt (nur sinnvoll, wenn etwas geplant war).
  bool get isComplete => planned > 0 && done == planned;

  /// Anteil erledigt an allem, was bis heute fällig war oder schon erledigt ist.
  double get shareSoFar {
    final due = done + missed;
    return due == 0 ? 1 : done / due;
  }

  static WeekAdherence compute({
    required WeekSchedule schedule,
    required Set<CalendarDay> trainingDays,
    required CalendarDay weekOf,
    required CalendarDay today,
  }) {
    final monday = PlanAdjustments.monday(weekOf);
    return WeekAdherence(
      monday: monday,
      days: [
        for (final weekday in Weekday.values)
          () {
            final date = monday.adding(weekday.rawValue);
            final planned = schedule.slots(weekday).isNotEmpty;
            final trained = trainingDays.contains(date);
            return switch ((planned, trained)) {
              (true, true) => AdherenceDay.done,
              (true, false) => date < today ? AdherenceDay.missed : AdherenceDay.open,
              (false, true) => AdherenceDay.extra,
              (false, false) => AdherenceDay.rest,
            };
          }(),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WeekAdherence && other.monday == monday && const ListEquality<AdherenceDay>().equals(other.days, days);

  @override
  int get hashCode => Object.hash(monday, Object.hashAll(days));
}

/// Punkte für die Rangliste. Belohnt wird das Erreichen der eigenen Ziele (Punkte und Stufen für erreichte Ziele
/// wie in Patel et al. 2017 und 2019), nicht die Menge: Wer wenig plant, kann genauso gewinnen wie wer viel plant.
abstract final class ScoreRules {
  static const pointsPerSession = 10;
  static const completeWeekBonus = 20;

  /// Ab diesem Anteil zählt eine Woche für die Serie.
  static const streakShare = 0.8;

  /// Zählt die Aktivität als Training? Spaziergänge und Ähnliches nur, wenn an dem Tag so etwas geplant war.
  static bool countsAsTraining(GarminActivity activity, {required bool otherIsPlanned}) =>
      (activity.durationSeconds ?? 0) >= 900 && (activity.sport != ActivitySport.other || otherIsPlanned);

  static int points(WeekAdherence week) => week.done * pointsPerSession + (week.isComplete ? completeWeekBonus : 0);

  /// Woche zählt für die Serie: mindestens 80 % des Geplanten erledigt. Laufende Wochen zählen erst, wenn sie
  /// vorbei sind.
  static bool countsForStreak(WeekAdherence week) => week.planned > 0 && week.done / week.planned >= streakShare;

  /// Serie abgeschlossener Wochen vor der aktuellen (neueste zuerst übergeben).
  static int streak(List<WeekAdherence> finishedWeeksNewestFirst) {
    var count = 0;
    for (final week in finishedWeeksNewestFirst) {
      if (week.planned == 0) continue; // Woche ohne Plan (Urlaub) unterbricht die Serie nicht
      if (!countsForStreak(week)) break;
      count += 1;
    }
    return count;
  }

  /// Stufe aus allen gesammelten Punkten: alle 100 Punkte eine Stufe.
  static int level(int totalPoints) => math.max(totalPoints, 0) ~/ 100 + 1;
}

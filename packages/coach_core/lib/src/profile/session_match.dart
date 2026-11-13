import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../analysis/session_kind.dart';
import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';
import 'plan_adjustments.dart';
import 'training_break.dart';
import 'user_profile.dart';
import 'week_schedule.dart';

/// Soll gegen Ist je Einheit. „Erledigt“ heißt: gleiche Sportart am selben Tag, mindestens 60 % der geplanten Dauer –
/// nicht nur „an dem Tag war irgendetwas“ (ein Spaziergang hakt keinen Intervalllauf ab).
enum SessionStatus implements RawEnum {
  /// Geplante Einheit wie vorgesehen gemacht.
  done('erledigt'),

  /// Gleiche Sportart, aber deutlich kürzer.
  partial('teilweise'),

  /// Andere Ausdauer-Sportart statt der geplanten (z. B. Rad statt Lauf).
  substituted('anders gemacht'),

  /// Tag vorbei, nichts Passendes.
  missed('verpasst'),

  /// Heute, noch offen.
  open('heute'),

  /// Später in der Woche.
  planned('geplant');

  const SessionStatus(this.label);

  final String label;

  @override
  String get rawValue => name;

  /// Zählt für Erinnerungen und Tagesempfehlung als „gemacht“.
  bool get counts => this == done || this == partial || this == substituted;
}

/// Eine geplante Einheit an einem Tag (Wochenplan mit Ausnahmen).
final class PlannedSession {
  PlannedSession({required this.day, required this.slot, this.index = 0, int? targetMinutes})
    : targetMinutes = targetMinutes ?? SessionMatcher.defaultMinutes(slot);

  final CalendarDay day;
  final SessionSlot slot;

  /// Index unter den Einheiten des Tages (zwei Läufe an einem Tag).
  final int index;
  final int targetMinutes;

  String get id => '${day.iso}-$index-${slot.id}';

  @override
  bool operator ==(Object other) =>
      other is PlannedSession &&
      other.day == day &&
      other.slot == slot &&
      other.index == index &&
      other.targetMinutes == targetMinutes;

  @override
  int get hashCode => Object.hash(day, slot, index, targetMinutes);

  @override
  String toString() => 'PlannedSession($id)';
}

final class SessionResult {
  const SessionResult({
    required this.planned,
    required this.status,
    this.activityID,
    this.actualMinutes,
    this.intensityNote,
  });

  final PlannedSession planned;
  final SessionStatus status;
  final int? activityID;
  final int? actualMinutes;

  /// Geplant intensiv, aber locker gemacht (oder umgekehrt).
  final String? intensityNote;

  String get id => planned.id;

  /// „Soll 45 min · Ist 41 min“.
  String get compareText => actualMinutes == null
      ? 'Soll ${planned.targetMinutes} min'
      : 'Soll ${planned.targetMinutes} min · Ist $actualMinutes min';

  @override
  String toString() => 'SessionResult(${planned.id}, ${status.name}, $activityID)';
}

/// Ergebnis einer Woche.
final class SessionWeek {
  const SessionWeek({required this.results, required this.extraIDs});

  final List<SessionResult> results;

  /// Außerplanmäßige Aktivitäten (keiner Einheit zugeordnet), ab 10 Minuten.
  final List<int> extraIDs;

  List<SessionResult> resultsOn(CalendarDay day) => results.where((result) => result.planned.day == day).toList();

  /// Alle geplanten Einheiten des Tages gemacht (für Erinnerungen und „Geschafft“).
  bool allCounted(CalendarDay day) {
    final today = resultsOn(day);
    return today.isNotEmpty && today.every((result) => result.status.counts);
  }
}

/// Zuordnung von Aktivitäten zu geplanten Einheiten (Port von `SessionMatcher`).
abstract final class SessionMatcher {
  /// Ab diesem Anteil der geplanten Dauer gilt die Einheit als erledigt, darunter als „teilweise“.
  static const doneShare = 0.6;

  /// Kürzere Aktivitäten (Weg zur Arbeit, Einrollen) zählen für keine Einheit.
  static const minimumSeconds = 900.0;

  /// Dauer, wenn der Plan keine nennt (der Laufplan liefert eigene Minuten).
  static int defaultMinutes(SessionSlot slot) => switch ((slot.sport, slot.intensity)) {
    (TrainingSport.strength, _) => 45,
    (TrainingSport.other, _) => 30,
    (_, SessionIntensity.easy) => 45,
    (_, SessionIntensity.hard) => 50,
    (_, SessionIntensity.long) => 90,
  };

  static TrainingSport sport(ActivitySport sport) => switch (sport) {
    ActivitySport.run => TrainingSport.run,
    ActivitySport.bike => TrainingSport.bike,
    ActivitySport.swim => TrainingSport.swim,
    ActivitySport.strength => TrainingSport.strength,
    ActivitySport.other => TrainingSport.other,
  };

  /// Geplante Einheiten der Woche ab [monday]; Laufminuten aus dem Laufplan, falls vorhanden.
  static List<PlannedSession> planned(
    WeekSchedule schedule, {
    required CalendarDay monday,
    Map<Weekday, List<int>> runMinutes = const {},
  }) => [
    for (final weekday in Weekday.values)
      ...() {
        final day = monday.adding(weekday.index);
        var runIndex = 0;
        final slots = schedule.slots(weekday);
        return [
          for (var index = 0; index < slots.length; index++)
            () {
              final slot = slots[index];
              int? minutes;
              final list = runMinutes[weekday];
              if (slot.sport == TrainingSport.run && list != null && runIndex < list.length) {
                minutes = list[runIndex];
                runIndex += 1;
              }
              return PlannedSession(day: day, slot: slot, index: index, targetMinutes: minutes);
            }(),
        ];
      }(),
  ];

  /// Zuordnung je Tag: zuerst gleiche Sportart (längste Aktivität zuerst), dann andere Ausdauer als Ersatz.
  /// Krafteinheiten aus der App ([gymDays]) zählen als Kraft, auch ohne Garmin-Aufzeichnung.
  static SessionWeek match({
    required List<PlannedSession> planned,
    required List<GarminActivity> activities,
    Set<CalendarDay> gymDays = const {},
    required CalendarDay today,
  }) {
    // Nur die Wochen des Plans, sonst stünde jede alte Aktivität unter „Außerplanmäßig“.
    final weeks = planned.isEmpty
        ? {PlanAdjustments.monday(today)}
        : planned.map((session) => PlanAdjustments.monday(session.day)).toSet();
    final weekActivities = activities.where((activity) {
      final day = activity.day;
      return day != null && weeks.contains(PlanAdjustments.monday(day));
    }).toList();
    final weekGymDays = gymDays.where((day) => weeks.contains(PlanAdjustments.monday(day))).toSet();
    final results = <SessionResult>[];
    final used = <int>{};
    // Krafttraining an einem Tag ohne offene Kraft-Einheit (z. B. Push am Dienstag statt am Montag).
    final spareStrength = <CalendarDay>[];
    final days = {
      ...planned.map((session) => session.day),
      ...weekActivities.map((activity) => activity.day).nonNulls,
      ...weekGymDays,
    }.toList()..sort();
    for (final day in days) {
      final sessions = planned.where((session) => session.day == day).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      final candidates = weekActivities
          .where((activity) => activity.day == day && (activity.durationSeconds ?? 0) >= minimumSeconds)
          .toList();
      mergeSort(candidates, compare: (a, b) => (b.durationSeconds ?? 0).compareTo(a.durationSeconds ?? 0));
      var gymAvailable = weekGymDays.contains(day);
      final open = <PlannedSession>[];
      for (final session in sessions) {
        final activity = candidates.firstWhereOrNull(
          (activity) => !used.contains(activity.id) && sport(activity.sport) == session.slot.sport,
        );
        if (activity != null) {
          used.add(activity.id);
          results.add(result(session, activity, substituted: false));
          // App-Einheit und Uhr-Aufzeichnung desselben Tages sind ein und dasselbe Training.
          if (session.slot.sport == TrainingSport.strength) gymAvailable = false;
        } else if (session.slot.sport == TrainingSport.strength && gymAvailable) {
          gymAvailable = false;
          results.add(SessionResult(planned: session, status: SessionStatus.done));
        } else {
          open.add(session);
        }
      }
      if (gymAvailable) spareStrength.add(day);
      for (final session in open) {
        // Ersatz: andere Ausdauer-Sportart (Rad statt Lauf), nicht Kraft oder Spaziergang.
        final substitute = session.slot.sport.isEndurance
            ? candidates.firstWhereOrNull(
                (activity) => !used.contains(activity.id) && sport(activity.sport).isEndurance,
              )
            : null;
        if (substitute != null) {
          used.add(substitute.id);
          results.add(result(session, substitute, substituted: true));
        } else {
          final status = day < today
              ? SessionStatus.missed
              : day == today
              ? SessionStatus.open
              : SessionStatus.planned;
          results.add(SessionResult(planned: session, status: status));
        }
      }
    }
    // Kraft an einem anderen Tag zählt für die offene Kraft-Einheit derselben Woche: zuerst eine verpasste oder heute
    // offene davor, sonst die nächste geplante. Uhr-Aufzeichnungen von Krafttraining ohne App-Einheit am selben Tag
    // (sonst wäre es doppelt).
    final spareActivities = <(CalendarDay, int?)>[
      for (final activity in weekActivities)
        if (activity.day case final day?
            when !used.contains(activity.id) &&
                activity.sport == ActivitySport.strength &&
                (activity.durationSeconds ?? 0) >= minimumSeconds &&
                !weekGymDays.contains(day))
          (day, activity.id),
    ];
    final spare = [for (final day in spareStrength) (day, null as int?), ...spareActivities];
    mergeSort(spare, compare: (a, b) => a.$1.compareTo(b.$1));
    for (final (day, activityID) in spare) {
      final monday = day.adding(-day.weekdayIndex);
      final candidates = [
        for (var index = 0; index < results.length; index++)
          if (results[index].planned.slot.sport == TrainingSport.strength &&
              !results[index].status.counts &&
              results[index].planned.day >= monday &&
              results[index].planned.day <= monday.adding(6))
            index,
      ];
      final before = candidates.where((index) => results[index].planned.day <= day);
      final index = before.firstOrNull ?? candidates.firstOrNull;
      if (index == null) continue;
      if (activityID != null) used.add(activityID);
      results[index] = SessionResult(
        planned: results[index].planned,
        status: SessionStatus.done,
        activityID: activityID,
      );
    }
    final extras = weekActivities
        .where((activity) => !used.contains(activity.id) && (activity.durationSeconds ?? 0) >= 600)
        .map((activity) => activity.id)
        .toList();
    mergeSort(
      results,
      compare: (a, b) {
        final byDay = a.planned.day.compareTo(b.planned.day);
        return byDay != 0 ? byDay : a.planned.index.compareTo(b.planned.index);
      },
    );
    return SessionWeek(results: results, extraIDs: extras);
  }

  static SessionResult result(PlannedSession session, GarminActivity activity, {required bool substituted}) {
    final minutes = ((activity.durationSeconds ?? 0) / 60).round();
    final short = minutes < session.targetMinutes * doneShare;
    final status = substituted
        ? SessionStatus.substituted
        : short
        ? SessionStatus.partial
        : SessionStatus.done;
    String? note;
    final hard = SessionKind.isHard(activity);
    if (session.slot.intensity == SessionIntensity.hard && !hard && activity.sport != ActivitySport.strength) {
      note = 'locker statt intensiv';
    } else if (session.slot.intensity == SessionIntensity.easy && hard && activity.sport != ActivitySport.strength) {
      note = 'intensiver als geplant';
    }
    return SessionResult(
      planned: session,
      status: status,
      activityID: activity.id,
      actualMinutes: minutes,
      intensityNote: note,
    );
  }

  /// Minuten je Sportart: Soll aus dem Plan, Ist aus allen Aktivitäten der Woche bis heute.
  static List<({TrainingSport sport, int planned, int actual})> totals({
    required List<PlannedSession> planned,
    required List<GarminActivity> activities,
    required CalendarDay monday,
  }) {
    final end = monday.adding(6);
    final week = activities.where((activity) {
      final day = activity.day;
      return day != null && monday <= day && day <= end;
    });
    return [
      for (final trainingSport in TrainingSport.values)
        if ((
              planned: planned
                  .where((session) => session.slot.sport == trainingSport)
                  .fold(0, (sum, session) => sum + session.targetMinutes),
              actual:
                  (week
                              .where((activity) => sport(activity.sport) == trainingSport)
                              .fold<double>(0, (sum, activity) => sum + (activity.durationSeconds ?? 0)) /
                          60)
                      .round(),
            )
            case (planned: final plannedMinutes, actual: final actual) when plannedMinutes != 0 || actual != 0)
          (sport: trainingSport, planned: plannedMinutes, actual: actual),
    ];
  }
}

/// Verpasste Einheiten: am nächsten Morgen entscheiden (nachholen, streichen, krank).
abstract final class MissedSessions {
  /// Höchstens eine Einheit pro Woche nachholen – sonst staut sich die Belastung.
  static const maxMakeUpsPerWeek = 1;

  /// Nach „krank“ so viele Tage nur locker.
  static const illnessEasyDays = 2;

  /// Verpasste, noch nicht entschiedene Einheiten der Woche bis gestern (neueste zuerst). Tage einer Pause
  /// ([TrainingBreak]) zählen nicht als verpasst.
  static List<SessionResult> open(SessionWeek week, {required Set<String> handled, TrainingBreak? pause}) {
    final result = week.results
        .where(
          (result) =>
              result.status == SessionStatus.missed &&
              !handled.contains(result.id) &&
              !(pause?.contains(result.planned.day) ?? false),
        )
        .toList();
    mergeSort(result, compare: (a, b) => b.planned.day.compareTo(a.planned.day));
    return result;
  }

  /// Nachholtag in dieser Woche nach heute: kein fordernder Ausdauertag direkt daneben, möglichst frei.
  static Weekday? makeUpDay(
    PlannedSession session, {
    required WeekSchedule schedule,
    required UserProfile profile,
    required CalendarDay today,
    required int makeUpsThisWeek,
  }) {
    final sameWeek = PlanAdjustments.monday(session.day) == PlanAdjustments.monday(today);
    if (makeUpsThisWeek >= maxMakeUpsPerWeek || !sameWeek) return null;
    final candidates = Weekday.values.where((weekday) => weekday.index > today.weekdayIndex).toList();
    WeekSchedule moved(Weekday target) => schedule.withSlots([...schedule.slots(target), session.slot], target);
    return candidates.firstWhereOrNull(
          (target) => schedule.slots(target).isEmpty && !PlanMoveAdvisor.createsBackToBack(moved(target), target),
        ) ??
        candidates.firstWhereOrNull((target) => !PlanMoveAdvisor.createsBackToBack(moved(target), target));
  }

  /// Nach Krankheit: Erholung höchstens „locker“ für die nächsten Tage.
  static RecoveryLevel? cappedRecovery(RecoveryLevel? level, {CalendarDay? sickDay, required CalendarDay today}) {
    if (sickDay == null || sickDay > today || sickDay.daysUntil(today) > illnessEasyDays) return level;
    if (level == RecoveryLevel.pause) return RecoveryLevel.pause;
    return RecoveryLevel.locker;
  }
}

/// Training ohne Uhr nachtragen (Schwimmen im Urlaub, Fußball): Belastung aus Dauer × Anstrengung (sRPE, Foster et al.
/// 2001), auf die Größenordnung der Garmin-Belastung skaliert.
abstract final class ManualActivity {
  /// Eigener ID-Bereich unterhalb der Apple-Health-IDs.
  static const idOffset = 1 << 62;

  static bool isManual(int id) => id < -idOffset;

  static GarminActivity make({
    required TrainingSport sport,
    required DateTime start,
    required int minutes,
    required int effort,
    String? name,
    math.Random? random,
  }) {
    // Zwei Einträge zur selben Startzeit dürfen sich nicht überschreiben.
    final unique = sport.index * 256 + (random ?? math.Random()).nextInt(256);
    final id = -idOffset - (start.millisecondsSinceEpoch ~/ 60000) * 2048 - unique - 1;
    final local = start.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return GarminActivity(id)
      ..typeKey = typeKey(sport)
      ..name = name == null || name.isEmpty ? '${sport.label} (nachgetragen)' : name
      ..startLocal =
          '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} '
          '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      ..durationSeconds = (math.max(minutes, 1) * 60).toDouble()
      ..trainingLoad = estimatedLoad(minutes: minutes, effort: effort);
  }

  /// sRPE = Minuten × Anstrengung (1–10); geteilt durch 4 liegt es grob in der Spanne der Garmin-Belastung.
  static double estimatedLoad({required int minutes, required int effort}) =>
      math.max(minutes, 0) * effort.clamp(1, 10) / 4;

  static String typeKey(TrainingSport sport) => switch (sport) {
    TrainingSport.run => 'running',
    TrainingSport.bike => 'cycling',
    TrainingSport.swim => 'lap_swimming',
    TrainingSport.strength => 'strength_training',
    TrainingSport.other => 'other',
  };
}

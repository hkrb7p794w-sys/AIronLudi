import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/season_plan.dart';
import '../garmin/garmin_activity.dart';
import '../plan/season_schedule.dart';
import '../plan/today_plan.dart';
import '../util/enum_codec.dart';
import 'schedule_check.dart';
import 'session_match.dart';
import 'user_profile.dart';
import 'week_schedule.dart';

/// Ausnahme vom Wochenplan für genau eine Woche: Einheiten eines Tages auslassen oder auf einen anderen Tag derselben
/// Woche verschieben. Der eigentliche Wochenplan bleibt unverändert.
final class PlanChange {
  const PlanChange({required this.week, required this.from, this.to});

  /// Montag der betroffenen Woche.
  final CalendarDay week;
  final Weekday from;

  /// Zieltag; `null` = ausgelassen.
  final Weekday? to;

  bool get isSkip => to == null;

  Map<String, Object?> toJson() => {'week': week.toJson(), 'from': from.index, 'to': ?to?.index};

  static PlanChange? fromJson(Object? json) {
    if (json is! Map || json['week'] is! Map) return null;
    final from = jsonInt(json['from']);
    final to = jsonInt(json['to']);
    if (from == null || from < 0 || from > 6 || (to != null && (to < 0 || to > 6))) return null;
    return PlanChange(
      week: CalendarDay.fromJson((json['week'] as Map).cast<String, Object?>()),
      from: Weekday.values[from],
      to: to == null ? null : Weekday.values[to],
    );
  }

  @override
  bool operator ==(Object other) => other is PlanChange && other.week == week && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(week, from, to);
}

/// Eigener Plan für genau eine Woche (aus „Nächste Woche planen“); ersetzt dort den Wochenplan.
final class WeekPlan {
  const WeekPlan({required this.week, required this.schedule});

  /// Montag der Woche.
  final CalendarDay week;
  final WeekSchedule schedule;

  Map<String, Object?> toJson() => {'week': week.toJson(), 'schedule': schedule.toJson()};

  static WeekPlan? fromJson(Object? json) {
    if (json is! Map || json['week'] is! Map) return null;
    return WeekPlan(
      week: CalendarDay.fromJson((json['week'] as Map).cast<String, Object?>()),
      schedule: WeekSchedule.fromJson(json['schedule']),
    );
  }

  @override
  bool operator ==(Object other) => other is WeekPlan && other.week == week && other.schedule == schedule;

  @override
  int get hashCode => Object.hash(week, schedule);
}

/// Alle Ausnahmen, gespeichert in der Reihenfolge, in der sie gemacht wurden (Schlüssel `coach.planAdjustments`).
final class PlanAdjustments {
  PlanAdjustments({List<PlanChange> changes = const [], List<WeekPlan> weekPlans = const []})
    : _changes = [...changes],
      _weekPlans = [...weekPlans];

  final List<PlanChange> _changes;
  final List<WeekPlan> _weekPlans;

  List<PlanChange> get changes => List.unmodifiable(_changes);
  List<WeekPlan> get weekPlans => List.unmodifiable(_weekPlans);

  static CalendarDay monday(CalendarDay day) => day.adding(-day.weekdayIndex);

  /// Eigener Plan der Woche, die [day] enthält, falls angelegt.
  WeekSchedule? weekPlan(CalendarDay day) {
    final week = monday(day);
    return _weekPlans.firstWhereOrNull((plan) => plan.week == week)?.schedule;
  }

  /// Plan für genau diese Woche festlegen. Entspricht er dem Wochenplan, wird nichts gespeichert. Ausnahmen
  /// (Auslassen/Verschieben) der Woche gehen in dem neuen Plan auf und werden entfernt.
  void setWeekPlan(WeekSchedule schedule, {required WeekSchedule base, required CalendarDay inWeekOf}) {
    final week = monday(inWeekOf);
    _weekPlans.removeWhere((plan) => plan.week == week);
    _changes.removeWhere((change) => change.week == week);
    if (schedule != base) _weekPlans.add(WeekPlan(week: week, schedule: schedule));
  }

  List<PlanChange> changesInWeekOf(CalendarDay day) {
    final week = monday(day);
    return _changes.where((change) => change.week == week).toList();
  }

  /// Der Plan der Woche, die [inWeekOf] enthält, mit allen Ausnahmen dieser Woche.
  WeekSchedule schedule(WeekSchedule base, {required CalendarDay inWeekOf}) {
    var result = weekPlan(inWeekOf) ?? base;
    for (final change in changesInWeekOf(inWeekOf)) {
      final moved = result.slots(change.from);
      if (moved.isEmpty) continue;
      result = result.withSlots(const [], change.from);
      final target = change.to;
      if (target != null) result = result.withSlots([...result.slots(target), ...moved], target);
    }
    return result;
  }

  /// Einheiten dieses Tages in dieser Woche auslassen.
  void skip(Weekday weekday, {required CalendarDay inWeekOf}) =>
      _changes.add(PlanChange(week: monday(inWeekOf), from: weekday));

  /// Einheiten dieses Tages in dieser Woche auf einen anderen Tag verschieben.
  void move(Weekday weekday, {required Weekday to, required CalendarDay inWeekOf}) {
    if (weekday == to) return;
    _changes.add(PlanChange(week: monday(inWeekOf), from: weekday, to: to));
  }

  /// Ausnahmen der Woche zurücknehmen, die diesen Tag betreffen (von dort weg oder dorthin verschoben).
  void undo(Weekday weekday, {required CalendarDay inWeekOf}) {
    final week = monday(inWeekOf);
    _changes.removeWhere((change) => change.week == week && (change.from == weekday || change.to == weekday));
  }

  /// Alle Ausnahmen der Woche zurücknehmen.
  void reset({required CalendarDay weekOf}) {
    final week = monday(weekOf);
    _changes.removeWhere((change) => change.week == week);
    _weekPlans.removeWhere((plan) => plan.week == week);
  }

  /// Ausnahmen vergangener Wochen entfernen (sie wirken nicht mehr).
  void prune({required CalendarDay before}) {
    final week = monday(before);
    _changes.removeWhere((change) => change.week < week);
    _weekPlans.removeWhere((plan) => plan.week < week);
  }

  /// Wurde an diesem Tag etwas ausgelassen oder weggeschoben?
  String? note(Weekday weekday, {required CalendarDay inWeekOf}) {
    final week = changesInWeekOf(inWeekOf);
    final moved = week.lastWhereOrNull((change) => change.from == weekday && change.to != null);
    if (moved != null) return 'verschoben auf ${moved.to!.long}';
    if (week.any((change) => change.from == weekday && change.isSkip)) return 'diese Woche ausgelassen';
    final incoming = week.lastWhereOrNull((change) => change.to == weekday);
    if (incoming != null) return 'von ${incoming.from.long} verschoben';
    return null;
  }

  PlanAdjustments copy() => PlanAdjustments(changes: _changes, weekPlans: _weekPlans);

  Map<String, Object?> toJson() => {
    'changes': [for (final change in _changes) change.toJson()],
    'weekPlans': [for (final plan in _weekPlans) plan.toJson()],
  };

  /// Wie Swift: ältere Daten ohne Wochenpläne bleiben lesbar; unlesbare Ausnahmen machen das Ganze unlesbar (`null`).
  static PlanAdjustments? fromJson(Object? json) {
    if (json is! Map) return null;
    final changes = json['changes'] == null ? const <PlanChange>[] : listStrict(json['changes'], PlanChange.fromJson);
    if (changes == null) return null;
    final weekPlans = listStrict(json['weekPlans'], WeekPlan.fromJson) ?? const <WeekPlan>[];
    return PlanAdjustments(changes: changes, weekPlans: weekPlans);
  }

  @override
  bool operator ==(Object other) =>
      other is PlanAdjustments &&
      const ListEquality<PlanChange>().equals(other._changes, _changes) &&
      const ListEquality<WeekPlan>().equals(other._weekPlans, _weekPlans);

  @override
  int get hashCode => Object.hash(Object.hashAll(_changes), Object.hashAll(_weekPlans));
}

/// Wohin sich eine Einheit sinnvoll verschieben lässt.
abstract final class PlanMoveAdvisor {
  /// Mögliche Zieltage in derselben Woche nach [today], die besten zuerst: keine zwei fordernden Ausdauertage direkt
  /// hintereinander (Seiler 2006), möglichst ein freier Tag.
  static List<Weekday> options(
    Weekday weekday, {
    required WeekSchedule schedule,
    required UserProfile profile,
    required CalendarDay today,
    int limit = 3,
  }) {
    final todayIndex = today.weekdayIndex;
    final moving = schedule.slots(weekday);
    if (moving.isEmpty) return const [];
    final candidates = Weekday.values.where((target) => target.index > todayIndex && target != weekday);
    final scored = [
      for (final target in candidates)
        () {
          final cleared = schedule.withSlots(const [], weekday);
          final moved = cleared.withSlots([...cleared.slots(target), ...moving], target);
          var score = ScheduleCheck.penalty(moved, profile);
          if (schedule.slots(target).isNotEmpty) score += 2;
          if (createsBackToBack(moved, target)) score += 20;
          return (target, score);
        }(),
    ]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.index.compareTo(b.$1.index));
    return scored.take(limit).map((entry) => entry.$1).toList();
  }

  static bool createsBackToBack(WeekSchedule schedule, Weekday day) {
    if (!schedule.slots(day).any((slot) => slot.isDemandingEndurance)) return false;
    return schedule.slots(day.previous).any((slot) => slot.isDemandingEndurance) ||
        schedule.slots(day.next).any((slot) => slot.isDemandingEndurance);
  }
}

/// Eine geplante Trainings-Erinnerung.
final class TrainingReminder {
  const TrainingReminder({required this.day, required this.titles, required this.canAdjust});

  final CalendarDay day;
  final List<String> titles;

  /// Mit Auslassen/Verschieben (nur beim eigenen Wochenplan).
  final bool canAdjust;

  String get id => 'coach.reminder.${day.iso}';

  String get title => 'Heute: ${titles.join(' + ')}';
}

/// Was schon trainiert wurde (Aktivitäten aus Garmin/Health, Krafteinheiten der App): Erinnerungen für Erledigtes
/// entfallen.
final class TrainingLog {
  const TrainingLog({this.activities = const [], this.gymDays = const {}});

  final List<GarminActivity> activities;
  final Set<CalendarDay> gymDays;

  /// Tage mit mindestens 15 Minuten Training oder einer Krafteinheit.
  Set<CalendarDay> get trainedDays => {
    ...activities.where((activity) => (activity.durationSeconds ?? 0) >= 900).map((activity) => activity.day).nonNulls,
    ...gymDays,
  };

  /// Saisonplan-Tag mit dem bis [today] Erledigten dieser Woche.
  TodayPlan seasonPlan({
    required SeasonSchedule schedule,
    required SeasonConfig config,
    required CompetitionDecisions decisions,
    required CalendarDay day,
    required CalendarDay today,
  }) {
    final progress = TodayPlan.doneThisWeek(activities: activities, gymDays: gymDays, weekOf: day, upTo: today);
    return TodayPlan(
      schedule: schedule,
      config: config,
      decisions: decisions,
      today: day,
      level: null,
      advice: '',
      done: progress.done,
      gymDays: progress.strengthDays,
      runZones: null,
    );
  }
}

/// Erinnerung zu einer festen Uhrzeit, die nicht am Trainingstag selbst kommt: Ausrüstung am Vorabend, Wochenplanung am
/// Sonntag.
enum ScheduledNoteKind implements RawEnum {
  equipment,
  weekPlanning,
  nutritionReview,
  meal,
  morningReport;

  @override
  String get rawValue => name;
}

final class ScheduledNote {
  const ScheduledNote({
    required this.kind,
    required this.day,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
    this.tag = '',
  });

  final ScheduledNoteKind kind;
  final CalendarDay day;
  final int hour;
  final int minute;
  final String title;
  final String body;

  /// Unterscheidet mehrere Mitteilungen derselben Art am selben Tag (z. B. Mahlzeit `fruehstueck`).
  final String tag;

  String get id => 'coach.reminder.${kind.rawValue}.${day.iso}${tag.isEmpty ? '' : '.$tag'}';
}

/// Erinnerungen an Einheiten.
abstract final class ReminderPlanner {
  static const equipmentHour = 18;

  /// Erinnerungen für den Saisonplan: die festen Einheiten der Tage laut `TodayPlan`, ohne Auslassen/Verschieben
  /// (der Saisonplan verteilt offene Einheiten selbst).
  static List<TrainingReminder> season({
    required SeasonSchedule schedule,
    required SeasonConfig config,
    required CompetitionDecisions decisions,
    required CalendarDay today,
    required bool includeToday,
    int days = 14,
    TrainingLog log = const TrainingLog(),
  }) => [
    for (var offset = 0; offset < days; offset++)
      if (offset != 0 || includeToday)
        if ([
              for (final item
                  in log
                      .seasonPlan(
                        schedule: schedule,
                        config: config,
                        decisions: decisions,
                        day: today.adding(offset),
                        today: today,
                      )
                      .items)
                if (item.sport != TodayPlanSport.rest && !item.done) item.title,
            ]
            case final titles when titles.isNotEmpty)
          TrainingReminder(day: today.adding(offset), titles: titles, canAdjust: false),
  ];

  /// Schwimmen mit Ausrüstung (Pull-Buoy, Paddles, Flossen, Schnorchel): Erinnerung am Vorabend um 18 Uhr.
  /// Nur der Saisonplan kennt die Ausrüstung je Einheit; im eigenen Wochenplan gibt es keine Angabe dazu.
  static List<ScheduledNote> swimEquipment({
    required SeasonSchedule schedule,
    required SeasonConfig config,
    required CompetitionDecisions decisions,
    required CalendarDay today,
    required int minutesNow,
    int days = 14,
    TrainingLog log = const TrainingLog(),
  }) {
    final result = <ScheduledNote>[];
    for (var offset = 1; offset <= (days < 1 ? 1 : days); offset++) {
      final training = today.adding(offset);
      final evening = training.adding(-1);
      if (evening == today && minutesNow >= equipmentHour * 60) continue;
      // Schon geschwommen (z. B. am Dienstag): Am Donnerstag stehen dann die Beine an, keine Erinnerung.
      final plan = log.seasonPlan(
        schedule: schedule,
        config: config,
        decisions: decisions,
        day: training,
        today: today,
      );
      final week = schedule.week(training);
      if (!plan.items.any((item) => item.sport == TodayPlanSport.swim && !item.done) || week == null) continue;
      final equipment = SwimStepText.equipment(week.ss ?? const []);
      if (equipment.isEmpty) continue;
      final list = ListFormat.german(equipment);
      result.add(
        ScheduledNote(
          kind: ScheduledNoteKind.equipment,
          day: evening,
          hour: equipmentHour,
          minute: 0,
          title: 'Morgen Schwimmen: $list einpacken',
          body: 'Für die Schwimmeinheit morgen brauchst du $list. Am besten gleich in die Tasche legen.',
        ),
      );
    }
    return result;
  }

  /// Erinnerungen für die kommenden [days] Tage ab [today] (iOS erlaubt höchstens 64 geplante Mitteilungen). Heute nur,
  /// wenn die Uhrzeit noch nicht vorbei ist und noch nicht trainiert wurde.
  static List<TrainingReminder> personal({
    required UserProfile profile,
    required PlanAdjustments adjustments,
    required CalendarDay today,
    required bool includeToday,
    int days = 14,
    TrainingLog log = const TrainingLog(),
  }) {
    // Nur wenn die geplanten Einheiten wirklich gemacht sind (gleiche Sportart, genug Dauer), entfällt die Erinnerung.
    final planned = SessionMatcher.planned(
      adjustments.schedule(profile.schedule, inWeekOf: today),
      monday: PlanAdjustments.monday(today),
    ).where((session) => session.day == today).toList();
    final trainedToday = SessionMatcher.match(
      planned: planned,
      activities: log.activities,
      gymDays: log.gymDays,
      today: today,
    ).allCounted(today);
    return [
      for (var offset = 0; offset < days; offset++)
        if (!(offset == 0 && (!includeToday || trainedToday)))
          if (adjustments
                  .schedule(profile.schedule, inWeekOf: today.adding(offset))
                  .slots(Weekday.of(today.adding(offset)))
              case final slots when slots.isNotEmpty)
            TrainingReminder(
              day: today.adding(offset),
              titles: [for (final slot in slots) slot.title],
              canAdjust: true,
            ),
    ];
  }

  /// Text der Mitteilung. Kurz, freundlich, ohne Druck; [lead] ist ein Satz des Begleiters.
  static String body(TrainingReminder reminder, {String? lead}) {
    final base = reminder.canAdjust
        ? 'Passt es heute nicht? Du kannst die Einheit verschieben oder diese Woche auslassen.'
        : 'Schau in der App, was heute ansteht.';
    if (lead == null || lead.isEmpty) return base;
    return '$lead $base';
  }

  /// Sonntags „Nächste Woche planen“ (heute nur, wenn die Uhrzeit noch nicht vorbei ist).
  static List<ScheduledNote> weekPlanning({
    required ProfileMode mode,
    required CalendarDay today,
    required int minutesNow,
    required int hour,
    required int minute,
    int days = 14,
  }) => [
    for (var offset = 0; offset < days; offset++)
      if (today.adding(offset).weekdayIndex == 6 && !(offset == 0 && minutesNow >= hour * 60 + minute))
        ScheduledNote(
          kind: ScheduledNoteKind.weekPlanning,
          day: today.adding(offset),
          hour: hour,
          minute: minute,
          title: 'Nächste Woche planen',
          body: mode == ProfileMode.personal
              ? 'Leg fest, an welchen Tagen du nächste Woche trainierst – Termine, Wetter, Erholung.'
              : 'Schau dir die Einheiten der nächsten Woche an und plane, wann du sie unterbringst.',
        ),
  ];
}

abstract final class ListFormat {
  /// „A“, „A und B“, „A, B und C“.
  static String german(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.single;
    return '${items.sublist(0, items.length - 1).join(', ')} und ${items.last}';
  }
}

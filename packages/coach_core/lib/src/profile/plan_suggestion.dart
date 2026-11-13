import '../calendar/calendar_day.dart';
import 'plan_adjustments.dart';
import 'post_workout.dart';
import 'schedule_advisor.dart';
import 'schedule_check.dart';
import 'user_profile.dart';
import 'week_load.dart';
import 'week_schedule.dart';

/// Woher ein Planvorschlag kommt.
enum PlanSuggestionSource {
  recovery,
  load,
  postWorkout,
  nextWeek;

  String get label => switch (this) {
    recovery => 'Tagesform',
    load => 'Wochenbelastung',
    postWorkout => 'Nach dem Training',
    nextWeek => 'Wochenrückblick',
  };
}

/// Eine Änderung an einem Tag.
final class PlanSuggestionChange {
  const PlanSuggestionChange({required this.weekday, required this.before, required this.after});

  final Weekday weekday;
  final List<SessionSlot> before;
  final List<SessionSlot> after;

  int get id => weekday.rawValue;

  /// „Do: Langer Lauf → Lockerer Lauf“
  String get text => '${weekday.short}: ${PlanSuggestion.text(before)} → ${PlanSuggestion.text(after)}';

  @override
  String toString() => 'PlanSuggestionChange($text)';
}

bool _sameSlots(List<SessionSlot> a, List<SessionSlot> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Ein Vorschlag zur Woche als Diff („Do: Qualitätslauf → Lockerer Lauf“) mit Regelprüfung. Übernehmen ersetzt die
/// Wochen-Ausnahmen (`adjustments`), Rückgängig stellt die vorherigen wieder her. Neue Konflikte mit den Planregeln
/// (zwei harte Tage hintereinander, kein Ruhetag …) stehen beim Vorschlag, statt still übernommen zu werden.
final class PlanSuggestion {
  const PlanSuggestion({
    required this.id,
    required this.source,
    required this.title,
    required this.reason,
    required this.week,
    required this.adjustments,
    required this.schedule,
    required this.changes,
    required this.unchanged,
    required this.conflicts,
    required this.evidenceIDs,
  });

  final String id;
  final PlanSuggestionSource source;
  final String title;
  final String reason;

  /// Montag der betroffenen Woche.
  final CalendarDay week;

  /// Wochen-Ausnahmen nach dem Übernehmen.
  final PlanAdjustments adjustments;

  /// Wochenplan nach dem Übernehmen (für „Anpassen“).
  final WeekSchedule schedule;
  final List<PlanSuggestionChange> changes;

  /// Fordernde Tage, die bleiben („Sa: Langer Lauf bleibt“).
  final List<String> unchanged;

  /// Planregeln, die erst durch den Vorschlag verletzt werden.
  final List<ScheduleHint> conflicts;
  final List<String> evidenceIDs;

  /// Vorschlag aus einer Änderung der Wochen-Ausnahmen; `null`, wenn sich am Plan nichts ändert. [edit] ändert eine
  /// Kopie der Ausnahmen.
  static PlanSuggestion? make({
    required String id,
    required PlanSuggestionSource source,
    required String title,
    required String reason,
    required UserProfile profile,
    required PlanAdjustments adjustments,
    required CalendarDay week,
    List<String> evidenceIDs = const [],
    required void Function(PlanAdjustments proposed) edit,
  }) {
    final proposed = adjustments.copy();
    edit(proposed);
    final before = adjustments.schedule(profile.schedule, inWeekOf: week);
    final after = proposed.schedule(profile.schedule, inWeekOf: week);
    final changes = diff(before, after);
    if (changes.isEmpty) return null;
    final changed = changes.map((change) => change.weekday).toSet();
    final unchanged = [
      for (final weekday in Weekday.values)
        if (!changed.contains(weekday))
          if (after.slots(weekday).where((slot) => slot.isDemandingEndurance).toList() case final slots
              when slots.isNotEmpty)
            '${weekday.short}: ${text(slots)} bleibt',
    ];
    return PlanSuggestion(
      id: id,
      source: source,
      title: title,
      reason: reason,
      week: PlanAdjustments.monday(week),
      adjustments: proposed,
      schedule: after,
      changes: changes,
      unchanged: unchanged,
      conflicts: newConflicts(before: before, after: after, profile: profile),
      evidenceIDs: evidenceIDs,
    );
  }

  static List<PlanSuggestionChange> diff(WeekSchedule before, WeekSchedule after) => [
    for (final weekday in Weekday.values)
      if (!_sameSlots(before.slots(weekday), after.slots(weekday)))
        PlanSuggestionChange(weekday: weekday, before: before.slots(weekday), after: after.slots(weekday)),
  ];

  /// Hinweise (ab „Tipp“), die der Plan vorher nicht hatte.
  static List<ScheduleHint> newConflicts({
    required WeekSchedule before,
    required WeekSchedule after,
    required UserProfile profile,
  }) {
    final existing = ScheduleCheck.hints(before, profile).map((hint) => hint.id).toSet();
    return [
      for (final hint in ScheduleCheck.hints(after, profile))
        if (hint.severity.index >= HintSeverity.tip.index && !existing.contains(hint.id)) hint,
    ];
  }

  static String text(List<SessionSlot> slots) => slots.isEmpty ? 'frei' : slots.map((slot) => slot.title).join(' + ');

  /// Fordernde Ausdauer an einem Tag durch lockere ersetzen.
  static WeekSchedule easing(WeekSchedule schedule, Weekday weekday) => schedule.withSlots([
    for (final slot in schedule.slots(weekday)) slot.isDemandingEndurance ? SessionSlot(slot.sport) : slot,
  ], weekday);

  // Quellen

  /// Tagesampel: heutige Einheit auf den vorgeschlagenen Tag verschieben.
  static PlanSuggestion? recovery({
    required ScheduleAdvice advice,
    required UserProfile profile,
    required PlanAdjustments adjustments,
    required CalendarDay today,
  }) {
    final move = advice.move;
    if (move == null) return null;
    final weekday = Weekday.of(today);
    return make(
      id: 'recovery-${today.iso}-${move.rawValue}',
      source: PlanSuggestionSource.recovery,
      title: 'Heutige Einheit auf ${move.long} verschieben',
      reason: advice.detail,
      profile: profile,
      adjustments: adjustments,
      week: today,
      evidenceIDs: advice.evidenceIDs,
      edit: (proposed) => proposed.move(weekday, to: move, inWeekOf: today),
    );
  }

  /// Wochenbelastung zu hoch: die nächste fordernde Ausdauereinheit dieser Woche (ab morgen) locker.
  static PlanSuggestion? load(
    WeekLoadResult load, {
    required UserProfile profile,
    required PlanAdjustments adjustments,
    required CalendarDay today,
  }) {
    final warning = load.warning;
    if (warning == null) return null;
    final schedule = adjustments.schedule(profile.schedule, inWeekOf: today);
    final weekday = Weekday.values
        .where(
          (day) => day.rawValue > today.weekdayIndex && schedule.slots(day).any((slot) => slot.isDemandingEndurance),
        )
        .firstOrNull;
    if (weekday == null) return null;
    final titles = text(schedule.slots(weekday).where((slot) => slot.isDemandingEndurance).toList());
    return make(
      id: 'load-${PlanAdjustments.monday(today).iso}-${weekday.rawValue}',
      source: PlanSuggestionSource.load,
      title: '${weekday.long}: $titles locker',
      reason: warning,
      profile: profile,
      adjustments: adjustments,
      week: today,
      evidenceIDs: load.evidenceIDs,
      edit: (proposed) => proposed.setWeekPlan(easing(schedule, weekday), base: profile.schedule, inWeekOf: today),
    );
  }

  /// Nach einer sehr harten Einheit: morgen entschärfen.
  static PlanSuggestion? postWorkout(
    PostWorkoutSuggestion suggestion, {
    required int activityID,
    required UserProfile profile,
    required PlanAdjustments adjustments,
  }) => make(
    id: 'post-$activityID-${suggestion.day.iso}',
    source: PlanSuggestionSource.postWorkout,
    title: 'Morgen locker',
    reason: suggestion.text,
    profile: profile,
    adjustments: adjustments,
    week: suggestion.day,
    evidenceIDs: const ['intensity.distribution'],
    edit: (proposed) => proposed.setWeekPlan(suggestion.schedule, base: profile.schedule, inWeekOf: suggestion.day),
  );

  /// Wochenrückblick: Nach einer Woche mit deutlich mehr Belastung beginnt die nächste ohne harte Einheit am Anfang –
  /// die erste fordernde Ausdauereinheit wird locker.
  static PlanSuggestion? nextWeek({
    required WeekLoadResult load,
    required UserProfile profile,
    required PlanAdjustments adjustments,
    required CalendarDay today,
  }) {
    if (load.warning == null) return null;
    final monday = PlanAdjustments.monday(today).adding(7);
    final schedule = adjustments.schedule(profile.schedule, inWeekOf: monday);
    final weekday = Weekday.values
        .where((day) => schedule.slots(day).any((slot) => slot.isDemandingEndurance))
        .firstOrNull;
    if (weekday == null) return null;
    return make(
      id: 'next-${monday.iso}',
      source: PlanSuggestionSource.nextWeek,
      title: 'Nächste Woche ruhiger beginnen',
      reason:
          'Diese Woche lag die Belastung ${((load.increase ?? 0) * 100).round()} % über dem Schnitt. '
          '${weekday.long} locker statt fordernd gibt dem Körper Zeit, sich anzupassen.',
      profile: profile,
      adjustments: adjustments,
      week: monday,
      evidenceIDs: load.evidenceIDs,
      edit: (proposed) => proposed.setWeekPlan(easing(schedule, weekday), base: profile.schedule, inWeekOf: monday),
    );
  }
}

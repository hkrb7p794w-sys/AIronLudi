import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

/// Saisonplan Woche für Woche: Einheiten mit eingesetzten Testwerten und Erledigt-Status (Port von `PlanViewModel`).
final class PlanController extends ChangeNotifier {
  PlanController({required this.schedule, DateTime? now}) : today = CalendarDay.fromDate(now ?? DateTime.now()) {
    weekIndex = currentWeekIndex;
  }

  final SeasonSchedule? schedule;
  CalendarDay today;

  /// Index der angezeigten Woche in `schedule.weeks`.
  int weekIndex = 0;
  List<PlannedUnit> units = const [];

  List<GarminActivity> _activities = const [];
  List<CalendarDay> _gymDays = const [];
  SeasonConfig _config = SeasonConfig.standard;
  CompetitionDecisions _decisions = const {};

  PlanWeek? get week {
    final weeks = schedule?.weeks ?? const <PlanWeek>[];
    return weekIndex >= 0 && weekIndex < weeks.length ? weeks[weekIndex] : null;
  }

  /// Aktuelle Woche; vor Planbeginn die erste, nach Planende die letzte.
  int get currentWeekIndex {
    final schedule = this.schedule;
    if (schedule == null || schedule.weeks.isEmpty) return 0;
    if (schedule.index(today) case final index?) return index;
    return (schedule.weeks.first.monday ?? today) > today ? 0 : schedule.weeks.length - 1;
  }

  bool get isCurrentWeek => weekIndex == currentWeekIndex;
  bool get canGoBack => weekIndex > 0;
  bool get canGoForward => weekIndex + 1 < (schedule?.weeks.length ?? 0);

  PlanPhaseInfo? get phaseInfo => switch (week) {
    final week? => schedule?.phases[week.ph],
    null => null,
  };

  /// „KW 44“ (ISO-Kalenderwoche).
  String get weekTitle {
    final monday = week?.monday;
    if (monday == null) return 'Plan';
    // ISO 8601: Woche mit dem ersten Donnerstag des Jahres ist KW 1.
    final thursday = monday.adding(3);
    final firstThursday = CalendarDay(
      thursday.year,
      1,
      1,
    ).adding((DateTime.thursday - DateTime(thursday.year).weekday + 7) % 7);
    return 'KW ${firstThursday.daysUntil(thursday) ~/ 7 + 1}';
  }

  String get weekRange {
    final monday = week?.monday;
    if (monday == null) return '';
    String short(CalendarDay day) => '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.';
    return '${short(monday)} – ${short(monday.adding(6))}';
  }

  int get doneCount => units.where((unit) => unit.done && unit.kind != PlannedUnitKind.bikeOptional).length;
  int get requiredCount => units.where((unit) => unit.kind != PlannedUnitKind.bikeOptional).length;

  void update({
    required List<GarminActivity> activities,
    required List<CalendarDay> gymDays,
    required SeasonConfig config,
    required CompetitionDecisions decisions,
    DateTime? now,
  }) {
    today = CalendarDay.fromDate(now ?? DateTime.now());
    _activities = activities;
    _gymDays = gymDays;
    _config = config;
    _decisions = decisions;
    _rebuild();
  }

  void show(int index) {
    final weeks = schedule?.weeks ?? const <PlanWeek>[];
    if (index < 0 || index >= weeks.length) return;
    weekIndex = index;
    _rebuild();
  }

  void step(int offset) => show(weekIndex + offset);

  void _rebuild() {
    final schedule = this.schedule;
    final week = this.week;
    if (schedule == null || week == null) {
      units = const [];
    } else {
      final planned = schedule.units(week, config: _config, decisions: _decisions);
      units = PlanProgress.mark(planned, week: week, activities: _activities, gymDays: _gymDays);
    }
    notifyListeners();
  }
}

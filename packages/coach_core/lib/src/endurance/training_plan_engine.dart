import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/recommendation.dart';
import '../coach/recovery_level.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../profile/week_schedule.dart';
import '../util/german_format.dart';
import 'endurance_plan.dart';
import 'endurance_workouts.dart';
import 'training_load.dart';

/// Ergebnis einer Anpassung.
final class AdaptationResult {
  const AdaptationResult(this.plan, this.changes);

  final EndurancePlan plan;

  /// Neue Einträge im Anpassungsverlauf (geänderte kommende Einheiten).
  final List<PlanAdjustmentEntry> changes;

  bool get changed => changes.isNotEmpty;
}

/// Adaptiver Ausdauerplan: erstellt den Makrozyklus (Periodisierung, Wochenumfang, Verteilung der Einheiten) und passt
/// kommende Einheiten täglich an. Regeln entscheiden, deterministisch und getestet – die KI formuliert höchstens.
///
/// Anpassung in dieser Reihenfolge (spätere Regeln haben Vorrang):
/// 1. Ausfall: eine ausgefallene Schlüsseleinheit der laufenden Woche ersetzt eine spätere Grundlageneinheit derselben
///    Woche, wenn davor und danach keine harte Einheit liegt (höchstens eine je Woche, nichts wird gestapelt).
/// 2. Belastung, disziplinübergreifend: war ein Tag der letzten zwei deutlich härter als geplant (Training Stress
///    über Plan, auch ungeplante Aktivitäten), wird die nächste Einheit danach entschärft – gleich welche Disziplin.
/// 3. Ermüdung: Form (CTL − ATL) unter −30 nimmt heute und morgen die Intensität heraus.
/// 4. Erholung heute: Ampel aus HRV-Status, Readiness, Ruhepuls und Schlaf (`RecoveryEvaluator`) sowie Body Battery
///    beim Aufwachen. „Locker“ macht aus harten Einheiten Grundlage und kürzt die lange um ein Drittel, „Pause“ macht
///    einen Ruhetag. Ohne Health-/Garmin-Werte entfällt die Regel.
///
/// Angepasst wird immer vom ursprünglichen Plan aus: Entfällt der Grund, gilt die Einheit wieder wie geplant.
/// Wettkämpfe werden nie automatisch verändert.
abstract final class TrainingPlanEngine {
  static const maxWeeks = 52;
  static const minWeeklyMinutes = 60;

  /// Prüft die Eingaben; `null`, wenn ein Plan erstellt werden kann.
  static String? validate(TrainingPlanRequest request) {
    if (request.username.isEmpty) return 'Kein Benutzer angemeldet.';
    if (request.planSports.isEmpty) return 'Bitte mindestens eine Disziplin wählen.';
    if (request.days.isEmpty) return 'Bitte mindestens einen Trainingstag wählen.';
    if (request.weeklyMinutes < minWeeklyMinutes) return 'Bitte mindestens 60 Minuten je Woche einplanen.';
    switch (request.mode) {
      case PlanningMode.goal:
        final event = request.event;
        final day = request.eventDay;
        if (event == null) return 'Bitte ein Ziel wählen.';
        if (day == null) return 'Bitte das Datum des Wettkampfs wählen.';
        if (day < request.start) return 'Der Wettkampf liegt vor dem Planbeginn.';
        if (weekCount(request) > maxWeeks) return 'Der Wettkampf liegt mehr als 52 Wochen entfernt.';
      case PlanningMode.period:
        if (request.weeks < 1 || request.weeks > maxWeeks) return 'Der Zeitraum muss zwischen 1 und 52 Wochen liegen.';
    }
    return null;
  }

  static CalendarDay monday(CalendarDay day) => day.adding(-day.weekdayIndex);

  /// Anzahl der Planwochen (Montag bis Sonntag).
  static int weekCount(TrainingPlanRequest request) => switch (request.mode) {
    PlanningMode.period => request.weeks,
    PlanningMode.goal => monday(request.start).daysUntil(monday(request.eventDay ?? request.start)) ~/ 7 + 1,
  };

  // Periodisierung

  /// Phasen je Woche. Ziel: Grundlage → Aufbau → Spitze → Tapering → Wettkampfwoche; Zeitraum: Grundlage bzw.
  /// Grundlage → Aufbau. Jede vierte Woche in Grundlage und Aufbau ist eine Entlastungswoche (3:1).
  static List<EndurancePhase> periodize({
    required PlanningMode mode,
    required int weeks,
    EnduranceEvent? event,
    PeriodFocus focus = PeriodFocus.fitness,
  }) {
    final total = weeks.clamp(1, maxWeeks);
    final result = <EndurancePhase>[];
    void loading(int base, int build) {
      for (var index = 0; index < base + build; index++) {
        final phase = index < base ? EndurancePhase.base : EndurancePhase.build;
        result.add(index % 4 == 3 && total >= 4 ? EndurancePhase.recovery : phase);
      }
    }

    switch (mode) {
      case PlanningMode.goal:
        final taper = math.min(event?.taperWeeks ?? 1, total);
        final remaining = total - taper;
        final peak = remaining >= 8 ? 2 : (remaining >= 5 ? 1 : 0);
        final rest = remaining - peak;
        final build = rest >= 3 ? (rest * 0.45).round() : rest;
        loading(rest - build, build);
        result.addAll(List.filled(peak, EndurancePhase.peak));
        result.addAll(List.filled(taper - 1, EndurancePhase.taper));
        result.add(EndurancePhase.race);
      case PlanningMode.period:
        final base = focus == PeriodFocus.base ? total : (total / 2).ceil();
        loading(base, total - base);
    }
    return result;
  }

  /// Umfang je Woche als Anteil der verfügbaren Zeit: Aufbau in Schritten von 5 % (höchstens rund 6 % mehr je
  /// Woche, unter der 10-%-Grenze), Entlastung 65 % der Vorwoche, Tapering 70 % bzw. 60 %, Wettkampfwoche 45 %.
  static List<double> volumeFactors(List<EndurancePhase> phases) {
    final result = <double>[];
    double? level;
    var taperIndex = 0;
    for (final phase in phases) {
      switch (phase) {
        case EndurancePhase.base || EndurancePhase.build:
          final cap = phase == EndurancePhase.base ? 0.95 : 1.0;
          level = level == null ? 0.8 : math.min(cap, level + 0.05);
          result.add(level);
        case EndurancePhase.recovery:
          result.add((level ?? 0.8) * 0.65);
        case EndurancePhase.peak:
          level = 0.95;
          result.add(level);
        case EndurancePhase.taper:
          result.add(taperIndex == 0 ? 0.7 : 0.6);
          taperIndex += 1;
        case EndurancePhase.race:
          result.add(0.45);
      }
    }
    return [for (final value in result) (value * 100).round() / 100];
  }

  // Erstellung

  static EndurancePlan generate(TrainingPlanRequest request, {required DateTime now, String? id}) {
    if (validate(request) case final error?) throw ArgumentError(error);
    final planID = id ?? 'P${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    final phases = periodize(
      mode: request.mode,
      weeks: weekCount(request),
      event: request.mode == PlanningMode.goal ? request.event : null,
      focus: request.focus,
    );
    final factors = volumeFactors(phases);
    final firstMonday = monday(request.start);
    final weeks = <PlanWeekInfo>[];
    final slots = <PlanSlot>[];
    for (var index = 0; index < phases.length; index++) {
      final weekMonday = firstMonday.adding(7 * index);
      final minutes = (request.weeklyMinutes * factors[index] / 5).round() * 5;
      weeks.add(PlanWeekInfo(index: index, monday: weekMonday, phase: phases[index], minutes: minutes));
      slots.addAll(
        _week(request, planID: planID, index: index, monday: weekMonday, phase: phases[index], minutes: minutes),
      );
    }
    return EndurancePlan(
      id: planID,
      username: request.username,
      request: request,
      createdAt: now,
      weeks: weeks,
      slots: slots,
    );
  }

  /// Anteile der Disziplinen an den Einheiten.
  static Map<EnduranceSport, double> shares(TrainingPlanRequest request) {
    final sports = request.planSports;
    final event = request.mode == PlanningMode.goal ? request.event : null;
    if (event == null) return {for (final sport in sports) sport: 1.0};
    if (event.isTriathlon) {
      return {EnduranceSport.swim: 0.22, EnduranceSport.bike: 0.43, EnduranceSport.run: 0.35};
    }
    return {for (final sport in sports) sport: sport == event.primary ? 1.0 : 0.25};
  }

  /// Hauptdisziplin (lange Einheit, erste Qualitätseinheit).
  static EnduranceSport primary(TrainingPlanRequest request) {
    if (request.mode == PlanningMode.goal && request.event != null) return request.event!.primary;
    return request.sports.firstOrNull ?? request.planSports.first;
  }

  /// Einheiten je Disziplin (größter Rest; jede gewählte Disziplin mindestens einmal, wenn genug Tage).
  static Map<EnduranceSport, int> sessionCounts(Map<EnduranceSport, double> shares, int sessions) {
    final total = shares.values.fold(0.0, (sum, value) => sum + value);
    final exact = {for (final entry in shares.entries) entry.key: sessions * entry.value / total};
    final counts = {for (final entry in exact.entries) entry.key: entry.value.floor()};
    var left = sessions - counts.values.fold(0, (sum, value) => sum + value);
    final byRemainder = exact.keys.toList()..sort((a, b) => (exact[b]! - counts[b]!).compareTo(exact[a]! - counts[a]!));
    for (final sport in byRemainder) {
      if (left <= 0) break;
      counts[sport] = counts[sport]! + 1;
      left -= 1;
    }
    if (sessions >= shares.length) {
      for (final sport in shares.keys) {
        if (counts[sport]! > 0) continue;
        final richest = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
        counts[richest] = counts[richest]! - 1;
        counts[sport] = 1;
      }
    }
    return counts;
  }

  static List<EnduranceWorkoutType> _qualityTypes(EndurancePhase phase, EnduranceEvent? event, bool firstWeek) {
    final long = event != null && event.defaultMinutes >= 200;
    return switch (phase) {
      EndurancePhase.base => firstWeek ? const [] : const [EnduranceWorkoutType.tempo],
      EndurancePhase.build => const [EnduranceWorkoutType.threshold, EnduranceWorkoutType.vo2max],
      EndurancePhase.peak =>
        long
            ? const [EnduranceWorkoutType.tempo, EnduranceWorkoutType.threshold]
            : const [EnduranceWorkoutType.threshold, EnduranceWorkoutType.vo2max],
      EndurancePhase.taper || EndurancePhase.race => const [EnduranceWorkoutType.threshold],
      EndurancePhase.recovery => const [],
    };
  }

  static int _minutes(EnduranceSport sport, EnduranceWorkoutType type, double raw, EnduranceEvent? event) {
    final (low, high) = switch (type) {
      EnduranceWorkoutType.recovery => (20, 45),
      EnduranceWorkoutType.endurance => switch (sport) {
        EnduranceSport.run => (30, 80),
        EnduranceSport.bike => (40, 150),
        EnduranceSport.swim => (30, 60),
      },
      EnduranceWorkoutType.tempo ||
      EnduranceWorkoutType.threshold ||
      EnduranceWorkoutType.vo2max => sport == EnduranceSport.swim ? (35, 70) : (40, 90),
      EnduranceWorkoutType.long => switch (sport) {
        EnduranceSport.run => (
          50,
          switch (event) {
            EnduranceEvent.marathon => 180,
            EnduranceEvent.halfMarathon || EnduranceEvent.triFull => 130,
            EnduranceEvent.triMiddle => 110,
            _ => 100,
          },
        ),
        EnduranceSport.bike => (
          60,
          switch (event) {
            EnduranceEvent.triFull => 330,
            EnduranceEvent.bikeEvent => 300,
            EnduranceEvent.triMiddle => 210,
            _ => 180,
          },
        ),
        EnduranceSport.swim => (40, 90),
      },
      EnduranceWorkoutType.rest || EnduranceWorkoutType.race => (0, 1000),
    };
    final clamped = raw.clamp(low.toDouble(), high.toDouble());
    return math.max(5, (clamped / 5).round() * 5);
  }

  static const _sportWeight = {EnduranceSport.run: 1.0, EnduranceSport.bike: 1.3, EnduranceSport.swim: 0.8};
  static const _typeWeight = {
    EnduranceWorkoutType.recovery: 0.6,
    EnduranceWorkoutType.endurance: 1.0,
    EnduranceWorkoutType.long: 1.8,
    EnduranceWorkoutType.tempo: 1.1,
    EnduranceWorkoutType.threshold: 1.1,
    EnduranceWorkoutType.vo2max: 1.05,
  };

  static List<PlanSlot> _week(
    TrainingPlanRequest request, {
    required String planID,
    required int index,
    required CalendarDay monday,
    required EndurancePhase phase,
    required int minutes,
  }) {
    final event = request.mode == PlanningMode.goal ? request.event : null;
    final eventDay = request.mode == PlanningMode.goal ? request.eventDay : null;
    final isRaceWeek = phase == EndurancePhase.race && eventDay != null;
    final weekdays = {...request.days}.toList()..sort((a, b) => a.index.compareTo(b.index));
    var days = [
      for (final weekday in weekdays)
        if (monday.adding(weekday.index) case final day when day >= request.start)
          if (eventDay == null || day < eventDay) day,
    ];
    if (isRaceWeek) {
      // Wettkampfwoche: höchstens drei kurze Einheiten vorher, am Vortag nur locker.
      days = days.length > 3 ? days.sublist(days.length - 3) : days;
    }
    final slots = <PlanSlot>[];
    final shares = TrainingPlanEngine.shares(request);
    final main = primary(request);

    // Lange Einheit: am gewünschten Tag, sonst am letzten Trainingstag; nicht in der Wettkampfwoche.
    final types = <CalendarDay, EnduranceWorkoutType>{};
    final sports = <CalendarDay, EnduranceSport>{};
    final counts = sessionCounts(shares, days.length);
    void use(CalendarDay day, EnduranceSport sport, EnduranceWorkoutType type) {
      types[day] = type;
      sports[day] = sport;
      counts[sport] = (counts[sport] ?? 0) - 1;
    }

    if (days.isNotEmpty && !isRaceWeek) {
      final longDay = days.where((day) => day.weekdayIndex == request.longDay.index).firstOrNull ?? days.last;
      use(longDay, main, days.length == 1 ? EnduranceWorkoutType.endurance : EnduranceWorkoutType.long);
    }

    // Qualitätseinheiten mit möglichst viel Abstand zu langer und anderer harter Einheit.
    var quality = _qualityTypes(phase, event, index == 0);
    if (days.length <= 4) quality = quality.take(1).toList();
    if (days.length <= 1 && !isRaceWeek) quality = const [];
    final qualitySports = _qualitySports(request, shares, main);
    for (var q = 0; q < quality.length; q++) {
      final free = [
        for (final day in days)
          if (!types.containsKey(day) && !(isRaceWeek && day == eventDay.adding(-1))) day,
      ];
      if (free.isEmpty) break;
      int distance(CalendarDay day) {
        final busy = [
          for (final entry in types.entries)
            if (entry.value != EnduranceWorkoutType.recovery && entry.value != EnduranceWorkoutType.endurance)
              entry.key,
          if (isRaceWeek) eventDay,
        ];
        return busy.isEmpty ? 7 : busy.map((other) => (other.daysUntil(day)).abs()).reduce(math.min);
      }

      final best = free.reduce((a, b) => distance(b) > distance(a) ? b : a);
      use(best, qualitySports[q % qualitySports.length], quality[q]);
    }

    // Übrige Tage: Disziplinen nach verbleibender Zahl, möglichst nicht zweimal hintereinander dieselbe.
    EnduranceSport? previous;
    for (final day in days) {
      if (types.containsKey(day)) {
        previous = sports[day];
        continue;
      }
      final candidates = shares.keys.toList()
        ..sort((a, b) {
          final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
          if (byCount != 0) return byCount;
          return (a == previous ? 1 : 0).compareTo(b == previous ? 1 : 0);
        });
      var sport = candidates.first;
      if (sport == previous && candidates.length > 1 && (counts[candidates[1]] ?? 0) == (counts[sport] ?? 0)) {
        sport = candidates[1];
      }
      if ((counts[sport] ?? 0) <= 0) sport = main;
      final dayBefore = types[day.adding(-1)];
      final afterHard = dayBefore != null && (dayBefore.isHard || dayBefore == EnduranceWorkoutType.long);
      final beforeRace = isRaceWeek && day == eventDay.adding(-1);
      use(
        day,
        sport,
        (afterHard && days.length >= 4) || beforeRace ? EnduranceWorkoutType.recovery : EnduranceWorkoutType.endurance,
      );
      previous = sport;
    }

    // Minuten nach Gewicht verteilen.
    final weights = {for (final day in days) day: _typeWeight[types[day]]! * _sportWeight[sports[day]]!};
    final totalWeight = weights.values.fold(0.0, (sum, value) => sum + value);
    for (final day in days) {
      final sport = sports[day]!;
      final type = types[day]!;
      final raw = totalWeight == 0 ? 0.0 : minutes * weights[day]! / totalWeight;
      final workout = EnduranceWorkouts.build(
        sport: sport,
        type: type,
        minutes: _minutes(sport, type, raw, event),
        thresholds: request.thresholds,
        phase: phase,
        event: event,
      );
      slots.add(_slot(planID, index, day, phase, workout));
    }

    if (isRaceWeek) {
      final target = request.targetMinutes ?? event!.defaultMinutes;
      final parts = event!.isTriathlon
          ? {EnduranceSport.swim: 0.15, EnduranceSport.bike: 0.52, EnduranceSport.run: 0.33}
          : {event.primary: 1.0};
      for (final entry in parts.entries) {
        final workout = EnduranceWorkouts.build(
          sport: entry.key,
          type: EnduranceWorkoutType.race,
          minutes: math.max(5, (target * entry.value).round()),
          thresholds: request.thresholds,
          phase: phase,
          event: event,
          note: request.targetMinutes == null ? '' : 'Zielzeit ${_clock(request.targetMinutes!)}',
        );
        slots.add(_slot(planID, index, eventDay, phase, workout));
      }
    }
    slots.sort((a, b) => a.day.compareTo(b.day));
    return slots;
  }

  static String _clock(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h';

  static List<EnduranceSport> _qualitySports(
    TrainingPlanRequest request,
    Map<EnduranceSport, double> shares,
    EnduranceSport main,
  ) {
    final event = request.mode == PlanningMode.goal ? request.event : null;
    if (event != null && event.isTriathlon) return const [EnduranceSport.run, EnduranceSport.bike];
    if (event != null) return [event.primary];
    final ordered = shares.keys.toList()..sort((a, b) => (a == main ? 0 : 1).compareTo(b == main ? 0 : 1));
    return ordered;
  }

  static PlanSlot _slot(String planID, int week, CalendarDay day, EndurancePhase phase, EnduranceWorkout workout) =>
      PlanSlot(
        id: '$planID-${day.iso}-${workout.sport.rawValue}',
        day: day,
        week: week,
        phase: phase,
        baseline: workout,
      );

  // Anpassung

  static String activityKey(GarminActivity activity) => '${activity.id}@${activity.startLocal ?? ''}';

  static String _weekday(CalendarDay day) => Weekday.values[day.weekdayIndex].short;

  static String _points(double value) => value.round().toString();

  static AdaptationResult adapt(
    EndurancePlan plan, {
    required List<GarminActivity> activities,
    required List<DailyMetrics> metrics,
    required CalendarDay today,
    required DateTime now,
  }) {
    final next = plan.copy();
    final thresholds = next.request.thresholds;
    final event = next.request.mode == PlanningMode.goal ? next.request.event : null;
    final window = [
      for (final activity in activities)
        if (activity.day case final day? when day >= next.firstDay.adding(-90) && day <= today) activity,
    ];
    final loads = {for (final activity in window) activityKey(activity): TrainingLoad.actual(activity, thresholds)};

    // 1. Zuordnen: erledigt bzw. ausgefallen.
    final used = <String>{
      for (final slot in next.slots)
        if (slot.status == SlotStatus.completed && slot.activityKey != null) slot.activityKey!,
    };
    final ordered = [...next.slots]..sort((a, b) => a.day.compareTo(b.day));
    for (final slot in ordered) {
      if (slot.day > today || slot.status == SlotStatus.completed) continue;
      final candidates = [
        for (final activity in window)
          if (activity.day == slot.day &&
              EnduranceSport.of(activity.sport) == slot.current.sport &&
              !used.contains(activityKey(activity)))
            activity,
      ]..sort((a, b) => (b.durationSeconds ?? 0).compareTo(a.durationSeconds ?? 0));
      if (candidates.firstOrNull case final activity?) {
        final key = activityKey(activity);
        used.add(key);
        slot
          ..status = SlotStatus.completed
          ..activityKey = key
          ..actualLoad = loads[key];
      } else if (slot.day < today) {
        slot.status = slot.current.isRest ? SlotStatus.completed : SlotStatus.missed;
      }
    }

    // Arbeitsstand der kommenden Einheiten (vom ursprünglichen Plan aus).
    final upcoming = [
      for (final slot in ordered)
        if (slot.day >= today && slot.status == SlotStatus.planned) slot,
    ];
    final work = {for (final slot in upcoming) slot.id: _Working(slot.baseline.type, slot.baseline.minutes)};
    bool hardOn(CalendarDay day) => next.slotsOn(day).any((slot) {
      final type = work[slot.id]?.type ?? slot.current.type;
      return type.isHard || type == EnduranceWorkoutType.long;
    });

    // 2. Ausgefallene Schlüsseleinheit der laufenden Woche nachholen.
    final week = next.weekOf(today);
    if (week != null) {
      final missed = [
        for (final slot in ordered)
          if (slot.week == week.index && slot.status == SlotStatus.missed && slot.baseline.type.isKey) slot,
      ];
      if (missed.firstOrNull case final lost?) {
        final targets =
            [
              for (final slot in upcoming)
                if (slot.week == week.index &&
                    slot.baseline.type == EnduranceWorkoutType.endurance &&
                    !hardOn(slot.day.adding(-1)) &&
                    !hardOn(slot.day.adding(1)))
                  slot,
            ]..sort(
              (a, b) => (a.current.sport == lost.baseline.sport ? 0 : 1).compareTo(
                b.current.sport == lost.baseline.sport ? 0 : 1,
              ),
            );
        if (targets.firstOrNull case final target?) {
          work[target.id] = _Working(
            lost.baseline.type,
            lost.baseline.minutes,
            cause: AdjustmentCause.missed,
            reason:
                'Nachgeholt: ${lost.baseline.title} vom ${_weekday(lost.day)} ${GermanFormat.date(lost.day)} '
                'ist ausgefallen.',
          );
        }
      }
    }

    // 3. Mehrbelastung der letzten zwei Tage auf die nächste Einheit (gleich welche Disziplin).
    for (var offset = 2; offset >= 0; offset--) {
      final day = today.adding(-offset);
      final dayActivities = [
        for (final activity in window)
          if (activity.day == day) activity,
      ];
      if (dayActivities.isEmpty) continue;
      var actual = 0.0;
      var planned = 0.0;
      for (final slot in next.slotsOn(day)) {
        planned += slot.current.load;
      }
      for (final activity in dayActivities) {
        actual += loads[activityKey(activity)] ?? 0;
      }
      final excess = actual - planned;
      if (excess <= math.max(25, planned * 0.3)) continue;
      final later = [
        for (final slot in ordered)
          if (slot.day > day) slot,
      ];
      final target = later.firstOrNull;
      if (target == null || target.day < today || target.status != SlotStatus.planned) continue;
      final current = work[target.id]!;
      if (current.type == EnduranceWorkoutType.race || current.type == EnduranceWorkoutType.rest) continue;
      final sports = {for (final activity in dayActivities) EnduranceSport.of(activity.sport)?.label ?? 'Training'}
          .join(' + ');
      final reason =
          '$sports am ${_weekday(day)}: ${_points(actual)} statt ${_points(planned)} geplanter Belastungspunkte – '
          '${target.baseline.sport.label} ${current.type.isHard || current.type == EnduranceWorkoutType.long ? 'ohne Intensität' : 'kürzer'}.';
      if (current.type.isHard) {
        work[target.id] = _Working(
          EnduranceWorkoutType.endurance,
          math.min(current.minutes, 60),
          cause: AdjustmentCause.load,
          reason: reason,
        );
      } else if (current.type == EnduranceWorkoutType.long) {
        work[target.id] = _Working(
          EnduranceWorkoutType.endurance,
          (current.minutes * 0.75).round(),
          cause: AdjustmentCause.load,
          reason: reason,
        );
      } else {
        final cut = (excess / (excess + 100)).clamp(0.15, 0.4);
        work[target.id] = _Working(
          current.type,
          (current.minutes * (1 - cut)).round(),
          cause: AdjustmentCause.load,
          reason: reason,
        );
      }
    }

    // 4. Ermüdung aus den letzten Wochen.
    final state = TrainingLoad.state(TrainingLoad.daily(window, thresholds), day: today);
    if (state.form < -30) {
      final form = state.form.round();
      for (final slot in upcoming) {
        if (slot.day > today.adding(1)) continue;
        final current = work[slot.id]!;
        if (current.type == EnduranceWorkoutType.race || current.type == EnduranceWorkoutType.rest) continue;
        final reason = 'Ermüdung hoch (Form $form): Intensität raus.';
        if (current.type.isHard) {
          work[slot.id] = _Working(
            EnduranceWorkoutType.endurance,
            math.min(current.minutes, 60),
            cause: AdjustmentCause.fatigue,
            reason: reason,
          );
        } else if (state.form < -40) {
          work[slot.id] = _Working(
            current.type == EnduranceWorkoutType.long ? EnduranceWorkoutType.endurance : current.type,
            (current.minutes * 0.75).round(),
            cause: AdjustmentCause.fatigue,
            reason: 'Ermüdung sehr hoch (Form $form): kürzer und locker.',
          );
        }
      }
    }

    // 5. Erholungswerte von heute.
    final recovery = recoveryToday(metrics, today: today);
    if (recovery != null && recovery.level != RecoveryLevel.normal) {
      final why = recovery.reasons.take(2).join(', ');
      for (final slot in upcoming) {
        if (slot.day != today) continue;
        final current = work[slot.id]!;
        if (current.type == EnduranceWorkoutType.race || current.type == EnduranceWorkoutType.rest) continue;
        if (recovery.level == RecoveryLevel.pause) {
          work[slot.id] = _Working(
            EnduranceWorkoutType.rest,
            0,
            cause: AdjustmentCause.recovery,
            reason: 'Ruhetag statt ${slot.baseline.type.label}: $why.',
          );
        } else if (current.type.isHard) {
          work[slot.id] = _Working(
            EnduranceWorkoutType.endurance,
            math.min(current.minutes, 60),
            cause: AdjustmentCause.recovery,
            reason: 'Locker in Zone 2 statt ${current.type.label}: $why.',
          );
        } else if (current.type == EnduranceWorkoutType.long) {
          work[slot.id] = _Working(
            EnduranceWorkoutType.endurance,
            (current.minutes * 2 / 3).round(),
            cause: AdjustmentCause.recovery,
            reason: 'Um ein Drittel kürzer und locker: $why.',
          );
        }
      }
    }

    // Neue Einheiten bauen und Änderungen festhalten.
    final changes = <PlanAdjustmentEntry>[];
    for (final slot in upcoming) {
      final working = work[slot.id]!;
      final unchanged =
          working.cause == null && working.type == slot.baseline.type && working.minutes == slot.baseline.minutes;
      final updated = unchanged
          ? slot.baseline
          : EnduranceWorkouts.build(
              sport: slot.baseline.sport,
              type: working.type,
              minutes: math.max(15, working.minutes),
              thresholds: thresholds,
              phase: slot.phase,
              event: event,
              note: working.reason ?? '',
            );
      if (updated.sameContent(slot.current)) continue;
      changes.add(
        PlanAdjustmentEntry(
          at: now,
          slotID: slot.id,
          day: slot.day,
          cause: working.cause ?? AdjustmentCause.restored,
          reason: working.reason ?? 'Der Anlass ist entfallen – wieder wie geplant.',
          before: slot.current.summary,
          after: updated.summary,
        ),
      );
      slot.current = updated;
    }
    if (changes.isNotEmpty) {
      next.revision += 1;
      next.adjustments.addAll(changes);
      if (next.adjustments.length > EndurancePlan.maxAdjustments) {
        next.adjustments.removeRange(0, next.adjustments.length - EndurancePlan.maxAdjustments);
      }
    }
    next.lastAdapted = today;
    return AdaptationResult(next, changes);
  }

  /// Ampel aus den Werten von heute (HRV-Status, Readiness, Ruhepuls gegen den 7-Tage-Schnitt, Schlaf) und der Body
  /// Battery beim Aufwachen (unter 25 Pause, unter 40 locker). `null` ohne verwertbare Werte (Health ist optional).
  static Recommendation? recoveryToday(List<DailyMetrics> metrics, {required CalendarDay today}) {
    final current = metrics.where((entry) => entry.day == today).firstOrNull;
    if (current == null) return null;
    final previous = [
      for (final entry in metrics)
        if (entry.day < today && entry.day >= today.adding(-7) && entry.restingHeartRate != null)
          entry.restingHeartRate!,
    ];
    final average = previous.isEmpty ? null : previous.reduce((a, b) => a + b) / previous.length;
    final battery = current.bodyBatteryAtWake ?? current.bodyBatteryHigh;
    final hasInputs = RecoveryEvaluator.hasInputs(current, restingHeartRate7DayAverage: average);
    if (!hasInputs && battery == null) return null;
    final base = hasInputs
        ? RecoveryEvaluator.evaluate(current, restingHeartRate7DayAverage: average)
        : const Recommendation(level: RecoveryLevel.normal, reasons: []);
    var level = base.level;
    final reasons = [
      for (final reason in base.reasons)
        if (reason != 'keine Erholungswerte auffällig') reason,
    ];
    if (battery != null && battery < 25) {
      level = RecoveryLevel.pause;
      reasons.add('Body Battery ${battery.round()} beim Aufwachen');
    } else if (battery != null && battery < 40) {
      if (level == RecoveryLevel.normal) level = RecoveryLevel.locker;
      reasons.add('Body Battery ${battery.round()} beim Aufwachen');
    }
    return Recommendation(level: level, reasons: reasons);
  }
}

final class _Working {
  const _Working(this.type, this.minutes, {this.cause, this.reason});

  final EnduranceWorkoutType type;
  final int minutes;
  final AdjustmentCause? cause;
  final String? reason;
}

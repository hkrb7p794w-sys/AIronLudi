import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/heart_rate_zones.dart';
import '../coach/recovery_level.dart';
import '../coach/season_plan.dart';
import '../garmin/garmin_activity.dart';
import 'season_schedule.dart';

/// Baustein des Wochenrahmens.
enum WeekFrameBlock {
  push('push'),
  pull('pull'),
  pp('pp'),
  swimlegs('swimlegs'),
  rest('rest'),

  /// Zwift am Wochenende
  zwift('z'),

  /// Longrun am Wochenende
  longRun('l'),

  /// Lange Radeinheit am Wochenende
  longRide('zlong'),

  /// Zwift-Intervall unter der Woche
  zwiftInterval('zi'),

  /// Qualitätslauf
  quality('q'),

  /// Z2-Lauf
  easy('e');

  const WeekFrameBlock(this.rawValue);

  final String rawValue;
}

/// Wochenrahmen je Phase (`coach_days.jinja` im Altbestand, Stand 14.10.2026): feste Bausteine je Wochentag und
/// Bausteine ohne festen Tag.
final class WeekFrame {
  const WeekFrame({required this.fixed, required this.flex});

  /// Wochentag (0 = Montag) → Bausteine
  final Map<int, List<WeekFrameBlock>> fixed;
  final List<WeekFrameBlock> flex;

  static WeekFrame frame(String phase) {
    const gym = {
      0: [WeekFrameBlock.push],
      1: [WeekFrameBlock.swimlegs],
      2: [WeekFrameBlock.pull],
      3: [WeekFrameBlock.swimlegs],
      4: [WeekFrameBlock.pp],
    };
    Map<int, List<WeekFrameBlock>> withWeekend(List<WeekFrameBlock> weekend) => {...gym, 5: weekend, 6: weekend};
    switch (phase) {
      case 'Marathon-Aufbau' || 'Marathon-Taper':
        return WeekFrame(
          fixed: withWeekend(const [WeekFrameBlock.zwift, WeekFrameBlock.longRun]),
          flex: const [WeekFrameBlock.quality, WeekFrameBlock.easy],
        );
      case 'Regeneration':
        return const WeekFrame(
          fixed: {
            0: [WeekFrameBlock.rest],
            1: [WeekFrameBlock.swimlegs],
            2: [WeekFrameBlock.rest],
            3: [WeekFrameBlock.swimlegs],
            4: [WeekFrameBlock.rest],
            5: [WeekFrameBlock.zwift],
            6: [WeekFrameBlock.zwift],
          },
          flex: [WeekFrameBlock.easy],
        );
      case 'Almere-Aufbau' || 'Almere-Peak' || 'Almere-Taper':
        return WeekFrame(
          fixed: withWeekend(const [WeekFrameBlock.longRide]),
          flex: const [WeekFrameBlock.quality, WeekFrameBlock.easy, WeekFrameBlock.zwiftInterval],
        );
      default:
        return WeekFrame(
          fixed: withWeekend(const [WeekFrameBlock.zwift]),
          flex: const [WeekFrameBlock.quality, WeekFrameBlock.easy],
        );
    }
  }
}

/// Sportart einer Zeile im Tagesplan.
enum TodayPlanSport { swim, bike, run, strength, rest }

/// Eine Zeile im Tagesplan.
final class TodayPlanItem {
  TodayPlanItem({
    required this.sport,
    required this.title,
    required this.caption,
    required this.detail,
    this.done = false,
    this.hardness = 0,
    this.chip = '',
    this.day,
  });

  final TodayPlanSport sport;
  final String title;
  final String caption;
  final String detail;
  final bool done;

  /// 2 = hart (Qualität, Test, Intervall) · 1 = gemischt · 0 = locker
  final int hardness;

  /// Hinweis bei gelber/roter Tagesampel, z. B. „nicht heute“ oder „⅓ weniger Sätze“
  String chip;

  /// Wochentag im Rest der Woche („Do“, „Sa/So“)
  String? day;

  String get id => '${day ?? ''}-${sport.name}-$title';

  @override
  bool operator ==(Object other) =>
      other is TodayPlanItem &&
      other.sport == sport &&
      other.title == title &&
      other.caption == caption &&
      other.detail == detail &&
      other.done == done &&
      other.hardness == hardness &&
      other.chip == chip &&
      other.day == day;

  @override
  int get hashCode => Object.hash(sport, title, caption, detail, done, hardness, chip, day);

  @override
  String toString() => 'TodayPlanItem($sport, $title, $caption, done: $done, chip: $chip, day: $day)';
}

/// Was diese Woche schon erledigt ist.
final class TodayPlanDone {
  const TodayPlanDone({this.swim = 0, this.run = 0, this.bike = 0, this.strength = 0});

  final int swim;
  final int run;
  final int bike;
  final int strength;

  @override
  bool operator ==(Object other) =>
      other is TodayPlanDone &&
      other.swim == swim &&
      other.run == run &&
      other.bike == bike &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(swim, run, bike, strength);

  @override
  String toString() => 'TodayPlanDone(swim: $swim, run: $run, bike: $bike, strength: $strength)';
}

/// Die Tagesansicht wie `coach_today()` im Altbestand: heutige Einheiten mit Hinweis je Einheit, offene Läufe ohne
/// festen Tag, Ausfälle am letzten Wochentag und der Rest der Woche. Eine Quelle für alle Hinweise – Karte und
/// Mitteilung zeigen nur an, was hier steht.
final class TodayPlan {
  /// [level]: Tagesampel (`null` = keine Werte); [gymDays]: Tage mit Krafteinheit (Garmin oder App); [runZones]:
  /// Intensitätsverteilung der Läufe dieser Woche (Uhr-Zonen).
  factory TodayPlan({
    required SeasonSchedule schedule,
    required SeasonConfig config,
    required CompetitionDecisions decisions,
    required CalendarDay today,
    required RecoveryLevel? level,
    required String advice,
    required TodayPlanDone done,
    required Set<CalendarDay> gymDays,
    required IntensityShare? runZones,
  }) {
    final weekday = today.weekdayIndex;
    final monday = today.adding(-weekday);
    final daysLeft = 6 - weekday;
    final weekCount = schedule.weeks.length;
    final items = <TodayPlanItem>[];
    final open = <TodayPlanItem>[];
    final rest = <TodayPlanItem>[];
    var hint = '';

    final index = schedule.weeks.indexWhere((week) => week.monday == monday);
    if (index < 0) {
      return TodayPlan._(
        phase: '',
        focus: '',
        weekIndex: 0,
        weekCount: weekCount,
        daysLeft: daysLeft,
        items: const [],
        open: const [],
        skipped: const [],
        rest: const [],
        hint: '',
        advice: advice,
      );
    }
    final week = FilledWeek(schedule.weeks[index], config: config, decisions: decisions);
    final frame = WeekFrame.frame(week.phase);
    final gymToday = gymDays.contains(today);
    final gymTuesday = weekday > 1 && gymDays.contains(today.adding(-(weekday - 1)));
    final zwiftCode = week.zwiftCode;

    TodayPlanItem item(
      TodayPlanSport sport,
      String title,
      String caption,
      String detail, {
      bool done = false,
      int hard = 0,
    }) => TodayPlanItem(sport: sport, title: title, caption: caption, detail: detail, done: done, hardness: hard);

    for (final block in frame.fixed[weekday] ?? const <WeekFrameBlock>[]) {
      switch (block) {
        case WeekFrameBlock.push || WeekFrameBlock.pull || WeekFrameBlock.pp:
          items.add(item(TodayPlanSport.strength, gymTitle(block), 'Home-Gym', '', done: gymToday));
        case WeekFrameBlock.rest:
          items.add(item(TodayPlanSport.rest, 'Ruhetag', 'Spazieren, Mobility', ''));
        case WeekFrameBlock.swimlegs:
          if (gymToday) {
            final detail = done.swim >= 1
                ? ''
                : (weekday == 1 ? 'Schwimmen dann am Donnerstag.' : 'Schwimmen fehlt diese Woche noch.');
            items.add(item(TodayPlanSport.strength, 'Beine', 'vor der Arbeit', detail, done: true));
          } else if (weekday == 1 && done.swim >= 1) {
            items.add(item(TodayPlanSport.swim, 'Schwimmen', week.swimCode, 'Beine dann am Donnerstag.', done: true));
          } else if (weekday == 1) {
            items.add(
              item(
                TodayPlanSport.swim,
                'Schwimmen oder Beine',
                week.swimCode,
                '${week.swim} · Das andere am Donnerstag.',
              ),
            );
          } else if (gymTuesday && done.swim >= 1) {
            items.add(item(TodayPlanSport.swim, 'Schwimmen', week.swimCode, 'Beine am Dienstag erledigt.', done: true));
          } else if (gymTuesday) {
            items.add(
              item(TodayPlanSport.swim, 'Schwimmen', week.swimCode, '${week.swim} · Beine am Dienstag erledigt.'),
            );
          } else if (done.swim >= 1) {
            items.add(
              item(TodayPlanSport.strength, 'Beine', 'vor der Arbeit', 'Schwimmen ist diese Woche schon erledigt.'),
            );
          } else {
            items.add(
              item(
                TodayPlanSport.swim,
                'Schwimmen',
                week.swimCode,
                '${week.swim} · Beine nur, falls sie am Dienstag ausgefallen sind.',
              ),
            );
          }
        case WeekFrameBlock.zwift:
          final title = weekday == 6 && done.bike >= 1 ? 'Zwift – diese Woche schon erledigt' : 'Zwift (Sa oder So)';
          items.add(item(TodayPlanSport.bike, title, zwiftCode, week.zwift, done: done.bike >= 1));
        case WeekFrameBlock.longRun when done.run < 3:
          final isOpen = week.longRunDecision == PlannedUnitDecision.open;
          final caption = week.longRunKilometers + (isOpen ? ' · 🏁 Wettkampf-Abschnitt offen' : '');
          final detail = week.longRun + (isOpen ? ' · Bei Ablehnen stattdessen: ${week.longRunAlternative}' : '');
          items.add(item(TodayPlanSport.run, 'Longrun (Sa oder So)', caption, detail));
        case WeekFrameBlock.longRide when week.zwift2.isNotEmpty:
          final weekend = week.zwift2.startsWith('Sa') || week.zwift2.startsWith('So');
          items.add(
            item(
              TodayPlanSport.bike,
              weekend ? 'Lange Radeinheit (Sa oder So)' : 'Rad',
              '',
              weekend ? String.fromCharCodes(week.zwift2.runes.skip(4)) : week.zwift2,
              done: done.bike >= 2,
            ),
          );
        default:
          break;
      }
    }

    final hasQuality = week.quality != '–';
    final openRuns = math.max((hasQuality ? 2 : 1) - done.run, 0);
    final qualityOpen = week.qualityDecision == PlannedUnitDecision.open;
    final qualityItem = item(
      TodayPlanSport.run,
      'Qualitätslauf',
      week.qualityCode + (qualityOpen ? ' · Wettkampf: im Reiter Plan annehmen oder ablehnen' : ''),
      week.quality + (qualityOpen ? ' · Bei Ablehnen stattdessen: ${week.qualityAlternative}' : ''),
      hard: 2,
    );
    final easyItem = item(TodayPlanSport.run, 'Lockerer Lauf (Z2)', week.easyShort, week.easy);
    if (openRuns > 0 && (frame.flex.contains(WeekFrameBlock.quality) || frame.flex.contains(WeekFrameBlock.easy))) {
      if (openRuns >= 2) {
        open.addAll([qualityItem, easyItem]);
      } else if (hasQuality) {
        // Welcher Lauf fehlt, verrät die HF-Verteilung der Woche: überwiegend locker → Qualität fehlt.
        if (runZones != null && runZones.easyPercent >= 80) {
          open.add(qualityItem);
        } else if (runZones != null && runZones.moderatePercent + runZones.hardPercent >= 40) {
          open.add(easyItem);
        } else {
          open.add(
            item(
              TodayPlanSport.run,
              'Noch 1 Lauf',
              '${week.qualityCode} oder Z2 – je nachdem, was fehlt',
              'Qualität: ${week.quality} · Z2: ${week.easy}',
              hard: 1,
            ),
          );
        }
      } else {
        open.add(easyItem);
      }
    }
    if (frame.flex.contains(WeekFrameBlock.zwiftInterval) && done.bike < 1 && weekday < 5) {
      open.add(item(TodayPlanSport.bike, 'Zwift-Intervall', zwiftCode, week.zwift, hard: 2));
    }
    if ((weekday == 1 || weekday == 3) &&
        open.any((entry) => entry.sport == TodayPlanSport.run && entry.hardness >= 1)) {
      hint = 'Qualitätslauf nicht am Tag nach Beine und nicht direkt vor dem Longrun.';
    }

    // Rest der Woche: alle noch kommenden Einheiten mit festem Tag.
    final legsTuesday = weekday >= 1 && gymDays.contains(today.adding(-(weekday - 1)));
    var weekendZwift = false;
    var weekendLongRun = false;
    var weekendLongRide = false;
    for (var day = weekday + 1; day < 7; day++) {
      for (final block in frame.fixed[day] ?? const <WeekFrameBlock>[]) {
        TodayPlanItem? entry;
        switch (block) {
          case WeekFrameBlock.push || WeekFrameBlock.pull || WeekFrameBlock.pp:
            entry = item(TodayPlanSport.strength, gymTitle(block), 'Home-Gym', '')..day = dayNames[day];
          case WeekFrameBlock.swimlegs when day == 1:
            entry = item(
              TodayPlanSport.swim,
              'Schwimmen oder Beine',
              '${week.swimCode} · das andere am Donnerstag',
              week.swim,
            )..day = 'Di';
          case WeekFrameBlock.swimlegs when day == 3:
            final swimLeft = done.swim < 1;
            final legsLeft = !(legsTuesday || (weekday == 1 && gymToday));
            if (weekday < 1) {
              entry = item(TodayPlanSport.strength, 'Beine oder Schwimmen', 'was am Dienstag nicht dran war', '');
            } else if (swimLeft && legsLeft) {
              entry = item(
                TodayPlanSport.swim,
                'Schwimmen oder Beine',
                '${week.swimCode} · Schwimmen hat Vorrang',
                week.swim,
              );
            } else if (swimLeft) {
              entry = item(TodayPlanSport.swim, 'Schwimmen', week.swimCode, week.swim);
            } else if (legsLeft) {
              entry = item(TodayPlanSport.strength, 'Beine', 'vor der Arbeit', '');
            }
            entry?.day = 'Do';
          case WeekFrameBlock.zwift when weekday < 5 && !weekendZwift && done.bike < 1:
            weekendZwift = true;
            entry = item(TodayPlanSport.bike, 'Zwift', zwiftCode, week.zwift)..day = 'Sa/So';
          case WeekFrameBlock.longRun when weekday < 5 && !weekendLongRun && done.run < 3:
            weekendLongRun = true;
            entry = item(TodayPlanSport.run, 'Longrun', week.longRunKilometers, week.longRun)..day = 'Sa/So';
          case WeekFrameBlock.longRide when weekday < 5 && !weekendLongRide && week.zwift2.isNotEmpty && done.bike < 2:
            weekendLongRide = true;
            entry = item(TodayPlanSport.bike, 'Lange Radeinheit', '', week.zwift2)..day = 'Sa/So';
          default:
            break;
        }
        if (entry != null) rest.add(entry);
      }
    }

    // Hinweise je Einheit
    final skipped = <TodayPlanItem>[];
    for (final entry in items) {
      entry.chip = chip(level: level, item: entry, isOpen: false, daysLeft: daysLeft);
    }
    final openWithChips = <TodayPlanItem>[];
    for (final entry in open) {
      final value = chip(level: level, item: entry, isOpen: true, daysLeft: daysLeft);
      if (value == 'skip') {
        skipped.add(entry);
        continue;
      }
      entry.chip = value;
      openWithChips.add(entry);
    }

    final fixed = items.where((entry) => entry.sport != TodayPlanSport.rest).toList();
    final allDone = fixed.isNotEmpty && fixed.every((entry) => entry.done);
    final String dayAdvice;
    if (allDone && level == RecoveryLevel.locker) {
      dayAdvice = 'Geplante Einheit erledigt – heute nichts Hartes mehr nachlegen.';
    } else if (allDone && level == RecoveryLevel.pause) {
      dayAdvice = 'Geplante Einheit erledigt – den Rest des Tages erholen.';
    } else {
      dayAdvice = advice;
    }
    return TodayPlan._(
      phase: week.phase,
      focus: week.focus,
      weekIndex: index + 1,
      weekCount: weekCount,
      daysLeft: daysLeft,
      items: items,
      open: openWithChips,
      skipped: skipped,
      rest: rest,
      hint: hint,
      advice: dayAdvice,
    );
  }

  const TodayPlan._({
    required this.phase,
    required this.focus,
    required this.weekIndex,
    required this.weekCount,
    required this.daysLeft,
    required this.items,
    required this.open,
    required this.skipped,
    required this.rest,
    required this.hint,
    required this.advice,
  });

  static const dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  final String phase;
  final String focus;
  final int weekIndex;
  final int weekCount;
  final int daysLeft;
  final List<TodayPlanItem> items;
  final List<TodayPlanItem> open;
  final List<TodayPlanItem> skipped;
  final List<TodayPlanItem> rest;
  final String hint;
  final String advice;

  /// Erledigtes der Woche von [weekOf] bis einschließlich [upTo]: Garmin-/Health-Aktivitäten (Rad nur mit Distanz)
  /// und Krafteinheiten aus Garmin und App. Liefert auch die Krafttage für `gymDays`.
  static ({TodayPlanDone done, Set<CalendarDay> strengthDays}) doneThisWeek({
    required List<GarminActivity> activities,
    required Iterable<CalendarDay> gymDays,
    required CalendarDay weekOf,
    required CalendarDay upTo,
  }) {
    final monday = weekOf.adding(-weekOf.weekdayIndex);
    final sunday = monday.adding(6);
    final last = upTo < sunday ? upTo : sunday;
    if (last < monday) return (done: const TodayPlanDone(), strengthDays: <CalendarDay>{});
    final week = activities.where((activity) {
      final day = activity.day;
      return day != null && monday <= day && day <= last;
    }).toList();
    final strengthDays = {
      ...week.where((activity) => activity.sport == ActivitySport.strength).map((activity) => activity.day).nonNulls,
      ...gymDays.where((day) => monday <= day && day <= last),
    };
    final done = TodayPlanDone(
      swim: week.where((activity) => activity.sport == ActivitySport.swim).length,
      run: week.where((activity) => activity.sport == ActivitySport.run).length,
      bike: week.where((activity) => activity.sport == ActivitySport.bike && (activity.distanceMeters ?? 0) > 0).length,
      strength: strengthDays.length,
    );
    return (done: done, strengthDays: strengthDays);
  }

  static String gymTitle(WeekFrameBlock block) => switch (block) {
    WeekFrameBlock.push => 'Push',
    WeekFrameBlock.pull => 'Pull',
    _ => 'Push + Pull',
  };

  /// Hinweis je Einheit (`_chip` im Altbestand). „skip“: Die Einheit kann diese Woche nicht mehr stattfinden.
  static String chip({
    required RecoveryLevel? level,
    required TodayPlanItem item,
    required bool isOpen,
    required int daysLeft,
  }) {
    if (level == null || level == RecoveryLevel.normal || item.done || item.sport == TodayPlanSport.rest) return '';
    if (!isOpen) {
      if (level == RecoveryLevel.pause) return 'nur locker bewegen';
      return item.sport == TodayPlanSport.strength ? '⅓ weniger Sätze' : 'locker / kürzer';
    }
    if (item.hardness == 0) return '';
    if (level == RecoveryLevel.locker && item.hardness == 1) return 'heute nur Z2';
    return daysLeft > 0 ? 'nicht heute' : 'skip';
  }
}

/// Eine Planwoche mit eingesetzten Testwerten und Wettkampf-Entscheidungen (wie `coach_plan()` im Altbestand).
final class FilledWeek {
  factory FilledWeek(PlanWeek week, {required SeasonConfig config, required CompetitionDecisions decisions}) {
    final tokens = PlanTokens(config);
    final qualityKey = SeasonSchedule.decisionKey(week, PlannedUnitKind.quality);
    final qualityChoice = week.qw != null ? decisions[qualityKey] ?? PlannedUnitDecision.open : null;
    final String quality;
    final String qualityCode;
    if (qualityChoice == PlannedUnitDecision.rejected) {
      quality = tokens.fill(week.qa ?? week.q);
      qualityCode = week.qca ?? week.qc;
    } else {
      quality = tokens.fill(week.q);
      qualityCode = qualityChoice == null ? week.qc : '🏁 ${week.qc}';
    }
    final longKey = SeasonSchedule.decisionKey(week, PlannedUnitKind.longRun);
    final longChoice = week.lw != null ? decisions[longKey] ?? PlannedUnitDecision.open : null;
    final longRun = longChoice == PlannedUnitDecision.rejected
        ? tokens.fill(week.la ?? week.l)
        : (longChoice == null ? '' : '🏁 ') + tokens.fill(week.l);
    return FilledWeek._(
      phase: week.ph,
      focus: week.f,
      zwift: tokens.fill(week.z),
      zwift2: tokens.fill(week.z2),
      swim: tokens.fill(week.s),
      swimCode: week.sc,
      quality: quality,
      qualityCode: qualityCode,
      qualityAlternative: tokens.fill(week.qa ?? ''),
      qualityDecision: qualityChoice,
      easy: tokens.fill(week.e),
      longRun: longRun,
      longRunAlternative: tokens.fill(week.la ?? ''),
      longRunDecision: longChoice,
      longRunKm: week.lr,
    );
  }

  const FilledWeek._({
    required this.phase,
    required this.focus,
    required this.zwift,
    required this.zwift2,
    required this.swim,
    required this.swimCode,
    required this.quality,
    required this.qualityCode,
    required this.qualityAlternative,
    required this.qualityDecision,
    required this.easy,
    required this.longRun,
    required this.longRunAlternative,
    required this.longRunDecision,
    required this.longRunKm,
  });

  final String phase;
  final String focus;
  final String zwift;
  final String zwift2;
  final String swim;
  final String swimCode;
  final String quality;
  final String qualityCode;
  final String qualityAlternative;
  final PlannedUnitDecision? qualityDecision;
  final String easy;
  final String longRun;
  final String longRunAlternative;
  final PlannedUnitDecision? longRunDecision;
  final double longRunKm;

  /// „Z03 Sweet Spot 2×20“ ohne „RAMP “
  String get zwiftCode {
    // Wie `split(separator: ":", maxSplits: 1).first` in Swift: leere Teile am Anfang zählen nicht.
    var text = zwift;
    while (text.startsWith(':')) {
      text = text.substring(1);
    }
    final colon = text.indexOf(':');
    return (colon < 0 ? text : text.substring(0, colon)).replaceAll('RAMP ', '');
  }

  String get easyShort => easy.split(' (').first;

  String get longRunKilometers {
    if (longRunKm <= 0) return '';
    final text = longRunKm == longRunKm.roundToDouble() ? '${longRunKm.toInt()}' : '$longRunKm'.replaceAll('.', ',');
    return '$text km';
  }
}

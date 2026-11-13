import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../util/german_format.dart';
import '../util/int_range.dart';
import '../util/rounding.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gym_plan.dart';
import 'gym_session.dart';

/// Status einer Übungsempfehlung, in Anzeigereihenfolge.
enum ProgressStatus implements Comparable<ProgressStatus> {
  increase('erhöhen'),
  restart('wiedereinstieg'),
  check('prüfen'),
  build('aufbauen'),
  baseline('basis'),
  noWeight('ohne_gewicht');

  const ProgressStatus(this.rawValue);

  final String rawValue;

  @override
  int compareTo(ProgressStatus other) => index.compareTo(other.index);
}

/// Empfehlung für eine Übung – Ergebnis von `evaluate_exercise` im Altbestand.
final class ExerciseProgress {
  ExerciseProgress({
    required this.exerciseID,
    required this.name,
    required this.group,
    required this.lastDay,
    required this.daysSince,
    required this.weightKg,
    required this.reps,
    required this.target,
    required this.sessions,
    this.nextWeightKg,
    this.increasePercent,
    this.status = ProgressStatus.baseline,
    this.headline = '',
    this.detail = '',
  });

  final String exerciseID;
  final String name;
  final MuscleGroup group;
  final CalendarDay lastDay;
  final int daysSince;
  final double weightKg;
  final List<int> reps;
  final IntRange target;
  final int sessions;
  double? nextWeightKg;
  double? increasePercent;
  ProgressStatus status;
  String headline;
  String detail;

  String get id => exerciseID;

  @override
  String toString() => 'ExerciseProgress($exerciseID, $status, $headline)';
}

/// Verlaufseintrag einer Übung an einem Tag.
final class ProgressEntry {
  ProgressEntry({required this.day, required this.weight, required this.reps, this.rirs = const []});

  final CalendarDay day;
  final double weight;
  final List<int> reps;

  /// RIR der Sätze am Höchstgewicht, soweit angegeben.
  final List<int> rirs;

  int get minReps => reps.isEmpty ? 0 : reps.reduce(math.min);
  int get maxReps => reps.isEmpty ? 0 : reps.reduce(math.max);
  int get lastReps => reps.isEmpty ? 0 : reps.last;

  @override
  bool operator ==(Object other) =>
      other is ProgressEntry &&
      other.day == day &&
      other.weight == weight &&
      other.reps.join(',') == reps.join(',') &&
      other.rirs.join(',') == rirs.join(',');

  @override
  int get hashCode => Object.hash(day, weight, reps.join(','), rirs.join(','));

  @override
  String toString() => 'ProgressEntry($day, $weight, $reps, $rirs)';
}

/// Verlauf einer Übung (alt → neu).
typedef ProgressHistory = ({String name, MuscleGroup group, List<ProgressEntry> entries});

/// Doppelprogression im Wiederholungsbereich, portiert aus `gym_progress.py`.
///
/// Zuerst die Wiederholungen bis zur Obergrenze steigern, dann das Gewicht erhöhen (2–10 %, mindestens ein
/// Gerätesprung) und wieder unten beginnen. Auslöser: alle Arbeitssätze an der Obergrenze, „2 für 2“ (ACSM 2009,
/// doi:10.1249/MSS.0b013e3181915670) oder zweimal in Folge knapp an der Obergrenze. Die Tagesampel verschiebt nur den
/// Zeitpunkt, nie das Zielgewicht.
abstract final class GymProgression {
  /// Sätze unter 80 % des schwersten Satzes gelten als Aufwärmen.
  static const warmupFraction = 0.80;
  static const minimumWorkingSets = 2;

  /// Übungen, die länger nicht gemacht wurden, fallen raus.
  static const relevantDays = 56;

  /// Ab so vielen Wiederholungen in Reserve in allen Arbeitssätzen war das Gewicht deutlich zu leicht.
  static const easyRIR = 4;

  /// Danach: Wiedereinstieg mit reduziertem Gewicht.
  static const breakDays = 21;
  static const restartFactor = 0.90;
  static const maxIncreasePercent = 10.0;
  static const weightTolerance = 0.011;

  /// Arbeitssätze: mindestens 80 % des schwersten Gewichts; ohne Gewicht alle Sätze.
  static List<LoggedSet> workingSets(List<LoggedSet> sets) {
    final valid = [
      for (final set in sets)
        if (set.done && set.reps > 0 && set.kind != SetKind.warmup)
          LoggedSet(reps: set.reps, weightKg: math.max(set.weightKg, 0), rir: set.rir),
    ];
    if (valid.isEmpty) return [];
    final top = valid.map((set) => set.weightKg).reduce(math.max);
    if (top <= 0) return valid;
    return valid.where((set) => set.weightKg >= top * warmupFraction).toList();
  }

  static ProgressEntry? summary({required CalendarDay day, required List<LoggedSet> sets}) {
    final working = workingSets(sets);
    if (working.isEmpty) return null;
    final top = working.map((set) => set.weightKg).reduce(math.max);
    final atTop = top > 0 ? working.where((set) => (set.weightKg - top).abs() <= weightTolerance).toList() : working;
    return ProgressEntry(
      day: day,
      weight: top,
      reps: [for (final set in atTop) set.reps],
      rirs: [for (final set in atTop) ?set.rir],
    );
  }

  /// Verlauf je Übung (alt → neu); mehrere Einheiten am selben Tag werden zusammengelegt.
  static Map<String, ProgressHistory> history(List<GymSession> sessions) {
    final perDay = <String, ({String name, MuscleGroup group, Map<CalendarDay, List<LoggedSet>> days})>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final item = perDay.putIfAbsent(
          exercise.exerciseID,
          () => (name: exercise.name, group: exercise.group, days: <CalendarDay, List<LoggedSet>>{}),
        );
        item.days.putIfAbsent(session.day, () => []).addAll(exercise.sets);
      }
    }
    final result = <String, ProgressHistory>{};
    for (final MapEntry(:key, :value) in perDay.entries) {
      final days = value.days.keys.toList()..sort();
      final entries = [for (final day in days) ?summary(day: day, sets: value.days[day] ?? [])];
      if (entries.isNotEmpty) result[key] = (name: value.name, group: value.group, entries: entries);
    }
    return result;
  }

  /// Wie `_round_to` im Altbestand (Python rundet halbe Werte zur geraden Zahl).
  static double roundTo(double value, double step) =>
      (roundHalfEvenDouble(value / step) * step * 100).roundToDouble() / 100;

  /// Nächstes Gewicht: ca. [percent] % mehr, mindestens ein Gerätesprung, höchstens 10 % (sofern der Sprung kleiner
  /// geht). Gibt Gewicht und tatsächliche Steigerung in Prozent zurück.
  static (double, double)? nextWeight(double weight, {required double step, required double percent}) {
    if (weight <= 0) return null;
    var increase = math.max(weight * percent / 100, step);
    increase = roundTo(increase, step);
    if (increase == 0) increase = step;
    final cap = weight * maxIncreasePercent / 100;
    if (increase > cap && cap >= step) increase = (cap / step).floorToDouble() * step;
    final next = ((weight + increase) * 100).roundToDouble() / 100;
    return (next, (increase / weight * 1000).roundToDouble() / 10);
  }

  static String _kg(double value) => GermanFormat.number(value);

  static String _repsText(List<int> reps) => reps.join('/');

  static ExerciseProgress? evaluateEntries({
    required ExerciseRule rule,
    required IntRange range,
    required List<ProgressEntry> entries,
    required CalendarDay today,
    required bool? recovered,
  }) {
    if (entries.isEmpty) return null;
    final last = entries.last;
    final previous = entries.length >= 2 ? entries[entries.length - 2] : null;
    final low = range.lower;
    final high = range.upper;
    final daysSince = last.day.daysUntil(today);
    final weight = last.weight;
    final result = ExerciseProgress(
      exerciseID: rule.id,
      name: rule.name,
      group: rule.group,
      lastDay: last.day,
      daysSince: daysSince,
      weightKg: weight,
      reps: last.reps,
      target: range,
      sessions: entries.length,
    );

    ExerciseProgress set(ProgressStatus status, String headline, String detail) => result
      ..status = status
      ..headline = headline
      ..detail = detail;

    if (high <= 1) {
      return set(ProgressStatus.noWeight, 'Haltübung', 'Keine Wiederholungsprogression – Zeit statt Gewicht steigern.');
    }
    if (weight <= 0) {
      if (last.minReps >= high) {
        return set(
          ProgressStatus.increase,
          'Zusatzgewicht beginnen',
          'Alle Sätze mit ${_repsText(last.reps)} Wdh. (Ziel $low–$high) – nächstes Mal mit kleinem Zusatzgewicht '
              'starten.',
        );
      }
      return set(
        ProgressStatus.build,
        'Wiederholungen steigern',
        '${_repsText(last.reps)} Wdh. – Ziel: alle Sätze auf $high.',
      );
    }
    if (daysSince > breakDays) {
      final restart = roundTo(weight * restartFactor, rule.step);
      result.nextWeightKg = restart;
      return set(
        ProgressStatus.restart,
        'Wiedereinstieg mit ca. ${_kg(restart)} kg',
        'Letzte Einheit vor $daysSince Tagen mit ${_kg(weight)} kg × ${_repsText(last.reps)}. Nach Pause ~10 % '
            'weniger ansetzen und in 1–2 Einheiten wieder hocharbeiten (Erfahrungswert).',
      );
    }

    final next = nextWeight(weight, step: rule.step, percent: rule.percent);
    final sameWeightPrevious = previous != null && (previous.weight - weight).abs() <= weightTolerance;
    // A: alle Arbeitssätze an der Obergrenze
    final ruleA = last.reps.length >= minimumWorkingSets && last.minReps >= high;
    // B (2 für 2): letzte Serie in zwei Einheiten in Folge ≥ Ziel + 1
    final ruleB = sameWeightPrevious && last.lastReps >= high + 1 && (previous.lastReps) >= high + 1;
    // C: zweimal in Folge knapp an der Obergrenze (jeder Satz ≥ Ziel − 1, mindestens einer am Ziel)
    final ruleC =
        sameWeightPrevious &&
        last.reps.length >= minimumWorkingSets &&
        last.minReps >= high - 1 &&
        previous.minReps >= high - 1 &&
        last.maxReps >= high;
    // D: alle Arbeitssätze mit mindestens 4 Wdh. in Reserve – Satz war deutlich zu leicht (RIR-Skala, Helms 2016)
    final minRir = last.rirs.isEmpty ? null : last.rirs.reduce(math.min);
    final ruleD =
        last.reps.length >= minimumWorkingSets &&
        last.rirs.length == last.reps.length &&
        (minRir ?? 0) >= easyRIR &&
        last.minReps >= low;
    // Warnsignal: zweimal mindestens 2 Wdh. unter der Untergrenze bei gleichem oder höherem Gewicht
    final drop =
        previous != null &&
        last.minReps <= low - 2 &&
        previous.minReps <= low - 2 &&
        last.weight >= previous.weight - weightTolerance;

    if (ruleD && !(ruleA || ruleB || ruleC) && next != null) {
      final (nextKg, percent) = next;
      result
        ..nextWeightKg = nextKg
        ..increasePercent = percent;
      final gate = recovered == false ? ' Erholung aktuell eingeschränkt: Steigerung erst bei guter Tagesform.' : '';
      return set(
        ProgressStatus.increase,
        'Erhöhen auf ${_kg(nextKg)} kg (+${_kg(percent)} %)',
        '${_kg(weight)} kg × ${_repsText(last.reps)} mit noch ${minRir ?? easyRIR}+ Wdh. in Reserve: deutlich '
            'zu leicht. Für Muskelaufbau sollten die Sätze näher am Muskelversagen enden (etwa 1–3 Wdh. in '
            'Reserve).$gate',
      );
    }
    if ((ruleA || ruleB || ruleC) && next != null) {
      final (nextKg, percent) = next;
      final String why;
      if (ruleA) {
        why = 'alle ${last.reps.length} Arbeitssätze bei ${_repsText(last.reps)} Wdh. (Ziel $low–$high)';
      } else if (ruleB) {
        why =
            'letzte Serie in zwei Einheiten in Folge mit ${previous.lastReps} bzw. ${last.lastReps} Wdh. '
            '(Ziel $high)';
      } else {
        why =
            'zwei Einheiten in Folge knapp an der Obergrenze (${_repsText(previous?.reps ?? [])} → '
            '${_repsText(last.reps)} Wdh., Ziel $high)';
      }
      final gate = recovered == false ? ' Erholung aktuell eingeschränkt: Steigerung erst bei guter Tagesform.' : '';
      var detail = '${_kg(weight)} kg: $why. Danach wieder bei $low Wdh. beginnen.$gate';
      if (percent > maxIncreasePercent) {
        detail +=
            ' Kleinster Sprung ist größer als 10 %: erst Zwischenschritt (z. B. Mikroscheiben) oder nur den ersten '
            'Satz steigern.';
      }
      result
        ..nextWeightKg = nextKg
        ..increasePercent = percent;
      return set(ProgressStatus.increase, 'Erhöhen auf ${_kg(nextKg)} kg (+${_kg(percent)} %)', detail);
    }
    if (drop) {
      return set(
        ProgressStatus.check,
        'Gewicht halten oder senken',
        'Zwei Einheiten in Folge mindestens 2 Wdh. unter dem Ziel $low–$high (${_repsText(previous.reps)} → '
            '${_repsText(last.reps)}) bei ${_kg(weight)} kg. Gewicht nicht erhöhen; bei weiterer Stagnation 5–10 % '
            'reduzieren. Erholung und Reihenfolge im Training mitprüfen.',
      );
    }
    if (entries.length == 1) {
      return set(
        ProgressStatus.baseline,
        'Ausgangswert ${_kg(weight)} kg',
        '${_repsText(last.reps)} Wdh. – eine Einheit reicht noch nicht für eine Empfehlung. Ziel: alle Sätze auf '
            '$high Wdh.',
      );
    }
    final left = math.max(0, high - last.minReps);
    result
      ..nextWeightKg = next?.$1
      ..increasePercent = next?.$2;
    return set(
      ProgressStatus.build,
      'Bei ${_kg(weight)} kg bleiben',
      '${_repsText(last.reps)} Wdh. – noch $left Wdh. bis zur Obergrenze $high im schwächsten Satz. Dann auf '
          '${_kg(next?.$1 ?? weight)} kg gehen.',
    );
  }

  /// Empfehlungen je Übung der letzten 8 Wochen, „erhöhen“ zuerst.
  /// [recovered]: `false`, wenn die Tagesampel nicht grün ist (Steigerung erst bei guter Tagesform).
  static List<ExerciseProgress> evaluate({
    required List<GymSession> sessions,
    required GymPlan plan,
    required CalendarDay today,
    bool? recovered,
  }) => evaluateRanges(sessions: sessions, ranges: plan.repRanges, today: today, recovered: recovered);

  /// Wie oben, mit Zielbereichen aus eigenen Routinen; eigene Übungen über [custom].
  static List<ExerciseProgress> evaluateRanges({
    required List<GymSession> sessions,
    required Map<String, IntRange> ranges,
    List<ExerciseInfo> custom = const [],
    required CalendarDay today,
    bool? recovered,
  }) {
    final result = <ExerciseProgress>[];
    for (final MapEntry(key: id, value: item) in history(sessions).entries) {
      final last = item.entries.last;
      if (last.day.daysUntil(today) > relevantDays) continue;
      final rule = ExerciseLibrary.rule(
        id,
        name: item.name,
        custom: custom,
      ).copyWith(id: id, name: item.name, group: item.group);
      final range = ranges[id] ?? rule.reps;
      final progress = evaluateEntries(
        rule: rule,
        range: range,
        entries: item.entries,
        today: today,
        recovered: recovered,
      );
      if (progress != null) result.add(progress);
    }
    result.sort((a, b) {
      final status = a.status.compareTo(b.status);
      return status != 0 ? status : b.lastDay.compareTo(a.lastDay);
    });
    return result;
  }
}

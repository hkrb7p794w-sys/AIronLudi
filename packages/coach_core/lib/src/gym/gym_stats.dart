import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../util/german_format.dart';
import 'gym_session.dart';

/// Ein Tag im Verlauf einer Übung.
final class GymStatsPoint {
  GymStatsPoint({
    required this.day,
    required this.topWeightKg,
    required this.oneRepMaxKg,
    required this.bestReps,
    required this.volumeKg,
    required this.sets,
  });

  final CalendarDay day;

  /// Schwerstes Gewicht des Tages.
  final double topWeightKg;

  /// Bestes geschätztes 1RM des Tages.
  final double? oneRepMaxKg;

  /// Meiste Wiederholungen in einem Satz.
  final int bestReps;
  final double volumeKg;
  final List<LoggedSet> sets;

  CalendarDay get id => day;
}

/// Bestwerte einer Übung.
final class GymRecords {
  const GymRecords({this.heaviestKg, this.bestOneRepMaxKg, this.mostReps, this.bestVolumeKg});

  final double? heaviestKg;
  final double? bestOneRepMaxKg;
  final int? mostReps;
  final double? bestVolumeKg;

  @override
  bool operator ==(Object other) =>
      other is GymRecords &&
      other.heaviestKg == heaviestKg &&
      other.bestOneRepMaxKg == bestOneRepMaxKg &&
      other.mostReps == mostReps &&
      other.bestVolumeKg == bestVolumeKg;

  @override
  int get hashCode => Object.hash(heaviestKg, bestOneRepMaxKg, mostReps, bestVolumeKg);
}

/// Beste Leistung einer früheren Einheit: der Arbeitssatz mit der höchsten Last, bei Gleichstand mit den meisten
/// Wiederholungen (bei Körpergewicht bzw. Halteübungen die meisten Wiederholungen bzw. Sekunden).
final class GymPerformance {
  const GymPerformance({required this.day, required this.weightKg, required this.reps});

  final CalendarDay day;
  final double weightKg;
  final int reps;

  CalendarDay get id => day;

  /// „80 kg × 10“, „× 12“ (Körpergewicht), „+10 kg × 8“ (Zusatz), „45 s“ (Halteübung).
  String text({bool isTime = false, bool allowsAssistance = false}) {
    final amount = isTime ? '$reps s' : '× $reps';
    if (weightKg == 0) return isTime ? amount : '$reps Wdh.';
    final weight = allowsAssistance
        ? (weightKg > 0 ? '+${GermanFormat.number(weightKg)} kg' : '${GermanFormat.number(-weightKg)} kg Hilfe')
        : '${GermanFormat.number(weightKg)} kg';
    return '$weight $amount';
  }

  @override
  bool operator ==(Object other) =>
      other is GymPerformance && other.day == day && other.weightKg == weightKg && other.reps == reps;

  @override
  int get hashCode => Object.hash(day, weightKg, reps);

  @override
  String toString() => 'GymPerformance($day, $weightKg × $reps)';
}

double? _maxOrNull(Iterable<double> values) => values.isEmpty ? null : values.reduce(math.max);

/// Kennzahlen je Übung: geschätztes 1RM, Bestwerte und Verlauf (wie die Statistik in GymBook).
abstract final class GymStats {
  /// Geschätztes Maximalgewicht für eine Wiederholung nach Epley: Gewicht × (1 + Wdh./30). Über 12 Wiederholungen
  /// wird die Schätzung ungenau und nicht ausgewiesen.
  static double? estimatedOneRepMax({required double weightKg, required int reps}) {
    if (weightKg <= 0 || reps <= 0 || reps > 12) return null;
    return reps == 1 ? weightKg : weightKg * (1 + reps / 30);
  }

  /// Verlauf einer Übung, alt → neu; mehrere Einheiten am selben Tag zusammengelegt.
  static List<GymStatsPoint> history(String exerciseID, {required List<GymSession> sessions}) {
    final byDay = <CalendarDay, List<LoggedSet>>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        if (exercise.exerciseID == exerciseID) byDay.putIfAbsent(session.day, () => []).addAll(exercise.doneSets);
      }
    }
    final days = byDay.keys.toList()..sort();
    return [
      for (final day in days)
        if (byDay[day] case final sets? when sets.isNotEmpty)
          GymStatsPoint(
            day: day,
            topWeightKg: sets.map((set) => set.weightKg).reduce(math.max),
            oneRepMaxKg: _maxOrNull(
              sets.map((set) => estimatedOneRepMax(weightKg: set.weightKg, reps: set.reps)).nonNulls,
            ),
            bestReps: sets.map((set) => set.reps).reduce(math.max),
            volumeKg: sets.fold(0, (sum, set) => sum + set.loadKg * set.reps),
            sets: sets,
          ),
    ];
  }

  /// Die letzten [limit] Einheiten einer Übung, neueste zuerst – als Orientierung unter der Eingabe.
  static List<GymPerformance> recentPerformances(
    String exerciseID, {
    required List<GymSession> sessions,
    int limit = 5,
  }) {
    final points = history(exerciseID, sessions: sessions);
    final recent = points.sublist(math.max(0, points.length - limit)).reversed;
    return [
      for (final point in recent)
        if (point.sets.isNotEmpty)
          () {
            var best = point.sets.first;
            for (final set in point.sets.skip(1)) {
              // Swift `max(by:)` behält bei Gleichstand das erste Element.
              if (best.weightKg < set.weightKg || (best.weightKg == set.weightKg && best.reps < set.reps)) best = set;
            }
            return GymPerformance(day: point.day, weightKg: best.weightKg, reps: best.reps);
          }(),
    ];
  }

  static GymRecords records(List<GymStatsPoint> points) => GymRecords(
    heaviestKg: _maxOrNull(points.map((point) => point.topWeightKg).where((value) => value > 0)),
    bestOneRepMaxKg: _maxOrNull(points.map((point) => point.oneRepMaxKg).nonNulls),
    mostReps: points.isEmpty ? null : points.map((point) => point.bestReps).reduce(math.max),
    bestVolumeKg: _maxOrNull(points.map((point) => point.volumeKg).where((value) => value > 0)),
  );

  /// Neue Bestwerte einer gerade beendeten Einheit gegenüber allen früheren Einheiten.
  static List<String> newRecords(GymSession session, {required List<GymSession> before}) {
    final result = <String>[];
    final earlier = before.where((other) => other.id != session.id && other.start.isBefore(session.start)).toList();
    for (final exercise in session.exercises) {
      final sets = exercise.doneSets;
      if (sets.isEmpty) continue;
      final old = records(history(exercise.exerciseID, sessions: earlier));
      if (old.heaviestKg == null && old.mostReps == null) continue; // erste Einheit ist kein Rekord
      final top = sets.map((set) => set.weightKg).reduce(math.max);
      final best = _maxOrNull(sets.map((set) => estimatedOneRepMax(weightKg: set.weightKg, reps: set.reps)).nonNulls);
      if (top > 0 && top > (old.heaviestKg ?? 0)) {
        result.add('${exercise.name}: neues Höchstgewicht ${GermanFormat.number(top)} kg');
      } else if (best != null && best > (old.bestOneRepMaxKg ?? 0) + 0.01) {
        result.add('${exercise.name}: bestes geschätztes 1RM ${GermanFormat.number(best.roundToDouble())} kg');
      } else if (top == 0) {
        final reps = sets.map((set) => set.reps).reduce(math.max);
        if (reps > (old.mostReps ?? 0)) result.add('${exercise.name}: $reps Wiederholungen – Bestwert');
      }
    }
    return result;
  }
}

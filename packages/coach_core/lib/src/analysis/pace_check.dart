import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../fit/fit_decoder.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import '../util/rounding.dart';

enum PaceKind implements RawEnum {
  threshold,
  vo2;

  @override
  String get rawValue => name;
}

/// Kompakte Runde (`laps_compact`): Dauer und Distanz gerundet.
final class PaceLap {
  const PaceLap({required this.duration, required this.distance, this.heartRate, this.maxHeartRate, this.isWork});

  final double duration;
  final double distance;
  final double? heartRate;
  final double? maxHeartRate;
  final bool? isWork;

  /// Aus der FIT-Datei; Runden ohne Dauer oder Distanz fallen weg.
  static List<PaceLap> from(List<FitLap> laps) => [
    for (final lap in laps)
      if ((lap.timerSeconds ?? lap.elapsedSeconds, lap.distanceMeters) case (final duration?, final distance?)
          when duration > 0 && distance > 0)
        PaceLap(
          duration: roundHalfEvenDouble(duration),
          distance: roundHalfEvenDouble(distance),
          heartRate: lap.averageHeartRate,
          maxHeartRate: lap.maxHeartRate,
          isWork: lap.intensity == null ? null : lap.isWork,
        ),
  ];

  Map<String, Object?> toJson() => {
    'duration': duration,
    'distance': distance,
    'heartRate': ?heartRate,
    'maxHeartRate': ?maxHeartRate,
    'isWork': ?isWork,
  };

  static PaceLap? fromJson(Object? json) {
    if (json is! Map) return null;
    final duration = jsonDouble(json['duration']);
    final distance = jsonDouble(json['distance']);
    if (duration == null || distance == null) return null;
    return PaceLap(
      duration: duration,
      distance: distance,
      heartRate: jsonDouble(json['heartRate']),
      maxHeartRate: jsonDouble(json['maxHeartRate']),
      isWork: json['isWork'] is bool ? json['isWork'] as bool : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaceLap &&
      other.duration == duration &&
      other.distance == distance &&
      other.heartRate == heartRate &&
      other.maxHeartRate == maxHeartRate &&
      other.isWork == isWork;

  @override
  int get hashCode => Object.hash(duration, distance, heartRate, maxHeartRate, isWork);
}

final class PaceSession {
  const PaceSession({
    required this.id,
    required this.day,
    required this.name,
    required this.kind,
    required this.rpe,
    required this.laps,
  });

  final int id;
  final CalendarDay day;
  final String? name;
  final PaceKind kind;
  final double? rpe;
  final List<PaceLap> laps;
}

final class PaceRow {
  PaceRow({required this.id, required this.day, required this.name, required this.kind, this.verdict = 'passt'});

  final int id;
  final CalendarDay day;
  final String? name;
  final PaceKind kind;
  int? workMinutes;
  int? workPace;
  int? workHeartRate;
  int? heartRatePercentOfThreshold;
  int? estimatedThreshold;
  int? repetitionPeakPercentOfMax;
  String verdict;
}

enum PaceStatus {
  fits('passt'),
  faster('schneller'),
  slower('langsamer'),
  tooFewData('zu wenig Daten');

  const PaceStatus(this.rawValue);

  final String rawValue;
}

final class PaceResult {
  PaceResult({required this.status, required this.current, required this.rows});

  PaceStatus status;
  final int current;
  final List<PaceRow> rows;
  int? suggested;
  String? reason;

  String get intervalBand => band(current);

  String? get suggestedIntervalBand => suggested == null ? null : band(suggested!);

  static String band(int threshold) =>
      '${GermanFormat.minutesSeconds(threshold - 23)}–${GermanFormat.minutesSeconds(threshold - 18)}';
}

/// Hinweis, ob die Schwellenpace (und damit die Intervallpace: Schwelle −23 bis −18 s/km) angepasst werden sollte –
/// wie im Altbestand (`pace_check.py`). Bewusst konservativ, der Feldtest bleibt der Goldstandard.
///
/// - Schwellenläufe: Aus Tempo und Ø-HF der Arbeitsrunden wird linear über die Herzfrequenzreserve das Tempo bei der
///   Schwellen-HF (LTHR) geschätzt, nur bei Ø-HF zwischen 90 und 103 % der LTHR.
/// - 4×4-Läufe: Ziel sind 90–95 % HFmax (Helgerud et al. 2007). Das ergibt nur eine Richtung.
/// - Ein Vorschlag braucht mindestens zwei Einheiten in dieselbe Richtung und ≥ 5 s/km Abweichung; höchstens 10 s/km
///   je Schritt, auf 5 s gerundet. RPE ≥ 9 bremst „schneller“ aus.
abstract final class PaceCheck {
  static const lookbackDays = 42;
  static const minSessions = 2;
  static const minDeltaSeconds = 5.0;
  static const maxStepSeconds = 10.0;

  /// Arbeitsrunden: bei strukturierten Workouts laut Uhr (ab 2 min), sonst Runden ab 150 s, die schneller sind als
  /// Schwelle + 30 s/km.
  static List<PaceLap> workLaps(List<PaceLap> laps, {required int thresholdPace}) {
    final typed = laps.where((lap) => lap.isWork == true).toList();
    if (typed.isNotEmpty) return typed.where((lap) => lap.duration >= 120).toList();
    final limit = (thresholdPace + 30).toDouble();
    return laps
        .where((lap) => lap.duration >= 150 && lap.distance > 0 && lap.duration / lap.distance * 1000 <= limit)
        .toList();
  }

  static PaceResult evaluate(
    List<PaceSession> sessions, {
    required int thresholdPace,
    required double? lthr,
    required double? maxHeartRate,
    required double restingHeartRate,
  }) {
    final rows = <PaceRow>[];
    final estimates = <double>[];
    final directions = <int>[];
    final intervalSlowEnd = (thresholdPace - 18).toDouble();
    final current = thresholdPace.toDouble();
    for (final session in sessions) {
      final row = PaceRow(id: session.id, day: session.day, name: session.name, kind: session.kind);
      final work = workLaps(session.laps, thresholdPace: thresholdPace);
      if (work.isEmpty) {
        row.verdict = 'keine Arbeitsrunden erkannt';
        rows.add(row);
        continue;
      }
      final duration = work.fold<double>(0, (sum, lap) => sum + lap.duration);
      final pace = duration / work.fold<double>(0, (sum, lap) => sum + lap.distance) * 1000;
      final withHeart = [
        for (final lap in work)
          if (lap.heartRate case final heart?) (heart, lap.duration),
      ];
      final heart = withHeart.isEmpty
          ? null
          : withHeart.fold<double>(0, (sum, entry) => sum + entry.$1 * entry.$2) /
                withHeart.fold<double>(0, (sum, entry) => sum + entry.$2);
      row
        ..workMinutes = roundHalfEven(duration / 60)
        ..workPace = roundHalfEven(pace)
        ..workHeartRate = heart == null ? null : roundHalfEven(heart);
      switch (session.kind) {
        case PaceKind.threshold:
          final ratio = heart != null && lthr != null && lthr > 0 ? heart / lthr : null;
          if (heart != null &&
              lthr != null &&
              ratio != null &&
              restingHeartRate > 0 &&
              ratio >= 0.90 &&
              ratio <= 1.03) {
            final speedAtThreshold = 1000 / pace * (lthr - restingHeartRate) / (heart - restingHeartRate);
            final estimate = 1000 / speedAtThreshold;
            row
              ..heartRatePercentOfThreshold = roundHalfEven(heart / lthr * 100)
              ..estimatedThreshold = roundHalfEven(estimate);
            final rpe = session.rpe;
            if (rpe != null && rpe >= 9 && estimate < current) {
              row.verdict = 'RPE ≥ 9 – keine Empfehlung „schneller“ aus dieser Einheit';
            } else {
              estimates.add(estimate);
              row.verdict = estimate < current - minDeltaSeconds
                  ? 'Schwelle eher schneller'
                  : estimate > current + minDeltaSeconds
                  ? 'Schwelle eher langsamer'
                  : 'passt';
            }
          } else {
            row.verdict = heart == null ? 'ohne HF' : 'HF außerhalb 90–103 % LTHR – nicht auswertbar';
          }
        case PaceKind.vo2:
          if (maxHeartRate == null || maxHeartRate <= 0) break;
          final peaks = work.map((lap) => lap.maxHeartRate).nonNulls.toList();
          final peak = peaks.isEmpty ? null : peaks.sum / peaks.length;
          row.repetitionPeakPercentOfMax = peak == null ? null : roundHalfEven(peak / maxHeartRate * 100);
          if (peak != null && peak < 0.90 * maxHeartRate && pace <= intervalSlowEnd) {
            directions.add(-1);
            row.verdict = 'Ziel-HF nicht erreicht trotz Pace im Band – Band zu langsam';
          } else if (peak != null && peak > 0.96 * maxHeartRate && pace > intervalSlowEnd + 5) {
            directions.add(1);
            row.verdict = 'HF über Ziel, Pace langsamer als Band – Band zu schnell';
          }
      }
      rows.add(row);
    }
    final result = PaceResult(
      status: PaceStatus.fits,
      current: thresholdPace,
      rows: rows.length > 10 ? rows.sublist(rows.length - 10) : rows,
    );
    if (estimates.length >= minSessions) {
      final target = median(estimates);
      final delta = target - current;
      final votes = estimates
          .where((estimate) => (estimate - current) * delta > 0 && (estimate - current).abs() >= minDeltaSeconds)
          .length;
      final vo2Agree = directions.where((direction) => direction * delta > 0).length;
      if (delta.abs() >= minDeltaSeconds && votes + vo2Agree >= minSessions) {
        final step = math.max(-maxStepSeconds, math.min(maxStepSeconds, delta));
        final suggested = 5 * roundHalfEven((current + step) / 5);
        if (suggested != thresholdPace) {
          result
            ..status = suggested < thresholdPace ? PaceStatus.faster : PaceStatus.slower
            ..suggested = suggested;
          var reason =
              '$votes Schwellenläufe der letzten ${lookbackDays ~/ 7} Wochen ergeben bei deiner Schwellen-HF '
              '${(lthr ?? 0).truncate()} bpm im Median ${GermanFormat.minutesSeconds(roundHalfEven(target))} /km';
          if (vo2Agree > 0) reason += ', $vo2Agree 4×4-Lauf/-Läufe zeigen in dieselbe Richtung';
          result.reason = '$reason.';
        }
      }
    } else if (estimates.length + directions.length < minSessions) {
      result.status = PaceStatus.tooFewData;
    } else if (directions.isNotEmpty &&
        directions.every((direction) => direction == directions.first) &&
        directions.length >= minSessions) {
      final first = directions.first;
      result
        ..suggested = thresholdPace + 5 * first
        ..status = first < 0 ? PaceStatus.faster : PaceStatus.slower
        ..reason = '${directions.length} 4×4-Läufe zeigen dieselbe Richtung (Ziel-HF 90–95 % HFmax).';
    }
    return result;
  }

  /// Vorschlagstext wie im Vorschlags-Pool des Altbestands (`suggestion`).
  static ({String title, String text})? suggestionText(PaceResult result) {
    final suggested = result.suggested;
    final reason = result.reason;
    final band = result.suggestedIntervalBand;
    if (suggested == null || reason == null || band == null) return null;
    final word = result.status == PaceStatus.faster ? 'schneller' : 'langsamer';
    return (
      title:
          'Schwellenpace auf ${GermanFormat.minutesSeconds(suggested)} /km ($word, bisher '
          '${GermanFormat.minutesSeconds(result.current)})',
      text:
          '$reason Annehmen trägt ${GermanFormat.minutesSeconds(suggested)} /km als Schwellenpace ein; die '
          'Intervallpace für 4×4 wird damit $band /km (bisher ${result.intervalBand}). Den nächsten 30-min-Test als '
          'Bestätigung nutzen.',
    );
  }

  static double median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

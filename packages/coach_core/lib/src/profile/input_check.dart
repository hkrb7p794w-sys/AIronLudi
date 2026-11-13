import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/race_predictions.dart';
import '../nutrition/nutrition_settings.dart';
import '../util/german_format.dart';
import 'user_profile.dart';

/// Schwere eines Hinweises.
enum InputSeverity implements Comparable<InputSeverity> {
  info,
  tip,
  warning;

  @override
  int compareTo(InputSeverity other) => index.compareTo(other.index);
}

/// Hinweis zu einer Eingabe (Körperdaten, Ziele): unplausibel, sehr ehrgeizig oder realistisch.
final class InputIssue {
  const InputIssue({required this.id, required this.severity, required this.message, this.evidenceIDs = const []});

  final String id;
  final InputSeverity severity;
  final String message;
  final List<String> evidenceIDs;

  @override
  String toString() => 'InputIssue($id, $severity, $message)';
}

/// Prüft Eingaben, bevor die App damit rechnet: Tippfehler bei Körperdaten, widersprüchliche Ziele und Zielzeiten
/// im Vergleich zur Wettkampfprognose der Uhr.
abstract final class InputCheck {
  /// Ab so viel schneller als die Prognose gilt ein Ziel als sehr ehrgeizig (Praxiswert).
  static const veryAmbitious = 0.90;
  static const ambitious = 0.97;

  static List<InputIssue> body(BodyProfile body) {
    final issues = <InputIssue>[];
    if (!(body.weightKilograms >= 30 && body.weightKilograms <= 250)) {
      issues.add(
        InputIssue(
          id: 'weight',
          severity: InputSeverity.warning,
          message: 'Gewicht ${GermanFormat.number(body.weightKilograms)} kg wirkt unplausibel – bitte prüfen.',
        ),
      );
    }
    if (!(body.heightCentimeters >= 120 && body.heightCentimeters <= 230)) {
      issues.add(
        InputIssue(
          id: 'height',
          severity: InputSeverity.warning,
          message: 'Größe ${GermanFormat.number(body.heightCentimeters)} cm wirkt unplausibel – bitte prüfen.',
        ),
      );
    }
    if (body.age < 14 || body.age > 100) {
      issues.add(
        InputIssue(
          id: 'age',
          severity: InputSeverity.warning,
          message: 'Alter ${body.age} wirkt unplausibel – bitte prüfen.',
        ),
      );
    }
    return issues;
  }

  static List<InputIssue> goals({
    required UserProfile profile,
    required BodyProfile body,
    required RacePredictions? predictions,
    required CalendarDay today,
  }) {
    final issues = <InputIssue>[];
    final targets = profile.targets;
    if (targets.targetWeightKilograms case final target?) {
      if (profile.goal.losesWeight && target >= body.weightKilograms) {
        issues.add(
          InputIssue(
            id: 'target-weight-direction',
            severity: InputSeverity.warning,
            message:
                'Dein Ziel ist Abnehmen, das Zielgewicht (${GermanFormat.number(target)} kg) liegt aber nicht unter '
                'deinem Gewicht (${GermanFormat.number(body.weightKilograms)} kg).',
          ),
        );
      }
      if (profile.goal.gainsWeight && target <= body.weightKilograms) {
        issues.add(
          InputIssue(
            id: 'target-weight-direction',
            severity: InputSeverity.warning,
            message:
                'Dein Ziel ist Zunehmen, das Zielgewicht (${GermanFormat.number(target)} kg) liegt aber nicht über '
                'deinem Gewicht (${GermanFormat.number(body.weightKilograms)} kg).',
          ),
        );
      }
    }
    if (targets.restingHeartRate case final pulse? when pulse < 38 || pulse > 90) {
      issues.add(
        InputIssue(
          id: 'resting-hr',
          severity: InputSeverity.tip,
          message: 'Ein Ruhepuls-Ziel von $pulse bpm ist ungewöhnlich – bitte prüfen.',
          evidenceIDs: const ['rhr.endurance'],
        ),
      );
    }
    if (profile.event case final event?) {
      final days = today.daysUntil(event.date);
      final distance = event.kind.distanceKilometers;
      final target = event.targetSeconds;
      final predicted = distance == null ? null : predictedSeconds(distance, predictions: predictions);
      if (days < 0) {
        issues.add(
          InputIssue(
            id: 'event-past',
            severity: InputSeverity.warning,
            message: '„${event.name}“ liegt in der Vergangenheit. Trage ein neues Ziel ein oder entferne es.',
          ),
        );
      } else if (target != null && predicted != null) {
        issues.add(
          compare(
            id: 'event-time',
            target: target.toDouble(),
            predicted: predicted,
            what: 'Zielzeit ${time(target.toDouble())} für ${event.kind.label}',
            weeks: days ~/ 7,
          ),
        );
      }
    }
    final distance = targets.runDistanceKilometers;
    final pace = targets.runPaceSecondsPerKilometer;
    if (distance != null && pace != null) {
      if (predictedSeconds(distance, predictions: predictions) case final predicted?) {
        issues.add(
          compare(
            id: 'run-pace',
            target: pace * distance,
            predicted: predicted,
            what: 'Zielpace ${paceText(pace.toDouble())} /km über ${GermanFormat.number(distance)} km',
            weeks: null,
          ),
        );
      }
    }
    // Stabil wie die Sortierung in Swift: gleiche Schwere behält die Reihenfolge.
    mergeSort(issues, compare: (a, b) => b.severity.compareTo(a.severity));
    return issues;
  }

  /// Vergleich mit der Prognose der Uhr; die Schwellen 3 % und 10 % sind Praxiswerte.
  static InputIssue compare({
    required String id,
    required double target,
    required double predicted,
    required String what,
    required int? weeks,
  }) {
    final ratio = target / predicted;
    final faster = ((1 - ratio) * 100).round();
    final prognosis = 'Prognose deiner Uhr: ${time(predicted)}';
    final timeLeft = weeks == null ? '' : ' Bis zum Wettkampf bleiben $weeks Wochen.';
    if (ratio < veryAmbitious) {
      return InputIssue(
        id: id,
        severity: InputSeverity.warning,
        message:
            '$what ist $faster % schneller als die $prognosis. Das ist sehr ehrgeizig – plane lieber ein '
            'Zwischenziel.$timeLeft',
      );
    }
    if (ratio < ambitious) {
      return InputIssue(
        id: id,
        severity: InputSeverity.tip,
        message: '$what ist $faster % schneller als die $prognosis: ehrgeizig, aber erreichbar.$timeLeft',
      );
    }
    return InputIssue(
      id: id,
      severity: InputSeverity.info,
      message: '$what passt zur $prognosis – realistisch.$timeLeft',
    );
  }

  /// Prognose für eine Strecke: direkt oder zwischen zwei Prognosen der Uhr interpoliert (log-log). Außerhalb der
  /// Spanne 5 km bis Marathon gibt es keine Schätzung.
  static double? predictedSeconds(double distanceKilometers, {required RacePredictions? predictions}) {
    if (predictions == null) return null;
    final points = [
      for (final (distance, seconds) in [
        (5.0, predictions.fiveK),
        (10.0, predictions.tenK),
        (21.0975, predictions.halfMarathon),
        (42.195, predictions.marathon),
      ])
        if (seconds != null) (distance, seconds),
    ];
    for (final point in points) {
      if ((point.$1 - distanceKilometers).abs() < 0.05) return point.$2;
    }
    for (var index = 0; index + 1 < points.length; index++) {
      final (lower, upper) = (points[index], points[index + 1]);
      if (lower.$1 < distanceKilometers && distanceKilometers < upper.$1) {
        final share = math.log(distanceKilometers / lower.$1) / math.log(upper.$1 / lower.$1);
        return math.exp(math.log(lower.$2) + share * (math.log(upper.$2) - math.log(lower.$2)));
      }
    }
    return null;
  }

  static String time(double seconds) {
    final total = seconds.round();
    final hours = total ~/ 3600;
    final minutes = total % 3600 ~/ 60;
    final rest = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${two(minutes)}:${two(rest)} h' : '$minutes:${two(rest)} min';
  }

  static String paceText(double seconds) {
    final total = seconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

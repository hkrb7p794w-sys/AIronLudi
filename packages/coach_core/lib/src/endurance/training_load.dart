import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import 'endurance_plan.dart';

/// Zonen je Disziplin relativ zur Schwelle. Laufen und Schwimmen als Anteil der Schwellengeschwindigkeit (Pace =
/// Schwellen-Pace / Anteil), Rad als Anteil der FTP (Coggan), Puls als Anteil der Schwellen-Herzfrequenz (Friel).
abstract final class EnduranceZones {
  static const Map<IntensityZone, (double, double)> runSpeed = {
    IntensityZone.recovery: (0.70, 0.78),
    IntensityZone.endurance: (0.78, 0.88),
    IntensityZone.tempo: (0.88, 0.95),
    IntensityZone.threshold: (0.97, 1.03),
    IntensityZone.vo2max: (1.05, 1.12),
  };

  static const Map<IntensityZone, (double, double)> swimSpeed = {
    IntensityZone.recovery: (0.80, 0.86),
    IntensityZone.endurance: (0.86, 0.92),
    IntensityZone.tempo: (0.92, 0.97),
    IntensityZone.threshold: (0.98, 1.02),
    IntensityZone.vo2max: (1.02, 1.06),
  };

  static const Map<IntensityZone, (double, double)> bikePower = {
    IntensityZone.recovery: (0.45, 0.55),
    IntensityZone.endurance: (0.56, 0.75),
    IntensityZone.tempo: (0.76, 0.90),
    IntensityZone.threshold: (0.95, 1.05),
    IntensityZone.vo2max: (1.06, 1.20),
  };

  static const Map<IntensityZone, (double, double)> heartRate = {
    IntensityZone.recovery: (0.70, 0.81),
    IntensityZone.endurance: (0.81, 0.89),
    IntensityZone.tempo: (0.90, 0.93),
    IntensityZone.threshold: (0.94, 1.00),
    IntensityZone.vo2max: (1.00, 1.06),
  };

  /// Intensitätsfaktor (Anteil der Schwellenleistung) je Zone für die Belastungsschätzung.
  static const Map<IntensityZone, double> intensityFactor = {
    IntensityZone.recovery: 0.55,
    IntensityZone.endurance: 0.68,
    IntensityZone.tempo: 0.83,
    IntensityZone.threshold: 0.98,
    IntensityZone.vo2max: 1.10,
  };

  /// Angenommene Schwimm-Pace (s/100 m) für Strecken, wenn keine CSS bekannt ist.
  static const assumedSwimCss = 125;

  /// Angenommene Schwellen-Pace Laufen (s/km), nur zur Umrechnung von Strecken ohne bekannte Schwelle.
  static const assumedRunPace = 300;

  /// Konkretes Ziel der Zone: Pace bzw. Leistung, sonst Puls, sonst offen.
  static StepTarget target(EnduranceSport sport, IntensityZone zone, AthleteThresholds thresholds) {
    switch (sport) {
      case EnduranceSport.run:
        if (thresholds.runThresholdPace case final pace?) {
          final (low, high) = runSpeed[zone]!;
          return StepTarget(TargetKind.pace, low: (pace / high).round(), high: (pace / low).round());
        }
      case EnduranceSport.swim:
        if (thresholds.swimCss case final css?) {
          final (low, high) = swimSpeed[zone]!;
          return StepTarget(TargetKind.pace, low: (css / high).round(), high: (css / low).round());
        }
        return const StepTarget.open();
      case EnduranceSport.bike:
        if (thresholds.ftpWatts case final ftp?) {
          final (low, high) = bikePower[zone]!;
          return StepTarget(TargetKind.power, low: (ftp * low).round(), high: (ftp * high).round());
        }
    }
    if (thresholds.thresholdHeartRate(sport) case final lthr?) {
      final (low, high) = heartRate[zone]!;
      return StepTarget(TargetKind.heartRate, low: (lthr * low).round(), high: (lthr * high).round());
    }
    return const StepTarget.open();
  }

  /// Mittlere Pace der Zone in Sekunden je km (Laufen) bzw. je 100 m (Schwimmen), für Umrechnungen.
  static double pace(EnduranceSport sport, IntensityZone zone, AthleteThresholds thresholds) {
    final (low, high) = (sport == EnduranceSport.swim ? swimSpeed : runSpeed)[zone]!;
    final threshold = sport == EnduranceSport.swim
        ? (thresholds.swimCss ?? assumedSwimCss)
        : (thresholds.runThresholdPace ?? assumedRunPace);
    return threshold / ((low + high) / 2);
  }

  /// Dauer eines Schritts in Sekunden (Strecken über die Zonen-Pace umgerechnet).
  static int seconds(EnduranceStep step, EnduranceSport sport, AthleteThresholds thresholds) {
    if (step.seconds case final seconds?) return seconds;
    final meters = step.meters ?? 0;
    final perUnit = pace(sport, step.zone, thresholds);
    return (sport == EnduranceSport.swim ? meters / 100 * perUnit : meters / 1000 * perUnit).round();
  }
}

/// Belastung in Training-Stress-Punkten (TSS: 100 = eine Stunde an der Schwelle) und Fitness/Ermüdung/Form nach dem
/// Impulse-Response-Modell (Banister; CTL 42 Tage, ATL 7 Tage, Form = CTL − ATL des Vortags).
abstract final class TrainingLoad {
  /// Geplante Belastung einer Einheit aus ihren Schritten.
  static double planned(List<EnduranceBlock> steps, EnduranceSport sport, AthleteThresholds thresholds) {
    double step(EnduranceStep step) {
      final hours = EnduranceZones.seconds(step, sport, thresholds) / 3600;
      final factor = EnduranceZones.intensityFactor[step.zone]!;
      return hours * factor * factor * 100;
    }

    var total = 0.0;
    for (final block in steps) {
      total += switch (block) {
        EnduranceStep() => step(block),
        EnduranceRepeat(:final count, steps: final inner) => count * inner.fold(0.0, (sum, item) => sum + step(item)),
      };
    }
    return (total * 10).round() / 10;
  }

  /// Ohne Messwerte: Belastung je Stunde nach Sportart (mittlere Intensität).
  static const fallbackPerHour = {
    ActivitySport.run: 60.0,
    ActivitySport.bike: 50.0,
    ActivitySport.swim: 50.0,
    ActivitySport.strength: 35.0,
    ActivitySport.other: 30.0,
  };

  /// Tatsächliche Belastung einer Aktivität: Rad über normalisierte Leistung und FTP, Laufen über Geschwindigkeit
  /// und Schwellen-Pace (rTSS), Schwimmen über Geschwindigkeit und CSS (sTSS, kubisch), sonst über Puls und
  /// Schwellenpuls (hrTSS), sonst eine Schätzung je Stunde.
  static double actual(GarminActivity activity, AthleteThresholds thresholds) {
    final seconds = activity.movingSeconds ?? activity.durationSeconds ?? 0;
    if (seconds <= 0) return 0;
    final hours = seconds / 3600;
    final sport = activity.sport;
    double? factor;
    var exponent = 2;
    switch (sport) {
      case ActivitySport.bike:
        final power = activity.normalizedPower ?? activity.averagePower;
        if (power != null && thresholds.ftpWatts != null && thresholds.ftpWatts! > 0) {
          factor = power / thresholds.ftpWatts!;
        }
      case ActivitySport.run:
        final speed = activity.averageSpeed ?? _speed(activity, seconds);
        if (speed != null && thresholds.runThresholdPace != null) {
          factor = speed / (1000 / thresholds.runThresholdPace!);
        }
      case ActivitySport.swim:
        final speed = activity.averageSpeed ?? _speed(activity, seconds);
        if (speed != null && thresholds.swimCss != null) {
          factor = speed / (100 / thresholds.swimCss!);
          exponent = 3;
        }
      case ActivitySport.strength || ActivitySport.other:
        break;
    }
    if (factor == null) {
      final endurance = EnduranceSport.of(sport);
      final lthr = endurance == null ? null : thresholds.thresholdHeartRate(endurance);
      if (activity.averageHeartRate case final heartRate? when lthr != null && lthr > 0) factor = heartRate / lthr;
    }
    if (factor == null) return ((fallbackPerHour[sport]! * hours) * 10).round() / 10;
    final bounded = factor.clamp(0.3, 1.5);
    return ((hours * math.pow(bounded, exponent) * 100) * 10).round() / 10;
  }

  static double? _speed(GarminActivity activity, double seconds) {
    final distance = activity.distanceMeters;
    return distance == null || distance <= 0 ? null : distance / seconds;
  }

  /// Belastung je Tag.
  static Map<CalendarDay, double> daily(List<GarminActivity> activities, AthleteThresholds thresholds) {
    final result = <CalendarDay, double>{};
    for (final activity in activities) {
      final day = activity.day;
      if (day == null) continue;
      result[day] = (result[day] ?? 0) + actual(activity, thresholds);
    }
    return result;
  }

  /// Fitness (CTL), Ermüdung (ATL) und Form (TSB) am Morgen von [day], also aus allen Tagen davor.
  static LoadState state(Map<CalendarDay, double> daily, {required CalendarDay day, int days = 90}) {
    var ctl = 0.0;
    var atl = 0.0;
    for (var offset = days; offset >= 1; offset--) {
      final load = daily[day.adding(-offset)] ?? 0;
      ctl += (load - ctl) / 42;
      atl += (load - atl) / 7;
    }
    return LoadState(fitness: ctl, fatigue: atl);
  }
}

/// Fitness, Ermüdung und Form.
final class LoadState {
  const LoadState({required this.fitness, required this.fatigue});

  final double fitness;
  final double fatigue;

  double get form => fitness - fatigue;
}

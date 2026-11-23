// Fuel Planner: die Regeln aus docs/FUEL_PLANNER_SCIENCE.md, jede Zahl genau einmal. Abschnittsnummern verweisen
// auf die Spezifikation.
import 'dart:math' as math;

import 'fuel_scenario.dart';

/// Empfohlenes Verhältnis von Glukose- zu Fruktosequellen (Spezifikation 2.4).
enum FuelRatio {
  single('Eine Quelle genügt', 'Glukose/Maltodextrin', 0),
  twoToOne('2 : 1', 'Glukose : Fruktose', 1 / 3),
  oneToPointEight('1 : 0,8', 'Glukose : Fruktose', 0.8 / 1.8);

  const FuelRatio(this.label, this.detail, this.fructoseShare);

  final String label;
  final String detail;

  /// Empfohlener Fruktose-Anteil an den Kohlenhydraten.
  final double fructoseShare;

  /// Abweichung nach unten, ab der gewarnt wird (Prozentpunkte als Anteil).
  static const tolerance = 0.08;
}

/// Koffein: Dosis vor dem Start und ggf. im letzten Drittel (Spezifikation 4.4).
final class FuelCaffeine {
  const FuelCaffeine({required this.total, required this.before, required this.late, this.lateMinute});

  final double total;

  /// 60 min vor dem Start.
  final double before;
  final double late;

  /// Beginn des letzten Drittels (nur über 150 min).
  final int? lateMinute;
}

/// Carboloading vor Wettkampf bzw. langer Schlüsseleinheit (Spezifikation 3.2).
final class FuelCarbLoading {
  const FuelCarbLoading({required this.days, required this.gramsPerKilogram, required this.gramsPerDay});

  /// 2 = 36–48 h, 1 = Vortag.
  final int days;
  final double gramsPerKilogram;
  final double gramsPerDay;
}

abstract final class FuelRules {
  // 2.1 Grundwert in g/h: Zeilen nach Dauer, Spalten locker, Tempo, Schwelle, Wettkampf.
  static const _carbTable = <(int, List<int>)>[
    (150, [60, 80, 90, 100]),
    (90, [40, 60, 75, 90]),
    (60, [0, 30, 45, 60]),
    (45, [0, 0, 15, 30]),
  ];

  static int baseCarbsPerHour({required int minutes, required FuelIntensity intensity, required bool isRace}) {
    final column = isRace ? 3 : intensity.index;
    for (final (from, values) in _carbTable) {
      if (minutes >= from) return values[column];
    }
    return 0;
  }

  /// 2.2 Zuschlag für Gut-Trained ab 150 min bei Schwelle oder Wettkampf.
  static const trainedBonus = 20;

  /// Ziel Kohlenhydrate unterwegs in g/h (2.1–2.3).
  static int carbsPerHour(FuelScenario s) {
    if (s.sport == FuelSport.strength) return strengthCarbsPerHour(s);
    var target = baseCarbsPerHour(minutes: s.minutes, intensity: s.intensity, isRace: s.isRace);
    final hard = s.isRace || s.intensity == FuelIntensity.threshold;
    if (s.minutes >= 150 && hard && s.gut == GutTolerance.trained) target += trainedBonus;
    return [target, s.gut.maxCarbsPerHour, s.sport.maxCarbsPerHour].reduce(math.min);
  }

  /// 2.3 Krafttraining (King 2022).
  static int strengthCarbsPerHour(FuelScenario s) {
    if (s.fasted && s.minutes >= 45) return 30;
    if (s.minutes >= 75 && s.intensity != FuelIntensity.easy) return 30;
    if (s.minutes >= 90) return 30;
    return 0;
  }

  /// Locker unter 90 min: Kohlenhydrate sind optional (bis 30 g/h).
  static bool carbsOptional(FuelScenario s) =>
      s.sport.isEndurance && !s.isRace && s.intensity == FuelIntensity.easy && s.minutes >= 45 && s.minutes < 90;

  /// Mundspülung reicht (45–59 min, hart).
  static bool mouthRinse(FuelScenario s) =>
      s.sport.isEndurance && s.minutes >= 45 && s.minutes < 60 && (s.isRace || s.intensity == FuelIntensity.threshold);

  /// 2.4
  static FuelRatio ratio(int carbsPerHour) => carbsPerHour > 90
      ? FuelRatio.oneToPointEight
      : carbsPerHour > 60
      ? FuelRatio.twoToOne
      : FuelRatio.single;

  /// 2.5 Gut-Training-Hinweis.
  static bool needsGutTraining(FuelScenario s, int carbsPerHour) {
    final below = switch (s.gut) {
      GutTolerance.beginner => null,
      GutTolerance.habituated => GutTolerance.beginner.maxCarbsPerHour,
      GutTolerance.trained => GutTolerance.habituated.maxCarbsPerHour,
    };
    return (below != null && carbsPerHour > below) || (s.isRace && s.minutes >= 150);
  }

  // 3.1 Pre.

  static double preMealCarbsPerKilogram(FuelScenario s) {
    final double value;
    if (s.isRace && s.minutes >= 150) {
      value = 3.0;
    } else if (s.isRace && s.minutes >= 90) {
      value = 2.5;
    } else if (s.minutes >= 90) {
      value = 2.0;
    } else if (s.minutes >= 60 || s.intensity != FuelIntensity.easy || s.isRace) {
      value = 1.5;
    } else {
      value = 1.0;
    }
    return s.gut == GutTolerance.beginner ? math.max(1.0, value - 0.5) : value;
  }

  /// Snack 1–2 h vorher (ab 90 min oder Wettkampf).
  static bool hasPreSnack(FuelScenario s) => s.sport.isEndurance && (s.minutes >= 90 || s.isRace);

  /// Schnelle Kohlenhydrate 15–30 min vorher.
  static bool hasPreBooster(FuelScenario s) {
    if (!s.sport.isEndurance) return false;
    if (s.sport == FuelSport.swim && s.minutes >= 45) return true;
    return s.minutes >= 60 && (s.isRace || s.intensity != FuelIntensity.easy);
  }

  /// 3.2
  static FuelCarbLoading? carbLoading(FuelScenario s) {
    if (!s.sport.isEndurance) return null;
    final (int days, double perKg) = switch (s) {
      _ when s.isRace && s.minutes >= 90 => (2, s.gut == GutTolerance.beginner ? 8.0 : 10.0),
      _ when s.isRace && s.minutes >= 60 => (1, 7.0),
      _ when !s.isRace && s.minutes >= 150 => (1, 7.0),
      _ => (0, 0.0),
    };
    if (days == 0) return null;
    return FuelCarbLoading(days: days, gramsPerKilogram: perKg, gramsPerDay: roundTo(perKg * s.weightKilograms, 10));
  }

  // 4.1 Schweißrate in l/h.

  static double sweatRate(FuelScenario s) {
    final measured = s.sweatRateLitersPerHour;
    if (measured != null && measured > 0) return measured;
    var rate = s.isRace ? 1.2 : s.intensity.sweatLitersPerHour;
    rate *= (s.weightKilograms / 70).clamp(0.7, 1.4);
    final t = s.temperatureCelsius;
    if (t > 20) rate += 0.03 * (t - 20);
    if (t < 15) rate -= 0.02 * (15 - t);
    if (s.humidity == FuelHumidity.humid) rate *= 1.15;
    if (s.indoor && s.sport != FuelSport.swim) rate *= 1.15;
    rate *= s.sport.sweatFactor;
    return (rate.clamp(0.2, 2.5) * 100).roundToDouble() / 100;
  }

  /// 4.2 Trinken unterwegs in ml/h.
  static int fluidPerHour(FuelScenario s, {double? sweat}) {
    if (s.minutes < 45) return 0;
    final rate = sweat ?? sweatRate(s);
    final loss = rate * s.hours;
    final allowed = 0.02 * s.weightKilograms;
    var intake = math.max(0.0, loss - allowed) / s.hours;
    if (s.minutes >= 60) intake = math.max(intake, 0.4 * rate);
    intake = math.min(intake, math.min(rate, s.gut.maxFluidPerHour / 1000));
    return roundTo(intake * 1000, 50).round();
  }

  /// 4.3 Natrium unterwegs in mg/h.
  static int sodiumPerHour(FuelScenario s, {double? sweat}) {
    final rate = sweat ?? sweatRate(s);
    final hot = s.temperatureCelsius >= 25;
    final salty = s.sodiumPerLiter != null
        ? s.sodiumPerLiter! >= SweatSaltiness.high.sodiumPerLiter
        : s.saltiness == SweatSaltiness.high;
    final double share;
    if (s.minutes < 60) {
      share = 0;
    } else if (s.minutes <= 120) {
      share = hot || salty ? 0.3 : 0;
    } else {
      share = hot ? 0.6 : 0.5;
    }
    return math.min(1500, roundTo(rate * s.sweatSodiumPerLiter * share, 50)).round();
  }

  // 4.4 Koffein.

  static const caffeineMaxPerKg = 6.0;
  static const caffeineMaxMilligrams = 400.0;

  static FuelCaffeine? caffeine(FuelScenario s) {
    if (!s.caffeine) return null;
    final perKg = s.caffeineMgPerKg.clamp(1, caffeineMaxPerKg);
    final total = roundTo(
      math.min(perKg * s.weightKilograms, math.min(caffeineMaxPerKg * s.weightKilograms, caffeineMaxMilligrams)),
      5,
    );
    if (s.minutes <= 150) return FuelCaffeine(total: total, before: total, late: 0);
    final before = roundTo(total * 2 / 3, 5);
    return FuelCaffeine(total: total, before: before, late: total - before, lateMinute: (s.minutes * 2 / 3).round());
  }

  /// Start ab 15 Uhr: Koffein kann den Schlaf stören.
  static bool caffeineHurtsSleep(FuelScenario s) => s.caffeine && (s.startMinuteOfDay ?? 0) >= 15 * 60;

  // 5 Post.

  static double proteinDose(FuelScenario s) =>
      (((s.age ?? 0) >= 60 ? 0.4 : 0.3) * s.weightKilograms).roundToDouble().clamp(20, 40).toDouble();

  /// Doppeltag: nächste Einheit in höchstens 8 h.
  static bool rapidRefuel(FuelScenario s) => s.hoursUntilNext != null && s.hoursUntilNext! <= 8;

  /// Kohlenhydrate nach der Einheit ohne Doppeltag (g/kg).
  static double postCarbsPerKilogram(FuelScenario s) =>
      s.sport.isEndurance && (s.minutes >= 90 || s.isRace || s.intensity == FuelIntensity.threshold) ? 1.0 : 0.5;

  /// Rate beim schnellen Auffüllen (g/kg/h) und Zahl der Stunden.
  static (double rate, int hours) rapidRate(FuelScenario s) {
    final next = s.hoursUntilNext ?? 24;
    if (next < 4) return (1.2, math.max(1, next));
    return (1.0, 4);
  }

  static const postFluidFactor = 1.5;
  static const postSodiumPerLiter = 700.0;

  static double roundTo(double value, double step) => (value / step).roundToDouble() * step;
}

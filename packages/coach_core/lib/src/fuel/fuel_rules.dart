// Fuel Planner: die Regeln aus docs/FUEL_PLANNER_SCIENCE.md, jede Zahl genau einmal. Abschnittsnummern verweisen
// auf die Spezifikation. Werte zwischen den Stützstellen werden linear verbunden – keine Sprünge an Grenzen.
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

  /// Abweichung nach unten, ab der gewarnt wird (eigene Festlegung, Spezifikation 9).
  static const tolerance = 0.08;
}

/// Koffein: Dosis vor dem Start und ggf. im letzten Drittel (Spezifikation 4.4).
final class FuelCaffeine {
  const FuelCaffeine({required this.total, required this.before, required this.late, this.lateMinute});

  /// Obergrenze für den ganzen Plan (vorher und unterwegs zusammen).
  final double total;

  /// 60 min vor dem Start.
  final double before;

  /// Budget unterwegs (ab [lateMinute]).
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

/// Abschnitt einer Einheit mit eigener Verpflegung (beim Triathlon Schwimmen, Rad, Laufen).
final class FuelSegment {
  const FuelSegment({
    required this.sport,
    required this.start,
    required this.end,
    required this.carbsPerHour,
    required this.fluidPerHour,
    required this.sodiumPerHour,
    this.canEat = true,
  });

  final FuelSport sport;

  /// Minuten ab Start.
  final int start;
  final int end;
  final int carbsPerHour;
  final int fluidPerHour;
  final int sodiumPerHour;

  /// Beim Schwimmen im Triathlon: keine Aufnahme möglich.
  final bool canEat;

  int get minutes => end - start;
}

abstract final class FuelRules {
  /// Linear zwischen Stützstellen; vor der ersten und nach der letzten konstant.
  static double interpolate(List<(num, double)> points, num x) {
    if (x <= points.first.$1) return points.first.$2;
    for (var index = 1; index < points.length; index++) {
      final (x1, y1) = points[index];
      if (x <= x1) {
        final (x0, y0) = points[index - 1];
        return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
      }
    }
    return points.last.$2;
  }

  // 2.1 Stützstellen in g/h je Spalte (locker, Tempo, Schwelle, Wettkampf) bei 45, 60, 90 und 150 min.
  static const _carbPoints = <List<(num, double)>>[
    [(45, 0), (60, 0), (90, 40), (150, 60)],
    [(45, 0), (60, 30), (90, 60), (150, 80)],
    [(45, 15), (60, 45), (90, 75), (150, 90)],
    [(45, 30), (60, 60), (90, 90), (150, 100)],
  ];

  /// Unter 45 min nichts (Glykogen reicht), danach gleitend.
  static int baseCarbsPerHour({required int minutes, required FuelIntensity intensity, required bool isRace}) {
    if (minutes < 45) return 0;
    return roundTo(interpolate(_carbPoints[isRace ? 3 : intensity.index], minutes), 5).round();
  }

  /// 2.2 Zuschlag für Gut-Trained bei Schwelle oder Wettkampf: von 120 bis 150 min auf +20 g/h.
  static const trainedBonus = 20;

  static int _bonus(FuelScenario s) {
    final hard = s.isRace || s.intensity == FuelIntensity.threshold;
    if (!hard || s.gut != GutTolerance.trained) return 0;
    return roundTo(interpolate([(120, 0), (150, trainedBonus.toDouble())], s.minutes), 5).round();
  }

  /// Ziel ohne die Grenze der Verträglichkeit (nur Disziplin) – für den Gut-Training-Hinweis.
  static int carbsPerHourWithoutGutLimit(FuelScenario s, {FuelSport? sport}) {
    final discipline = sport ?? s.sport;
    if (discipline == FuelSport.strength) return strengthCarbsPerHour(s);
    final target = baseCarbsPerHour(minutes: s.minutes, intensity: s.intensity, isRace: s.isRace) + _bonus(s);
    return math.min(target, discipline.maxCarbsPerHour);
  }

  /// Ziel Kohlenhydrate unterwegs in g/h (2.1–2.3). Triathlon: zeitgewichtet über Rad und Laufen.
  static int carbsPerHour(FuelScenario s) {
    if (s.sport == FuelSport.triathlon) {
      final eating = [
        for (final segment in segments(s))
          if (segment.canEat && segment.minutes > 0) segment,
      ];
      final minutes = eating.fold(0, (sum, segment) => sum + segment.minutes);
      if (minutes <= 0) return 0;
      final grams = eating.fold(0.0, (sum, segment) => sum + segment.carbsPerHour * segment.minutes);
      return roundTo(grams / minutes, 5).round();
    }
    return _carbsFor(s, s.sport);
  }

  static int _carbsFor(FuelScenario s, FuelSport sport) =>
      math.min(carbsPerHourWithoutGutLimit(s, sport: sport), s.gut.maxCarbsPerHour);

  /// 2.3 Krafttraining (King 2022): Nutzen ab 45 min nüchtern bzw. bei langen, umfangreichen Einheiten.
  static int strengthCarbsPerHour(FuelScenario s) {
    if (s.fasted && s.minutes >= 45) return 30;
    if (s.minutes >= 75 && s.intensity != FuelIntensity.easy) return 30;
    if (s.minutes >= 90) return 30;
    return 0;
  }

  /// Locker unter 90 min: Kohlenhydrate sind optional.
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

  /// 2.5 Gut-Training-Hinweis: wenn die Verträglichkeit das Ziel tatsächlich begrenzt, oder vor einem langen
  /// Wettkampf, solange der Darm noch nicht auf hohe Mengen trainiert ist.
  static bool needsGutTraining(FuelScenario s) {
    final sports = s.sport == FuelSport.triathlon ? const [FuelSport.bike, FuelSport.run] : [s.sport];
    final limited = sports.any((sport) => carbsPerHourWithoutGutLimit(s, sport: sport) > s.gut.maxCarbsPerHour);
    return limited || (s.isRace && s.minutes >= 150 && s.gut != GutTolerance.trained);
  }

  // 2.6 Triathlon: Anteile an der Gesamtzeit (Mittel aus Sprint bis Langdistanz), eigene Schätzung.
  static const triathlonSwimShare = 0.12;
  static const triathlonBikeShare = 0.52;

  /// Schwimmen, Rad, Laufen in Minuten (eigene Angaben haben Vorrang).
  static ({int swim, int bike, int run}) triathlonSplit(FuelScenario s) {
    final swim = (s.swimMinutes ?? (s.minutes * triathlonSwimShare).round()).clamp(0, s.minutes);
    final bike = (s.bikeMinutes ?? (s.minutes * triathlonBikeShare).round()).clamp(0, s.minutes - swim);
    return (swim: swim, bike: bike, run: s.minutes - swim - bike);
  }

  /// Abschnitte mit Zielwerten. Ohne Triathlon ein einziger Abschnitt.
  static List<FuelSegment> segments(FuelScenario s, {double? sweat}) {
    if (s.sport != FuelSport.triathlon) {
      final rate = sweat ?? sweatRate(s);
      return [
        FuelSegment(
          sport: s.sport,
          start: 0,
          end: s.minutes,
          carbsPerHour: _carbsFor(s, s.sport),
          fluidPerHour: fluidPerHour(s, sweat: rate),
          sodiumPerHour: sodiumPerHour(s, sweat: rate),
        ),
      ];
    }
    final split = triathlonSplit(s);
    FuelSegment part(FuelSport sport, int start, int end) {
      final derived = s.copyWith(sport: sport);
      final rate = s.sweatRateLitersPerHour ?? sweatRate(derived);
      return FuelSegment(
        sport: sport,
        start: start,
        end: end,
        carbsPerHour: _carbsFor(s, sport),
        fluidPerHour: fluidPerHour(derived, sweat: rate),
        sodiumPerHour: sodiumPerHour(derived, sweat: rate),
      );
    }

    return [
      FuelSegment(
        sport: FuelSport.swim,
        start: 0,
        end: split.swim,
        carbsPerHour: 0,
        fluidPerHour: 0,
        sodiumPerHour: 0,
        canEat: false,
      ),
      part(FuelSport.bike, split.swim, split.swim + split.bike),
      part(FuelSport.run, split.swim + split.bike, s.minutes),
    ];
  }

  // 3.1 Pre: Kohlenhydrate der Mahlzeit 3–4 h vorher in g/kg.

  static double preMealCarbsPerKilogram(FuelScenario s) {
    var value = s.isRace
        ? interpolate(const [(45, 1.5), (90, 2.5), (150, 3.0)], s.minutes)
        : interpolate(const [(45, 1.0), (60, 1.5), (90, 2.0)], s.minutes);
    if (s.intensity != FuelIntensity.easy) value = math.max(value, 1.5);
    if (s.gut == GutTolerance.beginner) value = math.max(1.0, value - 0.5);
    return (value * 10).roundToDouble() / 10;
  }

  /// Snack 1–2 h vorher (ab 90 min oder Wettkampf).
  static bool hasPreSnack(FuelScenario s) => s.sport.isEndurance && (s.minutes >= 90 || s.isRace);

  /// Schnelle Kohlenhydrate 15–30 min vorher (beim Schwimmen und Triathlon der wichtigste Zeitpunkt vor dem Wasser).
  static bool hasPreBooster(FuelScenario s) {
    if (!s.sport.isEndurance) return false;
    if ((s.sport == FuelSport.swim || s.sport == FuelSport.triathlon) && s.minutes >= 45) return true;
    return s.minutes >= 60 && (s.isRace || s.intensity != FuelIntensity.easy);
  }

  /// 3.2 Carboloading ist eine Entscheidung (laden oder nicht), daher in Stufen.
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

  // 4.1 Schweißrate in l/h – eigene Schätzung, kalibriert auf Barnes 2019 (Spezifikation 9).

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

  /// Ist die Schweißrate geschätzt (nicht gemessen)?
  static bool sweatIsEstimated(FuelScenario s) => (s.sweatRateLitersPerHour ?? 0) <= 0;

  /// 4.2 Trinken unterwegs in ml/h. Untergrenze wächst von 45 bis 75 min auf 40 % der Schweißrate.
  static int fluidPerHour(FuelScenario s, {double? sweat}) {
    if (s.minutes < 45) return 0;
    final rate = sweat ?? sweatRate(s);
    final loss = rate * s.hours;
    final allowed = 0.02 * s.weightKilograms;
    var intake = math.max(0.0, loss - allowed) / s.hours;
    intake = math.max(intake, 0.4 * rate * ((s.minutes - 45) / 30).clamp(0, 1));
    intake = math.min(intake, math.min(rate, s.gut.maxFluidPerHour / 1000));
    return roundTo(intake * 1000, 50).round();
  }

  /// 4.3 Natrium unterwegs in mg/h: Anteil des Verlusts wächst von 60 bis 150 min auf 50 %, bei ≥ 25 °C × 1,2.
  static int sodiumPerHour(FuelScenario s, {double? sweat}) {
    final rate = sweat ?? sweatRate(s);
    final hot = s.temperatureCelsius >= 25;
    final share = 0.5 * ((s.minutes - 60) / 90).clamp(0, 1) * (hot ? 1.2 : 1.0);
    return math.min(1500, roundTo(rate * s.sweatSodiumPerLiter * share, 50)).round();
  }

  /// ACSM 2007: Getränke mit 20–30 mmol/l Natrium (≈ 460–690 mg/l) und 5–10 % Kohlenhydraten.
  static const acsmDrinkSodium = (low: 460, high: 690);

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

  /// Höchstens so viel Koffein im ganzen Plan (6 mg/kg, höchstens 400 mg).
  static double caffeineCeiling(FuelScenario s) =>
      math.min(caffeineMaxPerKg * s.weightKilograms, caffeineMaxMilligrams);

  /// Start ab 15 Uhr: Koffein kann den Schlaf stören.
  static bool caffeineHurtsSleep(FuelScenario s) => s.caffeine && (s.startMinuteOfDay ?? 0) >= 15 * 60;

  // 5 Post.

  static double proteinDose(FuelScenario s) =>
      (((s.age ?? 0) >= 60 ? 0.4 : 0.3) * s.weightKilograms).roundToDouble().clamp(20, 40).toDouble();

  /// Doppeltag: nächste Einheit in höchstens 8 h.
  static bool rapidRefuel(FuelScenario s) => s.hoursUntilNext != null && s.hoursUntilNext! <= 8;

  /// Kohlenhydrate nach der Einheit ohne Doppeltag (g/kg): Ausdauer gleitend von 0,5 (60 min) auf 1,0 (90 min),
  /// hart immer 1,0; Kraft 0,5.
  static double postCarbsPerKilogram(FuelScenario s) {
    if (!s.sport.isEndurance) return 0.5;
    if (s.isRace || s.intensity == FuelIntensity.threshold) return 1.0;
    return (interpolate(const [(60, 0.5), (90, 1.0)], s.minutes) * 10).roundToDouble() / 10;
  }

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

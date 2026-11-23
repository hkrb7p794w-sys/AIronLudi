// Fuel Planner (neu in AIronLudi): jede Zahl aus docs/FUEL_PLANNER_SCIENCE.md, Abschnittsnummern wie dort.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

FuelScenario scenario({
  FuelSport sport = FuelSport.run,
  int minutes = 60,
  double weight = 70,
  FuelIntensity intensity = FuelIntensity.easy,
  bool race = false,
  GutTolerance gut = GutTolerance.habituated,
  double temperature = 20,
  FuelHumidity humidity = FuelHumidity.normal,
  bool indoor = false,
  double? sweatRate,
  SweatSaltiness saltiness = SweatSaltiness.medium,
  bool caffeine = false,
  double caffeinePerKg = 3,
  bool fasted = false,
  int? hoursUntilNext,
  int? age,
  int? start,
  int interval = 20,
}) => FuelScenario(
  sport: sport,
  minutes: minutes,
  weightKilograms: weight,
  intensity: intensity,
  isRace: race,
  gut: gut,
  temperatureCelsius: temperature,
  humidity: humidity,
  indoor: indoor,
  sweatRateLitersPerHour: sweatRate,
  saltiness: saltiness,
  caffeine: caffeine,
  caffeineMgPerKg: caffeinePerKg,
  fasted: fasted,
  hoursUntilNext: hoursUntilNext,
  age: age,
  startMinuteOfDay: start,
  intervalMinutes: interval,
);

int base(int minutes, FuelIntensity intensity, {bool race = false}) =>
    FuelRules.baseCarbsPerHour(minutes: minutes, intensity: intensity, isRace: race);

void main() {
  group('2.1 Grundwert: Stützstellen, dazwischen linear', () {
    test('Stützstellen', () {
      expect(base(44, FuelIntensity.threshold, race: true), 0);
      for (final (minutes, values) in [
        (45, [0, 0, 15, 30]),
        (60, [0, 30, 45, 60]),
        (90, [40, 60, 75, 90]),
        (150, [60, 80, 90, 100]),
        (300, [60, 80, 90, 100]),
      ]) {
        expect(
          [
            base(minutes, FuelIntensity.easy),
            base(minutes, FuelIntensity.tempo),
            base(minutes, FuelIntensity.threshold),
            base(minutes, FuelIntensity.easy, race: true),
          ],
          values,
          reason: '$minutes min',
        );
      }
    });

    test('Zwischenwerte, auf 5 g gerundet', () {
      expect(base(50, FuelIntensity.threshold), 25);
      expect(base(50, FuelIntensity.easy, race: true), 40);
      expect(base(75, FuelIntensity.easy), 20);
      expect(base(75, FuelIntensity.tempo), 45);
      expect(base(89, FuelIntensity.tempo), 60);
      expect(base(120, FuelIntensity.easy), 50);
      expect(base(120, FuelIntensity.threshold), 85);
      expect(base(120, FuelIntensity.easy, race: true), 95);
    });

    test('Keine Sprünge: eine Minute mehr ändert höchstens 5 g/h (ab 45 min)', () {
      for (final race in [false, true]) {
        for (final intensity in FuelIntensity.values) {
          for (var minutes = 45; minutes < 400; minutes++) {
            final step = (base(minutes + 1, intensity, race: race) - base(minutes, intensity, race: race)).abs();
            expect(step, lessThanOrEqualTo(5), reason: '$intensity race=$race $minutes min');
          }
        }
      }
    });

    test('Locker unter 90 min: optional; 45–59 min hart: Mundspülung', () {
      expect(FuelRules.carbsOptional(scenario(minutes: 75)), isTrue);
      expect(FuelRules.carbsOptional(scenario(minutes: 90)), isFalse);
      expect(FuelRules.mouthRinse(scenario(minutes: 50, intensity: FuelIntensity.threshold)), isTrue);
      expect(FuelRules.mouthRinse(scenario(minutes: 50)), isFalse);
    });
  });

  group('2.2 Verträglichkeit und Disziplin', () {
    test('Rad, Wettkampf 4 h: Gut-Trained 120, Gewohnt 90, Einsteiger 60', () {
      for (final (gut, expected) in [
        (GutTolerance.trained, 120),
        (GutTolerance.habituated, 90),
        (GutTolerance.beginner, 60),
      ]) {
        expect(FuelRules.carbsPerHour(scenario(sport: FuelSport.bike, minutes: 240, race: true, gut: gut)), expected);
      }
    });

    test('Laufen höchstens 90, Schwimmen 60', () {
      expect(FuelRules.carbsPerHour(scenario(minutes: 240, race: true, gut: GutTolerance.trained)), 90);
      expect(FuelRules.carbsPerHour(scenario(sport: FuelSport.swim, minutes: 100, race: true)), 60);
    });

    test('Zuschlag Gut-Trained wächst von 120 bis 150 min auf +20 g/h, nur bei Schwelle oder Wettkampf', () {
      const bike = FuelSport.bike;
      const trained = GutTolerance.trained;
      expect(
        FuelRules.carbsPerHour(scenario(sport: bike, minutes: 180, intensity: FuelIntensity.threshold, gut: trained)),
        110,
      );
      expect(
        FuelRules.carbsPerHour(scenario(sport: bike, minutes: 180, intensity: FuelIntensity.tempo, gut: trained)),
        80,
      );
      expect(FuelRules.carbsPerHour(scenario(sport: bike, minutes: 120, race: true, gut: trained)), 95);
      expect(FuelRules.carbsPerHour(scenario(sport: bike, minutes: 135, race: true, gut: trained)), 110);
    });
  });

  test('2.3 Krafttraining', () {
    const strength = FuelSport.strength;
    expect(FuelRules.carbsPerHour(scenario(sport: strength, intensity: FuelIntensity.tempo)), 0);
    expect(FuelRules.carbsPerHour(scenario(sport: strength, minutes: 50, fasted: true)), 30);
    expect(FuelRules.carbsPerHour(scenario(sport: strength, minutes: 40, fasted: true)), 0);
    expect(FuelRules.carbsPerHour(scenario(sport: strength, minutes: 80, intensity: FuelIntensity.tempo)), 30);
    expect(FuelRules.carbsPerHour(scenario(sport: strength, minutes: 80)), 0);
    expect(FuelRules.carbsPerHour(scenario(sport: strength, minutes: 95)), 30);
  });

  test('2.4 Verhältnis', () {
    expect(FuelRules.ratio(60), FuelRatio.single);
    expect(FuelRules.ratio(61), FuelRatio.twoToOne);
    expect(FuelRules.ratio(90), FuelRatio.twoToOne);
    expect(FuelRules.ratio(91), FuelRatio.oneToPointEight);
    expect(FuelRatio.oneToPointEight.fructoseShare, closeTo(0.444, 0.001));
  });

  test('2.5 Gut-Training nur, wenn die Verträglichkeit das Ziel begrenzt oder vor langem Wettkampf', () {
    // Rad: 95 g/h > 90 (Gewohnt) – der Magen begrenzt. Laufen: die Disziplin (90) begrenzt, kein Hinweis.
    expect(FuelRules.needsGutTraining(scenario(sport: FuelSport.bike, minutes: 120, race: true)), isTrue);
    expect(FuelRules.needsGutTraining(scenario(minutes: 120, race: true)), isFalse);
    expect(FuelRules.needsGutTraining(scenario(minutes: 120)), isFalse); // 50
    expect(FuelRules.needsGutTraining(scenario(minutes: 90, intensity: FuelIntensity.tempo)), isFalse);
    expect(
      FuelRules.needsGutTraining(scenario(minutes: 90, intensity: FuelIntensity.threshold, gut: GutTolerance.beginner)),
      isTrue,
    );
    const bike = FuelSport.bike;
    expect(FuelRules.needsGutTraining(scenario(sport: bike, minutes: 240, race: true)), isTrue);
    expect(
      FuelRules.needsGutTraining(scenario(sport: bike, minutes: 240, race: true, gut: GutTolerance.trained)),
      isFalse,
    );
  });

  group('2.6 Triathlon', () {
    test('Abschnitte: kein Essen im Wasser, Rad bis 120, Laufen bis 90 g/h', () {
      final s = scenario(sport: FuelSport.triathlon, minutes: 330, race: true, gut: GutTolerance.trained);
      expect(FuelRules.triathlonSplit(s), (swim: 40, bike: 172, run: 118));
      final segments = FuelRules.segments(s);
      expect(
        [for (final x in segments) (x.sport, x.carbsPerHour, x.canEat)],
        [(FuelSport.swim, 0, false), (FuelSport.bike, 120, true), (FuelSport.run, 90, true)],
      );
      // Zeitgewichtet über Rad und Laufen: (120 × 172 + 90 × 118) / 290 ≈ 108 → 110.
      expect(FuelRules.carbsPerHour(s), 110);
      final split = FuelRules.triathlonSplit(s.copyWith(swimMinutes: () => 35, bikeMinutes: () => 160));
      expect(split, (swim: 35, bike: 160, run: 135));
    });

    test('Zeitstrahl beginnt erst nach dem Schwimmen und nennt den Abschnitt', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.triathlon, minutes: 330, race: true, gut: GutTolerance.trained),
        setup: [FuelProducts.isoDrink, FuelProducts.classicGel],
      );
      expect(plan.intra.every((step) => step.minute > 40), isTrue);
      expect(plan.intra.first.timeLabel, 'Rad · Minute 60');
      expect(plan.intra.last.segment, FuelSport.run);
      expect(plan.intra.every((step) => step.minute <= 320), isTrue);
      expect(plan.pre.last.detail, 'Gel vor dem Schwimmen – im Wasser gibt es nichts.');
      expect(plan.carbCoverage, closeTo(1, 0.1));
    });
  });

  group('3 Vorher', () {
    test('3.1 Kohlenhydrate der Mahlzeit je kg, gleitend', () {
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 180, race: true)), 3.0);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 100, race: true)), 2.6);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 100)), 2.0);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 70)), 1.7);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 40, intensity: FuelIntensity.tempo)), 1.5);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 40)), 1.0);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 180, race: true, gut: GutTolerance.beginner)), 2.5);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 40, gut: GutTolerance.beginner)), 1.0);
      for (var minutes = 30; minutes < 300; minutes++) {
        final step =
            (FuelRules.preMealCarbsPerKilogram(scenario(minutes: minutes + 1, race: true)) -
                    FuelRules.preMealCarbsPerKilogram(scenario(minutes: minutes, race: true)))
                .abs();
        expect(step, lessThanOrEqualTo(0.1 + 1e-9));
      }
    });

    test('3.1 Zeitpunkte: Halbmarathon', () {
      final plan = FuelPlanner.plan(scenario(minutes: 110, race: true));
      expect([for (final step in plan.pre) step.minute], [-210, -90, -20]);
      final meal = plan.pre.first;
      expect(meal.amounts.carbs, 190); // 2,7 g/kg = 189 → 190
      expect(meal.amounts.protein, 18); // 0,25 g/kg
      expect(meal.amounts.fluid, 400); // 6 ml/kg = 420 → 400
      expect(plan.pre[1].amounts.carbs, 35);
      expect(plan.pre[1].amounts.fluid, 200); // 3 ml/kg = 210 → 200
      expect(plan.pre[2].amounts.carbs, 20);
      expect([for (final step in plan.pre) step.timeLabel], ['3–4 h vorher', '1–2 h vorher', '15–30 min vorher']);
    });

    test('3.1 Kraft und nüchtern', () {
      final strength = FuelPlanner.plan(scenario(sport: FuelSport.strength, weight: 80));
      expect(strength.pre.single.minute, -120);
      expect(strength.pre.single.amounts.carbs, 80);
      expect(strength.pre.single.amounts.protein, 24);
      expect(strength.pre.single.amounts.fluid, 400);
      final fasted = FuelPlanner.plan(scenario(minutes: 70, fasted: true, intensity: FuelIntensity.tempo));
      expect(fasted.pre.single.amounts.carbs, 0);
      expect(fasted.pre.single.amounts.fluid, 350);
    });

    test('3.1 Schwimmen und Triathlon: schnelle Kohlenhydrate auch locker', () {
      expect(FuelRules.hasPreBooster(scenario(sport: FuelSport.swim, minutes: 45)), isTrue);
      expect(FuelRules.hasPreBooster(scenario(sport: FuelSport.triathlon, minutes: 75)), isTrue);
      expect(FuelRules.hasPreBooster(scenario(minutes: 75)), isFalse);
      expect(FuelRules.hasPreBooster(scenario(minutes: 60, intensity: FuelIntensity.tempo)), isTrue);
    });

    test('3.2 Carboloading', () {
      final race = FuelRules.carbLoading(scenario(minutes: 100, race: true))!;
      expect((race.days, race.gramsPerKilogram, race.gramsPerDay), (2, 10.0, 700.0));
      final beginner = FuelRules.carbLoading(scenario(minutes: 100, race: true, gut: GutTolerance.beginner))!;
      expect((beginner.days, beginner.gramsPerKilogram, beginner.gramsPerDay), (2, 8.0, 560.0));
      expect(FuelRules.carbLoading(scenario(minutes: 70, race: true))!.gramsPerKilogram, 7.0);
      expect(FuelRules.carbLoading(scenario(minutes: 160))!.days, 1);
      expect(FuelRules.carbLoading(scenario(minutes: 120)), isNull);
      expect(FuelRules.carbLoading(scenario(sport: FuelSport.strength, minutes: 200, race: true)), isNull);
    });
  });

  group('4 Flüssigkeit, Natrium, Koffein', () {
    test('4.1 Schweißrate (Schätzung) und Messung', () {
      expect(FuelRules.sweatRate(scenario(race: true)), 1.2);
      expect(
        FuelRules.sweatRate(
          scenario(intensity: FuelIntensity.threshold, weight: 80, temperature: 30, humidity: FuelHumidity.humid),
        ),
        1.79,
      );
      expect(FuelRules.sweatRate(scenario(sport: FuelSport.bike, temperature: 10, indoor: true)), 0.52);
      expect(FuelRules.sweatRate(scenario(sport: FuelSport.swim, indoor: true)), 0.24);
      expect(FuelRules.sweatRate(scenario(sweatRate: 1.6, temperature: 35)), 1.6);
      expect(
        FuelRules.sweatRate(scenario(weight: 200, race: true, temperature: 45, humidity: FuelHumidity.humid)),
        2.5,
      );
      expect(FuelRules.sweatIsEstimated(scenario()), isTrue);
      expect(FuelRules.sweatIsEstimated(scenario(sweatRate: 1.1)), isFalse);
      expect(FuelProfile.measuredSweatRate(weightBefore: 70, weightAfter: 68.8, drankLiters: 0.5, minutes: 60), 1.7);
      expect(FuelProfile.measuredSweatRate(weightBefore: 70, weightAfter: 71, drankLiters: 0, minutes: 60), isNull);
    });

    test('4.2 Trinken: Untergrenze wächst von 45 bis 75 min, nie mehr als geschwitzt', () {
      expect(FuelRules.fluidPerHour(scenario(minutes: 180, race: true)), 750);
      expect(FuelRules.fluidPerHour(scenario(minutes: 180, race: true, gut: GutTolerance.beginner)), 750);
      expect(FuelRules.fluidPerHour(scenario(minutes: 40, race: true)), 0);
      expect(FuelRules.fluidPerHour(scenario(minutes: 90)), 250); // 40 % von 0,6 l/h
      expect(FuelRules.fluidPerHour(scenario(minutes: 50)), 50); // 40 % × 5/30 von 0,6 l/h
      expect(FuelRules.fluidPerHour(scenario(minutes: 300, sweatRate: 0.3)), 100);
      expect(FuelRules.fluidPerHour(scenario(minutes: 300, sweatRate: 2.0, gut: GutTolerance.trained)), 1000);
      for (var minutes = 45; minutes < 300; minutes++) {
        final step =
            (FuelRules.fluidPerHour(scenario(minutes: minutes + 1)) -
                    FuelRules.fluidPerHour(scenario(minutes: minutes)))
                .abs();
        expect(step, lessThanOrEqualTo(50));
      }
    });

    test('4.3 Natrium: Anteil wächst von 60 bis 150 min auf 50 %, Hitze × 1,2', () {
      expect(FuelRules.sodiumPerHour(scenario(minutes: 180, race: true)), 550);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 90, temperature: 26)), 150);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 90)), 100);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 90, saltiness: SweatSaltiness.high)), 150);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 50, temperature: 30)), 0);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 180, sweatRate: 1.0, temperature: 28)), 550);
      expect(
        FuelRules.sodiumPerHour(
          scenario(minutes: 300, sweatRate: 2.5, saltiness: SweatSaltiness.high, temperature: 30),
        ),
        1500,
      );
    });

    test('4.4 Koffein', () {
      final short = FuelRules.caffeine(scenario(minutes: 120, caffeine: true))!;
      expect((short.total, short.before, short.late, short.lateMinute), (210.0, 210.0, 0.0, null));
      final long = FuelRules.caffeine(scenario(minutes: 240, caffeine: true))!;
      expect((long.total, long.before, long.late, long.lateMinute), (210.0, 140.0, 70.0, 160));
      expect(FuelRules.caffeine(scenario(weight: 80, caffeine: true, caffeinePerKg: 6))!.total, 400);
      expect(FuelRules.caffeine(scenario()), isNull);
      expect(FuelRules.caffeineHurtsSleep(scenario(caffeine: true, start: 16 * 60)), isTrue);
      expect(FuelRules.caffeineHurtsSleep(scenario(caffeine: true, start: 9 * 60)), isFalse);
    });

    test('4.4 Koffein ohne Koffein-Produkt: vorher und als Schritt im letzten Drittel', () {
      final plan = FuelPlanner.plan(scenario(sport: FuelSport.bike, minutes: 240, race: true, caffeine: true));
      expect(plan.pre.firstWhere((step) => step.title == 'Koffein').amounts.caffeine, 140);
      final late = plan.intra.firstWhere((step) => step.amounts.caffeine > 0);
      expect(late.minute, 160);
      expect(late.amounts.caffeine, 70);
      expect(plan.all.caffeine, 210);
    });

    test('4.4 Koffein-Gels nie über das Budget (Roast: 1275 mg ⇒ jetzt unter 6 mg/kg)', () {
      final on = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 240, weight: 60, race: true, caffeine: true, caffeinePerKg: 5),
        setup: [FuelProducts.caffeineGel],
      );
      expect(on.all.caffeine, lessThanOrEqualTo(6 * 60));
      expect(on.packing.firstWhere((item) => item.product == FuelProducts.caffeineGel).count, 1);
      expect(on.packing.any((item) => item.product == FuelProducts.classicGel), isTrue);
      expect(on.intra.firstWhere((step) => step.amounts.caffeine > 0).minute, greaterThanOrEqualTo(160));
      expect(on.infos.any((note) => note.text.startsWith('Koffein-Gels nur im letzten Drittel')), isTrue);
      expect(on.warnings.any((note) => note.text.startsWith('Koffein insgesamt')), isFalse);

      final off = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 240, weight: 60, race: true),
        setup: [FuelProducts.caffeineGel],
      );
      expect(off.all.caffeine, 0);
      expect(off.infos.any((note) => note.text.startsWith('Koffein ist aus')), isTrue);
    });

    test('4.4 Koffein-Gel bis 20 % über dem Rest-Budget, zu Beginn des letzten Drittels', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 240, race: true, caffeine: true),
        setup: [FuelProducts.classicGel, FuelProducts.caffeineGel, FuelProducts.isoDrink],
      );
      final steps = plan.intra.where((step) => step.amounts.caffeine > 0).toList();
      expect(steps.single.minute, 160);
      expect(plan.all.caffeine, 215); // 140 vorher + 75 im Gel (Budget 70)
    });
  });

  group('5 Danach', () {
    test('Doppeltag: 1,0 g/kg/h für 4 h, unter 4 h 1,2 g/kg/h', () {
      final rapid = FuelPlanner.plan(scenario(minutes: 90, hoursUntilNext: 6));
      expect([for (final step in rapid.post) step.minute], [0, 60, 120, 180]);
      expect(rapid.post.every((step) => step.amounts.carbs == 70), isTrue);
      expect(rapid.post.first.amounts.protein, 21);
      expect(rapid.post[1].amounts.protein, 0);
      final quick = FuelPlanner.plan(scenario(minutes: 90, hoursUntilNext: 3));
      expect(quick.post.length, 3);
      expect(quick.post.first.amounts.carbs, 85); // 1,2 × 70 = 84 → 85
    });

    test('Normal: gleitend 0,5 → 1,0 g/kg zwischen 60 und 90 min, hart 1,0; Protein 0,3 g/kg (20–40 g)', () {
      final hard = FuelPlanner.plan(scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold));
      expect(hard.post.single.amounts.carbs, 70);
      expect(hard.post.single.amounts.protein, 21);
      expect(FuelPlanner.plan(scenario(sport: FuelSport.strength)).post.single.amounts.carbs, 35);
      expect(FuelPlanner.plan(scenario(minutes: 45)).post.single.amounts.carbs, 35);
      expect(FuelRules.postCarbsPerKilogram(scenario(minutes: 75)), 0.8);
      expect(FuelRules.proteinDose(scenario(age: 65)), 28);
      expect(FuelRules.proteinDose(scenario(weight: 50)), 20);
      expect(FuelRules.proteinDose(scenario(weight: 150)), 40);
    });

    test('Flüssigkeit: Defizit × 1,5, Natrium 700 mg/l', () {
      final plan = FuelPlanner.plan(scenario(minutes: 180, race: true));
      final deficit = 1.2 * 3 * 1000 - plan.intraDelivered.fluid;
      final post = plan.post.single.amounts;
      expect(post.fluid, FuelRules.roundTo(deficit * 1.5, 50));
      expect(post.sodium, FuelRules.roundTo(post.fluid / 1000 * 700, 50));
      expect(FuelPlanner.plan(scenario(minutes: 30)).post.single.amounts.fluid, 450); // 300 ml Defizit
      expect(FuelPlanner.plan(scenario(minutes: 15)).post.single.amounts.fluid, 0); // 150 ml: zu wenig
    });
  });

  group('6 Zeitstrahl und Produkte', () {
    test('Rad 2 h Schwelle mit Iso-Drink und Gel', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold),
        setup: [FuelProducts.isoDrink, FuelProducts.classicGel],
      );
      expect(plan.targets.carbsPerHour, 85);
      expect(plan.targets.fluidPerHour, 400);
      expect(plan.targets.sodiumPerHour, 300);
      expect([for (final step in plan.intra) step.minute], [20, 40, 60, 80, 100]);
      expect(plan.intra.first.line, 'Minute 20: 150 ml Iso-Drink 6 % (9 g KH) + 1 × Gel klassisch (2:1) (25 g KH)');
      expect(plan.intra[1].line, 'Minute 40: 100 ml Iso-Drink 6 % (6 g KH) + 1 × Gel klassisch (2:1) (25 g KH)');
      expect(plan.intraDelivered.carbs, 139);
      expect(plan.intraTarget.carbs, closeTo(141.7, 0.1));
      expect(plan.packing.firstWhere((item) => item.product == FuelProducts.classicGel).count, 4);
      final iso = plan.packing.firstWhere((item) => item.product == FuelProducts.isoDrink);
      expect(iso.milliliters, 650);
      expect(iso.line, '2 × Flasche Iso-Drink 6 % à 500 ml');
      expect(plan.warnings, isEmpty);
    });

    test('Trinken mit Saldo: Deckung nah an 100 % bei jedem Takt (Roast: 86 % bei 20 min)', () {
      for (final interval in fuelIntervals) {
        final plan = FuelPlanner.plan(
          scenario(minutes: 120, intensity: FuelIntensity.tempo, interval: interval),
          setup: [FuelProducts.classicGel],
        );
        expect((plan.intraDelivered.fluid - plan.intraTarget.fluid).abs(), lessThanOrEqualTo(25), reason: '$interval');
      }
    });

    test('Ohne Auswahl: Gel klassisch und Wasser mit Saldo', () {
      final plan = FuelPlanner.plan(scenario(minutes: 90, intensity: FuelIntensity.tempo));
      expect(plan.targets.carbsPerHour, 60);
      expect(plan.intra.first.portions.single.product, FuelProducts.classicGel);
      expect(plan.intraDelivered.carbs, 75);
      expect([for (final step in plan.intra) step.water], [100, 150, 100, 100]);
    });

    test('Zwei Getränke: Flaschen im Wechsel (Roast: das zweite wurde ignoriert)', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 180, intensity: FuelIntensity.tempo),
        setup: [FuelProducts.isoDrink, FuelProducts.highCarbDrink],
      );
      expect(
        plan.packing.map((item) => item.product),
        containsAll([FuelProducts.isoDrink, FuelProducts.highCarbDrink]),
      );
    });

    test('Kurz: keine Einnahme, Wasser nach Durst', () {
      final plan = FuelPlanner.plan(scenario(minutes: 40, race: true));
      expect(plan.intra, isEmpty);
      expect(plan.infos.map((note) => note.text), contains('Unter 45 Minuten: Wasser nach Durst genügt.'));
    });

    test('Schwimmen: Takt mindestens 20 min, am Beckenrand', () {
      final plan = FuelPlanner.plan(scenario(sport: FuelSport.swim, minutes: 90, race: true, interval: 15));
      expect(plan.intra.first.minute, 20);
      expect(plan.intra.first.detail, 'Am Beckenrand.');
    });

    test('Salztabletten über den Natrium-Saldo', () {
      final plan = FuelPlanner.plan(
        scenario(minutes: 180, race: true, saltiness: SweatSaltiness.high),
        setup: [FuelProducts.classicGel, FuelProducts.saltTablet],
      );
      expect(plan.targets.sodiumPerHour, 800); // 1,2 l/h × 1300 mg/l × 0,5 = 780 → 800
      expect(plan.packing.firstWhere((item) => item.product == FuelProducts.saltTablet).count, inInclusiveRange(7, 9));
      expect(plan.sodiumCoverage, closeTo(1, 0.15));
    });

    test('Natrium fehlt ohne salziges Produkt', () {
      final plan = FuelPlanner.plan(scenario(minutes: 180, race: true), setup: [FuelProducts.classicGel]);
      expect(plan.warnings.any((note) => note.text.startsWith('Natrium fehlt')), isTrue);
    });

    test('Zu wenig Fruktose bei hoher Menge', () {
      const glucoseGel = FuelProduct(id: 'g', name: 'Glukose-Gel', kind: FuelProductKind.gel, carbs: 30, fructose: 0);
      final hard = scenario(sport: FuelSport.bike, minutes: 240, race: true, gut: GutTolerance.trained);
      final plan = FuelPlanner.plan(hard, setup: [glucoseGel]);
      expect(plan.targets.ratio, FuelRatio.oneToPointEight);
      expect(plan.warnings.any((note) => note.text.startsWith('Zu wenig Fruktose')), isTrue);
      final fine = FuelPlanner.plan(hard, setup: [FuelProducts.highCarbDrink, FuelProducts.highCarbGel]);
      expect(fine.notes.any((note) => note.text.startsWith('Zu wenig Fruktose')), isFalse);
      expect(fine.carbCoverage, closeTo(1, 0.15));
    });

    test('Getränk mit vielen Kohlenhydraten: nur so viel, wie die Kohlenhydrate erlauben', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold),
        setup: [FuelProducts.highCarbDrink],
      );
      expect(plan.intra.first.portions.single.milliliters, 150);
      expect(plan.intra.first.water, 0);
    });

    test('Eigene Mischung: Werte aus Zutaten, Packliste mit Pulver, Hinweis über 10 %', () {
      const mix = FuelMix(maltodextrin: 60, fructose: 40, salt: 1, waterMilliliters: 500);
      expect(mix.carbs, 97);
      expect(mix.fructoseGrams, 40);
      expect(mix.sodium, 393);
      expect(mix.powderGrams, 101);
      expect(mix.concentration, closeTo(19.4, 0.01));
      expect(const FuelMix(sucrose: 20, dextrose: 10, waterMilliliters: 500).fructoseGrams, 10);
      expect(const FuelMix(sucrose: 20, dextrose: 10, waterMilliliters: 500).carbs, closeTo(29.1, 0.001));
      final product = FuelProduct.fromMix(id: 'mix', name: 'Meine Flasche', mix: mix);
      expect(product.isDrink, isTrue);
      expect(product.carbs, 97);
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 240, race: true, gut: GutTolerance.trained),
        setup: [product],
      );
      final pack = plan.packing.single;
      expect(pack.powderGrams, pack.count * 101);
      expect(plan.warnings.any((note) => note.text.startsWith('Meine Flasche: 19,4 %')), isTrue);
    });

    test('Gelöschtes Produkt wird gemeldet', () {
      final plan = FuelPlanner.plan(scenario(minutes: 120), missingProducts: 1);
      expect(plan.warnings.first.text, 'Ein gewähltes Produkt gibt es nicht mehr – im Szenario neu wählen.');
    });

    test('Kraft ohne Bedarf: nur Wasser, keine leeren Zeilen', () {
      final plan = FuelPlanner.plan(scenario(sport: FuelSport.strength));
      expect(plan.targets.carbsPerHour, 0);
      expect(plan.intra, isNotEmpty);
      expect(plan.intra.every((step) => step.portions.isEmpty && step.water > 0), isTrue);
      expect(plan.infos.map((note) => note.text), contains('Krafttraining: Mahlzeit davor und danach genügen.'));
    });

    test('Wenige Hinweise (Roast: sechs Karten beim Halbmarathon)', () {
      final plan = FuelPlanner.plan(
        scenario(minutes: 110, race: true, temperature: 26),
        setup: [FuelProducts.classicGel, FuelProducts.saltTablet],
      );
      expect(plan.notes.length, lessThanOrEqualTo(3));
      expect(plan.notes.any((note) => note.text.contains('Hyponatriämie')), isFalse);
      expect(plan.targets.maxFluidPerHour, 1380);
      expect(plan.targets.sodiumPerLiterDrink, isNotNull);
    });
  });

  group('7 Ernährungstagebuch', () {
    test('Unterwegs mit echten Produkten, vorher und danach als Platzhalter plus Wasser', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold),
        setup: [FuelProducts.isoDrink, FuelProducts.classicGel],
      );
      final entries = FuelDiary.entries(plan);
      expect([for (final entry in entries) entry.phase], FuelPhase.values);
      final intra = entries[1];
      expect(intra.title, 'Verpflegung unterwegs');
      final gel = intra.items.firstWhere((item) => item.name == FuelProducts.classicGel.name);
      expect(gel.grams, 160);
      expect(gel.portionCount, 4);
      final iso = intra.items.firstWhere((item) => item.name == FuelProducts.isoDrink.name);
      expect(iso.isDrink, isTrue);
      expect(iso.grams, 650);
      expect(intra.totals[Nutrient.carbs], closeTo(plan.intraDelivered.carbs, 0.01));
      expect(Hydration.total(intra.items).drinks, plan.intraDelivered.fluid);
      final pre = entries.first;
      expect(pre.minute, -210);
      expect(pre.items.first.name, 'Vor dem Training (Plan)');
      expect(pre.totals[Nutrient.carbs], plan.total(FuelPhase.pre).carbs);
      expect(pre.totals[Nutrient.kcal], plan.total(FuelPhase.pre).kilocalories.roundToDouble());
      expect(Hydration.total(pre.items).drinks, plan.total(FuelPhase.pre).fluid);
      expect(entries.last.minute, 120);
      expect(FuelDiary.entries(plan, phases: {FuelPhase.post}).single.phase, FuelPhase.post);
    });

    test('Markierung im Hinweis und Platzhalter-Erkennung', () {
      final hint = FuelDiary.hint('PLAN-1', FuelPhase.pre);
      expect(FuelDiary.marker(hint), (planID: 'PLAN-1', phase: FuelPhase.pre));
      expect(FuelDiary.marker(FuelDiary.hint('PLAN-1', FuelPhase.intra))?.phase, FuelPhase.intra);
      expect(FuelDiary.marker('Frühstück mit Ei'), isNull);
      expect(FuelDiary.visibleHint(FuelDiary.hint('P', FuelPhase.intra)), 'Aus dem Fuel Planner.');
      final placeholder = MealItem(
        name: 'Vor dem Training (Plan)',
        grams: 100,
        source: MealItemSource.manual,
        per100g: NutrientValues({Nutrient.kcal: 800}),
      );
      final bread = MealItem(
        name: 'Brot',
        grams: 100,
        source: MealItemSource.manual,
        per100g: NutrientValues({Nutrient.kcal: 250}),
      );
      expect(FuelDiary.isPlaceholder(hint: hint, items: [placeholder]), isTrue);
      // Schon durch echte Lebensmittel ersetzt (im Editor bearbeitet): kein Platzhalter mehr.
      expect(FuelDiary.isPlaceholder(hint: hint, items: [bread]), isFalse);
      expect(FuelDiary.isPlaceholder(hint: FuelDiary.hint('P', FuelPhase.intra), items: [placeholder]), isFalse);
    });

    test('Echte Mahlzeit ersetzt Platzhalter: ±90 min und mindestens 100 kcal bzw. 30 %', () {
      final at = DateTime(2026, 12, 6, 6, 30);
      bool replaces(Duration offset, double kcal, {bool water = false}) => FuelDiary.replaces(
        placeholderAt: at,
        placeholderKilocalories: 800,
        mealAt: at.add(offset),
        mealKilocalories: kcal,
        mealIsWaterOnly: water,
      );
      expect(replaces(const Duration(minutes: 20), 500), isTrue);
      expect(replaces(const Duration(minutes: -90), 500), isTrue);
      expect(replaces(const Duration(minutes: 91), 500), isFalse);
      expect(replaces(const Duration(minutes: 10), 200), isFalse); // Kaffee mit Keks: unter 30 %
      expect(replaces(const Duration(minutes: 10), 0, water: true), isFalse);
    });
  });

  group('8 Speicher je Benutzer', () {
    test('Szenario, Produkt und Bibliothek als JSON', () {
      final original =
          scenario(
            sport: FuelSport.triathlon,
            minutes: 150,
            race: true,
            caffeine: true,
            hoursUntilNext: 6,
            sweatRate: 1.3,
            start: 540,
          ).copyWith(
            title: 'Olympisch',
            day: () => const CalendarDay(2026, 12, 6),
            slotID: () => 'slot-1',
            swimMinutes: () => 25,
            bikeMinutes: () => 70,
          );
      final restored = FuelScenario.fromJson(jsonDecode(jsonEncode(original.toJson())))!;
      expect(jsonEncode(restored.toJson()), jsonEncode(original.toJson()));

      final library = FuelLibrary(username: 'anna')
        ..saveProduct(
          FuelProduct.fromMix(
            id: 'mix',
            name: 'Flasche',
            mix: const FuelMix(maltodextrin: 50, fructose: 30, waterMilliliters: 600),
          ),
        )
        ..saveProduct(FuelProducts.classicGel)
        ..profile = const FuelProfile(gut: GutTolerance.trained, setup: ['mix', 'builtin.gel'])
        ..savePlan(
          SavedFuelPlan(
            id: 'p',
            scenario: original,
            productIDs: ['mix'],
            savedAt: DateTime.utc(2026, 11),
            loggedAt: DateTime.utc(2026, 11, 2),
            loggedMealIDs: ['m1', 'm2'],
          ),
        );
      expect(library.products.length, 1); // Mitgelieferte werden nicht gespeichert.
      final json = jsonDecode(jsonEncode(library.toJson()));
      final back = FuelLibrary.fromJson(json, username: 'anna')!;
      expect(back.products.single.mix!.maltodextrin, 50);
      expect(back.products.single.carbs, 77.5);
      expect(back.profile.gut, GutTolerance.trained);
      expect(back.resolve(back.profile.setup).map((p) => p.id), ['mix', 'builtin.gel']);
      expect(back.planForSlot('slot-1')?.loggedMealIDs, ['m1', 'm2']);
      expect(back.planForSlot('slot-1')!.unlogged().loggedAt, isNull);
      expect(FuelLibrary.fromJson(json, username: 'ben'), isNull);
      back.deleteProduct('mix');
      expect(back.profile.setup, ['builtin.gel']);
    });

    test('Mitgelieferte IDs werden aus fremden Daten nicht übernommen', () {
      expect(FuelProduct.fromJson(FuelProducts.classicGel.toJson()), isNull);
    });
  });

  group('1 Aus Ausdauer- und Wochenplan', () {
    const workout = EnduranceWorkout(
      sport: EnduranceSport.run,
      type: EnduranceWorkoutType.race,
      title: 'Halbmarathon',
      minutes: 110,
      steps: [],
      load: 120,
    );

    test('Werte der Einheit übernommen', () {
      final s = FuelScenario.fromWorkout(
        workout,
        weightKilograms: 64,
        profile: const FuelProfile(gut: GutTolerance.trained, intervalMinutes: 15),
        slotID: 'x',
      );
      expect(
        (s.sport, s.isRace, s.intensity, s.minutes, s.gut, s.intervalMinutes, s.slotID),
        (FuelSport.run, true, FuelIntensity.threshold, 110, GutTolerance.trained, 15, 'x'),
      );
      expect(FuelIntensity.of(EnduranceWorkoutType.long), FuelIntensity.easy);
      expect(FuelIntensity.of(EnduranceWorkoutType.tempo), FuelIntensity.tempo);
      expect(FuelIntensity.of(EnduranceWorkoutType.vo2max), FuelIntensity.threshold);
    });

    test('Geänderte Einheit wird erkannt und übernommen, eigene Einstellungen bleiben', () {
      const day = CalendarDay(2026, 12, 6);
      final saved = FuelScenario.fromWorkout(
        workout,
        weightKilograms: 64,
        day: day,
      ).copyWith(temperatureCelsius: 27, gut: GutTolerance.trained, title: 'Mein HM');
      expect(saved.matchesWorkout(workout, day: day), isTrue);
      const shorter = EnduranceWorkout(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.tempo,
        title: 'Tempo',
        minutes: 60,
        steps: [],
        load: 70,
      );
      expect(saved.matchesWorkout(shorter, day: day), isFalse);
      expect(saved.matchesWorkout(workout, day: day.adding(1)), isFalse);
      final updated = saved.updatedFromWorkout(shorter, day: day.adding(1));
      expect(
        (updated.minutes, updated.intensity, updated.isRace, updated.day),
        (60, FuelIntensity.tempo, false, day.adding(1)),
      );
      expect((updated.temperatureCelsius, updated.gut, updated.title), (27.0, GutTolerance.trained, 'Mein HM'));
      expect(updated.matchesWorkout(shorter, day: day.adding(1)), isTrue);
    });

    test('Wochenplan: Kraft mit Standarddauer, „Anderes“ ohne Plan', () {
      final strength = FuelScenario.fromSession(
        const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
        weightKilograms: 80,
      )!;
      expect((strength.sport, strength.minutes, strength.intensity), (FuelSport.strength, 45, FuelIntensity.threshold));
      final long = FuelScenario.fromSession(
        const SessionSlot(TrainingSport.bike, SessionIntensity.long),
        weightKilograms: 80,
        minutes: 180,
      )!;
      expect((long.sport, long.minutes, long.intensity), (FuelSport.bike, 180, FuelIntensity.easy));
      expect(FuelScenario.fromSession(const SessionSlot(TrainingSport.other), weightKilograms: 80), isNull);
    });
  });

  group('Wetter aus der Vorhersage', () {
    List<WeatherHour> hours(double Function(int hour) temperature, int Function(int hour) humidity) => [
      for (var hour = 0; hour < 24; hour++)
        WeatherHour(
          time: DateTime(2026, 7, 12, hour),
          temperature: temperature(hour),
          windSpeed: 10,
          windFrom: 270,
          humidity: humidity(hour),
        ),
    ];

    test('Mittel über die Stunden der Einheit, Luftfeuchte als Stufe', () {
      final summer = hours((hour) => 10.0 + hour, (_) => 75);
      final weather = FuelWeather.of(summer, startMinuteOfDay: 9 * 60, minutes: 180)!;
      expect(weather.temperature, 20); // 19, 20, 21 °C
      expect(weather.humidity, FuelHumidity.humid);
      expect(
        FuelWeather.of(hours((_) => 15, (_) => 85), startMinuteOfDay: 540, minutes: 60)!.humidity,
        FuelHumidity.normal,
      ); // kühl: nicht schwül
      expect(
        FuelWeather.of(hours((_) => 30, (_) => 30), startMinuteOfDay: 540, minutes: 60)!.humidity,
        FuelHumidity.dry,
      );
      final applied = FuelWeather.apply(scenario(minutes: 120, start: 14 * 60), summer);
      expect((applied.temperatureCelsius, applied.humidity), (25.0, FuelHumidity.humid));
      expect(FuelWeather.apply(scenario(), const []).temperatureCelsius, 20);
    });

    test('Open-Meteo liefert die Luftfeuchte mit', () {
      expect(
        OpenMeteoFormat.uri(const GeoPoint(52.5, 13.4), const CalendarDay(2026, 7, 12)).toString(),
        contains('relative_humidity_2m'),
      );
      final parsed = OpenMeteoFormat.parse({
        'hourly': {
          'time': ['2026-07-12T09:00'],
          'temperature_2m': [21.5],
          'wind_speed_10m': [12],
          'wind_direction_10m': [250],
          'relative_humidity_2m': [64],
        },
      });
      expect(parsed.single.humidity, 64);
    });
  });
}

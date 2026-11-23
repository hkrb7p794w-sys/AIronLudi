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

void main() {
  group('2.1 Grundwert nach Dauer und Intensität', () {
    int base(int minutes, FuelIntensity intensity, {bool race = false}) =>
        FuelRules.baseCarbsPerHour(minutes: minutes, intensity: intensity, isRace: race);

    test('Tabelle', () {
      expect(base(30, FuelIntensity.threshold, race: true), 0);
      expect(base(50, FuelIntensity.easy), 0);
      expect(base(50, FuelIntensity.tempo), 0);
      expect(base(50, FuelIntensity.threshold), 15);
      expect(base(50, FuelIntensity.easy, race: true), 30);
      expect(base(75, FuelIntensity.easy), 0);
      expect(base(75, FuelIntensity.tempo), 30);
      expect(base(75, FuelIntensity.threshold), 45);
      expect(base(75, FuelIntensity.easy, race: true), 60);
      expect(base(120, FuelIntensity.easy), 40);
      expect(base(120, FuelIntensity.tempo), 60);
      expect(base(120, FuelIntensity.threshold), 75);
      expect(base(120, FuelIntensity.easy, race: true), 90);
      expect(base(200, FuelIntensity.easy), 60);
      expect(base(200, FuelIntensity.tempo), 80);
      expect(base(200, FuelIntensity.threshold), 90);
      expect(base(200, FuelIntensity.easy, race: true), 100);
    });

    test('Grenzen der Stufen', () {
      expect(base(44, FuelIntensity.easy, race: true), 0);
      expect(base(45, FuelIntensity.easy, race: true), 30);
      expect(base(89, FuelIntensity.tempo), 30);
      expect(base(90, FuelIntensity.tempo), 60);
      expect(base(149, FuelIntensity.easy, race: true), 90);
      expect(base(150, FuelIntensity.easy, race: true), 100);
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

    test('Laufen höchstens 90, Triathlon 100, Schwimmen 60', () {
      final trained = GutTolerance.trained;
      expect(FuelRules.carbsPerHour(scenario(minutes: 240, race: true, gut: trained)), 90);
      expect(FuelRules.carbsPerHour(scenario(sport: FuelSport.triathlon, minutes: 330, race: true, gut: trained)), 100);
      expect(FuelRules.carbsPerHour(scenario(sport: FuelSport.swim, minutes: 100, race: true)), 60);
    });

    test('Zuschlag nur ab 150 min bei Schwelle oder Wettkampf', () {
      final bike = FuelSport.bike;
      const trained = GutTolerance.trained;
      expect(
        FuelRules.carbsPerHour(scenario(sport: bike, minutes: 180, intensity: FuelIntensity.threshold, gut: trained)),
        110,
      );
      expect(
        FuelRules.carbsPerHour(scenario(sport: bike, minutes: 180, intensity: FuelIntensity.tempo, gut: trained)),
        80,
      );
      expect(FuelRules.carbsPerHour(scenario(sport: bike, minutes: 120, race: true, gut: trained)), 90);
    });
  });

  test('2.3 Krafttraining', () {
    final strength = FuelSport.strength;
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

  test('2.5 Gut-Training-Hinweis', () {
    expect(FuelRules.needsGutTraining(scenario(), 75), isTrue);
    expect(FuelRules.needsGutTraining(scenario(), 60), isFalse);
    expect(FuelRules.needsGutTraining(scenario(gut: GutTolerance.trained), 90), isFalse);
    expect(FuelRules.needsGutTraining(scenario(gut: GutTolerance.trained), 100), isTrue);
    expect(FuelRules.needsGutTraining(scenario(gut: GutTolerance.beginner, minutes: 150, race: true), 60), isTrue);
  });

  group('3 Vorher', () {
    test('3.1 Kohlenhydrate der Mahlzeit je kg', () {
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 180, race: true)), 3.0);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 100, race: true)), 2.5);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 100)), 2.0);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 70)), 1.5);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 40, intensity: FuelIntensity.tempo)), 1.5);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 40)), 1.0);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 180, race: true, gut: GutTolerance.beginner)), 2.5);
      expect(FuelRules.preMealCarbsPerKilogram(scenario(minutes: 40, gut: GutTolerance.beginner)), 1.0);
    });

    test('3.1 Zeitpunkte: Halbmarathon', () {
      final plan = FuelPlanner.plan(scenario(minutes: 110, race: true));
      expect([for (final step in plan.pre) step.minute], [-210, -90, -20]);
      final meal = plan.pre.first;
      expect(meal.amounts.carbs, 175); // 2,5 g/kg
      expect(meal.amounts.protein, 18); // 0,25 g/kg
      expect(meal.amounts.fluid, 400); // 6 ml/kg = 420 → 400
      expect(plan.pre[1].amounts.carbs, 35);
      expect(plan.pre[1].amounts.fluid, 200); // 3 ml/kg = 210 → 200
      expect(plan.pre[2].amounts.carbs, 20);
      expect(plan.pre.first.timeLabel, '3–4 h vorher');
      expect(plan.pre[1].timeLabel, '1–2 h vorher');
      expect(plan.pre[2].timeLabel, '15–30 min vorher');
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

    test('3.1 Schwimmen: schnelle Kohlenhydrate auch locker', () {
      expect(FuelRules.hasPreBooster(scenario(sport: FuelSport.swim, minutes: 45)), isTrue);
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
    test('4.1 Schweißrate', () {
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
    });

    test('4.1 Schweißrate aus Wiegen', () {
      expect(FuelProfile.measuredSweatRate(weightBefore: 70, weightAfter: 68.8, drankLiters: 0.5, minutes: 60), 1.7);
      expect(FuelProfile.measuredSweatRate(weightBefore: 70, weightAfter: 71, drankLiters: 0, minutes: 60), isNull);
    });

    test('4.2 Trinken', () {
      expect(FuelRules.fluidPerHour(scenario(minutes: 180, race: true)), 750);
      expect(FuelRules.fluidPerHour(scenario(minutes: 180, race: true, gut: GutTolerance.beginner)), 750);
      expect(FuelRules.fluidPerHour(scenario(minutes: 40, race: true)), 0);
      expect(FuelRules.fluidPerHour(scenario(minutes: 90)), 250); // Untergrenze 40 % von 0,6 l/h
      expect(FuelRules.fluidPerHour(scenario(minutes: 50)), 0); // unter 60 min keine Untergrenze, kein Defizit
      // Wenig Schweiß: kaum Defizit, Untergrenze 40 % von 0,3 l/h = 120 → 100 ml/h.
      expect(FuelRules.fluidPerHour(scenario(minutes: 300, sweatRate: 0.3)), 100);
      expect(FuelRules.fluidPerHour(scenario(minutes: 300, sweatRate: 2.0, gut: GutTolerance.trained)), 1000);
    });

    test('4.3 Natrium', () {
      expect(FuelRules.sodiumPerHour(scenario(minutes: 180, race: true)), 550);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 90, temperature: 26)), 200);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 90)), 0);
      expect(FuelRules.sodiumPerHour(scenario(minutes: 90, saltiness: SweatSaltiness.high)), 250);
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

    test('4.4 Koffein im Plan: vorher und im letzten Drittel', () {
      final plan = FuelPlanner.plan(scenario(sport: FuelSport.bike, minutes: 240, race: true, caffeine: true));
      expect(plan.pre.firstWhere((step) => step.title == 'Koffein').amounts.caffeine, 140);
      final late = plan.intra.firstWhere((step) => step.amounts.caffeine > 0);
      expect(late.minute, 160);
      expect(late.amounts.caffeine, 70);
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

    test('Normal: 1,0 bzw. 0,5 g/kg und Protein 0,3 g/kg (20–40 g)', () {
      final hard = FuelPlanner.plan(scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold));
      expect(hard.post.single.amounts.carbs, 70);
      expect(hard.post.single.amounts.protein, 21);
      expect(FuelPlanner.plan(scenario(sport: FuelSport.strength)).post.single.amounts.carbs, 35);
      expect(FuelPlanner.plan(scenario(minutes: 45)).post.single.amounts.carbs, 35);
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
      // 30 min locker: 0,6 l/h × 0,5 h = 300 ml Defizit → 450 ml.
      expect(FuelPlanner.plan(scenario(minutes: 30)).post.single.amounts.fluid, 450);
      expect(FuelPlanner.plan(scenario(minutes: 20)).post.single.amounts.fluid, 0);
    });
  });

  group('6 Zeitstrahl und Produkte', () {
    test('Rad 2 h Schwelle mit Iso-Drink und Gel', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold),
        setup: [FuelProducts.isoDrink, FuelProducts.classicGel],
      );
      expect(plan.targets.carbsPerHour, 75);
      expect(plan.targets.fluidPerHour, 400);
      expect(plan.targets.sodiumPerHour, 0);
      expect([for (final step in plan.intra) step.minute], [20, 40, 60, 80, 100]);
      expect(plan.intra.first.line, 'Minute 20: 150 ml Iso-Drink 6 % (9 g KH) + 1 × Gel klassisch (2:1) (25 g KH)');
      expect(plan.intra[1].line, 'Minute 40: 150 ml Iso-Drink 6 % (9 g KH)');
      expect(plan.intraTarget.carbs, 125);
      expect(plan.intraDelivered.carbs, 120);
      final gels = plan.packing.firstWhere((item) => item.product == FuelProducts.classicGel);
      expect(gels.count, 3);
      final iso = plan.packing.firstWhere((item) => item.product == FuelProducts.isoDrink);
      expect(iso.milliliters, 750);
      expect(iso.count, 2);
      expect(iso.line, '2 × Flasche Iso-Drink 6 % à 500 ml');
      expect(plan.notes.where((note) => note.isWarning), isEmpty);
    });

    test('Ohne Auswahl: Gel klassisch und Wasser', () {
      final plan = FuelPlanner.plan(scenario(minutes: 90, intensity: FuelIntensity.tempo));
      expect(plan.targets.carbsPerHour, 60);
      expect(plan.intra.first.portions.single.product, FuelProducts.classicGel);
      expect(plan.intraDelivered.carbs, 75); // 3 Einnahmen à 20 g Soll → 3 Gels
      expect(plan.intra.every((step) => step.water == 100), isTrue); // 0,4 × 0,9 l/h = 360 → 350 ml/h
    });

    test('Kurz: keine Einnahme, Wasser nach Durst', () {
      final plan = FuelPlanner.plan(scenario(minutes: 40, race: true));
      expect(plan.intra, isEmpty);
      expect(plan.notes.map((note) => note.text), contains('Unter 45 Minuten: Wasser nach Durst genügt.'));
    });

    test('Schwimmen: Takt mindestens 20 min', () {
      final plan = FuelPlanner.plan(scenario(sport: FuelSport.swim, minutes: 90, race: true, interval: 15));
      expect(plan.intra.first.minute, 20);
    });

    test('Salztabletten über den Natrium-Saldo', () {
      final plan = FuelPlanner.plan(
        scenario(minutes: 180, race: true, saltiness: SweatSaltiness.high),
        setup: [FuelProducts.classicGel, FuelProducts.saltTablet],
      );
      // 1,2 l/h × 1300 mg/l × 0,5 = 780 → 800 mg/h
      expect(plan.targets.sodiumPerHour, 800);
      final tablets = plan.packing.firstWhere((item) => item.product == FuelProducts.saltTablet).count;
      expect(tablets, inInclusiveRange(7, 9));
      expect(plan.sodiumCoverage, closeTo(1, 0.15));
    });

    test('Natrium fehlt ohne salziges Produkt', () {
      final plan = FuelPlanner.plan(scenario(minutes: 180, race: true), setup: [FuelProducts.classicGel]);
      expect(plan.notes.any((note) => note.isWarning && note.text.startsWith('Natrium fehlt')), isTrue);
    });

    test('Zu wenig Fruktose bei hoher Menge', () {
      const glucoseGel = FuelProduct(id: 'g', name: 'Glukose-Gel', kind: FuelProductKind.gel, carbs: 30, fructose: 0);
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 240, race: true, gut: GutTolerance.trained),
        setup: [glucoseGel],
      );
      expect(plan.targets.ratio, FuelRatio.oneToPointEight);
      expect(plan.notes.any((note) => note.isWarning && note.text.startsWith('Zu wenig Fruktose')), isTrue);
      final fine = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 240, race: true, gut: GutTolerance.trained),
        setup: [FuelProducts.highCarbDrink, FuelProducts.highCarbGel],
      );
      expect(fine.notes.any((note) => note.text.startsWith('Zu wenig Fruktose')), isFalse);
      expect(fine.carbCoverage, closeTo(1, 0.15));
    });

    test('Getränk mit vielen Kohlenhydraten: Rest als Wasser', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold),
        setup: [FuelProducts.highCarbDrink],
      );
      // Flüssigkeit 133 ml je Einnahme (KH erlauben 156 ml) → 150 ml Drink, kein Wasser mehr.
      expect(plan.intra.first.portions.single.milliliters, 150);
      expect(plan.intra.first.water, 0);
    });

    test('Eigene Mischung: Werte aus Zutaten, Packliste mit Pulver, Hinweis bei hoher Konzentration', () {
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
      expect(plan.notes.any((note) => note.text.startsWith('Meine Flasche: 19,4 %')), isTrue);
    });

    test('Kraft ohne Bedarf: kein Zeitstrahl', () {
      final plan = FuelPlanner.plan(scenario(sport: FuelSport.strength));
      expect(plan.targets.carbsPerHour, 0);
      expect(plan.intra.every((step) => step.portions.isEmpty && step.water > 0), isTrue);
      expect(plan.notes.map((note) => note.text), contains('Krafttraining: Mahlzeit davor und danach genügen.'));
    });
  });

  group('7 Ernährungstagebuch', () {
    test('Unterwegs mit echten Produkten, vorher und danach als Plan-Eintrag plus Wasser', () {
      final plan = FuelPlanner.plan(
        scenario(sport: FuelSport.bike, minutes: 120, intensity: FuelIntensity.threshold),
        setup: [FuelProducts.isoDrink, FuelProducts.classicGel],
      );
      final entries = FuelDiary.entries(plan);
      expect([for (final entry in entries) entry.phase], FuelPhase.values);
      final intra = entries[1];
      expect(intra.title, 'Verpflegung unterwegs');
      final gel = intra.items.firstWhere((item) => item.name == FuelProducts.classicGel.name);
      expect(gel.grams, 120);
      expect(gel.portionCount, 3);
      final iso = intra.items.firstWhere((item) => item.name == FuelProducts.isoDrink.name);
      expect(iso.isDrink, isTrue);
      expect(iso.grams, 750);
      expect(intra.totals[Nutrient.carbs], closeTo(plan.intraDelivered.carbs, 0.01));
      expect(Hydration.total(intra.items).drinks, 750);
      final pre = entries.first;
      expect(pre.minute, -210);
      expect(pre.totals[Nutrient.carbs], plan.total(FuelPhase.pre).carbs);
      expect(pre.totals[Nutrient.kcal], plan.total(FuelPhase.pre).kilocalories.roundToDouble());
      expect(Hydration.total(pre.items).drinks, plan.total(FuelPhase.pre).fluid);
      expect(entries.last.minute, 120);
      expect(FuelDiary.entries(plan, phases: {FuelPhase.post}).single.phase, FuelPhase.post);
    });
  });

  group('8 Speicher je Benutzer', () {
    test('Szenario, Produkt und Bibliothek als JSON', () {
      final original = scenario(
        sport: FuelSport.bike,
        minutes: 150,
        race: true,
        caffeine: true,
        hoursUntilNext: 6,
        sweatRate: 1.3,
        start: 540,
      ).copyWith(title: 'Radmarathon', day: () => const CalendarDay(2026, 12, 6), slotID: () => 'slot-1');
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
        ..savePlan(SavedFuelPlan(id: 'p', scenario: original, productIDs: ['mix'], savedAt: DateTime.utc(2026, 11)));
      expect(library.products.length, 1); // Mitgelieferte werden nicht gespeichert.
      final json = jsonDecode(jsonEncode(library.toJson()));
      final back = FuelLibrary.fromJson(json, username: 'anna')!;
      expect(back.products.single.mix!.maltodextrin, 50);
      expect(back.products.single.carbs, 77.5);
      expect(back.profile.gut, GutTolerance.trained);
      expect(back.resolve(back.profile.setup).map((p) => p.id), ['mix', 'builtin.gel']);
      expect(back.planForSlot('slot-1')?.id, 'p');
      expect(FuelLibrary.fromJson(json, username: 'ben'), isNull);
      back.deleteProduct('mix');
      expect(back.profile.setup, ['builtin.gel']);
    });

    test('Mitgelieferte IDs werden aus fremden Daten nicht übernommen', () {
      expect(FuelProduct.fromJson(FuelProducts.classicGel.toJson()), isNull);
    });
  });

  test('1 Aus einer Einheit des Ausdauerplans', () {
    const workout = EnduranceWorkout(
      sport: EnduranceSport.run,
      type: EnduranceWorkoutType.race,
      title: 'Halbmarathon',
      minutes: 110,
      steps: [],
      load: 120,
    );
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
}

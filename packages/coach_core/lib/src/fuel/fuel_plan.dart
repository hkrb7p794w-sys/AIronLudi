// Fuel Planner: rechnet ein Szenario in einen konkreten Plan um – Zielwerte, Zeitpunkte vor, während und nach der
// Einheit, Zuordnung der Produkte und Packliste. Spezifikation 3–6 (docs/FUEL_PLANNER_SCIENCE.md).
import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../util/german_format.dart';
import 'fuel_product.dart';
import 'fuel_rules.dart';
import 'fuel_scenario.dart';

enum FuelPhase {
  pre('Vorher'),
  intra('Unterwegs'),
  post('Danach');

  const FuelPhase(this.label);

  final String label;
}

/// Mengen einer Einnahme bzw. Phase.
final class FuelAmounts {
  const FuelAmounts({
    this.carbs = 0,
    this.fructose = 0,
    this.fructoseKnownCarbs = 0,
    this.protein = 0,
    this.fat = 0,
    this.fluid = 0,
    this.sodium = 0,
    this.caffeine = 0,
  });

  static const zero = FuelAmounts();

  final double carbs;

  /// Fruktose der Kohlenhydrate mit bekannter Fruktose-Angabe ([fructoseKnownCarbs]).
  final double fructose;
  final double fructoseKnownCarbs;
  final double protein;
  final double fat;

  /// ml
  final double fluid;

  /// mg
  final double sodium;

  /// mg
  final double caffeine;

  double get kilocalories => 4 * carbs + 4 * protein + 9 * fat;

  /// Fruktose-Anteil; `null`, wenn keine Angabe vorliegt.
  double? get fructoseShare => fructoseKnownCarbs <= 0 ? null : fructose / fructoseKnownCarbs;

  FuelAmounts operator +(FuelAmounts other) => FuelAmounts(
    carbs: carbs + other.carbs,
    fructose: fructose + other.fructose,
    fructoseKnownCarbs: fructoseKnownCarbs + other.fructoseKnownCarbs,
    protein: protein + other.protein,
    fat: fat + other.fat,
    fluid: fluid + other.fluid,
    sodium: sodium + other.sodium,
    caffeine: caffeine + other.caffeine,
  );

  static FuelAmounts sum(Iterable<FuelAmounts> values) => values.fold(zero, (a, b) => a + b);

  /// Werte eines Produkts für [servings] Portionen (bei Getränken [milliliters]).
  static FuelAmounts ofProduct(FuelProduct product, double servings) {
    final fructose = product.fructose;
    return FuelAmounts(
      carbs: product.carbs * servings,
      fructose: (fructose ?? 0) * servings,
      fructoseKnownCarbs: fructose == null ? 0 : product.carbs * servings,
      protein: product.protein * servings,
      fat: product.fat * servings,
      fluid: product.isDrink ? product.volumeMilliliters * servings : 0,
      sodium: product.sodium * servings,
      caffeine: product.caffeine * servings,
    );
  }
}

/// Ein Produkt in einer Einnahme.
final class FuelPortion {
  const FuelPortion({required this.product, required this.servings});

  final FuelProduct product;

  /// Portionen (bei Getränken Anteil der Flasche).
  final double servings;

  double get milliliters => product.isDrink ? product.volumeMilliliters * servings : 0;

  FuelAmounts get amounts => FuelAmounts.ofProduct(product, servings);

  /// „1 × Gel klassisch (25 g KH)“ bzw. „250 ml Iso-Drink 6 % (15 g KH)“.
  String get line {
    final carbs = amounts.carbs.round();
    final carbsText = carbs > 0 ? ' ($carbs g KH)' : '';
    if (product.isDrink) return '${milliliters.round()} ml ${product.name}$carbsText';
    return '${GermanFormat.decimal(servings)} × ${product.name}$carbsText';
  }
}

/// Ein Zeitpunkt des Plans. [minute] zählt ab Start (vorher negativ); nach der Einheit ab ihrem Ende.
final class FuelStep {
  const FuelStep({
    required this.phase,
    required this.minute,
    required this.title,
    this.detail = '',
    this.amounts = FuelAmounts.zero,
    this.portions = const [],
    this.water = 0,
  });

  final FuelPhase phase;
  final int minute;
  final String title;
  final String detail;

  /// Gesamtmengen (inklusive [portions] und [water]).
  final FuelAmounts amounts;
  final List<FuelPortion> portions;

  /// Wasser in ml (unterwegs).
  final double water;

  /// Zeitangabe: „3–4 h vorher“ bzw. „Minute 20“ bzw. „+1 h“.
  String get timeLabel => switch (phase) {
    FuelPhase.pre => FuelPlanner.preLabel(minute),
    FuelPhase.intra => 'Minute $minute',
    FuelPhase.post => minute == 0 ? 'Direkt danach' : '+${GermanFormat.decimal(minute / 60)} h',
  };

  /// „Minute 20: 1 × Gel klassisch (25 g KH) + 200 ml Wasser“.
  String get line {
    final parts = [
      for (final portion in portions) portion.line,
      if (water > 0) '${water.round()} ml Wasser',
      if (phase == FuelPhase.intra && amounts.caffeine > 0 && portions.every((p) => p.product.caffeine <= 0))
        '${amounts.caffeine.round()} mg Koffein',
    ];
    return '$timeLabel: ${parts.isEmpty ? title : parts.join(' + ')}';
  }
}

enum FuelNoteKind { info, warning }

final class FuelNote {
  const FuelNote(this.text, [this.kind = FuelNoteKind.info]);

  final String text;
  final FuelNoteKind kind;

  bool get isWarning => kind == FuelNoteKind.warning;
}

/// Was mitzunehmen ist.
final class FuelPackItem {
  const FuelPackItem({required this.product, required this.servings});

  final FuelProduct product;

  /// Portionen bzw. bei Getränken Flaschen (Anteil).
  final double servings;

  double get milliliters => product.isDrink ? product.volumeMilliliters * servings : 0;

  /// Ganze Flaschen bzw. Portionen zum Einpacken.
  int get count => (servings - 1e-6).ceil();

  /// Pulver für eigene Mischungen (g), für [count] Flaschen.
  double? get powderGrams => product.mix == null ? null : product.mix!.powderGrams * count;

  String get line {
    if (product.isDrink) {
      final bottles = count == 1 ? '1 ${product.serving}' : '$count × ${product.serving}';
      final powder = powderGrams;
      return '$bottles ${product.name} à ${product.volumeMilliliters.round()} ml'
          '${powder != null ? ' (${powder.round()} g Pulver)' : ''}';
    }
    return '$count × ${product.name}';
  }
}

/// Zielwerte unterwegs.
final class FuelTargets {
  const FuelTargets({
    required this.carbsPerHour,
    required this.fluidPerHour,
    required this.sodiumPerHour,
    required this.sweatRate,
    required this.ratio,
  });

  final int carbsPerHour;

  /// ml/h
  final int fluidPerHour;

  /// mg/h
  final int sodiumPerHour;

  /// l/h
  final double sweatRate;
  final FuelRatio ratio;

  /// Natrium je Liter Getränk (mg/l); `null` ohne Trinken.
  int? get sodiumPerLiterDrink => fluidPerHour <= 0 ? null : (sodiumPerHour / fluidPerHour * 1000).round();
}

final class FuelPlan {
  const FuelPlan({
    required this.scenario,
    required this.targets,
    required this.pre,
    required this.intra,
    required this.post,
    required this.intraTarget,
    required this.packing,
    required this.notes,
    this.carbLoading,
    this.caffeine,
  });

  final FuelScenario scenario;
  final FuelTargets targets;
  final List<FuelStep> pre;
  final List<FuelStep> intra;
  final List<FuelStep> post;

  /// Soll unterwegs (Summe über alle Einnahmen).
  final FuelAmounts intraTarget;
  final List<FuelPackItem> packing;
  final List<FuelNote> notes;
  final FuelCarbLoading? carbLoading;
  final FuelCaffeine? caffeine;

  List<FuelStep> steps(FuelPhase phase) => switch (phase) {
    FuelPhase.pre => pre,
    FuelPhase.intra => intra,
    FuelPhase.post => post,
  };

  FuelAmounts total(FuelPhase phase) => FuelAmounts.sum(steps(phase).map((step) => step.amounts));

  FuelAmounts get intraDelivered => total(FuelPhase.intra);

  FuelAmounts get all => total(FuelPhase.pre) + total(FuelPhase.intra) + total(FuelPhase.post);

  /// Anteil 0–∞ (1 = genau getroffen); `null` ohne Soll.
  static double? coverage(double delivered, double target) => target <= 0 ? null : delivered / target;

  double? get carbCoverage => coverage(intraDelivered.carbs, intraTarget.carbs);
  double? get fluidCoverage => coverage(intraDelivered.fluid, intraTarget.fluid);
  double? get sodiumCoverage => coverage(intraDelivered.sodium, intraTarget.sodium);

  /// Wasser unterwegs insgesamt (ml).
  double get intraWater => intra.map((step) => step.water).sum;
}

abstract final class FuelPlanner {
  /// Keine Einnahme in den letzten Minuten.
  static const lastIntakeBeforeEnd = 10;

  /// Mehr Portionen fester Produkte je Einnahme sind unrealistisch.
  static const maxServingsPerIntake = 3;

  /// Abweichung der Kohlenhydrate, ab der gewarnt wird: 15 % oder diese Grammzahl (eine halbe Portion Rundung).
  static const carbToleranceGrams = 15.0;

  static String preLabel(int minute) => switch (-minute) {
    >= 180 => '3–4 h vorher',
    >= 120 => '2 h vorher',
    >= 60 && < 90 => '60 min vorher',
    >= 60 => '1–2 h vorher',
    _ => '15–30 min vorher',
  };

  static FuelPlan plan(FuelScenario s, {List<FuelProduct> setup = const []}) {
    final sweat = FuelRules.sweatRate(s);
    final carbs = FuelRules.carbsPerHour(s);
    final targets = FuelTargets(
      carbsPerHour: carbs,
      fluidPerHour: FuelRules.fluidPerHour(s, sweat: sweat),
      sodiumPerHour: FuelRules.sodiumPerHour(s, sweat: sweat),
      sweatRate: sweat,
      ratio: FuelRules.ratio(carbs),
    );
    final caffeine = FuelRules.caffeine(s);
    final intra = _intra(s, targets, setup, caffeine);
    final intraTarget = intra.target;
    final delivered = FuelAmounts.sum(intra.steps.map((step) => step.amounts));
    final plan = FuelPlan(
      scenario: s,
      targets: targets,
      pre: _pre(s, caffeine),
      intra: intra.steps,
      post: _post(s, sweat: sweat, drank: delivered.fluid),
      intraTarget: intraTarget,
      packing: _packing(intra.steps),
      notes: const [],
      carbLoading: FuelRules.carbLoading(s),
      caffeine: caffeine,
    );
    return FuelPlan(
      scenario: plan.scenario,
      targets: plan.targets,
      pre: plan.pre,
      intra: plan.intra,
      post: plan.post,
      intraTarget: plan.intraTarget,
      packing: plan.packing,
      notes: _notes(plan, setup),
      carbLoading: plan.carbLoading,
      caffeine: plan.caffeine,
    );
  }

  static double _grams(double value) => FuelRules.roundTo(value, 5);
  static double _ml(double value) => FuelRules.roundTo(value, 50);

  // 3.1
  static List<FuelStep> _pre(FuelScenario s, FuelCaffeine? caffeine) {
    final w = s.weightKilograms;
    final steps = <FuelStep>[];
    if (s.fasted) {
      steps.add(
        FuelStep(
          phase: FuelPhase.pre,
          minute: -120,
          title: 'Wasser',
          detail: 'Nüchtern: nur trinken, nichts essen.',
          amounts: FuelAmounts(fluid: _ml(5 * w)),
        ),
      );
    } else if (s.sport == FuelSport.strength) {
      steps.add(
        FuelStep(
          phase: FuelPhase.pre,
          minute: -120,
          title: 'Mahlzeit',
          detail: 'Kohlenhydrate und Protein, z. B. Reis mit Hähnchen, Haferflocken mit Skyr.',
          amounts: FuelAmounts(
            carbs: _grams(1.0 * w),
            protein: (0.3 * w).roundToDouble().clamp(20, 40).toDouble(),
            fat: math.min(15, 0.15 * w).roundToDouble(),
            fluid: _ml(5 * w),
          ),
        ),
      );
    } else {
      steps.add(
        FuelStep(
          phase: FuelPhase.pre,
          minute: -210,
          title: 'Mahlzeit',
          detail:
              'Komplexe Kohlenhydrate, etwas Protein, wenig Fett und Ballaststoffe – z. B. Weißbrot mit Honig, '
              'Haferbrei, Reis.',
          amounts: FuelAmounts(
            carbs: _grams(FuelRules.preMealCarbsPerKilogram(s) * w),
            protein: math.min(25, 0.25 * w).roundToDouble(),
            fat: math.min(15, 0.15 * w).roundToDouble(),
            fluid: _ml(6 * w),
          ),
        ),
      );
      if (FuelRules.hasPreSnack(s)) {
        steps.add(
          FuelStep(
            phase: FuelPhase.pre,
            minute: -90,
            title: 'Snack',
            detail: 'Leicht verdaulich, z. B. Banane, Toast mit Marmelade, Reiswaffeln.',
            amounts: FuelAmounts(carbs: _grams(0.5 * w), fluid: _ml(3 * w)),
          ),
        );
      }
    }
    if (caffeine != null && caffeine.before > 0) {
      steps.add(
        FuelStep(
          phase: FuelPhase.pre,
          minute: -60,
          title: 'Koffein',
          detail: 'Kaffee, Kapsel oder Koffein-Gel.',
          amounts: FuelAmounts(caffeine: caffeine.before),
        ),
      );
    }
    if (!s.fasted && FuelRules.hasPreBooster(s)) {
      steps.add(
        const FuelStep(
          phase: FuelPhase.pre,
          minute: -20,
          title: 'Schnelle Kohlenhydrate',
          detail: 'Gel oder halbe Banane mit einem Schluck Wasser.',
          amounts: FuelAmounts(carbs: 20, fluid: 200),
        ),
      );
    }
    return steps;
  }

  // 6 Zeitstrahl.
  static ({List<FuelStep> steps, FuelAmounts target}) _intra(
    FuelScenario s,
    FuelTargets targets,
    List<FuelProduct> setup,
    FuelCaffeine? caffeine,
  ) {
    final hasNeed = targets.carbsPerHour > 0 || targets.fluidPerHour > 0 || targets.sodiumPerHour > 0;
    if (!hasNeed && (caffeine?.late ?? 0) <= 0) return (steps: const [], target: FuelAmounts.zero);
    final interval = s.sport == FuelSport.swim ? math.max(20, s.intervalMinutes) : s.intervalMinutes;
    final times = [for (var t = interval; t <= s.minutes - lastIntakeBeforeEnd; t += interval) t];
    if (times.isEmpty) return (steps: const [], target: FuelAmounts.zero);
    final fraction = interval / 60;
    final drink = setup.firstWhereOrNull((p) => p.isDrink);
    var solids = [
      for (final p in setup)
        if (p.kind.isSolid && p.carbs > 0) p,
    ];
    if (drink == null && solids.isEmpty && targets.carbsPerHour > 0) solids = [FuelProducts.classicGel];
    final salt = setup.firstWhereOrNull((p) => p.kind == FuelProductKind.electrolyte && p.sodium > 0);

    final carbsPerIntake = targets.carbsPerHour * fraction;
    final fluidPerIntake = targets.fluidPerHour * fraction;
    final sodiumPerIntake = targets.sodiumPerHour * fraction;
    var wantCarbs = 0.0;
    var wantSodium = 0.0;
    var gotCarbs = 0.0;
    var gotSodium = 0.0;
    var rotation = 0;
    final lateCaffeineMinute = caffeine?.lateMinute == null
        ? null
        : times.firstWhereOrNull((t) => t >= caffeine!.lateMinute!) ?? times.last;
    final steps = <FuelStep>[];
    for (final t in times) {
      wantCarbs += carbsPerIntake;
      wantSodium += sodiumPerIntake;
      final portions = <FuelProduct, double>{};
      var drinkMl = 0.0;
      if (drink != null && fluidPerIntake > 0) {
        final open = math.max(0.0, wantCarbs - gotCarbs);
        final byCarbs = drink.carbsPerMilliliter > 0 ? open / drink.carbsPerMilliliter : double.infinity;
        drinkMl = _ml(math.min(fluidPerIntake, byCarbs));
        if (drinkMl > 0) {
          portions[drink] = drinkMl / drink.volumeMilliliters;
          gotCarbs += drink.carbsPerMilliliter * drinkMl;
          gotSodium += drink.sodiumPerMilliliter * drinkMl;
        }
      }
      var count = 0;
      while (solids.isNotEmpty && count < maxServingsPerIntake) {
        final product = solids[rotation % solids.length];
        if (wantCarbs - gotCarbs < product.carbs / 2) break;
        portions[product] = (portions[product] ?? 0) + 1;
        gotCarbs += product.carbs;
        gotSodium += product.sodium;
        rotation++;
        count++;
      }
      if (salt != null) {
        var tablets = 0;
        while (tablets < maxServingsPerIntake && wantSodium - gotSodium >= salt.sodium / 2) {
          portions[salt] = (portions[salt] ?? 0) + 1;
          gotSodium += salt.sodium;
          tablets++;
        }
      }
      final waterMl = _ml(math.max(0.0, fluidPerIntake - drinkMl));
      final list = [for (final MapEntry(:key, :value) in portions.entries) FuelPortion(product: key, servings: value)];
      final lateCaffeine = t == lateCaffeineMinute ? caffeine!.late : 0.0;
      final amounts = FuelAmounts.sum(list.map((p) => p.amounts)) + FuelAmounts(fluid: waterMl, caffeine: lateCaffeine);
      steps.add(
        FuelStep(
          phase: FuelPhase.intra,
          minute: t,
          title: list.isEmpty && waterMl == 0 ? (lateCaffeine > 0 ? 'Koffein' : 'Nichts nötig') : 'Einnahme',
          detail: lateCaffeine > 0 ? 'Koffein fürs letzte Drittel (z. B. Koffein-Gel oder Cola).' : '',
          amounts: amounts,
          portions: list,
          water: waterMl,
        ),
      );
    }
    final n = times.length;
    final target = FuelAmounts(
      carbs: carbsPerIntake * n,
      fluid: fluidPerIntake * n,
      sodium: sodiumPerIntake * n,
      caffeine: caffeine?.late ?? 0,
    );
    return (steps: steps, target: target);
  }

  // 5
  static List<FuelStep> _post(FuelScenario s, {required double sweat, required double drank}) {
    final w = s.weightKilograms;
    final deficit = math.max(0.0, sweat * s.hours * 1000 - drank);
    final fluid = deficit >= 200 ? _ml(deficit * FuelRules.postFluidFactor) : 0.0;
    final sodium = FuelRules.roundTo(fluid / 1000 * FuelRules.postSodiumPerLiter, 50);
    final protein = FuelRules.proteinDose(s);
    const proteinDetail = 'Hochwertiges Protein (Leucin-Schwelle ~2,5–3 g): Milch, Skyr, Ei, Fleisch, Fisch, Molke.';
    if (FuelRules.rapidRefuel(s)) {
      final (rate, hours) = FuelRules.rapidRate(s);
      return [
        for (var hour = 0; hour < hours; hour++)
          FuelStep(
            phase: FuelPhase.post,
            minute: hour * 60,
            title: hour == 0 ? 'Schnell auffüllen' : 'Weiter auffüllen',
            detail: hour == 0
                ? 'Nächste Einheit in ${s.hoursUntilNext} h: stündlich schnelle Kohlenhydrate. $proteinDetail'
                : 'Schnelle Kohlenhydrate (Saft, Reiswaffeln, Weißbrot, Sportgetränk).',
            amounts: FuelAmounts(
              carbs: _grams(rate * w),
              protein: hour == 0 ? protein : 0,
              fluid: hour == 0 ? fluid : 0,
              sodium: hour == 0 ? sodium : 0,
            ),
          ),
      ];
    }
    return [
      FuelStep(
        phase: FuelPhase.post,
        minute: 0,
        title: 'Regenerationsmahlzeit',
        detail: 'In den ersten 2 Stunden. $proteinDetail',
        amounts: FuelAmounts(
          carbs: _grams(FuelRules.postCarbsPerKilogram(s) * w),
          protein: protein,
          fat: math.min(20, 0.2 * w).roundToDouble(),
          fluid: fluid,
          sodium: sodium,
        ),
      ),
    ];
  }

  static List<FuelPackItem> _packing(List<FuelStep> steps) {
    final servings = <FuelProduct, double>{};
    for (final step in steps) {
      for (final portion in step.portions) {
        servings[portion.product] = (servings[portion.product] ?? 0) + portion.servings;
      }
    }
    return [for (final MapEntry(:key, :value) in servings.entries) FuelPackItem(product: key, servings: value)];
  }

  static List<FuelNote> _notes(FuelPlan plan, List<FuelProduct> setup) {
    final s = plan.scenario;
    final t = plan.targets;
    final notes = <FuelNote>[];
    if (s.minutes < 45) notes.add(const FuelNote('Unter 45 Minuten: Wasser nach Durst genügt.'));
    if (FuelRules.mouthRinse(s)) {
      notes.add(const FuelNote('Unter einer Stunde reicht auch eine Mundspülung mit Sportgetränk.'));
    }
    if (FuelRules.carbsOptional(s)) {
      notes.add(const FuelNote('Locker unter 90 Minuten: Kohlenhydrate optional (bis 30 g/h).'));
    }
    if (s.sport == FuelSport.strength && t.carbsPerHour == 0) {
      notes.add(const FuelNote('Krafttraining: Mahlzeit davor und danach genügen.'));
    }
    if (s.sport == FuelSport.run && t.carbsPerHour >= 60) {
      notes.add(const FuelNote('Laufen: lieber kleine Portionen öfter, Gels mit Wasser nachspülen.'));
    }
    if (s.sport == FuelSport.swim && plan.intra.isNotEmpty) {
      notes.add(const FuelNote('Schwimmen: Flasche und Gels am Beckenrand bereitlegen.'));
    }
    if (FuelRules.needsGutTraining(s, t.carbsPerHour)) {
      notes.add(
        const FuelNote(
          'Gut-Training: 4–6 Wochen im Training üben, je Woche etwa 10 g/h mehr, mit den Produkten vom Wettkampf.',
        ),
      );
    }
    final share = plan.intraDelivered.fructoseShare;
    if (t.ratio != FuelRatio.single &&
        share != null &&
        share < t.ratio.fructoseShare - FuelRatio.tolerance &&
        plan.intraDelivered.carbs > 0) {
      notes.add(
        FuelNote(
          'Zu wenig Fruktose für ${t.carbsPerHour} g/h: ${(share * 100).round()} % statt '
          '${(t.ratio.fructoseShare * 100).round()} % (${t.ratio.label}). Produkte mit mehr Fruktose wählen.',
          FuelNoteKind.warning,
        ),
      );
    }
    if (t.fluidPerHour > 0) {
      notes.add(
        FuelNote(
          'Nicht mehr trinken als du schwitzt (≈ ${(t.sweatRate * 1000).round()} ml/h) – sonst droht eine '
          'Hyponatriämie.',
        ),
      );
    }
    if (t.sodiumPerLiterDrink case final perLiter? when t.sodiumPerHour > 0) {
      notes.add(FuelNote('Natrium: ≈ $perLiter mg je Liter Getränk.'));
    }
    final sodium = plan.sodiumCoverage;
    if (sodium != null && sodium < 0.7) {
      notes.add(
        const FuelNote(
          'Natrium fehlt: Salztablette oder salzigeres Getränk in die Auswahl nehmen.',
          FuelNoteKind.warning,
        ),
      );
    }
    final carbs = plan.carbCoverage;
    final carbGap = (plan.intraDelivered.carbs - plan.intraTarget.carbs).abs();
    if (carbs != null && carbGap > math.max(0.15 * plan.intraTarget.carbs, carbToleranceGrams)) {
      notes.add(
        FuelNote(
          'Die Produkte treffen ${(carbs * 100).round()} % der Kohlenhydrate – Portionsgröße oder Takt anpassen.',
          FuelNoteKind.warning,
        ),
      );
    }
    for (final product in setup) {
      final mix = product.mix;
      if (mix != null && mix.concentration > FuelMix.highConcentration) {
        notes.add(
          FuelNote(
            '${product.name}: ${GermanFormat.decimal(mix.concentration)} % Kohlenhydrate – der Magen leert sich '
            'langsamer. Mit Wasser nachspülen und im Training testen.',
            FuelNoteKind.warning,
          ),
        );
      }
    }
    final caffeine = plan.all.caffeine;
    if (caffeine > FuelRules.caffeineMaxPerKg * s.weightKilograms + 1) {
      notes.add(
        FuelNote(
          'Koffein insgesamt ${caffeine.round()} mg – mehr als 6 mg/kg. Weniger Koffein-Gels einplanen.',
          FuelNoteKind.warning,
        ),
      );
    }
    if (FuelRules.caffeineHurtsSleep(s)) {
      notes.add(
        const FuelNote(
          'Start am Nachmittag: Koffein wirkt ~5 h nach und kann den Schlaf stören.',
          FuelNoteKind.warning,
        ),
      );
    }
    if (s.temperatureCelsius >= 25) {
      notes.add(const FuelNote('Hitze: vorher gut trinken, kühle Getränke, im Zweifel Tempo rausnehmen.'));
    }
    return notes;
  }
}

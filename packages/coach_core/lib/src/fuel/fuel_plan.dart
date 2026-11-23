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
    this.segment,
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

  /// Abschnitt beim Triathlon (Rad, Laufen); sonst `null`.
  final FuelSport? segment;

  /// Zeitangabe: „3–4 h vorher“ bzw. „Minute 20“ bzw. „+1 h“ (Abschnitt beim Triathlon: [segment]).
  String get timeLabel => switch (phase) {
    FuelPhase.pre => FuelPlanner.preLabel(minute),
    FuelPhase.intra => 'Minute $minute',
    FuelPhase.post => minute == 0 ? 'Direkt danach' : '+${GermanFormat.decimal(minute / 60)} h',
  };

  /// Was eingenommen wird: „1 × Gel klassisch (25 g KH) + 200 ml Wasser“.
  String get content {
    final parts = [
      for (final portion in portions) portion.line,
      if (water > 0) '${water.round()} ml Wasser',
      if (phase == FuelPhase.intra && amounts.caffeine > 0 && portions.every((p) => p.product.caffeine <= 0))
        '${amounts.caffeine.round()} mg Koffein',
    ];
    return parts.isEmpty ? title : parts.join(' + ');
  }

  /// „Minute 20: 1 × Gel klassisch (25 g KH) + 200 ml Wasser“ (Triathlon: „Rad, Minute 60: …“).
  String get line => '${segment == null ? '' : '${segment!.label}, '}$timeLabel: $content';
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
  double? get powderGrams {
    final grams = product.mix?.powderGrams;
    return grams == null ? null : grams * count;
  }

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
    this.sweatEstimated = true,
    this.segments = const [],
  });

  /// Bei Triathlon zeitgewichtet über Rad und Laufen.
  final int carbsPerHour;

  /// ml/h
  final int fluidPerHour;

  /// mg/h
  final int sodiumPerHour;

  /// l/h
  final double sweatRate;
  final FuelRatio ratio;

  /// Schweißrate geschätzt (nicht gemessen).
  final bool sweatEstimated;

  /// Abschnitte mit eigenen Zielen (Triathlon: Schwimmen, Rad, Laufen).
  final List<FuelSegment> segments;

  /// Natrium je Liter Getränk (mg/l); `null` ohne Trinken.
  int? get sodiumPerLiterDrink => fluidPerHour <= 0 ? null : (sodiumPerHour / fluidPerHour * 1000).round();

  /// Mehr als geschwitzt sollte man nie trinken (ml/h).
  int get maxFluidPerHour => (sweatRate * 1000).round();
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

  List<FuelNote> get warnings => [
    for (final note in notes)
      if (note.isWarning) note,
  ];

  List<FuelNote> get infos => [
    for (final note in notes)
      if (!note.isWarning) note,
  ];

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
  /// Keine Einnahme in den letzten Minuten bzw. kurz vor einem Wechsel (Triathlon).
  static const lastIntakeBeforeEnd = 10;
  static const lastIntakeBeforeTransition = 5;

  /// Mehr Portionen fester Produkte je Einnahme sind unrealistisch.
  static const maxServingsPerIntake = 3;

  /// Sind Gels oder Riegel gewählt, deckt ein Getränk höchstens diesen Anteil der offenen Kohlenhydrate je Einnahme.
  static const drinkCarbShareWithSolids = 0.5;

  /// Ein Koffein-Produkt darf das Rest-Budget um bis zu 20 % überschreiten (feste Dosis je Gel).
  static const caffeineProductTolerance = 0.8;

  /// Abweichung der Kohlenhydrate, ab der gewarnt wird: 15 % oder diese Grammzahl (eine halbe Portion Rundung).
  static const carbToleranceGrams = 15.0;

  static String preLabel(int minute) => switch (-minute) {
    >= 180 => '3–4 h vorher',
    >= 120 => '2 h vorher',
    >= 60 && < 90 => '60 min vorher',
    >= 60 => '1–2 h vorher',
    _ => '15–30 min vorher',
  };

  /// [missingProducts]: gewählte Produkte, die es nicht mehr gibt (gelöscht).
  static FuelPlan plan(FuelScenario s, {List<FuelProduct> setup = const [], int missingProducts = 0}) {
    final sweat = FuelRules.sweatRate(s);
    final segments = FuelRules.segments(s, sweat: sweat);
    final carbs = FuelRules.carbsPerHour(s);
    final eating = segments.where((segment) => segment.canEat && segment.minutes > 0).toList();
    int weighted(int Function(FuelSegment) value) {
      final minutes = eating.fold(0, (sum, segment) => sum + segment.minutes);
      if (minutes <= 0) return 0;
      return FuelRules.roundTo(eating.fold(0.0, (sum, x) => sum + value(x) * x.minutes) / minutes, 50).round();
    }

    final targets = FuelTargets(
      carbsPerHour: carbs,
      fluidPerHour: segments.length == 1 ? segments.single.fluidPerHour : weighted((x) => x.fluidPerHour),
      sodiumPerHour: segments.length == 1 ? segments.single.sodiumPerHour : weighted((x) => x.sodiumPerHour),
      sweatRate: sweat,
      ratio: FuelRules.ratio(carbs),
      sweatEstimated: FuelRules.sweatIsEstimated(s),
      segments: segments,
    );
    final caffeine = FuelRules.caffeine(s);
    final intra = _intra(s, segments, setup, caffeine);
    final delivered = FuelAmounts.sum(intra.steps.map((step) => step.amounts));
    final draft = FuelPlan(
      scenario: s,
      targets: targets,
      pre: _pre(s, caffeine),
      intra: intra.steps,
      post: _post(s, sweat: sweat, drank: delivered.fluid),
      intraTarget: intra.target,
      packing: _packing(intra.steps),
      notes: const [],
      carbLoading: FuelRules.carbLoading(s),
      caffeine: caffeine,
    );
    return FuelPlan(
      scenario: draft.scenario,
      targets: draft.targets,
      pre: draft.pre,
      intra: draft.intra,
      post: draft.post,
      intraTarget: draft.intraTarget,
      packing: draft.packing,
      notes: _notes(draft, setup, substitutedCaffeine: intra.substitutedCaffeine, missingProducts: missingProducts),
      carbLoading: draft.carbLoading,
      caffeine: draft.caffeine,
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
        FuelStep(
          phase: FuelPhase.pre,
          minute: -20,
          title: 'Schnelle Kohlenhydrate',
          detail: s.sport == FuelSport.triathlon
              ? 'Gel vor dem Schwimmen – im Wasser gibt es nichts.'
              : 'Gel oder halbe Banane mit einem Schluck Wasser.',
          amounts: const FuelAmounts(carbs: 20, fluid: 200),
        ),
      );
    }
    return steps;
  }

  // 6 Zeitstrahl.
  static ({List<FuelStep> steps, FuelAmounts target, bool substitutedCaffeine}) _intra(
    FuelScenario s,
    List<FuelSegment> segments,
    List<FuelProduct> setup,
    FuelCaffeine? caffeine,
  ) {
    const none = (steps: <FuelStep>[], target: FuelAmounts.zero, substitutedCaffeine: false);
    final interval = s.sport == FuelSport.swim ? math.max(20, s.intervalMinutes) : s.intervalMinutes;
    final triathlon = s.sport == FuelSport.triathlon;
    // Einnahmen je Abschnitt: ab Abschnittsbeginn im Takt, nicht kurz vor Wechsel bzw. Ende.
    final intakes = <(int, FuelSegment)>[];
    for (final (index, segment) in segments.indexed) {
      if (!segment.canEat) continue;
      final gap = index == segments.length - 1 ? lastIntakeBeforeEnd : lastIntakeBeforeTransition;
      for (var t = segment.start + interval; t <= segment.end - gap; t += interval) {
        intakes.add((t, segment));
      }
    }
    final lateMinute = caffeine?.lateMinute;
    final hasNeed = segments.any((x) => x.carbsPerHour > 0 || x.fluidPerHour > 0 || x.sodiumPerHour > 0);
    if (intakes.isEmpty || (!hasNeed && (caffeine?.late ?? 0) <= 0)) return none;

    final drinks = [
      for (final p in setup)
        if (p.isDrink) p,
    ];
    final solids = [
      for (final p in setup)
        if (p.kind.isSolid && p.carbs > 0) p,
    ];
    final salt = setup.firstWhereOrNull((p) => p.kind == FuelProductKind.electrolyte && p.sodium > 0);
    final needsCarbs = segments.any((x) => x.carbsPerHour > 0);
    if (drinks.isEmpty && solids.isEmpty && needsCarbs) solids.add(FuelProducts.classicGel);
    final caffeineFree = solids.where((p) => p.caffeine <= 0).toList();

    var wantCarbs = 0.0, gotCarbs = 0.0;
    var wantFluid = 0.0, gotFluid = 0.0;
    var wantSodium = 0.0, gotSodium = 0.0;
    var rotation = 0;
    var bottle = 0;
    var bottleUsed = 0.0;
    // Koffein unterwegs: nur das Budget des letzten Drittels, nie darüber (Spezifikation 4.4).
    var caffeineLeft = caffeine?.late ?? 0.0;
    var caffeineSpent = caffeine?.before ?? 0.0;
    final ceiling = FuelRules.caffeineCeiling(s);
    final caffeineProducts = setup.any((p) => p.caffeine > 0);
    var substitutedCaffeine = false;
    var lateDone = false;
    final steps = <FuelStep>[];
    for (final (t, segment) in intakes) {
      final fraction = interval / 60;
      wantCarbs += segment.carbsPerHour * fraction;
      wantFluid += segment.fluidPerHour * fraction;
      wantSodium += segment.sodiumPerHour * fraction;
      final portions = <FuelProduct, double>{};
      final lateWindow = lateMinute != null && t >= lateMinute;

      // Höchstens 20 % über dem Rest-Budget (ein Gel hat feste Dosis), nie über die Grenze des ganzen Plans.
      bool caffeineAllowed(FuelProduct product) =>
          product.caffeine <= 0 ||
          (lateWindow &&
              caffeineLeft + 1e-6 >= caffeineProductTolerance * product.caffeine &&
              caffeineSpent + product.caffeine <= ceiling + 1e-6);
      void take(FuelProduct product, double servings) {
        portions[product] = (portions[product] ?? 0) + servings;
        gotCarbs += product.carbs * servings;
        gotSodium += product.sodium * servings;
        caffeineLeft -= product.caffeine * servings;
        caffeineSpent += product.caffeine * servings;
      }

      // 0. Im letzten Drittel zuerst das Koffein-Produkt, damit das Budget nicht hinter einem Getränk verschwindet.
      if (lateWindow) {
        final caffeineSolid = solids.firstWhereOrNull((p) => p.caffeine > 0 && caffeineAllowed(p));
        if (caffeineSolid != null && wantCarbs - gotCarbs >= caffeineSolid.carbs / 2) take(caffeineSolid, 1);
      }

      // 1. Getränk: offene Flüssigkeit, so weit die Kohlenhydrate es zulassen (mit gewählten Gels/Riegeln höchstens
      // die Hälfte der offenen Kohlenhydrate – Abwechslung statt nur Getränk); Flaschen im Wechsel.
      var drinkMl = 0.0;
      if (drinks.isNotEmpty && wantFluid - gotFluid > 0) {
        var drink = drinks[bottle % drinks.length];
        if (!caffeineAllowed(drink)) {
          drink = drinks.firstWhereOrNull((d) => d.caffeine <= 0) ?? drink;
        }
        final openCarbs = math.max(0.0, wantCarbs - gotCarbs) * (solids.isEmpty ? 1 : drinkCarbShareWithSolids);
        final byCarbs = drink.carbsPerMilliliter > 0 ? openCarbs / drink.carbsPerMilliliter : double.infinity;
        drinkMl = _ml(math.min(wantFluid - gotFluid, byCarbs));
        if (drinkMl > 0 && caffeineAllowed(drink)) {
          take(drink, drinkMl / drink.volumeMilliliters);
          gotFluid += drinkMl;
          bottleUsed += drinkMl;
          while (bottleUsed >= drink.volumeMilliliters - 1e-6) {
            bottleUsed -= drink.volumeMilliliters;
            bottle++;
          }
        } else {
          drinkMl = 0;
        }
      }

      // 2. Gels, Riegel …: ganze Portionen über den Saldo, im Wechsel; Koffein nur im Budget.
      var count = portions.keys.where((p) => p.kind.isSolid).length;
      while (solids.isNotEmpty && count < maxServingsPerIntake) {
        // Im letzten Drittel zuerst das Koffein-Produkt (solange es ins Budget passt).
        FuelProduct? product = lateWindow ? solids.firstWhereOrNull((p) => p.caffeine > 0 && caffeineAllowed(p)) : null;
        for (var attempt = 0; product == null && attempt < solids.length; attempt++) {
          final candidate = solids[(rotation + attempt) % solids.length];
          if (caffeineAllowed(candidate)) {
            product = candidate;
            rotation += attempt;
            break;
          }
        }
        if (product == null) {
          // Nur Koffein-Produkte gewählt, Budget erschöpft: ein Gel ohne Koffein statt dessen.
          product = caffeineFree.firstOrNull ?? FuelProducts.classicGel;
          substitutedCaffeine = true;
        }
        if (wantCarbs - gotCarbs < product.carbs / 2) break;
        take(product, 1);
        rotation++;
        count++;
      }
      if (solids.any((p) => p.caffeine > 0 && !caffeineAllowed(p)) && count > 0) substitutedCaffeine = true;

      // 3. Salztabletten über den Natrium-Saldo.
      if (salt != null) {
        var tablets = 0;
        while (tablets < maxServingsPerIntake && wantSodium - gotSodium >= salt.sodium / 2) {
          take(salt, 1);
          tablets++;
        }
      }

      // 4. Wasser: was an Flüssigkeit offen ist (laufender Saldo, auf 50 ml).
      final waterMl = _ml(math.max(0.0, wantFluid - gotFluid));
      gotFluid += waterMl;

      // Kein passendes Koffein-Produkt: einmal zu Beginn des letzten Drittels als eigener Schritt.
      var separateCaffeine = 0.0;
      final productFits = setup.any((p) => p.caffeine > 0 && caffeineAllowed(p));
      if (lateWindow && !lateDone && !productFits && caffeineLeft > 0 && portions.keys.every((p) => p.caffeine <= 0)) {
        separateCaffeine = caffeineLeft;
        caffeineSpent += caffeineLeft;
        caffeineLeft = 0;
      }
      if (lateWindow) lateDone = true;

      final list = [for (final MapEntry(:key, :value) in portions.entries) FuelPortion(product: key, servings: value)];
      // Nichts zu tun (z. B. Flüssigkeit noch unter 50 ml offen): keine Zeile im Zeitstrahl.
      if (list.isEmpty && waterMl == 0 && separateCaffeine == 0) continue;
      final amounts =
          FuelAmounts.sum(list.map((p) => p.amounts)) + FuelAmounts(fluid: waterMl, caffeine: separateCaffeine);
      steps.add(
        FuelStep(
          phase: FuelPhase.intra,
          minute: t,
          title: list.isEmpty && waterMl == 0 ? 'Koffein' : 'Einnahme',
          detail: [
            if (s.sport == FuelSport.swim) 'Am Beckenrand.',
            if (separateCaffeine > 0) 'Koffein fürs letzte Drittel (z. B. Koffein-Gel oder Cola).',
          ].join(' '),
          amounts: amounts,
          portions: list,
          water: waterMl,
          segment: triathlon ? segment.sport : null,
        ),
      );
    }
    final target = FuelAmounts(carbs: wantCarbs, fluid: wantFluid, sodium: wantSodium, caffeine: caffeine?.late ?? 0);
    return (steps: steps, target: target, substitutedCaffeine: substitutedCaffeine && caffeineProducts);
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

  /// Nur, was du wissen musst: Warnungen und wenige, situative Hinweise. Was zu den Zielwerten gehört (nicht mehr
  /// trinken als geschwitzt, Natrium je Liter), zeigt die App direkt bei den Ringen.
  static List<FuelNote> _notes(
    FuelPlan plan,
    List<FuelProduct> setup, {
    required bool substitutedCaffeine,
    required int missingProducts,
  }) {
    final s = plan.scenario;
    final t = plan.targets;
    final notes = <FuelNote>[];
    if (missingProducts > 0) {
      notes.add(
        FuelNote(
          missingProducts == 1
              ? 'Ein gewähltes Produkt gibt es nicht mehr – im Szenario neu wählen.'
              : '$missingProducts gewählte Produkte gibt es nicht mehr – im Szenario neu wählen.',
          FuelNoteKind.warning,
        ),
      );
    }
    final caffeine = plan.all.caffeine;
    if (caffeine > FuelRules.caffeineCeiling(s) + 1) {
      notes.add(
        FuelNote(
          'Koffein insgesamt ${caffeine.round()} mg – mehr als 6 mg/kg bzw. 400 mg. Koffeinhaltiges Getränk '
          'tauschen.',
          FuelNoteKind.warning,
        ),
      );
    }
    if (substitutedCaffeine) {
      notes.add(
        FuelNote(
          s.caffeine
              ? 'Koffein-Gels nur im letzten Drittel und bis zur Koffein-Grenze eingeplant, sonst Gels ohne Koffein.'
              : 'Koffein ist aus: statt Koffein-Gels Gels ohne Koffein eingeplant.',
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
            '${product.name}: ${GermanFormat.decimal(mix.concentration)} % Kohlenhydrate – über den 5–10 % der ACSM '
            'leert sich der Magen langsamer. Mit Wasser nachspülen und im Training testen.',
            FuelNoteKind.warning,
          ),
        );
      }
    }
    if (FuelRules.caffeineHurtsSleep(s)) {
      notes.add(
        const FuelNote(
          'Start am Nachmittag: Koffein wirkt ~5 h nach und kann den Schlaf stören.',
          FuelNoteKind.warning,
        ),
      );
    }
    if (s.minutes < 45) notes.add(const FuelNote('Unter 45 Minuten: Wasser nach Durst genügt.'));
    if (FuelRules.mouthRinse(s)) {
      notes.add(const FuelNote('Unter einer Stunde reicht auch eine Mundspülung mit Sportgetränk.'));
    }
    if (FuelRules.carbsOptional(s)) {
      notes.add(const FuelNote('Locker unter 90 Minuten: Kohlenhydrate sind optional.'));
    }
    if (s.sport == FuelSport.strength && t.carbsPerHour == 0) {
      notes.add(const FuelNote('Krafttraining: Mahlzeit davor und danach genügen.'));
    }
    if (s.sport == FuelSport.triathlon) {
      notes.add(const FuelNote('Im Wasser gibt es nichts – davor ein Gel, ab dem Rad essen und trinken.'));
    }
    if (FuelRules.needsGutTraining(s)) {
      notes.add(
        const FuelNote(
          'Gut-Training: 4–6 Wochen im Training üben, je Woche etwa 10 g/h mehr, mit den Produkten vom Wettkampf.',
        ),
      );
    }
    if (s.temperatureCelsius >= 25) {
      notes.add(const FuelNote('Hitze: vorher gut trinken, kühle Getränke, im Zweifel Tempo rausnehmen.'));
    }
    return notes;
  }
}

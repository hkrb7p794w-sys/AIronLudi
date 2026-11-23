// Fuel Planner: herkömmliche Lebensmittel (BLS), Mahlzeiten-Vorschläge, Alltag unterwegs, Vorrat, Einnahme-Tipps.
// Spezifikation 10 und 11 (docs/FUEL_PLANNER_SCIENCE.md).
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const halfMarathon = FuelScenario(
  sport: FuelSport.run,
  minutes: 110,
  weightKilograms: 70,
  isRace: true,
  startMinuteOfDay: 540,
  day: CalendarDay(2026, 12, 6),
);

FuelStep step(FuelPhase phase, int minute) =>
    FuelPlanner.plan(halfMarathon).steps(phase).firstWhere((s) => s.minute == minute);

void main() {
  group('10.1 Lebensmittel aus dem BLS 4.0', () {
    test('Jedes Lebensmittel stimmt mit der Tabelle überein', () {
      BLS.load(File('assets/bls.tsv').readAsStringSync());
      for (final food in FuelFoods.all) {
        final entry = BLS.food(food.bls);
        expect(entry, isNotNull, reason: food.id);
        expect(food.matches(entry!), isTrue, reason: '${food.id}: ${entry.per100g.values}');
      }
      expect({for (final food in FuelFoods.all) food.id}.length, FuelFoods.all.length);
    });

    test('Portion und Tagebuch-Position', () {
      final toast = FuelFoods.toast.amounts(50);
      expect(toast.carbs, closeTo(23.4, 0.01));
      final item = FuelFoods.toast.item(50);
      expect((item.blsCode, item.source, item.grams, item.portionCount), ('B314000', MealItemSource.bls, 50.0, 2.0));
      expect(FuelFoods.appleJuice.item(250).isDrink, isTrue);
    });

    test('Mengen lesbar', () {
      expect(FuelMeals.amountText(FuelFoods.toast, 3), '3 Scheiben Toastbrot');
      expect(FuelMeals.amountText(FuelFoods.toast, 1), '1 Scheibe Toastbrot');
      expect(FuelMeals.amountText(FuelFoods.banana, 0.5), '½ Banane');
      expect(FuelMeals.amountText(FuelFoods.banana, 2), '2 Bananen');
      expect(FuelMeals.amountText(FuelFoods.dates, 3), '3 Datteln');
      expect(FuelMeals.amountText(FuelFoods.appleJuice, 2), '2 Gläser (250 ml) Apfelsaft');
      expect(FuelMeals.amountText(FuelFoods.honey, 1.5), '1,5 EL Honig');
    });
  });

  group('10.2 Vorschläge für vorher und danach', () {
    test('Zeitpunkt → Art der Mahlzeit', () {
      final plan = FuelPlanner.plan(halfMarathon.copyWith(caffeine: true));
      expect(
        [for (final s in plan.pre) FuelMeals.slotOf(s)],
        [
          FuelMealSlot.meal,
          FuelMealSlot.snack,
          null, // Koffein
          FuelMealSlot.booster,
        ],
      );
      expect(FuelMeals.slotOf(plan.post.single), FuelMealSlot.post);
      final rapid = FuelPlanner.plan(halfMarathon.copyWith(hoursUntilNext: () => 6));
      expect(FuelMeals.slotOf(rapid.post[1]), FuelMealSlot.refuel);
      expect(FuelMeals.slotOf(plan.intra.first), isNull);
    });

    test('Mahlzeit 3–4 h vorher: drei Vorschläge, alle auf ±15 % genau, mit Protein', () {
      final meal = step(FuelPhase.pre, -210);
      final suggestions = FuelMeals.suggest(meal);
      expect(suggestions.length, 3);
      for (final x in suggestions) {
        expect(x.covers, isTrue, reason: x.text);
        expect(x.amounts.protein, greaterThanOrEqualTo(meal.amounts.protein * 0.9), reason: x.text);
        expect(x.isComplete, isTrue);
      }
    });

    test('Gleichmäßig verteilt statt einer Zutat bis zum Maximum', () {
      final toast = FuelMeals.templates.firstWhere((t) => t.id == 'toastHoney');
      final x = FuelMeals.compose(toast, const FuelAmounts(carbs: 120));
      expect(x.portions[FuelFoods.toast], greaterThanOrEqualTo(3));
      expect(x.portions[FuelFoods.honey], lessThanOrEqualTo(3));
      expect(x.carbCoverage, closeTo(1, 0.15));
    });

    test('Snack, schnelle Kohlenhydrate und danach', () {
      for (final minute in [-90, -20]) {
        final x = FuelMeals.suggest(step(FuelPhase.pre, minute)).first;
        expect(x.covers, isTrue, reason: '$minute: ${x.text}');
      }
      final booster = FuelMeals.suggest(step(FuelPhase.pre, -20));
      expect(booster.map((x) => x.text), contains('1 Banane'));
      final post = FuelMeals.suggest(step(FuelPhase.post, 0));
      expect(post.every((x) => x.covers && (x.proteinCoverage ?? 0) >= 0.9), isTrue);
    });

    test('Nur mit dem, was zu Hause ist: annähernd, ehrlich mit Prozent', () {
      final meal = step(FuelPhase.pre, -210);
      final best = FuelMeals.suggest(meal, home: {'toast', 'banana', 'milk'}).first;
      expect(best.template.name, 'Aus dem, was du da hast');
      expect(best.missing, isEmpty);
      expect(best.portions.keys, unorderedEquals([FuelFoods.toast, FuelFoods.banana, FuelFoods.milk]));
      expect(best.carbCoverage, closeTo(0.8, 0.05));
      expect(best.covers, isFalse);
      // Nichts Passendes da: der beste (schlechte) Vorschlag bleibt, damit die Lücke sichtbar ist.
      expect(FuelMeals.suggest(meal, home: {'chicken'}).length, 1);
    });

    test('Tagebuch-Positionen eines Vorschlags mit BLS-Werten', () {
      final x = FuelMeals.suggest(step(FuelPhase.pre, -90)).first;
      final items = x.items;
      expect(items.every((item) => item.blsCode != null), isTrue);
      expect(NutritionSummary.totals(items)[Nutrient.carbs], closeTo(x.amounts.carbs, 0.5));
    });
  });

  group('10.3 Alltag unterwegs und Einnahme', () {
    test('Übliche Snacks je Sportart, Getränk zuerst', () {
      for (final sport in FuelSport.values) {
        final snacks = FuelSnacks.choose(sport);
        expect(snacks.first, FuelSnacks.spritzer, reason: '$sport');
      }
      expect(FuelSnacks.choose(FuelSport.run).any((x) => x.heavy), isFalse);
    });

    test('Apfelschorle mit Salz: Werte aus Saftschorle und Salz', () {
      final product = FuelSnacks.spritzer.product;
      expect((product.isDrink, product.volumeMilliliters), (true, 500.0));
      expect(product.carbs, closeTo(30.7, 0.05));
      expect(product.sodium, closeTo(25 + 381.4, 1));
      expect(FuelSnacks.spritzer.availableWith({'appleSpritzer'}), isTrue); // Salz hat jeder
      expect(FuelSnacks.jamToast.availableWith({'toast'}), isFalse);
    });

    test('Rad 3 h nur mit Alltagslebensmitteln: Ziel getroffen, feste Kost zuerst', () {
      const bike = FuelScenario(
        sport: FuelSport.bike,
        minutes: 180,
        weightKilograms: 70,
        intensity: FuelIntensity.tempo,
      );
      final plan = FuelPlanner.plan(bike, setup: [for (final x in FuelSnacks.choose(FuelSport.bike)) x.product]);
      expect(plan.carbCoverage, closeTo(1, 0.1));
      expect(plan.fluidCoverage, closeTo(1, 0.1));
      final firstHalf = plan.intra.where((s) => s.minute < 90).expand((s) => s.portions).map((p) => p.product);
      final secondHalf = plan.intra.where((s) => s.minute >= 90).expand((s) => s.portions).map((p) => p.product);
      expect(firstHalf.where((p) => p.kind == FuelProductKind.food), isNotEmpty);
      expect(secondHalf.where((p) => p.kind == FuelProductKind.food), isEmpty);
    });

    test('Laufen: nichts Schweres, auch wenn gewählt', () {
      final plan = FuelPlanner.plan(halfMarathon, setup: [FuelSnacks.banana.product, FuelSnacks.gummies.product]);
      final used = plan.intra.expand((s) => s.portions).map((p) => p.product.id).toSet();
      expect(used, {FuelSnacks.gummies.productId});
    });

    test('Alltags-Snacks im Tagebuch als einzelne BLS-Lebensmittel', () {
      const bike = FuelScenario(sport: FuelSport.bike, minutes: 120, weightKilograms: 70);
      final plan = FuelPlanner.plan(bike, setup: [FuelSnacks.spritzer.product, FuelSnacks.jamToast.product]);
      final intra = FuelDiary.entry(plan, FuelPhase.intra)!;
      final names = intra.items.map((item) => item.name).toSet();
      expect(names, containsAll(['Apfelschorle', 'Speisesalz', 'Toastbrot', 'Konfitüre']));
      expect(intra.totals[Nutrient.carbs], closeTo(plan.intraDelivered.carbs, 1));
    });

    test('Tipps je Produkt, Sportart und Phase', () {
      expect(FuelHowTo.product(FuelProducts.classicGel), contains('nachspülen'));
      expect(FuelHowTo.product(FuelSnacks.dates.product), FuelSnacks.dates.tip);
      expect(FuelHowTo.sport(FuelSport.bike), contains('Feste Kost in der ersten Hälfte'));
      expect(FuelHowTo.phase(FuelPhase.pre, halfMarathon).length, 2);
      expect(FuelHowTo.phase(FuelPhase.intra, halfMarathon).single, FuelHowTo.sport(FuelSport.run));
      for (final kind in FuelProductKind.values) {
        final product = FuelProduct(id: 'x', name: 'x', kind: kind, carbs: 20, volumeMilliliters: 500);
        expect(FuelHowTo.product(product), isNotEmpty);
      }
    });
  });

  group('11 Vorrat', () {
    test('Vorrat zuerst, bald ablaufendes zuerst; Packliste mit Vorrat und Einkauf', () {
      final plan = FuelPlanner.plan(
        halfMarathon,
        setup: [FuelProducts.highCarbGel, FuelProducts.classicGel],
        stock: {'builtin.gel': 4},
        bestBefore: {'builtin.gel': const CalendarDay(2026, 12, 20)},
      );
      final firstFour = plan.intra.expand((s) => s.portions).take(4).map((p) => p.product);
      expect(firstFour.every((p) => p == FuelProducts.classicGel), isTrue);
      final classic = plan.packing.firstWhere((item) => item.product == FuelProducts.classicGel);
      expect((classic.inStock, classic.fromStock), (4.0, 4));
      expect(
        classic.stockLine,
        classic.toBuy == 0 ? 'alles aus dem Vorrat' : '4 aus dem Vorrat, ${classic.toBuy} kaufen',
      );
      expect(plan.infos.any((n) => n.text.contains('haltbar bis 20.12.2026')), isTrue);
    });

    test('Ohne Vorrat keine Vorrats-Zeile, Vorrat reicht: „alles aus dem Vorrat“', () {
      final none = FuelPlanner.plan(halfMarathon, setup: [FuelProducts.classicGel]);
      expect(none.packing.single.stockLine, isNull);
      final plenty = FuelPlanner.plan(halfMarathon, setup: [FuelProducts.classicGel], stock: {'builtin.gel': 20});
      expect(plenty.packing.single.stockLine, 'alles aus dem Vorrat');
      expect(plenty.infos.any((n) => n.text.startsWith('Vorrat reicht nicht')), isFalse);
    });

    test('Bibliothek: setzen, abbuchen, zurückbuchen, ablaufen, JSON', () {
      final library = FuelLibrary(username: 'anna')
        ..setStock('builtin.gel', const FuelStock(count: 6, bestBefore: CalendarDay(2026, 12, 1)))
        ..setStock('builtin.bar', const FuelStock(count: 2, bestBefore: CalendarDay(2026, 11, 1)));
      const day = CalendarDay(2026, 11, 23);
      expect(library.usableStock(day), {'builtin.gel': 6.0});
      expect(library.expired(day).single, FuelProducts.bar);
      expect(library.bestBefore(day), {'builtin.gel': const CalendarDay(2026, 12, 1)});
      library.consume({'builtin.gel': 4});
      expect(library.stock['builtin.gel']!.count, 2);
      library.consume({'builtin.gel': -4});
      expect(library.stock['builtin.gel']!.count, 6);
      library.consume({'builtin.gel': 10});
      expect(library.stock['builtin.gel']!.count, 0);
      expect(library.usableStock(day).containsKey('builtin.gel'), isFalse);
      library.consume({'builtin.gel': -2});
      expect(library.stock['builtin.gel']!.bestBefore, const CalendarDay(2026, 12, 1)); // MHD bleibt
      library.setStock('builtin.gel', const FuelStock(count: 3));
      final back = FuelLibrary.fromJson(jsonDecode(jsonEncode(library.toJson())), username: 'anna')!;
      expect(back.stock['builtin.gel']!.count, 3);
      expect(back.stock['builtin.bar']!.bestBefore, const CalendarDay(2026, 11, 1));
      expect(const FuelStock(count: 1, bestBefore: CalendarDay(2026, 12, 1)).expiresSoon(day), isTrue);
    });

    test('Plan und Profil merken Alltag, Vorschläge, Vorrat zuerst und „zu Hause“', () {
      final plan = SavedFuelPlan(
        id: 'p',
        scenario: halfMarathon,
        productIDs: const [],
        savedAt: DateTime.utc(2026, 11),
        everyday: true,
        mealChoices: const {'pre:-210': 'porridge'},
        consumedStock: const {'builtin.gel': 5},
      );
      final back = SavedFuelPlan.fromJson(jsonDecode(jsonEncode(plan.toJson())))!;
      expect(back.everyday, isTrue);
      expect(back.mealChoices, {'pre:-210': 'porridge'});
      expect(back.consumedStock, {'builtin.gel': 5.0});
      expect(back.unlogged().everyday, isTrue);
      const profile = FuelProfile(useStockFirst: false, home: ['toast', 'banana'], onlyHome: true);
      final restored = FuelProfile.fromJson(jsonDecode(jsonEncode(profile.toJson())));
      expect(restored.useStockFirst, isFalse);
      expect(restored.home, ['toast', 'banana']);
      expect(restored.homeFilter, {'toast', 'banana'});
      expect(const FuelProfile().homeFilter, isNull);
    });
  });
}

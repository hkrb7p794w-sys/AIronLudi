// Port von QuickLogTests, MealLibraryTests (ohne den Rezept-Fall, folgt mit `OwnRecipe`), MealShareTests,
// NutritionCheckInTests, ExpenditureTests, WeightForecastTests, MealReminderTests, NutritionDashboardTests und dem
// Verbrauchs-Test aus GoalGuardTests.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

MealItem item(String name, double grams, {double kcal = 100}) => MealItem(
  name: name,
  grams: grams,
  source: MealItemSource.manual,
  per100g: NutrientValues({Nutrient.kcal: kcal, Nutrient.protein: 10}),
);

List<double> grams(List<MealItem> items) => [for (final item in items) item.grams];

void main() {
  group('Schnell erfassen', () {
    const today = CalendarDay(2026, 10, 28);
    MealEntry entry(int daysAgo, MealCategory category, List<MealItem> items, {String title = 'x'}) => MealEntry(
      day: today.adding(-daysAgo),
      date: DateTime.fromMillisecondsSinceEpoch((1000000 - daysAgo * 86400) * 1000, isUtc: true),
      category: category,
      title: title,
      items: items,
    );

    test('häufige Mahlzeiten je Kategorie', () {
      final oats = [item('Haferflocken', 60), item('Milch', 200)];
      final skyr = [item('Skyr', 250)];
      final entries = [
        entry(1, MealCategory.breakfast, oats, title: 'Porridge'),
        entry(2, MealCategory.breakfast, [item('Milch', 198), item('Haferflocken', 58)]),
        entry(3, MealCategory.breakfast, skyr),
        entry(4, MealCategory.lunch, skyr),
        entry(90, MealCategory.breakfast, skyr),
      ];
      final result = MealSuggestions.frequent(entries, category: MealCategory.breakfast, today: today);
      expect(result.map((suggestion) => suggestion.count), [2, 1]);
      expect(result.first.title, 'Porridge');
      expect(result.first.kilocalories, 260);

      // Heute schon Porridge gegessen: nicht noch einmal vorschlagen.
      final withToday = [...entries, entry(0, MealCategory.breakfast, oats)];
      expect(MealSuggestions.frequent(withToday, category: MealCategory.breakfast, today: today).map((s) => s.count), [
        1,
      ]);
      expect(
        MealSuggestions.yesterday(entries, category: MealCategory.breakfast, today: today).first.title,
        'Porridge',
      );
      expect(MealSuggestions.yesterday(entries, category: MealCategory.dinner, today: today), isEmpty);
    });

    test('Suche findet Umlaute, Wortanfänge zuerst', () {
      final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final candidates = [
        FoodSearchCandidate(id: '1', title: 'Bircher Müsli', useCount: 9, lastUsed: now),
        FoodSearchCandidate(id: '2', title: 'Müsliriegel', useCount: 1, lastUsed: now),
        FoodSearchCandidate(id: '3', title: 'Skyr Natur', useCount: 20, lastUsed: now),
      ];
      List<String> ids(String query) => [for (final c in FoodSearch.rank(candidates, query: query)) c.id];
      expect(ids('muesli'), ['2', '1']);
      expect(ids('MÜSLI birch'), ['1']);
      expect(ids(' '), isEmpty);
    });

    test('Budget-Zeilen und Schnell-Einträge', () {
      final targets = NutrientValues({Nutrient.kcal: 2600, Nutrient.protein: 140, Nutrient.sugar: 50});
      final totals = NutrientValues({Nutrient.kcal: 1450, Nutrient.protein: 160, Nutrient.sugar: 60});
      final kcal = NutritionBudget.line(Nutrient.kcal, targets: targets, totals: totals)!;
      expect(kcal.remaining, 1150);
      expect(kcal.isOver, isFalse);
      final protein = NutritionBudget.line(Nutrient.protein, targets: targets, totals: totals)!;
      expect(NutritionBudget.remainingText(protein), '20 g drüber');
      expect(protein.isOver, isFalse);
      expect(NutritionBudget.line(Nutrient.sugar, targets: targets, totals: totals)?.isOver, isTrue);
      expect(NutritionBudget.line(Nutrient.fat, targets: targets, totals: totals), isNull);

      final quick = QuickMealItem.quick(kilocalories: 800, protein: 40);
      expect(quick.amounts[Nutrient.kcal], 800);
      expect(quick.amounts[Nutrient.protein], 40);
      expect(quick.amounts[Nutrient.fat], isNull);
      expect(quick.isQuickEstimate, isTrue);
      expect(MealItem.water(milliliters: 250).amounts[Nutrient.water], 250);
    });
  });

  group('Favoriten und Portionen', () {
    const today = CalendarDay(2026, 11, 2);
    MealItem food(String name, double grams) => item(name, grams, kcal: 200);
    MealEntry entry(
      String title,
      List<MealItem> items, {
      required int daysAgo,
      MealCategory category = MealCategory.lunch,
    }) {
      final day = today.adding(-daysAgo);
      return MealEntry(day: day, date: day.referenceDate, category: category, title: title, items: items);
    }

    test('Portion rechnet von der ursprünglichen Menge und stellt sie wieder her', () {
      final meal = [food('Curry', 400), food('Reis', 100)];
      final eaten = MealPortion.adjusted(meal, 0.75);
      expect(grams(eaten), [300, 75]);
      expect(eaten.map((item) => item.plannedGrams), [400, 100]);
      expect(NutritionSummary.totals(eaten)[Nutrient.kcal], 750);
      expect(MealPortion.eatenFraction(eaten), 0.75);
      expect(MealPortion.label(eaten), '75 % von 500 g');
      // Zweite Anpassung rechnet von der ursprünglichen Menge, nicht von 75 %.
      final half = MealPortion.adjusted(eaten, 0.5);
      expect(grams(half), [200, 50]);
      // 100 % stellt den Ausgangszustand her.
      expect(MealPortion.adjusted(half, 1), meal);
      expect(MealPortion.eatenFraction(meal), 1);
    });

    test('Favorit speichert die ursprüngliche Menge', () {
      final eaten = MealPortion.adjusted([food('Chili', 250)], 0.5);
      final favorite = FavoriteMeal(title: 'Chili', items: eaten, created: DateTime.utc(2026, 11, 2, 12));
      expect(favorite.items[0].grams, 250);
      expect(favorite.items[0].plannedGrams, isNull);
      expect(MealShortcuts.favorite(eaten, favorites: [favorite])?.id, favorite.id);
      final decoded = FavoriteMeal.fromJson(jsonDecode(jsonEncode(favorite.toJson())));
      expect(decoded, favorite);
    });

    test('zuletzt und häufig', () {
      final bowl = [food('Haferflocken', 60), food('Milch', 200)];
      final pasta = [food('Nudeln', 250)];
      final entries = [
        entry('Porridge', bowl, daysAgo: 0, category: MealCategory.breakfast),
        entry('Porridge', bowl, daysAgo: 1, category: MealCategory.breakfast),
        entry('Pasta', pasta, daysAgo: 2),
        entry('Porridge halb', MealPortion.adjusted(bowl, 0.5), daysAgo: 3, category: MealCategory.breakfast),
        entry('Leer', [], daysAgo: 0),
      ];
      expect(MealShortcuts.recent(entries).map((entry) => entry.title), ['Porridge', 'Pasta']);
      final frequent = MealShortcuts.frequent(entries, today: today);
      expect(frequent.map((suggestion) => suggestion.title), ['Porridge']);
      expect(frequent.first.count, 2);
    });

    test('alte Positionen ohne plannedGrams', () {
      final json = food('Apfel', 150).toJson()..remove('plannedGrams');
      final decoded = MealItem.fromJson(jsonDecode(jsonEncode(json)))!;
      expect(decoded.plannedGrams, isNull);
      expect(decoded.grams, 150);
    });
  });

  group('Mahlzeit teilen', () {
    test('Hin und zurück mit Mengen und Nährwerten', () {
      final rice = MealItem(
        name: 'Reis',
        grams: 200,
        source: MealItemSource.bls,
        per100g: NutrientValues({Nutrient.kcal: 130, Nutrient.protein: 2.7}),
        amountText: '1 Portion',
      );
      final chicken = MealItem(
        name: 'Hähnchen',
        grams: 150,
        source: MealItemSource.ai,
        per100g: NutrientValues({Nutrient.kcal: 110}),
      );
      // Nur 50 % gegessen – geteilt wird die ganze Mahlzeit.
      final eaten = MealPortion.adjusted([rice, chicken], 0.5);
      final shared = SharedMeal(title: 'Reis mit Hähnchen', items: eaten);
      final decoded = SharedMeal.fromJson(jsonDecode(jsonEncode(shared.toJson())))!;
      expect(decoded, shared);
      final items = decoded.mealItems;
      expect(grams(items), [200, 150]);
      expect(items[0].source, MealItemSource.bls);
      expect(items[0].per100g[Nutrient.protein], 2.7);
      expect(items[0].amountText, '1 Portion');
      expect(items.every((item) => item.plannedGrams == null), isTrue);
      expect({for (final i in items) i.id}.intersection({for (final i in eaten) i.id}), isEmpty);
      expect(decoded.kilocalories, 425);
    });

    test('unbekannte Herkunft und Nährstoffe fallen weg', () {
      const json =
          '{"title": "X", "items": [{"name": "A", "grams": 10, "isDrink": false, "source": "fremd", '
          '"per100g": {"kcal": 50, "zauber": 1}}]}';
      final meal = SharedMeal.fromJson(jsonDecode(json))!;
      expect(meal.mealItems[0].source, MealItemSource.manual);
      expect(meal.mealItems[0].per100g.values.length, 1);
    });

    test('Codes aus Links und Text', () {
      expect(MealShare.code('coach://meal/abcdefgh23'), 'abcdefgh23');
      expect(MealShare.code('https://coach-ai.example.workers.dev/m/abcdefgh23'), 'abcdefgh23');
      expect(MealShare.code('  ABCDEFGH23 '), 'abcdefgh23');
      expect(MealShare.code('coach://join?code=x'), isNull);
      expect(MealShare.code('abc'), isNull);
      final text = MealShare.message(
        title: 'Bowl',
        kilocalories: 512.4,
        link: Uri.parse('https://w.dev/m/abcdefgh23'),
        code: 'abcdefgh23',
      );
      expect(text, contains('512 kcal'));
      expect(text, contains('https://w.dev/m/abcdefgh23'));
    });
  });

  group('Ernährungs-Check-in', () {
    /// Mittwoch, 11.11.2026; Montag dieser Woche ist der 9.11.
    const today = CalendarDay(2026, 11, 11);

    test('einmal pro Woche mit Daten fällig', () {
      final data = [today.adding(-2)];
      expect(NutritionCheckIn.isDue(today: today, last: null, withheld: false, weighIns: data, mealDays: []), isTrue);
      // Letzte Woche erledigt → wieder fällig.
      expect(
        NutritionCheckIn.isDue(today: today, last: today.adding(-5), withheld: false, weighIns: data, mealDays: []),
        isTrue,
      );
      // Am Montag dieser Woche erledigt → nicht mehr.
      expect(
        NutritionCheckIn.isDue(
          today: today,
          last: const CalendarDay(2026, 11, 9),
          withheld: false,
          weighIns: data,
          mealDays: [],
        ),
        isFalse,
      );
    });

    test('nicht fällig ohne Daten oder mit Schutzgrenze', () {
      expect(NutritionCheckIn.isDue(today: today, last: null, withheld: false, weighIns: [], mealDays: []), isFalse);
      expect(
        NutritionCheckIn.isDue(today: today, last: null, withheld: false, weighIns: [today.adding(-20)], mealDays: []),
        isFalse,
      );
      expect(
        NutritionCheckIn.isDue(today: today, last: null, withheld: true, weighIns: [today], mealDays: [today]),
        isFalse,
      );
      expect(
        NutritionCheckIn.isDue(today: today, last: null, withheld: false, weighIns: [], mealDays: [today]),
        isTrue,
      );
    });

    test('alte Einstellungen ohne Check-in', () {
      final settings = NutritionSettings.fromJson(<String, Object?>{});
      expect(settings.lastCheckInDay, isNull);
      settings.lastCheckInDay = today;
      expect(NutritionSettings.fromJson(jsonDecode(jsonEncode(settings.toJson()))).lastCheckInDay, today);
    });
  });

  group('Verbrauch', () {
    const today = CalendarDay(2026, 11, 30);
    List<WeightEntry> weights({required double start, required double perWeek}) => [
      for (var back = 1; back <= 28; back++)
        WeightEntry(
          day: today.adding(-back),
          kilograms: start + perWeek * (28 - back) / 7 + (back.isEven ? 0.2 : -0.2),
          source: WeightSource.manual,
        ),
    ];
    Map<CalendarDay, double> intake(double kilocalories, {int days = 28}) => {
      for (var back = 1; back <= days; back++) today.adding(-back): kilocalories,
    };
    ExpenditureResult result(double kilocalories) => ExpenditureResult(
      kilocalories: kilocalories,
      averageIntake: kilocalories,
      loggedDays: 20,
      excludedDays: 0,
      kilogramsPerWeek: 0,
      plausible: true,
    );

    test('Defizit zeigt höheren Verbrauch', () {
      // 2.000 kcal gegessen, 0,5 kg pro Woche abgenommen → etwa 2.000 + 0,5 × 7.700 / 7 = 2.550 kcal.
      final value = Expenditure.estimate(
        intake: intake(2000),
        weights: weights(start: 80, perWeek: -0.5),
        today: today,
        basalMetabolicRate: 1700,
      )!;
      expect((value.kilocalories - 2550).abs(), lessThanOrEqualTo(40));
      expect(value.plausible, isTrue);
      expect(value.loggedDays, 28);
    });

    test('unvollständige Tage fallen weg', () {
      final days = intake(2400);
      for (final back in [3, 9, 15]) {
        days[today.adding(-back)] = 600;
      }
      final value = Expenditure.estimate(
        intake: days,
        weights: weights(start: 70, perWeek: 0),
        today: today,
        basalMetabolicRate: 1500,
      )!;
      expect(value.excludedDays, 3);
      expect((value.averageIntake - 2400).abs(), lessThan(1));
    });

    test('braucht genug Tage und Wägungen', () {
      expect(
        Expenditure.estimate(
          intake: intake(2000, days: 10),
          weights: weights(start: 80, perWeek: -0.5),
          today: today,
          basalMetabolicRate: 1700,
        ),
        isNull,
      );
      expect(Expenditure.estimate(intake: intake(2000), weights: [], today: today, basalMetabolicRate: 1700), isNull);
    });

    test('unplausibel: keine Anpassung', () {
      // 900 kcal erfasst bei gleichem Gewicht: fast sicher Lücken beim Erfassen.
      final value = Expenditure.estimate(
        intake: intake(900),
        weights: weights(start: 80, perWeek: 0),
        today: today,
        basalMetabolicRate: 1700,
      )!;
      expect(value.plausible, isFalse);
      expect(Expenditure.adjustment(value, formulaMaintenance: 2400, current: 0), isNull);
    });

    test('Anpassung gerundet und begrenzt', () {
      expect(Expenditure.adjustment(result(2730), formulaMaintenance: 2500, current: 0), 250);
      expect(Expenditure.adjustment(result(3400), formulaMaintenance: 2500, current: 0), 500);
      expect(Expenditure.adjustment(result(2560), formulaMaintenance: 2500, current: 0), isNull);
      // Schon übernommen: kein erneuter Vorschlag.
      expect(Expenditure.adjustment(result(2730), formulaMaintenance: 2500, current: 250), isNull);
      // Abweichung verschwunden: Anpassung zurücknehmen.
      expect(Expenditure.adjustment(result(2520), formulaMaintenance: 2500, current: 300), 0);
    });

    test('mit Schutzgrenze keine Senkung', () {
      expect(Expenditure.adjustment(result(2000), formulaMaintenance: 2400, current: 0), -400);
      expect(
        Expenditure.adjustment(result(2000), formulaMaintenance: 2400, current: 0, safety: WeightGoalGuard.noDeficit),
        isNull,
      );
      expect(
        Expenditure.adjustment(result(2000), formulaMaintenance: 2400, current: 0, safety: WeightGoalGuard.noTargets),
        isNull,
      );
      expect(
        Expenditure.adjustment(result(2800), formulaMaintenance: 2400, current: 0, safety: WeightGoalGuard.noDeficit),
        400,
      );
    });
  });

  group('Gewichtsprognose', () {
    const today = CalendarDay(2026, 10, 27);

    test('0,5 % pro Woche', () {
      final result = WeightForecast.compute(
        currentKilograms: 90,
        weeklyChangePercent: -0.5,
        heightCentimeters: 180,
        maintenanceKilocalories: 2800,
        target: 85,
        today: today,
      )!;
      expect(result.weeklyKilograms, 0.45);
      expect(result.dailyDeficit, 500);
      expect(result.deficitCapped, isFalse);
      expect(result.points.map((point) => point.weeks), [4, 8, 12]);
      expect(result.points[0].kilograms, 88.2);
      expect(result.points[2].kilograms, 85);
      expect(result.weeksToTarget, 12);
      expect(result.targetDay, today.adding(84));
    });

    test('Defizit höchstens ein Viertel des Bedarfs', () {
      final result = WeightForecast.compute(
        currentKilograms: 120,
        weeklyChangePercent: -1,
        heightCentimeters: 175,
        maintenanceKilocalories: 2400,
        target: null,
        today: today,
      )!;
      expect(result.deficitCapped, isTrue);
      expect(result.dailyDeficit, 600);
      expect(result.weeklyPercent, lessThan(1));
    });

    test('nie unter die gesunde Untergrenze', () {
      final result = WeightForecast.compute(
        currentKilograms: 62,
        weeklyChangePercent: -1,
        heightCentimeters: 180,
        maintenanceKilocalories: null,
        target: 50,
        today: today,
      )!;
      expect(result.floorKilograms, 60);
      expect(result.target, 60);
      expect(result.points.every((point) => point.kilograms >= 60), isTrue);
      expect(
        WeightForecast.compute(
          currentKilograms: 80,
          weeklyChangePercent: 0.25,
          heightCentimeters: 180,
          maintenanceKilocalories: null,
          target: null,
          today: today,
        ),
        isNull,
      );
    });
  });

  group('Mahlzeit-Erinnerungen', () {
    const today = CalendarDay(2026, 11, 2);
    MealReminderSettings settings() {
      final settings = MealReminderSettings();
      settings
        ..breakfast = settings.breakfast.copyWith(enabled: true)
        ..lunch = settings.lunch.copyWith(enabled: true)
        ..dinner = settings.dinner.copyWith(enabled: true);
      return settings;
    }

    test('überspringt Vergangenes, Erfasstes und Ausgeschaltetes', () {
      // 10:00 Uhr, Mittagessen heute schon erfasst.
      final logged = {MealReminderPlanner.loggedKey(today, MealCategory.lunch)};
      final notes = MealReminderPlanner.meals(settings(), today: today, minutesNow: 600, logged: logged);
      expect(notes.map((note) => note.id), [
        'coach.reminder.meal.2026-11-02.abendessen',
        'coach.reminder.meal.2026-11-03.fruehstueck',
        'coach.reminder.meal.2026-11-03.mittagessen',
        'coach.reminder.meal.2026-11-03.abendessen',
      ]);
      expect(notes.first.hour, 19);
      expect(notes.first.title, 'Abendessen eintragen');
      // Alles aus: keine Mitteilung.
      expect(MealReminderPlanner.meals(MealReminderSettings(), today: today, minutesNow: 0, logged: {}), isEmpty);
    });

    test('geänderte Zeiten und Lesen', () {
      final changed = settings()..dinner = MealReminderSlot(enabled: true, hour: 20, minute: 15);
      final note = MealReminderPlanner.meals(changed, today: today, minutesNow: 1200, logged: {}).first;
      expect((note.hour, note.minute), (20, 15));
      final decoded = MealReminderSettings.fromJson(jsonDecode('{"lunch": {"enabled": true}}'));
      expect(decoded, MealReminderSettings());
      expect(decoded.anyEnabled, isFalse);
      expect(MealReminderSlot(hour: 30, minute: -5).hour, 23);
      expect(MealReminderSettings.fromJson(jsonDecode(jsonEncode(changed.toJson()))), changed);
    });
  });

  group('Ernährungs-Dashboard', () {
    test('Standard, Verschieben, Ausblenden', () {
      final dashboard = NutritionDashboard();
      expect(dashboard.visible.first, NutritionCard.budget);
      expect(dashboard.visible, isNot(contains(NutritionCard.summary)));
      dashboard
        ..setVisible(NutritionCard.summary, visible: true)
        ..move(fromOffsets: {5}, toOffset: 0);
      expect(dashboard.order.first, NutritionCard.meals);
      expect(dashboard.visible, contains(NutritionCard.summary));
      dashboard.setVisible(NutritionCard.nutrients, visible: false);
      expect(dashboard.visible, isNot(contains(NutritionCard.nutrients)));
      expect(dashboard.order.length, NutritionCard.values.length);
    });

    test('unbekannte Karten fallen weg, neue kommen dazu', () {
      const json = '{"order": ["meals", "unbekannt", "meals", "budget"], "hidden": ["water", "x"]}';
      final decoded = NutritionDashboard.fromJson(jsonDecode(json));
      expect(decoded.order.take(2), [NutritionCard.meals, NutritionCard.budget]);
      expect(decoded.order.length, NutritionCard.values.length);
      expect(decoded.hidden, {NutritionCard.water});
      expect(NutritionDashboard.fromJson(jsonDecode(jsonEncode(decoded.toJson()))), decoded);
    });

    test('Kennzahlen der Tagesübersicht', () {
      const summary = NutritionDaySummary(eaten: 1500, goal: 2000, meals: 3);
      expect(summary.remaining, 500);
      expect(summary.percent, 75);
      expect(const NutritionDaySummary(eaten: 100, goal: null, meals: 1).percent, isNull);
    });
  });
}

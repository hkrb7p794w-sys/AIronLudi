// Port von MealPlanningTests, RecipeTests (RecipeRuleTests, RecipePlanTests, RecipeInputTests), StricterRecipeTests
// (SafeguardTests.swift), CookPlanTests und dem Rezept-Fall aus MealLibraryTests.
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Montag, 2.11.2026.
const monday = CalendarDay(2026, 11, 2);

Map<String, Object?> ingredient(String name, {required double grams, required double kcal, double protein = 0}) => {
  'name': name,
  'menge_g': grams,
  'naehrwerte_100g': {'kcal': kcal, 'protein_g': protein},
};

Map<String, Object?> dish(String title, {required String meal, required List<Object?> ingredients}) => {
  'titel': title,
  'mahlzeit': meal,
  'minuten': 15,
  'zubereitung': ['Alles mischen.', 'Servieren.'],
  'zutaten': ingredients,
};

final targets = [
  const RecipeDayTarget(
    day: monday,
    sessions: ['Lockerer Lauf'],
    dayType: DayType.moderate,
    kcal: 2000,
    protein: 120,
    carbs: 250,
    fat: 60,
  ),
  RecipeDayTarget(
    day: monday.adding(1),
    sessions: const [],
    dayType: DayType.restDay,
    kcal: 1800,
    protein: 120,
    carbs: 180,
    fat: 60,
  ),
];

JsonValue planOutput(List<(CalendarDay, List<Object?>)> days) => JsonValue({
  'tage': [
    for (final (day, dishes) in days) {'datum': day.iso, 'gerichte': dishes},
  ],
});

MealItem manual(String name, double grams, Map<Nutrient, double> values) =>
    MealItem(name: name, grams: grams, source: MealItemSource.manual, per100g: NutrientValues(values));

List<String> violations(String name, Diet diet, [Set<Allergen> allergens = const {}]) =>
    RecipePlanner.violations(name, diet: diet, allergens: allergens);

void main() {
  // In Swift ist der BLS immer eingebunden; ohne ihn fehlten Werte, die die KI nicht liefert.
  setUpAll(() => BLS.load(File('assets/bls.tsv').readAsStringSync()));

  group('Mahlzeitenplanung', () {
    const today = CalendarDay(2026, 10, 28);
    Map<String, Object?> food(String name, double grams, {required double kcal, double protein = 10}) => {
      'name': name,
      'menge_g': grams,
      'naehrwerte_100g': {'kcal': kcal, 'protein_g': protein},
    };

    test('„Was esse ich jetzt?“ skaliert und filtert', () {
      expect(MealNow.targetKilocalories(1400), 900);
      expect(MealNow.targetKilocalories(500), 500);
      expect(MealNow.targetKilocalories(100), isNull);
      final output = JsonValue({
        'gerichte': [
          {
            'titel': 'Linsen-Bowl',
            'mahlzeit': 'abendessen',
            'zutaten': [food('Testlinsen', 100, kcal: 300), food('Testspinat', 100, kcal: 20)],
          },
          {
            'titel': 'Hähnchen-Reis',
            'mahlzeit': 'abendessen',
            'zutaten': [food('Hähnchenbrust', 150, kcal: 110, protein: 23)],
          },
        ],
      });
      final result = MealNow.suggestions(output, targetKilocalories: 480, diet: Diet.vegetarian, allergens: {});
      expect(result.recipes.map((recipe) => recipe.title), ['Linsen-Bowl']);
      expect(result.notes.first, contains('Hähnchen-Reis'));
      // 320 kcal → 480 kcal: Faktor 1,5, auf 5 g gerundet (Testnamen, damit kein BLS-Eintrag die Werte ersetzt).
      expect(result.recipes.first.ingredients.map((item) => item.grams), [150, 150]);
      final input = MealNow.input(
        remaining: NutrientValues({Nutrient.kcal: 1800, Nutrient.protein: 90}),
        category: MealCategory.dinner,
        diet: Diet.vegetarian,
        preferences: RecipePreferences(),
        pantry: ['Linsen'],
        favorites: [],
      );
      expect(input['kcal'], 900);
      expect(input['protein_g'], 45);
      expect(input['pantry'], ['Linsen']);
    });

    test('eigenes Rezept: Portionen und Vorrat', () {
      final rice = manual('Reis', 400, {Nutrient.kcal: 350});
      final beans = manual('Bohnen', 400, {Nutrient.kcal: 100});
      final chili = OwnRecipe(
        name: 'Chili',
        ingredients: [rice, beans],
        cookedGrams: 2000,
        portions: 4,
        remainingPortions: 4,
      );
      expect(chili.totals[Nutrient.kcal], 1800);
      final portion = chili.item();
      expect(portion.grams, 500);
      expect(portion.amounts[Nutrient.kcal], 450);
      expect(portion.portion, const Portion('Portion', 500));
      expect(chili.item(grams: 350).amounts[Nutrient.kcal], 315);
      chili.consume(750);
      expect(chili.remainingPortions, 2.5);
      expect(OwnRecipe.fromJson(jsonDecode(jsonEncode(chili.toJson()))), chili);
    });

    test('Rezept und Favorit bleiben unverändert', () {
      final recipe = OwnRecipe(
        name: 'Chili',
        ingredients: [
          manual('Bohnen', 300, {Nutrient.kcal: 200, Nutrient.protein: 10}),
          manual('Tomaten', 200, {Nutrient.kcal: 200, Nutrient.protein: 10}),
        ],
        portions: 2,
      );
      final logged = recipe.item();
      final eaten = MealPortion.adjusted([logged], 0.5);
      expect(recipe.ingredients.map((item) => item.grams), [300, 200]);
      expect(recipe.item().grams, 250);
      expect(eaten[0].grams, 125);
      // Favorit speichert die ursprüngliche Menge.
      final favorite = FavoriteMeal(title: 'Chili', items: eaten);
      expect(favorite.items[0].grams, 250);
      expect(favorite.items[0].plannedGrams, isNull);
      expect(MealShortcuts.favorite(eaten, favorites: [favorite])?.id, favorite.id);
    });

    test('Wochenübersicht zählt nur Tage mit Einträgen', () {
      const start = CalendarDay(2026, 10, 26);
      final item = manual('x', 100, {Nutrient.kcal: 2000, Nutrient.protein: 100});
      final now = DateTime.now();
      final entries = [
        MealEntry(day: start, date: now, category: MealCategory.lunch, title: 'x', items: [item]),
        MealEntry(
          day: start.adding(1),
          date: now,
          category: MealCategory.lunch,
          title: 'x',
          items: [item.scaledBy(1.2)],
        ),
      ];
      final summary = NutritionWeek.summary(
        entries: entries,
        monday: start,
        targets: {
          start: NutrientValues({Nutrient.kcal: 2200}),
          start.adding(1): NutrientValues({Nutrient.kcal: 2600}),
        },
        trainedDays: {start},
        today: today,
      );
      expect(summary.days.length, 3);
      expect(summary.days[0].trained, isTrue);
      expect(summary.days[2].logged, isFalse);
      expect(summary.averageKilocalories, 2200);
      expect(summary.averageTargetKilocalories, 2400);
      expect(summary.averageProtein, 110);
    });

    test('Abteilungen und Abend-Erinnerung', () {
      expect(ShoppingAisle.of(name: 'Spinat', group: 'gemuese'), ShoppingAisle.produce);
      expect(ShoppingAisle.of(name: 'Vollkornbrot', group: 'vollkorn'), ShoppingAisle.bakery);
      expect(ShoppingAisle.of(name: 'Olivenöl', group: null), ShoppingAisle.spices);
      expect(ShoppingAisle.of(name: 'Skyr', group: 'milch'), ShoppingAisle.cooled);
      expect(ShoppingAisle.of(name: 'Irgendwas', group: null), ShoppingAisle.other);
      final notes = NutritionReviewReminder.nutritionReview(today: today, minutesNow: 21 * 60, days: 3);
      expect(notes.map((note) => note.day), [today.adding(1), today.adding(2)]);
      expect(notes.first.hour, 20);
      expect(notes.first.kind, ScheduledNoteKind.nutritionReview);
    });
  });

  group('Rezeptregeln', () {
    test('Ernährungsweise', () {
      expect(violations('Hähnchenbrust', Diet.vegetarian), ['Fleisch']);
      expect(violations('Lachsfilet', Diet.pescetarian), isEmpty);
      expect(violations('Lachsfilet', Diet.vegetarian), ['Fisch']);
      expect(violations('Sojahack', Diet.vegan), isEmpty);
      expect(violations('Hühnerei', Diet.vegan), ['Ei']);
      expect(violations('Naturreis', Diet.vegan), isEmpty);
      expect(violations('Haferbrei', Diet.vegan), isEmpty);
      expect(violations('Skyr', Diet.vegan), ['Milchprodukte']);
      expect(violations('Haferdrink', Diet.vegan), isEmpty);
      expect(violations('Sojajoghurt', Diet.vegan), isEmpty);
      expect(violations('Erdnussbutter', Diet.vegan), isEmpty);
      expect(violations('Vegane Bratwurst', Diet.vegan), isEmpty);
      expect(violations('Honig', Diet.vegan), ['Honig']);
      expect(violations('Rinderhack', Diet.omnivore), isEmpty);
    });

    test('Allergene', () {
      expect(violations('Vollkornnudeln', Diet.omnivore, {Allergen.gluten}), ['Gluten']);
      expect(violations('Buchweizen', Diet.omnivore, {Allergen.gluten}), isEmpty);
      expect(violations('Erdnussbutter', Diet.omnivore, {Allergen.nuts}), isEmpty);
      expect(violations('Erdnussbutter', Diet.omnivore, {Allergen.peanuts}), ['Erdnüsse']);
      expect(violations('Walnusskerne', Diet.omnivore, {Allergen.nuts}), ['Schalenfrüchte (Nüsse)']);
      expect(violations('Laktosefreie Milch', Diet.omnivore, {Allergen.lactose}), isEmpty);
      expect(violations('Bergkäse', Diet.omnivore, {Allergen.lactose}), ['Laktose / Milch']);
      expect(violations('Tofu natur', Diet.vegan, {Allergen.soy}), ['Soja']);
      expect(violations('Garnelen', Diet.omnivore, {Allergen.shellfish}), ['Krebstiere und Weichtiere']);
      expect(violations('Tahin', Diet.vegan, {Allergen.sesame}), ['Sesam']);
      expect(violations('Spiegelei', Diet.omnivore, {Allergen.egg}), ['Ei']);
    });

    test('versteckte Allergene', () {
      expect(violations('Basilikumpesto', Diet.vegan), ['Milchprodukte']);
      expect(violations('Basilikumpesto', Diet.omnivore, {Allergen.nuts}), ['Schalenfrüchte (Nüsse)']);
      expect(violations('Worcestersauce', Diet.vegetarian), ['Fisch']);
      expect(violations('Mayonnaise', Diet.omnivore, {Allergen.egg}), ['Ei']);
      expect(violations('Sojasauce', Diet.vegan, {Allergen.gluten}), ['Gluten']);
      expect(violations('Vegane Mayonnaise', Diet.vegan), isEmpty);
    });

    test('unstimmige Nährwerte', () {
      bool implausible(Map<Nutrient, double> values) => RecipePlanner.implausible(
        MealItem(name: 'X', grams: 100, source: MealItemSource.ai, per100g: NutrientValues(values)),
      );
      expect(implausible({Nutrient.kcal: 370, Nutrient.protein: 13, Nutrient.carbs: 59, Nutrient.fat: 7}), isFalse);
      expect(implausible({Nutrient.kcal: 1200}), isTrue);
      expect(implausible({Nutrient.kcal: 100, Nutrient.protein: 30, Nutrient.carbs: 30, Nutrient.fat: 10}), isTrue);
      expect(implausible({Nutrient.kcal: 400, Nutrient.protein: 60, Nutrient.carbs: 60}), isTrue);
      expect(implausible({Nutrient.kcal: 25, Nutrient.protein: 1, Nutrient.carbs: 4, Nutrient.fat: 0.2}), isFalse);
    });

    test('Wünsche werden tolerant gelesen', () {
      final decoded = RecipePreferences.fromJson(jsonDecode('{"servings":0,"allergens":["gluten"]}'));
      expect(decoded.servings, 1);
      expect(decoded.allergens, {Allergen.gluten});
      expect(decoded.maxMinutes, 30);
      expect(RecipePreferences.fromJson(jsonDecode(jsonEncode(decoded.toJson()))), decoded);
    });
  });

  group('Wochenrezepte', () {
    test('skaliert aufs Ziel und verwirft Verstöße', () {
      final dishes = [
        dish(
          'Porridge',
          meal: 'fruehstueck',
          ingredients: [ingredient('Haferflocken', grams: 100, kcal: 370, protein: 13)],
        ),
        dish(
          'Linsencurry',
          meal: 'mittagessen',
          ingredients: [ingredient('Rote Linsen', grams: 150, kcal: 340, protein: 25)],
        ),
        dish(
          'Hähnchen-Bowl',
          meal: 'abendessen',
          ingredients: [ingredient('Hähnchenbrust', grams: 200, kcal: 110, protein: 23)],
        ),
      ];
      final plan = RecipePlanner.plan(
        planOutput([(monday, dishes)]),
        targets: targets,
        diet: Diet.vegetarian,
        allergens: {},
        source: 'KI · test',
        created: DateTime.now(),
      )!;
      final day = plan.day(monday)!;
      expect(day.recipes.map((recipe) => recipe.title), ['Porridge', 'Linsencurry']);
      expect(plan.notes, contains('„Hähnchen-Bowl“ verworfen: enthält Fleisch.'));
      expect(plan.notes, contains('Dienstag: keine Rezepte erhalten.'));
      // 370 + 510 = 880 kcal → höchstens ×1,33 → Hinweis auf Abweichung.
      expect(day.scale, 1.33);
      expect(day.recipes.first.ingredients.first.grams, 135);
      expect(plan.notes.any((note) => note.startsWith('Montag: Rezepte ergeben ca.')), isTrue);
      expect(WeeklyRecipePlan.fromJson(jsonDecode(jsonEncode(plan.toJson())))?.days, plan.days);
    });

    test('nah genug: kein Hinweis', () {
      final dishes = [
        dish('Frühstück', meal: 'fruehstueck', ingredients: [ingredient('Haferflocken', grams: 200, kcal: 370)]),
        dish('Mittag', meal: 'mittagessen', ingredients: [ingredient('Nudeln', grams: 300, kcal: 350)]),
        dish('Abend', meal: 'abendessen', ingredients: [ingredient('Kartoffeln', grams: 300, kcal: 77)]),
      ];
      final plan = RecipePlanner.plan(
        planOutput([(monday, dishes)]),
        targets: [targets[0]],
        diet: Diet.omnivore,
        allergens: {},
        source: 'KI',
        created: DateTime.now(),
      )!;
      final kcal = plan.days.first.totals[Nutrient.kcal]!;
      expect((kcal - 2000).abs() / 2000, lessThan(0.05));
      expect(plan.notes, isEmpty);
    });

    test('leere oder kaputte Antworten', () {
      WeeklyRecipePlan? plan(JsonValue output) => RecipePlanner.plan(
        output,
        targets: targets,
        diet: Diet.omnivore,
        allergens: {},
        source: '',
        created: DateTime.now(),
      );
      expect(plan(const JsonValue(<String, Object?>{})), isNull);
      final noNutrients = dish(
        'Leer',
        meal: 'snack',
        ingredients: [
          {'name': 'Unbekannte Zutat', 'menge_g': 150},
        ],
      );
      expect(
        plan(
          planOutput([
            (monday, [noNutrients]),
          ]),
        ),
        isNull,
      );
      // Ohne Nährwerte der KI, aber mit BLS-Eintrag: Werte kommen aus dem BLS.
      final apple = dish(
        'Apfel',
        meal: 'snack',
        ingredients: [
          {'name': 'Apfel', 'menge_g': 150},
        ],
      );
      expect(
        plan(
          planOutput([
            (monday, [apple]),
          ]),
        )?.days.first.recipes.first.ingredients.first.source,
        MealItemSource.bls,
      );
    });

    test('Einkaufsliste über die Woche', () {
      final dishes = [
        dish('A', meal: 'fruehstueck', ingredients: [ingredient('Testflocken', grams: 80, kcal: 370)]),
        dish(
          'B',
          meal: 'snack',
          ingredients: [
            ingredient('testflocken', grams: 40, kcal: 370),
            ingredient('Testbanane', grams: 120, kcal: 90),
          ],
        ),
      ];
      WeeklyRecipePlan planFor(CalendarDay day) => RecipePlanner.plan(
        planOutput([(day, dishes)]),
        targets: [
          RecipeDayTarget(
            day: day,
            sessions: const [],
            dayType: DayType.restDay,
            kcal: 552,
            protein: 0,
            carbs: 0,
            fat: 0,
          ),
        ],
        diet: Diet.omnivore,
        allergens: {},
        source: '',
        created: DateTime.now(),
      )!;
      final plan = planFor(monday);
      final list = RecipePlanner.shoppingList(plan, servings: 2);
      expect(list.map((item) => item.name), ['Testbanane', 'Testflocken']);
      expect(list.last.grams, 240);
      // Einkaufsliste nur für einen Teil des Zeitraums.
      expect(RecipePlanner.shoppingList(plan, servings: 2, from: monday, to: monday), list);
      expect(RecipePlanner.shoppingList(plan, servings: 2, from: monday.adding(1)), isEmpty);
      // Frei gewählter Zeitraum: gleiche Ziele je Tag aus dem Durchschnitt, höchstens 14 Tage.
      final days = RecipePlanner.period(start: monday, days: 3);
      expect(days, [monday, monday.adding(1), monday.adding(2)]);
      expect(RecipePlanner.period(start: monday, days: 40).length, 14);
      expect(RecipePlanner.period(start: monday, days: 0).length, 1);
      const reference = [
        RecipeDayTarget(
          day: monday,
          sessions: ['Lauf'],
          dayType: DayType.hard,
          kcal: 3000,
          protein: 150,
          carbs: 400,
          fat: 80,
        ),
        RecipeDayTarget(
          day: monday,
          sessions: [],
          dayType: DayType.restDay,
          kcal: 2000,
          protein: 150,
          carbs: 200,
          fat: 70,
        ),
        RecipeDayTarget(
          day: monday,
          sessions: [],
          dayType: DayType.restDay,
          kcal: 2200,
          protein: 150,
          carbs: 210,
          fat: 75,
        ),
      ];
      final uniform = RecipePlanner.uniformTargets(days: days, reference: reference);
      expect(uniform.map((target) => target.kcal), [2400, 2400, 2400]);
      expect(uniform.every((t) => t.sessions.isEmpty && t.dayType == DayType.restDay && t.protein == 150), isTrue);
      expect(RecipePlanner.uniformTargets(days: days, reference: []), isEmpty);
      // Fehlende Tage erkennen und nachträglich ergänzen, ohne vorhandene zu verlieren.
      expect(RecipePlanner.missing(uniform, plan: plan).map((t) => t.day), [monday.adding(1), monday.adding(2)]);
      expect(RecipePlanner.missing(uniform, plan: null).length, 3);
      final both = plan.adding(planFor(monday.adding(1)));
      expect(both.days.map((day) => day.day), [monday, monday.adding(1)]);
      expect(RecipePlanner.missing(uniform, plan: both).map((t) => t.day), [monday.adding(2)]);
    });

    test('Lücken nur mit genug Tagen', () {
      final goals = NutrientValues({Nutrient.protein: 120, Nutrient.fiber: 30, Nutrient.iron: 15});
      final day = NutrientValues({Nutrient.protein: 115, Nutrient.fiber: 18, Nutrient.iron: 14});
      expect(RecipePlanner.gaps(dailyTotals: [day, day], targets: goals), isEmpty);
      expect(RecipePlanner.gaps(dailyTotals: [day, day, day], targets: goals), [
        'Ballaststoffe: im Schnitt 18 von 30 g (60 %)',
      ]);
    });

    test('Eingabe trägt Ziele und Wünsche', () {
      final preferences = RecipePreferences(
        allergens: {Allergen.peanuts},
        dislikes: 'Pilze',
        maxMinutes: 20,
        snacks: false,
      );
      final input = JsonValue(
        jsonDecode(
          jsonEncode(
            RecipePlanner.input(
              days: targets,
              preferences: preferences,
              diet: Diet.vegetarian,
              goal: 'Abnehmen',
              gaps: ['Eisen'],
              favorites: ['Skyr'],
            ),
          ),
        ),
      );
      final first = input['days']?.arrayValue?.first;
      expect(first?['datum']?.stringValue, '2026-11-02');
      expect(first?['wochentag']?.stringValue, 'Montag');
      expect(first?['training']?.stringValue, 'Lockerer Lauf');
      expect(first?['kcal']?.doubleValue, 2000);
      expect(input['days']?.arrayValue?.last['training']?.stringValue, 'nicht berücksichtigt');
      expect(input['diet']?.stringValue, 'vegetarisch');
      expect(input['allergens']?.arrayValue?.first.stringValue, 'Erdnüsse');
      expect(input['snacks']?.boolValue, isFalse);
      expect(input['evidence']?.arrayValue?.length, RecipePlanner.evidence.length);
    });
  });

  group('Gemeinsam kochen', () {
    /// Basisportion: 200 g Linsen-Curry (150 kcal je 100 g, 10 g Protein, 20 g KH, 3,3 g Fett) = 300 kcal, 20 g Protein.
    Map<String, Object?> recipeJSON({
      String title = 'Testcurry',
      bool prep = true,
      double fridge = 3,
      bool freezable = true,
      String ingredient = 'Testcurry Zyx',
    }) => {
      'titel': title,
      'minuten': 25,
      'zubereitung': ['Kochen'],
      'zutaten': [
        {
          'name': ingredient,
          'menge_g': 200,
          'menge_text': '200 g',
          'naehrwerte_100g': {'kcal': 150, 'protein_g': 10, 'carbs_g': 20, 'fat_g': 3.3},
        },
      ],
      'vorkochen_geeignet': prep,
      'haltbarkeit_tage': fridge,
      'einfrierbar': freezable,
      'lagerung': 'Luftdicht im Kühlschrank',
      'aufwaermen': 'In der Pfanne',
      'kompromiss': 'Mehr Protein für Person 1, weniger Energie für Person 2.',
    };
    JsonValue output(List<Map<String, Object?>> recipes) => JsonValue({'rezepte': recipes});
    final me = CookPerson(
      id: CookPerson.meID,
      share: CookShare(name: 'Ich', kcal: 2400, protein: 160, carbs: 280, fat: 80, diet: Diet.omnivore),
    );
    final partner = CookPerson(
      id: 'abcdefghij',
      share: CookShare(
        name: 'Lena',
        kcal: 1800,
        protein: 100,
        carbs: 200,
        fat: 60,
        diet: Diet.vegetarian,
        allergens: {Allergen.nuts},
        dislikes: 'Pilze',
      ),
    );
    final created = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);
    ({List<CookPlan> plans, List<String> notes}) plans(
      Map<String, Object?> recipe,
      List<CookPerson> people,
      CookAmount amount,
    ) => CookPlanner.plans(
      output([recipe]),
      people: people,
      meal: MealCategory.dinner,
      amount: amount,
      source: 'KI',
      created: created,
    );
    CookPlan makePlan(List<CookPerson> people, CookAmount amount) => plans(recipeJSON(), people, amount).plans.first;
    CookPortion portionOf(CookPlan plan, CookPerson person) =>
        plan.portions.firstWhere((portion) => portion.person.id == person.id);

    test('Portionen werden aufgeteilt, Tage zählen je Person', () {
      expect(CookPlanner.plates(const CookPortions(4), [me, partner]), {me.id: 2, partner.id: 2});
      expect(CookPlanner.plates(const CookPortions(3), [me, partner]), {me.id: 2, partner.id: 1});
      expect(CookPlanner.plates(const CookDays(3), [me, partner]), {me.id: 3, partner.id: 3});
      expect(CookPlanner.plates(const CookPortions(6), [me]), {me.id: 6});
      expect(CookPlanner.plates(const CookDays(99), [me]), {me.id: CookAmount.maxDays});
    });

    /// Abendessen sind 30 % des Tages: 720 kcal und 540 kcal; die Basisportion hat 300 kcal.
    test('Tellergröße folgt dem Ziel jeder Person', () {
      final result = makePlan([me, partner], const CookPortions(2));
      expect((portionOf(result, me).factor - 1.8).abs(), lessThan(0.001)); // 2,4 wären zu viel: auf 1,8 begrenzt.
      expect((portionOf(result, partner).factor - 1.8).abs(), lessThan(0.001));
      expect((portionOf(result, me).sharePercent - 50).abs(), lessThan(0.1));
    });

    /// Basisportion nah am Ziel: Teller unterscheiden sich im Verhältnis 720 : 540.
    test('Teller unterscheiden sich in der Energie', () {
      final plan = makePlan([me, partner], const CookPortions(2));
      plan.setGrams(400, itemID: plan.base.first.id); // 600 kcal
      final mine = portionOf(plan, me);
      final hers = portionOf(plan, partner);
      expect(((mine.nutrients[Nutrient.kcal] ?? 0) - 720).abs(), lessThan(0.5));
      expect(((hers.nutrients[Nutrient.kcal] ?? 0) - 540).abs(), lessThan(0.5));
      expect((mine.sharePercent - 720.0 / 1260 * 100).abs(), lessThan(0.1));
      expect((mine.grams - 480).abs(), lessThan(0.5));
      expect((hers.grams - 360).abs(), lessThan(0.5));
    });

    /// Ganzes Gericht = Summe aller Teller; die Nährwerte je Teller bleiben beim Hochrechnen gleich.
    test('ganzes Gericht ist die Summe der Teller', () {
      final two = makePlan([me, partner], const CookPortions(2));
      final six = makePlan([me, partner], const CookPortions(6));
      two.setGrams(400, itemID: two.base.first.id);
      six.setGrams(400, itemID: six.base.first.id);
      expect(two.portions.map((p) => p.nutrients), six.portions.map((p) => p.nutrients));
      final sum = six.portions.fold(0.0, (total, p) => total + p.plates * (p.nutrients[Nutrient.kcal] ?? 0));
      expect(((six.wholeNutrients[Nutrient.kcal] ?? 0) - sum).abs(), lessThan(0.5));
      expect(((six.wholeNutrients[Nutrient.kcal] ?? 0) - 3 * (720 + 540)).abs(), lessThan(0.5));
      expect(six.totalIngredients.first.grams, 2520); // 3 × (480 + 360) g
    });

    test('ohne Ziele die Basisportion', () {
      final open = CookPerson(
        id: 'kkkkkkkkkk',
        share: CookShare(name: 'Mia'),
      );
      final portion = makePlan([open], const CookPortions(1)).portions.first;
      expect(portion.factor, 1);
      expect(portion.target, isNull);
    });

    test('Hinweis, wenn Protein fehlt', () {
      final portion = makePlan([me], const CookPortions(1)).portions.first;
      expect(portion.notes.any((note) => note.contains('Protein')), isTrue);
    });

    test('strengste Ernährungsweise und alle Allergene gelten', () {
      expect(CookPlanner.mergedDiet([me, partner]), Diet.vegetarian);
      expect(CookPlanner.mergedAllergens([me, partner]), {Allergen.nuts});
      final result = plans(recipeJSON(ingredient: 'Hähnchenbrust'), [me, partner], const CookPortions(2));
      expect(result.plans, isEmpty);
      expect(result.notes.first, contains('Fleisch'));
    });

    test('Eingabe der KI ohne Namen', () {
      final input = CookPlanner.input(
        people: [me, partner],
        meal: MealCategory.dinner,
        amount: const CookDays(2),
        preferences: RecipePreferences(),
        favorites: [],
      );
      final text = jsonEncode(input);
      expect(text, isNot(contains('Lena')));
      expect(text, contains('Person 2'));
      expect(input['vorkochen'], isTrue);
      expect(input['dislikes'], 'Pilze');
    });

    test('ungeeignet zum Vorkochen wird verworfen', () {
      final result = plans(recipeJSON(prep: false), [me], const CookDays(3));
      expect(result.plans, isEmpty);
      expect(result.notes.first, contains('Vorkochen'));
    });

    test('eine frische Mahlzeit braucht keine Lagerung', () {
      expect(plans(recipeJSON(prep: false, fridge: 0, freezable: false), [me], const CookPortions(1)).plans.length, 1);
    });

    /// Zwei Personen, zwei Teller: Jede Person isst einmal, also keine Lagerung.
    test('gemeinsam gegessene Teller ohne Lagerung', () {
      expect(makePlan([me, partner], const CookPortions(2)).mealsPerPerson, 1);
    });

    test('Lagerung: nach dem Kühlschrank einfrieren', () {
      expect(CookPlanner.storagePlan(meals: 3, fridgeDays: 3, freezable: false), [
        CookStorage.fresh,
        CookStorage.fridge,
        CookStorage.fridge,
      ]);
      expect(CookPlanner.storagePlan(meals: 6, fridgeDays: 3, freezable: true), [
        CookStorage.fresh,
        CookStorage.fridge,
        CookStorage.fridge,
        CookStorage.fridge,
        CookStorage.freezer,
        CookStorage.freezer,
      ]);
      expect(CookPlanner.storagePlan(meals: 5, fridgeDays: 3, freezable: false), isNull);
    });

    /// Sagt die KI 7 Tage, gelten trotzdem höchstens 3.
    test('Haltbarkeit der KI wird begrenzt', () {
      final result = plans(recipeJSON(fridge: 7, freezable: false), [me], const CookDays(5));
      expect(result.plans, isEmpty);
      expect(result.notes.first, contains('hält nicht'));
    });

    test('extreme Haltbarkeit stürzt nicht ab', () {
      expect(
        plans(recipeJSON(fridge: 1e30), [me], const CookDays(2)).plans.first.fridgeDays,
        CookPlanner.maxFridgeDays,
      );
    });

    test('Bearbeiten rechnet neu und behält die letzte Zutat', () {
      final plan = makePlan([me], const CookPortions(1));
      final id = plan.base.first.id;
      plan.remove(itemID: id);
      expect(plan.base.length, 1);
      plan.setGrams(100, itemID: id);
      expect(plan.baseNutrients[Nutrient.kcal], 150);
      expect(CookPlan.fromJson(jsonDecode(jsonEncode(plan.toJson()))), plan);
    });

    List<RecipeDayTarget> week(double kcal) => [
      for (final (offset, value) in [(0, kcal - 200), (1, kcal + 200)])
        RecipeDayTarget(
          day: CalendarDay(2026, 11, 9 + offset),
          sessions: const [],
          dayType: DayType.restDay,
          kcal: value,
          protein: 120,
          carbs: 250,
          fat: 70,
        ),
    ];

    test('Freigabe enthält nur freigegebene Felder', () {
      final fields = CookShareFields(targets: false, dislikes: false);
      final preferences = RecipePreferences(allergens: {Allergen.egg}, dislikes: 'Pilze');
      final share = CookPlanner.share(
        name: ' Lena ',
        week: week(2000),
        diet: Diet.vegan,
        preferences: preferences,
        fields: fields,
        safety: WeightGoalGuard.free,
      );
      expect(share.name, 'Lena');
      expect(share.kcal, isNull);
      expect(share.dislikes, isEmpty);
      expect(share.allergens, {Allergen.egg});
      expect(jsonEncode(share.toJson()), isNot(contains('kcal')));
    });

    test('Freigabe mittelt die Wochenziele', () {
      final share = CookPlanner.share(
        name: 'A',
        week: week(2000),
        diet: Diet.omnivore,
        preferences: RecipePreferences(),
        fields: CookShareFields(),
        safety: WeightGoalGuard.free,
      );
      expect(share.kcal, 2000);
      expect(share.protein, 120);
    });

    /// Schwangerschaft/Stillzeit oder Essstörung: keine Kalorienziele, auch nicht an andere.
    test('gesperrte Ziele werden nie geteilt', () {
      final share = CookPlanner.share(
        name: 'A',
        week: week(2000),
        diet: Diet.omnivore,
        preferences: RecipePreferences(),
        fields: CookShareFields(),
        safety: WeightGoalGuard.noTargets,
      );
      expect(share.kcal, isNull);
      expect(share.protein, isNull);
    });

    test('unbekannte Werte lassen das Lesen nicht scheitern', () {
      final share = CookShare.fromJson(jsonDecode('{"name":"A","diet":"neu","allergens":["egg","neu"],"kcal":1800}'));
      expect(share.diet, isNull);
      expect(share.allergens, {Allergen.egg});
      expect(share.kcal, 1800);
    });

    test('Links tragen nur den Code', () {
      expect(CookLink.fromUri(Uri.parse('coach://cook/abcdefghij')), const CookPartnerLink('abcdefghij'));
      expect(CookLink.fromUri(Uri.parse('coach://open/cookShare')), const CookReleaseLink());
      expect(CookLink.fromUri(Uri.parse('coach://open/gym')), isNull);
      expect(CookLink.fromUri(Uri.parse('coach://meal/abcdefghij')), isNull);
      expect(CookPlanner.code('https://w.example/k/abcdefghij'), 'abcdefghij');
      expect(CookPlanner.code(' ABCDEFGHIJ '), 'abcdefghij');
      expect(CookPlanner.code('https://w.example/other/abcdefghij'), isNull);
      expect(CookPlanner.code('kurz'), isNull);
    });

    List<RecipeDayTarget> days(int count) => [
      for (var index = 0; index < count; index++)
        RecipeDayTarget(
          day: CalendarDay(2026, 11, 9 + index),
          sessions: const [],
          dayType: DayType.restDay,
          kcal: 2000,
          protein: 120,
          carbs: 250,
          fat: 70,
        ),
    ];

    test('Woche in kleine Abfragen geteilt', () {
      expect(RecipeBatches.batches(days(7)).map((batch) => batch.length), [2, 2, 2, 1]);
      expect(RecipeBatches.batches(days(2)).map((batch) => batch.length), [2]);
      expect(RecipeBatches.batches([]), isEmpty);
      expect(RecipeBatches.batches(days(7)).expand((batch) => batch), days(7));
    });

    test('Teilpläne in Kalenderreihenfolge zusammengeführt', () {
      final all = days(4);
      final late = WeeklyRecipePlan(
        created: created,
        days: [RecipeDay(day: all[3].day, recipes: [], scale: 1)],
        source: 'KI · a',
        notes: ['x'],
      );
      final early = WeeklyRecipePlan(
        created: created,
        days: [RecipeDay(day: all[0].day, recipes: [], scale: 1)],
        source: 'KI · b',
        notes: [],
      );
      final merged = RecipeBatches.merged([late, early], created: created)!;
      expect(merged.days.map((day) => day.day), [all[0].day, all[3].day]);
      expect(merged.source, 'KI · a, KI · b');
      expect(RecipeBatches.merged([], created: created), isNull);
    });

    test('Serverfehler werden lesbar, der Code bleibt', () {
      final busy = AIErrorText.message(status: 502, code: 'ai_unavailable', detail: 'Gemini HTTP 503');
      expect(busy, contains('nicht erreichbar'));
      expect(busy, contains('502'));
      expect(busy, isNot(contains('Gemini')));
      expect(AIErrorText.message(status: 502, code: 'ai_invalid', detail: 'x'), contains('brauchbare'));
      expect(AIErrorText.message(status: 400, code: null, detail: 'Name fehlt'), 'Name fehlt');
      const own = 'Dein KI-Tageslimit (60 Anfragen) ist erreicht. Morgen geht es weiter.';
      expect(AIErrorText.message(status: 429, code: 'quota_exceeded', detail: own), own);
      expect(AIErrorText.message(status: 429, code: null, detail: 'x'), contains('ausgeschöpft'));
      expect(AIErrorText.message(status: 429, code: 'locked', detail: 'Bitte in 15 Minuten'), 'Bitte in 15 Minuten');
      expect(AIErrorText.isTemporary(503), isTrue);
      expect(AIErrorText.isTemporary(400), isFalse);
    });

    test('Kochplan zählt als Planungsaufgabe', () {
      expect(AIPolicy.allows(AIMode.full, task: 'cook_plan', trigger: AITrigger.user), isTrue);
      expect(AIPolicy.kind('cook_plan'), AITaskKind.planning);
    });
  });
}

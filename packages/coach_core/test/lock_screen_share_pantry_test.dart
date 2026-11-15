// Neue Funktionen ohne Swift-Gegenstück (docs/decisions.md, 15.11.2026): Vorrang der Gym-Live-Aktivität, nächste
// Mahlzeit auf dem Sperrbildschirm, Ansicht der Live-Aktivität, Einheit teilen und Rezepte aus dem Kühlschrank-Foto.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

Map<String, Object?> ingredient(String name, {required double grams, required double kcal}) => {
  'name': name,
  'menge_g': grams,
  'naehrwerte_100g': {'kcal': kcal},
};

Map<String, Object?> dish(String title, {List<Object?> missing = const [], String extra = 'Testzutat'}) => {
  'titel': title,
  'mahlzeit': 'abendessen',
  'minuten': 15,
  'zubereitung': ['Anbraten.'],
  'zutaten': [ingredient('${extra}A', grams: 200, kcal: 100), ingredient('${extra}B', grams: 100, kcal: 100)],
  'fehlt': missing,
};

void main() {
  group('Sperrbildschirm', () {
    test('Gym-Einheit hat Vorrang vor „Mahlzeiten heute“', () {
      expect(LockScreenActivities.showsMeals(mealsEnabled: true, workoutShown: false), isTrue);
      expect(LockScreenActivities.showsMeals(mealsEnabled: true, workoutShown: true), isFalse);
      expect(LockScreenActivities.showsMeals(mealsEnabled: false, workoutShown: false), isFalse);
    });

    List<WidgetMealPart> parts({double breakfast = 0, double lunch = 0, double dinner = 0}) => [
      WidgetMealPart(category: MealCategory.breakfast, kcal: breakfast, target: null),
      WidgetMealPart(category: MealCategory.lunch, kcal: lunch, target: null),
      WidgetMealPart(category: MealCategory.dinner, kcal: dinner, target: null),
      const WidgetMealPart(category: MealCategory.snack, kcal: 0, target: null),
    ];

    test('nächste Mahlzeit ohne eingeschaltete Zeiten: gewohnte Hauptmahlzeiten', () {
      final settings = MealReminderSettings();
      final morning = MealLiveReminder.next(settings: settings, meals: parts(), now: DateTime(2026, 11, 15, 7));
      expect(morning?.category, MealCategory.breakfast);
      expect(morning?.due, isFalse);
      expect(morning?.text, 'Als Nächstes: Frühstück um 08:00');

      // 9 Uhr, Frühstück fehlt noch: fällig.
      final late = MealLiveReminder.next(settings: settings, meals: parts(), now: DateTime(2026, 11, 15, 9));
      expect(late?.category, MealCategory.breakfast);
      expect(late?.due, isTrue);
      expect(late?.text, 'Zeit fürs Frühstück – jetzt eintragen?');

      // Frühstück eingetragen: Mittagessen um 12:30.
      final lunch = MealLiveReminder.next(
        settings: settings,
        meals: parts(breakfast: 400),
        now: DateTime(2026, 11, 15, 9),
      );
      expect(lunch?.category, MealCategory.lunch);
      expect(lunch?.at, DateTime(2026, 11, 15, 12, 30));

      // Frühstück drei Stunden vorbei und nicht eingetragen: Es rückt das Mittagessen nach.
      final skipped = MealLiveReminder.next(settings: settings, meals: parts(), now: DateTime(2026, 11, 15, 11));
      expect(skipped?.category, MealCategory.lunch);

      // Alles eingetragen bzw. Tag vorbei: nichts mehr.
      expect(
        MealLiveReminder.next(
          settings: settings,
          meals: parts(breakfast: 1, lunch: 1, dinner: 1),
          now: DateTime(2026, 11, 15, 13),
        ),
        isNull,
      );
      expect(MealLiveReminder.next(settings: settings, meals: parts(), now: DateTime(2026, 11, 15, 23)), isNull);
    });

    test('nächste Mahlzeit: nur eingeschaltete Zeiten, Snack sprachlich richtig', () {
      final settings = MealReminderSettings()..snack = MealReminderSlot(enabled: true, hour: 16, minute: 0);
      final next = MealLiveReminder.next(settings: settings, meals: parts(), now: DateTime(2026, 11, 15, 16, 5));
      expect(next?.category, MealCategory.snack);
      expect(next?.text, 'Zeit für einen Snack – eintragen?');
      expect(MealLiveReminder.next(settings: settings, meals: parts(), now: DateTime(2026, 11, 15, 20)), isNull);
    });

    test('Ansicht der Live-Aktivität wird gespeichert, Standard: beides', () {
      expect(GymSettings().liveActivityLayout, WorkoutActivityLayout.combined);
      final settings = GymSettings()..liveActivityLayout = WorkoutActivityLayout.timer;
      final decoded = GymSettings.fromJson(settings.toJson());
      expect(decoded.liveActivityLayout, WorkoutActivityLayout.timer);
      expect(
        GymSettings.fromJson({'liveActivityLayout': 'unbekannt'}).liveActivityLayout,
        WorkoutActivityLayout.combined,
      );
      expect(WorkoutActivityLayout.timer.showsExercise, isFalse);
      expect(WorkoutActivityLayout.exercise.showsTimer, isFalse);
      expect(WorkoutActivityLayout.combined.showsTimer && WorkoutActivityLayout.combined.showsExercise, isTrue);
    });
  });

  group('Einheit teilen', () {
    final routine = Routine(
      name: 'Push A',
      items: [
        RoutineItem(
          exerciseID: 'bankdruecken',
          name: 'Bankdrücken',
          sets: 4,
          lowerReps: 6,
          upperReps: 8,
          restSeconds: 150,
          weightKg: 62.5,
          supersetWithNext: true,
        ),
        RoutineItem(exerciseID: 'dips', name: 'Dips', sets: 3, lowerReps: 10, upperReps: 10, restSeconds: 90),
      ],
    );

    test('Routine als Link: hin und zurück, neue Kennungen', () {
      final link = RoutineLink.encode(routine);
      expect(link, startsWith('coach://routine/'));
      expect(link, isNot(contains('=')));
      final decoded = RoutineLink.decode(link)!;
      expect(decoded.name, 'Push A');
      expect(decoded.id, isNot(routine.id));
      expect(decoded.items.map((item) => item.name), ['Bankdrücken', 'Dips']);
      final first = decoded.items.first;
      expect((first.sets, first.lowerReps, first.upperReps, first.restSeconds), (4, 6, 8, 150));
      expect(first.weightKg, 62.5);
      expect(first.supersetWithNext, isTrue);
      expect(decoded.items.last.weightKg, isNull);
      expect(decoded.items.last.supersetWithNext, isFalse);
    });

    test('kaputte Links werden abgelehnt', () {
      expect(RoutineLink.decode('coach://routine/'), isNull);
      expect(RoutineLink.decode('coach://routine/!!!'), isNull);
      expect(RoutineLink.decode('https://example.com'), isNull);
      expect(RoutineLink.decode('coach://routine/eyJuIjoiQSIsImkiOltdfQ'), isNull); // {"n":"A","i":[]}
    });

    test('Text einer Routine', () {
      final text = GymShareText.routine(routine, custom: const []);
      expect(text, contains('🏋️ Push A'));
      expect(text, contains('• Bankdrücken: 4 × 6–8 Wdh. · 62,5 kg (Supersatz)'));
      expect(text, contains('• Dips: 3 × 10 Wdh.'));
      expect(text, contains('coach://routine/'));
    });

    test('Text einer Einheit: gleiche Sätze zusammengefasst, ohne Aufwärmsätze, mit Link', () {
      final start = DateTime(2026, 11, 14, 18);
      final session = GymSession(
        workoutKey: null,
        title: 'Push A',
        start: start,
        end: start.add(const Duration(minutes: 52)),
        exercises: [
          LoggedExercise(
            exerciseID: 'bankdruecken',
            name: 'Bankdrücken',
            group: MuscleGroup.chest,
            restSeconds: 150,
            sets: [
              LoggedSet(reps: 10, weightKg: 20, kind: SetKind.warmup),
              LoggedSet(reps: 8, weightKg: 60),
              LoggedSet(reps: 8, weightKg: 60),
              LoggedSet(reps: 6, weightKg: 65),
              LoggedSet(reps: 8, weightKg: 60, done: false),
            ],
          ),
          LoggedExercise(
            exerciseID: 'dips',
            name: 'Dips',
            group: MuscleGroup.chest,
            sets: [LoggedSet(reps: 0, weightKg: 0)],
          ),
        ],
      );
      final text = GymShareText.session(session, custom: const []);
      expect(text, startsWith('🏋️ Push A – 14.11.2026\n52 min · 3 Sätze'));
      expect(text, contains('• Bankdrücken: 2 × 8 · 60 kg, 1 × 6 · 65 kg'));
      expect(text, isNot(contains('Dips')));
      final link = text.split('\n').last;
      final decoded = RoutineLink.decode(link)!;
      expect(decoded.items.single.sets, 3);
      expect((decoded.items.single.lowerReps, decoded.items.single.upperReps), (6, 8));
      expect(decoded.items.single.weightKg, 65);
      expect(decoded.items.single.restSeconds, 150);
    });
  });

  group('Rezepte aus dem Kühlschrank', () {
    final output = JsonValue({
      'erkannt': ['Eier', 'Paprika', 'eier', ' '],
      'gerichte': [
        dish('Omelett', missing: ['Butter', 'Salz']),
        dish('Paprika-Pfanne', missing: ['Butter']),
        dish('Shakshuka', missing: ['Tomaten', 'Zwiebel', 'Kreuzkümmel']),
        dish('Rührei', missing: ['Eier']),
        dish('Schinkenbrot', extra: 'Schinken'),
      ],
    });

    PantryResult parse({List<String> pantry = const []}) =>
        PantryRecipes.result(output, diet: Diet.vegetarian, allergens: {}, pantry: pantry)!;

    test('erkannte Lebensmittel ohne Doppelte; zu viel Fehlendes und Unpassendes verworfen', () {
      final result = parse();
      expect(result.detected, ['Eier', 'Paprika']);
      expect(result.recipes.map((recipe) => recipe.recipe.title), ['Omelett', 'Paprika-Pfanne', 'Rührei']);
      expect(result.notes.any((note) => note.contains('Shakshuka') && note.contains('zu viele')), isTrue);
      expect(result.notes.any((note) => note.contains('Schinkenbrot')), isTrue);
      // „Eier“ sind erkannt und fehlen deshalb nicht.
      expect(result.recipes.last.missing, isEmpty);
    });

    test('Vorrat gilt als da', () {
      final result = parse(pantry: ['salz']);
      expect(result.recipes.first.missing, ['Butter']);
    });

    test('Rückfragen: häufigste zuerst, Antworten klären die Gerichte', () {
      final recipes = parse().recipes;
      expect(PantryRecipes.questions(recipes, confirmed: {}, denied: {}), ['Butter', 'Salz']);
      expect(PantryRecipes.question('Butter'), 'Ist noch Butter da?');
      expect(PantryRecipes.neededFor('butter', recipes), ['Omelett', 'Paprika-Pfanne']);

      final omelett = recipes.first;
      expect(PantryRecipes.status(omelett, confirmed: {}, denied: {}), PantryRecipeStatus.waiting);
      expect(PantryRecipes.status(omelett, confirmed: {'butter'}, denied: {}), PantryRecipeStatus.waiting);
      expect(PantryRecipes.status(omelett, confirmed: {'Butter', 'Salz'}, denied: {}), PantryRecipeStatus.ready);
      expect(PantryRecipes.status(omelett, confirmed: {'Salz'}, denied: {'Butter'}), PantryRecipeStatus.blocked);
      expect(PantryRecipes.status(recipes.last, confirmed: {}, denied: {}), PantryRecipeStatus.ready);

      // Keine Butter: Fragen nur noch für Gerichte, die gehen könnten.
      expect(PantryRecipes.questions(recipes, confirmed: {}, denied: {'Butter'}), isEmpty);
      expect(PantryRecipes.questions(recipes, confirmed: {'Butter'}, denied: {}), ['Salz']);
    });

    test('Eingabe mit Antworten und Mengen aufs Ziel skaliert', () {
      final input = PantryRecipes.input(
        category: MealCategory.dinner,
        targetKilocalories: 600,
        diet: Diet.omnivore,
        preferences: RecipePreferences(),
        pantry: const ['Reis'],
        detected: const ['Paprika', 'Eier'],
        confirmed: const {'Salz'},
        denied: const {'Butter'},
      );
      expect(input['mahlzeit'], 'abendessen');
      expect(input['kcal'], 600);
      expect(input['erkannt'], ['Eier', 'Paprika']);
      expect(input['bestaetigt'], ['Salz']);
      expect(input['nicht_da'], ['Butter']);
      expect(input['max_fehlend'], 2);

      final scaled = PantryRecipes.result(
        output,
        diet: Diet.omnivore,
        allergens: {},
        pantry: const [],
        targetKilocalories: 450,
      )!;
      // 300 kcal → 450 kcal: Faktor 1,5.
      expect(scaled.recipes.first.recipe.ingredients.map((item) => item.grams), [300, 150]);
      expect(PantryRecipes.kilocalories(scaled.recipes.first), closeTo(450, 1));
    });

    test('Antwort ohne Lesbares', () {
      expect(PantryRecipes.result(const JsonValue({}), diet: Diet.omnivore, allergens: {}, pantry: const []), isNull);
    });
  });
}

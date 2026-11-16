// Sicherung der bisherigen Android-App „IronLudi“ einlesen (docs/decisions.md, 16.11.2026). Die Testdatei folgt den
// Datenklassen in Coach-App `android/core/.../Model.kt` im Format von kotlinx.serialization mit `encodeDefaults`.
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  final bytes = File('test/fixtures/ironludi-android-backup.json').readAsBytesSync();

  test('wird erkannt; die iPhone-Sicherung und Fremdes nicht', () {
    expect(KotlinBackup.looksLike(jsonDecode(utf8.decode(bytes))), isTrue);
    expect(KotlinBackup.looksLike({'version': 1, 'createdAt': '2026-11-13T12:00:00Z', 'gym': <Object?>[]}), isFalse);
    expect(KotlinBackup.decode(utf8.encode('{kein json')), isNull);
    expect(KotlinBackup.decode(utf8.encode('{"version": 99, "sessions": []}')), isNull);
    expect(KotlinBackup.decode(utf8.encode('{"version": 1, "sessions": []}'))?.count, 0);
  });

  test('Trainings: Sätze mit Aufwärmen, Muskelgruppe, Routine, Pause aus den Einstellungen', () {
    final backup = KotlinBackup.decode(bytes)!;
    expect(backup.sessions, hasLength(1));
    final session = backup.sessions.single;
    expect(session.id, '6F1C2A3E-1B2C-4D5E-8F90-A1B2C3D4E5F6');
    expect(GymSession.fromJson(session.toJson())?.id, session.id);
    expect(session.title, 'Push');
    expect(session.start, DateTime.fromMillisecondsSinceEpoch(1762790400000, isUtc: true));
    expect(session.end!.difference(session.start), const Duration(hours: 1));
    expect(session.workoutKey, 'routine-0A0B0C0D-1111-2222-3333-444455556666');
    final bench = session.exercises.first;
    expect(bench.group, MuscleGroup.chest);
    expect(bench.restSeconds, 120);
    expect(bench.sets.first.kind, SetKind.warmup);
    expect(bench.doneSets.map((set) => (set.weightKg, set.reps)), [(60.0, 8), (62.5, 6)]);
    expect(bench.sets.last.done, isFalse);
    // Zwei Arbeitssätze Bankdrücken und einer eigene Übung (ohne Aufwärmen).
    expect(session.doneSetCount, 3);
    expect(session.exercises.last.group, MuscleGroup.shoulders);
  });

  test('Pläne und eigene Übungen', () {
    final backup = KotlinBackup.decode(bytes)!;
    final custom = backup.customExercises.single;
    expect(custom.id, 'eigen_landmine_press');
    expect(custom.isCustom, isTrue);
    expect(custom.secondary, [MuscleGroup.triceps]);
    expect(custom.equipment, [Equipment.barbell]);
    expect(custom.compound, isTrue);
    final routine = backup.routines.single;
    expect(routine.name, 'Push');
    expect(Routine.fromJson(routine.toJson())?.id, routine.id);
    expect(routine.items.map((item) => (item.name, item.sets)), [('Bankdrücken', 4), ('Landmine Press', 3)]);
    // Wiederholungsbereich aus der Bibliothek bzw. der eigenen Übung.
    expect((routine.items.first.lowerReps, routine.items.first.upperReps), (6, 10));
    expect(routine.items.first.restSeconds, 120);
    expect(backup.restSeconds, 120);
    expect(backup.keepScreenOn, isFalse);
  });

  test('Ernährung: Mahlzeiten, Favoriten, Lebensmittel, eigene Rezepte, Gewichte', () {
    final backup = KotlinBackup.decode(bytes)!;
    final meal = backup.meals.single;
    expect(meal.title, 'Linsen-Bowl');
    expect(meal.day, const CalendarDay(2025, 11, 11));
    expect(meal.category, MealCategory.lunch);
    final item = meal.items.single;
    expect(
      (item.grams, item.source, item.per100g[Nutrient.kcal], item.amountText),
      (150.0, MealItemSource.ai, 120.0, '1 Schale'),
    );
    expect(backup.favorites.single.title, 'Müsli');
    expect(backup.favorites.single.category, MealCategory.breakfast);
    expect(backup.foods.single.barcode, '4000000000000');
    final chili = backup.ownRecipes.single;
    expect((chili.name, chili.portions, chili.cookedGrams, chili.remainingPortions), ('Chili', 4, 1200.0, 2.5));
    expect(backup.weights.map((entry) => (entry.day.iso, entry.kilograms)), [
      ('2025-11-10', 83.1),
      ('2025-11-11', 82.7),
    ]);
    expect(backup.weights.every((entry) => entry.source == WeightSource.manual), isTrue);
    expect(backup.count, 1 + 1 + 1 + 1 + 1 + 1 + 1 + 2);
  });

  test('Körperwerte, Rezept-Wünsche und Erinnerungen; Ziel bleibt bei den Schutzgrenzen der Einrichtung', () {
    final backup = KotlinBackup.decode(bytes)!;
    final body = backup.body!;
    expect((body.weightKilograms, body.heightCentimeters, body.age, body.isFemale), (82.5, 184.0, 34, false));
    expect(body.activityFactor, 1.5);
    expect(body.diet, Diet.vegetarian);
    final preferences = backup.recipePreferences!;
    expect(preferences.allergens, {Allergen.nuts, Allergen.sesame});
    expect(
      (preferences.dislikes, preferences.maxMinutes, preferences.snacks, preferences.mealPrep),
      ('Pilze', 25, false, true),
    );
    final reminders = backup.reminders!;
    expect((reminders.breakfast.enabled, reminders.breakfast.hour, reminders.breakfast.minute), (true, 7, 15));
    expect(reminders.lunch.enabled, isFalse);
    expect((reminders.dinner.hour, reminders.dinner.minute), (19, 30));
    expect(backup.reviewReminder, isTrue);
    expect(backup.skipped, hasLength(2));
    expect(backup.skipped.first, contains('laufendes Training'));
    expect(backup.skipped.last, contains('Tagestypen'));
  });
}

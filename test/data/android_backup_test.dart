// Sicherung der bisherigen Android-App in die Flutter-App einspielen: zusammenführend, nichts doppelt, vorhandene
// Einstellungen bleiben (Testdatei aus packages/coach_core/test/fixtures).
import 'dart:io';

import 'package:aironludi/data/backup/backup_service.dart';
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  final backup = KotlinBackup.decode(
    File('packages/coach_core/test/fixtures/ironludi-android-backup.json').readAsBytesSync(),
  )!;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  test('leere App: alles übernommen, beim zweiten Mal nichts doppelt', () async {
    final settings = CoachSettings(store);
    final service = BackupService(db, store);
    final result = await service.restoreKotlin(backup, settings);
    expect(
      result.text,
      '1 Krafteinheiten, 1 Mahlzeiten, 1 Lebensmittel und 6 Pläne, Übungen, Favoriten, Rezepte und Gewichte ergänzt.',
    );

    final sessions = await GymRepository(db).sessions();
    expect(sessions.single.title, 'Push');
    expect(sessions.single.doneSetCount, 3);
    final meals = await MealRepository(db).all();
    expect(meals.single.title, 'Linsen-Bowl');
    expect((await MealRepository(db).foods()).single.item?.barcode, '4000000000000');

    // Einstellungen neu gelesen (wie nach dem Neustart der App).
    final reloaded = CoachSettings(store);
    expect(reloaded.gym.routines.single.name, 'Push');
    expect(reloaded.gym.customExercises.single.id, 'eigen_landmine_press');
    expect((reloaded.gym.restCompound, reloaded.gym.restIsolation, reloaded.gym.keepsScreenOn), (120, 120, false));
    expect(reloaded.favoriteMeals.single.title, 'Müsli');
    expect(reloaded.ownRecipes.single.name, 'Chili');
    expect(reloaded.weights.map((entry) => entry.kilograms), [83.1, 82.7]);
    expect(reloaded.nutrition.weightKilograms, 82.5);
    expect(reloaded.nutrition.diet, Diet.vegetarian);
    expect(reloaded.recipes.allergens, {Allergen.nuts, Allergen.sesame});
    expect(reloaded.reminders.meals.breakfast.enabled, isTrue);
    expect(reloaded.reminders.nutritionReview, isTrue);

    final again = await service.restoreKotlin(backup, reloaded);
    expect(
      again.text,
      '0 Krafteinheiten, 0 Mahlzeiten, 0 Lebensmittel und 0 Pläne, Übungen, Favoriten, Rezepte und Gewichte ergänzt.',
    );
    expect(await GymRepository(db).sessions(), hasLength(1));
  });

  test('schon eingerichtete App: Körperwerte, Wünsche und Erinnerungen bleiben', () async {
    final settings = CoachSettings(store);
    settings.nutrition = settings.nutrition.copy()
      ..weightKilograms = 70
      ..diet = Diet.vegan;
    settings.recipes = RecipePreferences(dislikes: 'Koriander');
    settings.reminders = settings.reminders.copy()..meals.lunch = MealReminderSlot(enabled: true, hour: 13, minute: 0);
    await BackupService(db, store).restoreKotlin(backup, settings);
    final reloaded = CoachSettings(store);
    expect(reloaded.nutrition.weightKilograms, 70);
    expect(reloaded.nutrition.diet, Diet.vegan);
    expect(reloaded.recipes.dislikes, 'Koriander');
    expect(reloaded.reminders.meals.lunch.hour, 13);
    expect(reloaded.reminders.meals.breakfast.enabled, isFalse);
  });
}

// Homescreen-Widgets: Wasser aus dem Widget übernehmen, Stand im Format der Swift-App schreiben, ohne Ordner nichts.
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/gym/gym_controller.dart';
import 'package:aironludi/services/widgets/widget_publisher.dart';
import 'package:aironludi/services/widgets/widget_store.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late Directory folder;
  final now = DateTime(2026, 11, 16, 12);
  final today = CalendarDay.fromDate(now);

  setUpAll(() => initializeDateFormatting('de_DE'));

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    folder = Directory.systemTemp.createTempSync('widgets');
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  WidgetPublisher publisher(WidgetHost host, {bool onboarded = true}) {
    final settings = CoachSettings(store);
    settings.profile = settings.profile.copy()
      ..onboardingDone = onboarded
      ..mode = ProfileMode.personal
      ..sports = [TrainingSport.run, TrainingSport.strength];
    return WidgetPublisher(
      store: WidgetStore(host),
      settings: settings,
      settingsStore: store,
      metrics: MetricsRepository(db),
      activities: ActivityRepository(db),
      gymSessions: GymRepository(db),
      meals: MealRepository(db),
      gym: GymController(store: store, clock: () => now),
      garminProfile: () => null,
      schedule: null,
    );
  }

  test('Wasser aus dem Widget: heutige und gestrige Einträge übernommen, verfallene entfernt', () async {
    final queue = WidgetActionQueue()
      ..addWater(250, at: now.subtract(const Duration(hours: 1)))
      ..addWater(500, at: now.subtract(const Duration(days: 1)))
      ..addWater(300, at: now.subtract(const Duration(days: 9)));
    File('${folder.path}/${WidgetActionQueue.fileName}').writeAsStringSync(jsonEncode(queue.toJson()));
    final widgets = publisher(DirectoryWidgetHost(folder));

    expect(await widgets.takeQueuedActions(now: now), 2);
    final meals = await MealRepository(db).all();
    expect(meals.map((meal) => (meal.title, meal.day)), [('Wasser', today.adding(-1)), ('Wasser', today)]);
    expect(meals.every((meal) => meal.isWater), isTrue);
    // Alles übernommen oder verfallen: die Datei ist leer.
    expect((await WidgetStore(DirectoryWidgetHost(folder)).loadQueue()).entries, isEmpty);
    // Zweites Öffnen übernimmt nichts doppelt.
    expect(await widgets.takeQueuedActions(now: now), 0);
  });

  test('Stand schreiben: lesbar wie in Swift, Wasser, letzte Mahlzeit, Gym und Serie; Widgets neu geladen', () async {
    final host = DirectoryWidgetHost(folder);
    final widgets = publisher(host);
    final meals = MealRepository(db);
    await meals.save(
      StoredMeal(
        day: today,
        createdAt: now.subtract(const Duration(hours: 4)),
        category: MealCategory.breakfast,
        title: 'Porridge',
        items: [
          MealItem(
            name: 'Haferflocken',
            grams: 100,
            source: MealItemSource.manual,
            per100g: NutrientValues({Nutrient.kcal: 370, Nutrient.protein: 13}),
          ),
        ],
      ),
    );
    await meals.save(
      StoredMeal(
        day: today,
        createdAt: now.subtract(const Duration(hours: 2)),
        category: MealCategory.snack,
        title: 'Wasser',
        items: [MealItem.water(milliliters: 400)],
      ),
    );
    await widgets.publish(now: now);
    expect(host.reloads, 1);

    final raw = jsonDecode(File('${folder.path}/${WidgetSnapshot.fileName}').readAsStringSync()) as Map;
    // Zeitpunkte wie `JSONEncoder` (Sekunden seit 2001), damit die nativen Widgets sie lesen.
    expect(raw['createdAt'], isA<num>());
    final snapshot = (await WidgetStore(host).loadSnapshot())!;
    expect(snapshot.day, today);
    expect(snapshot.nutrition!.kcal, 370);
    expect(snapshot.nutrition!.waterMilliliters, greaterThanOrEqualTo(400));
    expect(snapshot.nutrition!.lastMeal!.title, 'Porridge');
    expect(snapshot.nutrition!.meals!.firstWhere((part) => part.category == MealCategory.breakfast).kcal, 370);
    expect(snapshot.gym, isNotNull);
    expect(snapshot.gym!.running, isFalse);
    expect(snapshot.mealStreak!.days, 1);
    expect(snapshot.streak!.activeToday, isTrue);
  });

  test('ohne gemeinsamen Ordner oder vor dem Onboarding: nichts geschrieben', () async {
    final none = DirectoryWidgetHost(null);
    await publisher(none).publish(now: now);
    expect(await publisher(none).takeQueuedActions(now: now), 0);
    expect(none.reloads, 0);

    final host = DirectoryWidgetHost(folder);
    await publisher(host, onboarded: false).publish(now: now);
    expect(File('${folder.path}/${WidgetSnapshot.fileName}').existsSync(), isFalse);
    expect(host.reloads, 0);
  });
}

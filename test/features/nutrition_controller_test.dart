// Port von `NutritionViewModelTests` und `PersonalizationAppTests.nutritionUsesTheOwnWeekPlan`.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/nutrition/nutrition_controller.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Freitag, 23.10.2026, mittags (laut Musterwoche Push + Pull → leichter Tag).
final friday = DateTime(2026, 10, 23, 12);

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late CoachSettings settings;
  late MealRepository meals;
  final requests = <HttpRequest>[];
  late String body;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    settings = CoachSettings(store)..profile = UserProfile.seasonPlan;
    meals = MealRepository(db);
    requests.clear();
    body = '{}';
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  NutritionController controller() {
    final transport = FakeHttpTransport((request) {
      requests.add(request);
      return HttpResponse(200, utf8.encode(body));
    });
    return NutritionController(
      meals: meals,
      settings: settings,
      ai: AIClient(secrets: Secrets.memory(), settings: store, transport: transport),
      openFoodFacts: OpenFoodFactsClient(transport: transport),
      clock: () => friday,
    );
  }

  test('gespeicherte Mahlzeit zählt zu den Summen von heute', () async {
    final model = controller()..update(meals: const [], activities: const [], profile: null, hasGarminData: false);
    await model.save(
      MealDraft(
        title: '',
        category: MealCategory.breakfast,
        hint: '',
        items: [
          MealItem(
            name: 'Haferflocken',
            grams: 80,
            source: MealItemSource.manual,
            per100g: NutrientValues({Nutrient.kcal: 360, Nutrient.protein: 13}),
          ),
        ],
      ),
    );
    final stored = await meals.all();
    final foods = await meals.foods();
    expect(stored, hasLength(1));
    expect(stored.first.title, 'Haferflocken');
    expect(foods.first.useCount, 1);
    expect(model.draft, isNull);

    model.update(meals: stored, activities: const [], profile: null, hasGarminData: false);
    expect(model.totals[Nutrient.kcal], 288);
    expect(model.targets?.dayType, DayType.light);
    expect(model.targets?.source, TargetsSource.planned);
  });

  test('leerer Entwurf wird abgelehnt', () async {
    final model = controller();
    await model.save(
      MealDraft(
        title: '',
        category: MealCategory.snack,
        hint: '',
        items: [MealItem(name: ' ', grams: 0, source: MealItemSource.manual, per100g: NutrientValues())],
      ),
    );
    expect(model.errorMessage, isNotNull);
    expect(await meals.all(), isEmpty);
  });

  test('Barcode: Entwurf und Produkt im Zwischenspeicher', () async {
    body =
        '{"status": 1, "product": {"product_name": "Skyr", "serving_quantity": 150, '
        '"nutriments": {"energy-kcal_100g": 63}}}';
    final model = controller();
    await model.lookup('4006381333931', const []);
    expect(requests.first.headers['User-Agent'], OpenFoodFacts.userAgent);
    final item = model.draft!.items.first;
    expect(item.name, 'Skyr');
    expect(item.grams, 150);
    expect((await meals.foods()).first.key, 'barcode:4006381333931');
  });

  test('ungültiger Barcode zeigt einen Fehler', () async {
    final model = controller();
    await model.lookup('123', const []);
    expect(model.errorMessage, contains('Barcode'));
    expect(model.draft, isNull);
  });

  test('Schnell-Eintrag am gewählten Tag und Rückgängig', () async {
    final model = controller()..update(meals: const [], activities: const [], profile: null, hasGarminData: false);
    // Donnerstag nachtragen.
    const thursday = CalendarDay(2026, 10, 22);
    model.selectedDay = thursday;
    await model.log(
      title: 'Skyr',
      category: MealCategory.snack,
      items: [QuickMealItem.quick(kilocalories: 150, protein: 25)],
    );
    final logged = await meals.all();
    expect(logged.first.day, thursday);
    expect(CalendarDay.fromDate(logged.first.createdAt), thursday);
    expect(model.lastLogged?.label, 'Skyr eingetragen');
    await model.undoLastLog();
    expect(await meals.all(), isEmpty);

    await model.log(title: 'Wasser', category: MealCategory.snack, items: [MealItem.water(milliliters: 250)]);
    final water = await meals.all();
    expect(water.first.isWater, isTrue);
    expect(MealRepository.entries(water), isEmpty);
  });

  test('persönliches Profil: Ziele aus dem eigenen Wochenplan', () {
    final profile = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run, TrainingSport.strength],
      goal: FitnessGoal.loseWeight,
    );
    profile.schedule = profile.schedule
        .withSlots(const [SessionSlot(TrainingSport.run, SessionIntensity.hard)], Weekday.friday)
        .withSlots(const [SessionSlot(TrainingSport.strength, SessionIntensity.hard)], Weekday.saturday);
    settings.profile = profile;
    final model = controller();
    // Freitag: harter Lauf geplant, noch keine Aktivität. Swift-Test: `.hard`; der (gleiche) Code liefert für
    // `SessionIntensity.hard` aber `DayType.moderate` (`SessionSlot.plannedDayType`), siehe docs/decisions.md.
    model.update(meals: const [], activities: const [], profile: null, hasGarminData: false, now: friday);
    expect(model.targets?.dayType, DayType.moderate);
    expect(model.targets?.source, TargetsSource.planned);
    // Samstag: Krafttraining → leichter Tag. Sonntag: nichts geplant.
    model.update(
      meals: const [],
      activities: const [],
      profile: null,
      hasGarminData: false,
      now: friday.add(const Duration(days: 1)),
    );
    expect(model.targets?.dayType, DayType.light);
    model.update(
      meals: const [],
      activities: const [],
      profile: null,
      hasGarminData: false,
      now: friday.add(const Duration(days: 2)),
    );
    expect(model.targets?.dayType, DayType.restDay);
  });
}

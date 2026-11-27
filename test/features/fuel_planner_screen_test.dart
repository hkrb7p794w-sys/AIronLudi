// Fuel Planner: Einstieg in der Ernährung, Plan berechnen, speichern, ins Tagebuch übernehmen (ohne Doppelzählung);
// Einstieg aus Ausdauer- und Wochenplan mit Erkennung geänderter Einheiten; Wetter; Speicher strikt je Benutzer.
import 'dart:async';
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/repositories/route_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/fuel/fuel_for_slot.dart';
import 'package:aironludi/features/fuel/fuel_plan_screen.dart';
import 'package:aironludi/features/fuel/fuel_planner_screen.dart';
import 'package:aironludi/features/fuel/fuel_scenario_screen.dart';
import 'package:aironludi/features/fuel/fuel_stock_screen.dart';
import 'package:aironludi/features/nutrition/nutrition_controller.dart';
import 'package:aironludi/features/plan/plan_screen.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/fuel/fuel_diary_writer.dart';
import 'package:aironludi/services/fuel/fuel_store.dart';
import 'package:aironludi/services/fuel/fuel_weather_service.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:aironludi/services/routing/location_source.dart';
import 'package:aironludi/services/routing/route_stores.dart';
import 'package:aironludi/services/routing/route_weather_service.dart';
import 'package:aironludi/services/routing/routing_providers.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

const raceDay = CalendarDay(2026, 12, 6);

FuelPlan halfMarathon() => FuelPlanner.plan(
  const FuelScenario(
    sport: FuelSport.run,
    minutes: 110,
    weightKilograms: 70,
    isRace: true,
    title: 'Halbmarathon',
    day: raceDay,
    startMinuteOfDay: 9 * 60,
  ),
  setup: [FuelProducts.classicGel],
);

MealItem food(String name, double kcal) =>
    MealItem(name: name, grams: 100, source: MealItemSource.manual, per100g: NutrientValues({Nutrient.kcal: kcal}));

final class FakeWeather implements WeatherSource {
  GeoPoint? asked;

  @override
  Future<List<WeatherHour>> forecast(GeoPoint point, CalendarDay day) async {
    asked = point;
    return [
      for (var hour = 0; hour < 24; hour++)
        WeatherHour(
          time: DateTime(day.year, day.month, day.day, hour),
          temperature: 24,
          windSpeed: 5,
          windFrom: 0,
          humidity: 80,
        ),
    ];
  }
}

final class FakeLocation implements LocationSource {
  @override
  Future<GeoPoint> current() async => const GeoPoint(48.1, 11.6);

  @override
  Stream<GeoPoint> watch({bool background = false}) => const Stream.empty();
}

void main() {
  group('Speicher je Benutzer', () {
    test('Eigener Stand wird gespeichert und neu geladen, Tagebuch-Stand mit Rückgängig', () async {
      final db = CoachDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = await SettingsStore.open(db);
      final store = FuelStore(settings, username: 'anna');
      await store.saveProfile(const FuelProfile(gut: GutTolerance.trained, setup: ['builtin.iso']));
      await store.saveProduct(
        FuelProduct.fromMix(id: 'mix', name: 'Flasche', mix: const FuelMix(maltodextrin: 60, waterMilliliters: 500)),
      );
      final id = await store.savePlan(
        const FuelScenario(sport: FuelSport.bike, minutes: 180, weightKilograms: 70, slotID: 'slot'),
        ['mix'],
      );
      expect(store.plansUsing('mix'), 1);
      final before = store.plan(id)!;
      await store.markLogged(id, ['m1', 'm2']);
      final again = FuelStore(settings, username: 'anna');
      expect(again.profile.gut, GutTolerance.trained);
      expect(again.ownProducts.single.carbs, 57);
      expect(again.planForSlot('slot')?.loggedMealIDs, ['m1', 'm2']);
      await again.restoreLogged(before);
      expect(again.plan(id)!.loggedAt, isNull);
      // Erneut speichern behält den Tagebuch-Stand.
      await again.markLogged(id, ['m3']);
      await again.savePlan(again.plan(id)!.scenario.copyWith(minutes: 200), ['mix'], id: id);
      expect(again.plan(id)!.loggedMealIDs, ['m3']);
    });

    test('Stand eines anderen Benutzers wird weder geladen noch überschrieben', () async {
      final db = CoachDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = await SettingsStore.open(db);
      await FuelStore(settings, username: 'anna').saveProfile(const FuelProfile(gut: GutTolerance.trained));
      final ben = FuelStore(settings, username: 'ben');
      expect(ben.hasForeignData, isTrue);
      expect(ben.profile.gut, GutTolerance.habituated);
      expect(ben.plans, isEmpty);
      expect(() => ben.saveProfile(const FuelProfile()), throwsStateError);
      expect(
        FuelLibrary.fromJson(settings.json(SettingsKeys.fuelPlanner), username: 'anna')!.profile.gut,
        GutTolerance.trained,
      );
    });
  });

  test('Vorrat: Plan bucht ab, erneutes Übernehmen nicht doppelt, Rückgängig bucht zurück', () async {
    final db = CoachDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = await SettingsStore.open(db);
    final store = FuelStore(settings, username: 'anna');
    await store.setStock('builtin.gel', const FuelStock(count: 6, bestBefore: CalendarDay(2026, 12, 20)));
    final id = await store.savePlan(halfMarathon().scenario, ['builtin.gel']);
    // Mit „Vorrat zuerst“ ist das Vorrätige auch ohne Auswahl im Plan.
    expect(store.setupWithStock(const [], raceDay).single, FuelProducts.classicGel);
    final before = store.plan(id)!;
    await store.markLogged(id, ['a'], consumed: {'builtin.gel': 5});
    expect(store.stock['builtin.gel']!.count, 1);
    final afterFirst = store.plan(id)!;
    await store.markLogged(id, ['b'], consumed: {'builtin.gel': 4}); // erneut: erst 5 zurück, dann 4 ab
    expect(store.stock['builtin.gel']!.count, 2);
    await store.restoreLogged(afterFirst); // Rückgängig des zweiten Übernehmens
    expect(store.stock['builtin.gel']!.count, 1);
    await store.restoreLogged(before); // und des ersten
    expect(store.stock['builtin.gel']!.count, 6);
    expect(store.stock['builtin.gel']!.bestBefore, const CalendarDay(2026, 12, 20));
    await store.saveProfile(store.profile.copyWith(useStockFirst: false));
    expect(store.setupWithStock(const [], raceDay), isEmpty);
  });

  group('Tagebuch ohne Doppelzählung', () {
    late CoachDatabase db;
    late MealRepository meals;

    setUp(() {
      db = CoachDatabase(NativeDatabase.memory());
      meals = MealRepository(db);
    });
    tearDown(() => db.close());

    test('Je Phase eine Mahlzeit zur Uhrzeit der Phase, mit Markierung', () async {
      final result = await writeFuelPlanToDiary(meals, halfMarathon(), planID: 'P', phases: {...FuelPhase.values});
      expect(result.saved.length, 3);
      expect(result.removed, isEmpty);
      final stored = await meals.day(raceDay);
      final pre = stored.firstWhere((meal) => meal.title.startsWith('Vor dem Training'));
      expect(pre.createdAt, DateTime(2026, 12, 6, 5, 30)); // 3½ h vor 9 Uhr
      expect(pre.title, 'Vor dem Training · Halbmarathon');
      expect(FuelDiary.marker(pre.hint), (planID: 'P', phase: FuelPhase.pre));
      expect(FuelDiary.isPlaceholder(hint: pre.hint, items: pre.items), isTrue);
      final post = stored.firstWhere((meal) => meal.title.startsWith('Nach dem Training'));
      expect(post.createdAt, DateTime(2026, 12, 6, 10, 50));
    });

    test('Erneut übernehmen ersetzt die eigenen Einträge, bearbeitete bleiben; Rückgängig stellt alles her', () async {
      final first = await writeFuelPlanToDiary(meals, halfMarathon(), planID: 'P', phases: {...FuelPhase.values});
      // Den Platzhalter „danach“ in echte Lebensmittel geändert: Markierung weg.
      final post = first.saved.last
        ..items = [food('Nudeln mit Hähnchen', 750)]
        ..hint = FuelDiary.editedHint;
      await meals.save(post);
      final second = await writeFuelPlanToDiary(
        meals,
        halfMarathon(),
        planID: 'P',
        phases: {FuelPhase.pre, FuelPhase.intra},
        previousMealIDs: [for (final meal in first.saved) meal.id],
      );
      expect(second.removed.length, 2);
      var stored = await meals.day(raceDay);
      expect(stored.length, 3); // 2 neu + bearbeitete Mahlzeit danach
      expect(stored.where((meal) => meal.hint == FuelDiary.editedHint).single.id, post.id);
      await undoFuelDiary(meals, second);
      stored = await meals.day(raceDay);
      expect({for (final meal in stored) meal.id}, {for (final meal in first.saved) meal.id});
    });

    test('Echte Mahlzeit ersetzt den Platzhalter, Rückgängig holt ihn zurück', () async {
      await writeFuelPlanToDiary(meals, halfMarathon(), planID: 'P', phases: {...FuelPhase.values});
      final store = await SettingsStore.open(db);
      final transport = FakeHttpTransport((_) => HttpResponse(200, utf8.encode('{}')));
      final controller = NutritionController(
        meals: meals,
        settings: CoachSettings(store)..profile = UserProfile.seasonPlan,
        ai: AIClient(secrets: Secrets.memory(), settings: store, transport: transport),
        openFoodFacts: OpenFoodFactsClient(transport: transport),
        clock: () => DateTime(2026, 12, 6, 6, 0),
      )..selectedDay = raceDay;
      addTearDown(controller.dispose);
      // Kaffee um 6 Uhr: zu wenig Energie, Platzhalter bleibt.
      await controller.log(title: 'Kaffee', category: MealCategory.breakfast, items: [food('Kaffee', 20)]);
      expect(controller.lastLogged!.replaced, isEmpty);
      // Frühstück um 6 Uhr (30 min nach dem Platzhalter um 5:30): ersetzt ihn.
      await controller.log(title: 'Frühstück', category: MealCategory.breakfast, items: [food('Toast mit Honig', 650)]);
      expect(controller.lastLogged!.replaced.single.title, 'Vor dem Training · Halbmarathon');
      expect(controller.lastLogged!.label, endsWith('Plan-Platzhalter ersetzt'));
      var titles = [for (final meal in await meals.day(raceDay)) meal.title];
      expect(titles.where((title) => title.startsWith('Vor dem Training')), isEmpty);
      expect(titles, contains('Verpflegung unterwegs · Halbmarathon'));
      await controller.undoLastLog();
      titles = [for (final meal in await meals.day(raceDay)) meal.title];
      expect(titles, contains('Vor dem Training · Halbmarathon'));
      expect(titles, isNot(contains('Frühstück')));
    });

    test('Schon eingetragene Mahlzeit wählt die Phase beim Übernehmen ab', () async {
      await meals.save(
        StoredMeal(
          day: raceDay,
          createdAt: DateTime(2026, 12, 6, 5, 45),
          category: MealCategory.breakfast,
          title: 'Frühstück',
          items: [food('Haferbrei', 600)],
        ),
      );
      final conflicts = fuelDiaryConflicts(halfMarathon(), await meals.day(raceDay), planID: 'P');
      expect(conflicts.keys, [FuelPhase.pre]);
      expect(conflicts[FuelPhase.pre]!.title, 'Frühstück');
    });
  });

  test('Wetter: Ort aus Favorit „Zuhause“, sonst Standort; Vorhersage nur 15 Tage', () async {
    final db = CoachDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = await SettingsStore.open(db);
    final routes = RouteStore(settings, username: 'anna', routes: RouteRepository(db));
    await routes.ready;
    final weather = FakeWeather();
    final service = FuelWeatherService(routes: routes, location: FakeLocation(), weather: weather);
    final today = CalendarDay.today();
    final s = FuelScenario(sport: FuelSport.run, minutes: 90, weightKilograms: 70, day: today);
    final (updated, message) = await service.apply(s, today: today);
    expect(weather.asked, const GeoPoint(48.1, 11.6));
    expect((updated.temperatureCelsius, updated.humidity), (24.0, FuelHumidity.humid));
    expect(message, 'Wetter ab 9 Uhr: 24 °C, 80 % Luftfeuchte');
    await routes.saveFavorite(
      FavoritePlace(id: 'h', name: 'Zuhause', point: const GeoPoint(52.5, 13.4), createdAt: DateTime(2026)),
    );
    await service.apply(s, today: today);
    expect(weather.asked, const GeoPoint(52.5, 13.4));
    expect(
      () => service.apply(s.copyWith(day: () => today.adding(20)), today: today),
      throwsA(isA<FuelWeatherProblem>()),
    );
  });

  testWidgets('Ernährung › Fuel Planner: Vorlage, berechnen, speichern, ins Tagebuch', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Ernährung')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Verpflegung'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Verpflegung'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelPlannerScreen), findsOneWidget);
    expect(find.text('Noch keine Pläne'), findsOneWidget);

    await tester.tap(find.text('Neuer Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelScenarioScreen), findsOneWidget);
    await tester.tap(find.text('Rad'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('5 Minuten mehr'));
    await tester.pumpAndSettle();
    expect(find.text('1:35'), findsOneWidget);
    await tester.tap(find.text('Berechnen'));
    await tester.pumpAndSettle();

    expect(find.byType(FuelPlanScreen), findsOneWidget);
    expect(find.text('UNTERWEGS JE STUNDE'), findsOneWidget);
    // 95 min locker auf dem Rad: 40 + 20 × 5/60 ≈ 41,7 → 40 g/h.
    expect(find.text('40'), findsOneWidget);
    expect(find.textContaining('(geschätzt)'), findsOneWidget);

    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    expect(container.read(fuelStoreProvider).plans.single.scenario.sport, FuelSport.bike);
    expect(find.text('Gesichert'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Vorher'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Vorher'));
    await tester.pumpAndSettle();
    expect(find.text('3–4 h vorher'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Ins Ernährungstagebuch übernehmen'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Ins Ernährungstagebuch übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ins Ernährungstagebuch übernehmen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Ins Tagebuch übernehmen'), findsOneWidget);
    expect(find.textContaining('Platzhalter – wird durch deine echte Mahlzeit ersetzt'), findsNWidgets(2));
    await tester.tap(find.text('Übernehmen'));
    for (var round = 0; round < 5; round++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('3 Einträge heute im Tagebuch'), findsOneWidget);
    final meals = await tester.runAsync(() => container.read(mealRepositoryProvider).day(CalendarDay.today()));
    expect(meals!.map((meal) => meal.title.split(' · ').first).toSet(), {
      'Vor dem Training',
      'Verpflegung unterwegs',
      'Nach dem Training',
    });
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final saved = container.read(fuelStoreProvider).plans.single;
    expect(saved.loggedMealIDs.length, 3);
  });

  testWidgets('Aus dem Ausdauerplan: Werte übernommen, geänderte Einheit erkannt', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    PlanSlot slot(int minutes) => PlanSlot(
      id: 'slot-1',
      day: CalendarDay.today().adding(3),
      week: 0,
      phase: EndurancePhase.build,
      baseline: EnduranceWorkout(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.long,
        title: 'Langer Lauf',
        minutes: minutes,
        steps: const [],
        load: 110,
      ),
    );
    final navigator = Navigator.of(tester.element(find.byType(LiquidTabBar)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ListView(children: [FuelForSlotSection(slot: slot(120))]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verpflegung planen'), findsOneWidget);
    // Lang, locker, 120 min: 50 g/h.
    expect(find.text('Unterwegs 50 g Kohlenhydrate je Stunde'), findsOneWidget);
    await tester.tap(find.text('Verpflegung planen'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelPlanScreen), findsOneWidget);
    expect(find.text('Langer Lauf'), findsOneWidget);
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(container.read(fuelStoreProvider).planForSlot('slot-1'), isNotNull);

    // Einheit im Plan gekürzt: Abschnitt und Plan melden es, „anpassen“ übernimmt 90 min.
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ListView(children: [FuelForSlotSection(slot: slot(90))]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('hat sich seit dem Speichern geändert'), findsOneWidget);
    await tester.tap(find.text('Verpflegungsplan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Die Einheit hat sich geändert'), findsOneWidget);
    await tester.tap(find.textContaining('Die Einheit hat sich geändert'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Die Einheit hat sich geändert'), findsNothing);
    expect(find.text('1:30 h'), findsOneWidget);
  });

  testWidgets('Aus dem Wochenplan: Krafteinheit mit Verpflegungsplan', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(LiquidTabBar)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SessionGuideScreen(
          slot: const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
          day: CalendarDay.today().adding(1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Verpflegung planen'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Kraft, 45 min, Schwelle'), findsOneWidget);
    expect(find.text('Unterwegs keine Kohlenhydrate nötig – Plan für davor und danach'), findsOneWidget);
    await tester.tap(find.text('Verpflegung planen'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelPlanScreen), findsOneWidget);
    expect(find.text('Kraft'), findsWidgets);
  });

  testWidgets('Szenario: Wetter aus der Vorhersage übernehmen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final weather = FakeWeather();
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [
            fuelWeatherServiceProvider.overrideWith(
              (ref) =>
                  FuelWeatherService(routes: ref.read(routeStoreProvider), location: FakeLocation(), weather: weather),
            ),
          ],
        ),
      ) as Widget,
    );
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(LiquidTabBar)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => FuelScenarioScreen(
          scenario: FuelScenario(sport: FuelSport.run, minutes: 60, weightKilograms: 70, day: CalendarDay.today()),
          productIDs: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Aus der Vorhersage übernehmen'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Aus der Vorhersage übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus der Vorhersage übernehmen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Wetter ab 9 Uhr: 24 °C, 80 % Luftfeuchte'), findsOneWidget);
    expect(find.text('24 °C'), findsOneWidget);
  });

  testWidgets('Plan: Vorschläge mit Lebensmitteln, Alltag unterwegs, So nimmst du es, Vorrat in der Packliste', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    // Im Speicher sofort gesetzt; das Schreiben in die Datenbank läuft nebenher.
    unawaited(container.read(fuelStoreProvider).setStock('builtin.gel', const FuelStock(count: 3)));
    final navigator = Navigator.of(tester.element(find.byType(LiquidTabBar)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => FuelPlanScreen(
          scenario: FuelScenario(
            sport: FuelSport.bike,
            minutes: 180,
            weightKilograms: 70,
            intensity: FuelIntensity.tempo,
            day: CalendarDay.today(),
          ),
          productIDs: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Sportnahrung: das vorrätige Gel ist automatisch eingeplant.
    await tester.scrollUntilVisible(find.text('Packliste'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('aus dem Vorrat'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('So nimmst du es'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('nachspülen'), findsOneWidget);

    // Alltag: Apfelschorle, Banane & Co.
    await tester.scrollUntilVisible(find.text('Alltag'), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Alltag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Apfelschorle mit einer Prise Salz'), findsWidgets);
    await tester.scrollUntilVisible(find.text('So nimmst du es'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Saft und Wasser 1 : 1'), findsOneWidget);
    expect(find.textContaining('aus dem Vorrat'), findsNothing);

    // Vorher: konkreter Vorschlag, „Andere Idee“ wechselt.
    await tester.scrollUntilVisible(find.text('Vorher'), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Vorher'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scheiben Toastbrot'), findsWidgets);
    List<String> shown() => [
      for (final template in FuelMeals.templates)
        if (find.text(template.name).evaluate().isNotEmpty) template.name,
    ];
    final before = shown();
    final other = find.text('Andere Idee').first;
    await tester.ensureVisible(other);
    await tester.pumpAndSettle();
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(shown(), isNot(before));
    expect(find.textContaining('Ballaststoff- und fettarm'), findsOneWidget);

    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    final saved = container.read(fuelStoreProvider).plans.single;
    expect(saved.everyday, isTrue);
    expect(saved.mealChoices, isNotEmpty);
  });

  testWidgets('Vorrat: Produkt hinzufügen, mehr, weniger', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    Navigator.of(tester.element(find.byType(LiquidTabBar)))
        .push(MaterialPageRoute<void>(builder: (_) => const FuelStockScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Noch nichts – unten ein Produkt hinzufügen.'), findsOneWidget);
    await tester.tap(find.text('Koffein-Gel'));
    await tester.pumpAndSettle();
    expect(container.read(fuelStoreProvider).stock['builtin.gelcaffeine']!.count, 1);
    await tester.tap(find.byTooltip('Eins mehr'));
    await tester.tap(find.byTooltip('Eins mehr'));
    await tester.pumpAndSettle();
    expect(container.read(fuelStoreProvider).stock['builtin.gelcaffeine']!.count, 3);
    await tester.tap(find.byTooltip('Eins weniger'));
    await tester.pumpAndSettle();
    expect(container.read(fuelStoreProvider).stock['builtin.gelcaffeine']!.count, 2);
    expect(fuelStockSummary(container.read(fuelStoreProvider), CalendarDay.today()), '2 Portionen von 1 Produkt');
  });
}

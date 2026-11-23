// Fuel Planner: Einstieg in der Ernährung, Plan berechnen, speichern, ins Tagebuch übernehmen; Einstieg aus einer
// Einheit des Ausdauerplans; Speicher strikt je Benutzer.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/fuel/fuel_for_slot.dart';
import 'package:aironludi/features/fuel/fuel_plan_screen.dart';
import 'package:aironludi/features/fuel/fuel_planner_screen.dart';
import 'package:aironludi/features/fuel/fuel_scenario_screen.dart';
import 'package:aironludi/services/fuel/fuel_diary_writer.dart';
import 'package:aironludi/services/fuel/fuel_store.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  group('Speicher je Benutzer', () {
    test('Eigener Stand wird gespeichert und neu geladen', () async {
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
      final again = FuelStore(settings, username: 'anna');
      expect(again.profile.gut, GutTolerance.trained);
      expect(again.ownProducts.single.carbs, 57);
      expect(again.planForSlot('slot')?.id, id);
      expect(again.hasForeignData, isFalse);
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

    test('Tagebuch: je Phase eine Mahlzeit auf dem Tag des Plans zur Uhrzeit der Phase', () async {
      final db = CoachDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final meals = MealRepository(db);
      const day = CalendarDay(2026, 12, 6);
      final plan = FuelPlanner.plan(
        const FuelScenario(
          sport: FuelSport.run,
          minutes: 110,
          weightKilograms: 70,
          isRace: true,
          title: 'Halbmarathon',
          day: day,
          startMinuteOfDay: 9 * 60,
        ),
        setup: [FuelProducts.classicGel],
      );
      final saved = await writeFuelPlanToDiary(meals, plan, phases: {...FuelPhase.values});
      expect(saved.length, 3);
      final stored = await meals.day(day);
      expect(stored.length, 3);
      final pre = stored.firstWhere((meal) => meal.title.startsWith('Vor dem Training'));
      expect(pre.createdAt, DateTime(2026, 12, 6, 5, 30)); // 3½ h vor 9 Uhr
      expect(pre.title, 'Vor dem Training · Halbmarathon');
      final intra = stored.firstWhere((meal) => meal.title.startsWith('Verpflegung unterwegs'));
      expect(intra.items.any((item) => item.name == FuelProducts.classicGel.name), isTrue);
      final post = stored.firstWhere((meal) => meal.title.startsWith('Nach dem Training'));
      expect(post.createdAt, DateTime(2026, 12, 6, 10, 50));
    });
  });

  testWidgets('Ernährung › Fuel Planner: berechnen, speichern, ins Tagebuch', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Ernährung')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Fuel Planner'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Fuel Planner'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelPlannerScreen), findsOneWidget);
    expect(find.text('Noch keine Pläne'), findsOneWidget);

    await tester.tap(find.text('Neuer Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelScenarioScreen), findsOneWidget);
    await tester.tap(find.text('Rad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Berechnen'));
    await tester.pumpAndSettle();

    expect(find.byType(FuelPlanScreen), findsOneWidget);
    expect(find.text('Unterwegs je Stunde'), findsOneWidget);
    expect(find.text('Kohlenhydrate'), findsWidgets);
    // 90 min locker auf dem Rad: 40 g/h.
    expect(find.text('40'), findsOneWidget);
    expect(find.text('Glukose : Fruktose unterwegs'), findsOneWidget);

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
    await tester.tap(find.text('Ins Ernährungstagebuch übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Ins Tagebuch übernehmen'), findsOneWidget);
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
    expect(container.read(fuelStoreProvider).plans.single.loggedAt, isNotNull);
  });

  testWidgets('Aus einer Einheit des Ausdauerplans: Werte übernommen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final slot = PlanSlot(
      id: 'slot-1',
      day: CalendarDay.today().adding(3),
      week: 0,
      phase: EndurancePhase.build,
      baseline: const EnduranceWorkout(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.long,
        title: 'Langer Lauf',
        minutes: 120,
        steps: [],
        load: 110,
      ),
    );
    final navigator = Navigator.of(tester.element(find.byType(LiquidTabBar)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ListView(children: [FuelForSlotSection(slot: slot)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verpflegung planen'), findsOneWidget);
    // Lang, locker, 120 min: 40 g/h.
    expect(find.text('Unterwegs 40 g Kohlenhydrate je Stunde'), findsOneWidget);
    await tester.tap(find.text('Verpflegung planen'));
    await tester.pumpAndSettle();
    expect(find.byType(FuelPlanScreen), findsOneWidget);
    expect(find.text('Langer Lauf'), findsOneWidget);
    expect(find.text(GermanFormat.date(slot.day)), findsOneWidget);
  });
}

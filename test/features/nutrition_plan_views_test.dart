// Eigene Rezepte, Woche, Gewichtsverlauf und empfangene Mahlzeit.
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/nutrition/meal_share_views.dart';
import 'package:aironludi/features/nutrition/nutrition_plan_views.dart';
import 'package:aironludi/features/nutrition/weight_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;
import 'capture_views_test.dart' show host;

MealItem item(String name, double grams, double kcal) =>
    MealItem(name: name, grams: grams, source: MealItemSource.manual, per100g: NutrientValues({Nutrient.kcal: kcal}));

void main() {
  final chili = OwnRecipe(name: 'Chili', ingredients: [item('Bohnen', 600, 100), item('Hack', 400, 200)], portions: 4);

  testWidgets('Rezept bearbeiten: Portionen, gekochtes Gewicht, Vorrat; Original bleibt unverändert', (tester) async {
    final results = await host(tester, () => OwnRecipeEditor(recipe: chili));
    await tester.tap(find.byTooltip('Mehr Portionen'));
    await tester.pump();
    expect(find.text('5 Portionen'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Gekocht gewogen'), '900');
    await tester.tap(find.text('Neu gekocht – 5 Portionen im Vorrat'));
    await tester.pump();
    expect(find.text('5 Portionen'), findsNWidgets(2));
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    final saved = results.single! as OwnRecipe;
    expect((saved.portions, saved.cookedGrams, saved.remainingPortions), (5, 900.0, 5.0));
    expect(saved.item().grams, 180);
    expect((chili.portions, chili.cookedGrams), (4, null));
  });

  testWidgets('vom Topf eintragen: Portionen oder gewogen', (tester) async {
    var results = await host(tester, () => Scaffold(body: LogOwnRecipeSheet(recipe: chili)));
    await tester.tap(find.text('1½'));
    await tester.pumpAndSettle();
    expect(results, [375.0]);

    results = await host(tester, () => Scaffold(body: LogOwnRecipeSheet(recipe: chili)));
    final enter = find.widgetWithText(TextButton, 'Eintragen');
    expect(tester.widget<TextButton>(enter).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '320');
    await tester.pump();
    await tester.tap(enter);
    await tester.pumpAndSettle();
    expect(results, [320.0]);
  });

  test('Woche: Hinweise aus den Schutzgrenzen', () {
    expect(NutritionWeekScreen.paceNote(NutritionGoal.lose, -1.2), contains('schneller ab als 1 %'));
    expect(NutritionWeekScreen.paceNote(NutritionGoal.lose, -0.6), isNull);
    expect(NutritionWeekScreen.paceNote(NutritionGoal.lose, 0.2), contains('steigt trotz Ziel'));
    expect(NutritionWeekScreen.paceNote(NutritionGoal.gain, 0.8), contains('schneller zu'));
    expect(NutritionWeekScreen.paceNote(NutritionGoal.maintain, -2), isNull);
  });

  testWidgets('Gewichtsverlauf: Wägung eintragen zählt als Wochen-Check-in', (tester) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Ernährung')));
    await tester.pumpAndSettle();
    final link = find.text('Gewichtsverlauf');
    await tester.scrollUntilVisible(link, 200);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(WeightTrendScreen), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(WeightTrendScreen)));
    final settings = container.read(coachSettingsProvider);
    expect(settings.nutrition.lastCheckInDay, CalendarDay.today());
    expect(find.text('Noch keine Wägungen.'), findsOneWidget);
    final enter = find.widgetWithText(ListTile, 'Eintragen');
    expect(tester.widget<ListTile>(enter).enabled, isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Gewicht'), '20');
    await tester.pump();
    expect(tester.widget<ListTile>(enter).enabled, isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Gewicht'), '72,4');
    await tester.pump();
    await tester.tap(enter);
    await tester.pumpAndSettle();
    expect(settings.weights.single.kilograms, 72.4);
    expect(find.text('72,4 kg'), findsOneWidget);
  });

  testWidgets('empfangene Mahlzeit: als neuer Eintrag ins Tagebuch', (tester) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    final meal = SharedMeal(title: 'Linsensuppe', items: [item('Linsen', 300, 110)]);
    unawaitedPush(tester, ReceivedMealScreen(preloaded: meal));
    await tester.pumpAndSettle();
    expect(find.text('LINSENSUPPE · 330 KCAL'), findsOneWidget);
    await tester.tap(find.text('In mein Tagebuch (heute)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Eingetragen unter'), findsOneWidget);
    final meals = await tester.runAsync(() => container.read(mealRepositoryProvider).all());
    expect((meals!.single.title, meals.single.hint), ('Linsensuppe', 'Geteilt'));
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Als Favorit merken')).enabled, isFalse);
  });
}

void unawaitedPush(WidgetTester tester, Widget page) {
  Navigator.of(tester.element(find.byType(NavigationBar))).push(MaterialPageRoute<void>(builder: (_) => page));
}

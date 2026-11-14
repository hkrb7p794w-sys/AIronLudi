// Ernährungsansicht: Schnelleintrag, Mahlzeitenliste, Übersicht anpassen.
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/nutrition/nutrition_screen.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  Future<void> openNutrition(WidgetTester tester) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Ernährung')));
    await tester.pumpAndSettle();
  }

  testWidgets('Nur Kalorien: Eintrag erscheint in der Mahlzeitenliste', (tester) async {
    await openNutrition(tester);
    expect(find.byType(NutritionScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Erfassen'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Nur kcal'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Eintragen')).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Kalorien'), '650');
    await tester.enterText(find.widgetWithText(TextField, 'Was war es? (optional)'), 'Kantine');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Eintragen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NutritionScreen)));
    final meals = await tester.runAsync(() => container.read(mealRepositoryProvider).all());
    expect(meals!.single.title, 'Kantine');
    expect(NutritionSummary.totals(meals.single.items)[Nutrient.kcal], 650);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Kantine'), 200);
    expect(find.text('Kantine'), findsWidgets);
  });

  testWidgets('Übersicht anpassen: Karte ausblenden bleibt gespeichert', (tester) async {
    await openNutrition(tester);
    final adjust = find.text('Übersicht anpassen');
    await tester.scrollUntilVisible(adjust, 200);
    await tester.tap(adjust);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NutritionDashboardEditor)));
    final card = NutritionCard.water;
    await tester.tap(find.widgetWithText(SwitchListTile, card.label));
    await tester.pumpAndSettle();
    expect(container.read(coachSettingsProvider).nutritionDashboard.visible, isNot(contains(card)));
  });
}

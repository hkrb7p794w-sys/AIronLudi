// Ernährungsansicht: Schnelleintrag, Mahlzeitenliste, Übersicht anpassen.
import 'dart:convert';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/nutrition/nutrition_screen.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  Future<void> openNutrition(WidgetTester tester) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Ernährung')));
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
    await tester.scrollUntilVisible(find.text('Kantine'), 200, scrollable: _nutritionList);
    expect(find.text('Kantine'), findsWidgets);
  });

  testWidgets('Nur Kalorien: Makros und Mikros ohne Angabe zeigen keinen Mangel', (tester) async {
    await openNutrition(tester);
    await tester.tap(find.byTooltip('Erfassen'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Nur kcal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Kalorien'), '650');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Eintragen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    // Protein ist beim Schnell-Eintrag unbekannt: übrig ist höchstens das ganze Ziel.
    expect(find.textContaining('noch höchstens'), findsWidgets);
    await _reveal(tester, find.text('Alle Nährstoffe'));
    await tester.tap(find.text('Alle Nährstoffe'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Eisen'), 200, scrollable: _nutritionList);
    expect(find.text('Keine Angabe in den Einträgen'), findsWidgets);
    expect(find.textContaining(RegExp(r'^– / 1[16] mg$')), findsOneWidget);
  });

  testWidgets('Schnellsuche: Markenprodukt aus Open Food Facts (Nutella) mit Nährwerten, „+“ trägt ein', (
    tester,
  ) async {
    final requests = <Uri>[];
    final transport = FakeHttpTransport((request) {
      requests.add(request.url);
      return HttpResponse(
        200,
        utf8.encode(
          jsonEncode({
            'hits': [
              {
                'code': '3017620422003',
                'product_name': 'Nutella',
                'brands': ['Ferrero'],
                'serving_quantity': 15,
                'serving_size': '15 g',
                'nutriments': {
                  'energy-kcal_100g': 539,
                  'proteins_100g': 6.3,
                  'carbohydrates_100g': 57.5,
                  'fat_100g': 30.9,
                },
              },
            ],
          }),
        ),
      );
    });
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [openFoodFactsProvider.overrideWithValue(OpenFoodFactsClient(transport: transport))],
        ),
      ) as Widget,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Ernährung')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Nutella');
    await tester.pump();
    // Erst nach der Tipp-Pause online.
    expect(requests, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(requests.single.host, 'search.openfoodfacts.org');
    expect(find.text('MARKENPRODUKTE'), findsOneWidget);
    expect(find.text('Nutella (Ferrero)'), findsOneWidget);
    expect(find.textContaining('je 100 g: 539 kcal · 6 g P · 58 g KH · 31 g F'), findsOneWidget);
    await tester.tap(find.byTooltip('Nutella (Ferrero) eintragen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NutritionScreen)));
    final meals = await tester.runAsync(() => container.read(mealRepositoryProvider).all());
    final item = meals!.single.items.single;
    expect((item.name, item.grams, item.barcode), ('Nutella (Ferrero)', 15.0, '3017620422003'));
    expect(NutritionSummary.totals(meals.single.items)[Nutrient.kcal], closeTo(80.85, 0.01));
  });

  testWidgets('Übersicht anpassen: Karte ausblenden bleibt gespeichert', (tester) async {
    await openNutrition(tester);
    final adjust = find.text('Übersicht anpassen');
    await _reveal(tester, adjust);
    await tester.tap(adjust);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NutritionDashboardEditor)));
    final card = NutritionCard.water;
    await tester.tap(find.widgetWithText(SwitchListTile, card.label));
    await tester.pumpAndSettle();
    expect(container.read(coachSettingsProvider).nutritionDashboard.visible, isNot(contains(card)));
  });
}

/// Liste des Reiters Ernährung (mit fünf Reitern liegen mehrere Listen im Baum).
final _nutritionList = find
    .descendant(
      of: find.byType(NutritionScreen),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down),
    )
    .first;

/// In die Mitte der Liste holen – sonst liegt der Eintrag knapp unter der schwebenden Tab-Leiste.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _nutritionList);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

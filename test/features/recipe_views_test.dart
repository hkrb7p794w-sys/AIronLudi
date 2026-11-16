// Rezeptideen: Einstieg in Ernährung, Zeitraum, Wünsche und Allergene, ohne Worker ein Hinweis.
import 'dart:async';

import 'package:aironludi/features/recipes/recipe_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Rezeptideen: Zeitraum, Erstellen ohne Worker, Wünsche', (tester) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
    unawaited(
      Navigator.of(tester.element(find.byType(CupertinoTabBar)))
          .push(MaterialPageRoute<void>(builder: (_) => const RecipesScreen())),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('7 Tage'), findsOneWidget);
    expect(find.textContaining('Ziel je Tag:'), findsOneWidget);
    await tester.tap(find.byTooltip('Weniger'));
    await tester.pumpAndSettle();
    expect(find.text('6 Tage'), findsOneWidget);

    await tester.tap(find.text('Rezeptideen erstellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Für Rezeptideen muss der KI-Worker'), findsOneWidget);

    await tester.tap(find.text('Wünsche und Allergene'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipePreferencesScreen), findsOneWidget);
    await tester.tap(find.text(Allergen.values.first.label));
    await tester.pumpAndSettle();
    final recipes = container.read(coachSettingsProvider).recipes;
    expect(recipes.allergens, {Allergen.values.first});
    await tester.tap(find.text(Allergen.values.first.label));
    await tester.pumpAndSettle();
    expect(container.read(coachSettingsProvider).recipes.allergens, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('Einkaufsmengen ab einem Kilo in kg', () {
    expect(ShoppingListScreen.amount(850), '850 g');
    expect(ShoppingListScreen.amount(1240), '1,2 kg');
  });
}

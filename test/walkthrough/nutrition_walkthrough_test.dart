// Durchlauf Ernährung: Tagebuch, Mahlzeit bearbeiten, Aktionen je Mahlzeit, Tage wechseln.
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/fuel/fuel_profile_screen.dart';
import 'package:aironludi/features/nutrition/meal_editor.dart';
import 'package:aironludi/features/nutrition/nutrition_screen.dart';
import 'package:aironludi/services/fuel/fuel_store.dart';
import 'package:aironludi/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

void main() {
  testWidgets(
    'Tagebuch: Wasser, Mahlzeit bearbeiten, Favorit, verschieben, löschen, Tage',
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
      final container = await startDemo(tester);
      await tab(tester, 'Ernährung');
      expect(find.byType(NutritionScreen), findsOneWidget);
      await reveal(tester, find.text('Haferflocken mit Skyr und Beeren'));

      // Wasser
      step('Wasser');
      await tapText(tester, '+250 ml');
      expect(find.textContaining('Wasser 0,25'), findsOneWidget);

      // Mahlzeit antippen: Editor, Menge ändern, speichern.
      step('Mahlzeit antippen: Editor, Menge ändern, speichern.');
      await tapText(tester, 'Haferflocken mit Skyr und Beeren');
      expect(find.byType(MealEditorScreen), findsOneWidget);
      await tapText(tester, 'Sichern');
      expect(find.byType(MealEditorScreen), findsNothing);

      // Lange drücken: Favorit merken
      step('Lange drücken: Favorit merken');
      Future<void> actions(String meal) async {
        final row = await reveal(tester, find.text(meal));
        await tester.longPress(row);
        await settle(tester);
      }

      await actions('Haferflocken mit Skyr und Beeren');
      await tapText(tester, 'Als Favorit merken');
      expect(container.read(coachSettingsProvider).favoriteMeals.map((meal) => meal.title), [
        'Haferflocken mit Skyr und Beeren',
      ]);
      await actions('Haferflocken mit Skyr und Beeren');
      expect(find.text('Aus Favoriten entfernen'), findsOneWidget);
      await tapText(tester, 'Aus Favoriten entfernen');
      expect(container.read(coachSettingsProvider).favoriteMeals, isEmpty);

      // Verschieben nach Abendessen
      step('Verschieben nach Abendessen');
      await actions('Hähnchen, Reis und Brokkoli');
      await tapText(tester, 'Verschieben nach Abendessen');
      expect(find.textContaining('ABENDESSEN'), findsWidgets);

      // Löschen
      step('Löschen');
      await actions('Hähnchen, Reis und Brokkoli');
      await tapText(tester, 'Löschen');
      expect(find.text('Hähnchen, Reis und Brokkoli'), findsNothing);

      // Als eigenes Rezept speichern
      step('Als eigenes Rezept speichern');
      await actions('Haferflocken mit Skyr und Beeren');
      await tapText(tester, 'Als eigenes Rezept speichern');
      await tapText(tester, 'Sichern');
      expect(container.read(coachSettingsProvider).ownRecipes.map((recipe) => recipe.name), [
        'Haferflocken mit Skyr und Beeren',
      ]);

      // Tag zurück und wieder vor
      step('Tag zurück und wieder vor');
      await tester.tap(await reveal(tester, find.byTooltip('Vorige Woche')));
      await settle(tester);
      await tester.tap(await reveal(tester, find.byTooltip('Nächste Woche')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.add), findsWidgets);
    },
  );

  testWidgets(
    'Erfassen: Vorschläge in den Korb, suchen, eintragen; Gewicht eintragen',
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
      final container = await startDemo(tester);
      await tab(tester, 'Ernährung');
      final before = (await tester.runAsync(() => container.read(mealRepositoryProvider).all()))!.length;

      step('Erfassen öffnen, Vorschlag hinzufügen');
      await tester.tap(find.byTooltip('Erfassen').first);
      await settle(tester);
      expect(find.text('Hähnchenbrust'), findsWidgets);
      await tester.tap(find.byTooltip('Hähnchenbrust hinzufügen').first);
      await settle(tester);
      expect(find.text('Eintragen (1)'), findsOneWidget);

      step('Suchen');
      await tester.enterText(find.byType(TextField).last, 'Brokkoli');
      await settle(tester, milliseconds: 600);
      await tester.tap(find.byTooltip('Brokkoli hinzufügen').first);
      await settle(tester);
      expect(find.text('Eintragen (2)'), findsOneWidget);

      step('Eintragen');
      await tester.tap(find.text('Eintragen (2)'));
      await settle(tester, milliseconds: 600);
      final after = (await tester.runAsync(() => container.read(mealRepositoryProvider).all()))!;
      expect(after.length, before + 1);
      expect(after.any((meal) => meal.items.length == 2), isTrue);

      step('Gewicht eintragen');
      await tapText(tester, 'Gewichtsverlauf');
      expect(find.text('Wägung eintragen'.toUpperCase()), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Gewicht'), '74,3');
      await settle(tester);
      await tapText(tester, 'Eintragen');
      expect(container.read(coachSettingsProvider).weights.last.kilograms, 74.3);
      await back(tester);
    },
  );

  testWidgets(
    'Verpflegung: eigenes Produkt anlegen, wiederfinden, löschen; Profil und Vorrat',
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
      final container = await startDemo(tester);
      await tab(tester, 'Ernährung');
      await tapText(tester, 'Verpflegung');
      step('Meine Produkte: anlegen');
      await tapText(tester, 'Meine Produkte und Mischungen');
      await tapText(tester, 'Produkt oder Mischung anlegen');
      expect(find.text('Neues Produkt'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mein Gel');
      await tester.enterText(await reveal(tester, find.widgetWithText(TextField, 'Kohlenhydrate (g)')), '25');
      await tester.enterText(await reveal(tester, find.widgetWithText(TextField, 'Natrium (mg)')), '50');
      await settle(tester);
      await tester.tap(find.text('Sichern'));
      await settle(tester);
      expect(container.read(fuelStoreProvider).ownProducts.map((product) => product.name), ['Mein Gel']);
      expect(find.text('Mein Gel'), findsOneWidget);

      step('wieder öffnen und löschen');
      await tapText(tester, 'Mein Gel');
      await tapText(tester, 'Löschen');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Löschen')));
      await settle(tester);
      expect(container.read(fuelStoreProvider).ownProducts, isEmpty);
      await back(tester);

      step('Profil und Vorrat');
      await tapText(tester, 'Mein Profil');
      expect(find.byType(FuelProfileScreen), findsOneWidget);
      await back(tester);
      await tapText(tester, 'Vorrat');
      await back(tester);
    },
  );
}

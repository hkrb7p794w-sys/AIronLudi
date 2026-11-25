// Durchlauf Rezepte: eigenes Rezept aus einer Mahlzeit, gewogen eintragen, bearbeiten, löschen; Rezeptideen mit
// Kochplan und Vorrat.
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

void main() {
  walk('Eigene Rezepte: anlegen, gewogen eintragen, bearbeiten, löschen', (tester, device) async {
    final container = await startDemo(tester, device: device);
    await tab(tester, 'Ernährung');

    step('Leerer Zustand');
    await tapText(tester, 'Eigene Rezepte und Meal-Prep');
    expect(find.text('Noch keine eigenen Rezepte'), findsOneWidget);

    step('Aus einer Mahlzeit anlegen (Knopf im leeren Zustand)');
    await tester.tap(find.text('Aus einer Mahlzeit anlegen'));
    await settle(tester, milliseconds: 600);
    await tapText(tester, 'Haferflocken mit Skyr und Beeren');
    expect(container.read(coachSettingsProvider).ownRecipes, hasLength(1));
    await back(tester);

    step('Gewogen eintragen');
    final before = (await tester.runAsync(() => container.read(mealRepositoryProvider).all()))!.length;
    await tapText(tester, 'Eigene Rezepte und Meal-Prep');
    await tapText(tester, 'Haferflocken mit Skyr und Beeren');
    await tester.enterText(find.widgetWithText(TextField, 'Gramm vom Topf'), '250');
    await tester.pump();
    await tester.tap(find.text('Eintragen'));
    await settle(tester, milliseconds: 600);
    final after = (await tester.runAsync(() => container.read(mealRepositoryProvider).all()))!;
    expect(after.length, before + 1);

    step('Bearbeiten: Portionen und Name');
    await tester.tap(find.byTooltip('Bearbeiten').first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Overnight Oats');
    await tester.tap(find.text('Sichern'));
    await settle(tester);
    expect(container.read(coachSettingsProvider).ownRecipes.single.name, 'Overnight Oats');

    step('Löschen');
    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await settle(tester);
    final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.text('Löschen'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await settle(tester);
    }
    expect(container.read(coachSettingsProvider).ownRecipes, isEmpty);
  });

  walk('Rezeptideen: Kochplan, Vorrat aus dem Kühlschrank', (tester, device) async {
    await startDemo(tester, device: device);
    await tab(tester, 'Ernährung');
    await tapText(tester, 'Rezeptideen für die kommende Woche');
    await scrollToEnd(tester);

    step('Kochen planen');
    await tapText(tester, 'Kochen planen: für wen, wie viel');
    await scrollToEnd(tester);
    await back(tester);

    step('Vorrat: Lebensmittel ergänzen');
    await tapText(tester, 'Was koche ich daraus? (Foto)');
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'Lebensmittel ergänzen',
    );
    if (field.evaluate().isNotEmpty) {
      await tester.enterText(field, 'Zucchini');
      await tester.tap(find.byTooltip('Ergänzen'));
      await settle(tester);
      expect(find.text('Zucchini'), findsWidgets);
    }
    await scrollToEnd(tester);
    await back(tester);
  });
}

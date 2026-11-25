// Durchlauf Einrichtung und Heute: erster Start bis „Los geht’s“, danach Heute mit Demo-Daten (KI-Empfehlungen ohne
// Worker, Heute anpassen, Verschieben, Woche auslassen, Morgenbericht).
import 'package:aironludi/features/today/today_screen.dart';
import 'package:aironludi/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

void main() {
  walk('Einrichtung: erster Start bis „Los geht’s“', (tester, device) async {
    final container = await startFresh(tester, device: device);
    for (var page = 0; page < 20; page++) {
      final finish = find.text('Los geht’s');
      if (finish.evaluate().isNotEmpty) {
        step('Einrichtung: Zusammenfassung');
        await tester.tap(finish);
        await settle(tester);
        break;
      }
      // Pflichtangaben wie eine Person: Körperdaten, Wochenplan per Vorschlag.
      if (find.widgetWithText(TextField, 'Gewicht in kg').evaluate().isNotEmpty) {
        await tester.enterText(find.widgetWithText(TextField, 'Gewicht in kg'), '75');
        await tester.enterText(find.widgetWithText(TextField, 'Größe in cm'), '180');
        await tester.enterText(find.widgetWithText(TextField, 'Alter'), '35');
        await tester.tap(await reveal(tester, find.text('Männlich')));
        await settle(tester);
      }
      // Wochenplan: nur Tage antippen; „Weiter“ schlägt den Plan dann vor.
      if (find.text('Wochenplan vorschlagen').evaluate().isNotEmpty) {
        for (final day in ['Mo', 'Mi', 'Sa']) {
          final chip = find.ancestor(of: find.text(day).first, matching: find.byType(InkWell)).first;
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pump();
        }
        await settle(tester);
      }
      final next = find.widgetWithText(FilledButton, 'Weiter');
      final enabled = tester.widget<FilledButton>(next).onPressed != null;
      final texts = [for (final e in find.byType(Text).evaluate().take(4)) (e.widget as Text).data];
      step('Einrichtung Seite ${page + 1}: ${enabled ? 'Weiter' : 'GESPERRT'} – $texts');
      expect(enabled, isTrue, reason: 'Weiter gesperrt auf Seite ${page + 1}: $texts');
      await tester.tap(next);
      await settle(tester);
    }
    expect(container.read(coachSettingsProvider).profile.onboardingDone, isTrue);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  walk('Heute: KI-Empfehlungen ohne Worker, Mobility, Verschieben, anpassen', (tester, device) async {
    await startDemo(tester, device: device);
    expect(find.byType(TodayScreen), findsOneWidget);

    step('KI-Empfehlungen ohne Worker');
    await tapText(tester, 'KI-Empfehlungen');
    await scrollToEnd(tester);
    await back(tester);

    step('Mobility für heute');
    await tapText(tester, 'Mobility für heute', contains: true);
    await scrollToEnd(tester);
    await back(tester);

    step('Verschieben');
    await tapText(tester, 'Verschieben');
    await scrollToEnd(tester);
    await back(tester);

    step('Heute anpassen');
    await tapText(tester, 'Heute anpassen');
    await scrollToEnd(tester);
    await back(tester);

    step('Woche: Ziele und Verlauf');
    await tapText(tester, 'Diese Woche, Ziele und Verlauf');
    await scrollToEnd(tester);
    await back(tester);
  });
}

// Durchlauf Quellen: Bibliothek mit Regeln und Studien, eigene Quelle anlegen, wiederfinden und löschen.
import 'package:aironludi/features/evidence/evidence_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

void main() {
  walk('Quellen: Bibliothek, eigene Quelle anlegen und löschen', (tester, device) async {
    final container = await startDemo(tester, device: device);
    await tab(tester, 'Ich');

    step('Allgemein › Quellen und Regeln');
    await tapText(tester, 'Allgemein');
    await tapText(tester, 'Quellen und Regeln');
    expect(find.byType(EvidenceLibraryScreen), findsOneWidget);
    await tester.tap(await reveal(tester, find.byType(EvidenceRuleRow)));
    await settle(tester);
    await scrollToEnd(tester);
    await home(tester);

    step('KI und Automatisierung › Eigene Quellen: anlegen');
    await tab(tester, 'Ich');
    await tapText(tester, 'KI und Automatisierung');
    await tapText(tester, 'Eigene Quellen');
    await tapText(tester, 'Quelle hinzufügen');
    Future<void> type(String hint, String text) async {
      final field = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == hint);
      await tester.enterText(await reveal(tester, field), text);
      await tester.pump();
    }

    await type('Kurzbeleg, z. B. Schoenfeld et al. 2017', 'Muster et al. 2024');
    await type('DOI, PMID oder Link', '10.1000/xyz123');
    await type('Was sagt die Studie?', 'Zwei Krafteinheiten pro Woche reichen für deutliche Fortschritte.');
    await tester.tap(await reveal(tester, find.byType(SwitchListTile).first));
    await settle(tester);
    await tester.tap(find.text('Sichern'));
    await settle(tester);
    expect(container.read(coachSettingsProvider).userSources.map((source) => source.citation), ['Muster et al. 2024']);
    expect(find.text('Muster et al. 2024'), findsOneWidget);

    step('wieder öffnen und löschen');
    await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
    await settle(tester);
    final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.text('Löschen'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await settle(tester);
    }
    expect(container.read(coachSettingsProvider).userSources, isEmpty);
  });
}

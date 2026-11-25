// Durchlauf Konto, Freunde und Liga gegen einen nachgebauten Worker: Konto anlegen, Freundschaftsanfrage annehmen,
// Feed mit Reaktion und Kommentar, jemanden suchen und anfragen, Rangliste, Challenge, abmelden.
import 'package:aironludi/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_worker.dart';
import 'walkthrough.dart';

/// Texte der obersten Seite (zur Fehlersuche im Protokoll).
void dumpTexts(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final text = (element.widget as Text).data;
    if (text != null) debugPrint('  · $text');
  }
}

void main() {
  walk('Konto anlegen, Freunde, Feed, Suche, Liga, abmelden', (tester, device) async {
    final worker = FakeWorker();
    final container = await startDemo(
      tester,
      device: device,
      overrides: [workerTransportProvider.overrideWithValue(worker.transport)],
    );
    await tab(tester, 'Ich');

    step('Konto erstellen');
    await tapText(tester, 'Konto erstellen');
    Future<void> fill(String label, String text) async {
      final field = find.widgetWithText(TextField, label);
      if (field.evaluate().isEmpty) return;
      await tester.enterText(await reveal(tester, field), text);
      await tester.pump();
    }

    final server = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText?.startsWith('https://') == true,
    );
    if (server.evaluate().isNotEmpty) await tester.enterText(server, fakeWorkerURL);
    await fill('Benutzername', 'lena');
    await fill('Anzeigename (z. B. Vorname)', 'Lena');
    await fill('Passwort', 'Sehr-geheim-2026');
    await fill('Passwort wiederholen', 'Sehr-geheim-2026');
    await fill('Einladungscode', 'EINLADUNG1');
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Konto erstellen').last);
    await settle(tester, milliseconds: 600);
    dumpTexts(tester);
    expect(find.text('Konto bereit'), findsOneWidget);
    await tapText(tester, 'Ich habe den Code sicher aufbewahrt');
    await tapText(tester, 'Fertig');
    expect(container.read(accountServiceProvider).isSignedIn, isTrue);

    step('Freunde & Liga: Anfrage von Mia annehmen');
    await tapText(tester, 'Freunde & Liga');
    await tester.tap(find.text('Freunde (1)'));
    await settle(tester);
    expect(find.text('Mia'), findsWidgets);
    await tester.tap(find.text('Annehmen').first);
    await settle(tester, milliseconds: 600);
    expect(find.text('Annehmen'), findsNothing);

    step('Feed: Mias Beitrag, Reaktion, Kommentar');
    await tester.tap(find.text('Feed'));
    await settle(tester, milliseconds: 600);
    expect(find.textContaining('Morgenlauf am See'), findsWidgets);
    // Der Feed zeigt kompakte Karten; Reaktionen und Kommentare in der Beitragsansicht.
    await tester.tap(find.textContaining('Morgenlauf am See').first);
    await settle(tester);
    await tester.tap(find.text('🔥').first);
    await settle(tester, milliseconds: 600);
    expect(worker.requests, contains('PUT v1/social/posts/p-mia-1/reaction'));
    await tester.tap(
      find.ancestor(of: find.byIcon(Icons.chat_bubble_outline), matching: find.byType(TextButton)).first,
    );
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Kommentar …'), 'Stark gelaufen!');
    await tester.pump();
    await tester.tap(find.byTooltip('Senden'));
    await settle(tester, milliseconds: 600);
    expect(worker.requests, contains('POST v1/social/posts/p-mia-1/comments'));
    expect(find.text('Stark gelaufen!'), findsOneWidget);
    await back(tester);
    await back(tester);

    step('Suche: Tom anfragen');
    await tester.tap(find.text('Freunde').first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Benutzername suchen'), 'tom');
    await settle(tester, milliseconds: 800);
    await tester.tap(find.text('Hinzufügen').first);
    await settle(tester, milliseconds: 600);
    expect(worker.requests, contains('POST v1/social/friends/tom'));

    step('Wettkampf: Rangliste, neue Challenge mit Mia');
    await tester.tap(find.text('Wettkampf').first);
    await settle(tester, milliseconds: 600);
    expect(find.text('Mia'), findsWidgets);
    await tapText(tester, 'Neue Challenge');
    await tester.enterText(find.widgetWithText(TextField, 'Name (optional), z. B. Novemberduell'), 'Novemberduell');
    await tester.tap(await reveal(tester, find.widgetWithText(CheckboxListTile, 'Mia')));
    await settle(tester);
    await tapText(tester, 'Challenge starten');
    await settle(tester, milliseconds: 600);
    expect(worker.requests, contains('POST v1/game/challenges'));
    await reveal(tester, find.text('Novemberduell'));
    await back(tester);

    step('Abmelden');
    await tapText(tester, 'Lena', contains: true);
    await tapText(tester, 'Auf diesem Gerät abmelden');
    await settle(tester, milliseconds: 600);
    expect(container.read(accountServiceProvider).isSignedIn, isFalse);
    expect(worker.requests, contains('POST v1/account/logout'));
  });

  walk('Trainings automatisch teilen: neues Training geht ohne Körperwerte an Freunde', (tester, device) async {
    final worker = FakeWorker();
    final container = await startDemo(
      tester,
      device: device,
      overrides: [workerTransportProvider.overrideWithValue(worker.transport)],
    );
    step('Anmelden als Mia');
    await tab(tester, 'Ich');
    await tapText(tester, 'Anmelden');
    final server = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText?.startsWith('https://') == true,
    );
    if (server.evaluate().isNotEmpty) await tester.enterText(server, fakeWorkerURL);
    await tester.enterText(find.widgetWithText(TextField, 'Benutzername'), 'mia');
    await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'geheim-mia');
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Anmelden').last);
    await settle(tester, milliseconds: 600);
    expect(container.read(accountServiceProvider).isSignedIn, isTrue);

    step('Einschalten');
    // Vor dem Training eingeschaltet (Trainings, die vor dem Einschalten begannen, bleiben privat).
    await container
        .read(socialAutoShareProvider)
        .setEnabled(true, now: DateTime.now().subtract(const Duration(hours: 2)));
    await settle(tester);
    expect(worker.postedBodies, isEmpty, reason: 'Ältere Trainings bleiben privat');

    step('Training nachtragen, Verlauf aktualisieren');
    await tab(tester, 'Plan');
    await tapText(tester, 'Woche');
    await tester.tap(find.byTooltip('Training nachtragen'));
    await settle(tester);
    await tester.tap(find.text('Sichern'));
    await settle(tester, milliseconds: 600);
    await home(tester);
    await tab(tester, 'Verlauf');
    await container.read(socialAutoShareProvider).run();
    await settle(tester, milliseconds: 600);
    expect(worker.postedBodies, hasLength(1));
    const bodyValues = ['heartRate', 'averageHeartRate', 'maxHeartRate', 'weight', 'hrv', 'sleep', 'calories', 'kcal'];
    expect(worker.postedBodies.single.keys.where((key) => bodyValues.any(key.toLowerCase().contains)), isEmpty);
    // Ein zweiter Lauf teilt nichts doppelt.
    await container.read(socialAutoShareProvider).run();
    await settle(tester);
    expect(worker.postedBodies, hasLength(1));
  });
}

// Durchlauf Datenquellen gegen nachgebaute Server: Garmin-Konto anmelden (mit Bestätigungscode), abrufen, Lauf und
// Tageswerte erscheinen, abmelden.
import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_garmin.dart';
import 'fake_whoop.dart';
import 'fake_worker.dart';
import 'walkthrough.dart';

void main() {
  walk('Garmin-Konto: anmelden mit Code, abrufen, Daten in Verlauf, abmelden', (tester, device) async {
    final garmin = FakeGarmin();
    final container = await startDemo(
      tester,
      device: device,
      overrides: [
        garminTransportProvider.overrideWithValue(garmin.transport),
        garminPauseProvider.overrideWithValue(() async {}),
      ],
    );
    await tab(tester, 'Ich');
    await tapText(tester, 'Training und Fitness');

    step('Anmelden');
    await tester.enterText(await reveal(tester, find.widgetWithText(TextField, 'E-Mail')), 'lena@example.com');
    await tester.enterText(await reveal(tester, find.widgetWithText(TextField, 'Passwort')), 'test-passwort');
    await settle(tester);
    await tapText(tester, 'Anmelden');
    await settle(tester, milliseconds: 600);
    await tester.enterText(await reveal(tester, find.widgetWithText(TextField, 'Bestätigungscode')), '123456');
    await tester.pump();
    await tapText(tester, 'Code bestätigen');
    await settle(tester, milliseconds: 600);
    expect(container.read(garminConnectProvider).isLoggedIn, isTrue);

    step('Jetzt abrufen');
    await tapText(tester, 'Jetzt abrufen');
    for (var i = 0; i < 20 && container.read(appModelProvider).isSyncing; i++) {
      await settle(tester, milliseconds: 500);
    }
    await settle(tester, milliseconds: 600);
    final activities = (await tester.runAsync(() => container.read(activityRepositoryProvider).all()))!;
    expect(
      activities.any((activity) => activity.name == 'Garmin-Lauf am Morgen'),
      isTrue,
      reason: '${garmin.requests}',
    );
    final today = (await tester.runAsync(() => container.read(metricsRepositoryProvider).day(CalendarDay.today())))!;
    expect(today.restingHeartRate, 47);

    step('Verlauf zeigt den Lauf');
    await home(tester);
    await tab(tester, 'Verlauf');
    await reveal(tester, find.text('Garmin-Lauf am Morgen'));

    step('Abmelden');
    await tab(tester, 'Ich');
    await tapText(tester, 'Training und Fitness');
    await tapText(tester, 'Abmelden');
    await settle(tester);
    final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.text('Abmelden'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await settle(tester);
    }
    expect(container.read(garminConnectProvider).isLoggedIn, isFalse);
  });

  walk('WHOOP: verbinden über den Browser, Rücksprung, Abruf mit Erholung, Schlaf und Training', (
    tester,
    device,
  ) async {
    final worker = FakeWorker();
    final whoop = FakeWhoop();
    final container = await startDemo(
      tester,
      device: device,
      overrides: [
        workerTransportProvider.overrideWithValue(worker.transport),
        whoopTransportProvider.overrideWithValue(whoop.transport),
      ],
    );
    final opened = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        opened.add('${call.arguments}');
        return true;
      },
    );

    step('Konto anmelden (WHOOP läuft über den Worker)');
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

    step('Mit WHOOP verbinden: Browser öffnet die Freigabe');
    await tapText(tester, 'Training und Fitness');
    await tapText(tester, 'Mit WHOOP verbinden');
    await settle(tester, milliseconds: 600);
    expect(opened.join(), contains('api.prod.whoop.com'));

    step('Rücksprung coach://whoop, Abruf');
    container.read(incomingLinkProvider.notifier).open(Uri.parse('coach://whoop?code=c1&state=whoop-state-1'));
    for (var i = 0; i < 10; i++) {
      await settle(tester, milliseconds: 400);
    }
    expect(container.read(whoopServiceProvider).isConnected, isTrue);
    expect(worker.requests, contains('POST v1/whoop/token'));
    expect(whoop.requests.where((request) => request.endsWith('/v2/recovery')), isNotEmpty);
    final activities = (await tester.runAsync(() => container.read(activityRepositoryProvider).all()))!;
    expect(activities.where((activity) => activity.trainingEffectLabel?.startsWith('WHOOP') ?? false), isNotEmpty);
  });
}

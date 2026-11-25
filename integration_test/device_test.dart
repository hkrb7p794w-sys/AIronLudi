// Gerätetest auf echtem iOS bzw. Android (Simulator/Emulator in GitHub Actions, `device-test.yml`): die echte App mit
// echtem Start (`main`), echter Datenbank, echten Ordnern, Schlüsselbund bzw. sicherem Speicher und nativen Brücken.
// Ersetzt nicht das eigene Gerät (Garmin, WHOOP, SideStore), aber alles, was das Betriebssystem allein prüfen kann.
import 'dart:io';

import 'package:aironludi/features/gym/active_workout_screen.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/features/today/today_screen.dart';
import 'package:aironludi/main.dart' as app;
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'device_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Erster Start, Einrichtung, alle Reiter, Datensicherung, Demo mit Benutzerwechsel', (tester) async {
    step('Start');
    await app.main();
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await waitFor(tester, find.text('Weiter'), timeout: const Duration(seconds: 60));
    await shot(binding, tester, '00-einrichtung');

    step('Einrichtung bis „Los geht’s“');
    for (var page = 0; page < 20; page++) {
      if (find.text('Los geht’s').evaluate().isNotEmpty) {
        await shot(binding, tester, '00-einrichtung-fertig');
        await tester.tap(find.text('Los geht’s'));
        await idle(tester, const Duration(seconds: 2));
        break;
      }
      if (find.widgetWithText(TextField, 'Gewicht in kg').evaluate().isNotEmpty) {
        await tester.enterText(find.widgetWithText(TextField, 'Gewicht in kg'), '75');
        await tester.enterText(find.widgetWithText(TextField, 'Größe in cm'), '180');
        await tester.enterText(find.widgetWithText(TextField, 'Alter'), '35');
        FocusManager.instance.primaryFocus?.unfocus();
        await idle(tester);
        await tester.tap(await reveal(tester, find.text('Männlich')));
        await idle(tester);
      }
      if (find.text('Wochenplan vorschlagen').evaluate().isNotEmpty) {
        for (final day in ['Mo', 'Mi', 'Sa']) {
          final chip = find.ancestor(of: find.text(day).first, matching: find.byType(InkWell)).first;
          await tester.ensureVisible(chip);
          await idle(tester, const Duration(milliseconds: 300));
          await tester.tap(chip);
          await tester.pump();
        }
      }
      final next = find.widgetWithText(FilledButton, 'Weiter');
      final enabled = tester.widget<FilledButton>(next).onPressed != null;
      final texts = [for (final e in find.byType(Text).evaluate().take(4)) (e.widget as Text).data];
      step('Seite ${page + 1}: $texts');
      expect(enabled, isTrue, reason: 'Weiter gesperrt auf Seite ${page + 1}: $texts');
      await tester.tap(next);
      await idle(tester);
    }
    await waitFor(tester, find.byType(TodayScreen));
    await shot(binding, tester, '01-heute');
    // Am ersten Tag ist nichts „verpasst“ (der Wochenplan gilt erst ab heute).
    await idle(tester, const Duration(seconds: 2));
    expect(find.text('VERPASST'), findsNothing);

    step('Alle Reiter');
    for (final (index, label) in ['Plan', 'Verlauf', 'Ernährung', 'Ich'].indexed) {
      await tab(tester, label);
      await idle(tester, const Duration(seconds: 1));
      await shot(binding, tester, '0${index + 2}-${label.toLowerCase()}');
    }

    step('Datensicherung mit echter Datei');
    await tapText(tester, 'Allgemein');
    await tapText(tester, 'Datensicherung');
    await tapText(tester, 'Sicherung erstellen');
    await waitFor(tester, find.text('Sicherung teilen oder in „Dateien“ sichern'));
    await shot(binding, tester, '10-sicherung');
    await back(tester);
    await back(tester);

    step('Demo: neuer Benutzer, echter Wechsel mit eigener Datenbank');
    await tapText(tester, 'Technik');
    await tapText(tester, 'Demo ansehen');
    await tester.tap(find.text('Demo öffnen'));
    await waitFor(tester, find.byType(TodayScreen), timeout: const Duration(seconds: 60));
    await idle(tester, const Duration(seconds: 3));
    await shot(binding, tester, '20-demo-heute');
    await tab(tester, 'Ernährung');
    await waitFor(tester, find.textContaining('Haferflocken'), timeout: const Duration(seconds: 20));
    await shot(binding, tester, '21-demo-ernaehrung');
    await tab(tester, 'Verlauf');
    await waitFor(tester, find.textContaining('Langer Lauf'), timeout: const Duration(seconds: 20));
    await shot(binding, tester, '22-demo-verlauf');

    step('Native Brücken antworten (keine fehlende Gegenseite)');
    Future<Object?> call(String channel, String method) => MethodChannel(channel).invokeMethod<Object?>(method);
    expect(await call('aironludi/alarm', 'state'), isA<String>());
    expect(await call('aironludi/activities', 'takePendingActions'), anyOf(isNull, isA<List<Object?>>()));
    await call('aironludi/widgets', 'reload');

    step('Gym: Live-Einheit mit erledigtem Satz (Live-Aktivität bzw. Benachrichtigung)');
    await tab(tester, 'Plan');
    await tapText(tester, 'Einheit starten');
    await tapText(tester, 'Freies Training');
    final container = ProviderScope.containerOf(tester.element(find.byType(ActiveWorkoutScreen)));
    final gym = container.read(gymControllerProvider);
    gym.addExercise(ExerciseLibrary.byID['bankdruecken']!);
    await idle(tester);
    await tester.tap(await waitFor(tester, find.text('Satz erledigt')));
    await idle(tester, const Duration(seconds: 2));
    expect(gym.active?.doneSetCount, 1);
    await shot(binding, tester, '30-gym-live');
    gym.cancelActive();
    await idle(tester, const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

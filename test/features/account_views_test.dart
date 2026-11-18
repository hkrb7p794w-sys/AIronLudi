// Konto: Abschnitt in den Einstellungen, Anmeldefenster mit Prüfungen, Wiederherstellungscode, Einladungslink.
import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/features/account/account_views.dart';
import 'package:aironludi/features/settings/settings_screen.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  test('Datum des Workers kurz', () {
    expect(AccountDetailScreen.shortDate('2026-11-28T09:30:00.000Z'), '28. Nov. 2026');
    expect(AccountDetailScreen.shortDate('kaputt'), 'kaputt');
  });

  testWidgets('Einstellungen: Konto erstellen mit Prüfungen', (tester) async {
    await _start(tester);
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('KONTO'), findsOneWidget);
    await tester.tap(find.text('Konto erstellen'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountAuthScreen), findsOneWidget);
    // Ohne gespeicherten Server: Feld für den Server.
    expect(find.text('SERVER'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Benutzername'), 'ab');
    await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'kurz');
    await tester.pump();
    expect(find.textContaining('Passwort'), findsWidgets);
    final submit = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Konto erstellen').last);
    expect(submit.enabled, isFalse);
    await tester.tap(find.text('Anmelden').first);
    await tester.pumpAndSettle();
    expect(find.text('Anzeigename (z. B. Vorname)'), findsNothing);
  });

  testWidgets('Wiederherstellungscode erst nach Bestätigung schließen', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: RecoveryCodeScreen(code: 'ABCD-EFGH-IJKL-MNOP', onDone: () => done = true),
      ),
    );
    await tester.tap(find.text('Fertig'));
    expect(done, isFalse);
    await tester.tap(find.text('Ich habe den Code sicher aufbewahrt'));
    await tester.pump();
    await tester.tap(find.text('Fertig'));
    expect(done, isTrue);
  });

  testWidgets('Einladungslink öffnet die Registrierung mit Code', (tester) async {
    final container = await _start(tester);
    container
        .read(incomingLinkProvider.notifier)
        .open(Uri.parse('coach://account?worker=https%3A%2F%2Fcoach.example.workers.dev&invite=ABCDE12345'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountAuthScreen), findsOneWidget);
    expect(find.textContaining('Du wurdest eingeladen'), findsOneWidget);
    expect(find.text('ABCDE12345'), findsOneWidget);
    expect(container.read(incomingLinkProvider), isNull);
  });
}

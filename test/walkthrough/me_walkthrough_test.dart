// Durchlauf Ich: alle Einstellungsbereiche bis zum Ende, Datenquellen, Sicherung, Benutzer, Konto, Freunde und KI
// ohne Worker.
import 'package:aironludi/features/settings/users_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

void main() {
  walk('Ich: Bereiche, Datenquellen, Sicherung, Benutzer, Konto, Freunde, KI', (tester, device) async {
    await startDemo(tester, device: device);
    await tab(tester, 'Ich');

    for (final section in [
      'Allgemein',
      'Training und Fitness',
      'Ernährung',
      'Sperrbildschirm',
      'Health und Erholung',
      'KI und Automatisierung',
      'Technik',
      'Freunde & Liga',
      'KI',
    ]) {
      step('Ich › $section');
      await tapText(tester, section);
      await scrollToEnd(tester);
      await back(tester);
    }

    // Benutzer anlegen, wechseln, umbenennen und löschen prüft test/app/user_session_test.dart (braucht eine echte
    // Sitzung mit Dateien); hier nur die Seite.
    step('Allgemein › Datensicherung, Health › Datenquellen');
    await tapText(tester, 'Allgemein');
    await tapText(tester, 'Datensicherung');
    await tapText(tester, 'Sicherung erstellen');
    // Sicherung liest die Datenbank und schreibt eine Datei: echte Zeit und Frames im Wechsel.
    for (var i = 0; i < 10 && find.text('Sicherung erstellen').evaluate().isNotEmpty; i++) {
      await settle(tester);
    }
    // Datei liegt bereit; das Teilen selbst öffnet das System-Blatt (auf dem Gerät).
    await reveal(tester, find.text('Sicherung teilen oder in „Dateien“ sichern'));
    await scrollToEnd(tester);
    await back(tester);
    await back(tester);
    await tapText(tester, 'Health und Erholung');
    await tapText(tester, 'Datenquellen und Vorrang');
    await scrollToEnd(tester);
    await back(tester);
    await back(tester);

    step('Benutzer');
    await tapText(tester, 'Benutzer dieses Geräts: wechseln, hinzufügen', contains: true);
    expect(find.byType(UsersScreen), findsOneWidget);
    await back(tester);

    step('Konto erstellen (ohne Worker)');
    await tapText(tester, 'Konto erstellen');
    await scrollToEnd(tester);
    await back(tester);
  });
}

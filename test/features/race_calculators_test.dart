// Wünsche vom 25.11.2026: Zeitrechner mit Reglern (Almere, Marathon), Auswahl im Menüstil, gleich große Kacheln.
import 'package:aironludi/features/training/race_calculators.dart';
import 'package:aironludi/ui/components.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ListView(children: [child])),
    ),
  );
}

void main() {
  testWidgets('Zeitrechner 70.3: Regler rechnet mit, Zurücksetzen stellt die Schätzung wieder her', (tester) async {
    final start = TriathlonTimes.season(SeasonConfig.standard);
    await _pump(tester, TriathlonCalculatorSection(start: start));
    final total = '${RaceEstimate.hoursMinutes(start.totalMinutes)} h';
    expect(find.text(total), findsOneWidget);
    expect(find.text('wie die Schätzung'), findsOneWidget);
    expect(find.text('Zurücksetzen'), findsNothing);
    expect(find.byType(Slider), findsNWidgets(4));

    // Rad nach rechts = schneller: Endzeit sinkt.
    await tester.drag(find.byType(Slider).at(1), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(find.text(total), findsNothing);
    expect(find.textContaining('min gegenüber der Schätzung'), findsOneWidget);
    expect(find.textContaining('−'), findsWidgets);

    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();
    expect(find.text(total), findsOneWidget);
    expect(find.text('Zurücksetzen'), findsNothing);
  });

  testWidgets('Zeitrechner Marathon: Pace, Zwischenzeiten und Spanne aus dem Halbmarathon', (tester) async {
    await _pump(tester, const MarathonCalculatorSection(pace: 300, half: 6300));
    expect(find.text('${TimeText.hms(MarathonTimes.seconds(300))} h'), findsOneWidget);
    expect(find.text('Halbmarathon'), findsWidgets);
    expect(find.text('3:45–3:51 h (5:21–5:28 /km)'), findsOneWidget);

    // Pace nach rechts = schneller.
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(find.text('${TimeText.hms(MarathonTimes.seconds(300))} h'), findsNothing);
    await tester.tap(find.text('Zurücksetzen').first);
    await tester.pumpAndSettle();
    expect(find.text('${TimeText.hms(MarathonTimes.seconds(300))} h'), findsOneWidget);
  });

  testWidgets('Auswahl im Menüstil: Wert rechts, Erklärung darunter, Menü wählt', (tester) async {
    var chosen = 'Vollständig';
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => MenuPickerTile<String>(
          title: 'KI nutzen',
          value: chosen,
          values: const ['Aus', 'Nur auf Wunsch', 'Vollständig'],
          label: (value) => value,
          detail: 'Notizen und Hinweise kommen automatisch.',
          onChanged: (value) => setState(() => chosen = value),
        ),
      ),
    );
    expect(find.text('KI nutzen'), findsOneWidget);
    expect(find.text('Notizen und Hinweise kommen automatisch.'), findsOneWidget);
    await tester.tap(find.text('KI nutzen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus').last);
    await tester.pumpAndSettle();
    expect(chosen, 'Aus');
  });

  testWidgets('Plan: Kacheln sind gleich groß', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Plan')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    Size tile(String text) => tester.getSize(find.ancestor(of: find.text(text), matching: find.byType(Card)).first);
    final endurance = tile('Ausdauerplan');
    expect(tile('Laufen & Rad'), endurance);
    expect(tile('Rund ums Training'), endurance);
    expect(find.text('Laufen & Rad auf OpenStreetMap'), findsNothing);
  });
}

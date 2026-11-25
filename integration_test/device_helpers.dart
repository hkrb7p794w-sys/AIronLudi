// Hilfen für Gerätetests (iOS-Simulator, Android-Emulator): echte Zeit, echte Plattform. Statt auf „Ruhe“ zu warten
// (ein Ladekreis dreht sich endlos), wird gewartet, bis ein bestimmtes Element erscheint.
import 'package:aironludi/ui/liquid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Fortschritt im Protokoll des Laufs.
void step(String text) => debugPrint('▶ $text');

/// Frames für [duration] (echte Zeit).
Future<void> idle(WidgetTester tester, [Duration duration = const Duration(milliseconds: 600)]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Warten, bis [finder] etwas findet; sonst Fehler mit den sichtbaren Texten.
Future<Finder> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return finder;
  }
  final texts = [for (final element in find.byType(Text).evaluate().take(25)) (element.widget as Text).data];
  fail('Nicht erschienen: $finder\nSichtbar: $texts');
}

/// Angezeigter Text (kein Eingabefeld, nicht die Tab-Leiste).
Finder shownText(String text, {bool contains = false}) => find.byElementPredicate(
  (element) =>
      element.widget is Text &&
      (contains ? ((element.widget as Text).data ?? '').contains(text) : (element.widget as Text).data == text) &&
      element.findAncestorWidgetOfExactType<LiquidTabBar>() == null,
);

/// Element in die Sicht scrollen (nach unten, sonst nach oben).
Future<Finder> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final vertical = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    try {
      await tester.scrollUntilVisible(finder, 300, scrollable: vertical.last, maxScrolls: 40);
    } on Object {
      await tester.scrollUntilVisible(finder, -300, scrollable: vertical.last, maxScrolls: 80);
    }
  }
  await tester.ensureVisible(finder.last);
  await idle(tester, const Duration(milliseconds: 300));
  return finder.last;
}

/// Text suchen, in die Sicht holen und antippen.
Future<void> tapText(WidgetTester tester, String text, {bool contains = false}) async {
  await idle(tester);
  await tester.tap(await reveal(tester, shownText(text, contains: contains)));
  await idle(tester);
}

/// Reiter wechseln.
Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text(label)));
  await idle(tester);
}

/// Oberste Seite schließen.
Future<void> back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).last).pop();
  await idle(tester);
}

/// Bildschirmfoto (vom Treiber als PNG gesichert); auf Android muss die Fläche einmal umgestellt sein.
Future<void> shot(IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester, String name) async {
  await idle(tester, const Duration(milliseconds: 300));
  await binding.takeScreenshot(name);
}

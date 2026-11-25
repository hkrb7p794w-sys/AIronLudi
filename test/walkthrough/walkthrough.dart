// Durchläufe: Funktionen mit Demo-Daten bis zum Ende bedienen (wie eine Person, die die App ausprobiert). Jeder
// Durchlauf startet die echte App mit eigener Datenbank im Speicher, spielt die Demo-Daten ein und tippt sich durch.
import 'dart:io';

import 'package:aironludi/services/demo/demo_seed.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;
import '../screenshots/screenshots_test.dart' show loadFonts;

var _fontsLoaded = false;

/// Gerät eines Durchlaufs: iPhone 15 mit normaler Schrift oder kleines Android mit großer Schrift (1,3).
enum WalkDevice {
  iphone(Size(1179, 2556), 3, 1),
  smallLargeText(Size(720, 1280), 2, 1.3);

  const WalkDevice(this.physicalSize, this.ratio, this.textScale);

  final Size physicalSize;
  final double ratio;
  final double textScale;
}

/// Durchlauf auf beiden Geräten registrieren.
void walk(String description, Future<void> Function(WidgetTester tester, WalkDevice device) body) {
  for (final device in WalkDevice.values) {
    testWidgets('$description (${device.name})', timeout: const Timeout(Duration(minutes: 4)), (tester) async {
      await body(tester, device);
      expect(endless, isEmpty, reason: 'Dauer-Animation: $endless');
    });
  }
}

/// App mit Demo-Daten starten.
Future<ProviderContainer> startDemo(
  WidgetTester tester, {
  List<Override> overrides = const [],
  WalkDevice device = WalkDevice.iphone,
}) async {
  endless.clear();
  // Echte Schrift (Inter) statt der breiten Testschrift, sonst sind Überläufe keine echten Befunde.
  if (!_fontsLoaded) {
    await tester.runAsync(loadFonts);
    // Wie `bootstrap.dart`: Bundeslebensmittelschlüssel laden.
    if (BLS.foods.isEmpty) BLS.load(File('packages/coach_core/assets/bls.tsv').readAsStringSync());
    _fontsLoaded = true;
  }
  tester.view.physicalSize = device.physicalSize;
  tester.view.devicePixelRatio = device.ratio;
  tester.platformDispatcher.textScaleFactorTestValue = device.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // Erst die Daten, dann die Oberfläche: Laufende Abfragen der Screens hielten sonst die Datenbank in der Testzeit fest.
  final widget = (await tester.runAsync(() async {
    final widget = await app(onboarded: true, overrides: overrides) as UncontrolledProviderScope;
    await seedDemo(widget.container);
    return widget;
  }))!;
  await tester.pumpWidget(widget);
  await settle(tester);
  return widget.container;
}

/// Datenbank und Zeitgeber arbeiten lassen, dann alle Frames.
Future<void> settle(WidgetTester tester, {int milliseconds = 300}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: milliseconds)));
  await tester.pump(const Duration(seconds: 1));
  await settleFrames(tester);
  expect(tester.takeException(), isNull);
}

/// Frames bis Ruhe, höchstens 5 s (Testzeit). Läuft danach noch eine Animation (Ladekreis, Puls), wird das als
/// Befund gemeldet: Auf dem Gerät hieße das Dauer-Animation, also Akku und Unruhe.
Future<void> settleFrames(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  } on FlutterError catch (error) {
    if (!error.message.contains('pumpAndSettle timed out')) rethrow;
    endless.add(describeEndless(tester));
  }
}

/// Gefundene Dauer-Animationen (Bildschirm und tickende Widgets).
final endless = <String>{};

String describeEndless(WidgetTester tester) {
  final route = find.byType(Scaffold).evaluate().map((element) => element.widget.runtimeType).join(',');
  final spinners = find.byType(CircularProgressIndicator).evaluate().length;
  return 'Seiten: $route; Ladekreise: $spinners';
}

/// Reiter wechseln.
Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text(label)));
  await settle(tester);
}

/// Text in die Sicht scrollen (im obersten Scrollbereich) und antippen.
Future<void> tapText(WidgetTester tester, String text, {bool contains = false}) async {
  // Nur angezeigte Texte, keine Eingabefelder (sonst träfe „Kniebeuge“ nach dem Suchen das Suchfeld).
  final shown = find.byWidgetPredicate(
    (widget) => widget is Text && (contains ? (widget.data ?? '').contains(text) : widget.data == text),
  );
  final target = await reveal(tester, shown);
  await tester.tap(target, warnIfMissed: false);
  await settle(tester);
}

/// Element in die Sicht holen; sucht im zuletzt geöffneten Scrollbereich.
Future<Finder> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    // Senkrechter Scrollbereich der obersten Seite; erst nach unten, sonst nach oben suchen.
    final vertical = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    try {
      await tester.scrollUntilVisible(finder, 300, scrollable: vertical.last, maxScrolls: 40);
    } on Object {
      await tester.scrollUntilVisible(finder, -300, scrollable: vertical.last, maxScrolls: 80);
    }
  }
  final target = finder.last;
  await tester.ensureVisible(target);
  await settleFrames(tester);
  return target;
}

/// Oberste Seite schließen (Zurück).
Future<void> back(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
  navigator.pop();
  await settle(tester);
}

/// Fortschritt im Testprotokoll (hilft, wenn ein Durchlauf hängt).
void step(String text) => debugPrint('▶ $text');

/// Alle Navigationsstapel auf ihre erste Seite zurücksetzen (Reiter-Übersichten).
Future<void> home(WidgetTester tester) async {
  final navigators = find.byType(Navigator, skipOffstage: false).evaluate().toList().reversed;
  for (final element in navigators) {
    if (element case StatefulElement(:final NavigatorState state) when element.mounted) {
      state.popUntil((route) => route.isFirst);
    }
  }
  await settle(tester);
}

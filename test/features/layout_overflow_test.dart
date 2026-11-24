// Kleines Android-Gerät (360 × 640 dp) mit großer Schrift (1,3): Ernährung und Einrichtung laufen nicht über
// (Roast B-28, gefunden mit dem Screenshot-Prüfstand).
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void _smallDeviceLargeText(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1280);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
}

void main() {
  testWidgets('Ernährung: Makro-Zeilen passen auf 360 dp bei großer Schrift', (tester) async {
    _smallDeviceLargeText(tester);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    container.read(coachSettingsProvider).nutrition = NutritionSettings()
      ..weightKilograms = 74
      ..heightCentimeters = 180
      ..age = 34
      ..isFemale = false;
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Ernährung')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Kohlenhydrate'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Einrichtung: „Sicherung einspielen“ läuft bei großer Schrift nicht über', (tester) async {
    _smallDeviceLargeText(tester);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: false)) as Widget);
    await tester.pumpAndSettle();
    expect(find.text('Sicherung einspielen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

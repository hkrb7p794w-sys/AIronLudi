// Barrierefreiheit der vier Reiter (Roast, Stufe 2 / PR 12): Tap-Flächen ≥ 44 pt (iOS-Richtlinie), jede Tap-Fläche
// mit Beschriftung, Textkontrast ≥ 4,5 : 1 (bzw. 3 : 1 für große Schrift). Androids 48-dp-Richtlinie gilt bewusst
// nicht: Die App nutzt auf beiden Plattformen iOS-Zeilenhöhen von 44 pt (docs/decisions.md, „Clean Liquid Design“).
import 'package:aironludi/ui/liquid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  for (final tab in ['Heute', 'Plan', 'Verlauf', 'Ernährung', 'Ich']) {
    testWidgets('$tab: Tap-Flächen, Beschriftungen, Kontrast', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text(tab)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}

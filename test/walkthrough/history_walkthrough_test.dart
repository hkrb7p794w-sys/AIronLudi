// Durchlauf Verlauf: Aktivität öffnen, Filter, Freunde ohne Konto; alle Auswertungen öffnen und bis zum Ende scrollen.
import 'package:aironludi/features/activities/activity_detail_screen.dart';
import 'package:aironludi/features/training/training_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

/// Bis zum Ende der obersten Seite scrollen (baut jede Karte einmal).
Future<void> scrollToEnd(WidgetTester tester) async {
  final vertical = find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  if (vertical.evaluate().isEmpty) return;
  for (var i = 0; i < 12; i++) {
    await tester.drag(vertical.last, const Offset(0, -600), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await settle(tester);
}

void main() {
  walk('Verlauf: Aktivität, Filter, Freunde; alle Auswertungen bis zum Ende', (tester, device) async {
    await startDemo(tester, device: device);
    await tab(tester, 'Verlauf');

    step('Aktivität öffnen');
    await tapText(tester, 'Langer Lauf');
    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    await scrollToEnd(tester);
    await back(tester);

    step('Meine mit Filter');
    await tester.tap(find.text('Meine'));
    await settle(tester);
    await tester.tap(find.text('4 Wochen'));
    await settle(tester);
    expect(find.textContaining('KW '), findsWidgets);
    await tester.tap(find.text('Freunde'));
    await settle(tester);
    expect(find.text('Mit Freunden wird daraus ein Feed'), findsOneWidget);

    step('Auswertungen');
    await tester.tap(find.byTooltip('Auswertungen'));
    await settle(tester);
    expect(find.byType(TrainingScreen), findsOneWidget);
    for (final page in [
      'Gesundheit',
      'Erholung',
      'Herzfrequenz',
      'Trends',
      'Schlaf-Coach',
      'Fitness & Form',
      'Wochenbericht',
    ]) {
      step('Auswertung $page');
      await tapText(tester, page);
      await scrollToEnd(tester);
      await back(tester);
    }
  });
}

import 'package:aironludi/ui/body_map.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jeder Muskel ist auf mindestens einer Seite gezeichnet', () {
    final shown = {...bodySideMuscles(BodySide.front), ...bodySideMuscles(BodySide.back)};
    expect(shown, containsAll(Muscle.values));
  });

  test('Zugübungen zeigen zuerst den Rücken, Druckübungen die Vorderseite', () {
    expect(BodyMap.preferredSide({Muscle.lats: 1, Muscle.biceps: 0.5, Muscle.rearDelts: 0.5}, 1), BodySide.back);
    expect(BodyMap.preferredSide({Muscle.chest: 1, Muscle.triceps: 0.5, Muscle.frontDelts: 0.5}, 1), BodySide.front);
    expect(BodyMap.preferredSide({}, 1), BodySide.front);
  });

  test('Heatmap-Farbe: ohne Last keine, mit voller Last kräftiges Rot', () {
    expect(BodyMap.heat(0, full: 6), isNull);
    final full = BodyMap.heat(6, full: 6)!;
    expect(full.a, closeTo(1, 0.01));
    expect(full.r, greaterThan(full.g));
  });

  testWidgets('blättert zwischen Vorder- und Rückseite', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BodyMap(values: const {Muscle.chest: 3}, full: 6)),
      ),
    );
    expect(find.byTooltip('Rückseite zeigen'), findsOneWidget);
    await tester.tap(find.byTooltip('Rückseite zeigen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Vorderseite zeigen'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Muskelkarte, Rückseite: Brust 3 Sätze')), findsOneWidget);
  });
}

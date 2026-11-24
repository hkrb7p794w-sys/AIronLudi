// Route je Einheit auch im Wochenplan (Roast B-04): Lauf und Rad bieten „Route dazu planen“, Kraft nicht.
import 'package:aironludi/features/plan/plan_screen.dart';
import 'package:aironludi/features/routes/route_for_slot.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  const day = CalendarDay(2026, 11, 26);

  Future<void> open(WidgetTester tester, SessionSlot slot) async {
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    // Nicht abgewartet: Die Seite bleibt bis zum Testende offen.
    // ignore: unawaited_futures
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SessionGuideScreen(slot: slot, day: day, minutes: 60),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Lauf im Wochenplan: Route dazu planen', (tester) async {
    await open(tester, const SessionSlot(TrainingSport.run, SessionIntensity.long));
    expect(find.byType(SessionGuideScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Route dazu planen'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.byType(RouteForSessionSection), findsOneWidget);
    expect(
      RouteForSessionSection.unitID(const SessionSlot(TrainingSport.run, SessionIntensity.long), day),
      'woche:2026-11-26:run:long',
    );
  });

  testWidgets('Kraft im Wochenplan: keine Route', (tester) async {
    await open(tester, const SessionSlot(TrainingSport.strength));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Route dazu planen'), findsNothing);
  });
}

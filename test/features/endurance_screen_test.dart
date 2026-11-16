// Ausdauerplan im Reiter Training: Einstieg, Erstellen, Woche, Einheit mit Export.
import 'package:aironludi/app/user_providers.dart';
import 'package:aironludi/features/endurance/endurance_controller.dart';
import 'package:aironludi/features/endurance/endurance_screens.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  test('Uhrzeiten lesen', () {
    expect(parseClock('4:30'), 270);
    expect(parseClock(' 1:50 '), 110);
    expect(parseClock('4:75'), isNull);
    expect(parseClock('abc'), isNull);
    expect(clockText(270), '4:30');
  });

  testWidgets('Einstieg im Reiter Training, Plan anlegen und Einheit öffnen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
    await tester.tap(find.descendant(of: find.byType(CupertinoTabBar), matching: find.text('Training')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Ausdauerplan'), findsOneWidget);
    await tester.tap(find.text('Ausdauerplan'));
    await tester.pumpAndSettle();
    expect(find.byType(EnduranceScreen), findsOneWidget);
    expect(find.text('Plan erstellen'), findsOneWidget);

    // Erstellen-Bildschirm öffnet sich und prüft die Eingaben.
    await tester.tap(find.text('Plan erstellen'));
    await tester.pumpAndSettle();
    expect(find.byType(EndurancePlanSetupScreen), findsOneWidget);
    expect(find.text('Wettkampf'), findsOneWidget);
    await tester.tap(find.text('Für einen Zeitraum'));
    await tester.pumpAndSettle();
    expect(find.text('Schwerpunkt'), findsOneWidget);
    Navigator.of(tester.element(find.byType(EndurancePlanSetupScreen))).pop();
    await tester.pumpAndSettle();

    final user = container.read(currentUserProvider);
    final today = CalendarDay.today();
    await tester.runAsync(
      () => container
          .read(enduranceControllerProvider)
          .create(
            TrainingPlanRequest(
              username: user.username,
              mode: PlanningMode.period,
              sports: const [EnduranceSport.bike],
              start: today,
              weeklyMinutes: 300,
              days: Weekday.values,
              longDay: Weekday.values[today.weekdayIndex],
              weeks: 4,
              thresholds: const AthleteThresholds(ftpWatts: 200),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Woche 1 von 4'), findsOneWidget);
    expect(find.text('HEUTE'), findsOneWidget);
    final slot = container.read(enduranceControllerProvider).plan!.slotsOn(today).single;
    await tester.tap(find.text(slot.current.title).first);
    await tester.pumpAndSettle();
    expect(find.byType(EnduranceWorkoutScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Einheit an Uhr senden'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('FIT-Datei teilen'), findsOneWidget);
    expect(find.text('Für Zwift exportieren (.zwo)'), findsOneWidget);
    await tester.tap(find.text('Einheit an Uhr senden'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anmeldung mit dem Garmin-Konto'), findsWidgets);
  });
}

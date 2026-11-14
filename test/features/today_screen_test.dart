// Reiter „Heute“: Jetzt dran, Regel-Notiz, Wochenübersicht mit eigenen Zielen, Auslassen für diese Woche.
import 'package:aironludi/features/today/today_screen.dart';
import 'package:aironludi/features/today/week_overview.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  testWidgets('persönliches Profil: Jetzt dran, Notiz ohne KI, Woche, auslassen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    final settings = container.read(coachSettingsProvider);
    final profile = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run],
      targets: const ImprovementTargets(restingHeartRate: 48),
    );
    final weekday = Weekday.of(CalendarDay.today());
    profile.schedule = profile.schedule.withSlots(const [SessionSlot(TrainingSport.run)], weekday);
    settings.profile = profile;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.textContaining('JETZT DRAN'), findsOneWidget);
    expect(find.text('WARUM?'), findsOneWidget);
    expect(find.text('Regeln (ohne KI)'), findsOneWidget);
    expect(find.textContaining('Melde dich in den Einstellungen'), findsOneWidget);

    await tester.tap(find.text('Diese Woche auslassen'));
    await tester.pumpAndSettle();
    expect(settings.planAdjustments.note(weekday, inWeekOf: CalendarDay.today()), isNotNull);
    expect(find.text('Rückgängig'), findsWidgets);

    final week = find.text('Diese Woche, Ziele und Verlauf');
    await tester.scrollUntilVisible(week, 300);
    await tester.tap(week);
    await tester.pumpAndSettle();
    expect(find.byType(WeekOverviewScreen), findsOneWidget);
    expect(find.text('DEINE ZIELE'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsOneWidget);
  });
}

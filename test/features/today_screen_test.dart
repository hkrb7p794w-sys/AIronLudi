// Reiter „Heute“: Jetzt dran, Regel-Notiz, Wochenübersicht mit eigenen Zielen, Auslassen für diese Woche.
import 'package:aironludi/features/ai/ai_screen.dart';
import 'package:aironludi/features/today/today_dashboard_editor.dart';
import 'package:aironludi/features/today/today_screen.dart';
import 'package:aironludi/features/today/week_overview.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  testWidgets('persönliches Profil: Jetzt dran, Notiz ohne KI, Woche, auslassen', (tester) async {
    // Höher als ein iPhone: vor 12 Uhr steht der Morning Report über „Jetzt dran“.
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
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
    // Oben drei Ringe: Schlaf, Erholung, Strain (0–21); die Detailkarte zur Belastung ist standardmäßig aus.
    expect(find.text('Schlaf'), findsOneWidget);
    expect(find.text('Erholung'), findsOneWidget);
    expect(find.text('Strain'), findsOneWidget);
    expect(find.text('MEINE BELASTUNG HEUTE'), findsNothing);
    expect(find.textContaining('Verbinde in den Einstellungen eine Datenquelle'), findsOneWidget);
    // „Warum?“ steht in den AI-Empfehlungen; auf „Heute“ nur der erste Punkt als Vorschau.
    expect(find.text('WARUM?'), findsNothing);
    await tester.tap(find.text('AI-Empfehlungen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(AIScreen), findsOneWidget);
    expect(find.text('WARUM?'), findsOneWidget);
    expect(find.text('Regeln (ohne KI)'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AIScreen))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Diese Woche auslassen'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Diese Woche auslassen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Diese Woche auslassen'));
    await tester.pumpAndSettle();
    expect(settings.planAdjustments.note(weekday, inWeekOf: CalendarDay.today()), isNotNull);
    expect(find.text('Rückgängig'), findsWidgets);

    final week = find.text('Diese Woche, Ziele und Verlauf');
    await tester.scrollUntilVisible(week, 300);
    await tester.ensureVisible(week);
    await tester.pumpAndSettle();
    await tester.tap(week);
    await tester.pumpAndSettle();
    expect(find.byType(WeekOverviewScreen), findsOneWidget);
    expect(find.text('DEINE ZIELE'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsOneWidget);
  });

  testWidgets('Heute anpassen: AI-Empfehlungen ganz ausblenden, Motivation zuschalten', (tester) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
    final settings = container.read(coachSettingsProvider);
    await tester.scrollUntilVisible(find.text('AI-Empfehlungen'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('AI-Empfehlungen'), findsOneWidget);

    await tester.tap(find.byTooltip('Heute anpassen'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayDashboardEditor), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'AI-Empfehlungen'));
    await tester.pumpAndSettle();
    expect(settings.todayDashboard.shows(TodayModule.ai), isFalse);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Motivation und Begleiter'));
    await tester.pumpAndSettle();
    expect(settings.todayDashboard.shows(TodayModule.motivation), isTrue);
    Navigator.of(tester.element(find.byType(TodayDashboardEditor))).pop();
    await tester.pumpAndSettle();
    expect(find.text('AI-Empfehlungen'), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
  });
}

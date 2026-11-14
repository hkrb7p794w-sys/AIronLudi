// Plan: Saisonplan Woche für Woche mit Einheit im Detail, eigene Woche mit Nachtragen und verpasster Einheit.
import 'dart:io';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/plan/my_week_screen.dart';
import 'package:aironludi/features/plan/plan_screen.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

final _schedule = SeasonSchedule.load(File('packages/coach_core/assets/season-plan.json').readAsStringSync())!;

Future<ProviderContainer> _openPlan(WidgetTester tester, UserProfile profile) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    await tester.runAsync(() => app(onboarded: true, overrides: [seasonScheduleProvider.overrideWithValue(_schedule)]))
        as Widget,
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
  container.read(coachSettingsProvider).profile = profile;
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plan'));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Saisonplan: Woche, Einheit, Saisonübersicht', (tester) async {
    await _openPlan(tester, UserProfile.seasonPlan);
    expect(find.byType(PlanScreen), findsOneWidget);
    expect(find.text('EINHEITEN'), findsOneWidget);
    expect(find.textContaining('KW '), findsOneWidget);

    // Woche weiter und zurück zu heute.
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
    if (tester.widget<IconButton>(next).onPressed != null) {
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Heute'), findsWidgets);
    }

    final firstUnit = find.descendant(of: find.byType(PlanScreen), matching: find.byType(ListTile)).first;
    await tester.tap(firstUnit);
    await tester.pumpAndSettle();
    expect(find.byType(PlanUnitDetailScreen), findsOneWidget);
    expect(find.text('WORUM ES GEHT'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(PlanUnitDetailScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Saison'));
    await tester.pumpAndSettle();
    expect(find.byType(SeasonOverviewSheet), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(find.byType(SeasonOverviewSheet), findsNothing);
  });

  testWidgets('Meine Woche: Tage, Erklärung, Training nachtragen', (tester) async {
    const easyRun = SessionSlot(TrainingSport.run);
    final container = await _openPlan(
      tester,
      UserProfile(
        mode: ProfileMode.personal,
        onboardingDone: true,
        schedule: WeekSchedule([
          for (var day = 0; day < 7; day++) day.isEven ? const [easyRun] : const <SessionSlot>[],
        ]),
      ),
    );
    expect(find.byType(MyWeekScreen), findsOneWidget);
    expect(find.text('Mo'), findsOneWidget);

    await tester.ensureVisible(find.text('Ausführlich').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ausführlich').first);
    await tester.pumpAndSettle();
    expect(find.byType(SessionGuideScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(SessionGuideScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Training nachtragen'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualActivityScreen), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Bezeichnung (optional)'), 'Fußball');
    await tester.tap(find.text('Sichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final stored = await tester.runAsync(() => container.read(activityRepositoryProvider).all());
    expect(stored!.single.name, 'Fußball');
    expect(ManualActivity.isManual(stored.single.id), isTrue);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fußball'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Fußball'), findsOneWidget);

    // Entschiedene verpasste Einheiten: Einträge älter als zwei Wochen fallen heraus.
    final settings = container.read(coachSettingsProvider);
    final today = CalendarDay.today();
    settings.handledMissed = ['${today.adding(-20).iso}-0-run-easy'];
    MissedSessionSection.handle(settings, ['${today.iso}-0-run-easy']);
    expect(settings.handledMissed, ['${today.iso}-0-run-easy']);
  });
}

// Spiel: Fortschritt auf Heute, Wettkampf mit Stand, Rangliste ohne Freunde, Abzeichen, neue Challenge.
import 'dart:async';

import 'package:aironludi/features/game/game_views.dart';
import 'package:aironludi/features/social/social_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/services/social/game_service.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart' hide Badge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
}

void main() {
  testWidgets('Heute: Fortschritt mit Serie und Stufe, merkt den Stand fürs Spiel', (tester) async {
    final container = await _start(tester);
    container.read(coachSettingsProvider).todayDashboard = TodayDashboard()..set(TodayModule.motivation, visible: true);
    await tester.pumpAndSettle();
    final section = find.text('FORTSCHRITT');
    await tester.scrollUntilVisible(section, 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Tage in Folge'), findsOneWidget);
    expect(find.textContaining('Stufe'), findsWidgets);
    await tester.pump();
    expect(container.read(gameServiceProvider).snapshot, isNotNull);
  });

  testWidgets('Wettkampf: Stand, Rangliste, Abzeichen, Challenge erst mit Freunden', (tester) async {
    final container = await _start(tester);
    final game = container.read(gameServiceProvider);
    final summary = container.read(appModelProvider).motivation({CalendarDay.today()});
    game.snapshot = GameSnapshot(
      streak: DailyStreak.compute(activeDays: {CalendarDay.today()}, today: CalendarDay.today()),
      summary: summary,
      stats: GameStats()..workouts = 6,
    );
    unawaited(
      Navigator.of(tester.element(find.byType(LiquidTabBar)))
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: GameScreen()))),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Tage in Folge'), findsOneWidget);
    expect(find.text('Füge Freunde hinzu, um euch in der Rangliste zu vergleichen.'), findsOneWidget);
    expect(find.text('Challenges gibt es mit Freunden – füge zuerst jemanden hinzu.'), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Neue Challenge')).enabled, isFalse);
    await tester.scrollUntilVisible(find.byType(BadgeGrid), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('ABZEICHEN ('), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Freunde ohne Konto auch auf der Seite Wettkampf: Hinweis', (tester) async {
    await _start(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(LiquidTabBar)))
          .push(MaterialPageRoute<void>(builder: (_) => const FriendsScreen(initialPage: FriendsPage.game))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Freunde brauchen ein Konto'), findsOneWidget);
  });
}

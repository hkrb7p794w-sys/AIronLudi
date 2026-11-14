// Reiter Training: Übersicht, Erholung mit Kacheln, Trends, Fitness & Form, Wochenbericht, Schlaf-Coach.
import 'dart:async';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/training/sleep_coach_screen.dart';
import 'package:aironludi/features/training/training_pages.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  testWidgets('Übersicht und Unterseiten', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    final today = CalendarDay.today();
    final metrics = container.read(metricsRepositoryProvider);
    for (var offset = 0; offset < 10; offset++) {
      unawaited(
        metrics.merge(
          DailyMetrics(today.adding(-offset))
            ..restingHeartRate = 50
            ..hrvWeeklyAverage = 60
            ..spo2Average = 95
            ..sleepSeconds = 7.5 * 3600,
        ),
      );
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Erholung'), findsOneWidget);
    expect(find.text('60 ms'), findsOneWidget);
    await tester.tap(find.text('Erholung'));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryScreen), findsOneWidget);
    expect(find.text('HRV · 7-Tage-Schnitt'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('95 %'), 300);
    expect(find.text('SpO2'), findsOneWidget);
    Navigator.of(tester.element(find.byType(RecoveryScreen))).pop();
    await tester.pumpAndSettle();

    for (final (title, type) in [
      ('Trends', TrendsScreen),
      ('Fitness & Form', FitnessFormScreen),
      ('Wochenbericht', WeeklyReportScreen),
      ('Herzfrequenz', HeartRateScreen),
    ]) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget, reason: title);
      Navigator.of(tester.element(find.byType(type))).pop();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Schlaf-Coach'));
    await tester.pumpAndSettle();
    expect(find.byType(SleepCoachScreen), findsOneWidget);
    final settings = container.read(coachSettingsProvider);
    await tester.scrollUntilVisible(find.text('Erinnerung 30 min vorher'), 300);
    await tester.tap(find.text('Erinnerung 30 min vorher'));
    await tester.pumpAndSettle();
    expect(settings.sleep.reminder, isTrue);
  });
}

// Gesundheitsbereich: Widgets mit eigenem Bereich, Verlauf, Anpassen, Morning Report.
import 'dart:async';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/health/health_screen.dart';
import 'package:aironludi/features/health/morning_report_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Gesundheit: Widgets, Verlauf, Anpassen, Morning Report', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    final today = CalendarDay.today();
    final metrics = container.read(metricsRepositoryProvider);
    for (var offset = 0; offset < 12; offset++) {
      unawaited(
        metrics.merge(
          DailyMetrics(today.adding(-offset))
            ..restingHeartRate = 50 + (offset % 3).toDouble()
            ..hrvWeeklyAverage = 60
            ..hrvLastNightAverage = 58 + (offset % 4).toDouble()
            ..sleepSeconds = 7.5 * 3600
            ..steps = 8000 + offset * 100,
        ),
      );
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesundheit'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.byType(HealthScreen), findsOneWidget);
    expect(find.byType(HealthWidgetCard), findsWidgets);
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(find.textContaining('Ohne Daten in den letzten 30 Tagen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ruhepuls'));
    await tester.pumpAndSettle();
    expect(find.byType(HealthMetricDetail), findsOneWidget);
    expect(find.text('12 von 30'), findsOneWidget);
    await tester.tap(find.text('90 Tage'));
    await tester.pumpAndSettle();
    expect(find.text('12 von 90'), findsOneWidget);
    Navigator.of(tester.element(find.byType(HealthMetricDetail))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anpassen'));
    await tester.pumpAndSettle();
    expect(find.byType(HealthDashboardEditor), findsOneWidget);
    final settings = container.read(coachSettingsProvider);
    await tester.tap(find.byTooltip('Ausblenden').first);
    await tester.pumpAndSettle();
    expect(settings.healthDashboard.entries.first.hidden, isTrue);
    await tester.scrollUntilVisible(
      find.text('Standard wiederherstellen'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Standard wiederherstellen'));
    await tester.pumpAndSettle();
    expect(settings.healthDashboard.entries.first.hidden, isFalse);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MorningReportHeader));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(MorningReportScreen), findsOneWidget);
    expect(find.text('WERTE DER NACHT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

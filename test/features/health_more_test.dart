// Gesundheit Teil 2: Body Battery, Mobility mit Selbsttest, Wecker-Hinweis im Morning Report.
import 'dart:async';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/health/body_battery_screen.dart';
import 'package:aironludi/features/health/mobility_screen.dart';
import 'package:aironludi/features/health/morning_report_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
}

Future<void> _push(WidgetTester tester, Widget screen) async {
  unawaited(
    Navigator.of(tester.element(find.byType(NavigationBar))).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Body Battery: Stand, Tagesverlauf, 30 Tage', (tester) async {
    final container = await _start(tester);
    final today = CalendarDay.today();
    for (var offset = 0; offset < 10; offset++) {
      unawaited(
        container
            .read(metricsRepositoryProvider)
            .merge(
              DailyMetrics(today.adding(-offset))
                ..bodyBatteryHigh = 90
                ..bodyBatteryLow = 20
                ..bodyBatteryAtWake = 70 + offset.toDouble()
                ..bodyBatteryLatest = 55
                ..bodyBatteryCharged = 60
                ..bodyBatteryDrained = 45
                ..bodyBatteryCurve = [
                  for (var minute = 0; minute < 600; minute += 15)
                    BodyBatterySample(minute: minute, value: 30 + minute ~/ 15),
                ],
            ),
      );
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _push(tester, const BodyBatteryScreen());
    expect(find.byType(BatteryGauge), findsOneWidget);
    expect(find.textContaining('Beim Aufwachen'), findsOneWidget);
    expect(find.text('LETZTE 30 TAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Body Battery ohne Garmin: Hinweis', (tester) async {
    await _start(tester);
    await _push(tester, const BodyBatteryScreen());
    expect(find.text('Keine Body Battery'), findsOneWidget);
  });

  testWidgets('Mobility: Einheit, erledigt, Beschwerde, Selbsttest', (tester) async {
    final container = await _start(tester);
    await _push(tester, const MobilityScreen());
    final settings = container.read(coachSettingsProvider);
    expect(find.textContaining('ABLAUF · ETWA'), findsOneWidget);
    await tester.tap(find.text('20 min'));
    await tester.pumpAndSettle();
    expect(settings.mobility.minutes, 20);
    await tester.scrollUntilVisible(
      find.text('Als erledigt eintragen'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Als erledigt eintragen'));
    await tester.pumpAndSettle();
    expect(settings.mobility.log.single.day, CalendarDay.today());
    expect(find.text('Heute erledigt'), findsOneWidget);

    final firstTest = MobilityTest.all.first;
    await tester.scrollUntilVisible(find.text(firstTest.name), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(firstTest.name));
    await tester.pumpAndSettle();
    expect(find.byType(MobilityTestScreen), findsOneWidget);
    for (var step = 0; step < 8; step++) {
      await tester.tap(find.byTooltip('Mehr'));
    }
    await tester.pump();
    expect(find.text('8 cm'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(settings.mobility.results.single.value, 8);
    expect(find.text(firstTest.rating(8).label), findsWidgets);

    final complaint = ComplaintArea.values.first;
    final toggle = find.widgetWithText(SwitchListTile, complaint.label);
    await tester.scrollUntilVisible(toggle, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(settings.mobility.complaints, [complaint]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Morning Report: Wecker ohne Systembrücke mit Ersatzhinweis', (tester) async {
    await _start(tester);
    await _push(tester, const MorningReportScreen());
    await tester.scrollUntilVisible(find.text('WECKER'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Stelle ihn in der Uhr-App'), findsOneWidget);
  });
}

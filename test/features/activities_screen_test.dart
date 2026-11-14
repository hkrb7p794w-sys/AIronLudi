// Aktivitäten: Reiter mit Alle/Meine/Freunde, Filter, Detailseite; „Nach dem Training“ auf Heute.
import 'dart:async';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/activities/activities_screen.dart';
import 'package:aironludi/features/activities/activity_detail_screen.dart';
import 'package:aironludi/features/activities/post_workout_section.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

GarminActivity _run(int id, DateTime start, {String name = 'Morgenlauf'}) {
  String two(int value) => value.toString().padLeft(2, '0');
  return GarminActivity(id)
    ..typeKey = 'running'
    ..name = name
    ..startLocal = '${start.year}-${two(start.month)}-${two(start.day)} ${two(start.hour)}:${two(start.minute)}:00'
    ..durationSeconds = 2700
    ..distanceMeters = 8200
    ..trainingLoad = 80;
}

Future<ProviderContainer> _start(WidgetTester tester, List<GarminActivity> activities) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
  unawaited(container.read(activityRepositoryProvider).upsertAll(activities));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  return container;
}

void main() {
  testWidgets('Reiter Aktivitäten: Meine mit Filter, Detailseite', (tester) async {
    final now = DateTime.now();
    await _start(tester, [
      _run(1, now.subtract(const Duration(days: 2))),
      _run(2, now.subtract(const Duration(days: 200)), name: 'Alter Lauf'),
    ]);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Aktivitäten')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(ActivitiesScreen), findsOneWidget);
    // „Alle“: eigene Trainings auch ohne Konto, dazu der Hinweis auf Freunde.
    expect(find.text('Morgenlauf'), findsOneWidget);
    expect(find.text('Mit Freunden wird daraus ein Feed'), findsOneWidget);

    await tester.tap(find.text('Meine'));
    await tester.pumpAndSettle();
    expect(find.text('Alter Lauf'), findsOneWidget);
    await tester.tap(find.text('4 Wochen'));
    await tester.pumpAndSettle();
    expect(find.text('Alter Lauf'), findsNothing);
    expect(find.text('Morgenlauf'), findsOneWidget);

    await tester.tap(find.text('Morgenlauf'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    expect(find.text('Garmin'), findsWidgets);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(ActivityDetailScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Freunde').last);
    await tester.pumpAndSettle();
    expect(find.text('Noch nichts von Freunden'), findsOneWidget);
  });

  testWidgets('Nach dem Training: Anstrengung, Auswertung, schließen', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour >= 1 ? now.hour - 1 : 0);
    final container = await _start(tester, const []);
    unawaited(
      Navigator.of(tester.element(find.byType(NavigationBar))).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ListView(
              children: [
                PostWorkoutSection(activities: [_run(7, start, name: 'Feierabendlauf')], sessions: null),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NACH DEM TRAINING'), findsOneWidget);
    expect(find.text('Wie anstrengend war es?'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Anstrengung 5 von 10'));
    await tester.tap(find.bySemanticsLabel('Anstrengung 5 von 10'));
    await tester.pumpAndSettle();
    final settings = container.read(coachSettingsProvider);
    expect(settings.efforts['7'], 5);
    expect(find.text('Anstrengung ändern (5/10)'), findsOneWidget);
    await tester.ensureVisible(find.text('Fertig'));
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(settings.closedReviews, contains('7'));
    expect(find.text('NACH DEM TRAINING'), findsNothing);
  });

  testWidgets('Detailseite mit gespeichertem Bericht: Auswertung, Verlauf, Runden, Kilometer', (tester) async {
    final container = await _start(tester, const []);
    final activity = _run(9, DateTime.now().subtract(const Duration(days: 1)));
    final fit = FitActivity();
    var distance = 0.0;
    for (var second = 0; second <= 2700; second += 5) {
      final speed = second < 1350 ? 3.1 : 3.0;
      distance += speed * 5;
      fit.records.add(
        FitRecord(timestamp: second.toDouble(), heartRate: 140 + second / 100, speed: speed, distance: distance),
      );
    }
    for (var lap = 0; lap < 8; lap++) {
      fit.laps.add(FitLap(timerSeconds: 330, distanceMeters: 1000, averageHeartRate: 145, maxHeartRate: 160));
    }
    container
        .read(garminSyncServiceProvider)
        .reportStore
        .store(ActivityReportBuilder.build(activity, fit), today: CalendarDay.today());
    unawaited(
      Navigator.of(tester.element(find.byType(NavigationBar)))
          .push(MaterialPageRoute<void>(builder: (_) => ActivityDetailScreen(activity: activity))),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('AUSWERTUNG'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('VERLAUF'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Herzfrequenz (bpm)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('RUNDEN'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('KILOMETER'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}

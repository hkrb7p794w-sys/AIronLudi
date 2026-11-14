// Disziplinseiten im Reiter Training: Saisonplan (Schwimmen, Rad, Laufen, Almere, Marathon) und eigene Sportarten.
import 'package:aironludi/features/training/discipline_pages.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> _openTraining(WidgetTester tester, {UserProfile? profile}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
  if (profile != null) container.read(coachSettingsProvider).profile = profile;
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openRow(WidgetTester tester, String title) async {
  final row = find.text(title).last;
  await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void _back(WidgetTester tester, Type type) => Navigator.of(tester.element(find.byType(type))).pop();

void main() {
  testWidgets('Saisonplan: Disziplinen und Ziele', (tester) async {
    final container = await _openTraining(tester, profile: UserProfile(mode: ProfileMode.season, onboardingDone: true));
    final settings = container.read(coachSettingsProvider);
    expect(find.text('DISZIPLINEN'), findsOneWidget);
    expect(find.text('Meine Sportarten'.toUpperCase()), findsNothing);

    await _openRow(tester, 'Schwimmen');
    expect(find.byType(SwimScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('400 m maximal'), 300);
    await tester.enterText(find.widgetWithText(TextField, '400 m maximal'), '8:40');
    await tester.enterText(find.widgetWithText(TextField, '200 m maximal'), '4:20');
    await tester.pump();
    expect(find.text('CSS 2:10 /100 m'), findsOneWidget);
    await tester.ensureVisible(find.text('Übernehmen'));
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    expect(TestHistory.latest(TestKind.css, settings.tests)?.value, 130);
    _back(tester, SwimScreen);
    await tester.pumpAndSettle();

    for (final (title, type) in [
      ('Rad', BikeScreen),
      ('Laufen', RunScreen),
      ('Almere', AlmereScreen),
      ('Marathon', MarathonScreen),
    ]) {
      await _openRow(tester, title);
      expect(find.byType(type), findsOneWidget, reason: title);
      expect(tester.takeException(), isNull, reason: title);
      _back(tester, type);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Persönlich: eigene Sportarten ohne Saisonwerte', (tester) async {
    await _openTraining(
      tester,
      profile: UserProfile(
        mode: ProfileMode.personal,
        onboardingDone: true,
        sports: const [TrainingSport.run, TrainingSport.bike, TrainingSport.strength],
      ),
    );
    expect(find.text('DISZIPLINEN'), findsNothing);
    expect(find.text('Almere'), findsNothing);
    await _openRow(tester, 'Laufen');
    expect(find.byType(PersonalSportScreen), findsOneWidget);
    expect(find.text('Kilometer pro Woche'.toUpperCase()), findsOneWidget);
    expect(find.text('Pace-Check'.toUpperCase()), findsNothing);
  });
}

// Durchlauf Plan: Woche (nachtragen, Wochenzeiten, nächste Woche), Gym (freies Training bis zum Abschluss, Verlauf,
// Übungsverlauf), Ausdauerplan.
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/gym/exercise_history_charts.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/features/gym/gym_screen.dart';
import 'package:aironludi/features/plan/my_week_screen.dart';
import 'package:aironludi/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'walkthrough.dart';

void main() {
  walk('Woche: Training nachtragen erscheint in Woche und Verlauf; Wochenzeiten; nächste Woche', (
    tester,
    device,
  ) async {
    final container = await startDemo(tester, device: device);
    await tab(tester, 'Plan');
    await tapText(tester, 'Woche');
    expect(find.byType(MyWeekScreen), findsOneWidget);
    final before = (await tester.runAsync(() => container.read(activityRepositoryProvider).all()))!.length;

    step('Training nachtragen');
    await tester.tap(find.byTooltip('Training nachtragen'));
    await settle(tester);
    expect(find.text('Training nachtragen'), findsWidgets);
    await tester.tap(find.byTooltip('Mehr').first);
    await tester.enterText(find.widgetWithText(TextField, 'Bezeichnung (optional)'), 'Abendrunde');
    await settle(tester);
    await tester.tap(find.text('Sichern'));
    await settle(tester, milliseconds: 600);
    final after = (await tester.runAsync(() => container.read(activityRepositoryProvider).all()))!;
    expect(after.length, before + 1);
    expect(after.any((activity) => activity.name == 'Abendrunde'), isTrue);
    expect(find.byType(MyWeekScreen), findsOneWidget);

    step('Wochenzeiten bearbeiten');
    await tester.tap(find.text('Bearbeiten'));
    await settle(tester);
    await back(tester);

    step('Nächste Woche');
    await tester.tap(find.byTooltip('Nächste Woche'));
    await settle(tester);
    await back(tester);
    await back(tester);

    step('Verlauf zeigt das Nachgetragene');
    await tab(tester, 'Verlauf');
    await reveal(tester, find.text('Abendrunde'));
  });

  walk('Gym: Übung mit Verlauf, Auswertung, Trainingsplan anlegen und starten, Einheit löschen', (
    tester,
    device,
  ) async {
    final container = await startDemo(tester, device: device);
    await tab(tester, 'Plan');
    await tapText(tester, 'Einheit starten');
    expect(find.byType(GymScreen), findsOneWidget);

    step('Übungen: Bankdrücken mit Verlauf');
    await tapText(tester, 'Übungen');
    await tester.enterText(find.byType(TextField).first, 'Bankdrücken');
    await settle(tester);
    // Erste Fundstelle: die Zeile der Liste (die letzte wäre das Suchfeld).
    await tester.tap(find.text('Bankdrücken').first);
    await settle(tester);
    await reveal(tester, find.byType(ExerciseHistoryCharts));
    await back(tester);
    await back(tester);

    step('Auswertung');
    await tapText(tester, 'Auswertung');
    await back(tester);

    step('Trainingsplan anlegen');
    await tapText(tester, 'Trainingspläne');
    await tapText(tester, 'Neuen Trainingsplan anlegen');
    await tapText(tester, 'Übung hinzufügen');
    await tester.enterText(find.widgetWithText(TextField, 'Übung suchen'), 'Kniebeuge');
    await settle(tester);
    await tapText(tester, 'Kniebeuge');
    await tester.tap(find.text('Sichern'));
    await settle(tester);
    final routines = container.read(coachSettingsProvider).gym.routines;
    expect(routines.map((routine) => routine.name), contains('Neuer Plan'));

    step('Trainingsplan starten');
    await tester.tap(await reveal(tester, find.byTooltip('Starten')));
    await settle(tester);
    expect(container.read(gymControllerProvider).active?.exercises.map((exercise) => exercise.exerciseID), [
      'kniebeuge',
    ]);
    container.read(gymControllerProvider).cancelActive();
    await settle(tester);
    // Zurück zur Plan-Übersicht und Gym neu öffnen.
    await home(tester);
    await tapText(tester, 'Einheit starten');

    step('Verlauf: Einheit öffnen, löschen');
    final gymRecords = (await tester.runAsync(() => container.read(gymRepositoryProvider).all()))!.length;
    await tapText(tester, 'Alle $gymRecords Einheiten');
    final first = find.byType(Dismissible).first;
    await tester.drag(first, const Offset(-500, 0));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Löschen')));
    await settle(tester, milliseconds: 600);
    expect((await tester.runAsync(() => container.read(gymRepositoryProvider).all()))!.length, gymRecords - 1);
  });
}

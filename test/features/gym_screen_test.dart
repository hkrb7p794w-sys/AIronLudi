// Gym-Reiter: Einstieg über Training, freies Training starten, letzte Einheiten und Auswertung.
import 'dart:async';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/gym/active_workout_screen.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/features/gym/gym_screen.dart';
import 'package:aironludi/features/gym/muscle_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  Future<ProviderContainer> openGym(WidgetTester tester, {List<GymSession> sessions = const []}) async {
    // Bildschirm in iPhone-Größe, damit Ziffernblock und Pausenfeld ganz sichtbar sind.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    // Im Testzonen-Kontext speichern und echte Zeit vergehen lassen (`runAsync` um die Datenbank blockiert hier).
    for (final session in sessions) {
      unawaited(container.read(gymRepositoryProvider).save(session));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    container.read(coachSettingsProvider).profile = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.strength],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gym'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('laufende Einheit: Satz erledigt, Pause mit RIR, Ziffernblock, Liste, beenden', (tester) async {
    final container = await openGym(tester);
    expect(find.byType(GymScreen), findsOneWidget);
    expect(find.textContaining('Lege unter „Trainingspläne“'), findsOneWidget);
    await tester.tap(find.text('Freies Training'));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    final gym = container.read(gymControllerProvider);
    expect(gym.active?.title, 'Krafttraining');
    gym.addExercise(ExerciseLibrary.byID['bankdruecken']!);
    await tester.pump();
    expect(find.text('Satz 1 von 3'), findsOneWidget);

    // Gewicht über den Ziffernblock: erste Taste ersetzt den alten Wert.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Gewicht:')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.tap(find.text('0').last);
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(gym.active!.exercises.first.sets.first.weightKg, 60);

    await tester.tap(find.text('Satz erledigt'));
    await tester.pump();
    expect(gym.active!.doneSetCount, 1);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.textContaining('wie viele wären noch gegangen?'), findsOneWidget);
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(gym.active!.exercises.first.sets.first.rir, 2);
    await tester.tap(find.bySemanticsLabel('Pause 15 Sekunden länger'));
    await tester.pump();
    expect(container.read(coachSettingsProvider).gym.restOverrides['bankdruecken'], 135);
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    expect(gym.restEndsAt, isNull);

    await tester.tap(find.text('Liste'));
    await tester.pumpAndSettle();
    expect(find.textContaining('× '), findsWidgets);
    expect(find.byTooltip('Satz abhaken'), findsNWidgets(2));

    await tester.tap(find.text('Beenden'));
    await tester.pumpAndSettle();
    expect(find.text('2 Sätze sind eingetragen, aber nicht abgehakt.'), findsOneWidget);
    await tester.tap(find.text('Nur abgehakte speichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(gym.active, isNull);
    expect(find.text('Fertig'), findsOneWidget);
    await tester.ensureVisible(find.text('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(find.byType(GymScreen), findsOneWidget);
  });

  testWidgets('letzte Einheiten und Auswertung mit Muskelkarte', (tester) async {
    final session = GymSession(
      workoutKey: null,
      title: 'Oberkörper',
      start: DateTime.now().subtract(const Duration(days: 1)),
      end: DateTime.now().subtract(const Duration(days: 1)).add(const Duration(minutes: 45)),
      exercises: [
        LoggedExercise(
          exerciseID: 'bankdruecken',
          name: 'Bankdrücken',
          group: MuscleGroup.chest,
          sets: [LoggedSet(reps: 10, weightKg: 60), LoggedSet(reps: 9, weightKg: 60)],
        ),
      ],
    );
    await openGym(tester, sessions: [session]);
    expect(find.text('Oberkörper'), findsOneWidget);
    await tester.tap(find.text('Oberkörper'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('60 kg × 10'), findsOneWidget);
    Navigator.of(tester.element(find.byType(SessionDetailScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auswertung'));
    await tester.pumpAndSettle();
    expect(find.byType(GymAnalysisScreen), findsOneWidget);
    expect(find.text('1 Woche in Folge trainiert'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(BodyMap), 200);
    expect(find.bySemanticsLabel(RegExp('Muskelkarte: Brust')), findsOneWidget);
  });
}

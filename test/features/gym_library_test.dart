// Gym-Bibliothek: Übungen mit Detail, Trainingspläne (Vorschlag, eigener Plan) und KI-Plan ohne Worker.
import 'package:aironludi/features/gym/active_workout_screen.dart';
import 'package:aironludi/features/gym/gym_library.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

void main() {
  Future<ProviderContainer> openGym(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
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

  testWidgets('Übungen: suchen und Anleitung öffnen', (tester) async {
    await openGym(tester);
    await tester.tap(find.text('Übungen'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Bankdrücken');
    await tester.pump();
    await tester.tap(find.text('Bankdrücken').first);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(find.text('BEANSPRUCHTE MUSKELN'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Noch keine Sätze erfasst.'), 300);
    expect(find.text('Noch keine Sätze erfasst.'), findsOneWidget);
  });

  testWidgets('Trainingspläne: Vorschlag übernehmen, eigenen Plan anlegen und starten', (tester) async {
    final container = await openGym(tester);
    await tester.tap(find.text('Trainingspläne'));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);
    final settings = container.read(coachSettingsProvider);
    await tester.tap(find.widgetWithText(TextButton, 'Übernehmen').first);
    await tester.pumpAndSettle();
    expect(settings.gym.routines, hasLength(1));

    await tester.tap(find.text('Neuen Trainingsplan anlegen'));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditor), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Sichern')).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Oberkörper');
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bankdrücken');
    await tester.pump();
    await tester.tap(find.text('Bankdrücken').first);
    await tester.pumpAndSettle();
    expect(find.text('1. Bankdrücken'.toUpperCase()), findsOneWidget);
    await tester.tap(find.byTooltip('3 Sätze erhöhen'));
    await tester.pump();
    expect(find.text('4 Sätze'), findsOneWidget);
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    expect(settings.gym.routines.map((routine) => routine.name), contains('Oberkörper'));
    expect(settings.gym.routines.last.items.single.sets, 4);

    await tester.tap(find.byTooltip('Starten').last);
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(container.read(gymControllerProvider).active?.title, 'Oberkörper');
  });

  testWidgets('KI-Trainingsplan ohne Worker: Regel-Vorschlag übernehmen', (tester) async {
    final container = await openGym(tester);
    await tester.tap(find.text('Trainingspläne'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KI-Trainingsplan erstellen'));
    await tester.pumpAndSettle();
    expect(find.byType(GymPlanScreen), findsOneWidget);
    final create = find.text('Plan erstellen');
    await tester.scrollUntilVisible(create, 300, scrollable: find.byType(Scrollable).first);
    // Oben ausrichten, damit die Reiterleiste den Eintrag nicht verdeckt.
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Vorschlag'), findsOneWidget);
    expect(find.textContaining('Regeln (ohne KI)'), findsOneWidget);
    final adopt = find.text('Plan übernehmen');
    await tester.scrollUntilVisible(adopt, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(adopt);
    await tester.pumpAndSettle();
    await tester.tap(adopt);
    await tester.pumpAndSettle();
    expect(container.read(coachSettingsProvider).gym.routines, isNotEmpty);
    expect(find.byType(RoutinesScreen), findsOneWidget);
  });
}

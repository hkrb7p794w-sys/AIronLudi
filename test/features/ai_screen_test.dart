// KI: Empfehlungen mit Bearbeitungsstand, Analyse ohne Worker, Chat ohne Worker, fehlende Daten.
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/features/ai/ai_screen.dart';
import 'package:aironludi/features/ai/chat_screen.dart';
import 'package:aironludi/features/ai/coach_facts.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  test('fehlende Daten werden benannt', () {
    final now = DateTime(2026, 11, 14, 10);
    final today = CalendarDay.fromDate(now);
    expect(
      CoachFacts.missing(metrics: const [], activities: const [], meals: const [], gym: const [], weights: 0, now: now),
      [
        'Keine Erholungsdaten (Ruhepuls, HRV, Schlaf) der letzten 7 Tage',
        'Keine Ausdaueraktivitäten in den letzten 2 Wochen',
        'Keine Krafteinheiten in den letzten 6 Wochen',
        'Kaum erfasste Mahlzeiten (0 Tage in 2 Wochen)',
        'Kein Gewichtsverlauf',
      ],
    );
    final meals = [
      for (var offset = 1; offset <= 3; offset++)
        StoredMeal(
          day: today.adding(-offset),
          createdAt: now,
          category: MealCategory.values.first,
          title: 'Essen',
          items: const [],
        ),
    ];
    final missing = CoachFacts.missing(
      metrics: [DailyMetrics(today)],
      activities: const [],
      meals: meals,
      gym: const [],
      weights: 2,
      now: now,
    );
    expect(missing, contains('Keine Schlafdaten der letzten 7 Tage'));
    expect(missing.any((line) => line.startsWith('Kaum erfasste')), isFalse);
    expect(missing, isNot(contains('Kein Gewichtsverlauf')));
  });

  testWidgets('Empfehlungen: lesen, umsetzen, Grundlage; Analyse und Chat ohne Worker', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    final settings = container.read(coachSettingsProvider);
    final now = DateTime.now();
    settings.insights = [
      Insight(
        topic: InsightTopic.recovery,
        subject: 'schlaf kurz',
        title: 'Früher ins Bett',
        text: 'Drei kurze Nächte in Folge.',
        direction: InsightDirection.values.first,
        origin: InsightOrigin.ai,
        created: now,
        validUntil: now.add(const Duration(days: 3)),
        basis: const ['Schlaf 5,5 h im Schnitt'],
        model: 'test-modell',
      ),
    ];
    await tester.pumpAndSettle();
    expect(find.text('AI-Empfehlungen'), findsOneWidget);
    expect(find.text('1 neu'), findsOneWidget);

    await tester.tap(find.text('AI-Empfehlungen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(AIScreen), findsOneWidget);
    expect(find.text('NEU'), findsOneWidget);
    expect(find.text('Für die KI-Analyse den KI-Worker in den Einstellungen einrichten.'), findsOneWidget);
    expect(find.textContaining('Es fehlen Daten'), findsOneWidget);

    await tester.tap(find.text('Früher ins Bett'));
    await tester.pumpAndSettle();
    expect(settings.insights.single.status, InsightStatus.read);
    expect(find.text('AKTUELL'), findsOneWidget);

    await tester.longPress(find.text('Früher ins Bett'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Worauf beruht das?'));
    await tester.pumpAndSettle();
    expect(find.byType(InsightBasisSheet), findsOneWidget);
    expect(find.text('Schlaf 5,5 h im Schnitt'), findsOneWidget);
    expect(find.text('test-modell'), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Früher ins Bett'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Umgesetzt'));
    await tester.pumpAndSettle();
    expect(settings.insights.single.status, InsightStatus.done);
    final closed = find.text('Umgesetzt und verworfen (1)');
    await tester.scrollUntilVisible(closed, 300, scrollable: find.byType(Scrollable).first);
    expect(closed, findsOneWidget);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(AIScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Coach fragen'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    await tester.tap(find.text(ChatScreen.suggestions.first));
    await tester.pumpAndSettle();
    expect(find.text(ChatScreen.suggestions.first), findsOneWidget);
    expect(find.textContaining('Für den Chat brauche ich den KI-Worker'), findsOneWidget);
  });
}

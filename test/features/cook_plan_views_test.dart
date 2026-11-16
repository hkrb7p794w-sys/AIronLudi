// Kochen planen: Einstieg aus den Rezeptideen, Menge, Freigabe ohne Worker, Detail mit Portionen und Lagerung,
// Links coach://cook/<code> und coach://meal/<code>.
import 'dart:async';

import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/features/nutrition/meal_share_views.dart';
import 'package:aironludi/features/recipes/cook_plan_controller.dart';
import 'package:aironludi/features/recipes/cook_plan_views.dart';
import 'package:aironludi/features/recipes/recipe_views.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

CookPlan _plan() {
  final people = [
    CookPerson(
      id: CookPerson.meID,
      share: CookShare(name: 'Ich', kcal: 2400, protein: 140),
    ),
    CookPerson(
      id: 'abcde12345',
      share: CookShare(name: 'Sam', kcal: 1800, protein: 100),
    ),
  ];
  final output = JsonValue({
    'rezepte': [
      {
        'titel': 'Linsen-Dal',
        'mahlzeit': 'abendessen',
        'minuten': 30,
        'zubereitung': ['Zwiebeln anschwitzen.', 'Linsen kochen.'],
        'zutaten': [
          {
            'name': 'Rote Linsen',
            'menge_g': 150,
            'naehrwerte_100g': {'kcal': 340, 'protein_g': 24},
          },
        ],
        'vorkochen_geeignet': true,
        'haltbarkeit_tage': 3,
        'einfrierbar': true,
        'lagerung': 'Luftdicht im Kühlschrank.',
        'aufwaermen': 'In der Pfanne.',
        'kompromiss': 'Mehr Linsen für Person 1.',
      },
    ],
  });
  return CookPlanner.plans(
    output,
    people: people,
    meal: MealCategory.dinner,
    amount: const CookDays(2),
    source: 'KI · test',
    created: DateTime(2026, 11, 16),
  ).plans.single;
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  Future<ProviderContainer> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
  }

  testWidgets('Kochen planen: Einstieg, Menge, Partner-Ansicht, Freigeben ohne Worker', (tester) async {
    await start(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(CupertinoTabBar)))
          .push(MaterialPageRoute<void>(builder: (_) => const RecipesScreen())),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kochen planen: für wen, wie viel'));
    await tester.pumpAndSettle();
    expect(find.byType(CookPlanScreen), findsOneWidget);
    expect(find.text('2 Teller für mehrere Mahlzeiten.'), findsOneWidget);

    await tester.tap(find.text('2 Portionen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 Tage').last);
    await tester.pumpAndSettle();
    expect(find.text('Einmal kochen, 3 Tage essen: je Tag ein Teller.'), findsOneWidget);

    await tester.tap(find.text('Rezepte vorschlagen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Für Rezeptideen muss der KI-Worker'), findsOneWidget);

    await tester.tap(find.text('Gemeinsam kochen: Personen und Freigaben'));
    await tester.pumpAndSettle();
    expect(find.byType(CookPartnersScreen), findsOneWidget);
    expect(find.textContaining('Wird freigegeben:'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Dein Name für die andere Person'), 'Alex');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Was ich nicht mag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Freigeben'));
    await tester.pumpAndSettle();
    // Ohne Worker keine Freigabe; die Meldung erscheint unten.
    expect(find.text('Freigabe aktualisieren'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Detail: Portionen je Person, Lagerung, Zutaten bearbeiten', (tester) async {
    await start(tester);
    final controller = CookPlanController()..cookPlans = [_plan()];
    final plan = controller.cookPlans.single;
    unawaited(
      Navigator.of(tester.element(find.byType(CupertinoTabBar))).push(
        MaterialPageRoute<void>(
          builder: (_) => CookPlanDetailScreen(controller: controller, planID: plan.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wer isst wie viel'.toUpperCase()), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Mehr Linsen für Person 1.'), findsOneWidget);
    expect(find.text('Tag 2'), findsOneWidget);
    expect(find.text('Kühlschrank'), findsOneWidget);
    expect(find.text('Meine Portion eintragen …'), findsOneWidget);

    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('150 g'), findsOneWidget);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('155 g'), findsOneWidget);
    expect(controller.cookPlans.single.base.single.grams, 155);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Links: Kochpartner und geteilte Mahlzeit', (tester) async {
    final container = await start(tester);
    container.read(incomingLinkProvider.notifier).open(Uri.parse('coach://cook/abcde12345'));
    await tester.pumpAndSettle();
    expect(find.byType(CookPartnersScreen), findsOneWidget);
    expect(find.text('abcde12345'), findsOneWidget);
    Navigator.of(tester.element(find.byType(CookPartnersScreen))).pop();
    await tester.pumpAndSettle();

    container.read(incomingLinkProvider.notifier).open(Uri.parse('coach://meal/mealcode12'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceivedMealScreen), findsOneWidget);
    expect(container.read(incomingLinkProvider), isNull);
  });
}

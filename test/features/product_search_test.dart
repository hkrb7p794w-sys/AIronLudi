// Ernährung: Erfassen mit Suche zuerst – Vorschläge zur Mahlzeit, „+“ in den Korb, Markenprodukte (Open Food Facts,
// hier ohne Netz), Filter, Menge wählen, alles auf einmal eintragen.
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/features/nutrition/capture_views.dart';
import 'package:aironludi/features/nutrition/product_search_screen.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart' hide Badge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FakeHttpTransport _skyr() => FakeHttpTransport(
  (request) => HttpResponse(
    200,
    utf8.encode(
      jsonEncode({
        'products': [
          {
            'code': '4000000000001',
            'product_name_de': 'Skyr Natur',
            'brands': 'Molkerei',
            'serving_quantity': 150,
            'serving_size': '1 Becher (150 g)',
            'nutriments': {'energy-kcal_100g': 63, 'proteins_100g': 11, 'carbohydrates_100g': 4, 'fat_100g': 0.2},
          },
        ],
      }),
    ),
  ),
);

Future<FoodLogResult? Function()> _open(WidgetTester tester, FakeHttpTransport transport, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  FoodLogResult? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [openFoodFactsProvider.overrideWithValue(OpenFoodFactsClient(transport: transport))],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await Navigator.of(context).push<FoodLogResult>(MaterialPageRoute(builder: (_) => screen)),
            child: const Text('öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('öffnen'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  setUpAll(() => BLS.load(File('packages/coach_core/assets/bls.tsv').readAsStringSync()));

  final banana = MealItem(
    name: 'Banane',
    grams: 120,
    source: MealItemSource.manual,
    per100g: NutrientValues({Nutrient.kcal: 90, Nutrient.protein: 1, Nutrient.carbs: 20, Nutrient.fat: 0.3}),
  );

  testWidgets('Vorschläge mit „+“, Markenprodukt mit Menge, Korb, Eintragen', (tester) async {
    final transport = _skyr();
    final result = await _open(
      tester,
      transport,
      ProductSearchScreen(
        own: [banana],
        picks: [banana],
        category: MealCategory.lunch,
        eaten: NutrientValues({Nutrient.kcal: 1600}),
        targets: NutrientValues({Nutrient.kcal: 2800}),
      ),
    );
    // Oben Mahlzeit und Tageskalorien, Vorschläge ohne Suchbegriff.
    expect(find.text('Mittagessen'), findsOneWidget);
    expect(find.text('1600 / 2800'), findsOneWidget);
    expect(find.text('Vorschläge · Mittagessen'), findsOneWidget);
    expect(find.text('108 kcal · 1 P · 24 K · 0 F · 120 g'), findsOneWidget);

    // „+“ legt mit der letzten Menge in den Korb; die Tageskalorien zählen ihn mit.
    await tester.tap(find.byTooltip('Banane hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Eintragen (1)'), findsOneWidget);
    expect(find.text('1708 / 2800'), findsOneWidget);

    // Suche: online erst nach der Pause beim Tippen.
    await tester.enterText(find.byType(TextField), 'Skyr');
    await tester.pump();
    expect(transport.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    // Zuerst die Volltextsuche (Search-a-licious); mit Treffern keine zweite Anfrage.
    expect(transport.requests.single.url.host, 'search.openfoodfacts.org');
    expect(transport.requests.single.url.queryParameters['q'], 'Skyr');
    expect(find.text('Skyr Natur (Molkerei)'), findsOneWidget);
    expect(find.text('95 kcal · 17 P · 6 K · 0 F · 150 g (1 Becher (150 g))'), findsOneWidget);

    // Filter: nur Lebensmittel blendet Markenprodukte aus.
    await tester.tap(find.widgetWithText(FilterChip, 'Lebensmittel'));
    await tester.pumpAndSettle();
    expect(find.text('Skyr Natur (Molkerei)'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'Lebensmittel'));
    await tester.pumpAndSettle();

    // Antippen: Menge wählen.
    await tester.tap(find.text('Skyr Natur (Molkerei)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '100 g'));
    await tester.pumpAndSettle();
    expect(find.textContaining('63 kcal · Protein 11 g'), findsOneWidget);
    await tester.tap(find.text('Zur Mahlzeit hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Eintragen (2)'), findsOneWidget);
    expect(find.textContaining('2 Positionen · 171 kcal'), findsOneWidget);

    // Eine Position wieder entfernen, dann eintragen.
    await tester.tap(find.byTooltip('Entfernen').first);
    await tester.pumpAndSettle();
    expect(find.text('Eintragen (1)'), findsOneWidget);
    await tester.tap(find.text('Eintragen (1)'));
    await tester.pumpAndSettle();
    final logged = result() as FoodLogItems;
    expect(logged.category, MealCategory.lunch);
    expect(logged.items.single.barcode, '4000000000001');
    expect(logged.items.single.grams, 100);
    expect(transport.requests, hasLength(1));
  });

  testWidgets('Andere Wege als Reiter: Scannen, KI, Nur kcal', (tester) async {
    var result = await _open(tester, _skyr(), const ProductSearchScreen());
    expect(find.textContaining('Unten ein Lebensmittel oder Produkt suchen'), findsOneWidget);
    expect(find.text('Eintragen'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Scannen'));
    await tester.pumpAndSettle();
    expect((result() as FoodLogOther).other, CaptureOther.barcode);

    result = await _open(tester, _skyr(), const ProductSearchScreen());
    await tester.ensureVisible(find.bySemanticsLabel('KI · Foto/Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('KI · Foto/Text'));
    await tester.pumpAndSettle();
    expect((result() as FoodLogOther).other, isNull);
  });
}

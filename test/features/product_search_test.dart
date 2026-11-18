// Ernährung: Produktsuche mit eigenen Lebensmitteln, BLS und Markenprodukten (Open Food Facts, hier ohne Netz).
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/features/nutrition/product_search_screen.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => BLS.load(File('packages/coach_core/assets/bls.tsv').readAsStringSync()));

  testWidgets('Suchen, filtern, Menge wählen, zur Mahlzeit hinzufügen', (tester) async {
    final transport = FakeHttpTransport(
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
    MealItem? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [openFoodFactsProvider.overrideWithValue(OpenFoodFactsClient(transport: transport))],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await Navigator.of(context)
                      .push<MealItem>(MaterialPageRoute(builder: (_) => const ProductSearchScreen())),
              child: const Text('öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Skyr');
    await tester.pump();
    // Erst nach der Pause beim Tippen geht die Suche ins Netz.
    expect(transport.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(transport.requests.single.url.queryParameters['search_terms'], 'Skyr');
    expect(find.text('Skyr Natur (Molkerei)'), findsOneWidget);
    expect(find.textContaining('Portion (150 g): 95 kcal'), findsOneWidget);

    // Filter „Kalorienarm“ lässt den Skyr stehen, „Lebensmittel“ allein blendet Markenprodukte aus.
    await tester.tap(find.widgetWithText(FilterChip, 'Kalorienarm'));
    await tester.pumpAndSettle();
    expect(find.text('Skyr Natur (Molkerei)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Lebensmittel'));
    await tester.pumpAndSettle();
    expect(find.text('MARKENPRODUKTE'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'Lebensmittel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skyr Natur (Molkerei)'));
    await tester.pumpAndSettle();
    expect(find.text('1 Becher (150 g)'), findsOneWidget);
    expect(find.textContaining('95 kcal · Protein 17 g'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '100 g'));
    await tester.pumpAndSettle();
    expect(find.textContaining('63 kcal · Protein 11 g'), findsOneWidget);
    await tester.tap(find.text('Zur Mahlzeit hinzufügen'));
    await tester.pumpAndSettle();
    expect(result?.grams, 100);
    expect(result?.barcode, '4000000000001');
    // Derselbe Begriff fragt nicht noch einmal.
    expect(transport.requests, hasLength(1));
  });
}

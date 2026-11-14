// Erfassen: Foto und Text, Schnellzugriffe, Barcode und unbekanntes Produkt.
import 'package:aironludi/features/nutrition/capture_views.dart';
import 'package:aironludi/features/nutrition/meal_shortcuts.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Öffnet [page] per Knopf und merkt sich das Ergebnis.
Future<List<Object?>> host(WidgetTester tester, Widget Function() page, {bool sheet = false}) async {
  final results = <Object?>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              sheet
                  ? await showModalBottomSheet<Object>(context: context, builder: (_) => page())
                  : await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => page())),
            ),
            child: const Text('öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('öffnen'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  final photo = img.encodePng(img.Image(width: 2, height: 2));

  testWidgets('Analysieren erst mit Text oder Foto; Foto und Text gehen zusammen zurück', (tester) async {
    final results = await host(tester, () => CaptureScreen(pickPhoto: (_) async => photo));
    final analyze = find.widgetWithText(TextButton, 'Analysieren');
    expect(tester.widget<TextButton>(analyze).onPressed, isNull);
    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    expect(find.text('Foto ausgewählt'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ohne Soße');
    await tester.pump();
    await tester.tap(analyze);
    await tester.pumpAndSettle();
    final result = results.single! as CaptureAnalyze;
    expect((result.text, result.photo), ('ohne Soße', photo));
  });

  testWidgets('andere Wege und Schnellzugriffe', (tester) async {
    final logged = <String>[];
    final opened = <String>[];
    final item = MealItem(
      name: 'Skyr',
      grams: 150,
      source: MealItemSource.manual,
      per100g: NutrientValues({Nutrient.kcal: 60}),
    );
    final shortcuts = CaptureShortcuts(
      favorites: [
        FavoriteMeal(title: 'Skyr-Bowl', items: [item], category: MealCategory.breakfast),
      ],
      log: (title, _) => logged.add(title),
      open: (title, _) => opened.add(title),
    );
    var results = await host(tester, () => CaptureScreen(shortcuts: shortcuts));
    // Ohne „Zuletzt“ beginnt die Auswahl bei den Favoriten.
    expect(find.text('150 g · 90 kcal'), findsOneWidget);
    await tester.tap(find.byTooltip('Skyr-Bowl eintragen'));
    await tester.pumpAndSettle();
    expect(logged, ['Skyr-Bowl']);
    expect(results.single, isNull);

    results = await host(tester, () => CaptureScreen(shortcuts: shortcuts));
    await tester.tap(find.text('Skyr-Bowl'));
    await tester.pumpAndSettle();
    expect(opened, ['Skyr-Bowl']);

    results = await host(tester, () => const CaptureScreen());
    await tester.tap(find.bySemanticsLabel('Barcode'));
    await tester.pumpAndSettle();
    expect((results.single! as CaptureChoose).other, CaptureOther.barcode);
  });

  testWidgets('Barcode von Hand: Suchen erst mit gültiger Prüfziffer', (tester) async {
    final results = await host(tester, () => const BarcodeEntryScreen(showsScanner: false));
    expect(find.text('Kamera-Scan nicht verfügbar'), findsOneWidget);
    final search = find.widgetWithText(FilledButton, 'Suchen');
    await tester.enterText(find.byType(TextField), '4006381333932');
    await tester.pump();
    expect(tester.widget<FilledButton>(search).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '4006381333931');
    await tester.pump();
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(results, ['4006381333931']);
  });

  testWidgets('unbekanntes Produkt: Tabelle fotografieren oder selbst eintragen', (tester) async {
    var results = await host(
      tester,
      () => MissingBarcodeSheet(barcode: '4006381333931', pickPhoto: (_) async => photo),
      sheet: true,
    );
    expect(find.textContaining('4006381333931 ist bei Open Food Facts nicht bekannt'), findsOneWidget);
    await tester.tap(find.text('Foto der Tabelle wählen'));
    await tester.pumpAndSettle();
    expect(results, [photo]);

    results = await host(tester, () => const MissingBarcodeSheet(barcode: '4006381333931'), sheet: true);
    await tester.tap(find.text('Werte selbst eintragen'));
    await tester.pumpAndSettle();
    expect(results, [MissingBarcodeSheet.create]);
  });
}

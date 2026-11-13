// Port von CoachCoreTests/PortionTests.swift und MealAmendTests.swift (ohne den AIPolicy-Fall, der mit dem
// KI-Modul folgt).
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

JsonValue _item(String name, double grams, {required double kcal}) => JsonValue({
  'name': name,
  'menge_g': grams,
  'sicherheit': 'mittel',
  'naehrwerte_100g': {'kcal': kcal, 'protein_g': 20},
});

void main() {
  setUpAll(() => BLS.load(File('assets/bls.tsv').readAsStringSync()));

  test('Portionen aus Text und Packung', () {
    expect(PortionGuess.fromAmountText('2 Scheiben', grams: 60), const Portion('Scheibe', 30));
    expect(PortionGuess.fromAmountText('1 Tasse (200 ml)', grams: 200), const Portion('Tasse', 200));
    expect(PortionGuess.fromAmountText('zwei Eier', grams: 110), const Portion('Ei', 55));
    expect(PortionGuess.fromAmountText('150 g', grams: 150), isNull);
    expect(PortionGuess.fromAmountText('etwas Öl', grams: 10), isNull);
    expect(PortionGuess.serving(text: '1 Riegel (45 g)', grams: 45), const Portion('Riegel', 45));
    expect(PortionGuess.serving(text: '45 g', grams: 45), const Portion('Portion', 45));
    expect(PortionGuess.serving(), isNull);

    final bread = MealItem(
      name: 'Brot',
      grams: 60,
      source: MealItemSource.ai,
      per100g: NutrientValues({Nutrient.kcal: 250}),
    )..portion = const Portion('Scheibe', 30);
    expect(bread.portionCount, 2);
    bread.setPortions(1.5);
    expect(bread.grams, 45);
    expect(bread.amountLabel, '1½ × Scheibe (45 g)');
    expect(bread.scaledBy(2).grams, 90);
    expect(PortionGuess.format(0.5), '½');
    expect(PortionGuess.format(1.25), '1,25');
  });

  test('fehlende Werte und Widerspruch kcal/Makros', () {
    final full = MealItem(
      name: 'A',
      grams: 100,
      source: MealItemSource.manual,
      per100g: NutrientValues({Nutrient.kcal: 100, Nutrient.protein: 5}),
    );
    final empty = MealItem(
      name: 'B',
      grams: 100,
      source: MealItemSource.manual,
      per100g: NutrientValues({Nutrient.kcal: 50}),
    );
    expect(NutrientCheck.missing(Nutrient.protein, [full, empty]), 1);
    // Haferflocken: 13 P, 59 KH, 7 F, 10 Ballaststoffe ≈ 371 kcal – passt zu 372.
    final oats = NutrientValues({
      Nutrient.kcal: 372,
      Nutrient.protein: 13,
      Nutrient.carbs: 59,
      Nutrient.fat: 7,
      Nutrient.fiber: 10,
    });
    expect(NutrientCheck.energyMismatch(oats), isNull);
    // Tippfehler: 37 statt 372 kcal.
    final typo = oats.copy()..[Nutrient.kcal] = 37;
    expect(NutrientCheck.energyMismatch(typo), contains('371'));
    expect(
      NutrientCheck.energyMismatch(
        NutrientValues({Nutrient.kcal: 5, Nutrient.protein: 0, Nutrient.carbs: 1, Nutrient.fat: 0}),
      ),
      isNull,
    );
  });

  test('liest die Antwort zur Nährwerttabelle', () {
    final output = JsonValue({
      'name': 'Proteinriegel Erdnuss',
      'portion_name': 'Riegel',
      'portion_g': 45,
      'naehrwerte_100g': {'kcal': 380, 'protein_g': 33, 'fat_g': 14},
    });
    final item = NutritionLabel.item(output)!;
    expect(item.name, 'Proteinriegel Erdnuss');
    expect(item.grams, 45);
    expect(item.portion, const Portion('Riegel', 45));
    expect(item.per100g[Nutrient.protein], 33);
    expect(item.source, MealItemSource.manual);
    expect(NutritionLabel.item(const JsonValue({'name': 'x'})), isNull);
  });

  test('Analyse liest „vielleicht vergessen“', () {
    final output = JsonValue({
      'titel': 'Reis mit Gemüse',
      'items': [_item('Reis gekocht', 200, kcal: 130).raw],
      'vielleicht_vergessen': ['Bratöl', 'Soße', '', 3],
    });
    expect(MealAnalysis.fromOutput(output)!.possiblyMissing, ['Bratöl', 'Soße']);
  });

  test('Ergänzen fügt nur neue Positionen an', () {
    final existing = [
      MealItem(name: 'Reis', grams: 200, source: MealItemSource.ai, per100g: NutrientValues({Nutrient.kcal: 130})),
    ];
    final output = JsonValue({
      'items': [_item('Hähnchenbrust', 150, kcal: 110).raw, _item('Olivenöl', 10, kcal: 884).raw],
      'hinweis': '',
    });
    final amendment = MealAnalysis.amendment(output);
    expect(amendment.items.map((item) => item.name), ['Hähnchenbrust', 'Olivenöl']);
    final combined = [...existing, ...amendment.items];
    // Bestehende Position unverändert, Summe neu: 260 + Hähnchen (BLS oder 165) + Öl (BLS oder 88,4).
    expect(combined[0], existing[0]);
    expect(NutritionSummary.totals(combined)[Nutrient.kcal] ?? 0, greaterThan(260 + 150));
    expect(
      amendment.items.every((item) => item.source == MealItemSource.ai || item.source == MealItemSource.bls),
      isTrue,
    );
    // Leere Ergänzung bleibt leer (kein Fehler, kein Überschreiben).
    final empty = MealAnalysis.amendment(const JsonValue({'items': <Object?>[], 'hinweis': 'Unklar'}));
    expect(empty.items, isEmpty);
    expect(empty.hint, 'Unklar');
  });
}

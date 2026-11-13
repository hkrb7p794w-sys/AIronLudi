// Port von CoachCoreTests/BLSTests.swift.
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => BLS.load(File('assets/bls.tsv').readAsStringSync()));

  test('Tabelle lädt', () {
    expect(BLS.foods.length, greaterThan(7000));
    final oats = BLS.food('C133000')!;
    expect(oats.name, 'Hafer Flocken');
    expect(oats.per100g[Nutrient.kcal], 348);
    expect(oats.per100g[Nutrient.protein], 13.22);
    expect(oats.per100g[Nutrient.vitaminC], isNull);
  });

  group('Suchbegriff der KI findet das Lebensmittel', () {
    const cases = {
      'Hühnerei gekocht': 'E111132',
      'Eier gekocht': 'E111132',
      'Haferflocken': 'C133000',
      'Möhren gekocht': 'G620132',
      'Karotte': 'G620100',
      'Erdnüsse': 'H110600',
      'Walnüsse': 'H120100',
      'Kartoffeln gekocht': 'K110132',
      'Nudeln gekocht': 'E401032',
      'Reis poliert, gekocht': 'C352032',
      'Vollmilch 3,5 % Fett': 'M111300',
      'Kaffee mit Milch': 'N410200',
      'Butter': 'Q611000',
      'Pilsner Bier': 'P163000',
      'Weizenbrötchen': 'B511000',
      'Apfel': 'F110100',
      'Tomaten': 'G561100',
    };
    for (final MapEntry(key: term, value: code) in cases.entries) {
      test(term, () => expect(BLS.match(term)?.code, code, reason: '$term → ${BLS.match(term)?.name}'));
    }
  });

  group('Schätzung bleibt, wenn unklar', () {
    for (final term in ['Brötchen', 'Bier', 'Müsli', 'Cola', 'Rührei', '', 'x']) {
      test('„$term“', () => expect(BLS.match(term), isNull, reason: '$term → ${BLS.match(term)?.name}'));
    }
  });

  test('Sonderprodukte nur, wenn genannt', () {
    expect(BLS.match('Butter')!.name.contains('gesalzen'), isFalse);
    expect(BLS.match('Butter gesalzen')?.code, 'Q6A4000');
    expect(BLS.match('Teigwaren glutenfrei gekocht')?.code, 'E612032');
  });

  test('Anreichern ersetzt die Schätzung und behält Fehlendes', () {
    final item = MealItem(
      name: 'Haferflocken',
      grams: 50,
      source: MealItemSource.ai,
      per100g: NutrientValues({Nutrient.kcal: 370, Nutrient.protein: 12, Nutrient.vitaminC: 1}),
    )..searchTerm = 'Haferflocken';
    final enriched = BLS.enrich(item);
    expect(enriched.source, MealItemSource.bls);
    expect(enriched.blsCode, 'C133000');
    expect(enriched.name, 'Haferflocken');
    expect(enriched.per100g[Nutrient.kcal], 348);
    expect(enriched.per100g[Nutrient.vitaminC], 1);
    expect(enriched.amounts[Nutrient.kcal], 174);

    final other = BLS.food('E111132')!;
    final switched = BLS.apply(other, enriched);
    expect(switched.per100g[Nutrient.vitaminC], other.per100g[Nutrient.vitaminC]);
    expect(switched.blsCode, 'E111132');
  });

  test('andere Quellen bleiben', () {
    final manual = MealItem(
      name: 'Haferflocken',
      grams: 50,
      source: MealItemSource.manual,
      per100g: NutrientValues({Nutrient.kcal: 1}),
    );
    expect(BLS.enrich(manual), manual);
    final unknown = MealItem(
      name: 'Omas Spezialkuchen',
      grams: 100,
      source: MealItemSource.ai,
      per100g: NutrientValues({Nutrient.kcal: 300}),
    )..searchTerm = 'Spezialkuchen';
    expect(BLS.enrich(unknown).source, MealItemSource.ai);
  });

  test('Suche findet Grundeinträge zuerst', () {
    final results = BLS.search('hafer');
    expect(results, isNotEmpty);
    expect(results.first.name.startsWith('Hafer'), isTrue);
    expect(results.any((food) => food.code == 'C133000'), isTrue);
    expect(BLS.search('x'), isEmpty);
    expect(BLS.search('apfel roh').first.code, 'F110100');
  });

  test('liest die Tabelle', () {
    final foods = BLS.parse('# Kommentar\ncode\tname\tkcal\tprotein_g\tunbekannt\nA1\tTest\t100\t\t5\n\nkaputt\n');
    expect(foods.length, 1);
    expect(foods[0].per100g[Nutrient.kcal], 100);
    expect(foods[0].per100g[Nutrient.protein], isNull);
  });

  test('Getränke werden erkannt', () {
    expect(BLS.food('N410100')!.item().isDrink, isTrue);
    expect(BLS.food('C133000')!.item().isDrink, isFalse);
  });
}

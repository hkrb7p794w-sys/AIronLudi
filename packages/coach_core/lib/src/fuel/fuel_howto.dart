// Fuel Planner: wie man es zu sich nimmt – Tipps je Produktart, Alltags-Snack, Sportart und Phase. Praxisregeln
// (Spezifikation 10.3); was belegt ist, steht dort.
import 'fuel_food.dart';
import 'fuel_plan.dart';
import 'fuel_product.dart';
import 'fuel_scenario.dart';

abstract final class FuelHowTo {
  /// Je Produktart bzw. Alltags-Snack.
  static String product(FuelProduct product) {
    final snack = FuelSnacks.byProductId(product.id);
    if (snack != null) return snack.tip;
    return switch (product.kind) {
      FuelProductKind.gel =>
        'Mit 150–250 ml Wasser nachspülen – nicht mit einem Kohlenhydrat-Getränk (zu konzentriert).',
      FuelProductKind.chew => 'Über ein paar Minuten verteilt kauen, mit Wasser.',
      FuelProductKind.bar => 'In kleinen Bissen und gut gekaut, eher in ruhigen Phasen; vorher anreißen.',
      FuelProductKind.food => 'Mundgerecht vorbereiten (Folie, Beutel), in ruhigen Phasen essen.',
      FuelProductKind.drink || FuelProductKind.drinkMix =>
        'Alle 10–15 min ein paar Schlucke statt viel auf einmal; Flasche vorher fertig mischen.',
      FuelProductKind.electrolyte => 'Mit einem Schluck Wasser einnehmen, nie ohne Flüssigkeit.',
    };
  }

  /// Wie man unterwegs in dieser Sportart isst und trinkt.
  static String sport(FuelSport sport) => switch (sport) {
    FuelSport.run =>
      'Gels und Kleines im Laufgürtel oder in der Tasche; an Verpflegungsstellen den Becher zusammendrücken und '
          'schluckweise trinken.',
    FuelSport.bike =>
      'Feste Kost in der ersten Hälfte, später Gels und Getränk; zweite Flasche einplanen, in ruhigen Abschnitten '
          'essen.',
    FuelSport.swim => 'Flasche und Gels am Beckenrand bzw. Boot bereitlegen; in der Pause zügig einnehmen.',
    FuelSport.triathlon =>
      'Im Wasser nichts; auf dem Rad den Großteil (feste Kost zuerst), beim Laufen Gels und Schlucke an den '
          'Verpflegungsstellen.',
    FuelSport.hybrid => 'Zwischen den Stationen kurz trinken oder ein Gel nehmen; nichts Schweres.',
    FuelSport.strength => 'Zwischen den Sätzen schluckweise trinken.',
  };

  /// Allgemeine Hinweise je Phase.
  static List<String> phase(FuelPhase phase, FuelScenario scenario) => switch (phase) {
    FuelPhase.pre => [
      'Ballaststoff- und fettarm, nichts Neues ausprobieren – schon gar nicht am Wettkampftag.',
      if (scenario.sport == FuelSport.run || scenario.sport == FuelSport.triathlon)
        'Vor dem Laufen lieber etwas weniger und früher essen; der Magen wird durchgeschüttelt.',
    ],
    FuelPhase.intra => [sport(scenario.sport)],
    FuelPhase.post => [
      'Innerhalb der ersten Stunde beginnen – je früher, desto schneller sind die Speicher wieder voll.',
      'Trinken über 2–4 Stunden verteilen, mit etwas Salz (Brühe, Brezeln, salzige Mahlzeit).',
    ],
  };
}

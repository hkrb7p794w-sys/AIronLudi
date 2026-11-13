/// Runden wie Swifts `.toNearestOrEven` bzw. Pythons `round()` („Bankers Rounding“): genau in der Mitte zur geraden
/// Zahl. Die Analyse-Regeln des Altbestands sind in Python geschrieben; nur so stimmen die Ergebnisse überein.
int roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final difference = value - floor;
  if (difference > 0.5) return floor.toInt() + 1;
  if (difference < 0.5) return floor.toInt();
  final down = floor.toInt();
  return down.isEven ? down : down + 1;
}

double roundHalfEvenDouble(double value) => roundHalfEven(value).toDouble();

/// Auf eine Nachkommastelle mit [roundHalfEven].
double round1HalfEven(double value) => roundHalfEven(value * 10) / 10;

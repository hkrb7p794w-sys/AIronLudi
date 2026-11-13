/// Mahlzeit des Tages. Die Rohwerte sind gespeichert und Teil von Links und Sicherungen – nicht ändern.
enum MealCategory {
  breakfast('fruehstueck', 'Frühstück'),
  lunch('mittagessen', 'Mittagessen'),
  dinner('abendessen', 'Abendessen'),
  snack('snack', 'Snack'),
  other('sonstiges', 'Sonstiges');

  const MealCategory(this.rawValue, this.label);

  final String rawValue;
  final String label;

  static MealCategory? fromRaw(String? raw) => values.where((value) => value.rawValue == raw).firstOrNull;

  /// Kategorie nach Uhrzeit (wie `guess_category` im Altbestand).
  static MealCategory guess({required int hour, required int minute}) {
    final time = hour + minute / 60;
    if (4 <= time && time < 10.5) return breakfast;
    if (10.5 <= time && time < 14.5) return lunch;
    if (17.5 <= time && time < 21.5) return dinner;
    return snack;
  }
}

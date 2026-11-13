/// Suche in eigenen Lebensmitteln und Mahlzeiten (Port von `FoodSearch`). Hier vorerst nur die Normalisierung, die
/// auch die BLS-Suche nutzt; die Rangfolge folgt mit `QuickLog`.
abstract final class FoodSearch {
  static const _folding = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', //
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', //
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e', //
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', //
    'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n', //
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ō': 'o', 'ő': 'o', //
    'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ť': 't', //
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', //
    'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
  };

  /// Kleinbuchstaben, Umlaute ausgeschrieben (ä → ae, ß → ss), andere Akzente entfernt, ohne Rand-Leerraum.
  static String normalized(String text) {
    final lower = text
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    final buffer = StringBuffer();
    for (final char in lower.split('')) {
      buffer.write(_folding[char] ?? char);
    }
    return buffer.toString().trim();
  }
}

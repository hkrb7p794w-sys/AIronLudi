import 'package:collection/collection.dart';

final _wordSeparator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Ein Treffer-Kandidat der Suche.
final class FoodSearchCandidate {
  const FoodSearchCandidate({required this.id, required this.title, required this.useCount, required this.lastUsed});

  final String id;
  final String title;
  final int useCount;
  final DateTime lastUsed;

  @override
  bool operator ==(Object other) =>
      other is FoodSearchCandidate &&
      other.id == id &&
      other.title == title &&
      other.useCount == useCount &&
      other.lastUsed.isAtSameMomentAs(lastUsed);

  @override
  int get hashCode => Object.hash(id, title, useCount);

  @override
  String toString() => 'FoodSearchCandidate($id, $title)';
}

/// Suche über eigene Lebensmittel und frühere Mahlzeiten: alle Wörter müssen vorkommen, Treffer am Wortanfang und
/// häufig Genutztes zuerst. Groß-/Kleinschreibung und Umlaute spielen keine Rolle („muesli“ findet „Müsli“).
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

  static List<FoodSearchCandidate> rank(List<FoodSearchCandidate> candidates, {required String query, int limit = 12}) {
    final words = normalized(query).split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final scored = <(FoodSearchCandidate, int)>[];
    for (final candidate in candidates) {
      final title = normalized(candidate.title);
      if (!words.every(title.contains)) continue;
      final titleWords = title.split(_wordSeparator).where((word) => word.isNotEmpty).toList();
      final prefixHits = words.where((word) => titleWords.any((titleWord) => titleWord.startsWith(word))).length;
      final starts = title.startsWith(words[0]) ? 2 : 0;
      scored.add((candidate, starts + prefixHits));
    }
    mergeSort(
      scored,
      compare: (a, b) {
        final byScore = b.$2.compareTo(a.$2);
        if (byScore != 0) return byScore;
        final byUse = b.$1.useCount.compareTo(a.$1.useCount);
        if (byUse != 0) return byUse;
        return b.$1.lastUsed.compareTo(a.$1.lastUsed);
      },
    );
    return [for (final entry in scored.take(limit)) entry.$1];
  }
}

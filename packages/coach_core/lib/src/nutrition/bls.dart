import 'package:collection/collection.dart';

import 'food_search.dart';
import 'meal.dart';
import 'nutrient.dart';

/// Ein Lebensmittel aus dem Bundeslebensmittelschlüssel mit Nährwerten je 100 g.
final class BLSFood {
  const BLSFood({required this.code, required this.name, required this.per100g});

  final String code;
  final String name;
  final NutrientValues per100g;

  String get id => code;

  /// Gerichte und Rezepte (Codes X und Y) statt einzelner Lebensmittel.
  bool get isDish => code.startsWith('X') || code.startsWith('Y');

  /// Als Position einer Mahlzeit (Standardmenge 100 g).
  MealItem item({double grams = 100}) => MealItem(
    name: name,
    grams: grams,
    source: MealItemSource.bls,
    per100g: per100g.copy(),
    blsCode: code,
    isDrink: BLS.isDrink(this),
  );

  @override
  bool operator ==(Object other) =>
      other is BLSFood && other.code == code && other.name == name && other.per100g == per100g;

  @override
  int get hashCode => Object.hash(code, name);

  @override
  String toString() => 'BLSFood($code, $name)';
}

/// Bundeslebensmittelschlüssel 4.0 (Max Rubner-Institut, frei nutzbar laut Dokumentation, Abschnitt 9.3): rund
/// 7.000 Lebensmittel, offline in der App (`assets/bls.tsv`).
///
/// Regeln entscheiden, KI formuliert: Die KI zerlegt eine Mahlzeit nur in Lebensmittel und nennt je einen
/// Suchbegriff; die Nährwerte kommen aus dem BLS, wenn der Begriff eindeutig genug passt. Sonst bleibt die
/// KI-Schätzung (in der App als „geschätzt“ gekennzeichnet).
///
/// Anders als in Swift (Bundle-Ressource) lädt die App die Tabelle beim Start mit [load], weil `coach_core` keine
/// Flutter-Assets kennt. Ohne geladene Tabelle findet die Suche nichts und KI-Schätzungen bleiben stehen.
abstract final class BLS {
  /// Zitierweise laut BLS-Dokumentation (Abschnitt 9.2).
  static const attribution = 'Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0. Karlsruhe';
  static const sourceLabel = 'BLS 4.0 (Max Rubner-Institut)';

  static BLSTable _table = BLSTable(const []);

  /// Tabelle aus dem Text von `bls.tsv` laden (einmal beim Start).
  static void load(String tsv) => _table = BLSTable(parse(tsv));

  static List<BLSFood> get foods => _table.foods;

  static BLSFood? food(String code) {
    final index = _table.byCode[code];
    return index == null ? null : _table.foods[index];
  }

  /// Freie Suche wie in der Suchleiste: alle Wörter müssen vorkommen (Wortanfang), kurze Namen zuerst.
  static List<BLSFood> search(String query, {int limit = 20}) {
    final words = Tokens.words(query)
        .map((word) => word.text)
        .where((word) => !Tokens.stopwords.contains(word))
        .toList();
    if (words.isEmpty || words.join().length < 2) return const [];
    final scored = <(int, int)>[];
    for (var index = 0; index < _table.entries.length; index++) {
      final entry = _table.entries[index];
      final allFound = words.every(
        (word) => entry.tokens.any((token) => token.startsWith(word)) || entry.joined.contains(word),
      );
      if (!allFound) continue;
      final head = entry.tokens.isNotEmpty && Tokens.stem(entry.tokens.first) == Tokens.stem(words.first);
      final score = (head ? 0 : 100) + (_table.foods[index].isDish ? 20 : 0) + entry.tokens.length;
      scored.add((index, score));
    }
    mergeSort(
      scored,
      compare: (a, b) {
        final byScore = a.$2.compareTo(b.$2);
        if (byScore != 0) return byScore;
        return _table.foods[a.$1].name.length.compareTo(_table.foods[b.$1].name.length);
      },
    );
    return scored.take(limit).map((pair) => _table.foods[pair.$1]).toList();
  }

  /// Bestes BLS-Lebensmittel zu einem Suchbegriff der KI (z. B. „Hühnerei gekocht“) oder `null`, wenn keins sicher
  /// genug passt. Regeln:
  /// - Das erste Wort (Hauptwort) entspricht dem ersten Wort des BLS-Namens (bei „Karotte/Möhre“ einem davon), alle
  ///   weiteren Wörter kommen im Namen vor.
  /// - Sonderprodukte (glutenfrei, Pulver, Konserve, gesalzen …) und Zusätze nach „mit“ nur, wenn genannt.
  /// - Ein einzelnes Wort passt nur auf Grundeinträge („Apfel roh“), sonst höchstens ein weiteres Merkmal (plus
  ///   eins in Klammern). Unter den Treffern gewinnt der mit den wenigsten Zusätzen.
  static BLSFood? match(String term) {
    var words = Tokens.words(term).map((word) => word.text).where((word) => !Tokens.stopwords.contains(word)).toList();
    if (words.isNotEmpty) {
      final alias = Tokens.aliases[words.first];
      if (alias != null) words = [...alias, ...words.skip(1)];
    }
    if (words.isEmpty || words.first.length < 2) return null;
    final headWord = words.first;
    (int, int)? best;
    for (var index = 0; index < _table.entries.length; index++) {
      final entry = _table.entries[index];
      final used = Tokens.head(headWord, entry);
      if (used == null) continue;
      var matched = true;
      for (final word in words.skip(1)) {
        final hit = Tokens.find(word, entry.tokens, used);
        if (hit == null) {
          matched = false;
          break;
        }
        used.addAll(hit);
      }
      if (!matched) continue;
      final extras = Tokens.extras(entry, used, singleWord: words.length == 1);
      if (extras == null) continue;
      final fillers = entry.tokens.length - used.length - extras;
      final score = extras * 10 + fillers + (_table.foods[index].isDish ? 5 : 0);
      final current = best;
      if (current != null &&
          (score > current.$2 ||
              (score == current.$2 && _table.foods[index].name.length >= _table.foods[current.$1].name.length))) {
        continue;
      }
      best = (index, score);
    }
    return best == null ? null : _table.foods[best.$1];
  }

  /// Übernimmt die BLS-Nährwerte in eine Position; Werte, die im BLS fehlen, bleiben aus der alten Quelle (außer die
  /// Position kam schon aus dem BLS).
  static MealItem apply(BLSFood food, MealItem item) {
    // Wechsel zwischen BLS-Einträgen: keine Reste des vorigen Eintrags.
    final base = item.source == MealItemSource.bls ? <Nutrient, double>{} : Map.of(item.per100g.values);
    base.addAll(food.per100g.values);
    return item.copy()
      ..per100g = NutrientValues(base)
      ..source = MealItemSource.bls
      ..blsCode = food.code;
  }

  /// KI-Positionen mit passendem BLS-Lebensmittel bekommen dessen Nährwerte. Andere Quellen bleiben unverändert.
  static MealItem enrich(MealItem item) {
    if (item.source != MealItemSource.ai) return item;
    final term = [item.searchTerm, item.name].nonNulls.firstWhereOrNull((text) => text.isNotEmpty) ?? item.name;
    final food = match(term) ?? (term == item.name ? null : match(item.name));
    return food == null ? item : apply(food, item);
  }

  static bool isDrink(BLSFood food) {
    const drinkCodes = ['N', 'P']; // N = nichtalkoholische, P = alkoholische Getränke
    return drinkCodes.contains(food.code.isEmpty ? '' : food.code[0]) ||
        food.name.contains('Getränk') ||
        food.name.contains('drink') ||
        food.name.endsWith('saft');
  }

  /// Liest die Tabelle: Kommentarzeile, Kopfzeile mit Nährstoff-Schlüsseln, dann eine Zeile je Lebensmittel.
  static List<BLSFood> parse(String text) {
    final lines = text.split('\n').where((line) => line.isNotEmpty && !line.startsWith('#')).toList();
    if (lines.isEmpty) return const [];
    final header = lines.removeAt(0).split('\t');
    final nutrients = header.skip(2).map(Nutrient.fromRaw).toList();
    final foods = <BLSFood>[];
    for (final line in lines) {
      final fields = line.split('\t');
      if (fields.length < 2) continue;
      final values = <Nutrient, double>{};
      for (var offset = 0; offset < nutrients.length; offset++) {
        final nutrient = nutrients[offset];
        if (nutrient == null || offset + 2 >= fields.length) continue;
        final value = double.tryParse(fields[offset + 2]);
        if (value != null) values[nutrient] = value;
      }
      foods.add(BLSFood(code: fields[0], name: fields[1], per100g: NutrientValues(values)));
    }
    return foods;
  }
}

/// Vorbereitete Tabelle: Wörter je Name und Index nach Code.
final class BLSTable {
  BLSTable(this.foods)
    : entries = [
        for (final food in foods)
          () {
            final words = Tokens.words(food.name);
            final tokens = words.map((word) => word.text).toList();
            return BLSEntry(
              tokens: tokens,
              inParens: words.map((word) => word.inParens).toList(),
              joined: tokens.join(),
            );
          }(),
      ],
      byCode = {} {
    for (var index = 0; index < foods.length; index++) {
      byCode.putIfAbsent(foods[index].code, () => index);
    }
  }

  final List<BLSFood> foods;
  final List<BLSEntry> entries;
  final Map<String, int> byCode;
}

final class BLSEntry {
  const BLSEntry({required this.tokens, required this.inParens, required this.joined});

  final List<String> tokens;

  /// Wort steht in Klammern (Erläuterung wie „(Getränk)“).
  final List<bool> inParens;
  final String joined;
}

final class TokenWord {
  const TokenWord(this.text, {this.inParens = false});

  final String text;
  final bool inParens;
}

/// Wortzerlegung für BLS-Namen und Suchbegriffe: Kleinbuchstaben, Umlaute ausgeschrieben, Dezimalkomma als Punkt.
abstract final class Tokens {
  /// Steht zwischen erstem und zweitem Wort, wenn der BLS-Name Alternativen nennt („Karotte/Möhre“).
  static const alternative = '/';
  static const stopwords = {'mit', 'und', 'der', 'die', 'das', 'von', 'vom', 'zum', 'zur', 'ca'};

  /// Zusätze, die die Nährwerte kaum ändern oder Standard sind (zählen nicht als Merkmal).
  static const fillers = {
    'roh', 'frisch', 'pasteurisiert', 'mind', 'max', 'fett', 'i', 'tr', 'bis', 'getraenk', 'ungesuesst', 'natur', //
    'zubereitet', 'verzehrfertig', 'suess', 'reif', 'ganz', 'geschaelt', 'geroestet', 'mild', 'gesaeuert',
  };

  /// Sonderprodukte: nur, wenn der Suchbegriff sie nennt.
  static const markers = {
    'glutenfrei', 'laktosefrei', 'kohlenhydratreduziert', 'energiereduziert', 'riegel', 'misch', 'einlauf', //
    'suppeneinlage', 'pulver', 'instantpulver', 'getrocknet', 'konserve', 'angereichert', 'trockenprodukt', //
    'gesalzen', 'gesuesst', 'alkoholfrei', 'entkoffeiniert', 'koffeinreduziert',
  };

  /// Alltagswörter, die im BLS anders heißen.
  static const aliases = {
    'ei': ['huehnerei'],
    'eier': ['huehnerei'],
    'nudeln': ['teigwaren', 'eifrei'],
    'spaghetti': ['teigwaren', 'eifrei'],
    'pasta': ['teigwaren', 'eifrei'],
    'brokkoli': ['broccoli'],
    'ketchup': ['tomatenketchup'],
  };

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _number = RegExp(r'\p{N}', unicode: true);

  static bool _isLetter(String char) => _letter.hasMatch(char);
  static bool _isNumber(String char) => _number.hasMatch(char);

  static bool isFiller(String token) =>
      token == 'mit' || fillers.contains(token) || token.split('').every((char) => _isNumber(char) || char == '.');

  static List<TokenWord> words(String text) {
    final characters = FoodSearch.normalized(text).split('');
    final words = <TokenWord>[];
    final current = StringBuffer();
    var depth = 0;
    void flush() {
      if (current.isNotEmpty) words.add(TokenWord(current.toString(), inParens: depth > 0));
      current.clear();
    }

    for (var index = 0; index < characters.length; index++) {
      final character = characters[index];
      if (character == ',' &&
          index > 0 &&
          index + 1 < characters.length &&
          _isNumber(characters[index - 1]) &&
          _isNumber(characters[index + 1])) {
        current.write('.');
        continue;
      }
      if (_isLetter(character) || _isNumber(character)) {
        current.write(character);
        continue;
      }
      flush();
      if (character == '/' && depth == 0 && words.length == 1) words.add(const TokenWord(alternative));
      if (character == '(') depth += 1;
      if (character == ')') depth = depth > 0 ? depth - 1 : 0;
    }
    flush();
    return words;
  }

  /// Einfache Grundform für Mehrzahl und Beugung („Kartoffeln“ = „Kartoffel“, „Erdnüsse“ = „Erdnuss“).
  static String stem(String word) {
    var result = word.replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
    if (result.length > 4) {
      final suffix = ['en', 'n', 'e'].firstWhereOrNull(result.endsWith);
      if (suffix != null) result = result.substring(0, result.length - suffix.length);
    }
    if (result.length > 4 && result.endsWith('s') && !result.endsWith('ss')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// Wie viele Namenswörter ab [start] dem Wort entsprechen: eins bei gleichem Wort, mehrere bei getrennt
  /// geschriebenen Zusammensetzungen („Haferflocken“ = „Hafer Flocken“). `exact: false` erlaubt Wortanfänge.
  static int? matchLength(String word, List<String> tokens, int start, {required bool exact}) {
    if (start >= tokens.length) return null;
    final target = stem(word);
    if (stem(tokens[start]) == target || (!exact && word.length >= 4 && tokens[start].startsWith(word))) return 1;
    var joined = tokens[start];
    final limit = start + 3 < tokens.length ? start + 3 : tokens.length;
    for (var end = start + 1; end < limit; end++) {
      if (tokens[end] == alternative) continue;
      joined += tokens[end];
      if (stem(joined) == target) return end - start + 1;
    }
    return null;
  }

  /// Verbrauchte Namenswörter für das Hauptwort (bei Alternativen samt Schrägstrich und zweitem Namen).
  static Set<int>? head(String word, BLSEntry entry) {
    final tokens = entry.tokens;
    final hasAlternative = tokens.length > 2 && tokens[1] == alternative;
    final length = matchLength(word, tokens, 0, exact: true);
    if (length != null) {
      return {
        for (var index = 0; index < length; index++) index,
        if (hasAlternative) ...[1, 2],
      };
    }
    if (hasAlternative) {
      final second = matchLength(word, tokens, 2, exact: true);
      if (second != null) return {for (var index = 0; index < 2 + second; index++) index};
    }
    return null;
  }

  /// Fundstelle eines Worts irgendwo im Namen (ohne schon verbrauchte Wörter).
  static Set<int>? find(String word, List<String> tokens, Set<int> used) {
    for (var start = 0; start < tokens.length; start++) {
      if (used.contains(start)) continue;
      final length = matchLength(word, tokens, start, exact: false);
      if (length == null) continue;
      final range = {for (var index = start; index < start + length; index++) index};
      if (range.intersection(used).isEmpty) return range;
    }
    return null;
  }

  /// Zahl der echten Zusatzmerkmale im BLS-Namen oder `null`, wenn der Eintrag nicht passen darf.
  static int? extras(BLSEntry entry, Set<int> used, {required bool singleWord}) {
    final rest = [
      for (var index = 0; index < entry.tokens.length; index++)
        if (!used.contains(index)) index,
    ];
    if (rest.any((index) => markers.contains(entry.tokens[index]))) return null;
    // „Bier mit Sekt“: alles nach „mit“ (außerhalb von Klammern) muss im Suchbegriff stehen.
    final withIndex = rest.firstWhereOrNull((index) => entry.tokens[index] == 'mit' && !entry.inParens[index]);
    if (withIndex != null &&
        rest.any((index) => index > withIndex && !entry.inParens[index] && !isFiller(entry.tokens[index]))) {
      return null;
    }
    final plain = rest.where((index) => !entry.inParens[index] && !isFiller(entry.tokens[index])).length;
    final inParens = rest.where((index) => entry.inParens[index] && !isFiller(entry.tokens[index])).length;
    if (singleWord && plain + inParens > 0) return null;
    if (plain > 1 || plain + inParens > 2) return null;
    return plain + inParens;
  }
}

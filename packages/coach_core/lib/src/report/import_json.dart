import 'dart:convert';

/// Toleranter Leser für Antworten externer KIs (Claude, ChatGPT, Gemini): Die Modelle halten sich nicht immer genau
/// an das Format. Hier wird nachsichtig gelesen – was die Regeln danach übernehmen, entscheidet weiterhin
/// `CoachImport`/`GymCoach.validatePlan`.
///
/// - Codeblöcke mit ``` oder ~~~, mit oder ohne Sprache, auch auf einer Zeile; sonst die ganze Antwort bzw. das
///   größte `{…}` darin.
/// - JSON mit Kommentaren (`//`, `/* */`), Kommas vor `}`/`]` und typografischen Anführungszeichen („“ ” “).
/// - Schlüssel auf Deutsch oder Englisch, mit oder ohne Umlaute (`routines`, `übungen`, `sets`, `reps: "8-10"` …).
abstract final class ImportJson {
  /// Schlüssel, an denen ein Block als Antwort für die App erkannt wird (nach [normalize]).
  static const knownKeys = {'routinen', 'wochenplan', 'hinweise', 'empfehlungen', 'verwerfen'};

  /// Kandidaten in Reihenfolge: ironludi-Blöcke, andere Blöcke, ganzer Text, größtes Objekt im Text.
  static List<({String tag, String body})> candidates(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    final blocks = <({String tag, String body})>[];
    final fence = RegExp(r'(```+|~~~+)[ \t]*([A-Za-z0-9_+-]*)[ \t]*\n?([\s\S]*?)\1', multiLine: true);
    for (final match in fence.allMatches(normalized)) {
      blocks.add((tag: match.group(2)!.toLowerCase(), body: match.group(3)!));
    }
    blocks.sort((a, b) => (a.tag == 'ironludi' ? 0 : 1).compareTo(b.tag == 'ironludi' ? 0 : 1));
    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    return [
      ...blocks,
      (tag: '', body: normalized),
      if (start >= 0 && end > start) (tag: '', body: normalized.substring(start, end + 1)),
    ];
  }

  /// JSON nachsichtig lesen; `null`, wenn es auch so nicht geht.
  static Object? parse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    for (final variant in [trimmed, _repair(trimmed)]) {
      try {
        return jsonDecode(variant);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// Typografische Anführungszeichen, Kommentare und überzählige Kommas außerhalb von Zeichenketten entfernen.
  static String _repair(String text) {
    final quoted = text.replaceAll(RegExp('[„“”″]'), '"').replaceAll(RegExp('[‚‘’]'), "'").replaceAll(' ', ' ');
    final buffer = StringBuffer();
    var inString = false;
    var index = 0;
    while (index < quoted.length) {
      final char = quoted[index];
      if (inString) {
        buffer.write(char);
        if (char == r'\' && index + 1 < quoted.length) {
          buffer.write(quoted[index + 1]);
          index += 2;
          continue;
        }
        if (char == '"') inString = false;
        index += 1;
        continue;
      }
      if (char == '"') {
        inString = true;
        buffer.write(char);
        index += 1;
        continue;
      }
      if (quoted.startsWith('//', index)) {
        final lineEnd = quoted.indexOf('\n', index);
        index = lineEnd < 0 ? quoted.length : lineEnd;
        continue;
      }
      if (quoted.startsWith('/*', index)) {
        final close = quoted.indexOf('*/', index + 2);
        index = close < 0 ? quoted.length : close + 2;
        continue;
      }
      if (char == ',') {
        var next = index + 1;
        while (next < quoted.length && ' \t\n'.contains(quoted[next])) {
          next += 1;
        }
        if (next < quoted.length && (quoted[next] == '}' || quoted[next] == ']')) {
          index += 1;
          continue;
        }
      }
      buffer.write(char);
      index += 1;
    }
    return buffer.toString();
  }

  static String _key(String key) => key
      .trim()
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[\s-]+'), '_');

  /// Synonyme → Schlüssel des App-Formats.
  static const aliases = <String, String>{
    'routines': 'routinen',
    'routine': 'routinen',
    'trainingsplaene': 'routinen',
    'trainingsplan': 'routinen',
    'plaene': 'routinen',
    'workouts': 'routinen',
    'einheiten': 'routinen',
    'list': 'liste',
    'items': 'liste',
    'mode': 'modus',
    'exercises': 'uebungen',
    'uebung': 'uebungen',
    'sets': 'saetze',
    'satz': 'saetze',
    'reps_min': 'wdh_min',
    'min_reps': 'wdh_min',
    'wiederholungen_min': 'wdh_min',
    'wdh_von': 'wdh_min',
    'reps_max': 'wdh_max',
    'max_reps': 'wdh_max',
    'wiederholungen_max': 'wdh_max',
    'wdh_bis': 'wdh_max',
    'reps': 'wdh',
    'wiederholungen': 'wdh',
    'rest': 'pause',
    'rest_seconds': 'pause',
    'pause_s': 'pause',
    'pause_sek': 'pause',
    'pause_sekunden': 'pause',
    'weight': 'gewicht',
    'weight_kg': 'gewicht',
    'gewicht_kg': 'gewicht',
    'title': 'titel',
    'weekly_plan': 'wochenplan',
    'week_plan': 'wochenplan',
    'weekplan': 'wochenplan',
    'woche': 'wochenplan',
    'days': 'tage',
    'applies_to': 'gilt_fuer',
    'scope': 'gilt_fuer',
    'intensity': 'intensitaet',
    'notes': 'hinweise',
    'hints': 'hinweise',
    'tips': 'hinweise',
    'tipps': 'hinweise',
    'recommendations': 'empfehlungen',
    'dismiss': 'verwerfen',
    'model': 'modell',
    'monday': 'mo',
    'montag': 'mo',
    'tuesday': 'di',
    'dienstag': 'di',
    'wednesday': 'mi',
    'mittwoch': 'mi',
    'thursday': 'do',
    'donnerstag': 'do',
    'friday': 'fr',
    'freitag': 'fr',
    'saturday': 'sa',
    'samstag': 'sa',
    'sunday': 'so',
    'sonntag': 'so',
  };

  /// Schlüssel vereinheitlichen (rekursiv) und Kurzformen ausschreiben: `"wdh": "8-10"` → `wdh_min`/`wdh_max`,
  /// Übungen als Text (`"Bankdrücken"`) → `{"name": …}`.
  static Object? normalize(Object? value) {
    if (value is List) return [for (final item in value) normalize(item)];
    if (value is! Map) return value;
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final raw = _key('${entry.key}');
      final key = aliases[raw] ?? raw;
      var child = normalize(entry.value);
      if (key == 'uebungen' && child is List) {
        child = [
          for (final item in child) item is String ? {'name': item} : item,
        ];
      }
      result.putIfAbsent(key, () => child);
    }
    if (result.remove('wdh') case final reps?) {
      final range = _range(reps);
      if (range != null) {
        result.putIfAbsent('wdh_min', () => range.$1);
        result.putIfAbsent('wdh_max', () => range.$2);
      }
    }
    for (final key in ['saetze', 'pause', 'gewicht', 'wdh_min', 'wdh_max']) {
      if (result[key] case final String text) result[key] = _number(text) ?? text;
    }
    return result;
  }

  static num? _number(String text) {
    final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(text);
    return match == null ? null : num.tryParse(match.group(0)!.replaceAll(',', '.'));
  }

  /// „8-10“, „8–10“, „8 bis 10“, 10, „10“ → (min, max).
  static (num, num)? _range(Object? value) {
    if (value is num) return (value, value);
    if (value is! String) return null;
    final numbers = RegExp(r'\d+').allMatches(value).map((match) => int.parse(match.group(0)!)).toList();
    if (numbers.isEmpty) return null;
    return (numbers.first, numbers.length > 1 ? numbers[1] : numbers.first);
  }

  /// Erstes Objekt mit bekannten Schlüsseln (nach [normalize]); `null`, wenn keins passt. [invalidTagged]: ein
  /// ironludi-Block war da, aber nicht lesbar.
  static ({Map<String, Object?>? json, bool invalidTagged}) find(String text) {
    var invalidTagged = false;
    for (final candidate in candidates(text)) {
      final parsed = parse(candidate.body);
      if (parsed == null) {
        if (candidate.tag == 'ironludi') invalidTagged = true;
        continue;
      }
      final normalized = normalize(parsed);
      // Nur eine Liste von Routinen (ohne Hülle) zählt auch.
      if (normalized is List &&
          normalized.isNotEmpty &&
          normalized.every((item) => item is Map && item['uebungen'] != null)) {
        return (json: {'routinen': normalized}, invalidTagged: false);
      }
      if (normalized is Map<String, Object?> && normalized.keys.any(knownKeys.contains)) {
        return (json: normalized, invalidTagged: false);
      }
    }
    return (json: null, invalidTagged: invalidTagged);
  }
}

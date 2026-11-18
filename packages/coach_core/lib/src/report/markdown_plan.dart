import '../nutrition/food_search.dart';

/// Wochenplan als Markdown-Tabelle (so geben Claude und ChatGPT Pläne gern aus, auch als .md-Datei):
///
/// ```text
/// ## Diese Woche
/// | Tag | Einheit | Hinweis |
/// |---|---|---|
/// | Mittwoch | Lockeres Schwimmen, 45 min | Nur Technik |
/// ```
///
/// Wird in das App-Format übersetzt (`wochenplan`, `diese_woche`, `hinweise`); welche Einheiten daraus werden,
/// entscheidet danach `CoachImport` mit denselben Regeln wie beim JSON-Block.
abstract final class MarkdownPlan {
  static const _days = {
    'mo': 'mo', 'montag': 'mo', 'monday': 'mo', 'mon': 'mo', //
    'di': 'di', 'dienstag': 'di', 'tuesday': 'di', 'tue': 'di',
    'mi': 'mi', 'mittwoch': 'mi', 'wednesday': 'mi', 'wed': 'mi',
    'do': 'do', 'donnerstag': 'do', 'thursday': 'do', 'thu': 'do',
    'fr': 'fr', 'freitag': 'fr', 'friday': 'fr', 'fri': 'fr',
    'sa': 'sa', 'samstag': 'sa', 'saturday': 'sa', 'sat': 'sa',
    'so': 'so', 'sonntag': 'so', 'sunday': 'so', 'sun': 'so',
  };

  static const _dayNames = {
    'mo': 'Montag',
    'di': 'Dienstag',
    'mi': 'Mittwoch',
    'do': 'Donnerstag',
    'fr': 'Freitag',
    'sa': 'Samstag',
    'so': 'Sonntag',
  };

  static String _plain(String text) => FoodSearch.normalized(text).replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

  /// Wochentag am Anfang einer Zelle („Mittwoch“, „Mi 18.11.“, „**Montag**“); sonst `null`.
  static String? day(String cell) {
    final words = _plain(cell).split(' ');
    return words.isEmpty ? null : _days[words.first];
  }

  static List<String> _cells(String line) {
    var row = line.trim();
    if (row.startsWith('|')) row = row.substring(1);
    if (row.endsWith('|')) row = row.substring(0, row.length - 1);
    return [for (final cell in row.split('|')) cell.replaceAll(RegExp(r'[*_`]'), '').trim()];
  }

  static bool _isSeparator(String line) => RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$').hasMatch(line.trim());

  static bool _empty(String text) => RegExp(r'^[\s\-–—/.]*$').hasMatch(text);

  /// Gültigkeit aus der Überschrift über der Tabelle.
  static String _scope(String heading) {
    final value = _plain(heading);
    if (RegExp(r'\b(diese|aktuelle|laufende) woche\b|\bthis week\b|\bcurrent week\b').hasMatch(value)) {
      return 'diese_woche';
    }
    if (RegExp(r'\bnaechste woche\b|\bnext week\b|\bkommende woche\b').hasMatch(value)) return 'naechste_woche';
    return 'dauerhaft';
  }

  /// App-Format oder `null`, wenn keine Tabelle mit Wochentagen im Text steht.
  static Map<String, Object?>? parse(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final tables = <({String scope, String label, Map<String, String> days, List<String> hints})>[];
    final paragraphs = <String>[];
    var heading = '';
    var index = 0;
    while (index < lines.length) {
      final line = lines[index].trim();
      if (line.startsWith('|') && index + 1 < lines.length && _isSeparator(lines[index + 1])) {
        final header = [for (final cell in _cells(line)) _plain(cell)];
        int column(List<String> words, int fallback) {
          final found = header.indexWhere((cell) => words.any(cell.contains));
          return found < 0 ? fallback : found;
        }

        final dayColumn = column(['tag', 'day'], 0);
        final unitColumn = column(['einheit', 'training', 'workout', 'session', 'programm', 'sport', 'plan'], 1);
        final hintColumn = column(['hinweis', 'notiz', 'details', 'bemerkung', 'note', 'fokus', 'ziel'], -1);
        final days = <String, String>{};
        final hints = <String>[];
        index += 2;
        while (index < lines.length && lines[index].trim().startsWith('|')) {
          final cells = _cells(lines[index]);
          index += 1;
          if (dayColumn >= cells.length) continue;
          final key = day(cells[dayColumn]);
          if (key == null) continue;
          final unit = unitColumn < cells.length ? cells[unitColumn] : '';
          final hint = hintColumn >= 0 && hintColumn < cells.length ? cells[hintColumn] : '';
          final restHint = RegExp(r'^(frei|ruhe|ruhetag|rest|off)\b').hasMatch(_plain(hint));
          // Mehrere Zeilen für denselben Tag: Einheiten zusammenfassen.
          final value = _empty(unit) || restHint ? 'frei' : unit;
          days[key] = days.containsKey(key) && days[key] != 'frei' && value != 'frei' ? '${days[key]} + $value' : value;
          if (!_empty(hint) && !restHint) hints.add('${_dayNames[key]}: $hint');
        }
        if (days.isNotEmpty) tables.add((scope: _scope(heading), label: heading, days: days, hints: hints));
        continue;
      }
      if (line.startsWith('#')) {
        heading = line.replaceFirst(RegExp('^#+'), '').trim();
      } else if (RegExp(r'^\*\*[^*]+\*\*:?$').hasMatch(line)) {
        heading = line.replaceAll('*', '').trim();
      } else if (line.isNotEmpty && !line.startsWith('|') && !line.startsWith('```')) {
        paragraphs.add(line.replaceFirst(RegExp(r'^[-*•]\s+'), '').replaceAll('**', ''));
      }
      index += 1;
    }
    if (tables.isEmpty) return null;

    final permanent = tables.where((table) => table.scope != 'diese_woche').firstOrNull;
    final thisWeek = tables.where((table) => table.scope == 'diese_woche').firstOrNull;
    return {
      if (permanent != null) 'wochenplan': {'gilt_fuer': permanent.scope, 'tage': permanent.days},
      if (thisWeek != null) 'diese_woche': {'tage': thisWeek.days},
      'hinweise': [
        ...paragraphs,
        if (thisWeek != null) ...thisWeek.hints.map((hint) => 'Diese Woche, $hint'),
        ...?permanent?.hints,
      ],
    };
  }
}

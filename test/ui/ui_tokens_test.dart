// Designsystem (Roast B-05): In `lib/features` keine rohen Farben (`Colors.*` außer `transparent`, `Color(0x…)`) und
// keine festen Schriftgrößen (`fontSize: <Zahl>`). Stattdessen `AppColors`, `AppPalette`, `AppText` und
// `LiquidText`/`LiquidSpacing` (lib/ui/tokens.dart, lib/ui/liquid.dart). Bis 25.11.2026 war das eine Sperrklinke mit
// Bestandsliste; seit dem Abbau des Bestands gilt die Regel ohne Ausnahme außer den unten begründeten Dateien.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _patterns = {
  'Farbe': RegExp(r'\bColors\.(?!transparent\b)[a-zA-Z]+'),
  'Hex-Farbe': RegExp(r'\bColor\(0x'),
  'Schriftgröße': RegExp(r'fontSize:\s*[0-9]'),
};

/// Dateien, in denen feste Werte gewollt sind.
const _allowed = {
  // Illustration des Begleiters: eigene Farben und mit der Animation wachsende Schrift.
  'lib/features/motivation/daisy_avatar.dart',
  // Vorschau des Sperrbildschirms: bildet die immer dunklen iOS-Karten in festen Größen nach.
  'lib/features/settings/lock_screen_settings.dart',
};

void main() {
  test('keine rohen Farben und festen Schriftgrößen in lib/features', () {
    final found = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final path = p.posix.joinAll(p.split(p.normalize(file.path)));
      if (_allowed.contains(path)) continue;
      for (final (index, line) in file.readAsLinesSync().indexed) {
        for (final MapEntry(key: kind, value: pattern) in _patterns.entries) {
          if (pattern.hasMatch(line)) found.add('$path:${index + 1}: $kind – ${line.trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: 'Bitte AppColors, AppPalette, AppText oder LiquidText aus lib/ui nutzen.');
  });

  test('Ausnahmen gibt es noch', () {
    for (final path in _allowed) {
      expect(File(path).existsSync(), isTrue, reason: '$path aus der Ausnahmeliste entfernen');
    }
  });
}

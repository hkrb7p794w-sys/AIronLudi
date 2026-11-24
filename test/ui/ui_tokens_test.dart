// Designsystem als Sperrklinke (Roast B-05): In `lib/features` dürfen rohe Farben (`Colors.*` außer `transparent`,
// `Color(0x…)`) und feste Schriftgrößen (`fontSize: <Zahl>`) nicht mehr werden – nur weniger. Stattdessen
// `AppColors`, `AppText`, `LiquidSpacing` (lib/ui/tokens.dart, lib/ui/liquid.dart).
//
// Nach dem Umstellen einer Datei den Bestand neu schreiben:
//   flutter test test/ui/ui_tokens_test.dart --dart-define=UPDATE_TOKEN_BASELINE=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _update = bool.fromEnvironment('UPDATE_TOKEN_BASELINE');
const _baselinePath = 'test/ui/ui_tokens_baseline.json';

final _patterns = {
  'colors': RegExp(r'\bColors\.(?!transparent\b)[a-zA-Z]+'),
  'hex': RegExp(r'\bColor\(0x'),
  'fontSize': RegExp(r'fontSize:\s*[0-9]'),
};

Map<String, Map<String, int>> _count() {
  final result = <String, Map<String, int>>{};
  final files = Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final text = file.readAsStringSync();
    final counts = {for (final entry in _patterns.entries) entry.key: entry.value.allMatches(text).length};
    if (counts.values.any((n) => n > 0)) result[p.posix.joinAll(p.split(p.normalize(file.path)))] = counts;
  }
  return Map.fromEntries(result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

void main() {
  test('Rohwerte in lib/features werden nicht mehr (Bestand: $_baselinePath)', () {
    final current = _count();
    if (_update) {
      File(_baselinePath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(current)}\n');
      return;
    }
    final baseline = (jsonDecode(File(_baselinePath).readAsStringSync()) as Map<String, Object?>).map(
      (file, counts) => MapEntry(file, (counts! as Map<String, Object?>).map((k, v) => MapEntry(k, v! as int))),
    );
    final more = <String>[];
    final fewer = <String>[];
    for (final file in {...current.keys, ...baseline.keys}) {
      for (final kind in _patterns.keys) {
        final now = current[file]?[kind] ?? 0;
        final before = baseline[file]?[kind] ?? 0;
        if (now > before) more.add('$file: $kind $before → $now');
        if (now < before) fewer.add('$file: $kind $before → $now');
      }
    }
    expect(
      more,
      isEmpty,
      reason: 'Neue Rohwerte – bitte AppColors/AppText/LiquidSpacing aus lib/ui/tokens.dart nutzen.',
    );
    expect(
      fewer,
      isEmpty,
      reason:
          'Weniger Rohwerte als im Bestand – gut! Bitte den Bestand neu schreiben: '
          'flutter test test/ui/ui_tokens_test.dart --dart-define=UPDATE_TOKEN_BASELINE=true',
    );
  });

  test('Summe der Rohwerte (nur zur Übersicht)', () {
    final totals = <String, int>{};
    for (final counts in _count().values) {
      counts.forEach((kind, n) => totals[kind] = (totals[kind] ?? 0) + n);
    }
    // Stand beim Einführen (24.11.2026): 473 Farben, 56 Hex-Werte, 279 Schriftgrößen in 70 Dateien.
    expect(totals.keys, containsAll(_patterns.keys));
  });
}

// Exporte (KI, Routen) im Temp-Ordner des Geräts: frischer Ordner je Export, beim Benutzerwechsel geleert
// (Roast B-23).
import 'dart:io';

import 'package:aironludi/services/share/export_folders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('exporte'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('frischer Ordner ersetzt den alten Export', () async {
    final first = await ExportFolders.fresh(ExportFolders.aiExport, temp: () async => temp);
    File(p.join(first.path, 'alt.md')).writeAsStringSync('alt');
    final second = await ExportFolders.fresh(ExportFolders.aiExport, temp: () async => temp);
    expect(second.path, first.path);
    expect(second.listSync(), isEmpty);
  });

  test('Benutzerwechsel: alle Export-Ordner weg, anderes im Temp-Ordner bleibt', () async {
    for (final name in ExportFolders.all) {
      final folder = await ExportFolders.fresh(name, temp: () async => temp);
      File(p.join(folder.path, 'export')).writeAsStringSync('Daten von A');
    }
    final other = File(p.join(temp.path, 'anderes.txt'))..writeAsStringSync('bleibt');
    await clearSharedExports(temp: () async => temp);
    for (final name in ExportFolders.all) {
      expect(Directory(p.join(temp.path, name)).existsSync(), isFalse, reason: name);
    }
    expect(other.existsSync(), isTrue);
  });
}

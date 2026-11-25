import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Temporäre Ordner für Dateien, die über das Teilen-Menü das Gerät verlassen (KI-Export, Routen als GPX/FIT). Sie
/// liegen im Temp-Ordner des Geräts, nicht des Benutzers; deshalb leert der Benutzerwechsel sie
/// ([clearSharedExports]), damit kein Export eines Benutzers für den nächsten liegen bleibt.
abstract final class ExportFolders {
  static const aiExport = 'ki-export';
  static const routeExport = 'routen-export';

  /// Datensicherung zum Teilen (enthält alle Daten des Benutzers).
  static const backupExport = 'sicherung-export';
  static const all = [aiExport, routeExport, backupExport];

  /// Leerer Ordner [name] im Temp-Ordner (ein alter Export wird ersetzt).
  static Future<Directory> fresh(String name, {Future<Directory> Function()? temp}) async {
    final folder = Directory(p.join((await (temp ?? getTemporaryDirectory)()).path, name));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    return folder..createSync(recursive: true);
  }
}

/// Alle Export-Ordner löschen (beim Benutzerwechsel).
Future<void> clearSharedExports({Future<Directory> Function()? temp}) async {
  final root = (await (temp ?? getTemporaryDirectory)()).path;
  for (final name in ExportFolders.all) {
    final folder = Directory(p.join(root, name));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  }
}

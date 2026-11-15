import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;

import '../secure/secret_store.dart';

/// Wo der Speicher eines Benutzers liegt. Alles, was einem Benutzer gehört, wird ausschließlich hierüber gefunden:
/// Datenbankdatei, Schlüssel im sicheren Speicher, App-Support- und Cache-Ordner. Der ursprüngliche Benutzer
/// ([UserDirectory.legacyID]) behält die Stellen von vor der Mehrbenutzer-Version (Datenbank `coach`, Schlüssel ohne
/// Präfix, Ordner direkt im App-Support) – so geht beim Update nichts verloren und nichts muss verschoben werden.
/// Weitere Benutzer liegen unter `users/<id>/`, ihre Datenbank heißt `coach-<id>`, ihre Schlüssel `u.<id>.<name>`.
final class UserLocation {
  const UserLocation(this.user);

  final LocalUser user;

  static const usersFolder = 'users';

  String get databaseName => user.isLegacy ? 'coach' : 'coach-${user.id}';

  String get secretPrefix => user.isLegacy ? '' : 'u.${user.id}.';

  /// App-Support-Ordner des Benutzers innerhalb von [root] (`null` ohne Ordner, z. B. in Tests).
  String? support(String? root) => root == null ? null : (user.isLegacy ? root : p.join(root, usersFolder, user.id));

  String? cache(String? root) => root == null ? null : (user.isLegacy ? root : p.join(root, usersFolder, user.id));

  /// Datenbankdatei samt Journal in [documents] (drift legt `<name>.sqlite` im Dokumente-Ordner an).
  List<File> databaseFiles(String documents) => [
    for (final suffix in const ['.sqlite', '.sqlite-wal', '.sqlite-shm', '.sqlite-journal'])
      File(p.join(documents, '$databaseName$suffix')),
  ];
}

/// Verzeichnis der Benutzer als Datei `users.json` im App-Support-Ordner (gehört dem Gerät, keinem Benutzer).
final class UserDirectoryStore {
  UserDirectoryStore(this.root);

  /// App-Support-Ordner; `null` in Tests (dann nur im Arbeitsspeicher).
  final String? root;

  File? get _file => root == null ? null : File(p.join(root!, UserDirectory.fileName));

  /// Ohne Datei: der vorhandene Speicher gehört dem ursprünglichen Benutzer.
  Future<UserDirectory> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return UserDirectory.initial();
    try {
      return UserDirectory.fromJson(jsonDecode(await file.readAsString())) ?? UserDirectory.initial();
    } on Object {
      return UserDirectory.initial();
    }
  }

  /// Erst schreiben, dann umbenennen: nie eine halbe Datei.
  Future<void> save(UserDirectory directory) async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(directory.toJson()), flush: true);
    await temp.rename(file.path);
  }
}

/// Löscht den gesamten Speicher eines (nicht aktiven, nicht ursprünglichen) Benutzers: Datenbank, Ordner, Geheimnisse.
Future<void> deleteUserStorage(
  UserLocation location, {
  required String? documents,
  required String? support,
  required String? cache,
  required SecretStore Function(String prefix) secrets,
}) async {
  if (location.user.isLegacy) throw StateError('Der ursprüngliche Benutzer wird nicht gelöscht.');
  if (documents != null) {
    for (final file in location.databaseFiles(documents)) {
      if (file.existsSync()) await file.delete();
    }
  }
  for (final folder in {location.support(support), location.cache(cache)}) {
    if (folder != null && Directory(folder).existsSync()) await Directory(folder).delete(recursive: true);
  }
  final store = secrets(location.secretPrefix);
  for (final key in SecretKey.values) {
    await store.write(key, null);
  }
}

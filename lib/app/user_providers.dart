import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'user_session.dart';

export '../data/users/current_user.dart';

/// Verwaltung der Benutzer des Geräts (anlegen, wechseln, löschen); `null` in Tests ohne Sitzung.
final userSessionProvider = Provider<UserSession?>((ref) => null);

/// App-Support-Ordner des aktiven Benutzers (`UserLocation.support`); `null` in Tests.
final userFolderProvider = Provider<String?>((ref) => null);

/// Ordner für Dateien des Benutzers (Rezepte, Kochplan, Begleiter-Foto). Ohne gesetzten Ordner (Tests) wie bisher der
/// App-Support-Ordner.
final userDirectoryProvider = Provider<Future<Directory> Function()>((ref) {
  final folder = ref.watch(userFolderProvider);
  if (folder == null) return getApplicationSupportDirectory;
  return () async => Directory(folder);
});

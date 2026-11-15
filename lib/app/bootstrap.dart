import 'dart:async';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/settings/preferences.dart';
import '../data/storage.dart';
import '../data/users/user_storage.dart';
import '../platform/notifications.dart';
import '../services/providers.dart';
import 'user_providers.dart';
import 'user_session.dart';

/// Ordner des Geräts (nicht des Benutzers); `null`, wenn es keinen gibt.
typedef DeviceFolders = ({String? documents, String? support, String? cache});

Future<DeviceFolders> deviceFolders() async {
  Future<String?> path(Future<Directory> Function() resolve) =>
      resolve().then<String?>((dir) => dir.path, onError: (Object _) => null);
  return (
    documents: await path(getApplicationDocumentsDirectory),
    support: await path(getApplicationSupportDirectory),
    cache: await path(getApplicationCacheDirectory),
  );
}

/// Aktiver Benutzer laut `users.json` (Hintergrundabruf, Start).
Future<LocalUser> activeUser({DeviceFolders? folders}) async {
  final resolved = folders ?? await deviceFolders();
  return (await UserDirectoryStore(resolved.support).load()).active;
}

/// Gemeinsamer Start von App und Hintergrundabruf: Einstellungen, Speicher des Benutzers, Saisonplan und Ordner öffnen
/// und den Provider-Container damit füllen. Jeder Benutzer bekommt einen eigenen Container mit eigener Datenbank,
/// eigenen Geheimnissen und eigenen Ordnern – nichts davon ist zwischen Benutzern geteilt.
Future<ProviderContainer> createAppContainer({
  NotificationCenterBridge? notificationCenter,
  LocalUser? user,
  UserSession? session,
}) async {
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  // Lebensmitteltabelle im Hintergrund laden; bis dahin bleiben KI-Schätzungen stehen (wie ohne Treffer). Sie ist für
  // alle gleich (mitgelieferte Daten, keine Nutzerdaten).
  if (BLS.foods.isEmpty) unawaited(rootBundle.loadString('packages/coach_core/assets/bls.tsv').then(BLS.load));
  final folders = await deviceFolders();
  final owner = user ?? await activeUser(folders: folders);
  final location = UserLocation(owner);
  final storage = await AppStorage.open(location: location);
  final season = await rootBundle
      .loadString('packages/coach_core/assets/season-plan.json')
      .then<SeasonSchedule?>(SeasonSchedule.load, onError: (Object _) => null);
  return ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      appStorageProvider.overrideWithValue(storage),
      currentUserProvider.overrideWithValue(owner),
      userSessionProvider.overrideWithValue(session),
      userFolderProvider.overrideWithValue(location.support(folders.support)),
      activityFoldersProvider.overrideWithValue((
        support: location.support(folders.support),
        cache: location.cache(folders.cache),
      )),
      seasonScheduleProvider.overrideWithValue(season),
      notificationCenterProvider.overrideWithValue(notificationCenter),
    ],
  );
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/settings/preferences.dart';
import '../data/storage.dart';
import '../platform/notifications.dart';
import '../services/providers.dart';

/// Gemeinsamer Start von App und Hintergrundabruf: Einstellungen, Speicher, Saisonplan und Ordner öffnen und den
/// Provider-Container damit füllen.
Future<ProviderContainer> createAppContainer({NotificationCenterBridge? notificationCenter}) async {
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  // Lebensmitteltabelle im Hintergrund laden; bis dahin bleiben KI-Schätzungen stehen (wie ohne Treffer).
  unawaited(rootBundle.loadString('packages/coach_core/assets/bls.tsv').then(BLS.load));
  final storage = await AppStorage.open();
  final season = await rootBundle
      .loadString('packages/coach_core/assets/season-plan.json')
      .then<SeasonSchedule?>(SeasonSchedule.load, onError: (Object _) => null);
  final support = await getApplicationSupportDirectory().then<String?>((dir) => dir.path, onError: (Object _) => null);
  final cache = await getApplicationCacheDirectory().then<String?>((dir) => dir.path, onError: (Object _) => null);
  return ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      appStorageProvider.overrideWithValue(storage),
      activityFoldersProvider.overrideWithValue((support: support, cache: cache)),
      seasonScheduleProvider.overrideWithValue(season),
      notificationCenterProvider.overrideWithValue(notificationCenter),
    ],
  );
}

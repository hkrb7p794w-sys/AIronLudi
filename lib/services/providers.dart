import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/repositories/metrics_repository.dart';
import '../data/storage.dart';
import 'account/account_service.dart';
import 'ai/ai_client.dart';
import 'garmin/activity_stores.dart';
import 'garmin/garmin_client.dart';
import 'garmin/garmin_connect_session.dart';
import 'garmin/garmin_sync_service.dart';

/// Garmin-Konto (inoffizieller Zugang).
final garminConnectProvider = Provider<GarminConnectSession>(
  (ref) => GarminConnectSession(secrets: ref.watch(secretsProvider), settings: ref.watch(settingsStoreProvider)),
);

/// Garmin Personal API mit dem Konto als erstem Weg.
final garminClientProvider = Provider<GarminClient>(
  (ref) => GarminClient(secrets: ref.watch(secretsProvider), connect: ref.watch(garminConnectProvider)),
);

/// KI-Worker; Einstellungen, eigene Quellen und Nutzungsprotokoll verbindet der App-Zustand.
final aiClientProvider = Provider<AIClient>(
  (ref) => AIClient(secrets: ref.watch(secretsProvider), settings: ref.watch(settingsStoreProvider)),
);

final accountServiceProvider = ChangeNotifierProvider<AccountService>(
  (ref) => AccountService(ai: ref.watch(aiClientProvider), settings: ref.watch(settingsStoreProvider)),
);

/// Ordner für Auswertungen (App-Support) und FIT-Dateien (Cache); in `main` gesetzt.
final activityFoldersProvider = Provider<({String? support, String? cache})>((ref) => (support: null, cache: null));

final garminSyncServiceProvider = Provider<GarminSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final folders = ref.watch(activityFoldersProvider);
  return GarminSyncService(
    client: ref.watch(garminClientProvider),
    settings: ref.watch(settingsStoreProvider),
    metrics: MetricsRepository(db),
    activities: ActivityRepository(db),
    raw: RawResponseRepository(db),
    analysisStore: ActivityAnalysisStore(folder: folders.support),
    reportStore: ActivityReportStore(folder: folders.support, cacheFolder: folders.cache),
    sources: ref.watch(sourceStoreProvider),
  );
});

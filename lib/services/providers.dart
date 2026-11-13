import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/repositories/gym_repository.dart';
import '../data/repositories/metrics_repository.dart';
import '../data/settings/coach_settings.dart';
import '../data/storage.dart';
import '../platform/notifications.dart';

import 'account/account_service.dart';
import 'ai/ai_client.dart';
import 'garmin/activity_stores.dart';
import 'garmin/garmin_client.dart';
import 'garmin/garmin_connect_session.dart';
import 'garmin/garmin_sync_service.dart';
import 'gym/garmin_strength_service.dart';
import 'health/health_import_service.dart';
import 'health/health_source.dart';
import 'health/health_writer.dart';
import 'nutrition/open_food_facts_client.dart';
import 'nutrition/pending_analysis.dart';
import 'reminders/reminder_service.dart';
import 'social/game_service.dart';
import 'social/league_service.dart';
import 'social/social_service.dart';

/// Garmin-Konto (inoffizieller Zugang).
final garminConnectProvider = Provider<GarminConnectSession>(
  (ref) => GarminConnectSession(secrets: ref.watch(secretsProvider), settings: ref.watch(settingsStoreProvider)),
);

/// Garmin Personal API mit dem Konto als erstem Weg.
final garminClientProvider = Provider<GarminClient>(
  (ref) => GarminClient(secrets: ref.watch(secretsProvider), connect: ref.watch(garminConnectProvider)),
);

/// KI-Worker; KI-Stufe, eigene Quellen und Nutzungsprotokoll kommen aus den App-Einstellungen (gelesen bei jeder
/// Anfrage, damit Änderungen der Einstellungen den Client nicht neu erzeugen).
final aiClientProvider = Provider<AIClient>((ref) {
  CoachSettings coach() => ref.read(coachSettingsProvider);
  return AIClient(secrets: ref.watch(secretsProvider), settings: ref.watch(settingsStoreProvider))
    ..settings = (() => coach().ai)
    ..userSources = (() => coach().userSources)
    ..onUsage = ((entry) => coach().aiUsage = AIUsageLog.appending(entry, coach().aiUsage));
});

/// App-Einstellungen (`coach.*`).
final coachSettingsProvider = ChangeNotifierProvider<CoachSettings>(
  (ref) => CoachSettings(ref.watch(settingsStoreProvider)),
);

final leagueServiceProvider = ChangeNotifierProvider<LeagueService>(
  (ref) => LeagueService(ai: ref.watch(aiClientProvider), settings: ref.read(coachSettingsProvider)),
);

final accountServiceProvider = ChangeNotifierProvider<AccountService>(
  (ref) => AccountService(ai: ref.watch(aiClientProvider), settings: ref.watch(settingsStoreProvider)),
);

/// Ordner für Auswertungen (App-Support) und FIT-Dateien (Cache); in `main` gesetzt.
final activityFoldersProvider = Provider<({String? support, String? cache})>((ref) => (support: null, cache: null));

final garminSyncServiceProvider = Provider<GarminSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final folders = ref.watch(activityFoldersProvider);
  final sources = ref.watch(sourceStoreProvider);
  sources.preferences = () => ref.read(coachSettingsProvider).sources;
  return GarminSyncService(
    client: ref.watch(garminClientProvider),
    settings: ref.watch(settingsStoreProvider),
    metrics: MetricsRepository(db),
    activities: ActivityRepository(db),
    raw: RawResponseRepository(db),
    analysisStore: ActivityAnalysisStore(folder: folders.support),
    reportStore: ActivityReportStore(folder: folders.support, cacheFolder: folders.cache),
    sources: sources,
  );
});

final socialServiceProvider = ChangeNotifierProvider<SocialService>(
  (ref) => SocialService(
    ai: ref.watch(aiClientProvider),
    account: ref.watch(accountServiceProvider),
    sharedPosts: SharedPostStore(ref.watch(settingsStoreProvider)),
  ),
);

final gameServiceProvider = ChangeNotifierProvider<GameService>(
  (ref) => GameService(ai: ref.watch(aiClientProvider), account: ref.watch(accountServiceProvider)),
);

final openFoodFactsProvider = Provider<OpenFoodFactsClient>((ref) => OpenFoodFactsClient());

final pendingAnalysisStoreProvider = Provider<PendingAnalysisStore>(
  (ref) => PendingAnalysisStore(ref.watch(settingsStoreProvider), folder: ref.watch(activityFoldersProvider).support),
);

final garminStrengthServiceProvider = Provider<GarminStrengthService>((ref) {
  final db = ref.watch(databaseProvider);
  return GarminStrengthService(
    gym: GymRepository(db),
    activities: ActivityRepository(db),
    folder: ref.watch(activityFoldersProvider).support,
  );
});

/// Mitteilungszentrale des Geräts; wird in `main` gesetzt (Einrichtung ist asynchron), ohne: keine Mitteilungen.
final notificationCenterProvider = Provider<NotificationCenterBridge?>((ref) => null);

final reminderServiceProvider = ChangeNotifierProvider<ReminderService>(
  (ref) => ReminderService(settings: ref.read(coachSettingsProvider), center: ref.watch(notificationCenterProvider)),
);

final healthSourceProvider = Provider<HealthSource>((ref) => PluginHealthSource());

final healthImportServiceProvider = ChangeNotifierProvider<HealthImportService>((ref) {
  final db = ref.watch(databaseProvider);
  final folders = ref.watch(activityFoldersProvider);
  return HealthImportService(
    source: ref.watch(healthSourceProvider),
    settings: ref.watch(settingsStoreProvider),
    metrics: MetricsRepository(db),
    activities: ActivityRepository(db),
    sources: ref.watch(sourceStoreProvider),
    reportStore: ActivityReportStore(folder: folders.support, cacheFolder: folders.cache),
  );
});

final workoutWriterProvider = Provider<WorkoutSaving>((ref) => HealthWorkoutWriter());

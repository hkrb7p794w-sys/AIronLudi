import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/app_model.dart';
import '../app/user_providers.dart';
import '../data/repositories/gym_repository.dart';
import '../data/repositories/meal_repository.dart';
import '../data/repositories/metrics_repository.dart';
import '../data/settings/coach_settings.dart';
import '../data/settings/settings_store.dart';
import '../data/storage.dart';
import '../platform/notifications.dart';
import 'account/account_service.dart';
import 'ai/ai_client.dart';
import 'alarm/wake_alarm_service.dart';
import 'garmin/activity_stores.dart';
import 'garmin/garmin_client.dart';
import 'garmin/garmin_connect_session.dart';
import 'garmin/garmin_sync_service.dart';
import 'gym/garmin_strength_service.dart';
import 'health/health_import_service.dart';
import 'health/health_source.dart';
import 'health/health_writer.dart';
import 'motivation/companion_photo.dart';
import 'nutrition/cook_share_service.dart';
import 'nutrition/meal_share_service.dart';
import 'nutrition/open_food_facts_client.dart';
import 'nutrition/pending_analysis.dart';
import 'reminders/reminder_service.dart';
import 'social/game_service.dart';
import 'social/league_service.dart';
import 'social/social_auto_share.dart';
import 'social/social_service.dart';
import 'speech/dictation.dart';
import 'update/app_update_service.dart';
import 'whoop/whoop_service.dart';

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

/// Foto des Begleiters im Ordner des Benutzers.
final companionPhotoProvider = Provider<CompanionPhoto>((ref) => CompanionPhoto(ref.watch(userDirectoryProvider)));

/// Ordner für Auswertungen (App-Support) und FIT-Dateien (Cache) des Benutzers; in `createAppContainer` gesetzt.
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

/// Trainings automatisch mit Freunden teilen.
final socialAutoShareProvider = Provider<SocialAutoShare>(
  (ref) => SocialAutoShare(
    settings: ref.watch(settingsStoreProvider),
    social: ref.watch(socialServiceProvider),
    activities: ref.watch(activityRepositoryProvider),
    gym: ref.watch(gymRepositoryProvider),
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
  (ref) => ReminderService(
    settings: ref.read(coachSettingsProvider),
    center: ref.watch(notificationCenterProvider),
    mealsOnLockScreen: () {
      final store = ref.read(settingsStoreProvider);
      return store.boolValue(SettingsKeys.mealsLiveActivity) && store.boolValue(SettingsKeys.mealsLiveReminders);
    },
  ),
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

final dictationProvider = ChangeNotifierProvider.autoDispose<Dictation>((ref) => Dictation());

/// Saisonplan aus `season-plan.json`; wird in `main` geladen.
/// Wecker zur Aufstehzeit (Systemwecker über die Plattformbrücke).
final wakeAlarmServiceProvider = ChangeNotifierProvider<WakeAlarmService>(
  (ref) => WakeAlarmService(store: ref.watch(settingsStoreProvider)),
);

final seasonScheduleProvider = Provider<SeasonSchedule?>((ref) => null);

final appModelProvider = ChangeNotifierProvider<AppModel>((ref) {
  final db = ref.watch(databaseProvider);
  return AppModel(
    // Demo-Benutzer (Ich › Technik › Demo ansehen): nichts abrufen, sichern oder teilen.
    isDemo: ref.read(settingsStoreProvider).boolValue(SettingsKeys.demo),
    settings: ref.read(coachSettingsProvider),
    garmin: ref.watch(garminClientProvider),
    sync: ref.watch(garminSyncServiceProvider),
    health: ref.read(healthImportServiceProvider),
    sources: ref.watch(sourceStoreProvider),
    reminders: ref.read(reminderServiceProvider),
    strength: ref.watch(garminStrengthServiceProvider),
    metrics: MetricsRepository(db),
    activities: ActivityRepository(db),
    meals: MealRepository(db),
    gymRepository: GymRepository(db),
    seasonSchedule: ref.watch(seasonScheduleProvider),
    whoop: ref.read(whoopServiceProvider),
  );
});

/// WHOOP über die offizielle API; den Token-Tausch macht der Worker.
final whoopServiceProvider = ChangeNotifierProvider<WhoopService>(
  (ref) => WhoopService(
    ai: ref.watch(aiClientProvider),
    secrets: ref.watch(secretsProvider),
    settings: ref.watch(settingsStoreProvider),
    activities: ActivityRepository(ref.watch(databaseProvider)),
  ),
);

final mealShareServiceProvider = Provider<MealShareService>((ref) => MealShareService(ref.watch(aiClientProvider)));

final cookShareServiceProvider = Provider<CookShareService>((ref) => CookShareService(ref.watch(aiClientProvider)));

/// Prüft Apple Health bzw. Health Connect (Diagnose in den Einstellungen).
final healthProbeProvider = Provider<Future<HealthAccessDiagnosis> Function()>(
  (ref) =>
      () => HealthProbe().run(),
);

/// Version und Build der installierten App.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Build-Nummer der installierten App (Android: `versionCode`); `null`, wenn sie nicht lesbar ist.
final installedBuildProvider = Provider<Future<int?> Function()>(
  (ref) => () async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } on Object {
      return null;
    }
  },
);

/// Update-Hinweis der Android-App (siehe [AppUpdateService]).
final appUpdateServiceProvider = ChangeNotifierProvider<AppUpdateService>(
  (ref) => AppUpdateService(
    ai: ref.watch(aiClientProvider),
    settings: ref.watch(settingsStoreProvider),
    installedBuild: ref.watch(installedBuildProvider),
  ),
);

/// Bildschirm anlassen (laufende Gym-Einheit); in Tests ohne Wirkung.
final screenAwakeProvider = Provider<Future<void> Function(bool on)>(
  (ref) => (on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object {
      // Ohne Plattformteil.
    }
  },
);

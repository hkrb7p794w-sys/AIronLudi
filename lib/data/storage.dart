import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup/backup_service.dart';
import 'db/database.dart';
import 'repositories/gym_repository.dart';
import 'repositories/meal_repository.dart';
import 'repositories/metrics_repository.dart';
import 'repositories/source_store.dart';
import 'secure/secret_store.dart';
import 'settings/settings_store.dart';
import 'users/current_user.dart';
import 'users/user_storage.dart';

/// Geöffneter Speicher der App: Datenbank, Einstellungen und Geheimnisse.
final class AppStorage {
  const AppStorage({required this.database, required this.settings, required this.secrets, this.openError});

  final CoachDatabase database;
  final SettingsStore settings;
  final Secrets secrets;

  /// Die Datenbank ließ sich nicht öffnen (z. B. fehlgeschlagene Migration); die App läuft nur im Arbeitsspeicher. Die
  /// Datei bleibt unangetastet, neue Einträge gehen beim Beenden aber verloren – die App warnt (Banner).
  final String? openError;

  bool get isTemporary => openError != null;

  /// Öffnet die Datei; misslingt das, im Arbeitsspeicher weiter (lieber ohne Daten starten als abstürzen).
  ///
  /// [location]: Speicher des Benutzers (eigene Datenbankdatei, eigene Schlüssel); ohne: der ursprüngliche.
  static Future<AppStorage> open({QueryExecutor? executor, SecretStore? secrets, UserLocation? location}) async {
    final store = await Secrets.load(secrets ?? DeviceSecretStore(prefix: location?.secretPrefix ?? ''));
    final database = executor == null
        ? CoachDatabase.open(name: location?.databaseName ?? 'coach')
        : CoachDatabase(executor);
    try {
      final settings = await SettingsStore.open(database);
      return AppStorage(database: database, settings: settings, secrets: store);
    } on Object catch (error) {
      await database.close().catchError((Object _) {});
      final fallback = CoachDatabase(NativeDatabase.memory());
      return AppStorage(
        database: fallback,
        settings: await SettingsStore.open(fallback),
        secrets: store,
        openError: '$error',
      );
    }
  }
}

/// Wird in `main` mit dem geöffneten Speicher überschrieben.
final appStorageProvider = Provider<AppStorage>(
  (ref) => throw UnimplementedError('appStorageProvider muss in main überschrieben werden'),
);

final databaseProvider = Provider<CoachDatabase>((ref) => ref.watch(appStorageProvider).database);

final settingsStoreProvider = Provider<SettingsStore>((ref) => ref.watch(appStorageProvider).settings);

final secretsProvider = Provider<Secrets>((ref) => ref.watch(appStorageProvider).secrets);

final backupServiceProvider = Provider<BackupService>((ref) {
  final user = ref.watch(currentUserProvider);
  return BackupService(
    ref.watch(databaseProvider),
    ref.watch(settingsStoreProvider),
    owner: user.isLegacy ? null : user.username,
  );
});

final metricsRepositoryProvider = Provider<MetricsRepository>((ref) => MetricsRepository(ref.watch(databaseProvider)));

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(databaseProvider)),
);

final rawResponseRepositoryProvider = Provider<RawResponseRepository>(
  (ref) => RawResponseRepository(ref.watch(databaseProvider)),
);

final mealRepositoryProvider = Provider<MealRepository>((ref) => MealRepository(ref.watch(databaseProvider)));

final gymRepositoryProvider = Provider<GymRepository>((ref) => GymRepository(ref.watch(databaseProvider)));

/// Quellen-Ablage; die Einstellungen (`preferences`) setzt der Synchronisierungsdienst.
final sourceStoreProvider = Provider<SourceStore>(
  (ref) => SourceStore(ref.watch(databaseProvider), ref.watch(settingsStoreProvider)),
);

/// Meldet jede Änderung der Trainingsdaten in der Datenbank: Tageswerte (Schlaf, HRV, Ruhepuls, Body Battery …),
/// Aktivitäten (Garmin, WHOOP, Health, nachgetragen) und Gym-Einheiten der App. Unabhängig davon, welche Quelle oder
/// welcher Bildschirm geschrieben hat – damit „Meine Belastung heute“ (Daily Strain) über den Tag mitläuft.
final trainingDataChangesProvider = Provider<Stream<void>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .tableUpdates(TableUpdateQuery.onAllTables([db.dailyMetricsRecords, db.activityRecords, db.gymSessionRecords]))
      .map((_) {});
});

/// Meldet jede Änderung an Mahlzeiten (auch aus anderen Bereichen, z. B. dem Fuel Planner), damit die Ernährung neu
/// lädt.
final mealDataChangesProvider = Provider<Stream<void>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.tableUpdates(TableUpdateQuery.onAllTables([db.mealRecords])).map((_) {});
});

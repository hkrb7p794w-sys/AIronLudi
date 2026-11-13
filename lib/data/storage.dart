
import 'backup/backup_service.dart';
import 'db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repositories/gym_repository.dart';
import 'repositories/meal_repository.dart';
import 'repositories/metrics_repository.dart';
import 'repositories/source_store.dart';
import 'secure/secret_store.dart';
import 'settings/settings_store.dart';

/// Geöffneter Speicher der App: Datenbank, Einstellungen und Geheimnisse.
final class AppStorage {
  const AppStorage({required this.database, required this.settings, required this.secrets, this.openError});

  final CoachDatabase database;
  final SettingsStore settings;
  final SecretStore secrets;

  /// Die Datenbank ließ sich nicht öffnen (z. B. fehlgeschlagene Migration); die App läuft nur im Arbeitsspeicher. Die
  /// Datei bleibt unangetastet, neue Einträge gehen beim Beenden aber verloren – die App warnt (Banner).
  final String? openError;

  bool get isTemporary => openError != null;

  /// Öffnet die Datei; misslingt das, im Arbeitsspeicher weiter (lieber ohne Daten starten als abstürzen).
  static Future<AppStorage> open({QueryExecutor? executor, SecretStore? secrets}) async {
    final store = secrets ?? DeviceSecretStore();
    final database = executor == null ? CoachDatabase.open() : CoachDatabase(executor);
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

final secretStoreProvider = Provider<SecretStore>((ref) => ref.watch(appStorageProvider).secrets);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider), ref.watch(settingsStoreProvider)),
);

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

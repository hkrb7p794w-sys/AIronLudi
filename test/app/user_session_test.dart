// Mehrere Benutzer auf einem Gerät: getrennte Datenbankdateien, Einstellungen, Geheimnisse und Ordner; der Wechsel
// räumt auf (Live-Aktivitäten, Mitteilungen, Widgets) und verwirft den alten Container samt Datenbank.
import 'dart:io';
import 'dart:typed_data';

import 'package:aironludi/app/user_providers.dart';
import 'package:aironludi/app/user_session.dart';
import 'package:aironludi/data/backup/backup_service.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/data/users/user_storage.dart';
import 'package:aironludi/platform/notifications.dart';
import 'package:aironludi/services/activities/live_activities.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/services/widgets/widget_providers.dart';
import 'package:aironludi/services/widgets/widget_store.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Schlüsselbund-Ersatz mit Präfixen wie `DeviceSecretStore` (ein gemeinsamer Speicher für alle Benutzer).
final class _Keychain {
  final Map<String, String> values = {};

  SecretStore store(String prefix) => _PrefixedStore(values, prefix);
}

final class _PrefixedStore implements SecretStore {
  _PrefixedStore(this._values, this._prefix);

  final Map<String, String> _values;
  final String _prefix;

  @override
  Future<String?> read(SecretKey key) async => _values['$_prefix${key.name}'];

  @override
  Future<void> write(SecretKey key, String? value) async =>
      value == null || value.isEmpty ? _values.remove('$_prefix${key.name}') : _values['$_prefix${key.name}'] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ({String? documents, String? support, String? cache}) folders;
  late _Keychain keychain;
  late FakeNotificationCenter center;
  late FakeLiveActivityHost activities;
  late Directory widgets;

  setUp(() {
    root = Directory.systemTemp.createTempSync('users');
    folders = (
      documents: p.join(root.path, 'documents'),
      support: p.join(root.path, 'support'),
      cache: p.join(root.path, 'cache'),
    );
    for (final folder in [folders.documents!, folders.support!, folders.cache!]) {
      Directory(folder).createSync(recursive: true);
    }
    widgets = Directory(p.join(root.path, 'group'))..createSync();
    keychain = _Keychain();
    center = FakeNotificationCenter();
    activities = FakeLiveActivityHost();
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Wie `createAppContainer`, aber mit Datenbankdatei im Testordner und Ersatz für Schlüsselbund und Widgets.
  Future<ProviderContainer> open(LocalUser user, UserSession session) async {
    final location = UserLocation(user);
    final storage = await AppStorage.open(
      executor: NativeDatabase(File(p.join(folders.documents!, '${location.databaseName}.sqlite'))),
      secrets: keychain.store(location.secretPrefix),
      location: location,
    );
    return ProviderContainer(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        currentUserProvider.overrideWithValue(user),
        userSessionProvider.overrideWithValue(session),
        userFolderProvider.overrideWithValue(location.support(folders.support)),
        activityFoldersProvider.overrideWithValue((
          support: location.support(folders.support),
          cache: location.cache(folders.cache),
        )),
        widgetHostProvider.overrideWithValue(DirectoryWidgetHost(widgets)),
        liveActivityHostProvider.overrideWithValue(activities),
      ],
    );
  }

  Future<UserSession> start() async {
    final store = UserDirectoryStore(folders.support);
    final session = UserSession(
      directory: await store.load(),
      store: store,
      open: open,
      folders: folders,
      notificationCenter: center,
      secrets: keychain.store,
      waitForFrame: () async {},
    );
    await session.start();
    return session;
  }

  StoredMeal meal(String title) => StoredMeal(
    day: const CalendarDay(2026, 11, 15),
    createdAt: DateTime.utc(2026, 11, 15, 12),
    category: MealCategory.lunch,
    title: title,
    items: [MealItem.water(milliliters: 250)],
  );

  test('zwei Benutzer: nichts von A ist bei B zu sehen – Datenbank, Einstellungen, Geheimnisse, Dateien', () async {
    final session = await start();
    final legacy = session.container;
    expect(session.user.isLegacy, isTrue);

    // Benutzer A (ursprünglich) trägt ein und meldet sich bei Garmin an.
    await legacy.read(mealRepositoryProvider).save(meal('Linsen von A'));
    await legacy.read(settingsStoreProvider).setString(SettingsKeys.workerURL, 'https://a.example.workers.dev');
    await legacy.read(secretsProvider).set(SecretKey.garminAPIKey, 'schluessel-a');
    await legacy.read(companionPhotoProvider).save(_jpeg());
    expect(await legacy.read(companionPhotoProvider).load(), isNotNull);

    // Neuer Benutzer B: leerer Speicher, eigene Datei, eigene Schlüssel.
    final ben = await session.add(username: 'ben', displayName: 'Ben');
    expect(session.user, ben);
    final b = session.container;
    expect(identical(b, legacy), isFalse);
    expect(b.read(currentUserProvider), ben);
    expect(await b.read(mealRepositoryProvider).all(), isEmpty);
    expect(b.read(settingsStoreProvider).string(SettingsKeys.workerURL), isNull);
    expect(b.read(secretsProvider).string(SecretKey.garminAPIKey), isNull);
    expect(await b.read(companionPhotoProvider).load(), isNull);
    expect(File(p.join(folders.documents!, 'coach-${ben.id}.sqlite')).existsSync(), isTrue);

    await b.read(mealRepositoryProvider).save(meal('Nudeln von B'));
    await b.read(secretsProvider).set(SecretKey.garminAPIKey, 'schluessel-b');
    expect(keychain.values['garminAPIKey'], 'schluessel-a');
    expect(keychain.values['u.${ben.id}.garminAPIKey'], 'schluessel-b');

    // Zurück zu A: nur seine Daten.
    await session.switchTo(UserDirectory.legacyID);
    final a = session.container;
    expect([for (final item in await a.read(mealRepositoryProvider).all()) item.title], ['Linsen von A']);
    expect(a.read(settingsStoreProvider).string(SettingsKeys.workerURL), 'https://a.example.workers.dev');
    expect(a.read(secretsProvider).string(SecretKey.garminAPIKey), 'schluessel-a');

    // Das Verzeichnis überlebt den Neustart, mit dem zuletzt aktiven Benutzer.
    final reloaded = await UserDirectoryStore(folders.support).load();
    expect(reloaded.active.isLegacy, isTrue);
    expect(reloaded.users.map((user) => user.username), ['ich', 'ben']);
    session.dispose();
  });

  test('Wechsel räumt auf: Live-Aktivitäten, Mitteilungen, Widgets; alter Container ist weg', () async {
    final session = await start();
    final old = session.container;
    final oldSettings = old.read(settingsStoreProvider);
    await center.add(
      LocalNotification(id: 'coach.reminder.x', title: 'A', body: '', day: CalendarDay.today(), hour: 23, minute: 0),
    );
    await old
        .read(widgetStoreProvider)
        .save(
          WidgetSnapshot(
            createdAt: DateTime.now(),
            day: CalendarDay.today(),
            today: const WidgetToday(level: RecoveryLevel.normal, headline: 'A'),
            nutrition: null,
            gym: null,
            health: const [],
          ),
        );
    expect(File(p.join(widgets.path, WidgetSnapshot.fileName)).existsSync(), isTrue);

    await session.add(username: 'carla');
    expect(activities.workout, [null]);
    expect(activities.meals, [null]);
    expect(await center.pendingIdentifiers(), isEmpty);
    expect(File(p.join(widgets.path, WidgetSnapshot.fileName)).existsSync(), isFalse);
    // Späte Schreibvorgänge des alten Benutzers landen nirgends.
    expect(oldSettings.isClosed, isTrue);
    await oldSettings.setString(SettingsKeys.workerURL, 'https://spaet.example');
    expect(session.container.read(settingsStoreProvider).string(SettingsKeys.workerURL), isNull);
    expect(() => old.read(databaseProvider), throwsA(anything));
    session.dispose();
  });

  test('löschen entfernt den ganzen Speicher des Benutzers, andere bleiben unberührt', () async {
    final session = await start();
    await session.container.read(secretsProvider).set(SecretKey.aiAppToken, 'token-a');
    final dora = await session.add(username: 'dora');
    final location = UserLocation(dora);
    await session.container.read(secretsProvider).set(SecretKey.aiAppToken, 'token-d');
    await session.container.read(companionPhotoProvider).save(_jpeg());
    final support = Directory(location.support(folders.support)!);
    expect(support.existsSync(), isTrue);

    expect(() => session.remove(dora.id), throwsA(isA<UserDirectoryError>()));
    await session.switchTo(UserDirectory.legacyID);
    await session.remove(dora.id);
    expect(session.users.map((user) => user.username), ['ich']);
    expect(support.existsSync(), isFalse);
    for (final file in location.databaseFiles(folders.documents!)) {
      expect(file.existsSync(), isFalse);
    }
    expect(keychain.values.keys.where((key) => key.startsWith('u.')), isEmpty);
    expect(keychain.values['aiAppToken'], 'token-a');
    expect(() => session.remove(UserDirectory.legacyID), throwsA(isA<UserDirectoryError>()));
    session.dispose();
  });

  test('Speicherorte: der ursprüngliche Benutzer behält die alten Stellen', () {
    final legacy = UserLocation(UserDirectory.initial().active);
    expect(legacy.databaseName, 'coach');
    expect(legacy.secretPrefix, '');
    expect(legacy.support('/s'), '/s');
    final other = UserLocation(
      LocalUser(id: 'ABCDEFGH-1234', username: 'eva', displayName: '', createdAt: DateTime.utc(2026)),
    );
    expect(other.databaseName, 'coach-ABCDEFGH-1234');
    expect(other.secretPrefix, 'u.ABCDEFGH-1234.');
    expect(other.support('/s'), '/s/users/ABCDEFGH-1234');
    expect(BackupService.folderFileName(null), AppBackup.fileName);
    expect(BackupService.folderFileName('eva'), 'IronLudi-Sicherung-eva.json');
    expect(BackupService.folderFileName('eva', previous: true), 'IronLudi-Sicherung-eva-vorher.json');
  });
}

/// Kleines gültiges Bild für das Begleiter-Foto.
Uint8List _jpeg() => Uint8List.fromList(
  // 1×1 PNG (wird beim Speichern verkleinert und als JPEG abgelegt).
  [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
    0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ],
);

// Datenschicht: Einstellungen wie UserDefaults, sicherer Speicher, Sicherung im Format der Swift-App.
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/data/backup/backup_service.dart';
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

CoachDatabase memory() => CoachDatabase(NativeDatabase.memory());

GymSession session() => GymSession(
  workoutKey: null,
  title: 'Push A',
  start: DateTime.utc(2026, 11, 9, 17),
  end: DateTime.utc(2026, 11, 9, 18),
  exercises: [
    LoggedExercise(
      exerciseID: 'bankdruecken',
      name: 'Bankdrücken',
      group: MuscleGroup.chest,
      sets: [LoggedSet(reps: 8, weightKg: 60)],
    ),
  ],
);

MealItem oats() => MealItem(
  name: 'Haferflocken',
  grams: 80,
  source: MealItemSource.manual,
  per100g: NutrientValues({Nutrient.kcal: 370, Nutrient.protein: 13}),
);

Future<void> seed(CoachDatabase db) async {
  final gym = session();
  await db
      .into(db.gymSessionRecords)
      .insert(
        GymSessionRecordsCompanion.insert(
          id: gym.id,
          dayKey: gym.day.iso,
          start: gym.start,
          payload: utf8.encode(jsonEncode(gym.toJson())),
          savedToHealth: const Value(true),
        ),
      );
  await db
      .into(db.mealRecords)
      .insert(
        MealRecordsCompanion.insert(
          id: newUuid(),
          dayKey: '2026-11-09',
          createdAt: DateTime.utc(2026, 11, 9, 7),
          categoryRaw: MealCategory.breakfast.rawValue,
          title: 'Porridge',
          hint: '',
          itemsPayload: utf8.encode(jsonEncode([oats().toJson()])),
        ),
      );
  await db
      .into(db.foodRecords)
      .insert(
        FoodRecordsCompanion.insert(
          key: 'name:haferflocken',
          name: 'Haferflocken',
          payload: utf8.encode(jsonEncode(oats().toJson())),
          lastUsed: DateTime.utc(2026, 11, 9),
          useCount: 3,
        ),
      );
}

void main() {
  group('Einstellungen', () {
    test('typisierte Werte bleiben nach dem Neustart erhalten', () async {
      final directory = Directory.systemTemp.createTempSync('coach-settings');
      final file = File('${directory.path}/coach.sqlite');
      var db = CoachDatabase(NativeDatabase(file));
      var store = await SettingsStore.open(db);
      await store.setString(SettingsKeys.privacy, 'voll');
      await store.setBool(SettingsKeys.showsEvidence, true);
      await store.setInt('coach.count', 3);
      await store.setDouble('coach.factor', 1.5);
      await store.setJson(SettingsKeys.companion, CompanionSettings(enabled: true, name: 'Daisy').toJson());
      await store.setString(SettingsKeys.garminLastSync, '2026-11-09');
      await db.close();

      db = CoachDatabase(NativeDatabase(file));
      store = await SettingsStore.open(db);
      expect(store.string(SettingsKeys.privacy), 'voll');
      expect(store.boolValue(SettingsKeys.showsEvidence), isTrue);
      expect(store.boolValue('coach.fehlt'), isFalse);
      expect(store.intValue('coach.count'), 3);
      expect(store.doubleValue('coach.factor'), 1.5);
      expect(store.read(SettingsKeys.companion, CompanionSettings.fromJson, CompanionSettings()).name, 'Daisy');
      // Gerätestand gehört nicht zur Sicherung.
      expect(store.backedUp.keys, isNot(contains(SettingsKeys.garminLastSync)));
      expect(store.backedUp.keys, contains(SettingsKeys.privacy));
      await store.remove(SettingsKeys.privacy);
      expect(store.string(SettingsKeys.privacy), isNull);
      await db.close();
      directory.deleteSync(recursive: true);
    });

    test('unlesbare Werte fallen auf den Standard zurück', () async {
      final db = memory();
      final store = await SettingsStore.open(db);
      await store.setValue(SettingsKeys.reminders, BackupData(utf8.encode('{kaputt')));
      expect(store.json(SettingsKeys.reminders), isNull);
      expect(store.read<int>(SettingsKeys.reminders, (json) => 1, 7), 7);
      await store.setJson(SettingsKeys.pantry, ['Linsen']);
      expect(store.read<List<String>>(SettingsKeys.pantry, (json) => (json! as List).cast<String>(), []), ['Linsen']);
      await db.close();
    });

    test('Änderungen werden gemeldet', () async {
      final db = memory();
      final store = await SettingsStore.open(db);
      final changed = <String>[];
      final subscription = store.changes.listen(changed.add);
      await store.setBool(SettingsKeys.showsEvidence, true);
      await Future<void>.delayed(Duration.zero);
      expect(changed, [SettingsKeys.showsEvidence]);
      await subscription.cancel();
      await db.close();
    });
  });

  group('Sicherer Speicher', () {
    test('leer löscht den Eintrag', () async {
      final store = InMemorySecretStore({SecretKey.garminAPIKey: 'abc'});
      expect(await store.read(SecretKey.garminAPIKey), 'abc');
      await store.write(SecretKey.garminAPIKey, '');
      expect(await store.read(SecretKey.garminAPIKey), isNull);
      await store.write(SecretKey.accountSession, 's1.x');
      expect(await store.read(SecretKey.accountSession), 's1.x');
      // Die Namen sind die Konten im Schlüsselbund der Swift-App.
      expect(SecretKey.values.map((key) => key.name), [
        'garminAPIKey',
        'garminBearerToken',
        'garminConnectToken',
        'aiAppToken',
        'accountSession',
      ]);
    });
  });

  group('Sicherung', () {
    test('erstellen, einspielen, nichts doppelt', () async {
      final source = memory();
      await seed(source);
      final settings = await SettingsStore.open(source);
      await settings.setString(SettingsKeys.privacy, 'voll');
      await settings.setString(SettingsKeys.workerURL, 'https://w.example.dev');
      await settings.setString(SettingsKeys.gymActiveSession, 'läuft');
      final backup = await BackupService(source, settings).make(now: DateTime.utc(2026, 11, 13, 12));
      expect(backup.summary, '1 Krafteinheiten, 1 Mahlzeiten, 1 eigene Lebensmittel, 2 Einstellungen');

      final target = memory();
      final targetSettings = await SettingsStore.open(target);
      final service = BackupService(target, targetSettings);
      final decoded = AppBackup.decode(backup.encoded());
      final result = await service.restore(decoded);
      expect(result.text, '1 Krafteinheiten, 1 Mahlzeiten und 1 Lebensmittel ergänzt, 2 Einstellungen übernommen.');
      expect(targetSettings.string(SettingsKeys.privacy), 'voll');
      expect(targetSettings.string(SettingsKeys.gymActiveSession), isNull);
      final gym = await target.select(target.gymSessionRecords).getSingle();
      expect(gym.savedToHealth, isTrue);
      expect(gym.dayKey, '2026-11-09');
      // Erneutes Einspielen ergänzt nichts.
      final again = await service.restore(decoded);
      expect((again.gym, again.meals, again.foods), (0, 0, 0));
      await source.close();
      await target.close();
    });

    test('Sicherung der Swift-App wird eingespielt', () async {
      // Einstellungen der Swift-App liegen als JSON mit Zeitpunkten in Sekunden seit 2001 (Standard-`JSONEncoder`).
      final swiftSession = utf8.encode(
        '{"id":"2B5C2B4E-6D7A-4A35-9E0D-6E4F2A7B1C11","title":"Pull","start":784404000,"end":784407600,'
        '"exercises":[]}',
      );
      final backup = AppBackup(
        createdAt: DateTime.utc(2026, 11, 13),
        settings: {
          SettingsKeys.privacy: const BackupString('voll'),
          SettingsKeys.showsEvidence: const BackupBool(true),
          SettingsKeys.pantry: BackupData(utf8.encode('["Linsen"]')),
          'garmin.lastSync': const BackupString('nicht aus der Sicherung'),
        },
        gym: [
          BackupGym(
            id: '2B5C2B4E-6D7A-4A35-9E0D-6E4F2A7B1C11',
            payload: swiftSession,
            savedToHealth: false,
            uploadedToGarmin: true,
          ),
          BackupGym(id: 'kaputt', payload: utf8.encode('{}'), savedToHealth: false, uploadedToGarmin: false),
        ],
        meals: [],
        foods: [],
      );
      final db = memory();
      final settings = await SettingsStore.open(db);
      final result = await BackupService(db, settings).restore(AppBackup.decode(backup.encoded()));
      expect(result.gym, 1);
      expect(result.settings, 3);
      expect(settings.contains('garmin.lastSync'), isFalse);
      final row = await db.select(db.gymSessionRecords).getSingle();
      expect(row.uploadedToGarmin, isTrue);
      expect(row.start.isAtSameMomentAs(DateTime.utc(2025, 11, 9, 18)), isTrue);
      // Die Bytes bleiben unverändert (eine spätere Sicherung gibt sie genau so zurück).
      expect(row.payload, swiftSession);
      await db.close();
    });

    test('Ordner: die vorige Sicherung bleibt erhalten', () async {
      final directory = Directory.systemTemp.createTempSync('coach-backup');
      final db = memory();
      final settings = await SettingsStore.open(db);
      final service = BackupService(db, settings);
      expect(await service.backupToFolder(), isFalse);
      await settings.setString(SettingsKeys.backupFolder, directory.path);
      final now = DateTime.utc(2026, 11, 13, 8);
      expect(await service.backupToFolder(now: now), isTrue);
      // Noch nicht fällig.
      expect(await service.backupToFolder(now: now.add(const Duration(hours: 1))), isFalse);
      expect(await service.backupToFolder(now: now.add(const Duration(hours: 21))), isTrue);
      expect(File('${directory.path}/${AppBackup.fileName}').existsSync(), isTrue);
      expect(File('${directory.path}/${AppBackup.previousFileName}').existsSync(), isTrue);
      expect(BackupService.shareFileName(DateTime(2026, 11, 13, 9)), 'IronLudi-Sicherung-2026-11-13.json');
      await db.close();
      directory.deleteSync(recursive: true);
    });
  });

  test('Speicher öffnet sich; misslingt das, läuft die App im Arbeitsspeicher', () async {
    final storage = await AppStorage.open(executor: NativeDatabase.memory(), secrets: InMemorySecretStore());
    expect(storage.isTemporary, isFalse);
    await storage.settings.setBool(SettingsKeys.showsEvidence, true);
    await storage.database.close();

    final broken = await AppStorage.open(
      executor: NativeDatabase(File('/proc/nicht-beschreibbar/coach.sqlite')),
      secrets: InMemorySecretStore(),
    );
    expect(broken.isTemporary, isTrue);
    await broken.settings.setBool(SettingsKeys.showsEvidence, true);
    expect(broken.settings.boolValue(SettingsKeys.showsEvidence), isTrue);
    await broken.database.close();
  });
}

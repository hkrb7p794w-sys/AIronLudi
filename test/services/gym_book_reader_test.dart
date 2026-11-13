// GymBook-Backup (SQLite) lesen und übernehmen.
import 'dart:io';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/gym/gym_book_reader.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temp;
  late CoachDatabase db;
  late SettingsStore store;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('gymbook');
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });

  tearDown(() async {
    await store.close();
    await db.close();
    temp.deleteSync(recursive: true);
  });

  String backup() {
    final path = p.join(temp.path, 'GymBook.sqlite');
    final database = sqlite3.open(path)
      ..execute(
        'CREATE TABLE ZEXERCISE (Z_PK INTEGER PRIMARY KEY, ZNAME TEXT, ZTARGETREGION TEXT, '
        'ZTARGETMUSCLESPRIMARY TEXT, ZEQUIPMENT TEXT)',
      )
      ..execute('CREATE TABLE ZWORKOUT (Z_PK INTEGER PRIMARY KEY, ZNAME TEXT)')
      ..execute(
        'CREATE TABLE ZEXERCISELOG (Z_PK INTEGER PRIMARY KEY, ZDAY TEXT, ZTIME REAL, ZEXERCISE INTEGER, '
        'ZWORKOUT INTEGER, ZFREQUENCYVALUE REAL, ZFREQUENCYUNIT TEXT, ZQUANTITYVALUE REAL, ZQUANTITYUNIT TEXT, '
        'ZSKIPPED INTEGER)',
      )
      ..execute(
        "INSERT INTO ZEXERCISE VALUES (1, 'Bankdrücken an Multipresse', '020.chest', NULL, "
        "'010.flatBench|050.smithMachine')",
      )
      ..execute("INSERT INTO ZEXERCISE VALUES (2, 'Ganz eigene Übung', '020.chest', NULL, NULL)")
      ..execute("INSERT INTO ZWORKOUT VALUES (1, 'Push A')")
      ..execute("INSERT INTO ZEXERCISELOG VALUES (1, '2026-10-23', 29000, 1, 1, 8, 'x', 40, 'kg', 0)")
      ..execute("INSERT INTO ZEXERCISELOG VALUES (2, '2026-10-23', 29200, 1, 1, 8, 'x', 40, 'kg', 0)")
      ..execute("INSERT INTO ZEXERCISELOG VALUES (3, '2026-10-23', 29500, 2, 1, 12, 'x', 10, 'kg', 0)");
    database.close();
    return path;
  }

  test('liest die Protokollzeilen', () {
    final rows = GymBookReader.rows(backup());
    expect(rows, hasLength(3));
    expect(rows.first.exercise, 'Bankdrücken an Multipresse');
    expect(rows.first.workout, 'Push A');
    expect(rows.first.secondsOfDay, 29000);
  });

  test('keine GymBook-Datei: klare Meldung', () {
    final path = p.join(temp.path, 'leer.sqlite');
    sqlite3.open(path)
      ..execute('CREATE TABLE X (A INTEGER)')
      ..close();
    expect(() => GymBookReader.rows(path), throwsA(isA<GymBookQueryError>()));
  });

  test('übernimmt Einheiten einmal und legt eigene Übungen an', () async {
    final settings = CoachSettings(store);
    final gym = GymRepository(db);
    final path = backup();
    final first = await GymBookReader.importBackup(path, gym: gym, settings: settings);
    expect(first, startsWith('1 Einheiten übernommen (1 im Backup, 3 Sätze)'));
    expect(settings.gym.customExercises, isNotEmpty);
    final second = await GymBookReader.importBackup(path, gym: gym, settings: settings);
    expect(second, contains('1 schon vorhanden'));
    expect(await gym.sessions(), hasLength(1));
    expect(File(path).existsSync(), isTrue);
  });
}

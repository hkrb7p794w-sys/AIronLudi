// Routen in eigener Tabelle: Übernahme aus `coach.routes`, Sicherung im bisherigen Format, Schema-Upgrade 1 → 2.
import 'dart:io';

import 'package:aironludi/data/backup/backup_service.dart';
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/route_repository.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/routing/route_stores.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const start = GeoPoint(52.52, 13.405);
const end = GeoPoint(52.53, 13.42);

PlannedRoute route(String id, {String username = 'anna'}) => PlannedRoute(
  id: id,
  username: username,
  name: 'Route $id',
  request: const RouteRequest(
    discipline: RouteDiscipline.run,
    shape: RouteShape.loop,
    start: start,
    distanceMeters: 5000,
  ),
  variant: RouteVariant.balanced,
  points: const [start, end, start],
  engine: 'Test',
  createdAt: DateTime.utc(2026, 11, 21),
);

void main() {
  test('Stand aus den Einstellungen wird übernommen, Reihenfolge bleibt, Schlüssel entfällt', () async {
    final db = CoachDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = await SettingsStore.open(db);
    await settings.setJson(
      SettingsKeys.routes,
      RouteLibrary(username: 'anna', routes: [route('neu'), route('alt')]).toJson(),
    );
    final store = RouteStore(settings, username: 'anna', routes: RouteRepository(db));
    // Sofort lesbar (noch aus den Einstellungen), nach dem Laden aus der Tabelle.
    expect(store.routes.length, 2);
    await store.ready;
    expect([for (final route in store.routes) route.id], ['neu', 'alt']);
    expect(settings.contains(SettingsKeys.routes), isFalse);
    expect((await RouteRepository(db).all('anna')).map((entry) => entry.$1.id), ['neu', 'alt']);

    // Neu öffnen: aus der Tabelle, gleiche Reihenfolge; Speichern stellt nach vorn.
    final again = RouteStore(settings, username: 'anna', routes: RouteRepository(db));
    await again.ready;
    expect([for (final route in again.routes) route.id], ['neu', 'alt']);
    await again.save(again.route('alt')!);
    expect([for (final route in again.routes) route.id], ['alt', 'neu']);
    await again.delete('neu');
    expect((await RouteRepository(db).all('anna')).map((entry) => entry.$1.id), ['alt']);
  });

  test('Stand eines anderen Benutzers bleibt unberührt', () async {
    final db = CoachDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = await SettingsStore.open(db);
    await settings.setJson(
      SettingsKeys.routes,
      RouteLibrary(
        username: 'ben',
        routes: [route('b', username: 'ben')],
      ).toJson(),
    );
    final store = RouteStore(settings, username: 'anna', routes: RouteRepository(db));
    await store.ready;
    expect(store.routes, isEmpty);
    expect(store.hasForeignRoutes, isTrue);
    expect(settings.contains(SettingsKeys.routes), isTrue);
    expect(await RouteRepository(db).all('ben'), isEmpty);
  });

  test('Sicherung: Routen unter coach.routes; Einspielen führt zusammen', () async {
    final source = CoachDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    final sourceSettings = await SettingsStore.open(source);
    final sourceStore = RouteStore(sourceSettings, username: 'anna', routes: RouteRepository(source));
    await sourceStore.save(route('a'));
    await sourceStore.save(route('b'));
    final backup = AppBackup.decode((await BackupService(source, sourceSettings).make()).encoded());
    final saved = backup.settings[SettingsKeys.routes];
    expect(saved, isNotNull);

    final target = CoachDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    final targetSettings = await SettingsStore.open(target);
    final targetStore = RouteStore(targetSettings, username: 'anna', routes: RouteRepository(target));
    await targetStore.save(route('c'));
    await BackupService(target, targetSettings).restore(backup);
    await Future<void>.delayed(Duration.zero);
    await targetStore.ready;
    expect({for (final route in targetStore.routes) route.id}, {'a', 'b', 'c'});
    expect(targetSettings.contains(SettingsKeys.routes), isFalse);
    expect((await RouteRepository(target).all('anna')).length, 3);
  });

  test('Schema 1 → 2: Tabelle wird angelegt, Einstellungen bleiben', () async {
    final directory = Directory.systemTemp.createTempSync('coach-routes');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/coach.sqlite');
    var db = CoachDatabase(NativeDatabase(file));
    final settings = await SettingsStore.open(db);
    await settings.setString(SettingsKeys.privacy, 'voll');
    // Stand von Schema 1 nachbilden: ohne Routen-Tabelle.
    await db.customStatement('DROP TABLE route_records');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    db = CoachDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await SettingsStore.open(db)).string(SettingsKeys.privacy), 'voll');
    await RouteRepository(db).putAll([(route('x'), DateTime.utc(2026, 11, 23))]);
    expect((await RouteRepository(db).all('anna')).single.$1.id, 'x');
  });
}

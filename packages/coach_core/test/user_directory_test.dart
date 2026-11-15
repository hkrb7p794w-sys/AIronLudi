// Benutzer auf einem Gerät (docs/decisions.md, 15.11.2026): Verzeichnis, eindeutige Namen, Schutz des aktiven und des
// ursprünglichen Benutzers, tolerantes Lesen.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  test('erster Start: der vorhandene Speicher gehört dem ursprünglichen Benutzer', () {
    final directory = UserDirectory.initial();
    expect(directory.users, hasLength(1));
    expect(directory.active.id, UserDirectory.legacyID);
    expect(directory.active.isLegacy, isTrue);
    expect(directory.active.username, 'ich');
  });

  test('anlegen: eindeutige, gültige Namen; eigene Kennung; wird nicht von selbst aktiv', () {
    final directory = UserDirectory.initial();
    final anna = directory.add(username: ' Anna.M ', displayName: 'Anna  Müller', now: DateTime.utc(2026, 11, 15));
    expect(anna.username, 'anna.m');
    expect(anna.displayName, 'Anna Müller');
    expect(anna.title, 'Anna Müller');
    expect(UserDirectory.isValidID(anna.id), isTrue);
    expect(anna.isLegacy, isFalse);
    expect(directory.active.isLegacy, isTrue);

    expect(directory.usernameProblem('ANNA.M'), contains('schon'));
    expect(() => directory.add(username: 'anna.m'), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.add(username: 'a'), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.add(username: 'admin'), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.add(username: 'ben', displayName: 'x' * 41), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.add(username: 'ben', id: '../etc'), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.add(username: 'ben', id: anna.id), throwsA(isA<UserDirectoryError>()));
  });

  test('wechseln, umbenennen, löschen: nie den aktiven und nie den ursprünglichen', () {
    final directory = UserDirectory.initial();
    final ben = directory.add(username: 'ben');
    directory.activate(ben.id);
    expect(directory.active, ben);
    expect(() => directory.remove(ben.id), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.remove(UserDirectory.legacyID), throwsA(isA<UserDirectoryError>()));
    expect(() => directory.activate('UNBEKANNT-1234'), throwsA(isA<UserDirectoryError>()));

    directory.rename(ben.id, 'Benjamin');
    expect(directory.active.title, 'Benjamin');
    expect(directory.active.username, 'ben');

    directory.activate(UserDirectory.legacyID);
    expect(directory.remove(ben.id).username, 'ben');
    expect(directory.users, hasLength(1));
  });

  test('höchstens 20 Benutzer', () {
    final directory = UserDirectory.initial();
    for (var index = 1; index < UserDirectory.maxUsers; index++) {
      directory.add(username: 'user$index');
    }
    expect(() => directory.add(username: 'einer.zu.viel'), throwsA(isA<UserDirectoryError>()));
  });

  test('JSON hin und zurück; Unlesbares, Doppeltes und fehlender aktiver Benutzer', () {
    final directory = UserDirectory.initial();
    final anna = directory.add(username: 'anna', now: DateTime.utc(2026, 11, 15, 8));
    directory.activate(anna.id);
    final decoded = UserDirectory.fromJson(directory.toJson())!;
    expect(decoded.active, anna);
    expect(decoded.users.map((user) => user.username), ['ich', 'anna']);

    final messy = UserDirectory.fromJson({
      'active': 'GIBT-ES-NICHT',
      'users': [
        {'id': 'NICHT GÜLTIG', 'username': 'x', 'displayName': '', 'createdAt': ''},
        anna.toJson(),
        {...anna.toJson(), 'username': 'zweite'},
        {'id': 'ABCDEFGH-1', 'username': 'anna', 'displayName': '', 'createdAt': ''},
        {'id': 'ABCDEFGH-2', 'username': 'carla', 'displayName': 'Carla', 'createdAt': 'kaputt'},
      ],
    })!;
    expect(messy.users.map((user) => user.username), ['anna', 'carla']);
    expect(messy.active.username, 'anna');
    expect(UserDirectory.fromJson({'users': <Object?>[]}), isNull);
    expect(UserDirectory.fromJson('kaputt'), isNull);
  });
}

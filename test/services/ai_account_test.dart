// Port von `NetworkClientTests` (KI-Worker und Konto).
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/account/account_service.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late (int, String) Function(HttpRequest request) handler;
  late FakeHttpTransport transport;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    handler = (_) => (200, '');
    transport = FakeHttpTransport((request) {
      final (status, body) = handler(request);
      return HttpResponse(status, utf8.encode(body));
    });
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  AIClient client([Secrets? secrets]) =>
      AIClient(secrets: secrets ?? Secrets.memory(), settings: settings, transport: transport);

  String? authorization(HttpRequest request) => request.headers['Authorization'];

  test('KI-Client prüft die Adresse und liest die Antwort', () async {
    final ai = client();
    await expectLater(ai.configure(url: 'http://unsicher.example', token: 't'), throwsA(AIClientError.invalidURL));
    await ai.configure(url: ' https://coach-ai.example.workers.dev/ ', token: 'geheim');
    expect(ai.workerURL, 'https://coach-ai.example.workers.dev');
    expect(ai.isConfigured, isTrue);

    handler = (_) =>
        (200, '{"output": {"ok": true, "gruss": "Hallo"}, "model": "gemini-3.6-flash", "provider": "gemini"}');
    final response = await ai.run('ping');
    expect(response.output['gruss']?.stringValue, 'Hallo');
    final request = transport.requests.first;
    expect(request.url.toString(), 'https://coach-ai.example.workers.dev/v1/ai/generate');
    expect(authorization(request), 'Bearer geheim');
  });

  test('Android-Download passt zum Worker', () async {
    expect(AIClient.secretPath(prefix: 'android', token: 'app-token-123'), '3d5b0ebdcfa5865d774ee00e8f93d04d');
    final ai = client();
    expect(ai.androidDownloadURL, isNull);
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'app-token-123');
    expect(
      ai.androidDownloadURL.toString(),
      'https://coach-ai.example.workers.dev/android/3d5b0ebdcfa5865d774ee00e8f93d04d/',
    );
  });

  test('SideStore-Quelle passt zum Worker', () async {
    expect(AIClient.sideStoreKey('app-token-123'), 'ee99266b889655b045c7352ceb212936');
    final ai = client();
    expect(ai.sideStoreSourceURL, isNull);
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'app-token-123');
    expect(
      ai.sideStoreSourceURL.toString(),
      'https://coach-ai.example.workers.dev/sidestore/ee99266b889655b045c7352ceb212936/source.json',
    );
  });

  test('401 mit App-Token wird als abgelehnt gemeldet', () async {
    // Abweichung vom Swift-Test: Dort liegt das Token vor dem ersten `configure` und würde als Serverwechsel gelöscht
    // (dann käme `notConfigured`); hier wird es mit der Adresse gesetzt.
    final ai = client();
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'falsch');
    handler = (_) => (401, '{"error": "Nicht autorisiert"}');
    await expectLater(ai.run('ping'), throwsA(AIClientError.unauthorized));
  });

  test('Konto-Sitzung hat Vorrang und läuft ab', () async {
    final ai = client();
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'g1.abcdefghjkmn.sig');
    final account = AccountService(ai: ai, settings: settings, device: 'Test');
    expect(account.isSignedIn, isFalse);

    handler = (_) => (
      200,
      '{"token": "s1.sitzung", "account": {"id": "a1", "username": "lena", "displayName": "Lena", "isAdmin": false}}',
    );
    await account.login(username: ' Lena ', password: 'Sommer-Lauf-2026');
    expect(account.isSignedIn, isTrue);
    expect(account.account?.username, 'lena');
    expect(authorization(transport.requests.last), isNull);
    expect(jsonDecode(utf8.decode(transport.requests.last.body!)), containsPair('username', 'lena'));

    // KI-Anfragen tragen jetzt die Sitzung statt des Gast-Tokens; das Gast-Token bleibt gespeichert.
    handler = (_) => (200, '{"output": {"ok": true}, "model": "m", "provider": "gemini"}');
    await ai.run('ping');
    expect(authorization(transport.requests.last), 'Bearer s1.sitzung');
    expect(ai.appToken, 'g1.abcdefghjkmn.sig');

    // Lehnt der Worker die Sitzung ab, ist das Konto abgemeldet.
    handler = (_) => (401, '{"error": "Nicht autorisiert"}');
    await expectLater(ai.run('ping'), throwsA(AIClientError.signedOut));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(account.isSignedIn, isFalse);
    expect(account.notice, isNotNull);
    expect(ai.sessionToken, isNull);
  });

  test('Anmeldefehler zeigen den Text des Workers', () async {
    final ai = client();
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: '');
    final account = AccountService(ai: ai, settings: settings, device: 'Test');
    handler = (_) => (401, '{"error": "Benutzername oder Passwort falsch.", "code": "wrong_login"}');
    await expectLater(
      account.login(username: 'lena', password: 'falsch-falsch'),
      throwsA(const AIClientError.http(401, 'Benutzername oder Passwort falsch.')),
    );
    handler = (_) => (429, '{"error": "Bitte in 15 Minuten erneut versuchen.", "code": "locked"}');
    await expectLater(
      account.login(username: 'lena', password: 'falsch-falsch'),
      throwsA(const AIClientError.http(429, 'Bitte in 15 Minuten erneut versuchen.')),
    );
  });

  test('Serverwechsel verwirft die Sitzung', () async {
    final ai = client(Secrets.memory({SecretKey.accountSession: 's1.alt'}));
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: '');
    expect(ai.sessionToken, isNull);
    await ai.setSession('s1.neu');
    await ai.configure(url: 'https://coach-ai.example.workers.dev/', token: '');
    expect(ai.sessionToken, 's1.neu');
  });

  test('Konto bleibt offline nach dem Neustart sichtbar', () async {
    final secrets = Secrets.memory();
    final ai = client(secrets);
    await ai.configure(url: 'https://coach-ai.example.workers.dev', token: '');
    handler = (_) => (
      200,
      '{"token": "s1.x", "account": {"id": "a1", "username": "lena", "displayName": "Lena", "isAdmin": false}, '
          '"recoveryCode": "ABCD-EFGH"}',
    );
    final code = await AccountService(
      ai: ai,
      settings: settings,
      device: 'Test',
    ).login(username: 'lena', password: 'x').then((_) => 'ok');
    expect(code, 'ok');
    final restarted = AccountService(ai: client(secrets), settings: settings, device: 'Test');
    expect(restarted.account?.displayName, 'Lena');
    expect(restarted.isSignedIn, isTrue);
  });
}

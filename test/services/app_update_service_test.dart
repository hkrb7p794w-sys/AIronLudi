// Update-Hinweis der Android-App gegen `GET /v1/app/android` (worker/src/android.ts).
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/update/app_update_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late (int, String) Function(HttpRequest request) handler;
  late FakeHttpTransport transport;
  late DateTime now;

  const body =
      '{"versionName": "2.0.57", "versionCode": 10057, "date": "2026-11-16T10:00:00Z", '
      '"notes": " Commit abc1234, Build 57. ", "url": "https://coach-ai.example.workers.dev/android/abc/"}';

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    handler = (_) => (200, body);
    transport = FakeHttpTransport((request) {
      final (status, text) = handler(request);
      return HttpResponse(status, utf8.encode(text));
    });
    now = DateTime.utc(2026, 11, 16, 12);
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  Future<AppUpdateService> service({int? installed = 10050, bool android = true, bool configured = true}) async {
    final ai = AIClient(secrets: Secrets.memory(), settings: settings, transport: transport);
    if (configured) await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'gast-token');
    return AppUpdateService(
      ai: ai,
      settings: settings,
      installedBuild: () async => installed,
      isAndroid: android,
      clock: () => now,
    );
  }

  test('liest die Antwort des Workers', () {
    final update = AndroidUpdate.fromJson(jsonDecode(body));
    expect(update?.versionName, '2.0.57');
    expect(update?.versionCode, 10057);
    expect(update?.url.toString(), 'https://coach-ai.example.workers.dev/android/abc/');
    expect(update?.notes, 'Commit abc1234, Build 57.');
    expect(AndroidUpdate.fromJson({'versionName': '1', 'versionCode': 1.5, 'url': 'https://x/'}), isNull);
    expect(AndroidUpdate.fromJson({'versionName': '1', 'versionCode': 1, 'url': 'http://x/'}), isNull);
    expect(AndroidUpdate.fromJson({'versionCode': 1, 'url': 'https://x/'}), isNull);
    expect(AndroidUpdate.fromJson('kaputt'), isNull);
  });

  test('zeigt eine neuere Version an und fragt mit dem App-Token', () async {
    final updates = await service();
    var notified = 0;
    updates.addListener(() => notified++);
    await updates.check();
    expect(updates.available?.versionName, '2.0.57');
    expect(notified, 1);
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.url.toString(), 'https://coach-ai.example.workers.dev/v1/app/android');
    expect(request.headers['Authorization'], 'Bearer gast-token');
  });

  test('gleiche oder ältere Version: kein Hinweis', () async {
    final same = await service(installed: 10057);
    await same.check();
    expect(same.available, isNull);
    final unknown = await service(installed: null);
    await unknown.check(force: true);
    expect(unknown.available, isNull);
  });

  test('„Später“ blendet diese Version aus, eine neuere erscheint wieder', () async {
    final updates = await service();
    await updates.check();
    await updates.dismiss();
    expect(updates.available, isNull);
    expect(settings.intValue(AppUpdateService.dismissedKey), 10057);
    await updates.check(force: true);
    expect(updates.available, isNull);

    handler = (_) => (200, body.replaceAll('10057', '10058').replaceAll('2.0.57', '2.0.58'));
    await updates.check(force: true);
    expect(updates.available?.versionName, '2.0.58');
  });

  test('prüft höchstens alle sechs Stunden', () async {
    final updates = await service();
    await updates.check();
    await updates.check();
    now = now.add(const Duration(hours: 5));
    await updates.check();
    expect(transport.requests, hasLength(1));
    // Hinweis bleibt in der Zwischenzeit stehen.
    expect(updates.available, isNotNull);
    now = now.add(const Duration(hours: 2));
    await updates.check();
    expect(transport.requests, hasLength(2));
    // Uhr zurückgestellt: neu prüfen statt tagelang schweigen.
    now = now.subtract(const Duration(days: 1));
    await updates.check();
    expect(transport.requests, hasLength(3));
  });

  test('ohne Android, Worker, im Demo-Modus oder bei Fehlern still', () async {
    final iphone = await service(android: false);
    await iphone.check();
    expect(iphone.isSupported, isFalse);
    await (await service()).check(isDemo: true);
    expect(transport.requests, isEmpty);

    final alone = await service(configured: false);
    await alone.check();
    expect(alone.available, isNull);

    handler = (_) => (404, '{"error": "Noch keine Android-Version hochgeladen"}');
    final old = await service();
    await old.check();
    expect(old.available, isNull);
    // Ein Fehler zählt nicht als Prüfung: beim nächsten Mal wieder fragen.
    expect(settings.date(AppUpdateService.lastCheckKey), isNull);
  });

  test('Prüfzeitpunkt und ausgeblendete Version gehören nicht zur Sicherung', () {
    expect(AppBackup.isBackedUp(AppUpdateService.lastCheckKey), isFalse);
    expect(AppBackup.isBackedUp(AppUpdateService.dismissedKey), isFalse);
  });
}

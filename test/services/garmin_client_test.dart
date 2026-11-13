// Port von `NetworkClientTests` (Garmin-Teil) und `GarminConnectSessionTests`.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/garmin/garmin_client.dart';
import 'package:aironludi/services/garmin/garmin_connect_session.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gültig bis 2100, damit es im Test nicht erneuert wird.
const longLivedToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.c2ln';

/// JWT mit `client_id` und Ablauf 2100 (Signatur egal, die App prüft sie nicht).
const connectToken =
    'eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln';

/// Ein Stub für alle Transporte, wie `StubURLProtocol` (gemeinsame Anfrageliste).
final class Stub {
  Stub(this.handler);

  (int, String) Function(HttpRequest request) handler;
  final requests = <HttpRequest>[];

  HttpTransport transport({bool cookies = false}) => FakeHttpTransport((request) {
    requests.add(request);
    final (status, body) = handler(request);
    return HttpResponse(status, utf8.encode(body));
  });
}

void main() {
  late CoachDatabase db;
  late SettingsStore settings;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  GarminConnectSession makeSession(Secrets secrets, Stub stub) =>
      GarminConnectSession(secrets: secrets, settings: settings, makeTransport: stub.transport, pause: () async {});

  group('Personal API', () {
    test('tauscht den Key gegen ein Token und nutzt Bearer', () async {
      final stub = Stub(
        (request) => request.url.path.endsWith('/token') ? (200, longLivedToken) : (200, '{"data": []}'),
      );
      final client = GarminClient(
        secrets: Secrets.memory({SecretKey.garminAPIKey: 'mein-key'}),
        transport: stub.transport(),
      );
      final range = DateRange.last(7, endingOn: const CalendarDay(2026, 10, 23));
      final json = await client.json(GarminEndpoint.dailySummaries(range));
      expect(json['data']?.raw, isEmpty);
      expect(stub.requests, hasLength(2));
      expect(stub.requests[0].method, 'POST');
      expect(stub.requests[0].headers['Authorization'], 'ApiKey mein-key');
      expect(stub.requests[1].headers['Authorization'], 'Bearer $longLivedToken');
    });

    test('nach 401 einmal mit frischem Token', () async {
      final secrets = Secrets.memory({SecretKey.garminAPIKey: 'k'});
      late Stub stub;
      stub = Stub((request) {
        if (request.url.path.endsWith('/token')) return (200, longLivedToken);
        final calls = stub.requests.where((r) => !r.url.path.endsWith('/token')).length;
        return calls == 1 ? (401, '') : (200, '{}');
      });
      final client = GarminClient(secrets: secrets, transport: stub.transport());
      await client.json(GarminEndpoint.profileSettings);
      expect(stub.requests, hasLength(4));
      expect(secrets.string(SecretKey.garminBearerToken), isNotNull);
    });

    test('abgelehnter Key wird klar gemeldet', () async {
      final stub = Stub((_) => (401, ''));
      final client = GarminClient(
        secrets: Secrets.memory({SecretKey.garminAPIKey: 'alt'}),
        transport: stub.transport(),
      );
      await expectLater(client.validToken(), throwsA(GarminAPIError.keyRejected));
    });

    test('ohne Key kein Netzwerk', () async {
      final stub = Stub((_) => (200, ''));
      final client = GarminClient(secrets: Secrets.memory(), transport: stub.transport());
      await expectLater(client.validToken(), throwsA(GarminAPIError.missingKey));
      expect(stub.requests, isEmpty);
    });

    test('Netzwerkfehler wird als GarminAPIError gemeldet', () async {
      final client = GarminClient(
        secrets: Secrets.memory({SecretKey.garminAPIKey: 'k'}),
        transport: FakeHttpTransport((_) => throw const HttpTransportException('offline')),
      );
      await expectLater(client.validToken(), throwsA(const GarminAPIError.network('offline')));
    });
  });

  group('Garmin-Konto', () {
    test('Anmeldung mit Bestätigungscode speichert Token und Anzeigenamen', () async {
      final stub = Stub(
        (request) => switch (request.url.path) {
          '/mobile/sso/en_US/sign-in' => (200, '<html></html>'),
          '/mobile/api/login' => (
            200,
            '{"responseStatus":{"type":"MFA_REQUIRED"},"customerMfaInfo":{"mfaLastMethodUsed":"email"}}',
          ),
          '/mobile/api/mfa/verifyCode' => (200, '{"responseStatus":{"type":"SUCCESSFUL"},"serviceTicketId":"ST-123"}'),
          '/di-oauth2-service/oauth/token' => (
            200,
            '{"access_token":"$connectToken","refresh_token":"r1","expires_in":3600}',
          ),
          '/userprofile-service/socialProfile' => (200, '{"displayName":"alex-123"}'),
          _ => (404, ''),
        },
      );
      final secrets = Secrets.memory();
      final session = makeSession(secrets, stub);

      final first = await session.login(email: ' alex@example.com ', password: 'geheim');
      expect(first, const ConnectNeedsCode('email'));
      expect(session.isLoggedIn, isFalse);
      final second = await session.submitCode('123456');

      expect(second, const ConnectLoggedIn());
      expect(session.isLoggedIn, isTrue);
      expect(session.displayName, 'alex-123');
      expect(session.email, 'alex@example.com');
      final stored = secrets.string(SecretKey.garminConnectToken);
      expect(stored, contains('r1'));
      // Das Passwort landet nirgends im Speicher.
      expect(stored, isNot(contains('geheim')));
      final login = stub.requests.firstWhere((r) => r.url.path == '/mobile/api/login');
      expect(login.headers['Origin'], 'https://sso.garmin.com');
      final exchange = stub.requests.firstWhere((r) => r.url.path == '/di-oauth2-service/oauth/token');
      expect(exchange.headers['Authorization'], startsWith('Basic '));
      expect(stub.requests.last.headers['Authorization'], 'Bearer $connectToken');
    });

    test('falsches Passwort wird gemeldet', () async {
      final stub = Stub(
        (request) => request.url.path == '/mobile/api/login'
            ? (200, '{"responseStatus":{"type":"INVALID_USERNAME_PASSWORD"}}')
            : (200, ''),
      );
      final session = makeSession(Secrets.memory(), stub);
      await expectLater(
        session.login(email: 'a@b.de', password: 'falsch'),
        throwsA(GarminConnectError.invalidCredentials),
      );
      expect(session.isLoggedIn, isFalse);
    });

    test('Konto zuerst, bei Fehler springt die Personal API ein', () async {
      final token = ConnectToken(
        accessToken: connectToken,
        refreshToken: 'r1',
        clientID: 'GARMIN_CONNECT_MOBILE_IOS_DI',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(4102444800 * 1000, isUtc: true),
      );
      final secrets = Secrets.memory({
        SecretKey.garminConnectToken: jsonEncode(token.toJson()),
        SecretKey.garminAPIKey: 'key',
      });
      final stub = Stub((request) {
        if (request.url.host == 'connectapi.garmin.com') {
          return request.url.path == '/userprofile-service/userprofile/settings' ? (403, '') : (200, '{"ok":1}');
        }
        return request.url.path.endsWith('/token') ? (200, longLivedToken) : (200, '{"fallback":1}');
      });
      final client = GarminClient(secrets: secrets, transport: stub.transport(), connect: makeSession(secrets, stub));

      final viaAccount = await client.json(GarminEndpoint.heartRateZones);
      expect(viaAccount['ok']?.doubleValue, 1);
      final viaFallback = await client.json(GarminEndpoint.profileSettings);
      expect(viaFallback['fallback']?.doubleValue, 1);
      expect(client.sources[GarminSource.connect], 1);
      expect(client.sources[GarminSource.personalAPI], 1);
      expect(client.lastConnectError, isNotNull);
      // Abrufe aufs Konto tragen die Kopfzeilen der Garmin-App.
      final accountCall = stub.requests.firstWhere((r) => r.url.host == 'connectapi.garmin.com');
      expect(accountCall.headers['X-Garmin-Client-Platform'], 'Android');
    });
  });
}

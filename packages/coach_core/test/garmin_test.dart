// Port von GarminEndpointTests.swift, SyncPlanTests.swift, GarminConnectTests.swift und den Endpunkt-Prüfungen aus
// MetricsAndZonesTests.swift und BodyBatteryTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

DateTime seconds(num value) => DateTime.fromMicrosecondsSinceEpoch((value * 1000000).round(), isUtc: true);

void main() {
  group('Endpunkte der Personal API', () {
    final range = DateRange(const CalendarDay(2026, 9, 1), const CalendarDay(2026, 10, 22));

    test('Token-Tausch wie im offiziellen Client', () {
      final request = GarminEndpoint.tokenExchange.request;
      expect(request.method, 'POST');
      expect(request.path, '/personalapitoken-service/personal-api/personal-api-key/token');
      expect(
        request.url().toString(),
        'https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token',
      );
    });

    test('Bereiche über Parameter oder Pfad', () {
      expect(
        GarminEndpoint.dailySummaries(range).request.url().toString(),
        'https://personal.connectapi.garmin.com/usersummary-service/v2/dailysummaries'
        '?startDate=2026-09-01&endDate=2026-10-22',
      );
      final hrv = GarminEndpoint.hrvSummaries(range).request;
      expect(hrv.path, '/hrv-service/hrv/daily/2026-09-01/2026-10-22');
      expect(hrv.query, isEmpty);
      final sleep = GarminEndpoint.dailySleep(range.end).request;
      expect(sleep.path, '/sleep-service/sleep/dailySleep');
      expect(sleep.query, [const GarminQueryItem('date', '2026-10-22')]);
      const today = CalendarDay(2026, 10, 22);
      expect(GarminEndpoint.spo2(today).request.path, '/wellness-service/wellness/daily/spo2acclimation/2026-10-22');
      expect(GarminEndpoint.fitnessAge(today).request.path, '/fitnessage-service/fitnessage/v2/2026-10-22');
    });

    test('Aktivitätsseite ist begrenzt', () {
      expect(GarminEndpoint.activities(start: 0, limit: 200).request.query.last, const GarminQueryItem('limit', '50'));
    });

    test('Bereichsgrenzen', () {
      expect(GarminEndpoint.sleepSummaries(range).maxDays, 28);
      expect(GarminEndpoint.hrvSummaries(range).maxDays, 180);
      expect(GarminEndpoint.hrv(range.end).maxDays, isNull);
    });

    test('Blöcke decken den Bereich ab, neueste zuerst', () {
      final chunks = range.chunks(28);
      expect(range.dayCount, 52);
      expect(chunks.length, 2);
      expect(chunks[0], DateRange(const CalendarDay(2026, 9, 25), range.end));
      expect(chunks[1], DateRange(range.start, const CalendarDay(2026, 9, 24)));
      expect(chunks.fold(0, (sum, chunk) => sum + chunk.dayCount), 52);
    });

    test('Kalenderrechnung über Monats- und Jahresgrenzen', () {
      final newYear = const CalendarDay(2026, 12, 31).adding(1);
      expect(newYear, const CalendarDay(2027, 1, 1));
      expect(const CalendarDay(2026, 3, 1).adding(-1), const CalendarDay(2026, 2, 28));
      expect(DateRange.last(7, endingOn: newYear).start, const CalendarDay(2026, 12, 26));
      expect(CalendarDay.tryParse('2026-10-22T00:00:00.0'), const CalendarDay(2026, 10, 22));
      expect(CalendarDay.tryParse('22.10.2026'), isNull);
    });

    test('Ablauf des Tokens aus dem JWT', () {
      // Payload {"sub":"x","exp":1761220800} (2025-10-23T12:00:00Z), Base64URL ohne Padding.
      const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4IiwiZXhwIjoxNzYxMjIwODAwfQ.c2ln';
      final parsed = GarminBearerToken.fromResponse('  $token\n')!;
      expect(parsed.value, token);
      expect(parsed.expiresAt, seconds(1761220800));
      expect(parsed.needsRefresh(now: seconds(1761220800 - 3000)), isTrue);
      expect(parsed.needsRefresh(now: seconds(1761220800 - 7200)), isFalse);
      expect(GarminBearerToken.fromJson(jsonDecode(jsonEncode(parsed.toJson()))), parsed);
    });

    test('Token ohne JWT nutzt die Ersatzdauer', () {
      final now = seconds(1000);
      final parsed = GarminBearerToken.fromResponse('opaque', now: now)!;
      expect(parsed.expiresAt, now.add(GarminBearerToken.fallbackLifetime));
      expect(GarminBearerToken.fromResponse(' \n'), isNull);
    });

    test('Statuscodes', () {
      final cases = <(int, bool, GarminAPIError?)>[
        (200, false, null),
        (401, true, GarminAPIError.keyRejected),
        (403, false, GarminAPIError.unauthorized),
        (429, false, GarminAPIError.rateLimited),
        (400, false, const GarminAPIError.rejectedRequest(400)),
        (503, false, const GarminAPIError.server(503)),
      ];
      for (final (status, isTokenExchange, expected) in cases) {
        expect(GarminAPIError.from(status: status, isTokenExchange: isTokenExchange), expected);
      }
      expect(const GarminAPIError.server(503).message, 'Garmin-Server-Fehler (HTTP 503).');
    });
  });

  group('Abrufplanung', () {
    const today = CalendarDay(2026, 10, 23);

    test('erster Abruf holt 60 Tage', () {
      final range = SyncPlan.range(latestStored: null, today: today);
      expect(range.end, today);
      expect(range.dayCount, 60);
    });

    test('spätere Abrufe überlappen zwei Tage', () {
      final range = SyncPlan.range(latestStored: today.adding(-1), today: today);
      expect(range.start, today.adding(-3));
      expect(range.end, today);
    });

    test('lange Pause höchstens 60 Tage', () {
      expect(SyncPlan.range(latestStored: today.adding(-200), today: today).dayCount, 60);
    });

    test('Daten aus der Zukunft: wieder der erste Zeitraum', () {
      expect(SyncPlan.range(latestStored: today.adding(5), today: today).dayCount, 60);
    });

    test('fällig nach dem Abstand', () {
      final now = seconds(10000);
      expect(SyncPlan.isDue(lastSync: null, now: now), isTrue);
      expect(SyncPlan.isDue(lastSync: now.subtract(const Duration(seconds: 60)), now: now), isFalse);
      expect(SyncPlan.isDue(lastSync: now.subtract(const Duration(minutes: 16)), now: now), isTrue);
      expect(SyncPlan.isDue(lastSync: now.add(const Duration(hours: 1)), now: now), isTrue);
    });

    test('Blättern endet bei bekannten oder alten Aktivitäten', () {
      final page = [
        for (var index = 0; index < 3; index++)
          GarminActivity(100 - index)..startLocal = '${today.adding(-index).iso} 07:00:00',
      ];
      final start = today.adding(-10);
      expect(
        SyncPlan.shouldLoadNextPage(page: page, pageSize: 3, knownIDs: {}, rangeStart: start, pagesLoaded: 1),
        isTrue,
      );
      expect(
        SyncPlan.shouldLoadNextPage(page: page, pageSize: 4, knownIDs: {}, rangeStart: start, pagesLoaded: 1),
        isFalse,
      );
      expect(
        SyncPlan.shouldLoadNextPage(page: page, pageSize: 3, knownIDs: {99}, rangeStart: start, pagesLoaded: 1),
        isFalse,
      );
      expect(
        SyncPlan.shouldLoadNextPage(
          page: page,
          pageSize: 3,
          knownIDs: {},
          rangeStart: today.adding(-1),
          pagesLoaded: 1,
        ),
        isFalse,
      );
      expect(
        SyncPlan.shouldLoadNextPage(page: page, pageSize: 3, knownIDs: {}, rangeStart: start, pagesLoaded: 6),
        isFalse,
      );
    });
  });

  // Anfragen und Antworten des inoffiziellen Zugangs, abgeglichen mit python-garminconnect 0.3.20
  // (`client/sso.py`, `client/session.py`, `client/constants.py`).
  group('Garmin-Connect-Zugang', () {
    Map<String, Object?> body(ConnectRequest request) => jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;

    test('Anmeldung wie der mobile Ablauf', () {
      final page = GarminConnect.signInPage;
      expect(page.method, 'GET');
      expect(page.url.host, 'sso.garmin.com');
      expect(page.url.path, '/mobile/sso/en_US/sign-in');
      expect(page.url.queryParameters['clientId'], 'GCM_IOS_DARK');

      final login = GarminConnect.login(email: 'a@b.de', password: 'p&ss');
      expect(login.method, 'POST');
      expect(login.url.path, '/mobile/api/login');
      expect(login.url.queryParameters['service'], 'https://mobile.integration.garmin.com/gcm/ios');
      expect(login.url.queryParameters['locale'], 'en-US');
      expect(login.headers['Referer'], page.url.toString());
      expect(login.headers['Content-Type'], 'application/json');
      expect(body(login)['username'], 'a@b.de');
      expect(body(login)['password'], 'p&ss');
      expect(body(login)['rememberMe'], true);

      final code = GarminConnect.verifyCode('123456', method: 'email');
      expect(code.url.path, '/mobile/api/mfa/verifyCode');
      expect(body(code)['mfaVerificationCode'], '123456');
      expect(body(code)['mfaMethod'], 'email');
    });

    test('Antworten der Anmeldung werden eingeordnet', () {
      LoginResult result(int status, String text) => GarminConnect.loginResult(status: status, body: utf8.encode(text));
      expect(
        result(200, '{"responseStatus":{"type":"SUCCESSFUL"},"serviceTicketId":"ST-1"}'),
        const LoginTicket('ST-1'),
      );
      expect(
        result(200, '{"responseStatus":{"type":"MFA_REQUIRED"},"customerMfaInfo":{"mfaLastMethodUsed":"sms"}}'),
        const LoginNeedsCode('sms'),
      );
      expect(result(200, '{"responseStatus":{"type":"MFA_REQUIRED"}}'), const LoginNeedsCode('email'));
      expect(result(200, '{"responseStatus":{"type":"INVALID_USERNAME_PASSWORD"}}'), const LoginInvalidCredentials());
      expect(result(200, '{"responseStatus":{"type":"CAPTCHA_REQUIRED"}}'), isA<LoginBlocked>());
      expect(result(429, ''), isA<LoginBlocked>());
      expect(result(403, '<html>'), isA<LoginBlocked>());
      expect(result(200, '{"error":{"status-code":"429"}}'), isA<LoginBlocked>());
      expect(result(200, '<html>'), isA<LoginUnexpected>());
      expect(result(200, '{"responseStatus":{"type":"SUCCESSFUL"}}'), isA<LoginUnexpected>());
    });

    test('Token-Tausch und Erneuerung', () {
      final exchange = GarminConnect.exchange(ticket: 'ST-1', clientID: 'GARMIN_CONNECT_MOBILE_IOS_DI');
      expect(exchange.url.toString(), 'https://diauth.garmin.com/di-oauth2-service/oauth/token');
      expect(exchange.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('GARMIN_CONNECT_MOBILE_IOS_DI:'))}');
      expect(exchange.headers['Content-Type'], 'application/x-www-form-urlencoded');
      final form = utf8.decode(exchange.body!);
      expect(form, contains('service_ticket=ST-1'));
      expect(form, contains('service_url=https%3A%2F%2Fmobile.integration.garmin.com%2Fgcm%2Fios'));
      expect(
        form,
        contains('grant_type=https%3A%2F%2Fconnectapi.garmin.com%2Fdi-oauth2-service%2Foauth%2Fgrant%2Fservice_ticket'),
      );
      final token = ConnectToken(accessToken: 'a', refreshToken: 'r+1', clientID: 'C', expiresAt: seconds(0));
      expect(
        utf8.decode(GarminConnect.refresh(token)!.body!),
        'grant_type=refresh_token&client_id=C&refresh_token=r%2B1',
      );
      final withoutRefresh = ConnectToken(accessToken: 'a', refreshToken: null, clientID: 'C', expiresAt: seconds(0));
      expect(GarminConnect.refresh(withoutRefresh), isNull);
    });

    test('Token liest die JWT-Angaben', () {
      // Payload {"client_id":"GARMIN_CONNECT_MOBILE_IOS_DI","exp":4102444800}
      const jwt =
          'eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln';
      final token = ConnectToken.fromResponse(
        utf8.encode('{"access_token":"$jwt","refresh_token":"r"}'),
        clientID: 'OTHER',
      )!;
      expect(token.clientID, 'GARMIN_CONNECT_MOBILE_IOS_DI');
      expect(token.expiresAt, seconds(4102444800));
      expect(token.needsRefresh(now: seconds(4102444800 - 3600)), isFalse);
      expect(token.needsRefresh(now: seconds(4102444800 - 600)), isTrue);
      final now = seconds(1000);
      final plain = ConnectToken.fromResponse(
        utf8.encode('{"access_token":"x","expires_in":7200}'),
        clientID: 'C',
        now: now,
      )!;
      expect(plain.clientID, 'C');
      expect(plain.expiresAt, now.add(const Duration(seconds: 7200)));
      expect(ConnectToken.fromResponse(utf8.encode('{}'), clientID: 'C'), isNull);
      expect(ConnectToken.fromJson(jsonDecode(jsonEncode(token.toJson()))), token);
    });

    test('Abrufe mit Bearer und Connect-Pfaden', () {
      final token = ConnectToken(accessToken: 'abc', refreshToken: null, clientID: 'C', expiresAt: DateTime.utc(9999));
      const day = CalendarDay(2026, 10, 26);
      const readiness = ConnectEndpoint.trainingReadiness(day);
      final request = GarminConnect.apiRequest(
        path: readiness.path,
        query: readiness.query,
        token: token,
        accept: 'application/json',
      );
      expect(
        request.url.toString(),
        'https://connectapi.garmin.com/metrics-service/metrics/trainingreadiness/2026-10-26',
      );
      expect(request.headers['Authorization'], 'Bearer abc');
      expect(request.headers['X-Garmin-Client-Platform'], 'Android');
      const endurance = ConnectEndpoint.enduranceScore(day);
      expect(
        GarminConnect.apiRequest(
          path: endurance.path,
          query: endurance.query,
          token: token,
          accept: 'application/json',
        ).url.toString(),
        'https://connectapi.garmin.com/metrics-service/metrics/endurancescore?calendarDate=2026-10-26',
      );
      expect(
        const ConnectEndpoint.racePredictions(displayName: 'a/b').path,
        '/metrics-service/metrics/racepredictions/latest/ab',
      );
      expect(const ConnectEndpoint.userSummary(displayName: 'alex', day: day).query.first.value, '2026-10-26');
      final weights = ConnectEndpoint.weightRange(start: day.adding(-27), end: day);
      expect(weights.path, '/weight-service/weight/range/2026-09-29/2026-10-26');
      expect(weights.query.first.name, 'includeAll');
      expect(GarminConnect.exerciseSetsPath(42), '/activity-service/activity/42/exerciseSets');
    });

    test('Werte nur aus Garmin Connect', () {
      const day = CalendarDay(2026, 10, 26);
      final readiness = GarminConnectMetrics.trainingReadiness(
        JsonValue.parse('[{"calendarDate":"2026-10-26","score":71,"level":"HIGH"}]'),
        day,
      );
      expect(readiness[day]?.trainingReadiness, 71);
      expect(readiness[day]?.trainingReadinessLevel, 'HIGH');
      expect(GarminConnectMetrics.trainingReadiness(JsonValue.parse('[]'), day), isEmpty);
      final status = GarminConnectMetrics.trainingStatus(
        JsonValue.parse(
          '{"mostRecentTrainingStatus":{"latestTrainingStatusData":{"3442":{"trainingStatusFeedbackPhrase":"PRODUCTIVE_3"}}}}',
        ),
        day,
      );
      expect(status[day]?.trainingStatus, 'PRODUCTIVE_3');
      expect(GarminConnectMetrics.trainingStatusGerman('PRODUCTIVE_3'), 'Produktiv');
      expect(GarminConnectMetrics.trainingStatusGerman('UNPRODUCTIVE_1'), 'Unproduktiv');
      expect(GarminConnectMetrics.trainingStatusGerman('NEW_THING'), 'New Thing');
      expect(
        GarminConnectMetrics.enduranceScore(JsonValue.parse('{"overallScore":6512}'), day)[day]?.enduranceScore,
        6512,
      );
      expect(
        GarminConnectMetrics.enduranceScore(
          JsonValue.parse('{"enduranceScoreDTO":{"overallScore":6400}}'),
          day,
        )[day]?.enduranceScore,
        6400,
      );
      final predictions = RacePredictions.fromGarmin(
        JsonValue.parse(
          '{"calendarDate":"2026-10-26","time5K":1250,"time10K":2620,"timeHalfMarathon":5900,"timeMarathon":12600}',
        ),
      )!;
      expect(predictions.fiveK, 1250);
      expect(predictions.marathon, 12600);
      expect(predictions.day, day);
      expect(RacePredictions.fromGarmin(JsonValue.parse('{}')), isNull);
    });

    test('Erholungszeit und Trainingsbelastung (BodyBatteryTests)', () {
      const day = CalendarDay(2026, 4, 21);
      final readiness = JsonValue.parse('[{"score": 60, "level": "MODERATE", "recoveryTime": 1260}]');
      expect(GarminConnectMetrics.trainingReadiness(readiness, day)[day]?.recoveryHours, 21);
      final recovered = JsonValue.parse(
        '[{"score": 80, "recoveryTime": 900, "recoveryTimeChangePhrase": "REACHED_ZERO"}]',
      );
      expect(GarminConnectMetrics.trainingReadiness(recovered, day)[day]?.recoveryHours, 0);
      final status = JsonValue.parse(
        '{"mostRecentTrainingStatus": {"latestTrainingStatusData": {"123": {'
        '"trainingStatusFeedbackPhrase": "PRODUCTIVE_3",'
        '"acuteTrainingLoadDTO": {"dailyTrainingLoadAcute": 512, "dailyTrainingLoadChronic": 430}}}}}',
      );
      final metrics = GarminConnectMetrics.trainingStatus(status, day)[day]!;
      expect(metrics.acuteLoad, 512);
      expect(metrics.chronicLoad, 430);
    });

    test('Readiness aus den Werten fließt in die Empfehlung', () {
      final metrics = DailyMetrics(const CalendarDay(2026, 10, 26))
        ..hrvStatus = 'BALANCED'
        ..trainingReadiness = 20;
      final recommendation = RecoveryEvaluator.evaluate(metrics, restingHeartRate7DayAverage: null);
      expect(recommendation.level, RecoveryLevel.pause);
      expect(recommendation.reasons.any((reason) => reason.startsWith('Readiness 20')), isTrue);
    });
  });
}

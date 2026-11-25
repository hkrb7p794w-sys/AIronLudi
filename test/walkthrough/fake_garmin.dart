// Nachgebauter Garmin-Server für Durchläufe: Anmeldung mit Bestätigungscode (SSO, Token-Tausch) und Connect-API mit
// einem Lauf von heute, Tageswerten, Schlaf und Trainingsbereitschaft. Unbekannte Endpunkte antworten leer.
import 'dart:convert';

import 'package:aironludi/services/http/http_transport.dart';
import 'package:coach_core/coach_core.dart';

/// JWT mit `client_id` und Ablauf 2100 (die App prüft die Signatur nicht).
const _connectToken =
    'eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln';

final class FakeGarmin {
  final requests = <String>[];

  /// Fabrik für `garminTransportProvider` (Anmeldung und API teilen sich die Anfrageliste).
  HttpTransport transport({bool cookies = false}) => FakeHttpTransport(_handle);

  HttpResponse _json(Object body) => HttpResponse(200, utf8.encode(jsonEncode(body)));

  HttpResponse _handle(HttpRequest request) {
    final path = request.url.path;
    requests.add('${request.method} ${request.url.host}$path');
    final today = CalendarDay.today().iso;
    switch (path) {
      case '/mobile/sso/en_US/sign-in':
        return HttpResponse(200, utf8.encode('<html></html>'));
      case '/mobile/api/login':
        return _json({
          'responseStatus': {'type': 'MFA_REQUIRED'},
          'customerMfaInfo': {'mfaLastMethodUsed': 'email'},
        });
      case '/mobile/api/mfa/verifyCode':
        return _json({
          'responseStatus': {'type': 'SUCCESSFUL'},
          'serviceTicketId': 'ST-123',
        });
      case '/di-oauth2-service/oauth/token':
        return _json({'access_token': _connectToken, 'refresh_token': 'r1', 'expires_in': 3600});
      case '/userprofile-service/socialProfile':
        return _json({'displayName': 'lena-garmin'});
      case '/activitylist-service/activities/search/activities':
        return _json([
          {
            'activityId': 9001,
            'activityName': 'Garmin-Lauf am Morgen',
            'startTimeLocal': '$today 06:30:00',
            'activityType': {'typeKey': 'running'},
            'duration': 2400.0,
            'distance': 8000.0,
            'averageHR': 142.0,
          },
        ]);
    }
    if (path.startsWith('/usersummary-service/usersummary/daily/')) {
      return _json({'calendarDate': request.url.queryParameters['calendarDate'] ?? today, 'restingHeartRate': 47});
    }
    if (path.startsWith('/wellness-service/wellness/dailySleepData/')) {
      return _json({
        'dailySleepDTO': {'calendarDate': request.url.queryParameters['date'] ?? today, 'sleepTimeSeconds': 27000},
      });
    }
    if (path.startsWith('/metrics-service/metrics/trainingreadiness/')) {
      return _json([
        {'calendarDate': path.split('/').last, 'score': 74, 'level': 'HIGH'},
      ]);
    }
    return HttpResponse(200, utf8.encode(path.contains('list') || path.contains('range') ? '[]' : '{}'));
  }
}

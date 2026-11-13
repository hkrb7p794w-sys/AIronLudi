import 'dart:convert';
import 'dart:typed_data';

import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../util/swift_date.dart';
import 'daily_metrics.dart';
import 'garmin_endpoint.dart';

/// HTTP-Anfrage mit vollständiger Adresse (verschiedene Garmin-Hosts).
final class ConnectRequest {
  const ConnectRequest({required this.method, required this.url, required this.headers, this.body});

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Uint8List? body;

  @override
  String toString() => 'ConnectRequest($method $url)';
}

/// Ergebnis der Anmeldung.
sealed class LoginResult {
  const LoginResult();
}

final class LoginTicket extends LoginResult {
  const LoginTicket(this.ticket);

  final String ticket;

  @override
  bool operator ==(Object other) => other is LoginTicket && other.ticket == ticket;

  @override
  int get hashCode => ticket.hashCode;
}

/// Bestätigungscode nötig; [method] z. B. `email` oder `sms`.
final class LoginNeedsCode extends LoginResult {
  const LoginNeedsCode(this.method);

  final String method;

  @override
  bool operator ==(Object other) => other is LoginNeedsCode && other.method == method;

  @override
  int get hashCode => method.hashCode;
}

final class LoginInvalidCredentials extends LoginResult {
  const LoginInvalidCredentials();

  @override
  bool operator ==(Object other) => other is LoginInvalidCredentials;

  @override
  int get hashCode => 0;
}

/// Garmin blockiert (Captcha, Cloudflare, Rate-Limit) – später erneut versuchen.
final class LoginBlocked extends LoginResult {
  const LoginBlocked(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) => other is LoginBlocked && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

final class LoginUnexpected extends LoginResult {
  const LoginUnexpected(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) => other is LoginUnexpected && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

JsonValue? _jwtClaim(String token, String name) {
  final parts = token.split('.').where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return null;
  var base64 = parts[1].replaceAll('-', '+').replaceAll('_', '/');
  base64 += '=' * ((4 - base64.length % 4) % 4);
  try {
    return JsonValue(jsonDecode(utf8.decode(base64Decode(base64))))[name];
  } on FormatException {
    return null;
  }
}

/// DI-OAuth2-Token; liegt nur im sicheren Speicher.
final class ConnectToken {
  const ConnectToken({
    required this.accessToken,
    required this.refreshToken,
    required this.clientID,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final String clientID;
  final DateTime expiresAt;

  /// Antwort des Token-Endpunkts; `client_id` aus dem JWT hat Vorrang (wie im Vorbild).
  static ConnectToken? fromResponse(List<int> body, {required String clientID, DateTime? now}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
    final json = JsonValue(decoded);
    final access = json['access_token']?.stringValue;
    if (access == null || access.isEmpty) return null;
    final current = now ?? DateTime.now();
    final DateTime expiresAt;
    if (_jwtClaim(access, 'exp')?.doubleValue case final exp?) {
      expiresAt = DateTime.fromMicrosecondsSinceEpoch((exp * 1000000).round(), isUtc: true);
    } else if (json['expires_in']?.doubleValue case final seconds?) {
      expiresAt = current.add(Duration(microseconds: (seconds * 1000000).round()));
    } else {
      expiresAt = current.add(const Duration(hours: 1));
    }
    return ConnectToken(
      accessToken: access,
      refreshToken: json['refresh_token']?.stringValue,
      clientID: _jwtClaim(access, 'client_id')?.stringValue ?? clientID,
      expiresAt: expiresAt,
    );
  }

  /// Erneuern, wenn weniger als 15 Minuten bleiben (`_token_expires_soon`).
  bool needsRefresh({DateTime? now}) => expiresAt.difference(now ?? DateTime.now()).inMicroseconds < 900 * 1000000;

  static JsonValue? jwtClaim(String token, String name) => _jwtClaim(token, name);

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': ?refreshToken,
    'clientID': clientID,
    'expiresAt': swiftDateToJson(expiresAt),
  };

  static ConnectToken? fromJson(Object? json) {
    if (json is! Map) return null;
    final (access, refresh, client) = (json['accessToken'], json['refreshToken'], json['clientID']);
    final expiresAt = swiftDateFromJson(json['expiresAt']);
    if (access is! String || client is! String || expiresAt == null) return null;
    if (refresh != null && refresh is! String) return null;
    return ConnectToken(accessToken: access, refreshToken: refresh as String?, clientID: client, expiresAt: expiresAt);
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectToken &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.clientID == clientID &&
      other.expiresAt.isAtSameMomentAs(expiresAt);

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, clientID, expiresAt.microsecondsSinceEpoch);
}

/// Inoffizieller Zugang zu Garmin Connect wie die Garmin-Connect-App auf dem iPhone (Anmeldung mit E-Mail und
/// Passwort, optional Bestätigungscode). Liefert mehr als die Personal API (Training Readiness, Trainingsstatus,
/// Endurance Score, Wettkampfprognosen). Die Personal API bleibt der Rückfallweg.
///
/// Ablauf nach python-garminconnect 0.3.20 (Strategie „mobile“, `client/sso.py`, `client/session.py`,
/// `client/constants.py`, Stand 23.10.2026), seit Garmin im März 2026 den alten OAuth1-Weg (garth) abgeschaltet hat:
/// 1. `GET sso.garmin.com/mobile/sso/en_US/sign-in` (setzt Cookies, wie die WebView der App),
/// 2. `POST sso.garmin.com/mobile/api/login` mit JSON → Service-Ticket oder `MFA_REQUIRED`,
/// 3. ggf. `POST …/mobile/api/mfa/verifyCode`,
/// 4. Ticket gegen ein DI-OAuth2-Token tauschen (`diauth.garmin.com`), Erneuerung per Refresh-Token,
/// 5. Abrufe auf `connectapi.garmin.com` mit `Authorization: Bearer`.
abstract final class GarminConnect {
  static const ssoBase = 'https://sso.garmin.com';
  static const apiBase = 'https://connectapi.garmin.com';
  static const ssoClientID = 'GCM_IOS_DARK';
  static const serviceURL = 'https://mobile.integration.garmin.com/gcm/ios';
  static const loginUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
  static const grantType = 'https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket';

  /// Reihenfolge wie im Vorbild, die iOS-Kennung zuerst (die App läuft auf einem iPhone).
  static const diClientIDs = [
    'GARMIN_CONNECT_MOBILE_IOS_DI',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI',
  ];

  // Anmeldung

  /// Adresse aus festen Garmin-Hosts; [base] ist immer eine der Konstanten oben. Werte werden wie bei
  /// `URLComponents` prozentkodiert (Leerzeichen als `%20`).
  static Uri url(String base, String path, [List<(String, String)> query = const []]) {
    final host = base.replaceAll('https://', '').split('/').first;
    final uri = Uri(scheme: 'https', host: host, path: path);
    if (query.isEmpty) return uri;
    final encoded = query.map((item) => '${Uri.encodeComponent(item.$1)}=${Uri.encodeComponent(item.$2)}').join('&');
    return Uri.parse('$uri?$encoded');
  }

  static List<(String, String)> get signInQuery => const [('clientId', ssoClientID), ('service', serviceURL)];

  static List<(String, String)> get apiQuery => const [
    ('clientId', ssoClientID),
    ('locale', 'en-US'),
    ('service', serviceURL),
  ];

  static ConnectRequest get signInPage => ConnectRequest(
    method: 'GET',
    url: url(ssoBase, '/mobile/sso/en_US/sign-in', signInQuery),
    headers: const {
      'User-Agent': loginUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  );

  static Map<String, String> get jsonHeaders => {
    'User-Agent': loginUserAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Content-Type': 'application/json',
    'Origin': ssoBase,
    'Referer': signInPage.url.toString(),
  };

  static Uint8List _json(Object value) => Uint8List.fromList(utf8.encode(jsonEncode(value)));

  static ConnectRequest login({required String email, required String password}) => ConnectRequest(
    method: 'POST',
    url: url(ssoBase, '/mobile/api/login', apiQuery),
    headers: jsonHeaders,
    body: _json({'username': email, 'password': password, 'rememberMe': true, 'captchaToken': ''}),
  );

  static ConnectRequest verifyCode(String code, {required String method}) => ConnectRequest(
    method: 'POST',
    url: url(ssoBase, '/mobile/api/mfa/verifyCode', apiQuery),
    headers: jsonHeaders,
    body: _json({
      'mfaMethod': method,
      'mfaVerificationCode': code,
      'rememberMyBrowser': true,
      'reconsentList': <Object?>[],
      'mfaSetup': false,
    }),
  );

  /// Antwort von `/mobile/api/login` und `/mfa/verifyCode`.
  static LoginResult loginResult({required int status, required List<int> body}) {
    if (status == 429 || status == 427) return LoginBlocked('zu viele Anmeldeversuche (HTTP $status)');
    if (status == 403) return const LoginBlocked('Garmin hat die Anmeldung blockiert (HTTP 403)');
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } on FormatException {
      return LoginUnexpected('keine JSON-Antwort (HTTP $status)');
    }
    final json = JsonValue(decoded);
    if (json['error']?['status-code']?.stringValue == '429') return const LoginBlocked('zu viele Anmeldeversuche');
    final type = json['responseStatus']?['type']?.stringValue;
    switch (type) {
      case 'SUCCESSFUL':
        final ticket = json['serviceTicketId']?.stringValue;
        if (ticket == null || ticket.isEmpty) return const LoginUnexpected('Anmeldung ohne Ticket');
        return LoginTicket(ticket);
      case 'MFA_REQUIRED':
        return LoginNeedsCode(json['customerMfaInfo']?['mfaLastMethodUsed']?.stringValue ?? 'email');
      case 'INVALID_USERNAME_PASSWORD':
        return const LoginInvalidCredentials();
      case 'CAPTCHA_REQUIRED':
        return const LoginBlocked('Garmin verlangt ein Captcha');
      default:
        return LoginUnexpected('HTTP $status, Status ${type ?? 'unbekannt'}');
    }
  }

  // Token

  /// Kopfzeilen der Garmin-Connect-App für Token- und API-Abrufe (`_native_headers`).
  static Map<String, String> get nativeHeaders => {
    'User-Agent': 'GCM-Android-5.23',
    'X-Garmin-User-Agent':
        'com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0',
    'X-Garmin-Paired-App-Version': '10861',
    'X-Garmin-Client-Platform': 'Android',
    'X-App-Ver': '10861',
    'X-Lang': 'en',
    'X-GCExperience': 'GC5',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Formular wie `addingPercentEncoding(withAllowedCharacters: .alphanumerics + "-._~")`.
  static Uint8List form(List<(String, String)> fields) {
    String encode(String value) {
      final buffer = StringBuffer();
      for (final rune in value.runes) {
        final character = String.fromCharCode(rune);
        final isAllowed =
            (rune >= 0x30 && rune <= 0x39) ||
            (rune >= 0x41 && rune <= 0x5A) ||
            (rune >= 0x61 && rune <= 0x7A) ||
            '-._~'.contains(character) ||
            // `CharacterSet.alphanumerics` umfasst auch Buchstaben und Ziffern außerhalb von ASCII.
            (rune > 0x7F && RegExp(r'^[\p{L}\p{N}\p{M}]$', unicode: true).hasMatch(character));
        if (isAllowed) {
          buffer.write(character);
        } else {
          for (final byte in utf8.encode(character)) {
            buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
          }
        }
      }
      return buffer.toString();
    }

    return Uint8List.fromList(utf8.encode(fields.map((field) => '${field.$1}=${encode(field.$2)}').join('&')));
  }

  static ConnectRequest tokenRequest({
    required String clientID,
    required List<(String, String)> fields,
    required String accept,
  }) => ConnectRequest(
    method: 'POST',
    url: url('https://diauth.garmin.com', '/di-oauth2-service/oauth/token'),
    headers: {
      ...nativeHeaders,
      'Authorization': 'Basic ${base64Encode(utf8.encode('$clientID:'))}',
      'Accept': accept,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cache-Control': 'no-cache',
    },
    body: form(fields),
  );

  static ConnectRequest exchange({required String ticket, required String clientID}) => tokenRequest(
    clientID: clientID,
    fields: [
      ('client_id', clientID),
      ('service_ticket', ticket),
      ('grant_type', grantType),
      ('service_url', serviceURL),
    ],
    accept: 'application/json,text/html;q=0.9,*/*;q=0.8',
  );

  static ConnectRequest? refresh(ConnectToken token) {
    final refreshToken = token.refreshToken;
    if (refreshToken == null) return null;
    return tokenRequest(
      clientID: token.clientID,
      fields: [('grant_type', 'refresh_token'), ('client_id', token.clientID), ('refresh_token', refreshToken)],
      accept: 'application/json',
    );
  }

  // Abrufe

  /// Abruf auf connectapi; die Pfade der Personal API sind dieselben wie in Garmin Connect.
  static ConnectRequest apiRequest({
    required String path,
    required List<GarminQueryItem> query,
    required ConnectToken token,
    required String accept,
  }) => ConnectRequest(
    method: 'GET',
    url: url(apiBase, path, [for (final item in query) (item.name, item.value)]),
    headers: {...nativeHeaders, 'Authorization': 'Bearer ${token.accessToken}', 'Accept': accept},
  );

  /// JSON an connectapi senden (z. B. PUT der Sätze einer Aktivität).
  static ConnectRequest jsonRequest({
    required String method,
    required String path,
    required List<int> body,
    required ConnectToken token,
  }) => ConnectRequest(
    method: method,
    url: url(apiBase, path),
    headers: {
      ...nativeHeaders,
      'Authorization': 'Bearer ${token.accessToken}',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
    body: Uint8List.fromList(body),
  );

  /// Pfad der Sätze einer Krafttraining-Aktivität (GET liest, PUT ersetzt alle Sätze).
  static String exerciseSetsPath(int activityID) => '/activity-service/activity/$activityID/exerciseSets';

  /// Aktivitätsdatei hochladen (`/upload-service/upload`, Formularfeld `file`, wie python-garminconnect
  /// `upload_activity`). Garmin antwortet mit `detailedImportResult`; 409 heißt „schon vorhanden“.
  static ConnectRequest uploadRequest({
    required List<int> fit,
    required String fileName,
    required ConnectToken token,
    required String boundary,
  }) {
    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'))
      ..add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'))
      ..add(fit)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    return ConnectRequest(
      method: 'POST',
      url: url(apiBase, '/upload-service/upload'),
      headers: {
        ...nativeHeaders,
        'Authorization': 'Bearer ${token.accessToken}',
        'Accept': 'application/json',
        'Content-Type': 'multipart/form-data; boundary=$boundary',
      },
      body: body.takeBytes(),
    );
  }
}

/// Endpunkte, die es nur über den Garmin-Connect-Zugang gibt (python-garminconnect `api/base.py`).
sealed class ConnectEndpoint {
  const ConnectEndpoint();

  static const socialProfile = _ConnectSimple('/userprofile-service/socialProfile');

  const factory ConnectEndpoint.trainingReadiness(CalendarDay day) = _ConnectDay.trainingReadiness;
  const factory ConnectEndpoint.trainingStatus(CalendarDay day) = _ConnectDay.trainingStatus;
  const factory ConnectEndpoint.enduranceScore(CalendarDay day) = _ConnectDay.enduranceScore;
  const factory ConnectEndpoint.racePredictions({required String displayName}) = _ConnectName.racePredictions;

  /// Tageszusammenfassung und Schlaf in der Form von Garmin Connect (die Personal-API-Pfade `v2/dailysummaries` und
  /// `dailySleep` sind dort nicht sicher verfügbar).
  const factory ConnectEndpoint.userSummary({required String displayName, required CalendarDay day}) =
      _ConnectName.userSummary;
  const factory ConnectEndpoint.dailySleepData({required String displayName, required CalendarDay day}) =
      _ConnectName.dailySleepData;

  /// Wägungen eines Zeitraums (Waage, Garmin-App oder Eingabe in Connect).
  const factory ConnectEndpoint.weightRange({required CalendarDay start, required CalendarDay end}) = _ConnectWeight;

  /// Die neuesten Aktivitäten (für den Abgleich von Krafttrainings direkt nach dem Speichern).
  const factory ConnectEndpoint.recentActivities({required int limit}) = _ConnectRecent;

  String get path;
  List<GarminQueryItem> get query => const [];

  /// Schrägstriche im Namen würden den Pfad verlassen.
  static String safe(String name) => name.replaceAll('/', '');
}

final class _ConnectSimple extends ConnectEndpoint {
  const _ConnectSimple(this.path);

  @override
  final String path;
}

enum _ConnectDayKind { trainingReadiness, trainingStatus, enduranceScore }

final class _ConnectDay extends ConnectEndpoint {
  const _ConnectDay.trainingReadiness(this.day) : kind = _ConnectDayKind.trainingReadiness;
  const _ConnectDay.trainingStatus(this.day) : kind = _ConnectDayKind.trainingStatus;
  const _ConnectDay.enduranceScore(this.day) : kind = _ConnectDayKind.enduranceScore;

  final _ConnectDayKind kind;
  final CalendarDay day;

  @override
  String get path => switch (kind) {
    _ConnectDayKind.trainingReadiness => '/metrics-service/metrics/trainingreadiness/${day.iso}',
    _ConnectDayKind.trainingStatus => '/metrics-service/metrics/trainingstatus/aggregated/${day.iso}',
    _ConnectDayKind.enduranceScore => '/metrics-service/metrics/endurancescore',
  };

  @override
  List<GarminQueryItem> get query =>
      kind == _ConnectDayKind.enduranceScore ? [GarminQueryItem('calendarDate', day.iso)] : const [];
}

enum _ConnectNameKind { racePredictions, userSummary, dailySleepData }

final class _ConnectName extends ConnectEndpoint {
  const _ConnectName.racePredictions({required this.displayName}) : kind = _ConnectNameKind.racePredictions, day = null;
  const _ConnectName.userSummary({required this.displayName, required CalendarDay this.day})
    : kind = _ConnectNameKind.userSummary;
  const _ConnectName.dailySleepData({required this.displayName, required CalendarDay this.day})
    : kind = _ConnectNameKind.dailySleepData;

  final _ConnectNameKind kind;
  final String displayName;
  final CalendarDay? day;

  @override
  String get path => switch (kind) {
    _ConnectNameKind.racePredictions =>
      '/metrics-service/metrics/racepredictions/latest/${ConnectEndpoint.safe(displayName)}',
    _ConnectNameKind.userSummary => '/usersummary-service/usersummary/daily/${ConnectEndpoint.safe(displayName)}',
    _ConnectNameKind.dailySleepData => '/wellness-service/wellness/dailySleepData/${ConnectEndpoint.safe(displayName)}',
  };

  @override
  List<GarminQueryItem> get query => switch (kind) {
    _ConnectNameKind.racePredictions => const [],
    _ConnectNameKind.userSummary => [GarminQueryItem('calendarDate', day!.iso)],
    _ConnectNameKind.dailySleepData => [
      GarminQueryItem('date', day!.iso),
      const GarminQueryItem('nonSleepBufferMinutes', '60'),
    ],
  };
}

final class _ConnectWeight extends ConnectEndpoint {
  const _ConnectWeight({required this.start, required this.end});

  final CalendarDay start;
  final CalendarDay end;

  @override
  String get path => '/weight-service/weight/range/${start.iso}/${end.iso}';

  @override
  List<GarminQueryItem> get query => const [GarminQueryItem('includeAll', 'true')];
}

final class _ConnectRecent extends ConnectEndpoint {
  const _ConnectRecent({required this.limit});

  final int limit;

  @override
  String get path => '/activitylist-service/activities/search/activities';

  @override
  List<GarminQueryItem> get query => [const GarminQueryItem('start', '0'), GarminQueryItem('limit', '$limit')];
}

/// Werte, die es nur über Garmin Connect gibt (Erweiterung von `GarminMetricsParser` in Swift).
abstract final class GarminConnectMetrics {
  /// `/metrics-service/metrics/trainingreadiness/{date}`: Liste mit einem Eintrag je Messung (`score`, `level`).
  static DayMap trainingReadiness(JsonValue json, CalendarDay day) {
    final entries = json.arrayValue ?? [json];
    final first = entries.where((entry) => entry['score']?.doubleValue != null).firstOrNull;
    final score = first?['score']?.doubleValue;
    if (first == null || score == null || score <= 0) return {};
    final metrics = DailyMetrics(day)
      ..trainingReadiness = score
      ..trainingReadinessLevel = first['level']?.stringValue;
    // `recoveryTime` in Minuten; „REACHED_ZERO“ heißt erholt, auch wenn noch der alte Wert drinsteht.
    if (first['recoveryTimeChangePhrase']?.stringValue == 'REACHED_ZERO') {
      metrics.recoveryHours = 0;
    } else if (first['recoveryTime']?.doubleValue case final minutes? when minutes >= 0) {
      metrics.recoveryHours = (minutes / 6).roundToDouble() / 10;
    }
    return {day: metrics};
  }

  /// `/metrics-service/metrics/trainingstatus/aggregated/{date}`: Status je Gerät unter einer Geräte-ID.
  static DayMap trainingStatus(JsonValue json, CalendarDay day) {
    final devices = json['mostRecentTrainingStatus']?['latestTrainingStatusData']?.objectValue;
    if (devices == null) return {};
    String? phrase;
    for (final key in devices.keys.toList()..sort()) {
      phrase = devices[key]?['trainingStatusFeedbackPhrase']?.stringValue;
      if (phrase != null) break;
    }
    if (phrase == null) return {};
    final metrics = DailyMetrics(day)..trainingStatus = phrase;
    // Akute/chronische Belastung: `acuteTrainingLoadDTO` desselben Geräteeintrags.
    final loads = json.objects('dailyTrainingLoadAcute');
    if (loads.isNotEmpty) {
      final acute = loads.first['dailyTrainingLoadAcute']?.doubleValue;
      final chronic = loads.first['dailyTrainingLoadChronic']?.doubleValue;
      metrics
        ..acuteLoad = acute != null && acute >= 0 ? acute : null
        ..chronicLoad = chronic != null && chronic > 0 ? chronic : null;
    }
    return {day: metrics};
  }

  /// `/metrics-service/metrics/endurancescore?calendarDate=`: `overallScore`, auch unter `enduranceScoreDTO`.
  static DayMap enduranceScore(JsonValue json, CalendarDay day) {
    final value =
        json['overallScore']?.doubleValue ??
        json['enduranceScoreDTO']?['overallScore']?.doubleValue ??
        json['avg']?.doubleValue ??
        json['max']?.doubleValue;
    if (value == null || value <= 0) return {};
    return {day: DailyMetrics(day)..enduranceScore = value};
  }

  /// Garmins Trainingsstatus auf Deutsch (Altbestand `TRAINING_STATUS_DE`, z. B. `PRODUCTIVE_3`).
  static String trainingStatusGerman(String phrase) {
    const names = [
      ('PRODUCTIVE', 'Produktiv'),
      ('MAINTAINING', 'Erhaltend'),
      ('RECOVERY', 'Erholung'),
      ('UNPRODUCTIVE', 'Unproduktiv'),
      ('DETRAINING', 'Formverlust'),
      ('PEAKING', 'Formhöhepunkt'),
      ('OVERREACHING', 'Überlastung'),
      ('STRAINED', 'Überbeansprucht'),
      ('NO_STATUS', 'Kein Status'),
      ('PAUSED', 'Pausiert'),
    ];
    final code = phrase.toUpperCase();
    for (final (prefix, name) in names) {
      if (code.startsWith(prefix)) return name;
    }
    // Wie `capitalized` in Swift: erster Buchstabe je Wort groß, der Rest klein.
    return phrase
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}

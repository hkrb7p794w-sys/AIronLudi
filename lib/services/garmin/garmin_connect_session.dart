import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:uuid/uuid.dart';

import '../../data/secure/secret_store.dart';
import '../../data/settings/settings_store.dart';
import '../http/http_transport.dart';

/// Fehler der Anmeldung am Garmin-Konto (wie `GarminConnectError`).
sealed class GarminConnectError implements Exception {
  const GarminConnectError();

  static const invalidCredentials = _ConnectPlain('invalidCredentials', 'E-Mail oder Passwort falsch.');
  static const needsLogin = _ConnectPlain(
    'needsLogin',
    'Garmin-Anmeldung abgelaufen. Bitte in den Einstellungen neu anmelden.',
  );
  static const codeRejected = _ConnectPlain('codeRejected', 'Der Bestätigungscode wurde nicht akzeptiert.');

  const factory GarminConnectError.blocked(String detail) = GarminConnectBlocked;
  const factory GarminConnectError.unexpected(String detail) = GarminConnectUnexpected;

  String get message;

  @override
  String toString() => message;
}

final class _ConnectPlain extends GarminConnectError {
  const _ConnectPlain(this.name, this.message);

  final String name;

  @override
  final String message;

  @override
  bool operator ==(Object other) => other is _ConnectPlain && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class GarminConnectBlocked extends GarminConnectError {
  const GarminConnectBlocked(this.detail);

  final String detail;

  @override
  String get message => 'Garmin blockiert die Anmeldung gerade ($detail). Bitte später erneut versuchen.';

  @override
  bool operator ==(Object other) => other is GarminConnectBlocked && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;
}

final class GarminConnectUnexpected extends GarminConnectError {
  const GarminConnectUnexpected(this.detail);

  final String detail;

  @override
  String get message => 'Garmin-Anmeldung fehlgeschlagen: $detail';

  @override
  bool operator ==(Object other) => other is GarminConnectUnexpected && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;
}

/// Zustand nach einem Anmeldeschritt.
sealed class ConnectLoginState {
  const ConnectLoginState();
}

final class ConnectLoggedIn extends ConnectLoginState {
  const ConnectLoggedIn();

  @override
  bool operator ==(Object other) => other is ConnectLoggedIn;

  @override
  int get hashCode => 0;
}

final class ConnectNeedsCode extends ConnectLoginState {
  const ConnectNeedsCode(this.method);

  final String method;

  @override
  bool operator ==(Object other) => other is ConnectNeedsCode && other.method == method;

  @override
  int get hashCode => method.hashCode;
}

/// Inoffizieller Garmin-Connect-Zugang (Ablauf in `coach_core` `GarminConnect`). Das Passwort wird nie gespeichert,
/// nur das Token (sicherer Speicher) und die E-Mail-Adresse (zur Anzeige).
final class GarminConnectSession {
  GarminConnectSession({
    required this._secrets,
    required this._settings,
    HttpTransportFactory makeTransport = DioTransport.create,
    Future<void> Function()? pause,
    DateTime Function()? clock,
  }) : _makeTransport = makeTransport,
       _api = makeTransport(cookies: true),
       _clock = clock ?? DateTime.now,
       pause = pause ?? _randomPause;

  static const emailKey = SettingsKeys.garminConnectEmail;
  static const displayNameKey = SettingsKeys.garminConnectDisplayName;

  final Secrets _secrets;
  final SettingsStore _settings;
  final HttpTransportFactory _makeTransport;

  /// Für Token-Erneuerung und API-Abrufe (eigene Cookies wie eine `.ephemeral`-Sitzung, ohne die der Anmeldung).
  final HttpTransport _api;
  final DateTime Function() _clock;

  /// Pause zwischen Anmeldeseite und Absenden (wie die App; sonst antwortet Cloudflare mit 429).
  Future<void> Function() pause;

  ConnectToken? _cachedToken;

  /// Sitzung mit den Cookies der laufenden Anmeldung (für den Bestätigungscode).
  HttpTransport? _login;
  String? _pendingMethod;

  static Future<void> _randomPause() =>
      Future<void>.delayed(Duration(milliseconds: 2000 + math.Random().nextInt(3001)));

  bool get isLoggedIn => _storedToken() != null;
  String? get email => _settings.string(emailKey);
  String? get displayName => _settings.string(displayNameKey);

  // Anmeldung

  Future<ConnectLoginState> login({required String email, required String password}) async {
    _login?.close();
    final session = _makeTransport(cookies: true);
    _login = session;
    _pendingMethod = null;
    final page = await _send(GarminConnect.signInPage, session);
    if (page.status == 429 || page.status == 427 || page.status == 403) {
      throw GarminConnectError.blocked('Anmeldeseite HTTP ${page.status}');
    }
    await pause();
    final trimmed = email.trim();
    final response = await _send(GarminConnect.login(email: trimmed, password: password), session);
    await _settings.setString(emailKey, trimmed);
    return _handle(GarminConnect.loginResult(status: response.status, body: response.body), session);
  }

  Future<ConnectLoginState> submitCode(String code) async {
    final (session, method) = (_login, _pendingMethod);
    if (session == null || method == null) throw GarminConnectError.needsLogin;
    final response = await _send(GarminConnect.verifyCode(code.trim(), method: method), session);
    final result = GarminConnect.loginResult(status: response.status, body: response.body);
    if (result is LoginUnexpected) throw GarminConnectError.codeRejected;
    return _handle(result, session);
  }

  Future<void> logout() async {
    await _secrets.set(SecretKey.garminConnectToken, null);
    _cachedToken = null;
    _login?.close();
    _login = null;
    _pendingMethod = null;
    await _settings.remove(displayNameKey);
  }

  Future<ConnectLoginState> _handle(LoginResult result, HttpTransport session) async {
    switch (result) {
      case LoginTicket(:final ticket):
        await _exchange(ticket, session);
        _login?.close();
        _login = null;
        _pendingMethod = null;
        return const ConnectLoggedIn();
      case LoginNeedsCode(:final method):
        _pendingMethod = method;
        return ConnectNeedsCode(method);
      case LoginInvalidCredentials():
        throw GarminConnectError.invalidCredentials;
      case LoginBlocked(:final reason):
        throw GarminConnectError.blocked(reason);
      case LoginUnexpected(:final reason):
        throw GarminConnectError.unexpected(reason);
    }
  }

  /// Ticket gegen ein Token tauschen (Client-Kennungen der Reihe nach) und mit einem Abruf prüfen.
  Future<void> _exchange(String ticket, HttpTransport session) async {
    for (final clientID in GarminConnect.diClientIDs) {
      final response = await _send(GarminConnect.exchange(ticket: ticket, clientID: clientID), session);
      if (response.status == 429) throw GarminConnectError.blocked('Token-Tausch HTTP 429');
      if (!response.isSuccess) continue;
      final token = ConnectToken.fromResponse(response.body, clientID: clientID, now: _clock());
      if (token == null) continue;
      await _store(token);
      final profile = await json(ConnectEndpoint.socialProfile);
      if (profile['displayName']?.stringValue case final name?) await _settings.setString(displayNameKey, name);
      return;
    }
    throw GarminConnectError.unexpected('Token-Tausch fehlgeschlagen');
  }

  // Token

  Future<ConnectToken> validToken({bool forceRefresh = false}) async {
    final token = _storedToken();
    if (token == null) throw GarminConnectError.needsLogin;
    final now = _clock();
    if (!forceRefresh && !token.needsRefresh(now: now)) return token;
    final request = GarminConnect.refresh(token);
    if (request == null) throw GarminConnectError.needsLogin;
    final response = await _send(request, _api);
    final fresh = response.isSuccess
        ? ConnectToken.fromResponse(response.body, clientID: token.clientID, now: now)
        : null;
    if (fresh == null) {
      // Abgelehnt: neu anmelden. Netz- oder Serverfehler: altes Token behalten, solange es gilt.
      if (response.status == 400 || response.status == 401) await logout();
      if (token.expiresAt.isAfter(now) && response.status >= 500) return token;
      throw GarminConnectError.needsLogin;
    }
    final merged = fresh.refreshToken == null
        ? ConnectToken(
            accessToken: fresh.accessToken,
            refreshToken: token.refreshToken,
            clientID: fresh.clientID,
            expiresAt: fresh.expiresAt,
          )
        : fresh;
    await _store(merged);
    return merged;
  }

  Future<void> _store(ConnectToken token) async {
    _cachedToken = token;
    await _secrets.set(SecretKey.garminConnectToken, jsonEncode(token.toJson()));
  }

  ConnectToken? _storedToken() {
    if (_cachedToken case final token?) return token;
    final text = _secrets.string(SecretKey.garminConnectToken);
    if (text == null) return null;
    try {
      return ConnectToken.fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  // Abrufe

  /// GET auf connectapi; bei 401 einmal das Token erneuern.
  Future<Uint8List> data({
    required String path,
    List<GarminQueryItem> query = const [],
    String accept = 'application/json',
  }) => _authorized(
    (token) => GarminConnect.apiRequest(path: path, query: query, token: token, accept: accept),
    (response) => response.body,
  );

  /// JSON senden (PUT/POST) mit einmaliger Token-Erneuerung bei 401.
  Future<Uint8List> sendJson({required String method, required String path, required List<int> json}) => _authorized(
    (token) => GarminConnect.jsonRequest(method: method, path: path, body: json, token: token),
    (response) => response.body,
  );

  /// Lädt eine FIT-Datei als Aktivität hoch. `true` = neu angelegt, `false` = war schon vorhanden (409).
  Future<bool> upload({required List<int> fit, required String fileName}) => _authorized(
    (token) => GarminConnect.uploadRequest(
      fit: fit,
      fileName: fileName,
      token: token,
      boundary: 'coach-${const Uuid().v4().toUpperCase()}',
    ),
    (response) => true,
    conflict: false,
  );

  Future<T> _authorized<T>(
    ConnectRequest Function(ConnectToken token) build,
    T Function(HttpResponse response) success, {
    T? conflict,
  }) async {
    var token = await validToken();
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await _send(build(token), _api);
      if (response.status == 401 && attempt == 0) {
        token = await validToken(forceRefresh: true);
        continue;
      }
      if (conflict != null && response.status == 409) return conflict;
      if (GarminAPIError.from(status: response.status, isTokenExchange: false) case final error?) throw error;
      return success(response);
    }
    throw GarminAPIError.unauthorized;
  }

  Future<JsonValue> json(ConnectEndpoint endpoint) async {
    final body = await data(path: endpoint.path, query: endpoint.query);
    return decodeGarminJson(body);
  }

  Future<HttpResponse> _send(ConnectRequest request, HttpTransport transport) async {
    try {
      return await transport.send(
        HttpRequest(method: request.method, url: request.url, headers: request.headers, body: request.body),
      );
    } on HttpTransportException catch (error) {
      throw GarminAPIError.network(error.message);
    }
  }
}

/// Leere Antwort = `null`; sonst JSON (ungültig: [GarminAPIError.invalidResponse]).
JsonValue decodeGarminJson(List<int> body) {
  if (body.isEmpty) return JsonValue(null);
  try {
    return JsonValue(jsonDecode(utf8.decode(body)));
  } on FormatException {
    throw GarminAPIError.invalidResponse;
  }
}

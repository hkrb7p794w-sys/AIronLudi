import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';

import '../../data/secure/secret_store.dart';
import '../http/http_transport.dart';
import 'garmin_connect_session.dart';

/// Wer einen Abruf beantwortet hat.
enum GarminSource {
  connect('Garmin-Konto'),
  personalAPI('Personal API');

  const GarminSource(this.label);

  final String label;
}

/// Zugriff auf die Garmin Connect Personal API.
///
/// Der persönliche API-Key (aus Garmin Connect, Einstellungen › Personal API Key) wird gegen ein Bearer-Token
/// getauscht, das im sicheren Speicher zwischengespeichert und kurz vor Ablauf erneuert wird.
///
/// Ist das Garmin-Konto angemeldet ([GarminConnectSession]), kommen die Daten zuerst von dort; die Personal API
/// springt je Abruf ein, wenn das Konto scheitert (abgelaufen, blockiert, Endpunkt unbekannt).
final class GarminClient {
  GarminClient({required this._secrets, HttpTransport? transport, this.connect, DateTime Function()? clock})
    : _transport = transport ?? DioTransport(),
      _clock = clock ?? DateTime.now;

  final Secrets _secrets;
  final HttpTransport _transport;
  final DateTime Function() _clock;
  final GarminConnectSession? connect;
  GarminBearerToken? _cachedToken;

  /// Wer die Abrufe seit dem letzten [resetSources] beantwortet hat (für den Abrufbericht).
  final Map<GarminSource, int> sources = {};

  /// Letzter Fehler des Garmin-Kontos, wenn die Personal API einspringen musste.
  String? lastConnectError;

  bool get hasKey => (_secrets.string(SecretKey.garminAPIKey) ?? '').isNotEmpty;

  /// Mindestens ein Zugang ist eingerichtet.
  bool get isConfigured => hasKey || (connect?.isLoggedIn ?? false);

  void resetSources() {
    sources.clear();
    lastConnectError = null;
  }

  /// Neuer Key: altes Token verwerfen.
  Future<void> updateKey(String key) async {
    await _secrets.set(SecretKey.garminAPIKey, key.trim());
    await _secrets.set(SecretKey.garminBearerToken, null);
    _cachedToken = null;
  }

  Future<JsonValue> json(GarminEndpoint endpoint) async => decodeGarminJson(await data(endpoint));

  Future<Uint8List> data(GarminEndpoint endpoint) async {
    final connect = this.connect;
    if (connect != null && connect.isLoggedIn && endpoint != GarminEndpoint.tokenExchange) {
      try {
        final request = endpoint.request;
        final data = await connect.data(path: request.path, query: request.query, accept: request.accept);
        _count(GarminSource.connect);
        return data;
      } on Object catch (error) {
        lastConnectError = switch (error) {
          GarminAPIError(:final message) || GarminConnectError(:final message) => message,
          _ => '$error',
        };
        if (!hasKey) rethrow;
      }
    }
    final data = await _personalData(endpoint);
    _count(GarminSource.personalAPI);
    return data;
  }

  /// Nur über das Garmin-Konto verfügbare Werte (Readiness, Trainingsstatus …).
  Future<JsonValue> connectJson(ConnectEndpoint endpoint) async {
    final connect = this.connect;
    if (connect == null || !connect.isLoggedIn) throw GarminConnectError.needsLogin;
    final value = await connect.json(endpoint);
    _count(GarminSource.connect);
    return value;
  }

  void _count(GarminSource source) => sources[source] = (sources[source] ?? 0) + 1;

  Future<Uint8List> _personalData(GarminEndpoint endpoint) async {
    try {
      return await _authorizedData(endpoint, await validToken());
    } on GarminAPIError catch (error) {
      // Token von Garmin vorzeitig verworfen: einmal neu tauschen.
      if (error != GarminAPIError.unauthorized) rethrow;
      return _authorizedData(endpoint, await validToken(forceRefresh: true));
    }
  }

  Future<GarminBearerToken> validToken({bool forceRefresh = false}) async {
    final now = _clock();
    if (!forceRefresh) {
      final token = _cachedToken ?? _storedToken();
      if (token != null && !token.needsRefresh(now: now)) {
        _cachedToken = token;
        return token;
      }
    }
    final key = _secrets.string(SecretKey.garminAPIKey);
    if (key == null || key.isEmpty) throw GarminAPIError.missingKey;
    final response = await _send(GarminEndpoint.tokenExchange.request, authorization: 'ApiKey $key');
    if (GarminAPIError.from(status: response.status, isTokenExchange: true) case final error?) throw error;
    final token = GarminBearerToken.fromResponse(utf8.decode(response.body, allowMalformed: true), now: now);
    if (token == null) throw GarminAPIError.invalidResponse;
    _cachedToken = token;
    await _secrets.set(SecretKey.garminBearerToken, jsonEncode(token.toJson()));
    return token;
  }

  GarminBearerToken? _storedToken() {
    final text = _secrets.string(SecretKey.garminBearerToken);
    if (text == null) return null;
    try {
      return GarminBearerToken.fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  Future<Uint8List> _authorizedData(GarminEndpoint endpoint, GarminBearerToken token) async {
    final response = await _send(endpoint.request, authorization: 'Bearer ${token.value}');
    if (GarminAPIError.from(status: response.status, isTokenExchange: false) case final error?) throw error;
    return response.body;
  }

  Future<HttpResponse> _send(GarminRequest request, {required String authorization}) async {
    final url = request.url();
    if (url == null) throw GarminAPIError.invalidResponse;
    try {
      return await _transport.send(
        HttpRequest(
          method: request.method,
          url: url,
          headers: {'Accept': request.accept, 'Authorization': authorization},
        ),
      );
    } on HttpTransportException catch (error) {
      throw GarminAPIError.network(error.message);
    }
  }
}

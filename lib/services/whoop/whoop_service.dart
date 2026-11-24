import 'dart:async';
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/metrics_repository.dart';
import '../../data/repositories/source_store.dart';
import '../../data/secure/secret_store.dart';
import '../../data/settings/settings_store.dart';
import '../ai/ai_client.dart';
import '../http/http_transport.dart';

/// Fehler der WHOOP-Anbindung mit Text für die Anzeige.
final class WhoopError implements Exception {
  const WhoopError(this.message, {this.reconnect = false});

  final String message;

  /// Zugang abgelaufen oder widerrufen: neu verbinden.
  final bool reconnect;

  @override
  String toString() => message;
}

/// WHOOP über die offizielle API v2 (OAuth). Den Token-Tausch macht der Worker (Client-Secret), die Daten holt die
/// App selbst bei `api.prod.whoop.com/developer`. Tageswerte gehen wie bei Apple Health ins Herkunftsverzeichnis
/// (`SourceStore`, Vorrang je Datenart), Trainings als Aktivitäten mit Herkunft WHOOP.
final class WhoopService extends ChangeNotifier {
  WhoopService({
    required this._ai,
    required this._secrets,
    required this._settings,
    required this._activities,
    this.sources,
    HttpTransport? transport,
    DateTime Function()? clock,
  }) : _transport = transport ?? DioTransport(),
       _clock = clock ?? DateTime.now;

  static const apiBase = 'https://api.prod.whoop.com/developer';
  static const pageSize = 25;

  final AIClient _ai;
  final Secrets _secrets;
  final SettingsStore _settings;
  final ActivityRepository _activities;
  final HttpTransport _transport;
  final DateTime Function() _clock;
  SourceStore? sources;

  bool isSyncing = false;

  /// Läuft gerade ein Refresh, warten weitere Anfragen darauf: WHOOP macht das alte Refresh-Token beim ersten
  /// Refresh ungültig, ein zweiter gleichzeitiger würde scheitern.
  Future<WhoopToken>? _refreshing;

  WhoopToken? get _token => WhoopToken.fromJson(_decode(_secrets.string(SecretKey.whoopToken)));

  bool get isConnected => _token != null;

  WhoopProfile? get profile => WhoopProfile.fromJson(_settings.json(SettingsKeys.whoopProfile));

  WhoopBody? get body => WhoopBody.fromJson(_settings.json(SettingsKeys.whoopBody));

  DateTime? get lastSync => _settings.date(SettingsKeys.whoopLastSync);

  String? get lastResult => _settings.string(SettingsKeys.whoopLastResult);

  static Object? _decode(String? text) {
    if (text == null) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  // Verbinden

  /// Anmelde-Adresse bei WHOOP (vom Worker, mit Zufalls-`state`). Öffnet die Oberfläche im Browser.
  Future<Uri> beginConnect() async {
    if (!_ai.isConfigured) {
      throw const WhoopError('Für WHOOP muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker).');
    }
    final Object? json;
    try {
      json = _decode(utf8.decode(await _ai.send('v1/whoop/authorize', method: 'POST')));
    } on AIHttpError catch (error) {
      throw WhoopError(error.message);
    }
    if (json case {'url': final String url, 'state': final String state}) {
      await _settings.setString(SettingsKeys.whoopState, state);
      return Uri.parse(url);
    }
    throw const WhoopError('Antwort des Workers unvollständig.');
  }

  /// Rücksprung `coach://whoop?code=…&state=…`: Code tauschen, Profil holen, ersten Abruf starten.
  Future<void> complete(Uri link) async {
    final query = link.queryParameters;
    if (query['error'] case final error?) {
      throw WhoopError(WhoopAuthErrors.message(error));
    }
    final expected = _settings.string(SettingsKeys.whoopState);
    final code = query['code'];
    if (code == null || expected == null || query['state'] != expected) {
      throw const WhoopError('Die Anmeldung passt nicht zu diesem Gerät. Bitte erneut verbinden.');
    }
    await _settings.remove(SettingsKeys.whoopState);
    await _store(await _exchange({'grant_type': 'authorization_code', 'code': code}));
    await refreshProfile();
    notifyListeners();
  }

  Future<WhoopToken> _exchange(Map<String, String> body) async {
    final Object? json;
    try {
      json = _decode(
        utf8.decode(await _ai.send('v1/whoop/token', method: 'POST', body: utf8.encode(jsonEncode(body)))),
      );
    } on AIHttpError catch (error) {
      throw WhoopError(error.message, reconnect: error.status == 400);
    }
    final token = WhoopToken.fromResponse(json, now: _clock());
    if (token == null) throw const WhoopError('Antwort von WHOOP unvollständig.');
    return token;
  }

  Future<void> _store(WhoopToken token) => _secrets.set(SecretKey.whoopToken, jsonEncode(token.toJson()));

  /// Gültiges Access-Token; abgelaufen: genau ein Refresh, das neue Refresh-Token wird sofort gespeichert.
  Future<WhoopToken> _validToken({bool force = false}) async {
    final token = _token;
    if (token == null) throw const WhoopError('WHOOP ist nicht verbunden.', reconnect: true);
    if (!force && !token.isExpired(_clock())) return token;
    return _refreshing ??= _refresh(token).whenComplete(() => _refreshing = null);
  }

  Future<WhoopToken> _refresh(WhoopToken token) async {
    final refresh = token.refreshToken;
    if (refresh == null) {
      await _forget();
      throw const WhoopError('WHOOP-Zugang abgelaufen. Bitte neu verbinden.', reconnect: true);
    }
    try {
      final fresh = await _exchange({'grant_type': 'refresh_token', 'refresh_token': refresh});
      final next = fresh.refreshToken == null
          ? WhoopToken(accessToken: fresh.accessToken, refreshToken: refresh, expiresAt: fresh.expiresAt)
          : fresh;
      await _store(next);
      return next;
    } on WhoopError catch (error) {
      if (error.reconnect) {
        await _forget();
        throw const WhoopError('WHOOP-Zugang abgelaufen. Bitte neu verbinden.', reconnect: true);
      }
      rethrow;
    }
  }

  /// Trennen: Zugang bei WHOOP widerrufen (wenn möglich) und alles auf dem Gerät löschen.
  Future<void> disconnect() async {
    try {
      if (_token != null) await _request('DELETE', '/v2/user/access');
    } on Object {
      // Auch ohne Netz lokal trennen.
    }
    await _forget();
    notifyListeners();
  }

  Future<void> _forget() async {
    await _secrets.set(SecretKey.whoopToken, null);
    for (final key in [
      SettingsKeys.whoopProfile,
      SettingsKeys.whoopBody,
      SettingsKeys.whoopLastSync,
      SettingsKeys.whoopLastResult,
      SettingsKeys.whoopState,
    ]) {
      await _settings.remove(key);
    }
  }

  // Anfragen

  Future<HttpResponse> _request(String method, String path, {Map<String, String> query = const {}}) async {
    var url = Uri.parse('$apiBase$path');
    if (query.isNotEmpty) url = url.replace(queryParameters: query);
    Future<HttpResponse> send(WhoopToken token) async {
      try {
        return await _transport.send(
          HttpRequest(
            method: method,
            url: url,
            headers: {'Authorization': 'Bearer ${token.accessToken}', 'Accept': 'application/json'},
          ),
        );
      } on HttpTransportException catch (error) {
        throw WhoopError('WHOOP nicht erreichbar: ${error.message}');
      }
    }

    var response = await send(await _validToken());
    // Abgelaufen oder vorzeitig ungültig: einmal erneuern und wiederholen.
    if (response.status == 401) response = await send(await _validToken(force: true));
    if (response.status == 401) {
      await _forget();
      throw const WhoopError('WHOOP-Zugang abgelaufen. Bitte neu verbinden.', reconnect: true);
    }
    if (response.status == 429) throw const WhoopError('WHOOP-Abruflimit erreicht. Später erneut versuchen.');
    if (!response.isSuccess && response.status != 404) {
      throw WhoopError('WHOOP antwortet mit Fehler ${response.status}.');
    }
    return response;
  }

  Future<Object?> _get(String path, {Map<String, String> query = const {}}) async {
    final response = await _request('GET', path, query: query);
    if (response.status == 404) return null;
    return _decode(utf8.decode(response.body));
  }

  /// Alle Einträge im Zeitraum, seitenweise (höchstens 25 je Seite). `complete`: alle Seiten gelesen.
  Future<({List<Object?> records, bool complete})> _collection(
    String path, {
    required DateTime start,
    required DateTime end,
    required int maxPages,
  }) async {
    final records = <Object?>[];
    String? next;
    for (var page = 0; page < maxPages; page++) {
      final json = await _get(
        path,
        query: {
          'limit': '$pageSize',
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
          'nextToken': ?next,
        },
      );
      if (json is! Map) break;
      if (json['records'] case final List<Object?> list) records.addAll(list);
      next = json['next_token'] is String && (json['next_token'] as String).isNotEmpty
          ? json['next_token'] as String
          : null;
      if (next == null) return (records: records, complete: true);
    }
    return (records: records, complete: next == null);
  }

  /// Vorname und Körperwerte (für die Einstellungen).
  Future<void> refreshProfile() async {
    if (WhoopProfile.fromJson(await _get('/v2/user/profile/basic')) case final profile?) {
      await _settings.setJson(SettingsKeys.whoopProfile, profile.toJson());
    }
    if (WhoopBody.fromJson(await _get('/v2/user/measurement/body')) case final body?) {
      await _settings.setJson(SettingsKeys.whoopBody, body.toJson());
    }
  }

  // Abruf

  /// Holt Erholung, Schlaf, Zyklen und Trainings seit dem letzten Abruf (beim ersten Mal 90 Tage) und übernimmt
  /// sie. Gibt eine kurze Zusammenfassung zurück.
  Future<String> sync() async {
    if (!isConnected) throw const WhoopError('WHOOP ist nicht verbunden.', reconnect: true);
    if (isSyncing) return lastResult ?? '';
    isSyncing = true;
    notifyListeners();
    try {
      final now = _clock();
      final start = WhoopImport.syncStart(now: now, lastSync: lastSync);
      final pages = WhoopImport.maxPages(now.difference(start).inDays + 1);
      final recovery = await _collection('/v2/recovery', start: start, end: now, maxPages: pages);
      final sleep = await _collection('/v2/activity/sleep', start: start, end: now, maxPages: pages);
      final cycle = await _collection('/v2/cycle', start: start, end: now, maxPages: pages);
      final workout = await _collection('/v2/activity/workout', start: start, end: now, maxPages: pages);

      final days = WhoopImport.days(
        recoveries: [for (final item in recovery.records) ?WhoopRecovery.fromJson(item)],
        sleeps: [for (final item in sleep.records) ?WhoopSleep.fromJson(item)],
        cycles: [for (final item in cycle.records) ?WhoopCycle.fromJson(item)],
      );
      final activities = [
        for (final item in workout.records)
          if (WhoopWorkout.fromJson(item) case final workout?) WhoopImport.activity(workout),
      ];
      final store = sources;
      if (store != null) await store.ingestDays(days, from: DataProvider.whoop, now: now);
      final allowed = await store?.recordActivities(
        activities,
        from: DataProvider.whoop,
        window: DateRange(CalendarDay.fromDate(start), CalendarDay.fromDate(now)),
        complete: workout.complete,
        now: now,
      );
      final existing = {for (final activity in await _activities.all()) activity.id};
      final fresh = [
        for (final activity in activities)
          if (allowed?.contains(activity.id) ?? true) activity,
      ];
      await _activities.upsertAll(fresh);
      final added = fresh.where((activity) => !existing.contains(activity.id)).length;
      try {
        await refreshProfile();
      } on WhoopError {
        // Profil und Körperwerte sind nur Zusatz.
      }
      await _settings.setDate(SettingsKeys.whoopLastSync, now);
      final result = '${days.length} Tage, $added neue Trainings von WHOOP';
      await _settings.setString(SettingsKeys.whoopLastResult, result);
      return result;
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }
}

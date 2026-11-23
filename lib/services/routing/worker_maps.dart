import 'dart:convert';

import 'package:coach_core/coach_core.dart';

import '../ai/ai_client.dart';

/// Rundwege von openrouteservice über den eigenen Worker (Schlüssel nur dort, `worker/src/maps.ts`). Ohne Worker oder
/// ohne eingerichteten Schlüssel meldet die Quelle „nicht verfügbar“ – der Planer zeigt dann die Meldung des Routers.
final class WorkerRoundTripSource implements RoundTripSource {
  WorkerRoundTripSource(this._ai);

  final AIClient _ai;

  /// Der Worker hat „nicht eingerichtet“ gemeldet: bis zum Neustart nicht mehr fragen.
  bool _notConfigured = false;

  @override
  Future<RoutedPath> roundTrip(
    GeoPoint start, {
    required RouteDiscipline discipline,
    required double lengthMeters,
    required int seed,
  }) async {
    if (_notConfigured || !_ai.isConfigured) {
      throw const RoutingUnavailable('Kein Ausweich-Router eingerichtet.');
    }
    try {
      final body = await _ai.send(
        WorkerRoundTripFormat.path,
        method: 'POST',
        body: utf8.encode(
          jsonEncode(WorkerRoundTripFormat.body(start, discipline: discipline, lengthMeters: lengthMeters, seed: seed)),
        ),
        timeout: const Duration(seconds: 30),
      );
      return WorkerRoundTripFormat.parse(jsonDecode(utf8.decode(body)));
    } on AIHttpError catch (error) {
      if (error.status == 404) throw const NoRouteFound('Kein Rundweg gefunden.');
      if (error.status == 503) _notConfigured = true;
      throw RoutingUnavailable('openrouteservice: ${error.message}');
    } on AIClientError catch (error) {
      throw RoutingUnavailable(error.message);
    } on FormatException {
      throw const RoutingUnavailable('Unerwartete Antwort für den Rundweg.');
    }
  }
}

/// Kartenkacheln über den Worker (MapTiler, mit hellem und dunklem Stil). Ohne Worker: OSM-Kacheln.
final class WorkerTiles {
  const WorkerTiles({required this.base, required this.token});

  final Uri base;
  final String token;

  /// Vorlage für `TileLayer.urlTemplate`.
  String urlTemplate({required bool dark}) {
    final text = base.toString();
    // Als Text zusammengesetzt: `Uri` würde die Platzhalter {z}/{x}/{y} kodieren.
    return '${text.endsWith('/') ? text : '$text/'}v1/maps/tiles/${dark ? 'dark' : 'light'}/{z}/{x}/{y}.png';
  }

  Map<String, String> get headers => {'Authorization': 'Bearer $token'};

  static const attribution = '© MapTiler © OpenStreetMap-Mitwirkende';

  /// Fragt den Worker (`/v1/health`, ohne Anmeldung), ob Kacheln eingerichtet sind; sonst `null`.
  static Future<WorkerTiles?> probe(AIClient ai) async {
    final base = AIClient.normalizedURL(ai.workerURL);
    final token = ai.sessionToken ?? ai.appToken;
    if (base == null || token == null) return null;
    try {
      final body = await ai.send('v1/health', method: 'GET', auth: AIAuth.none, timeout: const Duration(seconds: 8));
      final health = jsonDecode(utf8.decode(body));
      if (health case {'maps': {'tiles': true}}) return WorkerTiles(base: base, token: token);
    } on Object {
      // Worker nicht erreichbar: OSM-Kacheln.
    }
    return null;
  }
}

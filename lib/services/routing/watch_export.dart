import 'dart:convert';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';

import '../ai/ai_client.dart';

/// Ergebnis von „Auf die Uhr“.
final class WatchExportResult {
  const WatchExportResult({required this.bytes, required this.chunks, required this.variants, required this.nodes});

  final int bytes;
  final int chunks;

  /// Mitgegebene Varianten (kürzer/länger).
  final int variants;

  /// Knoten im Wegenetz.
  final int nodes;
}

/// Kein Worker eingerichtet oder die Uhr-Funktion dort nicht erreichbar.
final class WatchExportFailed implements Exception {
  const WatchExportFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// „Auf die Uhr“: Route mit Varianten (kürzer/länger) und dem Wegenetz rundherum als Paket für das Datenfeld
/// `garmin/` packen und beim eigenen Worker ablegen; die Uhr holt es vor dem Lauf, unterwegs braucht sie kein Handy.
final class WatchExportService {
  WatchExportService({required this.ai, required this.backend, required this.network, this.features});

  final AIClient ai;
  final RoutingBackend backend;
  final WatchNetworkSource network;
  final RouteFeatureSource? features;

  /// Varianten in Kilometern gegenüber der Route (nur Rundwege).
  static const variantDeltas = [-4.0, -2.0, 2.0, 4.0];

  bool get isAvailable => ai.isConfigured;

  /// Varianten derselben Gegend: gleicher Start, gleiche Richtung, andere Länge. Scheitert eine, fehlt nur sie.
  Future<List<(WatchRouteKind, String, PlannedRoute)>> variants(
    PlannedRoute route, {
    void Function(String message)? onProgress,
  }) async {
    if (!route.isLoop || route.request.shape == RouteShape.direction) return const [];
    final start = route.points.first;
    final center = GeoPoint(
      route.points.fold(0.0, (sum, point) => sum + point.latitude) / route.points.length,
      route.points.fold(0.0, (sum, point) => sum + point.longitude) / route.points.length,
    );
    final bearing = Geo.distance(start, center) < 50 ? null : Geo.bearing(start, center);
    final kilometers = route.stats.distanceMeters / 1000;
    final max = RouteRequest.maxDistance(route.discipline) / 1000;
    final planner = RoutePlanner(backend, features: features);
    final result = <(WatchRouteKind, String, PlannedRoute)>[];
    for (final delta in variantDeltas) {
      final target = ((kilometers + delta) * 2).round() / 2;
      if (target < 1 || target > max) continue;
      final label = '${delta > 0 ? '+' : '−'}${GermanFormat.decimal(delta.abs())} km';
      onProgress?.call('Variante $label wird geplant …');
      try {
        final routes = await planner.generate(
          RouteRequest(
            discipline: route.discipline,
            shape: RouteShape.loop,
            start: start,
            bearingDegrees: bearing,
            distanceMeters: target * 1000,
            preferences: route.request.preferences,
          ),
          username: route.username,
          seed: route.id.codeUnits.fold(7, (hash, unit) => (hash * 31 + unit) & 0xffff),
          variants: const [RouteVariant.balanced],
        );
        result.add((delta < 0 ? WatchRouteKind.shorter : WatchRouteKind.longer, label, routes.first));
      } on Object {
        // Variante fehlt; die Route selbst geht trotzdem auf die Uhr.
      }
    }
    return result;
  }

  /// Paket bauen und hochladen. Wirft [WatchExportFailed] mit verständlicher Meldung.
  Future<WatchExportResult> export(PlannedRoute route, {void Function(String message)? onProgress}) async {
    if (!ai.isConfigured) {
      throw const WatchExportFailed('Dafür ist der eigene Worker nötig (Ich › KI › Worker).');
    }
    final variants = await this.variants(route, onProgress: onProgress);
    onProgress?.call('Wegenetz wird geladen …');
    final WatchPackage package;
    try {
      final osm = await network.network([route.points, for (final (_, _, variant) in variants) variant.points]);
      onProgress?.call('Paket für die Uhr wird gepackt …');
      package = WatchPackage.build(route: route, variants: variants, osm: osm);
    } on RoutingUnavailable catch (error) {
      throw WatchExportFailed('${error.message} Bitte gleich noch einmal versuchen.');
    } on WatchPackageTooLarge catch (error) {
      throw WatchExportFailed(error.message);
    }
    final bytes = package.encode();
    final chunks = WatchPackage.chunks(bytes);
    onProgress?.call('Wird hochgeladen …');
    try {
      await ai.send(
        'v1/watch/routes/${route.id}',
        method: 'PUT',
        body: utf8.encode(
          jsonEncode({
            'name': route.name,
            'distanceMeters': route.stats.distanceMeters.round(),
            'bytes': bytes.length,
            'chunks': chunks,
          }),
        ),
        timeout: const Duration(seconds: 60),
      );
    } on AIClientError catch (error) {
      throw WatchExportFailed('Hochladen hat nicht geklappt: ${error.message}');
    }
    return WatchExportResult(
      bytes: bytes.length,
      chunks: chunks.length,
      variants: variants.length,
      nodes: package.nodes.length,
    );
  }

  /// Uhr mit dem Code koppeln, den das Datenfeld anzeigt. Wirft [WatchExportFailed].
  Future<void> pair(String code) async {
    final cleaned = code.trim().toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (cleaned.length != 6) throw const WatchExportFailed('Der Code hat sechs Zeichen.');
    try {
      await ai.send('v1/watch/pair', method: 'POST', body: utf8.encode(jsonEncode({'code': cleaned})));
    } on AIHttpError catch (error) {
      throw WatchExportFailed(
        error.status == 404 ? 'Code unbekannt oder abgelaufen – öffne das Datenfeld erneut.' : error.message,
      );
    } on AIClientError catch (error) {
      throw WatchExportFailed(error.message);
    }
  }

  /// Wie viele Routen gerade für die Uhr bereitliegen (höchstens fünf).
  Future<int> routesOnWatch() async {
    try {
      final body = jsonDecode(utf8.decode(await ai.send('v1/watch/routes', method: 'GET')));
      return body is Map && body['routes'] is List ? math.min(5, (body['routes'] as List).length) : 0;
    } on Object {
      return 0;
    }
  }
}

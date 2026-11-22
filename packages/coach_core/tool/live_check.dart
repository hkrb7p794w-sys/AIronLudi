// Echttest des Routenplaners gegen die öffentlichen Dienste (nicht Teil der CI, nur von Hand):
//   cd packages/coach_core && dart run tool/live_check.dart
// Prüft, ob die Anfragen und das Lesen der Antworten (Valhalla, BRouter, Overpass, Photon, Nominatim, Open-Meteo)
// zu den echten Servern passen. Hält die Rate-Limits der Dienste ein (Pausen zwischen den Anfragen).
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';

const _userAgent = 'AIronLudi-Routenplaner/1.0 (Flutter)';
final _client = HttpClient()
  ..userAgent = _userAgent
  ..connectionTimeout = const Duration(seconds: 20);
const _timeout = Duration(seconds: 45);
var _failures = 0;

Future<(int, String)> _get(Uri uri) async {
  final request = await _client.getUrl(uri);
  request.headers.set('Accept-Language', 'de');
  final response = await request.close().timeout(_timeout);
  return (response.statusCode, await response.transform(utf8.decoder).join().timeout(_timeout));
}

Future<(int, String)> _post(Uri uri, String body, {String type = 'application/json'}) async {
  final request = await _client.postUrl(uri);
  request.headers.contentType = ContentType.parse(type);
  request.write(body);
  final response = await request.close().timeout(_timeout);
  return (response.statusCode, await response.transform(utf8.decoder).join().timeout(_timeout));
}

String _head(String text) => text.length > 300 ? text.substring(0, 300) : text;

Future<void> _check(String name, Future<String> Function() run) async {
  try {
    stdout.writeln('OK     $name: ${await run()}');
  } on Object catch (error) {
    _failures++;
    stdout.writeln('FEHLER $name: $error');
  }
}

Future<void> _pause([int milliseconds = 1300]) => Future<void>.delayed(Duration(milliseconds: milliseconds));

/// Echter Router für den Planer-Test: Valhalla mit Pause zwischen den Anfragen.
final class _LiveValhalla implements RoutingBackend {
  int requests = 0;

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    await _pause(1200);
    requests++;
    final body = ValhallaFormat.routeBody(
      waypoints,
      discipline: discipline,
      variant: variant,
      elevationGain: elevationGain,
      distanceMeters: distanceMeters,
      preferences: preferences,
    );
    final (status, text) = await _post(ValhallaFormat.routeUri, jsonEncode(body));
    final json = jsonDecode(text);
    if (status >= 500) throw RoutingUnavailable('Status $status');
    return ValhallaFormat.parseRoute(json);
  }

  @override
  Future<List<double?>> elevations(List<GeoPoint> points) async {
    await _pause(1200);
    requests++;
    final (status, text) = await _post(ValhallaFormat.heightUri, jsonEncode(ValhallaFormat.heightBody(points)));
    if (status != 200) throw RoutingUnavailable('Status $status');
    return ValhallaFormat.parseHeight(jsonDecode(text), points.length);
  }
}

Future<void> _planner() async {
  const start = GeoPoint(52.5163, 13.3777);
  final cases = [
    const RouteRequest(discipline: RouteDiscipline.run, shape: RouteShape.loop, start: start, distanceMeters: 10000),
    const RouteRequest(
      discipline: RouteDiscipline.roadBike,
      shape: RouteShape.loop,
      start: start,
      distanceMeters: 40000,
    ),
    const RouteRequest(
      discipline: RouteDiscipline.walk,
      shape: RouteShape.direction,
      start: start,
      distanceMeters: 4000,
      bearingDegrees: 90,
    ),
    RouteRequest(
      discipline: RouteDiscipline.gravel,
      shape: RouteShape.toDestination,
      start: start,
      destination: Geo.destination(start, 200, 6000),
      distanceMeters: 15000,
    ),
  ];
  for (final request in cases) {
    final backend = _LiveValhalla();
    final watch = Stopwatch()..start();
    await _check(
      'Planer ${request.discipline.rawValue} ${request.shape.rawValue} ${request.distanceMeters ~/ 1000} km',
      () async {
        final routes = await RoutePlanner(backend).generate(request, username: 'test', seed: 7);
        final parts = [
          for (final route in routes)
            '${route.variant.rawValue} ${(route.stats.distanceMeters / 10).round() / 100} km '
                '(${((route.stats.distanceMeters / request.distanceMeters - 1) * 1000).round() / 10} %) '
                '↑${route.stats.ascentMeters.round()}',
        ];
        return '${parts.join(' | ')} · ${backend.requests} Anfragen, ${watch.elapsed.inSeconds} s';
      },
    );
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--planer')) {
    await _planner();
    _client.close();
    stdout.writeln(_failures == 0 ? 'Alle Prüfungen bestanden.' : '$_failures Prüfungen fehlgeschlagen.');
    exitCode = _failures == 0 ? 0 : 1;
    return;
  }
  const start = GeoPoint(52.5163, 13.3777); // Berlin, Brandenburger Tor
  final waypoints = RouteWaypointPlanner.loop(start: start, geometricLength: 8000, bearingDegrees: 30);

  for (final discipline in RouteDiscipline.values) {
    await _check('Valhalla ${discipline.rawValue}', () async {
      final body = ValhallaFormat.routeBody(waypoints, discipline: discipline, variant: RouteVariant.balanced);
      final (status, text) = await _post(ValhallaFormat.routeUri, jsonEncode(body));
      if (status != 200) throw 'Status $status ${_head(text)}';
      final path = ValhallaFormat.parseRoute(jsonDecode(text));
      return '${path.points.length} Punkte, ${path.distanceMeters.round()} m';
    });
    await _pause();
  }

  await _check('Valhalla Höhe', () async {
    final (status, text) = await _post(ValhallaFormat.heightUri, jsonEncode(ValhallaFormat.heightBody(waypoints)));
    if (status != 200) throw 'Status $status ${_head(text)}';
    return '${ValhallaFormat.parseHeight(jsonDecode(text), waypoints.length)}';
  });
  await _pause();

  for (final discipline in RouteDiscipline.values) {
    for (final preferences in [
      <RoutePreference>{},
      {RoutePreference.nature},
      {RoutePreference.paved},
    ]) {
      final uri = BRouterFormat.uri(
        waypoints,
        discipline: discipline,
        variant: RouteVariant.balanced,
        preferences: preferences,
      );
      await _check('BRouter ${uri.queryParameters['profile']} (${discipline.rawValue})', () async {
        final (status, text) = await _get(uri);
        if (status != 200) throw 'Status $status ${_head(text)}';
        final path = BRouterFormat.parse(text);
        return '${path.points.length} Punkte, ${path.distanceMeters.round()} m, Höhe ${path.hasElevation}';
      });
      await _pause(1600);
    }
  }

  for (final preferences in [
    {RoutePreference.water},
    {RoutePreference.nature},
    {RoutePreference.paved},
  ]) {
    for (final uri in OverpassFormat.uris) {
      await _check('Overpass ${preferences.first.rawValue} (${uri.host})', () async {
        final query = OverpassFormat.query(start, 2500, preferences, discipline: RouteDiscipline.roadBike);
        final watch = Stopwatch()..start();
        final (status, text) = await _post(
          uri,
          'data=${Uri.encodeQueryComponent(query)}',
          type: 'application/x-www-form-urlencoded',
        );
        if (status != 200) throw 'Status $status ${_head(text)}';
        final points = OverpassFormat.parse(jsonDecode(text));
        if (points.isEmpty) throw 'keine Punkte';
        return '${points.length} Punkte in ${watch.elapsedMilliseconds} ms';
      });
      await _pause(2500);
    }
  }

  await _check('Photon', () async {
    final (status, text) = await _get(GeocodingFormat.photonUri('Hauptstraße 5 Berlin', near: start));
    if (status != 200) throw 'Status $status ${_head(text)}';
    final places = GeocodingFormat.parsePhoton(jsonDecode(text));
    if (places.isEmpty) throw 'keine Treffer';
    return places.take(3).map((place) => place.label).join(' | ');
  });
  await _pause();

  await _check('Nominatim', () async {
    final (status, text) = await _get(GeocodingFormat.nominatimUri('Tempelhofer Feld Berlin'));
    if (status != 200) throw 'Status $status ${_head(text)}';
    final places = GeocodingFormat.parseNominatim(jsonDecode(text));
    if (places.isEmpty) throw 'keine Treffer';
    return places.take(3).map((place) => place.label).join(' | ');
  });

  _client.close();
  stdout.writeln(_failures == 0 ? 'Alle Prüfungen bestanden.' : '$_failures Prüfungen fehlgeschlagen.');
  exitCode = _failures == 0 ? 0 : 1;
}

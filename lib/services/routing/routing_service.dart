import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';

import '../http/http_transport.dart';

/// Ein Router hinter dem Routenplaner (Valhalla oder BRouter).
abstract interface class RoutingEngine {
  String get name;

  bool get supportsElevation;

  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  });

  Future<List<double?>> elevations(List<GeoPoint> points);
}

/// Hält einen Mindestabstand zwischen Anfragen an denselben Dienst ein (öffentliche Server: höchstens etwa eine
/// Anfrage je Sekunde) und reiht gleichzeitige Anfragen nacheinander ein.
final class RateGate {
  RateGate(this.interval, {DateTime Function()? now, Future<void> Function(Duration)? wait})
    : _now = now ?? DateTime.now,
      _wait = wait ?? Future<void>.delayed;

  final Duration interval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  DateTime? _next;
  Future<void> _queue = Future.value();

  /// Pause nach einem 429 („zu viele Anfragen“).
  void backOff(Duration duration) {
    final until = _now().add(duration);
    if (_next == null || until.isAfter(_next!)) _next = until;
  }

  Future<T> run<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      final next = _next;
      if (next != null) {
        final delay = next.difference(_now());
        if (delay > Duration.zero) await _wait(delay);
      }
      _next = _now().add(interval);
      return action();
    });
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// Gemeinsame HTTP-Behandlung: Status 429/5xx als [RoutingUnavailable] (mit `Retry-After`), fehlende Antwort ebenso.
abstract base class _HttpEngine implements RoutingEngine {
  _HttpEngine(this.transport, {required this.gate});

  final HttpTransport transport;
  final RateGate gate;

  static const userAgent = 'AIronLudi-Routenplaner/1.0 (Flutter)';

  Future<HttpResponse> send(HttpRequest request) => gate.run(() async {
    final HttpResponse response;
    try {
      response = await transport.send(request);
    } on HttpTransportException catch (error) {
      throw RoutingUnavailable('$name nicht erreichbar: ${error.message}');
    }
    if (response.status == 429 || response.status >= 500) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      final retry = Duration(seconds: seconds ?? (response.status == 429 ? 5 : 2));
      gate.backOff(retry);
      throw RoutingUnavailable(
        response.status == 429 ? '$name: zu viele Anfragen, bitte kurz warten.' : '$name ist gerade gestört.',
        retryAfter: retry,
      );
    }
    return response;
  });

  static Object? decode(HttpResponse response) {
    try {
      return jsonDecode(utf8.decode(response.body));
    } on FormatException {
      return null;
    }
  }
}

/// Valhalla auf dem Server der FOSSGIS (OSM-Daten, Höhen über `/height`), ohne Schlüssel.
final class ValhallaEngine extends _HttpEngine {
  ValhallaEngine(super.transport, {RateGate? gate}) : super(gate: gate ?? RateGate(const Duration(milliseconds: 1100)));

  @override
  String get name => ValhallaFormat.engineName;

  @override
  bool get supportsElevation => true;

  HttpRequest _post(Uri uri, Map<String, Object?> body) => HttpRequest(
    method: 'POST',
    url: uri,
    headers: const {'Content-Type': 'application/json', 'User-Agent': _HttpEngine.userAgent},
    body: utf8.encode(jsonEncode(body)),
    timeout: const Duration(seconds: 30),
  );

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    final response = await send(
      _post(
        ValhallaFormat.routeUri,
        ValhallaFormat.routeBody(
          waypoints,
          discipline: discipline,
          variant: variant,
          elevationGain: elevationGain,
          distanceMeters: distanceMeters,
          preferences: preferences,
        ),
      ),
    );
    final json = _HttpEngine.decode(response);
    if (!response.isSuccess && json == null) throw RoutingUnavailable('$name antwortet mit Status ${response.status}.');
    return ValhallaFormat.parseRoute(json);
  }

  @override
  Future<List<double?>> elevations(List<GeoPoint> points) async {
    final response = await send(_post(ValhallaFormat.heightUri, ValhallaFormat.heightBody(points)));
    if (!response.isSuccess) throw RoutingUnavailable('Höhendaten gerade nicht verfügbar (${response.status}).');
    return ValhallaFormat.parseHeight(_HttpEngine.decode(response), points.length);
  }
}

/// BRouter (`brouter.de`) als Ausweich-Router; Höhen kommen mit der Strecke.
final class BRouterEngine extends _HttpEngine {
  BRouterEngine(super.transport, {RateGate? gate}) : super(gate: gate ?? RateGate(const Duration(milliseconds: 1500)));

  @override
  String get name => BRouterFormat.engineName;

  @override
  bool get supportsElevation => false;

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    final response = await send(
      HttpRequest(
        method: 'GET',
        url: BRouterFormat.uri(waypoints, discipline: discipline, variant: variant, preferences: preferences),
        headers: const {'User-Agent': _HttpEngine.userAgent},
        timeout: const Duration(seconds: 40),
      ),
    );
    final body = utf8.decode(response.body, allowMalformed: true);
    if (!response.isSuccess) throw NoRouteFound(body.trim().isEmpty ? 'Kein Weg gefunden.' : body.trim());
    return BRouterFormat.parse(body);
  }

  @override
  Future<List<double?>> elevations(List<GeoPoint> points) =>
      Future.error(const RoutingUnavailable('BRouter liefert keine Höhen einzeln.'));
}

/// Router mit Ausweichen: zuerst Valhalla, bei Störung (nicht bei „kein Weg“) BRouter. Ein gestörter Router wird
/// für [cooldown] übersprungen. Gleiche Anfragen kommen aus dem Zwischenspeicher (z. B. nach „Neu würfeln“ zurück).
final class FallbackRoutingBackend implements RoutingBackend {
  FallbackRoutingBackend(this.engines, {this.cooldown = const Duration(minutes: 2), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final List<RoutingEngine> engines;
  final Duration cooldown;
  final DateTime Function() _now;
  final Map<String, DateTime> _disabledUntil = {};
  final Map<String, RoutedPath> _cache = {};

  static const _maxCache = 40;

  factory FallbackRoutingBackend.standard(HttpTransport transport) =>
      FallbackRoutingBackend([ValhallaEngine(transport), BRouterEngine(transport)]);

  bool _available(RoutingEngine engine) {
    final until = _disabledUntil[engine.name];
    return until == null || _now().isAfter(until);
  }

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    final key = [
      discipline.rawValue,
      variant.rawValue,
      elevationGain?.round(),
      distanceMeters?.round(),
      [
        for (final preference in RoutePreference.values)
          if (preferences.contains(preference)) preference.rawValue,
      ].join(),
      Geo.encodePolyline(waypoints),
    ].join('|');
    if (_cache[key] case final cached?) return cached;
    RoutingUnavailable? lastProblem;
    final candidates = engines.where(_available).toList();
    for (final engine in candidates.isEmpty ? engines : candidates) {
      try {
        final path = await engine.route(
          waypoints,
          discipline: discipline,
          variant: variant,
          elevationGain: elevationGain,
          distanceMeters: distanceMeters,
          preferences: preferences,
        );
        if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
        return _cache[key] = path;
      } on RoutingUnavailable catch (error) {
        lastProblem = error;
        _disabledUntil[engine.name] = _now().add(
          error.retryAfter == null ? cooldown : Duration(seconds: math.max(error.retryAfter!.inSeconds, 10)),
        );
      }
    }
    throw lastProblem ?? const RoutingUnavailable('Kein Router erreichbar.');
  }

  @override
  Future<List<double?>> elevations(List<GeoPoint> points) async {
    RoutingUnavailable? lastProblem;
    for (final engine in engines.where((engine) => engine.supportsElevation)) {
      try {
        return await engine.elevations(points);
      } on RoutingUnavailable catch (error) {
        lastProblem = error;
      }
    }
    throw lastProblem ?? const RoutingUnavailable('Keine Höhendaten verfügbar.');
  }
}

/// Wege der gewünschten Art aus OpenStreetMap über die Overpass-API (ohne Schlüssel, höchstens eine Anfrage je zwei
/// Sekunden). Fehler ergeben eine leere Liste: Der Planer routet dann nur mit der Wegbewertung.
final class OverpassFeatureSource implements RouteFeatureSource {
  OverpassFeatureSource(this.transport, {RateGate? gate}) : gate = gate ?? RateGate(const Duration(seconds: 2));

  final HttpTransport transport;
  final RateGate gate;
  final Map<String, List<GeoPoint>> _cache = {};

  @override
  Future<List<GeoPoint>> attractors(
    GeoPoint center,
    double radiusMeters,
    Set<RoutePreference> preferences, {
    RouteDiscipline discipline = RouteDiscipline.run,
  }) async {
    final query = OverpassFormat.query(center, radiusMeters, preferences, discipline: discipline);
    if (_cache[query] case final cached?) return cached;
    try {
      final response = await gate.run(
        () => transport.send(
          HttpRequest(
            method: 'POST',
            url: OverpassFormat.uri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'User-Agent': _HttpEngine.userAgent,
            },
            body: utf8.encode('data=${Uri.encodeQueryComponent(query)}'),
            timeout: const Duration(seconds: 30),
          ),
        ),
      );
      if (response.status == 429 || response.status >= 500) {
        gate.backOff(Duration(seconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 10));
        return const [];
      }
      if (!response.isSuccess) return const [];
      final points = OverpassFormat.parse(_HttpEngine.decode(response));
      if (_cache.length >= 20) _cache.remove(_cache.keys.first);
      return _cache[query] = points;
    } on Object {
      return const [];
    }
  }
}

/// Adresssuche: Photon (Vorschläge beim Tippen, nach Nähe sortiert), bei ausdrücklicher Suche ersatzweise Nominatim
/// (höchstens eine Anfrage je Sekunde, nie beim Tippen – Nutzungsregeln der OSM Foundation). Gleiche Anfragen kommen
/// aus dem Zwischenspeicher.
final class OsmPlaceSearch implements PlaceSearch {
  OsmPlaceSearch(this.transport, {RateGate? photonGate, RateGate? nominatimGate})
    : photonGate = photonGate ?? RateGate(const Duration(milliseconds: 600)),
      nominatimGate = nominatimGate ?? RateGate(const Duration(milliseconds: 1100));

  final HttpTransport transport;
  final RateGate photonGate;
  final RateGate nominatimGate;
  final Map<String, List<Place>> _cache = {};

  @override
  Future<List<Place>> search(String query, {GeoPoint? near, bool typing = false}) async {
    if (GeocodingFormat.coordinates(query) case final point?) {
      return [Place(title: 'Koordinaten', detail: query.trim(), point: point)];
    }
    final text = GeocodingFormat.normalized(query);
    if (text == null) return const [];
    final key =
        '$text|${near == null ? '' : '${near.latitude.toStringAsFixed(2)},${near.longitude.toStringAsFixed(2)}'}';
    if (_cache[key] case final cached?) return cached;
    RoutingUnavailable? problem;
    try {
      final places = await _get(photonGate, GeocodingFormat.photonUri(text, near: near), GeocodingFormat.parsePhoton);
      if (places.isNotEmpty || typing) return _remember(key, places);
    } on RoutingUnavailable catch (error) {
      if (typing) rethrow;
      problem = error;
    }
    try {
      return _remember(
        key,
        await _get(nominatimGate, GeocodingFormat.nominatimUri(text), GeocodingFormat.parseNominatim),
      );
    } on RoutingUnavailable {
      if (problem != null) throw problem;
      rethrow;
    }
  }

  List<Place> _remember(String key, List<Place> places) {
    if (_cache.length >= 50) _cache.remove(_cache.keys.first);
    return _cache[key] = places;
  }

  Future<List<Place>> _get(RateGate gate, Uri uri, List<Place> Function(Object? json) parse) => gate.run(() async {
    final HttpResponse response;
    try {
      response = await transport.send(
        HttpRequest(
          method: 'GET',
          url: uri,
          headers: const {'User-Agent': _HttpEngine.userAgent, 'Accept-Language': 'de'},
          timeout: const Duration(seconds: 15),
        ),
      );
    } on HttpTransportException catch (error) {
      throw RoutingUnavailable('Adresssuche nicht erreichbar: ${error.message}');
    }
    if (response.status == 429) {
      gate.backOff(const Duration(seconds: 5));
      throw const RoutingUnavailable('Adresssuche: zu viele Anfragen, bitte kurz warten.');
    }
    if (!response.isSuccess) throw RoutingUnavailable('Adresssuche gestört (${response.status}).');
    return parse(_HttpEngine.decode(response));
  });
}

// Routenplaner und Gebiete (neu in AIronLudi, keine Swift-Vorlage): Geometrie, Wegpunkte, Router-Formate, Planer mit
// Test-Router, Export (GPX, FIT-Kurs) und Erkundung je Benutzer.
import 'dart:convert';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const berlin = GeoPoint(52.5200, 13.4050);
const hamburg = GeoPoint(53.5511, 9.9937);

/// Test-Router: läuft die Wegpunkte ab und tut so, als wäre das Wegenetz um [factor] länger als die Luftlinie.
final class FakeBackend implements RoutingBackend {
  FakeBackend({this.factor = 1.4, this.failFirst = 0, this.unavailable = false, this.hill = 0});

  final double factor;
  int failFirst;
  final bool unavailable;

  /// Höhe = Breitengrad-Abweichung × [hill] (für Höhenmeter).
  final double hill;
  final List<List<GeoPoint>> calls = [];
  final List<RouteVariant> variants = [];
  final List<Set<RoutePreference>> preferences = [];
  int heightCalls = 0;

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    calls.add(waypoints);
    this.preferences.add(preferences);
    variants.add(variant);
    if (unavailable) throw const RoutingUnavailable('Dienst gestört');
    if (failFirst > 0) {
      failFirst--;
      throw const NoRouteFound('Punkt im See');
    }
    final points = <GeoPoint>[];
    for (var index = 1; index < waypoints.length; index++) {
      final a = waypoints[index - 1];
      final b = waypoints[index];
      for (var step = 0; step < 20; step++) {
        final t = step / 20;
        points.add(GeoPoint(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t));
      }
    }
    points.add(waypoints.last);
    return RoutedPath(points: points, distanceMeters: Geo.length(points) * factor, engine: 'Test');
  }

  @override
  Future<List<double?>> elevations(List<GeoPoint> points) async {
    heightCalls++;
    return [for (final point in points) 100 + (point.latitude - berlin.latitude).abs() * hill];
  }
}

final class FakeFeatures implements RouteFeatureSource {
  FakeFeatures(this.points, {this.fails = false});

  final List<GeoPoint> points;
  final bool fails;
  int requests = 0;

  @override
  Future<List<GeoPoint>> attractors(
    GeoPoint center,
    double radiusMeters,
    Set<RoutePreference> preferences, {
    RouteDiscipline discipline = RouteDiscipline.run,
  }) async {
    requests++;
    if (fails) throw const RoutingUnavailable('Overpass gestört');
    return points;
  }
}

/// Router, dessen Umwegfaktor mit der Größe der Runde wächst (nichtlinear wie echte Wegenetze).
final class CurvedBackend extends FakeBackend {
  double lastDistance = 0;

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    final path = await super.route(waypoints, discipline: discipline, variant: variant);
    final straight = Geo.length(path.points);
    final factor = 1.2 + 0.4 * (straight / 20000).clamp(0, 1);
    lastDistance = straight * factor;
    return RoutedPath(points: path.points, distanceMeters: lastDistance, engine: 'Test');
  }
}

void main() {
  group('Geo', () {
    test('Abstand, Richtung und Zielpunkt', () {
      expect(Geo.distance(berlin, hamburg), closeTo(255000, 2000));
      expect(Geo.bearing(berlin, const GeoPoint(53.52, 13.405)), closeTo(0, 0.01));
      expect(Geo.bearing(berlin, const GeoPoint(52.52, 14.0)), closeTo(90, 0.5));
      final target = Geo.destination(berlin, 135, 5000);
      expect(Geo.distance(berlin, target), closeTo(5000, 1));
      expect(Geo.bearing(berlin, target), closeTo(135, 0.1));
    });

    test('Polylinie wie Google (Genauigkeit 5) und Valhalla (6)', () {
      final decoded = Geo.decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5);
      expect(decoded.map((point) => [point.latitude, point.longitude]), [
        [38.5, -120.2],
        [40.7, -120.95],
        [43.252, -126.453],
      ]);
      expect(Geo.encodePolyline(decoded, precision: 5), '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      final line = [berlin, const GeoPoint(52.523456, 13.401234), hamburg];
      final round = Geo.decodePolyline(Geo.encodePolyline(line));
      for (final (index, point) in round.indexed) {
        expect(point.latitude, closeTo(line[index].latitude, 1e-6));
        expect(point.longitude, closeTo(line[index].longitude, 1e-6));
      }
    });

    test('Fläche, Punkt im Polygon, Vereinfachung', () {
      final north = Geo.destination(berlin, 0, 1000);
      final northEast = Geo.destination(north, 90, 1000);
      final east = Geo.destination(berlin, 90, 1000);
      final square = [berlin, north, northEast, east];
      expect(Geo.area(square), closeTo(1e6, 1e4));
      expect(Geo.contains(square, Geo.destination(Geo.destination(berlin, 0, 500), 90, 500)), isTrue);
      expect(Geo.contains(square, Geo.destination(berlin, 180, 200)), isFalse);
      // Fast gerade Linie mit 2 m Ausschlag: auf Anfang und Ende vereinfacht.
      final straight = [
        for (var index = 0; index <= 10; index++)
          Geo.destination(Geo.destination(berlin, 90, index * 100.0), 0, index.isEven ? 0 : 2),
      ];
      expect(Geo.simplify(straight, 5), [straight.first, straight.last]);
      expect(Geo.simplify(straight, 1).length, straight.length);
      expect(Geo.thin(straight, 3), [straight.first, straight[5], straight.last]);
    });

    test('Punkt als JSON', () {
      const point = GeoPoint(52.1234567, 13.7654321, elevation: 34.56);
      expect(point.toJson(), [52.123457, 13.765432, 34.6]);
      expect(GeoPoint.fromJson([52.1, 13.2]), const GeoPoint(52.1, 13.2));
      expect(GeoPoint.fromJson([95, 13]), isNull);
      expect(GeoPoint.fromJson('x'), isNull);
    });
  });

  group('Vorgaben und Wegpunkte', () {
    RouteRequest loop({double distance = 10000, double? gain}) => RouteRequest(
      discipline: RouteDiscipline.run,
      shape: RouteShape.loop,
      start: berlin,
      distanceMeters: distance,
      elevationGainMeters: gain,
    );

    test('Prüfung der Eingaben', () {
      expect(loop().problem, isNull);
      expect(loop(distance: 500).problem, contains('mindestens 1 km'));
      expect(loop(distance: 70000).problem, contains('Höchstens 60 km'));
      expect(
        const RouteRequest(
          discipline: RouteDiscipline.roadBike,
          shape: RouteShape.toDestination,
          start: berlin,
          distanceMeters: 40000,
        ).problem,
        contains('Zielpunkt'),
      );
      expect(
        const RouteRequest(
          discipline: RouteDiscipline.gravel,
          shape: RouteShape.direction,
          start: berlin,
          distanceMeters: 40000,
        ).problem,
        contains('Himmelsrichtung'),
      );
      expect(loop().withinTolerance(10240), isTrue);
      expect(loop().withinTolerance(10300), isFalse);
      expect(
        RouteRequest.fromJson(jsonDecode(jsonEncode(loop(gain: 200).toJson())))!.toJson(),
        loop(gain: 200).toJson(),
      );
    });

    test('Rundweg beginnt und endet am Start und hat etwa die geplante Größe', () {
      final points = RouteWaypointPlanner.loop(start: berlin, geometricLength: 8000, bearingDegrees: 45, seed: 3);
      expect(points.length, 5);
      expect(points.first, berlin);
      expect(points.last, berlin);
      expect(Geo.length(points), inInclusiveRange(8000 * 0.75, 8000 * 1.15));
      // Gleicher Startwert: gleiche Punkte (Neu würfeln nur mit neuem Startwert).
      expect(RouteWaypointPlanner.loop(start: berlin, geometricLength: 8000, bearingDegrees: 45, seed: 3), points);
    });

    test('Zum Ziel: direkt, wenn weit genug; sonst Umweg auf der gewählten Seite', () {
      final destination = Geo.destination(berlin, 90, 5000);
      expect(RouteWaypointPlanner.toDestination(start: berlin, destination: destination, geometricLength: 4000), [
        berlin,
        destination,
      ]);
      final detour = RouteWaypointPlanner.toDestination(start: berlin, destination: destination, geometricLength: 8000);
      expect(detour.length, 3);
      expect(Geo.length(detour), closeTo(8000, 50));
      // Rechts von Ost = Süden.
      expect(detour[1].latitude, lessThan(berlin.latitude));
      final left = RouteWaypointPlanner.toDestination(
        start: berlin,
        destination: destination,
        geometricLength: 8000,
        side: -1,
      );
      expect(left[1].latitude, greaterThan(berlin.latitude));
    });

    test('Richtung: Endpunkt liegt in der gewählten Himmelsrichtung', () {
      final points = RouteWaypointPlanner.direction(start: berlin, geometricLength: 6000, bearingDegrees: 270);
      expect(Geo.distance(berlin, points.last), closeTo(6000, 1));
      expect(Geo.bearing(berlin, points.last), closeTo(270, 0.5));
      expect(CompassDirection.nearest(100), CompassDirection.east);
      expect(CompassDirection.nearest(350), CompassDirection.north);
    });

    test('Varianten zeigen in verschiedene Richtungen', () {
      final bearings = {
        for (final variant in RouteVariant.values) RouteWaypointPlanner.bearingFor(seed: 7, variant: variant).round(),
      };
      expect(bearings.length, 3);
      expect(RouteWaypointPlanner.bearingFor(seed: 7, variant: RouteVariant.balanced, preferred: 90), 90);
      expect(
        RouteWaypointPlanner.rescale(geometricLength: 8000, routedMeters: 12000, targetMeters: 10000),
        closeTo(6666.7, 0.1),
      );
      expect(RouteWaypointPlanner.rescale(geometricLength: 8000, routedMeters: 100, targetMeters: 10000), 20000);
    });
  });

  group('Höhe, Dauer, Bewertung', () {
    test('Anstieg mit Rauschschwelle', () {
      List<GeoPoint> line(List<double> heights, {double spacing = 100}) => [
        for (final (index, height) in heights.indexed)
          Geo.destination(berlin, 90, index * spacing).withElevation(height),
      ];
      // Punkte weiter auseinander als das Glättungsfenster: nur die Schwelle wirkt.
      final stats = RouteStats.of(line([100, 101, 102, 101, 110, 120, 118, 119, 100], spacing: 400));
      expect(stats.ascentMeters, 20);
      expect(stats.descentMeters, 20);
      expect(stats.minElevation, 100);
      expect(stats.maxElevation, 120);
      expect(stats.distanceMeters, closeTo(3200, 2));
      // Rauschen des Geländemodells (±4 m alle 20 m) auf flacher Strecke: kaum Höhenmeter.
      final noisy = line([for (var index = 0; index < 250; index++) 40 + (index.isEven ? 4.0 : -4.0)], spacing: 20);
      expect(RouteStats.of(noisy).ascentMeters, lessThan(5));
      // Echter Anstieg (100 m auf 2 km) bleibt erhalten.
      final climb = line([for (var index = 0; index <= 100; index++) 50 + index.toDouble()], spacing: 20);
      expect(RouteStats.of(climb).ascentMeters, closeTo(100, 12));
      expect(RouteStats.of([berlin, hamburg]).hasElevation, isFalse);
      final profile = RouteStats.profile(line(List.filled(300, 50)), samples: 50);
      expect(profile.length, lessThanOrEqualTo(51));
      expect(profile.last.kilometers, closeTo(29.9, 0.01));
    });

    test('Dauer: Laufen mit Steigungszuschlag, Rad nach Geschwindigkeit', () {
      expect(
        RouteDuration.estimate(discipline: RouteDiscipline.run, distanceMeters: 10000, ascentMeters: 0),
        const Duration(minutes: 60),
      );
      // 4:00 Schwelle → 5:00 locker; 100 hm ≙ 800 m.
      expect(
        RouteDuration.estimate(
          discipline: RouteDiscipline.run,
          distanceMeters: 10000,
          ascentMeters: 100,
          runThresholdPace: 240,
        ),
        const Duration(seconds: 3240),
      );
      expect(
        RouteDuration.estimate(discipline: RouteDiscipline.roadBike, distanceMeters: 50000, ascentMeters: 0),
        const Duration(hours: 2),
      );
      expect(
        RouteDuration.estimate(discipline: RouteDiscipline.gravel, distanceMeters: 19000, ascentMeters: 550),
        const Duration(minutes: 90),
      );
    });

    test('Hin und zurück zählt als Doppelung, eine Runde nicht', () {
      final out = [for (var index = 0; index <= 40; index++) Geo.destination(berlin, 0, index * 50.0)];
      final outAndBack = [...out, ...out.reversed.skip(1)];
      expect(RouteScore.overlap(outAndBack), greaterThan(0.35));
      final ring = [
        for (var angle = 0; angle <= 360; angle += 5)
          Geo.destination(Geo.destination(berlin, 0, 1000), angle + 180.0, 1000),
      ];
      expect(RouteScore.overlap(ring), lessThan(0.05));
    });

    test('Bewertung: Toleranz, Höhenvorgabe, Höhenmeter-Fokus', () {
      const request = RouteRequest(
        discipline: RouteDiscipline.run,
        shape: RouteShape.loop,
        start: berlin,
        distanceMeters: 10000,
        elevationGainMeters: 200,
      );
      RouteStats stats(double distance, double ascent) => RouteStats(
        distanceMeters: distance,
        ascentMeters: ascent,
        descentMeters: ascent,
        minElevation: 0,
        maxElevation: 1,
      );
      double score(double distance, double ascent, {RouteVariant variant = RouteVariant.balanced}) =>
          RouteScore.of(request: request, variant: variant, stats: stats(distance, ascent), overlap: 0);
      expect(score(10200, 200), lessThan(score(11500, 200)));
      expect(score(10000, 190), lessThan(score(10000, 60)));
      expect(score(10000, 60, variant: RouteVariant.hilly), greaterThan(score(10000, 60)));
    });
  });

  group('Router-Formate', () {
    test('Valhalla: Anfrage je Disziplin und Variante', () {
      final body = ValhallaFormat.routeBody(
        [berlin, const GeoPoint(52.53, 13.41), berlin],
        discipline: RouteDiscipline.roadBike,
        variant: RouteVariant.green,
      );
      expect(body['costing'], 'bicycle');
      final locations = body['locations']! as List<Object?>;
      expect([for (final location in locations) (location! as Map)['type']], ['break', 'through', 'break']);
      final options = (body['costing_options']! as Map)['bicycle'] as Map;
      expect(options['bicycle_type'], 'Road');
      expect(options['use_roads'], 0.1);
      expect(ValhallaFormat.costing(RouteDiscipline.run, RouteVariant.balanced).costing, 'pedestrian');
      expect(ValhallaFormat.costing(RouteDiscipline.gravel, RouteVariant.balanced).options['bicycle_type'], 'Cross');
      // Flache Vorgabe (50 hm auf 20 km): Hügel meiden, auch beim Höhenmeter-Fokus.
      final flat = ValhallaFormat.costing(
        RouteDiscipline.run,
        RouteVariant.hilly,
        elevationGain: 50,
        distanceMeters: 20000,
      );
      expect(flat.options['use_hills'], closeTo(0.125, 1e-9));
      expect(ValhallaFormat.costing(RouteDiscipline.run, RouteVariant.hilly).options['use_hills'], 1.0);
    });

    test('Valhalla: Antwort, Fehler und Höhen', () {
      final line = [berlin, const GeoPoint(52.53, 13.41), const GeoPoint(52.54, 13.42)];
      final path = ValhallaFormat.parseRoute({
        'trip': {
          'legs': [
            {'shape': Geo.encodePolyline(line.sublist(0, 2))},
            {'shape': Geo.encodePolyline(line.sublist(1))},
          ],
          'summary': {'length': 2.5},
        },
      });
      expect(path.points.length, 3);
      expect(path.distanceMeters, 2500);
      expect(path.hasElevation, isFalse);
      expect(
        () => ValhallaFormat.parseRoute({'error_code': 442, 'error': 'No path could be found for input'}),
        throwsA(isA<NoRouteFound>()),
      );
      expect(() => ValhallaFormat.parseRoute({'error_code': 503, 'error': 'busy'}), throwsA(isA<RoutingUnavailable>()));
      expect(() => ValhallaFormat.parseRoute('kaputt'), throwsA(isA<RoutingUnavailable>()));
      expect(ValhallaFormat.heightBody(line)['encoded_polyline'], Geo.encodePolyline(line));
      expect(
        ValhallaFormat.parseHeight({
          'height': [34, 35.5, -32768],
        }, 3),
        [34, 35.5, null],
      );
      expect(
        () => ValhallaFormat.parseHeight({
          'height': [1],
        }, 3),
        throwsA(isA<RoutingUnavailable>()),
      );
    });

    test('BRouter: Anfrage, GeoJSON mit Höhe, Klartext-Fehler', () {
      final uri = BRouterFormat.uri(
        [berlin, hamburg],
        discipline: RouteDiscipline.gravel,
        variant: RouteVariant.balanced,
      );
      expect(uri.host, 'brouter.de');
      expect(uri.queryParameters['lonlats'], '13.405000,52.520000|9.993700,53.551100');
      expect(uri.queryParameters['profile'], 'gravel');
      final path = BRouterFormat.parse(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': {'track-length': '1234', 'filtered ascend': '12'},
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [13.405, 52.52, 34.0],
                  [13.41, 52.53, 41.5],
                ],
              },
            },
          ],
        }),
      );
      expect(path.distanceMeters, 1234);
      expect(path.hasElevation, isTrue);
      expect(path.points.last.elevation, 41.5);
      expect(() => BRouterFormat.parse('target island detected for section 0'), throwsA(isA<NoRouteFound>()));
    });
  });

  group('Planer', () {
    var counter = 0;
    RoutePlanner planner(RoutingBackend backend) =>
        RoutePlanner(backend, newID: () => 'id${counter++}', now: () => DateTime.utc(2026, 11, 21, 8));

    test('Rundweg: drei Varianten in der Toleranz, mit Höhen und Benutzer', () async {
      final backend = FakeBackend(hill: 3000);
      const request = RouteRequest(
        discipline: RouteDiscipline.run,
        shape: RouteShape.loop,
        start: berlin,
        distanceMeters: 10000,
      );
      final routes = await planner(backend).generate(request, username: 'anna', seed: 4);
      expect(routes.length, 3);
      expect(routes.map((route) => route.variant), RouteVariant.values);
      for (final route in routes) {
        expect(route.username, 'anna');
        expect(route.points.first.latitude, closeTo(berlin.latitude, 1e-6));
        expect(route.stats.hasElevation, isTrue);
        // Gespeicherte Linie ist die geroutete (ohne Umwegfaktor des Test-Routers); der Router meldet 10 km ± 7 %.
        expect(route.stats.distanceMeters * 1.4, inInclusiveRange(9750, 10250));
      }
      // Höchstens sechs Router-Anfragen je Variante.
      expect(backend.calls.length, lessThanOrEqualTo(18));
      // Gleicher Startwert: gleiche Wegpunkte.
      final again = FakeBackend(hill: 3000);
      await planner(again).generate(request, username: 'anna', seed: 4);
      expect(again.calls.first, backend.calls.first);
      // Neu würfeln: andere Wegpunkte.
      final other = FakeBackend(hill: 3000);
      await planner(other).generate(request, username: 'anna', seed: 5);
      expect(other.calls.first, isNot(backend.calls.first));
    });

    test('Kein Weg am Wegpunkt: gedreht neu versucht', () async {
      final backend = FakeBackend(failFirst: 1);
      final routes = await planner(backend).generate(
        const RouteRequest(
          discipline: RouteDiscipline.gravel,
          shape: RouteShape.loop,
          start: berlin,
          distanceMeters: 30000,
        ),
        username: 'ben',
        variants: const [RouteVariant.balanced],
      );
      expect(routes.single.variant, RouteVariant.balanced);
      expect(backend.calls.length, greaterThanOrEqualTo(2));
    });

    test('Zum Ziel, das schon weiter liegt: direkte Strecke, keine Schleifen', () async {
      final destination = Geo.destination(berlin, 90, 9000);
      final backend = FakeBackend();
      final routes = await planner(backend).generate(
        RouteRequest(
          discipline: RouteDiscipline.roadBike,
          shape: RouteShape.toDestination,
          start: berlin,
          destination: destination,
          distanceMeters: 5000,
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(backend.calls.single, [berlin, destination]);
      expect(routes.single.points.last.longitude, closeTo(destination.longitude, 1e-6));
    });

    test('Zum Ziel mit Wunschdistanz: Umweg bis in die Toleranz', () async {
      final destination = Geo.destination(berlin, 90, 3000);
      final backend = FakeBackend(factor: 1.0);
      await planner(backend).generate(
        RouteRequest(
          discipline: RouteDiscipline.run,
          shape: RouteShape.toDestination,
          start: berlin,
          destination: destination,
          distanceMeters: 8000,
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(backend.calls.last.length, 3);
      expect(Geo.length(backend.calls.last), closeTo(8000, 8000 * RouteRequest.tolerance));
    });

    test('Dienst gestört: Fehler wird gemeldet', () async {
      expect(
        planner(FakeBackend(unavailable: true)).generate(
          const RouteRequest(
            discipline: RouteDiscipline.run,
            shape: RouteShape.loop,
            start: berlin,
            distanceMeters: 5000,
          ),
          username: 'anna',
        ),
        throwsA(isA<RoutingUnavailable>()),
      );
      expect(
        planner(FakeBackend()).generate(
          const RouteRequest(
            discipline: RouteDiscipline.run,
            shape: RouteShape.loop,
            start: berlin,
            distanceMeters: 50,
          ),
          username: 'anna',
        ),
        throwsArgumentError,
      );
    });

    test('Höhen werden über die Strecke interpoliert', () {
      final points = [for (var index = 0; index < 5; index++) Geo.destination(berlin, 90, index * 100.0)];
      final filled = ElevationFill.interpolate(points, [0, 4], [100, 140]);
      expect([for (final point in filled) point.elevation!.round()], [100, 110, 120, 130, 140]);
      expect(ElevationFill.interpolate(points, [0, 2, 4], [10, null, 30])[1].elevation, closeTo(15, 0.01));
    });
  });

  group('Gespeicherte Routen und Export', () {
    PlannedRoute route({String username = 'anna'}) => PlannedRoute(
      id: 'r1',
      username: username,
      name: 'Rundweg 5,0 km · Grün & <verkehrsarm>',
      request: const RouteRequest(
        discipline: RouteDiscipline.roadBike,
        shape: RouteShape.loop,
        start: berlin,
        distanceMeters: 5000,
      ),
      variant: RouteVariant.green,
      points: [
        for (var index = 0; index <= 10; index++)
          Geo.destination(berlin, 0, index * 250.0).withElevation(40 + index * 2.0),
      ],
      engine: ValhallaFormat.engineName,
      createdAt: DateTime.utc(2026, 11, 21, 8),
      plannedDay: CalendarDay(2026, 11, 22),
      slotID: 'slot-1',
      slotTitle: 'Lockere Ausfahrt',
    );

    test('JSON hin und zurück; fremde Routen werden nicht geladen', () {
      final original = route();
      final json = jsonDecode(jsonEncode(original.toJson()));
      final restored = PlannedRoute.fromJson(json, username: 'anna')!;
      expect(restored.toJson(), original.toJson());
      expect(restored.stats.ascentMeters, 20);
      expect(restored.plannedDay, CalendarDay(2026, 11, 22));
      expect(PlannedRoute.fromJson(json, username: 'ben'), isNull);
    });

    test('Ablage je Benutzer', () {
      final library = RouteLibrary(username: 'anna')..save(route());
      expect(() => library.save(route(username: 'ben')), throwsStateError);
      expect(library.plannedOn(CalendarDay(2026, 11, 22)).single.id, 'r1');
      final json = jsonDecode(jsonEncode(library.toJson()));
      expect(RouteLibrary.fromJson(json, username: 'anna')!.routes.single.id, 'r1');
      expect(RouteLibrary.fromJson(json, username: 'ben'), isNull);
      library.delete('r1');
      expect(library.routes, isEmpty);
    });

    test('GPX mit Höhe und maskiertem Namen', () {
      final xml = GpxExport.xml(route());
      expect(RegExp('<trkpt ').allMatches(xml).length, 11);
      expect(xml, contains('<ele>60.0</ele>'));
      expect(xml, contains('Grün &amp; &lt;verkehrsarm&gt;'));
      expect(xml, contains('<type>cycling</type>'));
      expect(GpxExport.fileName(route()), 'route-2026-11-21-rundweg-5-0-km-gruen-verkehrsarm.gpx');
    });

    test('FIT-Kurs lässt sich wieder lesen', () {
      final bytes = FitCourseFile.bytes(route(), created: DateTime.utc(2026, 11, 21, 8));
      final fit = FitDecoder.decode(bytes);
      expect(fit.records.length, 11);
      expect(fit.records.first.latitude, closeTo(berlin.latitude, 1e-6));
      expect(fit.records.first.longitude, closeTo(berlin.longitude, 1e-6));
      expect(fit.records.last.distance, closeTo(2500, 1));
      expect(fit.records.last.altitude, closeTo(60, 0.2));
      expect(fit.laps.single.distanceMeters, closeTo(2500, 1));
      // Westlich von Greenwich: negative Koordinaten (Zweierkomplement).
      expect(FitCourseFile.semicircles(-1), -11930465);
    });
  });

  group('Gebiete', () {
    List<GeoPoint> ring(double radius) => [
      for (var angle = 0; angle <= 360; angle += 5)
        Geo.destination(Geo.destination(berlin, 0, radius), angle + 180.0, radius),
    ];

    test('Kacheln: Schlüssel und Lage', () {
      final tile = ExplorationTile.at(berlin);
      expect(ExplorationTile.fromKey(tile.key), tile);
      expect(berlin.latitude, inInclusiveRange(tile.south, tile.north));
      expect(berlin.longitude, inInclusiveRange(tile.west, tile.east));
      // Zoom 17 in Berlin: etwa 186 m Kantenlänge.
      expect(math.sqrt(tile.areaSquareMeters), closeTo(186, 5));
    });

    test('Geschlossene Runde erobert die Fläche, hin und zurück nicht', () {
      final loop = ring(1000);
      expect(ExplorationRules.isClosed(loop), isTrue);
      expect(Geo.area(ExplorationRules.polygon(loop)!), closeTo(math.pi * 1e6, 0.05 * math.pi * 1e6));
      final out = [for (var index = 0; index <= 40; index++) Geo.destination(berlin, 0, index * 50.0)];
      expect(ExplorationRules.polygon([...out, ...out.reversed]), isNull);
      expect(ExplorationRules.polygon(out), isNull);
    });

    test('Stand je Benutzer: Kacheln, Gebiete, jede Quelle nur einmal', () {
      final state = ExplorationState(username: 'anna');
      final gain = state.add(
        ExplorationTrack(sourceID: 'a1', name: 'Runde', day: CalendarDay(2026, 11, 20), points: ring(1000)),
      );
      expect(gain.territory, isNotNull);
      expect(gain.newTiles, greaterThan(20));
      expect(gain.newCapturedTiles, greaterThan(60));
      expect(state.capturedSquareKilometers, closeTo(math.pi, 0.6));
      expect(state.largestCluster, state.tileCount);
      expect(
        state
            .add(ExplorationTrack(sourceID: 'a1', name: 'Runde', day: CalendarDay(2026, 11, 20), points: ring(1000)))
            .isEmpty,
        isTrue,
      );
      final second = state.add(
        ExplorationTrack(sourceID: 'a2', name: 'Runde', day: CalendarDay(2026, 11, 21), points: ring(1000)),
      );
      expect(second.newTiles, 0);
      expect(second.newCapturedTiles, 0);
      expect(state.visits.values.every((count) => count >= 2), isTrue);
      final json = jsonDecode(jsonEncode(state.toJson()));
      final restored = ExplorationState.fromJson(json, username: 'anna')!;
      expect(restored.tileCount, state.tileCount);
      expect(restored.captured, state.captured);
      expect(restored.territories.length, 2);
      expect(restored.processed, {'a1', 'a2'});
      expect(ExplorationState.fromJson(json, username: 'ben'), isNull);
    });
  });

  group('Wegarten, Pfeile, Zeichnen', () {
    test('Auswahl: Natur und Asphalt schließen sich aus, leer ist der Mix', () {
      var selection = <RoutePreference>{};
      expect(RoutePreference.describe(selection), 'Ausgewogener Mix');
      selection = RoutePreference.toggle(selection, RoutePreference.nature);
      selection = RoutePreference.toggle(selection, RoutePreference.water);
      expect(selection, {RoutePreference.nature, RoutePreference.water});
      selection = RoutePreference.toggle(selection, RoutePreference.paved);
      expect(selection, {RoutePreference.water, RoutePreference.paved});
      expect(RoutePreference.describe(selection), 'Am Wasser + Straße & Asphalt');
      selection = RoutePreference.toggle(selection, RoutePreference.water);
      expect(selection, {RoutePreference.paved});
      const request = RouteRequest(
        discipline: RouteDiscipline.run,
        shape: RouteShape.loop,
        start: berlin,
        distanceMeters: 8000,
        preferences: {RoutePreference.water, RoutePreference.nature},
      );
      final restored = RouteRequest.fromJson(jsonDecode(jsonEncode(request.toJson())))!;
      expect(restored.preferences, request.preferences);
      expect(RouteShape.generated, isNot(contains(RouteShape.drawn)));
    });

    test('Router-Gewichtung je Wegart', () {
      final nature = ValhallaFormat.costing(
        RouteDiscipline.run,
        RouteVariant.balanced,
        preferences: {RoutePreference.nature},
      ).options;
      expect(nature['use_tracks'], 1.0);
      expect(nature['sidewalk_factor'], greaterThan(1));
      final paved = ValhallaFormat.costing(
        RouteDiscipline.run,
        RouteVariant.green,
        preferences: {RoutePreference.paved},
      ).options;
      expect(paved['use_tracks'], 0.0);
      final gravelNature = ValhallaFormat.costing(
        RouteDiscipline.gravel,
        RouteVariant.balanced,
        preferences: {RoutePreference.nature},
      ).options;
      expect(gravelNature['bicycle_type'], 'Mountain');
      expect(gravelNature['use_roads'], 0.0);
      final roadPaved = ValhallaFormat.costing(
        RouteDiscipline.roadBike,
        RouteVariant.green,
        preferences: {RoutePreference.paved},
      ).options;
      expect(roadPaved['avoid_bad_surfaces'], 1.0);
      expect(
        BRouterFormat.profile(RouteDiscipline.gravel, RouteVariant.balanced, preferences: {RoutePreference.nature}),
        'mtb',
      );
      expect(BRouterFormat.profile(RouteDiscipline.gravel, RouteVariant.balanced), 'gravel');
      expect(
        BRouterFormat.profile(RouteDiscipline.roadBike, RouteVariant.balanced, preferences: {RoutePreference.water}),
        'trekking-noferries',
      );
    });

    test('Overpass: Abfrage für Wasser und Natur, Antwort mit Mittelpunkten', () {
      final query = OverpassFormat.query(berlin, 3000, {RoutePreference.water, RoutePreference.nature});
      expect(query, startsWith('[out:json]'));
      expect(query, contains('waterway'));
      expect(query, contains('(around.w:40)'));
      expect(query, contains('around:3000,52.52000,13.40500'));
      expect(query, contains('leisure'));
      // Knoten auf den Wegen statt Mittelpunkt des Rechtecks (der läge bei Flussbiegungen im Wasser).
      expect(query, contains('(.s0;.s1;.s2;)->.all;node(w.all);out skel qt 2000;'));
      expect(query, isNot(contains('out center')));
      expect(OverpassFormat.query(berlin, 50000, {RoutePreference.water}), contains('around:12000,'));
      expect(OverpassFormat.needed({RoutePreference.paved}, RouteDiscipline.run), isFalse);
      expect(OverpassFormat.needed({RoutePreference.paved}, RouteDiscipline.roadBike), isTrue);
      expect(OverpassFormat.needed(const {}, RouteDiscipline.gravel), isFalse);
      final points = OverpassFormat.parse({
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'center': {'lat': 52.5, 'lon': 13.4},
          },
          {'type': 'node', 'id': 2, 'lat': 52.6, 'lon': 13.5},
          {'type': 'way', 'id': 3},
        ],
      });
      expect(points, [const GeoPoint(52.5, 13.4), const GeoPoint(52.6, 13.5)]);
      // Dicht liegende Knoten werden ausgedünnt: höchstens einer je 80 m.
      final dense = [for (var index = 0; index < 100; index++) Geo.destination(berlin, 90, index * 10.0)];
      final spread = OverpassFormat.spread(dense);
      expect(spread.length, inInclusiveRange(12, 14));
      expect(OverpassFormat.spread(dense, max: 5).length, 5);
    });

    test('Nie übers Wasser: Routen mit Fähre werden verworfen', () {
      expect(
        () => ValhallaFormat.parseRoute({
          'trip': {
            'legs': [
              {
                'shape': Geo.encodePolyline([berlin, hamburg]),
              },
            ],
            'summary': {'length': 255, 'has_ferry': true},
          },
        }),
        throwsA(isA<NoRouteFound>()),
      );
      Map<String, Object?> brouter(String tags) => {
        'features': [
          {
            'properties': {
              'track-length': '1000',
              'messages': [
                ['Longitude', 'Latitude', 'Elevation', 'Distance', 'WayTags'],
                ['13405000', '52520000', '34', '500', tags],
              ],
            },
            'geometry': {
              'coordinates': [
                [13.405, 52.52, 34.0],
                [13.41, 52.53, 35.0],
              ],
            },
          },
        ],
      };
      expect(
        () => BRouterFormat.parse(jsonEncode(brouter('route=ferry highway=service'))),
        throwsA(isA<NoRouteFound>()),
      );
      expect(BRouterFormat.parse(jsonEncode(brouter('highway=path surface=gravel'))).distanceMeters, 1000);
    });

    test('Wegpunkte auf passende Wege ziehen und Anteil messen', () {
      final waypoints = [berlin, Geo.destination(berlin, 0, 1000), Geo.destination(berlin, 90, 1000), berlin];
      final near = Geo.destination(waypoints[1], 90, 200);
      final far = Geo.destination(waypoints[2], 180, 3000);
      final snapped = PreferenceSnapper.snap(waypoints, [near, far], maxShift: 400);
      expect(snapped[1], near);
      expect(snapped[2], waypoints[2]);
      expect(snapped.first, berlin);
      expect(snapped.last, berlin);
      final line = [for (var index = 0; index <= 10; index++) Geo.destination(berlin, 0, index * 100.0)];
      expect(PreferenceSnapper.coverage(line, [Geo.destination(berlin, 0, 250)]), closeTo(3 / 11, 0.01));
      expect(PreferenceSnapper.coverage(line, const []), 0);
    });

    test('Richtungspfeile in gleichen Abständen mit Fahrtrichtung', () {
      final line = [
        berlin,
        Geo.destination(berlin, 90, 1000),
        Geo.destination(Geo.destination(berlin, 90, 1000), 0, 1000),
      ];
      final arrows = RouteArrows.along(line, 500);
      expect(arrows.length, 4);
      expect(arrows.first.bearing, closeTo(90, 0.5));
      expect(arrows.last.bearing, closeTo(0, 0.5));
      expect(Geo.distance(berlin, arrows.first.point), closeTo(250, 1));
      expect(RouteArrows.along(line, 1, maxArrows: 10).length, 10);
      expect(RouteArrows.metersPerPixel(0, 0), closeTo(156543, 1));
    });

    test('Kürzen auf exakte Länge mit Höhe', () {
      final line = [
        berlin.withElevation(10),
        Geo.destination(berlin, 0, 1000).withElevation(20),
        Geo.destination(berlin, 0, 2000).withElevation(30),
      ];
      final trimmed = RouteTrim.truncate(line, 1500);
      expect(Geo.length(trimmed), closeTo(1500, 0.5));
      expect(trimmed.last.elevation, closeTo(25, 0.01));
      expect(RouteTrim.truncate(line, 5000).length, 3);
    });

    test('Gezeichneter Strich wird zu wenigen Wegpunkten', () {
      final stroke = [for (var index = 0; index <= 200; index++) Geo.destination(berlin, 45, index * 25.0)];
      final points = FreehandStroke.waypoints(stroke);
      expect(points.length, lessThanOrEqualTo(FreehandStroke.maxWaypoints));
      expect(points.first, stroke.first);
      expect(points.last, stroke.last);
      expect(FreehandStroke.waypoints([berlin, Geo.destination(berlin, 0, 50)]).length, 2);
    });

    test('Frei geplante Route: Abschnitte, Rückgängig, Rundweg schließen', () {
      final route = DrawnRoute();
      expect(route.isEmpty, isTrue);
      route.setStart(berlin);
      expect(route.points, [berlin]);
      final a = Geo.destination(berlin, 0, 1000);
      final b = Geo.destination(a, 90, 1000);
      route
        ..add([berlin, a])
        ..add([a, b]);
      expect(route.points, [berlin, a, b]);
      expect(route.stats.distanceMeters, closeTo(2000, 2));
      expect(route.canClose, isTrue);
      route.add([b, berlin]);
      expect(route.isClosed, isTrue);
      expect(route.canClose, isFalse);
      route.undo();
      expect(route.end, b);
      route
        ..undo()
        ..undo();
      expect(route.points, [berlin]);
      route.undo();
      expect(route.isEmpty, isTrue);
    });

    test('Sekantenverfahren zwischen zu kurz und zu lang', () {
      expect(RouteSizing.next(length: 8000, routed: 9000, target: 10000), closeTo(8888.9, 0.1));
      expect(
        RouteSizing.next(length: 8000, routed: 9000, target: 10000, below: (8000, 9000), above: (9000, 11000)),
        closeTo(8500, 0.1),
      );
    });
  });

  group('Planer mit Wegarten und exakter Distanz', () {
    test('Wegarten: Router bekommt die Auswahl, Wegpunkte liegen auf passenden Wegen', () async {
      // Ufer rund um den Start (alle 20° in 1–2 km Entfernung).
      final water = [
        for (var angle = 0; angle < 360; angle += 20)
          for (final distance in [1000.0, 2000.0]) Geo.destination(berlin, angle.toDouble(), distance),
      ];
      final features = FakeFeatures(water);
      final backend = FakeBackend(hill: 1000);
      final routes = await RoutePlanner(backend, features: features).generate(
        const RouteRequest(
          discipline: RouteDiscipline.run,
          shape: RouteShape.loop,
          start: berlin,
          distanceMeters: 8000,
          preferences: {RoutePreference.water},
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(features.requests, 1);
      expect(backend.preferences.first, {RoutePreference.water});
      expect(backend.calls.first.where(water.contains), isNotEmpty);
      expect(routes.single.preferenceShare, isNotNull);
      expect(routes.single.preferenceShare, greaterThan(0));
    });

    test('Ohne passende Auswahl keine Overpass-Abfrage; Abfragefehler stört nicht', () async {
      final features = FakeFeatures(const []);
      await RoutePlanner(FakeBackend(), features: features).generate(
        const RouteRequest(
          discipline: RouteDiscipline.run,
          shape: RouteShape.loop,
          start: berlin,
          distanceMeters: 5000,
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(features.requests, 0);
      final routes = await RoutePlanner(FakeBackend(), features: FakeFeatures(const [], fails: true)).generate(
        const RouteRequest(
          discipline: RouteDiscipline.gravel,
          shape: RouteShape.loop,
          start: berlin,
          distanceMeters: 20000,
          preferences: {RoutePreference.nature},
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(routes.single.preferenceShare, isNull);
    });

    test('Ungleichmäßiges Wegenetz: trotzdem auf ±2,5 % genau', () async {
      // Umwegfaktor wächst mit der Größe (1,2 bei kleinen, bis 1,6 bei großen Runden).
      final backend = CurvedBackend();
      final routes = await RoutePlanner(backend).generate(
        const RouteRequest(
          discipline: RouteDiscipline.run,
          shape: RouteShape.loop,
          start: berlin,
          distanceMeters: 12000,
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(backend.lastDistance, inInclusiveRange(12000 * 0.975, 12000 * 1.025));
      expect(routes, hasLength(1));
    });

    test('Offenes Ziel wird exakt auf die Wunschdistanz gekürzt', () async {
      final routes = await RoutePlanner(FakeBackend(factor: 1.0)).generate(
        const RouteRequest(
          discipline: RouteDiscipline.roadBike,
          shape: RouteShape.direction,
          start: berlin,
          distanceMeters: 30000,
          bearingDegrees: 90,
        ),
        username: 'anna',
        variants: const [RouteVariant.balanced],
      );
      expect(routes.single.stats.distanceMeters, closeTo(30000, 30000 * 0.005));
    });

    test('Frei gezeichnete Routen erzeugt der Planer nicht', () {
      expect(
        RoutePlanner(FakeBackend()).generate(
          const RouteRequest(
            discipline: RouteDiscipline.run,
            shape: RouteShape.drawn,
            start: berlin,
            distanceMeters: 0,
          ),
          username: 'anna',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Adresssuche', () {
    test('Photon: Anfrage mit Nähe, Antwort mit Straße, Ort und Land', () {
      final uri = GeocodingFormat.photonUri('Hauptstraße 5', near: berlin);
      expect(uri.host, 'photon.komoot.io');
      expect(uri.queryParameters, containsPair('q', 'Hauptstraße 5'));
      expect(uri.queryParameters, containsPair('lat', '52.5200'));
      expect(uri.queryParameters, containsPair('lang', 'de'));
      final places = GeocodingFormat.parsePhoton({
        'features': [
          {
            'geometry': {
              'coordinates': [13.35, 52.49],
            },
            'properties': {
              'street': 'Hauptstraße',
              'housenumber': '5',
              'postcode': '10827',
              'city': 'Berlin',
              'countrycode': 'DE',
              'country': 'Deutschland',
            },
          },
          {
            'geometry': {
              'coordinates': [9.99, 53.55],
            },
            'properties': {'name': 'Alster', 'city': 'Hamburg', 'countrycode': 'DE'},
          },
          {
            'geometry': {
              'coordinates': [16.37, 48.21],
            },
            'properties': {'name': 'Prater', 'city': 'Wien', 'countrycode': 'AT', 'country': 'Österreich'},
          },
          {
            'geometry': {
              'coordinates': [1, 2],
            },
            'properties': <String, Object?>{},
          },
        ],
      });
      expect(places.map((place) => place.label), [
        'Hauptstraße 5, 10827 Berlin',
        'Alster, Hamburg',
        'Prater, Wien, Österreich',
      ]);
      expect(places.first.point, const GeoPoint(52.49, 13.35));
      expect(() => GeocodingFormat.parsePhoton('kaputt'), throwsA(isA<RoutingUnavailable>()));
    });

    test('Nominatim: Anfrage und Antwort', () {
      final uri = GeocodingFormat.nominatimUri('Tempelhofer Feld');
      expect(uri.host, 'nominatim.openstreetmap.org');
      expect(uri.queryParameters['format'], 'jsonv2');
      final places = GeocodingFormat.parseNominatim([
        {
          'lat': '52.4731',
          'lon': '13.4013',
          'name': 'Tempelhofer Feld',
          'display_name': 'Tempelhofer Feld, Tempelhof, Tempelhof-Schöneberg, Berlin, 12101, Deutschland',
        },
        {'lat': 'x', 'lon': '1', 'display_name': 'kaputt'},
      ]);
      expect(places.single.label, 'Tempelhofer Feld, Tempelhof, Tempelhof-Schöneberg, Berlin');
      expect(places.single.point, const GeoPoint(52.4731, 13.4013));
    });

    test('Eingabe: Mindestlänge, Koordinaten, Entfernung', () {
      expect(GeocodingFormat.normalized('  ab '), isNull);
      expect(GeocodingFormat.normalized(' Haupt   straße '), 'Haupt straße');
      expect(GeocodingFormat.coordinates('52.52, 13.405'), const GeoPoint(52.52, 13.405));
      expect(GeocodingFormat.coordinates('52,52 13,405'), const GeoPoint(52.52, 13.405));
      expect(GeocodingFormat.coordinates('95, 13'), isNull);
      expect(GeocodingFormat.coordinates('Berlin'), isNull);
      final place = Place(title: 'Ziel', detail: '', point: Geo.destination(berlin, 0, 2400));
      expect(GeocodingFormat.distanceLabel(place, berlin), '2,4 km');
      expect(GeocodingFormat.distanceLabel(place, null), isNull);
      expect(place.label, 'Ziel');
    });
  });

  group('Favoriten und Spazieren', () {
    test('Favoriten je Benutzer: speichern, gleiche Stelle ersetzen, umbenennen, suchen', () {
      final favorites = FavoritePlaces(username: 'anna');
      final home = FavoritePlace(
        id: 'f1',
        name: 'Zuhause',
        point: berlin,
        createdAt: DateTime.utc(2026, 11, 22),
        address: 'Hauptstraße 5, 10827 Berlin',
      );
      favorites
        ..save(home)
        ..save(FavoritePlace(id: 'f2', name: 'Hundewiese', point: hamburg, createdAt: DateTime.utc(2026, 11, 22)));
      expect(favorites.places.map((place) => place.name), ['Hundewiese', 'Zuhause']);
      // Gleiche Stelle (10 m daneben): ersetzt statt doppelt.
      favorites.save(
        FavoritePlace(
          id: 'f3',
          name: 'Daheim',
          point: Geo.destination(berlin, 0, 10),
          createdAt: DateTime.utc(2026, 11, 22),
        ),
      );
      expect(favorites.places.length, 2);
      expect(favorites.near(berlin)!.name, 'Daheim');
      favorites.rename('f3', '  Zuhause  ');
      expect(favorites.near(berlin)!.name, 'Zuhause');
      expect(favorites.matching('hunde').single.id, 'f2');
      expect(favorites.matching('').length, 2);
      expect(home.place.label, 'Zuhause, Hauptstraße 5, 10827 Berlin');
      final json = jsonDecode(jsonEncode(favorites.toJson()));
      expect(FavoritePlaces.fromJson(json, username: 'anna')!.places.map((place) => place.id), ['f3', 'f2']);
      expect(FavoritePlaces.fromJson(json, username: 'ben'), isNull);
      favorites.delete('f2');
      expect(favorites.places.single.id, 'f3');
    });

    test('Spazieren: Fußwege-Profil, Gehtempo, eigene Grenzen und Export', () {
      expect(RouteDiscipline.walk.onFoot, isTrue);
      expect(RouteDiscipline.walk.isBike, isFalse);
      expect(RouteDiscipline.gravel.label, 'Gravel');
      expect(ValhallaFormat.costing(RouteDiscipline.walk, RouteVariant.balanced).costing, 'pedestrian');
      expect(ValhallaFormat.costing(RouteDiscipline.walk, RouteVariant.balanced).options['use_hills'], 0.2);
      expect(
        ValhallaFormat.costing(
          RouteDiscipline.walk,
          RouteVariant.balanced,
          preferences: {RoutePreference.nature},
        ).options['use_tracks'],
        1.0,
      );
      expect(BRouterFormat.profile(RouteDiscipline.walk, RouteVariant.green), 'hiking-mountain');
      // 4,5 km/h: 3 km in 40 min; 60 hm kosten 6 min.
      expect(
        RouteDuration.estimate(discipline: RouteDiscipline.walk, distanceMeters: 3000, ascentMeters: 60),
        const Duration(minutes: 46),
      );
      expect(RouteRequest.maxDistance(RouteDiscipline.walk), 30000);
      final route = PlannedRoute(
        id: 'w',
        username: 'anna',
        name: 'Gassi',
        request: const RouteRequest(
          discipline: RouteDiscipline.walk,
          shape: RouteShape.loop,
          start: berlin,
          distanceMeters: 3000,
        ),
        variant: RouteVariant.green,
        points: [berlin, Geo.destination(berlin, 0, 500), berlin],
        engine: 'Test',
        createdAt: DateTime.utc(2026, 11, 22),
      );
      expect(GpxExport.xml(route), contains('<type>walking</type>'));
      expect(FitDecoder.decode(FitCourseFile.bytes(route, created: DateTime.utc(2026, 11, 22))).records.length, 3);
    });
  });

  group('Archiv und Kilometermarken', () {
    PlannedRoute planned({RouteDiscipline discipline = RouteDiscipline.run, CalendarDay? day}) => PlannedRoute(
      id: 'p-${discipline.rawValue}',
      username: 'anna',
      name: 'Runde',
      request: RouteRequest(discipline: discipline, shape: RouteShape.loop, start: berlin, distanceMeters: 10000),
      variant: RouteVariant.balanced,
      points: [berlin, Geo.destination(berlin, 0, 5000), berlin],
      engine: 'Test',
      createdAt: DateTime.utc(2026, 11, 20),
      plannedDay: day ?? CalendarDay(2026, 11, 22),
    );

    GarminActivity activity(int id, String type, double? meters, {String day = '2026-11-22 07:30:00'}) =>
        GarminActivity(id)
          ..typeKey = type
          ..startLocal = day
          ..distanceMeters = meters;

    test('Aktivität am geplanten Tag mit passender Sportart und Distanz schließt die Route ab', () {
      final route = planned();
      final activities = [
        activity(1, 'cycling', 10000),
        activity(2, 'running', 3000),
        activity(3, 'running', 9600),
        activity(4, 'running', 10100, day: '2026-11-21 07:30:00'),
      ];
      expect(RouteCompletion.match(route, activities)!.id, 3);
      expect(RouteCompletion.match(route, activities, taken: {3}), isNull);
      expect(RouteCompletion.match(planned(discipline: RouteDiscipline.gravel), activities)!.id, 1);
      expect(RouteCompletion.match(planned(discipline: RouteDiscipline.walk), [activity(5, 'walking', null)])!.id, 5);
      expect(RouteCompletion.match(planned(day: CalendarDay(2026, 11, 23)), activities), isNull);
    });

    test('Archiv: abgeschlossen raus aus „heute“, eigene Liste, JSON', () {
      final library = RouteLibrary(username: 'anna');
      final route = planned();
      library.save(route);
      expect(library.plannedOn(CalendarDay(2026, 11, 22)).single.id, route.id);
      route
        ..completedAt = DateTime.utc(2026, 11, 22, 9)
        ..activityID = 3;
      library.save(route);
      expect(library.plannedOn(CalendarDay(2026, 11, 22)), isEmpty);
      expect(library.open, isEmpty);
      expect(library.archive.single.activityID, 3);
      final restored = RouteLibrary.fromJson(jsonDecode(jsonEncode(library.toJson())), username: 'anna')!;
      expect(restored.archive.single.completedAt, DateTime.utc(2026, 11, 22, 9));
      expect(restored.archive.single.isCompleted, isTrue);
    });

    test('Kilometermarken: jeder Kilometer, ohne Marke direkt am Ziel, Schritt je Zoom', () {
      final line = [berlin, Geo.destination(berlin, 0, 3050)];
      final marks = KilometerMarks.along(line);
      expect(marks.map((mark) => mark.kilometer), [1, 2]);
      expect(Geo.distance(berlin, marks.first.point), closeTo(1000, 1));
      expect(KilometerMarks.along([berlin, Geo.destination(berlin, 0, 3500)]).map((mark) => mark.kilometer), [1, 2, 3]);
      expect(KilometerMarks.along(line, stepKm: 2).map((mark) => mark.kilometer), [2]);
      expect(KilometerMarks.step(400), 1);
      expect(KilometerMarks.step(1500), 2);
      expect(KilometerMarks.step(7000), 10);
      expect(KilometerMarks.step(1e9), 50);
    });
  });

  test('Anzeige', () {
    expect(RouteFormat.distance(850), '850 m');
    expect(RouteFormat.distance(10249), '10,2 km');
    expect(RouteFormat.distance(124400), '124 km');
    expect(RouteFormat.duration(const Duration(minutes: 48)), '48 min');
    expect(RouteFormat.duration(const Duration(minutes: 65)), '1:05 h');
    expect(RouteFormat.elevation(179.6), '180 hm');
  });

  test('Einstellungen des Planers', () {
    expect(RoutePlannerSettings().explorationEnabled, isFalse);
    final settings = RoutePlannerSettings(
      explorationEnabled: true,
      discipline: RouteDiscipline.gravel,
      shape: RouteShape.direction,
      distanceKilometers: 42,
      elevationGain: 300,
    );
    final restored = RoutePlannerSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())))!;
    expect(restored.toJson(), settings.toJson());
  });
}

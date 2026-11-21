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
  int heightCalls = 0;

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
  }) async {
    calls.add(waypoints);
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
      expect(loop().withinTolerance(10650), isTrue);
      expect(loop().withinTolerance(10800), isFalse);
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
      List<GeoPoint> line(List<double> heights) => [
        for (final (index, height) in heights.indexed) Geo.destination(berlin, 90, index * 100.0).withElevation(height),
      ];
      final stats = RouteStats.of(line([100, 101, 102, 101, 110, 120, 118, 119, 100]));
      expect(stats.ascentMeters, 20);
      expect(stats.descentMeters, 20);
      expect(stats.minElevation, 100);
      expect(stats.maxElevation, 120);
      expect(stats.distanceMeters, closeTo(800, 1));
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
      expect(uri.queryParameters['profile'], 'trekking');
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
        expect(route.stats.distanceMeters * 1.4, inInclusiveRange(9300, 10700));
      }
      // Höchstens drei Router-Anfragen je Variante.
      expect(backend.calls.length, lessThanOrEqualTo(9));
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

// Uhr-Paket (Karte auf der Garmin): Wegenetz im Streifen, Abbiegungen, Binärformat.
import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const start = GeoPoint(51.5, 7.3);

/// Straßenraster 100 m, 21 × 21 Knoten um den Start (IDs = Zeile * 100 + Spalte), dazu ein Weg 5 km entfernt.
OsmWays grid() {
  final projection = LocalProjection(start);
  final nodes = <int, GeoPoint>{};
  for (var row = 0; row <= 20; row++) {
    for (var col = 0; col <= 20; col++) {
      nodes[row * 100 + col] = projection.unproject((col - 10) * 100, (row - 10) * 100);
    }
  }
  nodes[90001] = projection.unproject(5000, 5000);
  nodes[90002] = projection.unproject(5200, 5000);
  return OsmWays(
    nodes: nodes,
    ways: [
      for (var row = 0; row <= 20; row++) [for (var col = 0; col <= 20; col++) row * 100 + col],
      for (var col = 0; col <= 20; col++) [for (var row = 0; row <= 20; row++) row * 100 + col],
      [90001, 90002],
    ],
  );
}

/// Runde auf dem Raster: 500 m Ost, 500 m Nord, 500 m West, zurück nach Süd.
PlannedRoute loop() {
  final projection = LocalProjection(start);
  final corners = [(0, 0), (500, 0), (500, 500), (0, 500), (0, 0)];
  final points = <GeoPoint>[];
  for (var i = 1; i < corners.length; i++) {
    final (ax, ay) = corners[i - 1];
    final (bx, by) = corners[i];
    for (var step = 0; step < 10; step++) {
      points.add(projection.unproject(ax + (bx - ax) * step / 10, ay + (by - ay) * step / 10));
    }
  }
  points.add(start);
  return PlannedRoute(
    id: 'r1',
    username: 'anna',
    name: 'Runde am Kanal',
    request: const RouteRequest(
      discipline: RouteDiscipline.run,
      shape: RouteShape.loop,
      start: start,
      distanceMeters: 2000,
    ),
    variant: RouteVariant.balanced,
    points: points,
    engine: 'Test',
    createdAt: DateTime.utc(2026, 11, 27),
  );
}

void main() {
  test('Abfrage und Antwort von Overpass', () {
    // Kleine Runde: ein Rechteck um alle Linien plus Abstand (für Overpass viel leichter).
    final query = WatchNetworkFormat.query([loop().points], radius: 300);
    expect(query, startsWith('[out:json][timeout:40];way['));
    expect(query, contains('(51.49731,7.29567,51.50719,7.31154);'));
    expect(query, isNot(contains('around')));
    expect(query, contains('footway|path|track'));
    expect(query, endsWith('(._;>;);out skel qt;'));
    // Lange Strecke: Streifen um die Linie statt eines riesigen Rechtecks.
    final projection = LocalProjection(start);
    final long = [for (var km = 0; km <= 20; km++) projection.unproject(km * 1000.0, km * 1000.0)];
    final corridor = WatchNetworkFormat.query([long], radius: 300);
    expect(corridor, contains('(around:300,51.50000,7.30000,'));
    final osm = WatchNetworkFormat.parse({
      'elements': [
        {'type': 'node', 'id': 1, 'lat': 51.5, 'lon': 7.3},
        {'type': 'node', 'id': 2, 'lat': 51.501, 'lon': 7.3},
        {
          'type': 'way',
          'id': 10,
          'nodes': [1, 2],
        },
        {
          'type': 'way',
          'id': 11,
          'nodes': [1, 3],
        },
      ],
    });
    expect(osm.nodes.length, 2);
    expect(osm.ways, [
      [1, 2],
    ]);
    expect(() => WatchNetworkFormat.parse({'remark': 'timeout'}), throwsA(isA<RoutingUnavailable>()));
  });

  test('Wegenetz nur im Streifen; Abbiegungen an den Ecken; Knoten auf der Route', () {
    final package = WatchPackage.build(route: loop(), osm: grid(), corridorMeters: 150);
    // Raster im Streifen: x und y zwischen -100 und 600 m (Zwischenpunkte vereinfacht), kein Weg 5 km entfernt.
    expect(package.nodes, isNotEmpty);
    for (final (x, y) in package.nodes) {
      expect(x, inInclusiveRange(-300, 800));
      expect(y, inInclusiveRange(-300, 800));
    }
    expect(package.edges.length, greaterThan(package.nodes.length));
    final main = package.main;
    expect(main.kind, WatchRouteKind.main);
    expect(main.distanceMeters, closeTo(2000, 5));
    // Ost → Nord: links; Nord → West: links; West → Süd: links.
    expect([for (final maneuver in main.maneuvers) maneuver.turn], [WatchTurn.left, WatchTurn.left, WatchTurn.left]);
    expect(main.attach.length, greaterThanOrEqualTo(16));
    // Jeder zugeordnete Knoten liegt auf seinem Abschnitt (Raster: genau auf der Linie).
    for (final (node, segment) in main.attach) {
      final (nx, ny) = package.nodes[node];
      final (ax, ay) = main.points[segment];
      final (bx, by) = main.points[segment + 1];
      expect(nx, inInclusiveRange(ax < bx ? ax : bx, ax < bx ? bx : ax));
      expect(ny, inInclusiveRange(ay < by ? ay : by, ay < by ? by : ay));
    }
    expect(main.maneuvers.map((maneuver) => main.points[maneuver.pointIndex]), [(500, 0), (500, 500), (0, 500)]);
  });

  test('Binärformat: kodieren, in Teile zerlegen, dekodieren', () {
    final shorter = loop();
    final package = WatchPackage.build(
      route: loop(),
      variants: [(WatchRouteKind.shorter, '−2 km', shorter)],
      osm: grid(),
      corridorMeters: 150,
    );
    final bytes = package.encode();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'AIW1');
    final decoded = WatchPackage.decode(bytes);
    expect(decoded.nodes, package.nodes);
    expect(decoded.edges, package.edges);
    expect(decoded.routes.length, 2);
    expect(decoded.routes[1].kind, WatchRouteKind.shorter);
    expect(decoded.routes[1].name, '−2 km');
    expect(decoded.main.name, 'Runde am Kanal');
    expect(decoded.main.points, package.main.points);
    expect(
      [for (final m in decoded.main.maneuvers) (m.pointIndex, m.turn)],
      [for (final m in package.main.maneuvers) (m.pointIndex, m.turn)],
    );
    expect(decoded.main.attach, package.main.attach);
    expect(decoded.origin.latitude, closeTo(start.latitude, 1e-6));

    final chunks = WatchPackage.chunks(bytes, size: 500);
    expect(chunks.length, (bytes.length / 500).ceil());
    final joined = Uint8List.fromList([for (final chunk in chunks) ...base64.decode(chunk)]);
    expect(joined, bytes);
    expect(() => WatchPackage.decode(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('Abbiegungen: Richtungsänderung in Grad', () {
    expect(WatchTurn.of(10), isNull);
    expect(WatchTurn.of(40), WatchTurn.slightRight);
    expect(WatchTurn.of(-90), WatchTurn.left);
    expect(WatchTurn.of(140), WatchTurn.sharpRight);
    expect(WatchTurn.of(175), WatchTurn.uTurn);
    expect(WatchTurn.fromCode(6), WatchTurn.left);
  });

  test('Zu weit vom Start: Hinweis statt kaputtem Paket', () {
    final far = loop();
    final projection = LocalProjection(start);
    final long = PlannedRoute(
      id: 'far',
      username: 'anna',
      name: 'Weit',
      request: far.request,
      variant: far.variant,
      points: [start, projection.unproject(40000, 0)],
      engine: 'Test',
      createdAt: far.createdAt,
    );
    expect(
      () => WatchPackage.build(
        route: long,
        osm: const OsmWays(nodes: {}, ways: []),
      ),
      throwsA(isA<WatchPackageTooLarge>()),
    );
  });
  test('Ohne Wegenetz: Route mit Abbiegungen aus ihrer Form', () {
    final package = WatchPackage.build(
      route: loop(),
      osm: const OsmWays(nodes: {}, ways: []),
    );
    expect(package.nodes, isEmpty);
    expect(package.edges, isEmpty);
    final turns = package.main.maneuvers.map((maneuver) => maneuver.turn).toList();
    // Runde gegen den Uhrzeigersinn: an den drei Ecken jeweils links.
    expect(turns, [WatchTurn.left, WatchTurn.left, WatchTurn.left]);
    final decoded = WatchPackage.decode(package.encode());
    expect(decoded.main.maneuvers.length, 3);
  });
}

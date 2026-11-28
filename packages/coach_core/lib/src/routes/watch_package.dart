import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';
import 'planned_route.dart';
import 'routing_formats.dart';

/// Wege aus OpenStreetMap: Knoten (ID → Punkt) und Wege als Folge von Knoten-IDs.
final class OsmWays {
  const OsmWays({required this.nodes, required this.ways});

  final Map<int, GeoPoint> nodes;
  final List<List<int>> ways;

  bool get isEmpty => ways.isEmpty;
}

/// Wegenetz rund um Linien (in der App: Overpass mit Spiegeln); wirft [RoutingUnavailable].
abstract interface class WatchNetworkSource {
  Future<OsmWays> network(List<List<GeoPoint>> lines, {double radius});
}

/// Overpass-Abfrage für das Wegenetz rund um Route und Varianten (für die Karte auf der Uhr).
abstract final class WatchNetworkFormat {
  /// Halbe Breite des Streifens um Route und Varianten.
  static const corridorMeters = 400.0;

  /// Begehbare Wege und Straßen (ohne Autobahnen und Schnellstraßen).
  static const highways =
      'footway|path|track|pedestrian|cycleway|bridleway|steps|living_street|residential|service|unclassified|'
      'tertiary|secondary|primary|road';

  /// Höchstzahl der Punkte, mit denen die Linien in der Abfrage stehen (sonst wird sie zu lang).
  static const maxQueryPoints = 160;

  /// Fläche (km²), bis zu der ein Rechteck abgefragt wird statt Streifen um jede Linie. Ein Rechteck ist für Overpass
  /// viel leichter; beim Packen wird ohnehin auf den Streifen um die Linien zugeschnitten.
  static const maxBoxSquareKilometers = 16.0;

  /// Overpass-QL: Wege im Abstand [radius] um die Linien, mit allen Knoten (IDs und Koordinaten). Kleine Gebiete
  /// (Runde mit Varianten) als ein Rechteck, große als Streifen um die Linien.
  static String query(List<List<GeoPoint>> lines, {double radius = corridorMeters}) {
    const filter = '["access"!~"^(private|no)\$"]["foot"!~"^(no|private)\$"]';
    final box = _box(lines, radius);
    if (box != null) {
      final (south, west, north, east) = box;
      return '[out:json][timeout:40];way["highway"~"^($highways)\$"]$filter'
          '(${[south, west, north, east].map((value) => value.toStringAsFixed(5)).join(',')});'
          '(._;>;);out skel qt;';
    }
    final perLine = math.max(8, maxQueryPoints ~/ math.max(1, lines.length));
    final parts = [
      for (final line in lines)
        if (line.length >= 2)
          'way["highway"~"^($highways)\$"]$filter'
              '(around:${radius.round()},${[for (final point in Geo.thin(line, perLine)) '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}'].join(',')});',
    ];
    return '[out:json][timeout:40];(${parts.join()});(._;>;);out skel qt;';
  }

  /// Rechteck (Süd, West, Nord, Ost) um alle Linien plus [radius], wenn es klein genug ist; sonst null.
  static (double, double, double, double)? _box(List<List<GeoPoint>> lines, double radius) {
    final points = [for (final line in lines) ...line];
    if (points.isEmpty) return null;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final point in points) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    final dLat = radius / 111320;
    final dLon = radius / (111320 * math.cos((south + north) / 2 * math.pi / 180));
    south -= dLat;
    north += dLat;
    west -= dLon;
    east += dLon;
    final height = (north - south) * 111.32;
    final width = (east - west) * 111.32 * math.cos((south + north) / 2 * math.pi / 180);
    return width * height <= maxBoxSquareKilometers ? (south, west, north, east) : null;
  }

  /// Antwort (`out skel`): Knoten mit `lat`/`lon`, Wege mit `nodes`. Wirft [RoutingUnavailable] ohne `elements`.
  static OsmWays parse(Object? json) {
    if (json case {'elements': final List<Object?> elements}) {
      final nodes = <int, GeoPoint>{};
      final ways = <List<int>>[];
      for (final element in elements) {
        switch (element) {
          case {'type': 'node', 'id': final num id, 'lat': final num lat, 'lon': final num lon}:
            nodes[id.toInt()] = GeoPoint(lat.toDouble(), lon.toDouble());
          case {'type': 'way', 'nodes': final List<Object?> ids}:
            final list = [
              for (final id in ids)
                if (id is num) id.toInt(),
            ];
            if (list.length >= 2) ways.add(list);
        }
      }
      return OsmWays(
        nodes: nodes,
        ways: [
          for (final way in ways)
            if (way.every(nodes.containsKey)) way,
        ],
      );
    }
    throw const RoutingUnavailable('Unerwartete Antwort für das Wegenetz.');
  }
}

/// Ebene Meter um einen Ursprung (für die kleine Fläche eines Laufs genau genug).
final class LocalProjection {
  LocalProjection(this.origin) : _cos = math.cos(origin.latitude * math.pi / 180);

  final GeoPoint origin;
  final double _cos;

  static const _metersPerDegree = 111320.0;

  (double, double) project(GeoPoint point) => (
    (point.longitude - origin.longitude) * _metersPerDegree * _cos,
    (point.latitude - origin.latitude) * _metersPerDegree,
  );

  GeoPoint unproject(num x, num y) =>
      GeoPoint(origin.latitude + y / _metersPerDegree, origin.longitude + x / (_metersPerDegree * _cos));
}

/// Abbiegung an einer Kreuzung.
enum WatchTurn {
  slightRight(1, 'leicht rechts'),
  right(2, 'rechts'),
  sharpRight(3, 'scharf rechts'),
  uTurn(4, 'wenden'),
  sharpLeft(5, 'scharf links'),
  left(6, 'links'),
  slightLeft(7, 'leicht links');

  const WatchTurn(this.code, this.label);

  final int code;
  final String label;

  static WatchTurn? fromCode(int code) => values.where((turn) => turn.code == code).firstOrNull;

  /// Richtungsänderung in Grad (positiv = rechts); unter 30° keine Abbiegung.
  static WatchTurn? of(double delta) {
    final abs = delta.abs();
    if (abs < 30) return null;
    if (abs >= 160) return uTurn;
    final right = delta > 0;
    if (abs < 55) return right ? slightRight : slightLeft;
    if (abs < 120) return right ? WatchTurn.right : left;
    return right ? sharpRight : sharpLeft;
  }
}

/// Art einer Strecke im Paket.
enum WatchRouteKind {
  main(0),
  shorter(1),
  longer(2);

  const WatchRouteKind(this.code);

  final int code;

  static WatchRouteKind fromCode(int code) => values.where((kind) => kind.code == code).firstOrNull ?? main;
}

final class WatchManeuver {
  const WatchManeuver({required this.pointIndex, required this.turn});

  /// Index des Routenpunkts, an dem abgebogen wird.
  final int pointIndex;
  final WatchTurn turn;
}

/// Eine Strecke im Paket (Hauptroute oder Variante), in Metern um den Ursprung.
final class WatchRoute {
  const WatchRoute({
    required this.kind,
    required this.name,
    required this.distanceMeters,
    required this.points,
    required this.maneuvers,
    required this.attach,
  });

  final WatchRouteKind kind;
  final String name;
  final int distanceMeters;
  final List<(int, int)> points;
  final List<WatchManeuver> maneuvers;

  /// Knoten des Wegenetzes auf der Strecke: (Knoten, Abschnitt) – der Knoten liegt höchstens 15 m neben dem Abschnitt
  /// von Punkt `Abschnitt` zu `Abschnitt + 1`. Für den Rückweg zur Route.
  final List<(int, int)> attach;
}

/// Paket zu groß für die Uhr.
final class WatchPackageTooLarge implements Exception {
  const WatchPackageTooLarge(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Route mit Varianten und Wegenetz für die Karte auf der Uhr (Connect-IQ-Datenfeld `garmin/`). Alles in ganzen
/// Metern um den Start; Binärformat `AIW1` (Little Endian), beschrieben in `garmin/FORMAT.md`.
final class WatchPackage {
  const WatchPackage({required this.origin, required this.nodes, required this.edges, required this.routes});

  static const magic = 'AIW1';
  static const version = 1;

  /// Grenzen der Uhr (Speicher des Datenfelds 256 KB; Koordinaten als 16 Bit).
  static const maxNodes = 6000;
  static const maxEdges = 7000;
  static const maxRoutePoints = 1500;
  static const maxCoordinate = 32000;

  /// Größe eines Teils beim Laden auf die Uhr (Bytes vor Base64).
  static const chunkBytes = 6000;

  final GeoPoint origin;
  final List<(int, int)> nodes;
  final List<(int, int)> edges;
  final List<WatchRoute> routes;

  WatchRoute get main => routes.first;

  /// Baut das Paket aus Hauptroute, Varianten und Wegenetz (`osm` z. B. aus [WatchNetworkFormat.parse]).
  /// Wirft [WatchPackageTooLarge], wenn es nicht auf die Uhr passt.
  static WatchPackage build({
    required PlannedRoute route,
    List<(WatchRouteKind, String, PlannedRoute)> variants = const [],
    required OsmWays osm,
    double corridorMeters = WatchNetworkFormat.corridorMeters,
  }) {
    final projection = LocalProjection(route.points.first);
    final lines = [route.points, for (final (_, _, variant) in variants) variant.points];
    final graph = _Graph.build(osm, projection, lines: lines, corridor: corridorMeters);
    if (graph.nodes.length > maxNodes || graph.edges.length > maxEdges) {
      throw const WatchPackageTooLarge('Das Wegenetz ist für die Uhr zu groß – plane eine kürzere Route.');
    }
    final degree = List.filled(graph.nodes.length, 0);
    for (final (a, b) in graph.edges) {
      degree[a]++;
      degree[b]++;
    }
    WatchRoute watchRoute(WatchRouteKind kind, String name, PlannedRoute planned) {
      var points = [for (final point in planned.points) _round(projection.project(point))];
      points = _simplify(points, 3);
      if (points.length > maxRoutePoints) points = _thinInts(points, maxRoutePoints);
      _checkRange(points);
      final attach = _attach(points, graph.nodes);
      return WatchRoute(
        kind: kind,
        name: name.length > 40 ? name.substring(0, 40) : name,
        distanceMeters: planned.stats.distanceMeters.round(),
        points: points,
        maneuvers: _maneuvers(points, attach, degree, graph.nodes),
        attach: attach,
      );
    }

    return WatchPackage(
      origin: route.points.first,
      nodes: graph.nodes,
      edges: graph.edges,
      routes: [
        watchRoute(WatchRouteKind.main, route.name, route),
        for (final (kind, name, variant) in variants) watchRoute(kind, name, variant),
      ],
    );
  }

  static (int, int) _round((double, double) point) => (point.$1.round(), point.$2.round());

  static void _checkRange(List<(int, int)> points) {
    for (final (x, y) in points) {
      if (x.abs() > maxCoordinate || y.abs() > maxCoordinate) {
        throw const WatchPackageTooLarge('Die Route reicht zu weit vom Start weg für die Uhr (höchstens 32 km).');
      }
    }
  }

  /// Knoten bis 15 m neben der Strecke, je mit dem nächsten Abschnitt; nach Abschnitt sortiert.
  static List<(int, int)> _attach(List<(int, int)> points, List<(int, int)> nodes) {
    if (points.length < 2) return const [];
    final grid = _SegmentGrid(points, cell: 60);
    final result = <(int, int)>[];
    for (final (index, node) in nodes.indexed) {
      final (_, segment) = grid.nearest(node, maxDistance: 15);
      if (segment >= 0) result.add((index, segment));
    }
    result.sort((x, y) => x.$2.compareTo(y.$2));
    return result;
  }

  /// Abbiegungen an Kreuzungen (Knoten mit mindestens drei Wegen) auf der Strecke.
  static List<WatchManeuver> _maneuvers(
    List<(int, int)> points,
    List<(int, int)> attach,
    List<int> degree,
    List<(int, int)> nodes,
  ) {
    if (points.length < 3) return const [];
    final cumulative = <double>[0];
    for (var index = 1; index < points.length; index++) {
      cumulative.add(cumulative.last + math.sqrt(_dist2(points[index - 1], points[index])));
    }
    int back(int index, double meters) {
      var i = index;
      while (i > 0 && cumulative[index] - cumulative[i] < meters) {
        i--;
      }
      return i;
    }

    int ahead(int index, double meters) {
      var i = index;
      while (i < points.length - 1 && cumulative[i] - cumulative[index] < meters) {
        i++;
      }
      return i;
    }

    // Ohne Wegenetz (Overpass nicht erreichbar): Abbiegungen aus der Form der Route.
    if (nodes.isEmpty) return _shapeManeuvers(points, cumulative, back, ahead);
    final result = <WatchManeuver>[];
    for (final (node, segment) in attach) {
      if (degree[node] < 3) continue;
      // Abbiegen nur an einem Routenpunkt (nach dem Vereinfachen bleiben dort die Knicke).
      final position = nodes[node];
      final pointIndex = [
        segment,
        segment + 1,
      ].where((i) => i > 0 && i < points.length - 1 && _dist2(points[i], position) <= 15 * 15).firstOrNull;
      if (pointIndex == null) continue;
      if (result.any((maneuver) => maneuver.pointIndex == pointIndex)) continue;
      final from = points[back(pointIndex, 20)];
      final at = points[pointIndex];
      final to = points[ahead(pointIndex, 20)];
      if (from == at || to == at) continue;
      final inBearing = _bearing(from, at);
      final outBearing = _bearing(at, to);
      final delta = ((outBearing - inBearing + 540) % 360) - 180;
      final turn = WatchTurn.of(delta);
      if (turn == null) continue;
      // Zwei Kreuzungen dicht beieinander: nur eine Abbiegung.
      if (result.isNotEmpty && cumulative[pointIndex] - cumulative[result.last.pointIndex] < 25) continue;
      result.add(WatchManeuver(pointIndex: pointIndex, turn: turn));
    }
    return result;
  }

  /// Abbiegungen nur aus der Linie: deutliche Knicke (ab 55°, „leicht“ wäre bei kurvigen Wegen zu häufig); liegen
  /// zwei innerhalb von 25 m, zählt der stärkere.
  static List<WatchManeuver> _shapeManeuvers(
    List<(int, int)> points,
    List<double> cumulative,
    int Function(int, double) back,
    int Function(int, double) ahead,
  ) {
    final result = <(WatchManeuver, double)>[];
    for (var index = 1; index < points.length - 1; index++) {
      final from = points[back(index, 20)];
      final at = points[index];
      final to = points[ahead(index, 20)];
      if (from == at || to == at) continue;
      final delta = ((_bearing(at, to) - _bearing(from, at) + 540) % 360) - 180;
      if (delta.abs() < 55) continue;
      final turn = WatchTurn.of(delta)!;
      if (result.isNotEmpty && cumulative[index] - cumulative[result.last.$1.pointIndex] < 25) {
        if (delta.abs() > result.last.$2.abs()) {
          result[result.length - 1] = (WatchManeuver(pointIndex: index, turn: turn), delta);
        }
        continue;
      }
      result.add((WatchManeuver(pointIndex: index, turn: turn), delta));
    }
    return [for (final (maneuver, _) in result) maneuver];
  }

  static double _bearing((int, int) a, (int, int) b) =>
      (math.atan2((b.$1 - a.$1).toDouble(), (b.$2 - a.$2).toDouble()) * 180 / math.pi + 360) % 360;

  static int _dist2((int, int) a, (int, int) b) {
    final dx = a.$1 - b.$1;
    final dy = a.$2 - b.$2;
    return dx * dx + dy * dy;
  }

  /// Douglas-Peucker in ganzen Metern.
  static List<(int, int)> _simplify(List<(int, int)> points, double tolerance) {
    if (points.length < 3) return points;
    final keep = List.filled(points.length, false)
      ..[0] = true
      ..[points.length - 1] = true;
    final stack = [(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      var maxDistance = 0.0;
      var index = -1;
      for (var i = first + 1; i < last; i++) {
        final distance = _segmentDistance(points[i], points[first], points[last]);
        if (distance > maxDistance) {
          maxDistance = distance;
          index = i;
        }
      }
      if (index >= 0 && maxDistance > tolerance) {
        keep[index] = true;
        stack
          ..add((first, index))
          ..add((index, last));
      }
    }
    final result = <(int, int)>[];
    for (final (i, point) in points.indexed) {
      if (keep[i] && (result.isEmpty || result.last != point)) result.add(point);
    }
    return result;
  }

  static List<(int, int)> _thinInts(List<(int, int)> points, int max) {
    final step = (points.length - 1) / (max - 1);
    return [for (var i = 0; i < max; i++) points[(i * step).round()]];
  }

  static double _segmentDistance((int, int) p, (int, int) a, (int, int) b) {
    final dx = (b.$1 - a.$1).toDouble();
    final dy = (b.$2 - a.$2).toDouble();
    final length2 = dx * dx + dy * dy;
    if (length2 == 0) return math.sqrt(_dist2(p, a).toDouble());
    final t = (((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / length2).clamp(0.0, 1.0);
    final x = a.$1 + t * dx - p.$1;
    final y = a.$2 + t * dy - p.$2;
    return math.sqrt(x * x + y * y);
  }

  // Binärformat

  /// Kodiert nach `garmin/FORMAT.md`.
  Uint8List encode() {
    final out = BytesBuilder();
    final header = ByteData(20);
    for (var i = 0; i < 4; i++) {
      header.setUint8(i, magic.codeUnitAt(i));
    }
    header
      ..setUint8(4, version)
      ..setUint8(5, routes.length)
      ..setUint16(6, nodes.length, Endian.little)
      ..setUint16(8, edges.length, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setInt32(12, (origin.latitude * 1e6).round(), Endian.little)
      ..setInt32(16, (origin.longitude * 1e6).round(), Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(_pairs(nodes, signed: true));
    out.add(_pairs(edges, signed: false));
    for (final route in routes) {
      final name = utf8.encode(route.name);
      final head = ByteData(7 + name.length)
        ..setUint8(0, route.kind.code)
        ..setUint32(1, route.distanceMeters, Endian.little)
        ..setUint16(5, name.length, Endian.little);
      head.buffer.asUint8List().setRange(7, 7 + name.length, name);
      out.add(head.buffer.asUint8List());
      out.add(_count(route.points.length));
      out.add(_pairs(route.points, signed: true));
      out.add(_count(route.maneuvers.length));
      final maneuvers = ByteData(route.maneuvers.length * 3);
      for (final (i, maneuver) in route.maneuvers.indexed) {
        maneuvers
          ..setUint16(i * 3, maneuver.pointIndex, Endian.little)
          ..setUint8(i * 3 + 2, maneuver.turn.code);
      }
      out.add(maneuvers.buffer.asUint8List());
      out.add(_count(route.attach.length));
      out.add(_pairs(route.attach, signed: false));
    }
    return out.takeBytes();
  }

  static Uint8List _count(int value) => (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();

  static Uint8List _pairs(List<(int, int)> pairs, {required bool signed}) {
    final data = ByteData(pairs.length * 4);
    for (final (i, (a, b)) in pairs.indexed) {
      if (signed) {
        data
          ..setInt16(i * 4, a, Endian.little)
          ..setInt16(i * 4 + 2, b, Endian.little);
      } else {
        data
          ..setUint16(i * 4, a, Endian.little)
          ..setUint16(i * 4 + 2, b, Endian.little);
      }
    }
    return data.buffer.asUint8List();
  }

  /// Liest ein kodiertes Paket (Gegenstück zu [encode]); wirft [FormatException].
  static WatchPackage decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 20 || String.fromCharCodes(bytes.sublist(0, 4)) != magic) {
      throw const FormatException('Kein Uhr-Paket');
    }
    if (data.getUint8(4) != version) throw const FormatException('Unbekannte Version');
    final routeCount = data.getUint8(5);
    final nodeCount = data.getUint16(6, Endian.little);
    final edgeCount = data.getUint16(8, Endian.little);
    final origin = GeoPoint(data.getInt32(12, Endian.little) / 1e6, data.getInt32(16, Endian.little) / 1e6);
    var offset = 20;
    List<(int, int)> pairs(int count, {required bool signed}) {
      final result = [
        for (var i = 0; i < count; i++)
          signed
              ? (data.getInt16(offset + i * 4, Endian.little), data.getInt16(offset + i * 4 + 2, Endian.little))
              : (data.getUint16(offset + i * 4, Endian.little), data.getUint16(offset + i * 4 + 2, Endian.little)),
      ];
      offset += count * 4;
      return result;
    }

    int count() {
      final value = data.getUint16(offset, Endian.little);
      offset += 2;
      return value;
    }

    final nodes = pairs(nodeCount, signed: true);
    final edges = pairs(edgeCount, signed: false);
    final routes = <WatchRoute>[];
    for (var r = 0; r < routeCount; r++) {
      final kind = WatchRouteKind.fromCode(data.getUint8(offset));
      final distance = data.getUint32(offset + 1, Endian.little);
      final nameLength = data.getUint16(offset + 5, Endian.little);
      final name = utf8.decode(bytes.sublist(offset + 7, offset + 7 + nameLength));
      offset += 7 + nameLength;
      final points = pairs(count(), signed: true);
      final maneuverCount = count();
      final maneuvers = [
        for (var i = 0; i < maneuverCount; i++)
          WatchManeuver(
            pointIndex: data.getUint16(offset + i * 3, Endian.little),
            turn: WatchTurn.fromCode(data.getUint8(offset + i * 3 + 2)) ?? WatchTurn.right,
          ),
      ];
      offset += maneuverCount * 3;
      final attach = pairs(count(), signed: false);
      routes.add(
        WatchRoute(
          kind: kind,
          name: name,
          distanceMeters: distance,
          points: points,
          maneuvers: maneuvers,
          attach: attach,
        ),
      );
    }
    if (offset != bytes.length) throw const FormatException('Länge stimmt nicht');
    return WatchPackage(origin: origin, nodes: nodes, edges: edges, routes: routes);
  }

  /// Base64-Teile zum Laden auf die Uhr (je höchstens [chunkBytes] Bytes).
  static List<String> chunks(Uint8List bytes, {int size = chunkBytes}) => [
    for (var start = 0; start < bytes.length; start += size)
      base64.encode(bytes.sublist(start, math.min(bytes.length, start + size))),
  ];
}

/// Wegenetz als Graph: Kreuzungen und Endpunkte bleiben, Zwischenpunkte vereinfacht (5 m), nur im Streifen um die
/// Linien.
final class _Graph {
  _Graph(this.nodes, this.edges);

  final List<(int, int)> nodes;
  final List<(int, int)> edges;

  static _Graph build(
    OsmWays osm,
    LocalProjection projection, {
    required List<List<GeoPoint>> lines,
    required double corridor,
  }) {
    final usage = <int, int>{};
    for (final way in osm.ways) {
      for (final (i, id) in way.indexed) {
        // Endpunkte zählen doppelt (bleiben immer erhalten).
        usage[id] = (usage[id] ?? 0) + (i == 0 || i == way.length - 1 ? 2 : 1);
      }
    }
    final projected = <int, (int, int)>{
      for (final MapEntry(:key, :value) in osm.nodes.entries) key: WatchPackage._round(projection.project(value)),
    };
    final lineGrid = [
      for (final line in lines)
        _SegmentGrid([
          for (final point in Geo.thin(line, 1500)) WatchPackage._round(projection.project(point)),
        ], cell: 250),
    ];
    bool inCorridor((int, int) point) => lineGrid.any((grid) => grid.nearest(point, maxDistance: corridor).$2 >= 0);

    final index = <int, int>{};
    final nodes = <(int, int)>[];
    final edges = <(int, int)>{};
    int nodeIndex(int id) => index.putIfAbsent(id, () {
      nodes.add(projected[id]!);
      return nodes.length - 1;
    });
    for (final way in osm.ways) {
      // In Abschnitte zwischen Kreuzungen teilen, je Abschnitt vereinfachen.
      var start = 0;
      for (var i = 1; i < way.length; i++) {
        if (i < way.length - 1 && (usage[way[i]] ?? 0) < 2) continue;
        final section = [for (var j = start; j <= i; j++) projected[way[j]]!];
        final ids = [for (var j = start; j <= i; j++) way[j]];
        final kept = WatchPackage._simplify(section, 5);
        // Abschnitt nur, wenn er den Streifen berührt.
        if (section.any(inCorridor)) {
          var previous = ids.first;
          var cursor = 1;
          for (final point in kept.skip(1)) {
            while (cursor < section.length && section[cursor] != point) {
              cursor++;
            }
            if (cursor >= section.length) break;
            final id = ids[cursor];
            final a = nodeIndex(previous);
            final b = nodeIndex(id);
            if (a != b) edges.add(a < b ? (a, b) : (b, a));
            previous = id;
          }
        }
        start = i;
      }
    }
    return _Graph(nodes, edges.toList());
  }
}

/// Raster der Abschnitte einer Linie für schnelle Abstandsabfragen.
final class _SegmentGrid {
  _SegmentGrid(this.points, {required this.cell}) {
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final minX = (math.min(a.$1, b.$1) / cell).floor();
      final maxX = (math.max(a.$1, b.$1) / cell).floor();
      final minY = (math.min(a.$2, b.$2) / cell).floor();
      final maxY = (math.max(a.$2, b.$2) / cell).floor();
      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          (_cells[(x, y)] ??= []).add(i);
        }
      }
    }
  }

  final List<(int, int)> points;
  final int cell;
  final Map<(int, int), List<int>> _cells = {};

  /// (Abstand, Abschnitt) des nächsten Abschnitts bis [maxDistance], sonst (-1, -1).
  (double, int) nearest((int, int) point, {required double maxDistance}) {
    final reach = (maxDistance / cell).ceil();
    final cx = (point.$1 / cell).floor();
    final cy = (point.$2 / cell).floor();
    var best = maxDistance;
    var segment = -1;
    final seen = <int>{};
    for (var x = cx - reach; x <= cx + reach; x++) {
      for (var y = cy - reach; y <= cy + reach; y++) {
        for (final i in _cells[(x, y)] ?? const <int>[]) {
          if (!seen.add(i)) continue;
          final distance = WatchPackage._segmentDistance(point, points[i], points[i + 1]);
          if (distance <= best) {
            best = distance;
            segment = i;
          }
        }
      }
    }
    return segment < 0 ? (-1, -1) : (best, segment);
  }
}

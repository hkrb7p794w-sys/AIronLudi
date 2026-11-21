// Optionales Gebiete-Modul (neu in AIronLudi, Prinzip von Territory-Apps): Geschlossene Runden erobern die umschlossene
// Fläche, alle Strecken füllen die persönliche Erkundungskarte aus Kacheln. Alles gehört genau einem Benutzer.
import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import 'geo.dart';

/// Kachel des Erkundungsrasters: OSM-Kachel der Zoomstufe [zoom] (etwa 300 m × 300 m in Mitteleuropa ≈ 200 m).
final class ExplorationTile {
  const ExplorationTile(this.x, this.y);

  final int x;
  final int y;

  static const zoom = 17;
  static const _count = 1 << zoom;

  factory ExplorationTile.at(GeoPoint point) {
    final latitude = point.latitude.clamp(-85.0511, 85.0511) * math.pi / 180;
    final x = ((point.longitude + 180) / 360 * _count).floor().clamp(0, _count - 1);
    final y = ((1 - math.log(math.tan(latitude) + 1 / math.cos(latitude)) / math.pi) / 2 * _count).floor().clamp(
      0,
      _count - 1,
    );
    return ExplorationTile(x, y);
  }

  /// Ganzzahliger Schlüssel (für JSON und Mengen).
  int get key => x * _count + y;

  factory ExplorationTile.fromKey(int key) => ExplorationTile(key ~/ _count, key % _count);

  static double _latitude(int y) {
    final n = math.pi - 2 * math.pi * y / _count;
    return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  double get north => _latitude(y);
  double get south => _latitude(y + 1);
  double get west => x / _count * 360 - 180;
  double get east => (x + 1) / _count * 360 - 180;

  GeoPoint get center => GeoPoint((north + south) / 2, (west + east) / 2);

  /// Ecken im Uhrzeigersinn (für das Zeichnen).
  List<GeoPoint> get corners => [
    GeoPoint(north, west),
    GeoPoint(north, east),
    GeoPoint(south, east),
    GeoPoint(south, west),
  ];

  /// Fläche in m².
  double get areaSquareMeters => Geo.area(corners);

  @override
  bool operator ==(Object other) => other is ExplorationTile && other.x == x && other.y == y;

  @override
  int get hashCode => key.hashCode;
}

/// Erobertes Gebiet: Fläche innerhalb einer geschlossenen Runde.
final class Territory {
  const Territory({
    required this.sourceID,
    required this.name,
    required this.day,
    required this.polygon,
    required this.areaSquareMeters,
  });

  /// Herkunft (Aktivität `a<ID>` oder Route `r<ID>`).
  final String sourceID;
  final String name;
  final CalendarDay day;
  final List<GeoPoint> polygon;
  final double areaSquareMeters;

  Map<String, Object?> toJson() => {
    'source': sourceID,
    'name': name,
    'day': day.iso,
    'shape': Geo.encodePolyline(polygon, precision: 5),
    'area': areaSquareMeters.round(),
  };

  static Territory? fromJson(Object? json) {
    if (json is! Map) return null;
    final source = json['source'];
    final name = json['name'];
    final day = json['day'] is String ? CalendarDay.tryParse(json['day'] as String) : null;
    final shape = json['shape'];
    final area = json['area'];
    if (source is! String || name is! String || day == null || shape is! String || area is! num) return null;
    final polygon = Geo.decodePolyline(shape, precision: 5);
    if (polygon.length < 3) return null;
    return Territory(sourceID: source, name: name, day: day, polygon: polygon, areaSquareMeters: area.toDouble());
  }
}

/// Eine abgeschlossene Strecke für die Erkundung.
final class ExplorationTrack {
  const ExplorationTrack({required this.sourceID, required this.name, required this.day, required this.points});

  final String sourceID;
  final String name;
  final CalendarDay day;
  final List<GeoPoint> points;
}

/// Was eine Strecke neu gebracht hat.
final class ExplorationGain {
  const ExplorationGain({required this.newTiles, required this.newCapturedTiles, this.territory});

  final int newTiles;
  final int newCapturedTiles;
  final Territory? territory;

  bool get isEmpty => newTiles == 0 && newCapturedTiles == 0 && territory == null;

  static const none = ExplorationGain(newTiles: 0, newCapturedTiles: 0);
}

/// Regeln der Erkundung.
abstract final class ExplorationRules {
  /// Runde gilt als geschlossen, wenn Start und Ende höchstens so weit auseinander liegen (oder 3 % der Länge) …
  static const closeDistance = 150.0;

  /// … sie mindestens 1 km lang ist …
  static const minLoopLength = 1000.0;

  /// … und eine echte Fläche umschließt (kein „hin und zurück“): mindestens 2 ha.
  static const minLoopArea = 20000.0;

  /// Höchstzahl der Ecken eines gespeicherten Gebiets.
  static const maxPolygonPoints = 300;

  /// Gebiete über dieser Fläche (z. B. falsche GPS-Sprünge) werden nicht gewertet: 400 km².
  static const maxLoopArea = 400e6;

  static bool isClosed(List<GeoPoint> points) {
    if (points.length < 4) return false;
    final length = Geo.length(points);
    if (length < minLoopLength) return false;
    final gap = Geo.distance(points.first, points.last);
    return gap <= math.max(closeDistance, length * 0.03);
  }

  /// Umschlossenes Gebiet einer geschlossenen Runde, sonst `null`.
  static List<GeoPoint>? polygon(List<GeoPoint> points) {
    if (!isClosed(points)) return null;
    var polygon = Geo.simplify(points, 15);
    if (polygon.length > maxPolygonPoints) polygon = Geo.thin(polygon, maxPolygonPoints);
    if (polygon.length < 3) return null;
    final area = Geo.area(polygon);
    if (area < minLoopArea || area > maxLoopArea) return null;
    return polygon;
  }

  /// Alle Kacheln, die die Linie berührt (Punkte im Abstand von höchstens 50 m, damit keine Kachel übersprungen wird).
  static Set<int> tilesAlong(List<GeoPoint> points) {
    final result = <int>{};
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      result.add(ExplorationTile.at(point).key);
      if (index + 1 < points.length) {
        final next = points[index + 1];
        final distance = Geo.distance(point, next);
        if (distance > 50 && distance < 5000) {
          final steps = (distance / 50).ceil();
          for (var step = 1; step < steps; step++) {
            final t = step / steps;
            result.add(
              ExplorationTile.at(
                GeoPoint(
                  point.latitude + (next.latitude - point.latitude) * t,
                  point.longitude + (next.longitude - point.longitude) * t,
                ),
              ).key,
            );
          }
        }
      }
    }
    return result;
  }

  /// Kacheln, deren Mittelpunkt im Gebiet liegt.
  static Set<int> tilesInside(List<GeoPoint> polygon) {
    final bounds = Geo.bounds(polygon);
    final northWest = ExplorationTile.at(GeoPoint(bounds.north, bounds.west));
    final southEast = ExplorationTile.at(GeoPoint(bounds.south, bounds.east));
    final result = <int>{};
    // Schutz vor riesigen Flächen: höchstens 200 × 200 Kacheln prüfen.
    if ((southEast.x - northWest.x) > 200 || (southEast.y - northWest.y) > 200) return result;
    for (var x = northWest.x; x <= southEast.x; x++) {
      for (var y = northWest.y; y <= southEast.y; y++) {
        final tile = ExplorationTile(x, y);
        if (Geo.contains(polygon, tile.center)) result.add(tile.key);
      }
    }
    return result;
  }
}

/// Erkundungsstand eines Benutzers (Schlüssel `coach.exploration`): besuchte Kacheln mit Anzahl (Heatmap), eroberte
/// Kacheln (in geschlossenen Runden), Gebiete und bereits verarbeitete Quellen.
final class ExplorationState {
  ExplorationState({
    required this.username,
    Map<int, int>? visits,
    Set<int>? captured,
    List<Territory>? territories,
    Set<String>? processed,
  }) : visits = visits ?? {},
       captured = captured ?? {},
       territories = territories ?? [],
       processed = processed ?? {};

  final String username;
  final Map<int, int> visits;
  final Set<int> captured;
  final List<Territory> territories;
  final Set<String> processed;

  int get tileCount => visits.length;

  /// Eroberte Fläche (Summe der eroberten Kacheln) in km².
  double get capturedSquareKilometers =>
      captured.fold<double>(0, (sum, key) => sum + ExplorationTile.fromKey(key).areaSquareMeters) / 1e6;

  /// Größte zusammenhängende Gruppe besuchter Kacheln (Nachbarn über Kanten) – „Erkundungs-Cluster“.
  int get largestCluster {
    final remaining = {...visits.keys};
    var best = 0;
    while (remaining.isNotEmpty) {
      final first = remaining.first;
      remaining.remove(first);
      final queue = [first];
      var size = 0;
      while (queue.isNotEmpty) {
        final tile = ExplorationTile.fromKey(queue.removeLast());
        size++;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final key = ExplorationTile(tile.x + dx, tile.y + dy).key;
          if (remaining.remove(key)) queue.add(key);
        }
      }
      best = math.max(best, size);
    }
    return best;
  }

  /// Nimmt eine Strecke auf (einmal je Quelle).
  ExplorationGain add(ExplorationTrack track) {
    if (processed.contains(track.sourceID) || track.points.length < 2) return ExplorationGain.none;
    processed.add(track.sourceID);
    var newTiles = 0;
    for (final key in ExplorationRules.tilesAlong(track.points)) {
      final count = visits[key];
      if (count == null) newTiles++;
      visits[key] = (count ?? 0) + 1;
    }
    Territory? territory;
    var newCaptured = 0;
    if (ExplorationRules.polygon(track.points) case final polygon?) {
      territory = Territory(
        sourceID: track.sourceID,
        name: track.name,
        day: track.day,
        polygon: polygon,
        areaSquareMeters: Geo.area(polygon),
      );
      territories.add(territory);
      for (final key in ExplorationRules.tilesInside(polygon)) {
        if (captured.add(key)) newCaptured++;
      }
    }
    return ExplorationGain(newTiles: newTiles, newCapturedTiles: newCaptured, territory: territory);
  }

  /// Alles zurücksetzen (Benutzer bleibt).
  ExplorationState cleared() => ExplorationState(username: username);

  Map<String, Object?> toJson() => {
    'username': username,
    'visits': [
      for (final MapEntry(:key, :value) in visits.entries) [key, value],
    ],
    'captured': [...captured],
    'territories': [for (final territory in territories) territory.toJson()],
    'processed': [...processed],
  };

  /// Gehört der Stand einem anderen Benutzer, `null`.
  static ExplorationState? fromJson(Object? json, {required String username}) {
    if (json is! Map || json['username'] != username) return null;
    final visits = <int, int>{};
    if (json['visits'] case final List<Object?> list) {
      for (final item in list) {
        if (item case [final int key, final int count]) visits[key] = count;
      }
    }
    return ExplorationState(
      username: username,
      visits: visits,
      captured: {
        if (json['captured'] case final List<Object?> list)
          for (final item in list)
            if (item is int) item,
      },
      territories: [
        if (json['territories'] case final List<Object?> list)
          for (final item in list) ?Territory.fromJson(item),
      ],
      processed: {
        if (json['processed'] case final List<Object?> list)
          for (final item in list)
            if (item is String) item,
      },
    );
  }
}

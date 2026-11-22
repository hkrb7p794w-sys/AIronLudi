// Werkzeuge des Routenplaners (neu in AIronLudi): Wegarten aus OpenStreetMap (Overpass), Wegpunkte auf passende
// Wege ziehen, Richtungspfeile, Strecke kürzen und frei gezeichnete Routen.
import 'dart:math' as math;

import 'geo.dart';
import 'route_planning.dart';
import 'routing_formats.dart';

/// Liefert Punkte auf Wegen der gewünschten Art (Wald, Wasser, Radwege) rund um einen Ort.
abstract interface class RouteFeatureSource {
  /// Leere Liste, wenn nichts gefunden wurde oder der Dienst gestört ist (dann routet der Planer ohne).
  Future<List<GeoPoint>> attractors(
    GeoPoint center,
    double radiusMeters,
    Set<RoutePreference> preferences, {
    RouteDiscipline discipline = RouteDiscipline.run,
  });
}

/// Overpass-API (`overpass-api.de`, ohne Schlüssel): Abfrage und Antwort.
abstract final class OverpassFormat {
  /// Hauptserver und öffentliche Spiegel (gleiche Abfragesprache); fällt einer aus, fragt die App den nächsten.
  static final uris = [
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://overpass.kumi.systems/api/interpreter'),
    Uri.parse('https://overpass.private.coffee/api/interpreter'),
  ];
  static Uri get uri => uris.first;
  static const engineName = 'Overpass';

  /// Größter Suchradius (größere Abfragen dauern auf dem öffentlichen Server zu lange).
  static const maxRadius = 12000.0;

  /// Höchstzahl gelieferter Wegpunkte (Knoten) je Abfrage.
  static const maxResults = 2000;

  /// Höchstzahl der Anziehungspunkte nach dem Ausdünnen (einer je [spreadMeters]).
  static const maxAttractors = 400;
  static const spreadMeters = 80.0;

  /// Braucht die Auswahl überhaupt Punkte aus OSM? Asphalt beim Laufen regelt allein die Wegbewertung.
  static bool needed(Set<RoutePreference> preferences, RouteDiscipline discipline) =>
      preferences.contains(RoutePreference.nature) ||
      preferences.contains(RoutePreference.water) ||
      (preferences.contains(RoutePreference.dogPark) && discipline == RouteDiscipline.walk) ||
      (preferences.contains(RoutePreference.paved) && discipline.isBike);

  /// Overpass-QL: Knoten **auf** passenden Wegen im Umkreis. Bewusst nicht `out center`: Der Mittelpunkt des
  /// umgebenden Rechtecks eines gebogenen Uferwegs liegt oft im Wasser – ein Wegpunkt dort hieße „durch den Kanal“.
  static String query(
    GeoPoint center,
    double radiusMeters,
    Set<RoutePreference> preferences, {
    RouteDiscipline discipline = RouteDiscipline.run,
  }) {
    final radius = radiusMeters.clamp(500, maxRadius).round();
    final around = '(around:$radius,${center.latitude.toStringAsFixed(5)},${center.longitude.toStringAsFixed(5)})';
    final parts = <String>[];
    var sets = 0;
    if (preferences.contains(RoutePreference.water)) {
      // Wege bis 40 m neben Kanälen, Flüssen und Seen (Ufer- und Leinpfade).
      parts
        ..add('(way["waterway"~"^(canal|river)\$"]$around;way["natural"="water"]$around;)->.w;')
        ..add('way["highway"~"^(path|track|footway|cycleway|bridleway)\$"](around.w:40)->.s$sets;');
      sets++;
    }
    if (preferences.contains(RoutePreference.nature)) {
      // Unbefestigte Wald- und Feldwege, Pfade; dazu Parks.
      parts
        ..add('way["highway"~"^(path|track|bridleway)\$"]["surface"!~"^(asphalt|paved|concrete)\$"]$around->.s$sets;')
        ..add('way["leisure"="park"]$around->.s${sets + 1};');
      sets += 2;
    }
    if (preferences.contains(RoutePreference.paved) && discipline.isBike) {
      parts.add('way["highway"="cycleway"]$around->.s$sets;');
      sets++;
    }
    if (preferences.contains(RoutePreference.dogPark)) {
      parts.add('way["leisure"="dog_park"]$around->.s$sets;');
      sets++;
    }
    final union = [for (var index = 0; index < sets; index++) '.s$index;'].join();
    return '[out:json][timeout:20];${parts.join()}($union)->.all;node(w.all);out skel qt $maxResults;';
  }

  /// Knoten aus der Antwort, räumlich ausgedünnt (höchstens einer je [spreadMeters]).
  static List<GeoPoint> parse(Object? json) => spread(_points(json));

  static List<GeoPoint> _points(Object? json) {
    if (json is! Map) throw const RoutingUnavailable('Antwort von Overpass unlesbar.');
    final elements = json['elements'];
    if (elements is! List) return const [];
    return [
      for (final element in elements)
        if (element case {'center': {'lat': final num latitude, 'lon': final num longitude}})
          GeoPoint(latitude.toDouble(), longitude.toDouble())
        else if (element case {'lat': final num latitude, 'lon': final num longitude})
          GeoPoint(latitude.toDouble(), longitude.toDouble()),
    ];
  }

  /// Ein Punkt je Rasterzelle von [cellMeters], höchstens [max] (gleichmäßig über die Liste).
  static List<GeoPoint> spread(List<GeoPoint> points, {double cellMeters = spreadMeters, int max = maxAttractors}) {
    if (points.isEmpty) return const [];
    final origin = points.first;
    final cosLat = math.cos(origin.latitude * math.pi / 180);
    final seen = <(int, int)>{};
    final result = <GeoPoint>[];
    for (final point in points) {
      final cell = (
        ((point.longitude - origin.longitude) * math.pi / 180 * Geo.earthRadius * cosLat / cellMeters).floor(),
        ((point.latitude - origin.latitude) * math.pi / 180 * Geo.earthRadius / cellMeters).floor(),
      );
      if (seen.add(cell)) result.add(point);
    }
    return Geo.thin(result, max);
  }
}

/// Zieht Wegpunkte auf Wege der gewünschten Art und misst, wie viel der Strecke dort verläuft.
abstract final class PreferenceSnapper {
  /// Ersetzt jeden Zwischenpunkt durch den nächsten Anziehungspunkt, wenn dieser höchstens [maxShift] entfernt
  /// liegt; jeder Anziehungspunkt wird nur einmal verwendet. Start und Ende bleiben.
  static List<GeoPoint> snap(List<GeoPoint> waypoints, List<GeoPoint> attractors, {required double maxShift}) {
    if (attractors.isEmpty || waypoints.length < 3) return waypoints;
    final used = <int>{};
    final result = [waypoints.first];
    for (var index = 1; index < waypoints.length - 1; index++) {
      final point = waypoints[index];
      var best = -1;
      var bestDistance = maxShift;
      for (final (candidate, attractor) in attractors.indexed) {
        if (used.contains(candidate)) continue;
        final distance = Geo.distance(point, attractor);
        if (distance <= bestDistance) {
          best = candidate;
          bestDistance = distance;
        }
      }
      if (best >= 0) {
        used.add(best);
        result.add(attractors[best]);
      } else {
        result.add(point);
      }
    }
    return result..add(waypoints.last);
  }

  /// Den Zwischenpunkt, der einem der [targets] am nächsten liegt, durch diesen ersetzen (z. B. Hundewiese als fester
  /// Wegpunkt). Ohne Zwischenpunkt wird einer eingefügt.
  static List<GeoPoint> force(List<GeoPoint> waypoints, List<GeoPoint> targets) {
    if (targets.isEmpty || waypoints.length < 2) return waypoints;
    if (waypoints.length == 2) {
      final middle = Geo.midpoint(waypoints.first, waypoints.last);
      final target = targets.reduce((a, b) => Geo.distance(a, middle) <= Geo.distance(b, middle) ? a : b);
      return [waypoints.first, target, waypoints.last];
    }
    var bestIndex = 1;
    var bestTarget = targets.first;
    var bestDistance = double.infinity;
    for (var index = 1; index < waypoints.length - 1; index++) {
      for (final target in targets) {
        final distance = Geo.distance(waypoints[index], target);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = index;
          bestTarget = target;
        }
      }
    }
    return [...waypoints]..[bestIndex] = bestTarget;
  }

  /// Anteil der Strecke (0…1), der höchstens [radius] neben einem Anziehungspunkt liegt (alle 100 m gemessen).
  static double coverage(List<GeoPoint> route, List<GeoPoint> attractors, {double radius = 150}) {
    if (route.length < 2 || attractors.isEmpty) return 0;
    // Raster mit Zellen von [radius] für schnelle Nachbarsuche.
    final origin = route.first;
    final cosLat = math.cos(origin.latitude * math.pi / 180);
    (int, int) cell(GeoPoint point) => (
      ((point.longitude - origin.longitude) * math.pi / 180 * Geo.earthRadius * cosLat / radius).floor(),
      ((point.latitude - origin.latitude) * math.pi / 180 * Geo.earthRadius / radius).floor(),
    );
    final grid = <(int, int), List<GeoPoint>>{};
    for (final attractor in attractors) {
      (grid[cell(attractor)] ??= []).add(attractor);
    }
    final cumulative = Geo.cumulative(route);
    var next = 0.0;
    var samples = 0;
    var near = 0;
    for (var index = 0; index < route.length; index++) {
      // Halber Meter Spielraum gegen Rundungsfehler der Streckensumme.
      if (cumulative[index] < next - 0.5) continue;
      next = cumulative[index] + 100;
      samples++;
      final (x, y) = cell(route[index]);
      var found = false;
      for (var dx = -1; dx <= 1 && !found; dx++) {
        for (var dy = -1; dy <= 1 && !found; dy++) {
          for (final attractor in grid[(x + dx, y + dy)] ?? const <GeoPoint>[]) {
            if (Geo.distance(route[index], attractor) <= radius) {
              found = true;
              break;
            }
          }
        }
      }
      if (found) near++;
    }
    return samples == 0 ? 0 : near / samples;
  }
}

/// Richtungspfeil auf der Strecke: Ort und Richtung (Grad, 0 = Nord).
typedef DirectionArrow = ({GeoPoint point, double bearing});

/// Pfeile in gleichen Abständen entlang der Strecke, damit die Laufrichtung erkennbar ist.
abstract final class RouteArrows {
  /// Pfeile alle [spacingMeters], beginnend nach einem halben Abstand; höchstens [maxArrows] (sonst weiter auseinander).
  static List<DirectionArrow> along(List<GeoPoint> points, double spacingMeters, {int maxArrows = 80}) {
    if (points.length < 2 || spacingMeters <= 0) return const [];
    final total = Geo.length(points);
    if (total <= 0) return const [];
    var spacing = spacingMeters;
    if (total / spacing > maxArrows) spacing = total / maxArrows;
    final result = <DirectionArrow>[];
    var target = spacing / 2;
    var walked = 0.0;
    for (var index = 1; index < points.length && target < total; index++) {
      final a = points[index - 1];
      final b = points[index];
      final segment = Geo.distance(a, b);
      while (segment > 0 && target <= walked + segment && target < total) {
        final t = (target - walked) / segment;
        result.add((
          point: GeoPoint(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t),
          bearing: Geo.bearing(a, b),
        ));
        target += spacing;
      }
      walked += segment;
    }
    return result;
  }

  /// Meter je Bildpunkt in Web-Mercator bei [zoom] und Breite [latitude].
  static double metersPerPixel(double latitude, double zoom) =>
      156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);
}

/// Kilometermarke auf der Strecke („3“ bei 3 km).
typedef KilometerMark = ({int kilometer, GeoPoint point});

/// Kilometermarken entlang der Strecke, je nach Zoom in Schritten von 1, 2, 5, 10 … km.
abstract final class KilometerMarks {
  static const steps = [1, 2, 5, 10, 20, 50];

  /// Kleinster Schritt (km), bei dem Marken mindestens [minSpacingMeters] auseinander liegen.
  static int step(double minSpacingMeters) =>
      steps.firstWhere((step) => step * 1000 >= minSpacingMeters, orElse: () => steps.last);

  /// Marken alle [stepKm] Kilometer (ohne Start; das Ziel bekommt keine eigene Marke, wenn es zu nah liegt).
  static List<KilometerMark> along(List<GeoPoint> points, {int stepKm = 1}) {
    if (points.length < 2 || stepKm <= 0) return const [];
    final result = <KilometerMark>[];
    final spacing = stepKm * 1000.0;
    var target = spacing;
    var walked = 0.0;
    for (var index = 1; index < points.length; index++) {
      final a = points[index - 1];
      final b = points[index];
      final segment = Geo.distance(a, b);
      while (segment > 0 && target <= walked + segment) {
        final t = (target - walked) / segment;
        result.add((
          kilometer: (target / 1000).round(),
          point: GeoPoint(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t),
        ));
        target += spacing;
      }
      walked += segment;
    }
    // Marke direkt am Ziel (weniger als 10 % eines Schritts davor) weglassen: dort steht die Zielflagge.
    if (result.isNotEmpty && walked - result.last.kilometer * 1000 < spacing * 0.1) result.removeLast();
    return result;
  }
}

/// Strecke auf eine Länge kürzen (für offene Ziele: exakt die Wunschdistanz).
abstract final class RouteTrim {
  static List<GeoPoint> truncate(List<GeoPoint> points, double meters) {
    if (points.length < 2 || meters <= 0) return [...points];
    final result = [points.first];
    var walked = 0.0;
    for (var index = 1; index < points.length; index++) {
      final a = points[index - 1];
      final b = points[index];
      final segment = Geo.distance(a, b);
      if (walked + segment >= meters) {
        final t = segment <= 0 ? 0.0 : (meters - walked) / segment;
        final elevation = switch ((a.elevation, b.elevation)) {
          (final first?, final second?) => first + (second - first) * t,
          _ => null,
        };
        result.add(
          GeoPoint(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
            elevation: elevation,
          ),
        );
        return result;
      }
      walked += segment;
      result.add(b);
    }
    return result;
  }
}

/// Grob gezeichnete Linie → Wegpunkte für den Router (der die Linie auf echte Wege legt).
abstract final class FreehandStroke {
  /// Höchstzahl Wegpunkte je Strich (öffentliche Router begrenzen die Anzahl der Orte je Anfrage).
  static const maxWaypoints = 16;

  /// Vereinfacht den Strich und verteilt höchstens [maxWaypoints] Punkte mit mindestens [minSpacing] Abstand.
  static List<GeoPoint> waypoints(List<GeoPoint> stroke, {double minSpacing = 120}) {
    if (stroke.length < 2) return [...stroke];
    final length = Geo.length(stroke);
    if (length < minSpacing) return [stroke.first, stroke.last];
    final spacing = math.max(minSpacing, length / (maxWaypoints - 1));
    final simplified = Geo.simplify(stroke, spacing / 6);
    final result = [simplified.first];
    var sinceLast = 0.0;
    for (var index = 1; index < simplified.length; index++) {
      sinceLast += Geo.distance(simplified[index - 1], simplified[index]);
      if (sinceLast >= spacing && index < simplified.length - 1) {
        result.add(simplified[index]);
        sinceLast = 0;
      }
    }
    if (Geo.distance(result.last, simplified.last) < spacing / 3 && result.length > 1) result.removeLast();
    result.add(simplified.last);
    return Geo.thin(result, maxWaypoints);
  }
}

/// Abschnitt einer frei geplanten Route: Ziel (vom Nutzer gesetzter Punkt), Zwischenpunkte eines gezeichneten Strichs
/// und die geroutete Linie (leer, solange der Abschnitt noch neu geroutet werden muss).
final class DrawnSegment {
  const DrawnSegment({required this.target, this.vias = const [], this.points = const []});

  final GeoPoint target;
  final List<GeoPoint> vias;
  final List<GeoPoint> points;

  bool get isRouted => points.length >= 2;

  DrawnSegment withPoints(List<GeoPoint> value) => DrawnSegment(target: target, vias: vias, points: value);
}

/// Frei geplante Route: Wegpunkte mit Abschnitten dazwischen (je angetipptem Punkt bzw. gezeichnetem Strich).
/// Wegpunkte lassen sich verschieben, löschen und einfügen; betroffene Abschnitte meldet die jeweilige Methode zum
/// Neu-Routen. „Rückgängig“ nimmt die letzte Aktion zurück.
final class DrawnRoute {
  DrawnRoute();

  GeoPoint? _start;
  List<DrawnSegment> _segments = [];
  final List<(GeoPoint?, List<DrawnSegment>)> _history = [];

  /// Höchstzahl gemerkter Schritte für „Rückgängig“.
  static const maxHistory = 50;

  GeoPoint? get start => _start;

  /// Geroutete Linie je Abschnitt (unroutete als gerade Verbindung).
  List<List<GeoPoint>> get segments => [
    for (final (index, segment) in _segments.indexed)
      segment.isRouted ? segment.points : [waypoint(index), ...segment.vias, segment.target],
  ];

  List<DrawnSegment> get parts => List.unmodifiable(_segments);
  bool get isEmpty => _start == null;
  bool get hasSegments => _segments.isNotEmpty;
  bool get canUndo => _history.isNotEmpty;

  /// Wegpunkte: Start und das Ziel jedes Abschnitts.
  List<GeoPoint> get waypoints => [?_start, for (final segment in _segments) segment.target];

  /// Anfang des Abschnitts [index] (Start bzw. Ziel des vorigen Abschnitts).
  GeoPoint waypoint(int index) => index == 0 ? _start! : _segments[index - 1].target;

  /// Letzter Punkt (Anschluss für den nächsten Abschnitt).
  GeoPoint? get end => _segments.isEmpty ? _start : _segments.last.target;

  /// Ganze Strecke ohne doppelte Anschlusspunkte.
  List<GeoPoint> get points => [
    if (_start case final start? when _segments.isEmpty) start,
    for (final (index, segment) in segments.indexed) ...(index == 0 ? segment : segment.skip(1)),
  ];

  /// Geschlossen, wenn das Ende höchstens 60 m vom Start liegt.
  bool get isClosed => _segments.isNotEmpty && _start != null && Geo.distance(_segments.last.target, _start!) <= 60;

  /// Rundweg schließen lohnt sich, sobald das Ende mehr als 60 m vom Start entfernt ist.
  bool get canClose => _segments.isNotEmpty && !isClosed && Geo.distance(end!, _start!) > 60;

  /// Abschnitte, die noch geroutet werden müssen.
  List<int> get unrouted => [
    for (final (index, segment) in _segments.indexed)
      if (!segment.isRouted) index,
  ];

  /// Wegpunkte für das Routen von Abschnitt [index]: Anfang, Zwischenpunkte, Ziel.
  List<GeoPoint> request(int index) => [waypoint(index), ..._segments[index].vias, _segments[index].target];

  void _remember() {
    _history.add((_start, [..._segments]));
    if (_history.length > maxHistory) _history.removeAt(0);
  }

  void setStart(GeoPoint point) {
    _remember();
    _start = point;
    _segments = [];
  }

  /// Fertig gerouteten Abschnitt anhängen (Ziel = letzter Punkt bzw. [target]).
  void add(List<GeoPoint> segment, {GeoPoint? target, List<GeoPoint> vias = const []}) {
    if (_start == null || segment.length < 2) return;
    _remember();
    _segments = [..._segments, DrawnSegment(target: target ?? segment.last, vias: vias, points: segment)];
  }

  /// Geroutete Linie für Abschnitt [index] eintragen (nach einer Änderung; kein eigener Schritt für „Rückgängig“).
  void setRouted(int index, List<GeoPoint> points) {
    if (index < 0 || index >= _segments.length || points.length < 2) return;
    _segments = [..._segments]..[index] = _segments[index].withPoints(points);
  }

  /// Wegpunkt [index] (0 = Start) verschieben; liefert die neu zu routenden Abschnitte.
  List<int> moveWaypoint(int index, GeoPoint point) {
    if (index < 0 || index > _segments.length || _start == null) return const [];
    _remember();
    final next = [..._segments];
    final dirty = <int>[];
    if (index == 0) {
      _start = point;
    } else {
      next[index - 1] = DrawnSegment(target: point, vias: const []);
      dirty.add(index - 1);
    }
    if (index < next.length) {
      next[index] = DrawnSegment(target: next[index].target, vias: const []);
      dirty.add(index);
    }
    _segments = next;
    return dirty;
  }

  /// Wegpunkt [index] löschen; die Nachbarn werden direkt verbunden. Liefert die neu zu routenden Abschnitte.
  List<int> removeWaypoint(int index) {
    if (index < 0 || index > _segments.length || _start == null) return const [];
    _remember();
    if (_segments.isEmpty) {
      _start = null;
      return const [];
    }
    if (index == 0) {
      // Erstes Ziel wird zum Start, der erste Abschnitt entfällt.
      _start = _segments.first.target;
      _segments = _segments.sublist(1);
      return const [];
    }
    if (index == _segments.length) {
      _segments = _segments.sublist(0, _segments.length - 1);
      return const [];
    }
    final next = [..._segments];
    next[index - 1] = DrawnSegment(target: next[index].target);
    next.removeAt(index);
    _segments = next;
    return [index - 1];
  }

  /// Neuen Wegpunkt [point] in Abschnitt [segment] einfügen; liefert die beiden neu zu routenden Abschnitte.
  List<int> insertWaypoint(int segment, GeoPoint point) {
    if (segment < 0 || segment >= _segments.length) return const [];
    _remember();
    final next = [..._segments];
    final old = next[segment];
    next
      ..[segment] = DrawnSegment(target: point)
      ..insert(segment + 1, DrawnSegment(target: old.target));
    _segments = next;
    return [segment, segment + 1];
  }

  /// Abschnitt, dessen Linie höchstens [maxDistance] neben [point] verläuft (zum Einfügen), sonst `null`.
  int? nearestSegment(GeoPoint point, {double maxDistance = 80}) {
    int? best;
    var bestDistance = maxDistance;
    for (final (index, line) in segments.indexed) {
      for (var step = 1; step < line.length; step++) {
        final distance = Geo.distanceToSegment(point, line[step - 1], line[step]);
        if (distance <= bestDistance) {
          best = index;
          bestDistance = distance;
        }
      }
    }
    return best;
  }

  /// Wegpunkt höchstens [maxDistance] neben [point] (zum Auswählen), sonst `null`.
  int? nearestWaypoint(GeoPoint point, {double maxDistance = 40}) {
    int? best;
    var bestDistance = maxDistance;
    for (final (index, waypoint) in waypoints.indexed) {
      final distance = Geo.distance(point, waypoint);
      if (distance <= bestDistance) {
        best = index;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Letzte Aktion zurücknehmen.
  void undo() {
    if (_history.isEmpty) {
      _start = null;
      _segments = [];
      return;
    }
    final (start, segments) = _history.removeLast();
    _start = start;
    _segments = segments;
  }

  void reset() {
    _remember();
    _start = null;
    _segments = [];
  }

  RouteStats get stats => RouteStats.of(points);
}

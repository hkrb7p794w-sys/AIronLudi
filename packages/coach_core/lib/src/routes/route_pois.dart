// Punkte entlang einer Route aus OpenStreetMap (neu in AIronLudi): Trinkbrunnen, Hundewiesen, Kotbeutel-Spender.
import 'geo.dart';
import 'routing_formats.dart';

/// Art eines Punkts unterwegs.
enum PoiKind {
  water('Trinkbrunnen'),
  dogPark('Hundewiese'),
  bags('Kotbeutel');

  const PoiKind(this.label);

  final String label;
}

/// Punkt unterwegs mit Abstand zur Strecke.
final class RoutePoi {
  const RoutePoi({required this.kind, required this.point, this.name});

  final PoiKind kind;
  final GeoPoint point;
  final String? name;

  @override
  bool operator ==(Object other) => other is RoutePoi && other.kind == kind && other.point == point;

  @override
  int get hashCode => Object.hash(kind, point);
}

/// Liefert Punkte unterwegs im Umkreis einer Strecke (wirft [RoutingUnavailable], wenn kein Server antwortet).
abstract interface class RoutePoiSource {
  Future<List<RoutePoi>> pois(List<GeoPoint> route, {required Set<PoiKind> kinds});
}

abstract final class PoiFormat {
  /// Höchstens so viele Punkte je Abfrage.
  static const maxResults = 300;

  /// Punkte gelten als „an der Strecke“, wenn sie höchstens so weit entfernt sind.
  static const nearDistance = 120.0;

  /// Welche Punkte zur Disziplin passen: Trinkbrunnen immer; Hundewiese und Kotbeutel beim Spazieren.
  static Set<PoiKind> kindsFor({required bool walk}) =>
      walk ? {PoiKind.water, PoiKind.dogPark, PoiKind.bags} : {PoiKind.water};

  /// Overpass-QL im umgebenden Rechteck der Strecke (etwas vergrößert), mit Merkmalen und Mittelpunkten.
  static String query(List<GeoPoint> route, Set<PoiKind> kinds) {
    final bounds = Geo.bounds(route);
    const margin = 0.002; // etwa 150–200 m
    final box =
        '(${(bounds.south - margin).toStringAsFixed(5)},${(bounds.west - margin).toStringAsFixed(5)},'
        '${(bounds.north + margin).toStringAsFixed(5)},${(bounds.east + margin).toStringAsFixed(5)})';
    final parts = <String>[
      if (kinds.contains(PoiKind.water)) 'node["amenity"="drinking_water"]$box;',
      if (kinds.contains(PoiKind.dogPark)) 'way["leisure"="dog_park"]$box;',
      if (kinds.contains(PoiKind.dogPark)) 'node["leisure"="dog_park"]$box;',
      if (kinds.contains(PoiKind.bags)) 'node["vending"="excrement_bags"]$box;',
      if (kinds.contains(PoiKind.bags)) 'node["amenity"="dog_toilet"]$box;',
    ];
    return '[out:json][timeout:20];(${parts.join()});out center tags $maxResults;';
  }

  static List<RoutePoi> parse(Object? json) {
    if (json is! Map) throw const RoutingUnavailable('Antwort von Overpass unlesbar.');
    final elements = json['elements'];
    if (elements is! List) return const [];
    final result = <RoutePoi>[];
    for (final element in elements) {
      if (element is! Map) continue;
      final tags = element['tags'] is Map ? element['tags'] as Map : const <String, Object?>{};
      final kind = switch (tags) {
        {'amenity': 'drinking_water'} => PoiKind.water,
        {'leisure': 'dog_park'} => PoiKind.dogPark,
        {'vending': 'excrement_bags'} || {'amenity': 'dog_toilet'} => PoiKind.bags,
        _ => null,
      };
      if (kind == null) continue;
      final (latitude, longitude) = switch (element) {
        {'center': {'lat': final num lat, 'lon': final num lon}} => (lat.toDouble(), lon.toDouble()),
        {'lat': final num lat, 'lon': final num lon} => (lat.toDouble(), lon.toDouble()),
        _ => (double.nan, double.nan),
      };
      final point = GeoPoint(latitude, longitude);
      if (!point.isValid) continue;
      final name = tags['name'];
      result.add(RoutePoi(kind: kind, point: point, name: name is String && name.isNotEmpty ? name : null));
    }
    return result;
  }

  /// Nur Punkte nahe der Strecke, je Art höchstens einer je 300 m Strecke (keine Häufung).
  static List<RoutePoi> along(List<GeoPoint> route, List<RoutePoi> pois, {double maxDistance = nearDistance}) {
    if (route.length < 2) return const [];
    final line = Geo.thin(route, 800);
    final result = <RoutePoi>[];
    for (final poi in pois) {
      if (Geo.distanceToLine(poi.point, line) > maxDistance) continue;
      final crowded = result.any((other) => other.kind == poi.kind && Geo.distance(other.point, poi.point) < 300);
      if (!crowded) result.add(poi);
    }
    return result;
  }

  /// „2 Trinkbrunnen · 1 Hundewiese“.
  static String summary(List<RoutePoi> pois) {
    final counts = <PoiKind, int>{};
    for (final poi in pois) {
      counts[poi.kind] = (counts[poi.kind] ?? 0) + 1;
    }
    return [
      for (final kind in PoiKind.values)
        if (counts[kind] case final count?) '$count ${kind.label}',
    ].join(' · ');
  }
}

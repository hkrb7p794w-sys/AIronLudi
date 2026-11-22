import 'dart:convert';

import 'geo.dart';
import 'route_planning.dart';

/// Ergebnis eines Routers: Linie (mit Höhe, falls geliefert) und Länge.
final class RoutedPath {
  const RoutedPath({required this.points, required this.distanceMeters, required this.engine});

  final List<GeoPoint> points;
  final double distanceMeters;

  /// Name des Routers für die Quellenangabe.
  final String engine;

  bool get hasElevation => points.isNotEmpty && points.every((point) => point.elevation != null);
}

/// Der Router fand keinen Weg (z. B. Punkt im See) – anderer Wegpunkt hilft, ein anderer Router selten.
final class NoRouteFound implements Exception {
  const NoRouteFound(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Antwort unbrauchbar oder Dienst gestört (Rate-Limit, Wartung) – ein anderer Router kann helfen.
final class RoutingUnavailable implements Exception {
  const RoutingUnavailable(this.message, {this.retryAfter});

  final String message;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// Valhalla (öffentlicher Server der FOSSGIS: `valhalla1.openstreetmap.de`, ohne Schlüssel): Anfrage und Antwort.
abstract final class ValhallaFormat {
  static final routeUri = Uri.parse('https://valhalla1.openstreetmap.de/route');
  static final heightUri = Uri.parse('https://valhalla1.openstreetmap.de/height');
  static const engineName = 'Valhalla (FOSSGIS)';

  /// Höchstens so viele Punkte je Höhenanfrage.
  static const maxHeightPoints = 400;

  /// Kosten und Vorlieben je Disziplin und Variante. Werte 0…1; `use_hills` hoch = Hügel willkommen.
  static ({String costing, Map<String, Object?> options}) costing(
    RouteDiscipline discipline,
    RouteVariant variant, {
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) {
    final base = _costing(discipline, variant, elevationGain: elevationGain, distanceMeters: distanceMeters);
    return (costing: base.costing, options: {...base.options, ..._preferenceOptions(discipline, preferences)});
  }

  /// Gewichtung der gewählten Wegearten (überschreibt die Werte der Variante).
  static Map<String, Object?> _preferenceOptions(RouteDiscipline discipline, Set<RoutePreference> preferences) {
    final nature = preferences.contains(RoutePreference.nature);
    final paved = preferences.contains(RoutePreference.paved);
    final water = preferences.contains(RoutePreference.water);
    switch (discipline) {
      case RouteDiscipline.run:
        return {
          if (nature) ...{'use_tracks': 1.0, 'walkway_factor': 0.6, 'sidewalk_factor': 1.6, 'use_living_streets': 0.3},
          if (paved) ...{'use_tracks': 0.0, 'walkway_factor': 1.0, 'sidewalk_factor': 0.8, 'use_living_streets': 0.8},
          if (water && !nature && !paved) ...{'use_tracks': 0.8, 'walkway_factor': 0.7},
        };
      case RouteDiscipline.roadBike:
        return {
          if (nature) ...{'use_roads': 0.0, 'avoid_bad_surfaces': 0.6, 'use_living_streets': 0.9},
          if (paved) ...{'use_roads': 0.6, 'avoid_bad_surfaces': 1.0},
          if (water && !paved) 'avoid_bad_surfaces': 0.7,
        };
      case RouteDiscipline.gravel:
        return {
          if (nature) ...{'bicycle_type': 'Mountain', 'use_roads': 0.0, 'avoid_bad_surfaces': 0.0},
          if (paved) ...{'bicycle_type': 'Hybrid', 'use_roads': 0.5, 'avoid_bad_surfaces': 0.8},
          if (water && !paved) ...{'use_roads': 0.1, 'avoid_bad_surfaces': 0.1},
        };
    }
  }

  static ({String costing, Map<String, Object?> options}) _costing(
    RouteDiscipline discipline,
    RouteVariant variant, {
    double? elevationGain,
    double? distanceMeters,
  }) {
    // Höhenmeter-Fokus: bei flacher Vorgabe Hügel meiden, sonst suchen.
    final hillsForTarget = switch ((elevationGain, distanceMeters)) {
      (final gain?, final distance?) when distance > 0 => (gain / (distance / 1000) / 20).clamp(0.0, 1.0),
      _ => null,
    };
    final hills = switch (variant) {
      RouteVariant.balanced => hillsForTarget ?? 0.4,
      RouteVariant.hilly => hillsForTarget ?? 1.0,
      RouteVariant.green => hillsForTarget ?? 0.5,
    };
    switch (discipline) {
      case RouteDiscipline.run:
        return (
          costing: 'pedestrian',
          options: {
            'use_hills': hills,
            'use_tracks': variant == RouteVariant.green ? 1.0 : 0.6,
            'use_living_streets': variant == RouteVariant.green ? 0.9 : 0.6,
            'walkway_factor': variant == RouteVariant.green ? 0.7 : 0.9,
            'sidewalk_factor': variant == RouteVariant.green ? 1.2 : 1.0,
            'use_ferry': 0.0,
          },
        );
      case RouteDiscipline.roadBike:
        return (
          costing: 'bicycle',
          options: {
            'bicycle_type': 'Road',
            'use_roads': variant == RouteVariant.green ? 0.1 : 0.5,
            'use_hills': hills,
            'avoid_bad_surfaces': 0.9,
            'use_living_streets': variant == RouteVariant.green ? 0.8 : 0.5,
            'use_ferry': 0.0,
          },
        );
      case RouteDiscipline.gravel:
        return (
          costing: 'bicycle',
          options: {
            'bicycle_type': variant == RouteVariant.green ? 'Mountain' : 'Cross',
            'use_roads': variant == RouteVariant.green ? 0.0 : 0.25,
            'use_hills': hills,
            'avoid_bad_surfaces': 0.0,
            'use_living_streets': 0.7,
            'use_ferry': 0.0,
          },
        );
    }
  }

  static Map<String, Object?> routeBody(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) {
    final cost = costing(
      discipline,
      variant,
      elevationGain: elevationGain,
      distanceMeters: distanceMeters,
      preferences: preferences,
    );
    return {
      'locations': [
        for (final (index, point) in waypoints.indexed)
          {
            'lat': point.latitude,
            'lon': point.longitude,
            // Zwischenpunkte ohne Wenden (`through`), damit keine Stichwege zum Wegpunkt entstehen.
            'type': index == 0 || index == waypoints.length - 1 ? 'break' : 'through',
            'radius': 150,
          },
      ],
      'costing': cost.costing,
      'costing_options': {cost.costing: cost.options},
      'directions_type': 'none',
      'units': 'kilometers',
    };
  }

  static RoutedPath parseRoute(Object? json) {
    if (json is! Map) throw const RoutingUnavailable('Antwort des Routers unlesbar.');
    if (json['error'] != null || json['error_code'] != null) {
      final code = json['error_code'];
      final message = '${json['error'] ?? 'Kein Weg gefunden'}';
      // 4xx-Fehler zum Weg (z. B. 171 „No suitable edges“, 442 „No path could be found“).
      if (code is num && code >= 100 && code < 500) throw NoRouteFound(message);
      throw RoutingUnavailable(message);
    }
    final trip = json['trip'];
    if (trip is! Map) throw const RoutingUnavailable('Antwort des Routers ohne Strecke.');
    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) throw const NoRouteFound('Kein Weg gefunden.');
    final points = <GeoPoint>[];
    for (final leg in legs) {
      final shape = leg is Map ? leg['shape'] : null;
      if (shape is! String) continue;
      final decoded = Geo.decodePolyline(shape);
      points.addAll(points.isEmpty ? decoded : decoded.skip(1));
    }
    if (points.length < 2) throw const NoRouteFound('Kein Weg gefunden.');
    final summary = trip['summary'];
    // Nie übers Wasser: Fähren sind abgewertet (`use_ferry` 0), aber nicht verboten – eine Route mit Fähre verwerfen.
    if (summary is Map && summary['has_ferry'] == true) {
      throw const NoRouteFound('Die Route würde eine Fähre nutzen.');
    }
    final kilometers = summary is Map ? summary['length'] : null;
    return RoutedPath(
      points: points,
      distanceMeters: kilometers is num ? kilometers * 1000 : Geo.length(points),
      engine: engineName,
    );
  }

  static Map<String, Object?> heightBody(List<GeoPoint> points) => {
    'encoded_polyline': Geo.encodePolyline(points),
    'shape_format': 'polyline6',
    'range': false,
  };

  /// Höhen zu den angefragten Punkten (gleiche Reihenfolge); Lücken (`null`) bleiben.
  static List<double?> parseHeight(Object? json, int count) {
    if (json is! Map) throw const RoutingUnavailable('Höhendaten unlesbar.');
    final heights = json['height'];
    if (heights is! List || heights.length != count) throw const RoutingUnavailable('Höhendaten unvollständig.');
    return [for (final value in heights) value is num && value > -1000 ? value.toDouble() : null];
  }
}

/// BRouter (`brouter.de`, ohne Schlüssel) als Ausweich-Router: liefert Höhen gleich mit.
abstract final class BRouterFormat {
  static const engineName = 'BRouter';

  static String profile(
    RouteDiscipline discipline,
    RouteVariant variant, {
    Set<RoutePreference> preferences = const {},
  }) => switch (discipline) {
    RouteDiscipline.run => preferences.contains(RoutePreference.paved) ? 'shortest' : 'hiking-mountain',
    RouteDiscipline.roadBike =>
      preferences.contains(RoutePreference.nature) || variant == RouteVariant.green
          ? 'fastbike-lowtraffic'
          : 'fastbike',
    RouteDiscipline.gravel =>
      preferences.contains(RoutePreference.paved)
          ? 'trekking'
          : (preferences.contains(RoutePreference.nature) || variant == RouteVariant.green
                ? 'mtb-zossebart'
                : 'trekking'),
  };

  static Uri uri(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    Set<RoutePreference> preferences = const {},
  }) => Uri.https('brouter.de', '/brouter', {
    'lonlats': [
      for (final point in waypoints) '${point.longitude.toStringAsFixed(6)},${point.latitude.toStringAsFixed(6)}',
    ].join('|'),
    'profile': profile(discipline, variant, preferences: preferences),
    'alternativeidx': '0',
    'format': 'geojson',
  });

  static RoutedPath parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      // BRouter antwortet bei Fehlern mit Klartext („target island detected …“).
      throw NoRouteFound(body.trim().isEmpty ? 'Kein Weg gefunden.' : body.trim());
    }
    if (json is! Map) throw const RoutingUnavailable('Antwort von BRouter unlesbar.');
    final features = json['features'];
    final feature = features is List && features.isNotEmpty ? features.first : null;
    final geometry = feature is Map ? feature['geometry'] : null;
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    if (coordinates is! List || coordinates.length < 2) throw const NoRouteFound('Kein Weg gefunden.');
    final points = <GeoPoint>[
      for (final item in coordinates)
        if (item case [final num longitude, final num latitude, ...final rest])
          GeoPoint(
            latitude.toDouble(),
            longitude.toDouble(),
            elevation: rest.firstOrNull is num ? (rest.first as num).toDouble() : null,
          ),
    ];
    if (points.length < 2) throw const NoRouteFound('Kein Weg gefunden.');
    final properties = feature is Map ? feature['properties'] : null;
    // BRouter kann Fähren nicht ausschließen: steht `route=ferry` in den Wegmerkmalen, die Route verwerfen.
    final messages = properties is Map ? properties['messages'] : null;
    if (messages is List<Object?>) {
      for (final message in messages.skip(1)) {
        if (message is List<Object?> && message.any((field) => '$field'.contains('route=ferry'))) {
          throw const NoRouteFound('Die Route würde eine Fähre nutzen.');
        }
      }
    }
    final length = properties is Map ? double.tryParse('${properties['track-length']}') : null;
    return RoutedPath(points: points, distanceMeters: length ?? Geo.length(points), engine: engineName);
  }
}

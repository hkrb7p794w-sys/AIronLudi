import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../util/enum_codec.dart';
import 'geo.dart';
import 'planned_route.dart';
import 'route_planning.dart';
import 'routing_formats.dart';

/// Router und Höhendaten hinter dem Planer (in der App: Valhalla mit BRouter als Ausweich, Rate-Limit).
abstract interface class RoutingBackend {
  /// Wirft [NoRouteFound] oder [RoutingUnavailable].
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
  });

  /// Höhen zu den Punkten (gleiche Länge); wirft [RoutingUnavailable].
  Future<List<double?>> elevations(List<GeoPoint> points);
}

/// Erzeugt 2–3 Vorschläge zu den Vorgaben. Je Variante höchstens [maxAttempts] Router-Anfragen: Die Größe der
/// Wegpunkte wird nach jeder Antwort proportional nachgeführt, bis die Distanz in der Toleranz liegt.
final class RoutePlanner {
  RoutePlanner(this.backend, {String Function()? newID, DateTime Function()? now})
    : _newID = newID ?? const Uuid().v4,
      _now = now ?? DateTime.now;

  final RoutingBackend backend;
  final String Function() _newID;
  final DateTime Function() _now;

  static const maxAttempts = 3;

  /// Höchstzahl der Punkte für eine Höhenanfrage; dazwischen wird über die Strecke interpoliert.
  static const elevationSamples = ValhallaFormat.maxHeightPoints;

  Future<List<PlannedRoute>> generate(
    RouteRequest request, {
    required String username,
    int seed = 0,
    List<RouteVariant> variants = RouteVariant.values,
    int? runThresholdPace,
    void Function(String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (request.problem case final problem?) throw ArgumentError(problem);
    final result = <PlannedRoute>[];
    Object? lastError;
    for (final variant in variants) {
      if (isCancelled?.call() ?? false) break;
      onProgress?.call('${variant.label} wird berechnet …');
      try {
        final route = await _variant(request, variant, seed: seed);
        if (route == null) continue;
        var withElevation = route;
        if (!route.hasElevation) {
          try {
            withElevation = await _fillElevation(route);
          } on RoutingUnavailable {
            // Höhendienst gestört: Vorschlag ohne Höhenprofil zeigen statt gar keinen.
          }
        }
        // Nahezu gleiche Strecke wie ein schon gefundener Vorschlag: weglassen.
        if (result.any((other) => _similar(other.points, withElevation.points))) continue;
        result.add(
          PlannedRoute(
            id: _newID(),
            username: username,
            name: PlannedRoute.suggestedName(request, variant, withElevation.distanceMeters),
            request: request,
            variant: variant,
            points: PlannedRoute.storable(withElevation.points),
            engine: withElevation.engine,
            createdAt: _now(),
            runThresholdPace: runThresholdPace,
          ),
        );
      } on RoutingUnavailable catch (error) {
        lastError = error;
      } on NoRouteFound catch (error) {
        lastError = error;
      }
    }
    if (result.isEmpty) {
      if (lastError is RoutingUnavailable) throw lastError;
      throw NoRouteFound(
        lastError == null
            ? 'Keine Route gefunden.'
            : 'Keine Route gefunden. Versuche einen anderen Startpunkt oder eine andere Distanz.',
      );
    }
    return result;
  }

  Future<RoutedPath?> _variant(RouteRequest request, RouteVariant variant, {required int seed}) async {
    final variantSeed = seed * 31 + variant.index;
    var bearing = RouteWaypointPlanner.bearingFor(
      seed: seed,
      variant: variant,
      preferred: request.shape == RouteShape.loop ? request.bearingDegrees : null,
    );
    if (request.shape == RouteShape.direction) {
      bearing = (request.bearingDegrees! + (variant.index - 1) * 12 + 360) % 360;
    }
    var length = RouteWaypointPlanner.initialLength(request);
    RoutedPath? best;
    var bestScore = double.infinity;
    final wantsElevation = request.elevationGainMeters != null;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final waypoints = switch (request.shape) {
        RouteShape.loop => RouteWaypointPlanner.loop(
          start: request.start,
          geometricLength: length,
          bearingDegrees: bearing,
          seed: variantSeed + attempt,
        ),
        RouteShape.toDestination => RouteWaypointPlanner.toDestination(
          start: request.start,
          destination: request.destination!,
          geometricLength: length,
          side: variant == RouteVariant.hilly ? -1 : 1,
        ),
        RouteShape.direction => RouteWaypointPlanner.direction(
          start: request.start,
          geometricLength: length,
          bearingDegrees: bearing,
          seed: variantSeed + attempt,
        ),
      };
      RoutedPath path;
      try {
        path = await backend.route(
          waypoints,
          discipline: request.discipline,
          variant: variant,
          elevationGain: request.elevationGainMeters,
          distanceMeters: request.distanceMeters,
        );
      } on NoRouteFound {
        // Wegpunkt lag z. B. im Wasser: etwas gedreht noch einmal.
        bearing = (bearing + 35) % 360;
        continue;
      }
      // Bei Höhen-Vorgabe zählt die Höhe schon bei der Auswahl.
      if (wantsElevation && !path.hasElevation) {
        try {
          path = await _fillElevation(path);
        } on RoutingUnavailable {
          // Ohne Höhen weiter; bewertet wird dann nur die Distanz.
        }
      }
      final stats = RouteStats.of(path.points);
      final score = RouteScore.of(
        request: request,
        variant: variant,
        stats: RouteStats(
          distanceMeters: path.distanceMeters,
          ascentMeters: stats.ascentMeters,
          descentMeters: stats.descentMeters,
          minElevation: stats.minElevation,
          maxElevation: stats.maxElevation,
        ),
        overlap: RouteScore.overlap(path.points),
      );
      if (score < bestScore) {
        best = path;
        bestScore = score;
      }
      final elevationOK = switch (request.elevationGainMeters) {
        final target? when stats.hasElevation && variant == RouteVariant.hilly =>
          (stats.ascentMeters - target).abs() <= math.max(target * 0.25, 30),
        _ => true,
      };
      if (request.withinTolerance(path.distanceMeters) && elevationOK) break;
      // Direkt zum Ziel ist schon zu lang: kürzer geht nicht.
      if (waypoints.length == 2 && path.distanceMeters > request.distanceMeters) break;
      length = RouteWaypointPlanner.rescale(
        geometricLength: length,
        routedMeters: path.distanceMeters,
        targetMeters: request.distanceMeters,
      );
    }
    return best;
  }

  /// Höhen für höchstens [elevationSamples] Punkte holen und dazwischen über die Strecke interpolieren.
  Future<RoutedPath> _fillElevation(RoutedPath path) async {
    final points = path.points;
    final indices = _sampleIndices(points.length, elevationSamples);
    final heights = await backend.elevations([for (final index in indices) points[index]]);
    return RoutedPath(
      points: ElevationFill.interpolate(points, indices, heights),
      distanceMeters: path.distanceMeters,
      engine: path.engine,
    );
  }

  static List<int> _sampleIndices(int count, int max) {
    if (count <= max) return [for (var index = 0; index < count; index++) index];
    final step = (count - 1) / (max - 1);
    return {for (var index = 0; index < max; index++) (index * step).round()}.toList();
  }

  /// Gleich, wenn sich die Strecken zu über 85 % decken (Raster wie [RouteScore.overlap]).
  static bool _similar(List<GeoPoint> a, List<GeoPoint> b) {
    Set<(int, int)> cells(List<GeoPoint> points) => {
      for (final point in Geo.thin(points, 600)) ((point.latitude * 2000).floor(), (point.longitude * 1300).floor()),
    };
    final first = cells(a);
    final second = cells(b);
    if (first.isEmpty || second.isEmpty) return false;
    final shared = first.intersection(second).length;
    return shared / math.min(first.length, second.length) > 0.85;
  }
}

/// Höhen von Stützpunkten linear über die Strecke auf alle Punkte verteilen.
abstract final class ElevationFill {
  static List<GeoPoint> interpolate(List<GeoPoint> points, List<int> indices, List<double?> heights) {
    final known = <(int, double)>[
      for (final (position, index) in indices.indexed)
        if (position < heights.length && heights[position] != null) (index, heights[position]!),
    ];
    if (known.isEmpty) return points;
    final cumulative = Geo.cumulative(points);
    final result = <GeoPoint>[];
    var cursor = 0;
    for (var index = 0; index < points.length; index++) {
      while (cursor + 1 < known.length && known[cursor + 1].$1 <= index) {
        cursor++;
      }
      final (leftIndex, leftHeight) = known[cursor];
      double elevation;
      if (index <= leftIndex || cursor + 1 >= known.length) {
        elevation = leftHeight;
      } else {
        final (rightIndex, rightHeight) = known[cursor + 1];
        final span = cumulative[rightIndex] - cumulative[leftIndex];
        final t = span <= 0 ? 0.0 : (cumulative[index] - cumulative[leftIndex]) / span;
        elevation = leftHeight + (rightHeight - leftHeight) * t;
      }
      result.add(points[index].withElevation(elevation));
    }
    return result;
  }
}

/// Einstellungen des Routenplaners (Schlüssel `coach.routePlanner`): letzte Vorgaben und das optionale Gebiete-Modul.
final class RoutePlannerSettings {
  RoutePlannerSettings({
    this.explorationEnabled = false,
    this.discipline = RouteDiscipline.run,
    this.shape = RouteShape.loop,
    this.distanceKilometers = 10,
    this.elevationGain,
  });

  /// Gebiete und Erkundungskarte (standardmäßig aus, wie ausblendbare Bereiche).
  bool explorationEnabled;
  RouteDiscipline discipline;
  RouteShape shape;
  double distanceKilometers;
  int? elevationGain;

  Map<String, Object?> toJson() => {
    'explorationEnabled': explorationEnabled,
    'discipline': discipline.rawValue,
    'shape': shape.rawValue,
    'distanceKilometers': distanceKilometers,
    'elevationGain': ?elevationGain,
  };

  static RoutePlannerSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final distance = json['distanceKilometers'];
    final gain = json['elevationGain'];
    return RoutePlannerSettings(
      explorationEnabled: json['explorationEnabled'] == true,
      discipline: enumFromRaw(RouteDiscipline.values, json['discipline']) ?? RouteDiscipline.run,
      shape: enumFromRaw(RouteShape.values, json['shape']) ?? RouteShape.loop,
      distanceKilometers: distance is num && distance > 0 ? distance.toDouble() : 10,
      elevationGain: gain is num ? gain.toInt() : null,
    );
  }
}

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../util/enum_codec.dart';
import 'geo.dart';
import 'planned_route.dart';
import 'route_planning.dart';
import 'route_tools.dart';
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
    Set<RoutePreference> preferences = const {},
  });

  /// Höhen zu den Punkten (gleiche Länge); wirft [RoutingUnavailable].
  Future<List<double?>> elevations(List<GeoPoint> points);
}

/// Erzeugt 2–3 Vorschläge zu den Vorgaben. Je Variante höchstens [maxAttempts] Router-Anfragen: Die Größe der
/// Wegpunkte wird nach jeder Antwort nachgeführt (erst proportional, dann zwischen der besten zu kurzen und der besten
/// zu langen Strecke interpoliert), bis die Distanz in ±2,5 % liegt. Offene Ziele werden exakt gekürzt. Mit
/// gewählten Wegearten (Wald, Wasser, Radwege) zieht der Planer die Wegpunkte auf passende OSM-Wege.
final class RoutePlanner {
  RoutePlanner(this.backend, {this.features, String Function()? newID, DateTime Function()? now})
    : _newID = newID ?? const Uuid().v4,
      _now = now ?? DateTime.now;

  final RoutingBackend backend;
  final RouteFeatureSource? features;
  final String Function() _newID;
  final DateTime Function() _now;

  static const maxAttempts = 6;

  /// Höchstzahl der Punkte für eine Höhenanfrage; dazwischen wird über die Strecke interpoliert.
  static const elevationSamples = ValhallaFormat.maxHeightPoints;

  Future<List<PlannedRoute>> generate(
    RouteRequest request, {
    required String username,
    int seed = 0,
    List<RouteVariant> variants = RouteVariant.values,
    int? runThresholdPace,
    void Function(String message)? onProgress,
    void Function(PlannedRoute route)? onRoute,
    bool Function()? isCancelled,
  }) async {
    if (request.problem case final problem?) throw ArgumentError(problem);
    if (request.shape == RouteShape.drawn) throw ArgumentError('Frei geplante Routen erzeugt der Planer nicht.');
    var attractors = const <GeoPoint>[];
    if (features != null && OverpassFormat.needed(request.preferences, request.discipline)) {
      onProgress?.call('Passende Wege werden gesucht …');
      final area = searchArea(request);
      try {
        attractors = await features!.attractors(
          area.center,
          area.radius,
          request.preferences,
          discipline: request.discipline,
        );
      } on Object {
        // Ohne Overpass: nur die Wegbewertung des Routers.
      }
    }
    final result = <PlannedRoute>[];
    Object? lastError;
    for (final variant in variants) {
      if (isCancelled?.call() ?? false) break;
      onProgress?.call('${variant.label} wird berechnet …');
      try {
        final found = await _variant(request, variant, seed: seed, attractors: attractors, onProgress: onProgress);
        if (found == null) continue;
        var withElevation = found;
        if (!found.hasElevation) {
          try {
            withElevation = await _fillElevation(found);
          } on RoutingUnavailable {
            // Höhendienst gestört: Vorschlag ohne Höhenprofil zeigen statt gar keinen.
          }
        }
        // Nahezu gleiche Strecke wie ein schon gefundener Vorschlag: weglassen.
        if (result.any((other) => _similar(other.points, withElevation.points))) continue;
        final route = PlannedRoute(
          id: _newID(),
          username: username,
          name: PlannedRoute.suggestedName(request, variant, withElevation.distanceMeters),
          request: request,
          variant: variant,
          points: PlannedRoute.storable(withElevation.points),
          engine: withElevation.engine,
          createdAt: _now(),
          runThresholdPace: runThresholdPace,
          preferenceShare: attractors.isEmpty ? null : PreferenceSnapper.coverage(withElevation.points, attractors),
        );
        result.add(route);
        // Jeder Vorschlag sofort, nicht erst wenn alle fertig sind.
        onRoute?.call(route);
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

  /// Wo nach passenden Wegen gesucht wird: um die erwartete Strecke herum.
  static ({GeoPoint center, double radius}) searchArea(RouteRequest request) {
    final distance = request.distanceMeters;
    final (center, radius) = switch (request.shape) {
      RouteShape.loop => (request.start, distance / (2 * math.pi) * 2.3),
      RouteShape.toDestination => (
        Geo.midpoint(request.start, request.destination!),
        math.max(Geo.distance(request.start, request.destination!) / 2, distance / 3) * 1.2,
      ),
      RouteShape.direction => (
        Geo.destination(request.start, request.bearingDegrees ?? 0, distance / 2.5),
        distance / 2.5,
      ),
      RouteShape.drawn => (request.start, distance / 2),
    };
    return (center: center, radius: radius.clamp(800.0, OverpassFormat.maxRadius));
  }

  Future<RoutedPath?> _variant(
    RouteRequest request,
    RouteVariant variant, {
    required int seed,
    required List<GeoPoint> attractors,
    void Function(String message)? onProgress,
  }) async {
    final variantSeed = seed * 31 + variant.index;
    var bearing = RouteWaypointPlanner.bearingFor(
      seed: seed,
      variant: variant,
      preferred: request.shape == RouteShape.loop ? request.bearingDegrees : null,
    );
    if (request.shape == RouteShape.direction) {
      bearing = (request.bearingDegrees! + (variant.index - 1) * 12 + 360) % 360;
    }
    final target = request.distanceMeters;
    final initial = RouteWaypointPlanner.initialLength(request);
    var length = initial;
    RoutedPath? best;
    var bestScore = double.infinity;
    // Klammer für die Interpolation: beste zu kurze und beste zu lange Antwort (Größe, Länge).
    (double, double)? below;
    (double, double)? above;
    final wantsElevation = request.elevationGainMeters != null;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) onProgress?.call('${variant.label}: Distanz wird angepasst ($attempt/${maxAttempts - 1}) …');
      var waypoints = switch (request.shape) {
        RouteShape.loop => RouteWaypointPlanner.loop(
          start: request.start,
          geometricLength: length,
          bearingDegrees: bearing,
          seed: variantSeed + attempt,
          points: attractors.isEmpty ? 3 : 4,
        ),
        RouteShape.toDestination => RouteWaypointPlanner.toDestination(
          start: request.start,
          destination: request.destination!,
          geometricLength: length,
          side: variant == RouteVariant.hilly ? -1 : 1,
        ),
        RouteShape.direction || RouteShape.drawn => RouteWaypointPlanner.direction(
          start: request.start,
          geometricLength: length,
          bearingDegrees: bearing,
          seed: variantSeed + attempt,
        ),
      };
      if (attractors.isNotEmpty) {
        // Wegpunkte auf passende Wege ziehen; nicht zu weit, sonst stimmt die Form nicht mehr.
        final shift = switch (request.shape) {
          RouteShape.loop => length / (2 * math.pi) * 0.45,
          _ => length * 0.12,
        };
        waypoints = PreferenceSnapper.snap(waypoints, attractors, maxShift: shift);
      }
      RoutedPath path;
      try {
        path = await backend.route(
          waypoints,
          discipline: request.discipline,
          variant: variant,
          elevationGain: request.elevationGainMeters,
          distanceMeters: target,
          preferences: request.preferences,
        );
      } on NoRouteFound {
        // Wegpunkt lag z. B. im Wasser: etwas gedreht noch einmal.
        bearing = (bearing + 35) % 360;
        continue;
      }
      // Offenes Ziel: Endpunkt ist frei – lange Strecken exakt auf die Wunschdistanz kürzen.
      final open = request.shape == RouteShape.direction;
      if (open && path.distanceMeters >= target) {
        final trimmed = RouteTrim.truncate(path.points, target * path.distanceMeters / Geo.length(path.points));
        path = RoutedPath(points: trimmed, distanceMeters: target, engine: path.engine);
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
      var score = RouteScore.of(
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
      if (attractors.isNotEmpty) score -= PreferenceSnapper.coverage(path.points, attractors) * 0.03;
      if (score < bestScore) {
        best = path;
        bestScore = score;
      }
      final elevationOK = switch (request.elevationGainMeters) {
        final targetGain? when stats.hasElevation && variant == RouteVariant.hilly =>
          (stats.ascentMeters - targetGain).abs() <= math.max(targetGain * 0.25, 30),
        _ => true,
      };
      if (request.withinTolerance(path.distanceMeters) && elevationOK) break;
      // Direkt zum Ziel ist schon zu lang: kürzer geht nicht.
      if (waypoints.length == 2 && path.distanceMeters > target) break;
      final routed = path.distanceMeters;
      if (routed < target) {
        if (below == null || routed > below.$2) below = (length, routed);
      } else if (above == null || routed < above.$2) {
        above = (length, routed);
      }
      length = RouteSizing.next(
        length: length,
        routed: routed,
        target: target,
        below: below,
        above: above,
        // Offene Ziele lieber etwas zu lang planen: der Rest wird gekürzt.
        overshoot: open ? 1.06 : 1,
      ).clamp(initial * 0.3, initial * 3);
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

/// Nächste Größe der Wegpunkte: Liegen schon eine zu kurze und eine zu lange Antwort vor, linear dazwischen
/// interpoliert (Sekantenverfahren), sonst proportional nachgeführt.
abstract final class RouteSizing {
  static double next({
    required double length,
    required double routed,
    required double target,
    (double, double)? below,
    (double, double)? above,
    double overshoot = 1,
  }) {
    final goal = target * overshoot;
    if (below != null && above != null && above.$2 > below.$2) {
      final t = (goal - below.$2) / (above.$2 - below.$2);
      return below.$1 + (above.$1 - below.$1) * t.clamp(0.05, 0.95);
    }
    return RouteWaypointPlanner.rescale(geometricLength: length, routedMeters: routed, targetMeters: goal);
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
    Set<RoutePreference>? preferences,
  }) : preferences = preferences ?? {};

  /// Gebiete und Erkundungskarte (standardmäßig aus, wie ausblendbare Bereiche).
  bool explorationEnabled;
  RouteDiscipline discipline;
  RouteShape shape;
  double distanceKilometers;
  int? elevationGain;
  Set<RoutePreference> preferences;

  Map<String, Object?> toJson() => {
    'explorationEnabled': explorationEnabled,
    'discipline': discipline.rawValue,
    'shape': shape.rawValue,
    'distanceKilometers': distanceKilometers,
    'elevationGain': ?elevationGain,
    'preferences': [
      for (final preference in RoutePreference.values)
        if (preferences.contains(preference)) preference.rawValue,
    ],
  };

  static RoutePlannerSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final distance = json['distanceKilometers'];
    final gain = json['elevationGain'];
    return RoutePlannerSettings(
      explorationEnabled: json['explorationEnabled'] == true,
      discipline: enumFromRaw(RouteDiscipline.values, json['discipline']) ?? RouteDiscipline.run,
      shape: enumFromRaw(RouteShape.generated, json['shape']) ?? RouteShape.loop,
      distanceKilometers: distance is num && distance > 0 ? distance.toDouble() : 10,
      elevationGain: gain is num ? gain.toInt() : null,
      preferences: {...enumListFromRaw(RoutePreference.values, json['preferences'])},
    );
  }
}

// Routenplaner (neu in AIronLudi, keine Swift-Vorlage): Vorgaben, Wegpunkte für Rundwege und Strecken,
// Höhenprofil, Dauer und Bewertung der Vorschläge. Regeln entscheiden – das Routing selbst liefert ein
// OSM-Router (Valhalla, BRouter) über den RoutePlannerService der App.
import 'dart:math' as math;

import '../util/enum_codec.dart';
import 'geo.dart';

/// Disziplin des Routenplaners samt Wegbevorzugung.
enum RouteDiscipline implements RawEnum {
  /// Fuß- und Waldwege, Parks, ruhige Nebenstraßen (`footway`, `path`, `track`).
  run('run', 'Laufen', 'figure.run'),

  /// Asphaltierte Radwege und Straßen (`cycleway`, `surface=asphalt`).
  roadBike('roadBike', 'Rennrad', 'figure.outdoor.cycle'),

  /// Gemischte und unbefestigte Wege (`gravel`, `track`).
  gravel('gravel', 'Gravel', 'bicycle'),

  /// Gemütliche Runden, z. B. Gassi mit dem Hund: ruhige Fußwege, Parks, Grünflächen; Gehtempo statt Lauftempo.
  walk('walk', 'Spazieren', 'figure.walk');

  const RouteDiscipline(this.rawValue, this.label, this.symbol);

  @override
  final String rawValue;
  final String label;
  final String symbol;

  bool get isBike => this == roadBike || this == gravel;

  /// Zu Fuß (Laufen, Spazieren): Fußwege-Profil der Router.
  bool get onFoot => !isBike;

  /// Beschreibung der bevorzugten Wege (Auswahl im Planer).
  String get surfaces => switch (this) {
    run => 'Fuß- und Waldwege, Parks, ruhige Nebenstraßen',
    roadBike => 'Asphalt: Radwege und ruhige Straßen',
    gravel => 'Gemischt: Schotter, Feld- und Waldwege',
    walk => 'Ruhige Fußwege, Parks und Grünflächen – ideal für Gassi-Runden',
  };
}

/// Form der Strecke.
enum RouteShape implements RawEnum {
  /// Start = Ziel.
  loop('loop', 'Rundweg'),

  /// Fester Zielpunkt auf der Karte; bei Bedarf mit Umweg zur Wunschdistanz.
  toDestination('toDestination', 'Zum Ziel'),

  /// Offenes Ziel: Himmelsrichtung und Distanz.
  direction('direction', 'Richtung'),

  /// Frei gezeichnet bzw. aus angetippten Wegpunkten (Modus „Frei planen“).
  drawn('drawn', 'Frei geplant');

  const RouteShape(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;

  /// Formen, die der Planer automatisch erzeugt.
  static const generated = [loop, toDestination, direction];
}

/// Bevorzugte Umgebung bzw. Wegeart. Keine Auswahl = ausgewogener Mix.
enum RoutePreference implements RawEnum {
  /// Wald- und Forstwege, Trails, Parks (`highway=track|path`, `landuse=forest`, `natural=wood`, `leisure=park`).
  nature('nature', 'Wald & Natur', 'Wald- und Forstwege, Trails, Parks'),

  /// Ufer- und Leinpfade entlang von Kanälen, Flüssen und Seen (`waterway=canal|river`, `natural=water`) – immer an
  /// Land: Wegpunkte liegen auf Wegen, Fähren sind ausgeschlossen.
  water('water', 'Am Wasser', 'Entlang von Kanälen, Flüssen und Seen – auf Uferwegen, ohne Fähre'),

  /// Befestigte Straßen und Radwege (`highway=cycleway`, `surface=asphalt`).
  paved('paved', 'Straße & Asphalt', 'Befestigte Wege, Radwege und ruhige Straßen'),

  /// Nur beim Spazieren: Die Runde führt über eine Hundewiese in der Nähe (`leisure=dog_park`).
  dogPark('dogPark', 'Hundewiese', 'Die Runde führt über eine Hundewiese in der Nähe');

  const RoutePreference(this.rawValue, this.label, this.detail);

  @override
  final String rawValue;
  final String label;
  final String detail;

  static const mixLabel = 'Ausgewogener Mix';

  /// Wählbare Wegarten je Disziplin (Hundewiese nur beim Spazieren).
  static List<RoutePreference> available(RouteDiscipline discipline) => [
    for (final preference in values)
      if (preference != dogPark || discipline == RouteDiscipline.walk) preference,
  ];

  /// Natur und Asphalt schließen sich aus; Wasser passt zu beidem.
  static Set<RoutePreference> toggle(Set<RoutePreference> current, RoutePreference preference) {
    if (current.contains(preference)) return {...current}..remove(preference);
    return {
      ...current.where((item) => !(preference == nature && item == paved) && !(preference == paved && item == nature)),
      preference,
    };
  }

  static String describe(Set<RoutePreference> preferences) => preferences.isEmpty
      ? mixLabel
      : [
          for (final preference in values)
            if (preferences.contains(preference)) preference.label,
        ].join(' + ');
}

/// Charakter eines Vorschlags.
enum RouteVariant implements RawEnum {
  balanced('balanced', 'Direkt & ausgeglichen'),
  hilly('hilly', 'Höhenmeter-Fokus'),
  green('green', 'Grün & verkehrsarm');

  const RouteVariant(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;
}

/// Himmelsrichtungen für Strecken mit offenem Ziel.
enum CompassDirection {
  north('N', 0),
  northEast('NO', 45),
  east('O', 90),
  southEast('SO', 135),
  south('S', 180),
  southWest('SW', 225),
  west('W', 270),
  northWest('NW', 315);

  const CompassDirection(this.label, this.degrees);

  final String label;
  final double degrees;

  static CompassDirection nearest(double degrees) {
    final index = (((degrees % 360) + 360) % 360 / 45).round() % 8;
    return values[index];
  }
}

/// Vorgaben des Nutzers.
final class RouteRequest {
  const RouteRequest({
    required this.discipline,
    required this.shape,
    required this.start,
    required this.distanceMeters,
    this.destination,
    this.bearingDegrees,
    this.elevationGainMeters,
    this.preferences = const {},
    this.direct = false,
  });

  final RouteDiscipline discipline;
  final RouteShape shape;
  final GeoPoint start;
  final GeoPoint? destination;

  /// Richtung (Grad) bei [RouteShape.direction]; bei Rundwegen optional die Richtung der Schleife.
  final double? bearingDegrees;
  final double distanceMeters;

  /// Gewünschte kumulierte Höhenmeter (Anstieg); `null`: egal.
  final double? elevationGainMeters;

  /// Bevorzugte Wegearten (leer: ausgewogener Mix).
  final Set<RoutePreference> preferences;

  /// Nur bei [RouteShape.toDestination]: ohne Wunschdistanz – der beste Weg von Start zum Ziel (z. B. Lauf zur
  /// Arbeit). [distanceMeters] ist dann nur eine Schätzung.
  final bool direct;

  /// Strecke zum Ziel ohne Wunschdistanz.
  bool get isDirect => direct && shape == RouteShape.toDestination;

  /// Geschätzte Distanz eines direkten Wegs (Luftlinie × typischer Umweg des Wegenetzes).
  static double directEstimate(GeoPoint start, GeoPoint destination) =>
      Geo.distance(start, destination) * RouteWaypointPlanner.roadFactor;

  /// Größte Luftlinie für Strecken ohne Wunschdistanz.
  static double maxDirect(RouteDiscipline discipline) => maxDistance(discipline) / RouteWaypointPlanner.roadFactor;

  /// Erlaubte Abweichung der Distanz (±2,5 %, bei 10 km also ±250 m).
  static const tolerance = 0.025;

  /// Grenzen der Eingabe.
  static const minDistance = 1000.0;
  static double maxDistance(RouteDiscipline discipline) => switch (discipline) {
    RouteDiscipline.roadBike || RouteDiscipline.gravel => 250000,
    RouteDiscipline.run => 60000,
    RouteDiscipline.walk => 30000,
  };

  /// Fehler der Eingabe für die Anzeige, sonst `null`.
  String? get problem {
    if (!start.isValid) return 'Bitte einen Startpunkt wählen.';
    if (shape == RouteShape.drawn) return null;
    if (isDirect) {
      final destination = this.destination;
      if (destination == null || !destination.isValid) return 'Bitte einen Zielpunkt auf der Karte setzen.';
      final distance = Geo.distance(start, destination);
      if (distance < 100) return 'Start und Ziel liegen zu nah beieinander.';
      if (distance > maxDirect(discipline)) return 'Das Ziel liegt zu weit weg für ${discipline.label}.';
      return null;
    }
    if (distanceMeters < minDistance) return 'Die Distanz muss mindestens 1 km betragen.';
    if (distanceMeters > maxDistance(discipline)) {
      return 'Höchstens ${maxDistance(discipline) ~/ 1000} km für ${discipline.label}.';
    }
    if (shape == RouteShape.toDestination) {
      final destination = this.destination;
      if (destination == null || !destination.isValid) return 'Bitte einen Zielpunkt auf der Karte setzen.';
      if (Geo.distance(start, destination) < 100) return 'Start und Ziel liegen zu nah beieinander.';
    }
    if (shape == RouteShape.direction && bearingDegrees == null) return 'Bitte eine Himmelsrichtung wählen.';
    if (elevationGainMeters case final gain? when gain < 0) return 'Höhenmeter können nicht negativ sein.';
    return null;
  }

  /// Ohne Wunschdistanz passt jede Länge.
  bool withinTolerance(double meters) => isDirect || (meters - distanceMeters).abs() <= distanceMeters * tolerance;

  RouteRequest copyWith({GeoPoint? start, GeoPoint? destination}) => RouteRequest(
    discipline: discipline,
    shape: shape,
    start: start ?? this.start,
    destination: destination ?? this.destination,
    bearingDegrees: bearingDegrees,
    distanceMeters: distanceMeters,
    elevationGainMeters: elevationGainMeters,
    preferences: preferences,
    direct: direct,
  );

  Map<String, Object?> toJson() => {
    'discipline': discipline.rawValue,
    'shape': shape.rawValue,
    'start': start.toJson(),
    'destination': ?destination?.toJson(),
    'bearing': ?bearingDegrees,
    'distance': distanceMeters,
    'elevationGain': ?elevationGainMeters,
    if (preferences.isNotEmpty)
      'preferences': [
        for (final preference in RoutePreference.values)
          if (preferences.contains(preference)) preference.rawValue,
      ],
    if (direct) 'direct': true,
  };

  static RouteRequest? fromJson(Object? json) {
    if (json is! Map) return null;
    final discipline = enumFromRaw(RouteDiscipline.values, json['discipline']);
    final shape = enumFromRaw(RouteShape.values, json['shape']);
    final start = GeoPoint.fromJson(json['start']);
    final distance = json['distance'];
    if (discipline == null || shape == null || start == null || distance is! num) return null;
    final bearing = json['bearing'];
    final gain = json['elevationGain'];
    return RouteRequest(
      discipline: discipline,
      shape: shape,
      start: start,
      destination: GeoPoint.fromJson(json['destination']),
      bearingDegrees: bearing is num ? bearing.toDouble() : null,
      distanceMeters: distance.toDouble(),
      elevationGainMeters: gain is num ? gain.toDouble() : null,
      preferences: {...enumListFromRaw(RoutePreference.values, json['preferences'])},
      direct: json['direct'] == true,
    );
  }
}

/// Wegpunkte, die der Router zu einer Strecke der gewünschten Länge verbindet. Alles deterministisch aus dem
/// Startwert ([seed]): „Neu würfeln“ wählt nur einen anderen Startwert.
abstract final class RouteWaypointPlanner {
  /// Typischer Umwegfaktor des Wegenetzes gegenüber der Luftlinie.
  static const roadFactor = 1.25;

  /// Richtung (Grad) der Schleife bzw. des Umwegs für Variante [variant] beim Würfeln [seed].
  static double bearingFor({required int seed, required RouteVariant variant, double? preferred}) {
    final base = preferred ?? (math.Random(seed).nextDouble() * 360);
    // Varianten zeigen in verschiedene Richtungen; mit gewählter Richtung nur leicht versetzt.
    final spread = preferred == null ? 120.0 : 25.0;
    final offset = switch (variant) {
      RouteVariant.balanced => 0.0,
      RouteVariant.hilly => spread,
      RouteVariant.green => -spread,
    };
    return (base + offset + 360) % 360;
  }

  /// Rundweg: Start liegt auf einem Kreis mit Umfang [geometricLength]; drei Wegpunkte verteilen sich leicht
  /// unregelmäßig darauf, damit die Runde nicht wie gezirkelt wirkt und keine Wege doppelt läuft.
  static List<GeoPoint> loop({
    required GeoPoint start,
    required double geometricLength,
    required double bearingDegrees,
    int seed = 0,
    int points = 3,
  }) {
    final random = math.Random(seed);
    final radius = geometricLength / (2 * math.pi);
    final center = Geo.destination(start, bearingDegrees, radius);
    // Winkel des Starts vom Mittelpunkt aus gesehen.
    final startAngle = (bearingDegrees + 180) % 360;
    final result = [start];
    for (var index = 1; index <= points; index++) {
      final jitter = (random.nextDouble() - 0.5) * (240 / (points + 1)) * 0.35;
      final angle = startAngle + index * 360 / (points + 1) + jitter;
      final scale = 0.9 + random.nextDouble() * 0.2;
      result.add(Geo.destination(center, angle % 360, radius * scale));
    }
    return result..add(start);
  }

  /// Zum festen Ziel: direkt, wenn die Luftlinie schon reicht, sonst über einen seitlichen Umweg-Punkt (Ellipse),
  /// sodass die Strecke etwa [targetMeters] lang wird. [side] wählt die Seite (+1 rechts, −1 links).
  static List<GeoPoint> toDestination({
    required GeoPoint start,
    required GeoPoint destination,
    required double geometricLength,
    double side = 1,
  }) {
    final direct = Geo.distance(start, destination);
    if (direct >= geometricLength * 0.97) return [start, destination];
    final half = geometricLength / 2;
    final offset = math.sqrt(math.max(0, half * half - direct * direct / 4));
    final bearing = Geo.bearing(start, destination);
    final via = Geo.destination(Geo.midpoint(start, destination), (bearing + 90 * side.sign + 360) % 360, offset);
    return [start, via, destination];
  }

  /// Offenes Ziel: Endpunkt in Richtung [bearingDegrees]; ein leicht versetzter Zwischenpunkt sorgt für Abwechslung
  /// zwischen den Varianten.
  static List<GeoPoint> direction({
    required GeoPoint start,
    required double geometricLength,
    required double bearingDegrees,
    int seed = 0,
  }) {
    final random = math.Random(seed);
    final end = Geo.destination(start, bearingDegrees, geometricLength);
    final lateral = (random.nextDouble() - 0.5) * 0.3 * geometricLength;
    final middle = Geo.destination(
      Geo.destination(start, bearingDegrees, geometricLength / 2),
      (bearingDegrees + 90) % 360,
      lateral,
    );
    return [start, middle, end];
  }

  /// Nächste Größe nach einer gerouteten Länge [routedMeters] mit Größe [geometricLength]: proportional nachführen,
  /// gedämpft, damit sich die Schätzung nicht aufschaukelt.
  static double rescale({required double geometricLength, required double routedMeters, required double targetMeters}) {
    if (routedMeters <= 0) return geometricLength;
    final ratio = (targetMeters / routedMeters).clamp(0.4, 2.5);
    return geometricLength * ratio;
  }

  /// Erste Größe für die Wunschdistanz.
  static double initialLength(RouteRequest request) => request.distanceMeters / roadFactor;
}

/// Punkt des Höhenprofils.
typedef ElevationSample = ({double kilometers, double elevation});

/// Kennzahlen einer Strecke aus Punkten mit Höhe.
final class RouteStats {
  const RouteStats({
    required this.distanceMeters,
    required this.ascentMeters,
    required this.descentMeters,
    this.minElevation,
    this.maxElevation,
  });

  final double distanceMeters;
  final double ascentMeters;
  final double descentMeters;
  final double? minElevation;
  final double? maxElevation;

  bool get hasElevation => minElevation != null;

  /// Schwelle gegen Rauschen der Höhendaten: Anstieg zählt erst nach 3 m in einer Richtung (Hysterese).
  static const noiseThreshold = 3.0;

  /// Glättungsfenster für Höhen aus dem Geländemodell (es misst auch Bäume, Gebäude und Brücken). Im Echttest
  /// (Berlin, 9 km) ergab die Rohsumme 184 hm, ohne Glättung 132 hm, mit 200 m Glättung realistische 61 hm.
  static const smoothingMeters = 200.0;

  /// Gleitender Mittelwert der Höhen über [window] Meter Strecke (O(n), Punkte ohne Höhe bleiben ohne).
  static List<double?> smoothedElevations(List<GeoPoint> points, {double window = smoothingMeters}) {
    final cumulative = Geo.cumulative(points);
    final result = List<double?>.filled(points.length, null);
    var left = 0;
    var right = 0;
    var sum = 0.0;
    var count = 0;
    for (var index = 0; index < points.length; index++) {
      if (points[index].elevation == null) continue;
      while (right < points.length && cumulative[right] - cumulative[index] <= window / 2) {
        if (points[right].elevation case final elevation?) {
          sum += elevation;
          count++;
        }
        right++;
      }
      while (cumulative[index] - cumulative[left] > window / 2) {
        if (points[left].elevation case final elevation?) {
          sum -= elevation;
          count--;
        }
        left++;
      }
      result[index] = count == 0 ? points[index].elevation : sum / count;
    }
    return result;
  }

  static RouteStats of(List<GeoPoint> points) {
    final distance = Geo.length(points);
    final raw = [for (final point in points) ?point.elevation];
    final elevations = raw.isEmpty ? raw : [for (final value in smoothedElevations(points)) ?value];
    if (raw.isEmpty) return RouteStats(distanceMeters: distance, ascentMeters: 0, descentMeters: 0);
    var ascent = 0.0;
    var descent = 0.0;
    var reference = elevations.first;
    for (final elevation in elevations.skip(1)) {
      final delta = elevation - reference;
      if (delta >= noiseThreshold) {
        ascent += delta;
        reference = elevation;
      } else if (delta <= -noiseThreshold) {
        descent -= delta;
        reference = elevation;
      }
    }
    return RouteStats(
      distanceMeters: distance,
      ascentMeters: ascent,
      descentMeters: descent,
      minElevation: raw.reduce(math.min),
      maxElevation: raw.reduce(math.max),
    );
  }

  /// Höhenprofil mit höchstens [samples] Punkten (km, m) – für das Diagramm.
  static List<ElevationSample> profile(List<GeoPoint> points, {int samples = 120}) {
    if (points.isEmpty || points.every((point) => point.elevation == null)) return const [];
    final cumulative = Geo.cumulative(points);
    final step = math.max(1, (points.length / samples).ceil());
    final result = <ElevationSample>[];
    for (var index = 0; index < points.length; index += step) {
      if (points[index].elevation case final elevation?) {
        result.add((kilometers: cumulative[index] / 1000, elevation: elevation));
      }
    }
    if (points.last.elevation case final elevation? when (points.length - 1) % step != 0) {
      result.add((kilometers: cumulative.last / 1000, elevation: elevation));
    }
    return result;
  }
}

/// Geschätzte Dauer: Distanz mit Steigungszuschlag.
abstract final class RouteDuration {
  /// Lockere Pace ohne bekannte Schwelle: 6:00 /km.
  static const defaultRunPace = 360.0;

  /// Laufen: 1 Höhenmeter kostet so viel wie 8 m in der Ebene (Faustregel nach Naismith/Scarf).
  static const runClimbEquivalent = 8.0;

  /// Rad in der Ebene (km/h) und Steigleistung (Höhenmeter je Stunde, VAM) für Freizeitfahrer.
  static const roadSpeed = 25.0, gravelSpeed = 19.0;

  /// Spazieren: 4,5 km/h, Anstieg 600 hm je Stunde (Wanderfaustregel).
  static const walkSpeed = 4.5, walkClimbRate = 600.0;
  static const roadClimbRate = 700.0, gravelClimbRate = 550.0;

  /// Lockere Pace aus der Schwellen-Pace (s/km): etwa 25 % langsamer.
  static double easyPace(int? thresholdPace) =>
      thresholdPace == null || thresholdPace <= 0 ? defaultRunPace : thresholdPace * 1.25;

  static Duration estimate({
    required RouteDiscipline discipline,
    required double distanceMeters,
    required double ascentMeters,
    int? runThresholdPace,
  }) {
    final seconds = switch (discipline) {
      RouteDiscipline.run => (distanceMeters + ascentMeters * runClimbEquivalent) / 1000 * easyPace(runThresholdPace),
      RouteDiscipline.roadBike => distanceMeters / 1000 / roadSpeed * 3600 + ascentMeters / roadClimbRate * 3600 * 0.5,
      RouteDiscipline.gravel =>
        distanceMeters / 1000 / gravelSpeed * 3600 + ascentMeters / gravelClimbRate * 3600 * 0.5,
      RouteDiscipline.walk => distanceMeters / 1000 / walkSpeed * 3600 + ascentMeters / walkClimbRate * 3600,
    };
    return Duration(seconds: seconds.round());
  }
}

/// Bewertung eines Vorschlags (kleiner ist besser): Abweichung von Distanz und Höhenmetern sowie doppelt gelaufene
/// Abschnitte („hin und zurück“).
abstract final class RouteScore {
  static double of({
    required RouteRequest request,
    required RouteVariant variant,
    required RouteStats stats,
    required double overlap,
  }) {
    final distanceError = (stats.distanceMeters - request.distanceMeters).abs() / request.distanceMeters;
    // Innerhalb der Toleranz zählt die Distanz kaum, außerhalb stark.
    final distancePart = distanceError <= RouteRequest.tolerance
        ? distanceError
        : RouteRequest.tolerance + (distanceError - RouteRequest.tolerance) * 4;
    double elevationPart = 0;
    if (request.elevationGainMeters case final target?) {
      elevationPart = (stats.ascentMeters - target).abs() / math.max(target, 50);
      if (variant == RouteVariant.hilly) elevationPart *= 2;
    } else if (variant == RouteVariant.hilly && stats.hasElevation) {
      // Ohne Vorgabe: mehr Höhenmeter je km sind beim Höhenmeter-Fokus besser.
      final perKm = stats.ascentMeters / math.max(1, stats.distanceMeters / 1000);
      elevationPart = -math.min(perKm, 40) / 100;
    }
    return distancePart + elevationPart * 0.5 + overlap * 0.6;
  }

  /// Anteil der Strecke, der auf schon befahrenen Abschnitten liegt (0…1), über ein Raster von etwa 25 m.
  static double overlap(List<GeoPoint> points) {
    if (points.length < 2) return 0;
    final cumulative = Geo.cumulative(points);
    final total = cumulative.last;
    if (total <= 0) return 0;
    const cell = 25.0;
    final origin = points.first;
    final cosLat = math.cos(origin.latitude * math.pi / 180);
    (int, int) key(GeoPoint point) => (
      ((point.longitude - origin.longitude) * math.pi / 180 * Geo.earthRadius * cosLat / cell).floor(),
      ((point.latitude - origin.latitude) * math.pi / 180 * Geo.earthRadius / cell).floor(),
    );
    // Wann (Streckenmeter) jede Zelle zuerst erreicht wurde; erneuter Besuch erst nach 150 m zählt als Doppelung.
    final firstSeen = <(int, int), double>{};
    var repeated = 0.0;
    var samples = 0;
    var next = 0.0;
    for (var index = 0; index < points.length; index++) {
      if (cumulative[index] < next) continue;
      next = cumulative[index] + cell;
      samples++;
      final id = key(points[index]);
      final seen = firstSeen[id];
      if (seen == null) {
        firstSeen[id] = cumulative[index];
      } else if (cumulative[index] - seen > 150 && cumulative[index] < total - 150) {
        repeated++;
      }
    }
    return samples == 0 ? 0 : repeated / samples;
  }
}

/// Anzeige von Routenwerten auf Deutsch.
abstract final class RouteFormat {
  /// „850 m“, „10,2 km“, „124 km“.
  static String distance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final kilometers = meters / 1000;
    if (kilometers >= 100) return '${kilometers.round()} km';
    return '${kilometers.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  /// „48 min“, „1:05 h“.
  static String duration(Duration duration) {
    final minutes = (duration.inSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h';
  }

  /// „180 hm“.
  static String elevation(double meters) => '${meters.round()} hm';
}

/// Wunschdistanz für eine Einheit des Ausdauerplans: geplante Strecke, sonst Dauer × lockeres Tempo (Laufen) bzw.
/// Radtempo. Schwimmen und Ruhetage haben keine Route.
abstract final class RouteForWorkout {
  static ({RouteDiscipline discipline, double kilometers})? suggest({
    required bool isBike,
    required bool isRun,
    required int minutes,
    int? meters,
    int? runThresholdPace,
  }) {
    if (!isBike && !isRun) return null;
    final discipline = isBike ? RouteDiscipline.roadBike : RouteDiscipline.run;
    double kilometers;
    if (meters case final meters? when meters > 0) {
      kilometers = meters / 1000;
    } else if (minutes > 0) {
      kilometers = isBike
          ? minutes / 60 * RouteDuration.roadSpeed
          : minutes * 60 / RouteDuration.easyPace(runThresholdPace);
    } else {
      return null;
    }
    // Laufen auf halbe, Rad auf ganze Kilometer; innerhalb der Grenzen des Planers.
    kilometers = isBike ? kilometers.roundToDouble() : (kilometers * 2).round() / 2;
    final max = RouteRequest.maxDistance(discipline) / 1000;
    return (discipline: discipline, kilometers: kilometers.clamp(1.0, max));
  }
}

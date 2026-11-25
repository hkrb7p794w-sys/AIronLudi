import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../endurance/endurance_plan.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';
import 'geo.dart';
import 'planned_route.dart';
import 'route_planning.dart';

/// Wofür die Route gedacht ist: aus der geplanten Einheit abgeleitet (Distanz, Gelände, Höhenmeter) mit kurzer
/// Begründung. Die Regeln entscheiden, nicht die KI.
final class RunRouteBrief {
  const RunRouteBrief({required this.kilometers, required this.preferences, required this.reason, this.flat = false});

  final double kilometers;
  final Set<RoutePreference> preferences;
  final String reason;

  /// Möglichst flach (Tempo- und Intervallabschnitte, Regeneration).
  final bool flat;

  /// Höhenmeter-Vorgabe für flache Strecken (etwa 4 hm je km), sonst `null`.
  double? get elevationGain => flat ? (kilometers * 4).roundToDouble() : null;

  RouteRequest request(GeoPoint start, {double? bearingDegrees}) => RouteRequest(
    discipline: RouteDiscipline.run,
    shape: RouteShape.loop,
    start: start,
    bearingDegrees: bearingDegrees,
    distanceMeters: kilometers * 1000,
    elevationGainMeters: elevationGain,
    preferences: preferences,
  );
}

/// Regeln: welche Strecke zu welcher Laufeinheit passt.
abstract final class RunRouteBriefs {
  /// Einheit des Ausdauerplans; `null` für Ruhetage, Wettkämpfe und andere Sportarten.
  static RunRouteBrief? forWorkout(
    EnduranceWorkout workout, {
    Set<RoutePreference> preferences = const {},
    int? runThresholdPace,
  }) {
    if (workout.sport != EnduranceSport.run) return null;
    final kind = switch (workout.type) {
      EnduranceWorkoutType.rest || EnduranceWorkoutType.race => null,
      EnduranceWorkoutType.recovery => _Kind.recovery,
      EnduranceWorkoutType.endurance => _Kind.easy,
      EnduranceWorkoutType.long => _Kind.long,
      EnduranceWorkoutType.tempo || EnduranceWorkoutType.threshold || EnduranceWorkoutType.vo2max => _Kind.fast,
    };
    if (kind == null) return null;
    return _brief(
      kind,
      minutes: workout.minutes,
      meters: workout.meters,
      preferences: preferences,
      runThresholdPace: runThresholdPace,
    );
  }

  /// Lauf aus dem Wochenplan (persönlicher Modus).
  static RunRouteBrief? forSession(
    SessionSlot slot, {
    required int minutes,
    Set<RoutePreference> preferences = const {},
    int? runThresholdPace,
  }) {
    if (slot.sport != TrainingSport.run) return null;
    final kind = switch (slot.intensity) {
      SessionIntensity.easy => _Kind.easy,
      SessionIntensity.hard => _Kind.fast,
      SessionIntensity.long => _Kind.long,
    };
    return _brief(kind, minutes: minutes, preferences: preferences, runThresholdPace: runThresholdPace);
  }

  static RunRouteBrief? _brief(
    _Kind kind, {
    required int minutes,
    int? meters,
    required Set<RoutePreference> preferences,
    int? runThresholdPace,
  }) {
    final base = RouteForWorkout.suggest(
      isBike: false,
      isRun: true,
      minutes: minutes,
      meters: meters,
      runThresholdPace: runThresholdPace,
    );
    if (base == null) return null;
    // Nur Wegarten fürs Laufen (keine Hundewiese).
    final chosen = {
      for (final preference in preferences)
        if (RoutePreference.available(RouteDiscipline.run).contains(preference)) preference,
    };
    return switch (kind) {
      _Kind.recovery => RunRouteBrief(
        kilometers: base.kilometers,
        // Weicher Untergrund schont, außer es ist ausdrücklich Asphalt gewünscht.
        preferences: chosen.contains(RoutePreference.paved) ? chosen : {...chosen, RoutePreference.nature},
        flat: true,
        reason: 'Regeneration: flach und möglichst weicher Untergrund.',
      ),
      _Kind.easy => RunRouteBrief(
        kilometers: base.kilometers,
        preferences: chosen,
        reason: 'Lockerer Lauf: eine Runde nach deinen Vorlieben.',
      ),
      _Kind.long => RunRouteBrief(
        kilometers: base.kilometers,
        preferences: chosen,
        reason: 'Lange Einheit: eine große Runde ohne Wiederholungen.',
      ),
      _Kind.fast => RunRouteBrief(
        kilometers: base.kilometers,
        preferences: chosen,
        flat: true,
        reason: 'Tempo und Intervalle: flach und gleichmäßig, damit die Abschnitte vergleichbar bleiben.',
      ),
    };
  }
}

enum _Kind { recovery, easy, long, fast }

/// Spur einer früheren Route (für Abwechslung): Tag und vereinfachte Linie.
final class RouteFootprint {
  const RouteFootprint({required this.day, required this.points});

  /// Höchstzahl gespeicherter Punkte je Spur.
  static const maxPoints = 120;

  final CalendarDay day;
  final List<GeoPoint> points;

  factory RouteFootprint.of(List<GeoPoint> points, CalendarDay day) => RouteFootprint(
    day: day,
    points: [for (final point in Geo.thin(points, maxPoints)) GeoPoint(point.latitude, point.longitude)],
  );

  Map<String, Object?> toJson() => {
    'day': day.iso,
    'points': [for (final point in points) point.toJson()],
  };

  static RouteFootprint? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawDay = json['day'];
    final day = rawDay is String ? CalendarDay.tryParse(rawDay) : null;
    final raw = json['points'];
    if (day == null || raw is! List) return null;
    final points = [for (final item in raw) ?GeoPoint.fromJson(item)];
    return points.length < 2 ? null : RouteFootprint(day: day, points: points);
  }
}

/// Abwechslung: Richtung der Runde und Überschneidung mit Strecken der letzten Wochen.
abstract final class RouteVariety {
  /// So weit zurück zählen frühere Strecken.
  static const window = 28;

  /// Ab dieser Überschneidung gilt eine Strecke als „dieselbe“.
  static const sameRoute = 0.6;

  /// Rasterzellen (etwa 110 × 70 m) entlang der Linie, Abschnitte alle 50 m abgetastet.
  static Set<(int, int)> cells(List<GeoPoint> points) {
    final result = <(int, int)>{};
    void add(GeoPoint point) => result.add(((point.latitude * 1000).floor(), (point.longitude * 1000).floor()));
    for (var index = 0; index < points.length; index++) {
      add(points[index]);
      if (index == 0) continue;
      final a = points[index - 1];
      final b = points[index];
      final steps = (Geo.distance(a, b) / 50).floor();
      for (var step = 1; step < steps; step++) {
        final t = step / steps;
        add(GeoPoint(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t));
      }
    }
    return result;
  }

  /// Spuren im Fenster vor [day] (und bis zu einer Woche danach, schon geplante).
  static List<RouteFootprint> recent(Iterable<RouteFootprint> footprints, CalendarDay day) => [
    for (final footprint in footprints)
      if (footprint.day.daysUntil(day) <= window && day.daysUntil(footprint.day) <= 7) footprint,
  ];

  /// Größter Anteil der Linie [points], der schon in einer der [footprints] lag (0…1).
  static double overlap(List<GeoPoint> points, Iterable<RouteFootprint> footprints) {
    final own = cells(points);
    if (own.isEmpty) return 0;
    var best = 0.0;
    for (final footprint in footprints) {
      final shared = own.intersection(cells(footprint.points)).length / own.length;
      best = math.max(best, shared);
    }
    return best;
  }

  /// Richtung (Grad) der Runde: die am wenigsten genutzte von acht Himmelsrichtungen rund um [start]; bei
  /// Gleichstand entscheidet [seed] (so wechselt sie auch ohne Verlauf).
  static double bearing(GeoPoint start, Iterable<RouteFootprint> footprints, {required int seed}) {
    final used = List.filled(8, 0.0);
    for (final footprint in footprints) {
      // Nur Strecken in der Nähe zählen (anderer Startort: andere Gegend).
      if (Geo.distance(footprint.points.first, start) > 3000) continue;
      final center = _centroid(footprint.points);
      if (Geo.distance(start, center) < 150) continue;
      final sector = ((Geo.bearing(start, center) / 45).round()) % 8;
      used[sector] += 1;
      // Nachbarrichtungen zählen halb (ähnliches Gebiet).
      used[(sector + 1) % 8] += 0.5;
      used[(sector + 7) % 8] += 0.5;
    }
    final least = used.reduce(math.min);
    final candidates = [
      for (var sector = 0; sector < 8; sector++)
        if (used[sector] == least) sector,
    ];
    return candidates[seed.abs() % candidates.length] * 45.0;
  }

  static GeoPoint _centroid(List<GeoPoint> points) => GeoPoint(
    points.fold(0.0, (sum, point) => sum + point.latitude) / points.length,
    points.fold(0.0, (sum, point) => sum + point.longitude) / points.length,
  );

  /// Vorschlag mit der geringsten Überschneidung; bei Gleichstand der erste (beste Bewertung des Planers).
  static PlannedRoute? pick(List<PlannedRoute> candidates, Iterable<RouteFootprint> footprints) {
    if (candidates.isEmpty) return null;
    final list = footprints.toList();
    PlannedRoute? best;
    var bestOverlap = double.infinity;
    for (final route in candidates) {
      final value = overlap(route.points, list);
      // Kleine Unterschiede (unter 5 Prozentpunkten) entscheiden nicht.
      if (value < bestOverlap - 0.05) {
        best = route;
        bestOverlap = value;
      }
    }
    return best;
  }
}

/// Stand eines Vorschlags je Einheit.
enum RunSuggestionStatus implements RawEnum {
  pending,
  accepted,
  declined;

  @override
  String get rawValue => name;
}

/// Vorschlag für eine Einheit: offene Route (noch nicht in der Ablage) bzw. angenommen oder abgelehnt.
final class RunSuggestionEntry {
  RunSuggestionEntry({
    required this.unitID,
    required this.day,
    this.status = RunSuggestionStatus.pending,
    this.route,
    this.declines = 0,
  });

  final String unitID;
  final CalendarDay day;
  RunSuggestionStatus status;

  /// Offener Vorschlag (bei „angenommen“ liegt die Route in der Ablage).
  PlannedRoute? route;

  /// Wie oft abgelehnt (für den nächsten Würfelwurf).
  int declines;

  Map<String, Object?> toJson() => {
    'unitID': unitID,
    'day': day.iso,
    'status': status.rawValue,
    'route': ?route?.toJson(),
    if (declines > 0) 'declines': declines,
  };

  static RunSuggestionEntry? fromJson(Object? json, {required String username}) {
    if (json is! Map) return null;
    final unitID = json['unitID'];
    final rawDay = json['day'];
    final day = rawDay is String ? CalendarDay.tryParse(rawDay) : null;
    if (unitID is! String || day == null) return null;
    final declines = json['declines'];
    return RunSuggestionEntry(
      unitID: unitID,
      day: day,
      status: enumFromRaw(RunSuggestionStatus.values, json['status']) ?? RunSuggestionStatus.pending,
      route: PlannedRoute.fromJson(json['route'], username: username),
      declines: declines is num ? declines.toInt() : 0,
    );
  }
}

/// Routenvorschläge für Läufe (Schlüssel `coach.runRouteSuggestions`, je Benutzer): Einstellungen, Vorschläge je
/// Einheit und Spuren abgelehnter Strecken.
final class RunRouteSuggestions {
  RunRouteSuggestions({
    required this.username,
    this.enabled = true,
    Set<RoutePreference>? preferences,
    this.startFavoriteID,
    Map<String, RunSuggestionEntry>? entries,
    List<RouteFootprint>? declined,
  }) : preferences = preferences ?? {},
       entries = entries ?? {},
       declined = declined ?? [];

  final String username;

  /// Für geplante Läufe automatisch eine Route vorschlagen.
  bool enabled;

  /// Bevorzugtes Gelände (leer: ausgewogen).
  Set<RoutePreference> preferences;

  /// Start der Runden: Favorit (sonst „Zuhause“, sonst der eigene Standort).
  String? startFavoriteID;

  final Map<String, RunSuggestionEntry> entries;

  /// Spuren abgelehnter Vorschläge (werden nicht wieder vorgeschlagen).
  final List<RouteFootprint> declined;

  static const maxDeclined = 40;

  /// Einträge und Spuren, die älter als das Fenster sind, entfernen.
  void prune(CalendarDay today) {
    entries.removeWhere((_, entry) => entry.day.daysUntil(today) > RouteVariety.window);
    declined.removeWhere((footprint) => footprint.day.daysUntil(today) > RouteVariety.window);
    if (declined.length > maxDeclined) declined.removeRange(0, declined.length - maxDeclined);
  }

  Map<String, Object?> toJson() => {
    'username': username,
    'enabled': enabled,
    'preferences': [
      for (final preference in RoutePreference.values)
        if (preferences.contains(preference)) preference.rawValue,
    ],
    'startFavoriteID': ?startFavoriteID,
    'entries': [for (final entry in entries.values) entry.toJson()],
    'declined': [for (final footprint in declined) footprint.toJson()],
  };

  /// Gehört der Stand einem anderen Benutzer, `null`.
  static RunRouteSuggestions? fromJson(Object? json, {required String username}) {
    if (json is! Map || json['username'] != username) return null;
    final rawEntries = json['entries'];
    final rawDeclined = json['declined'];
    final favorite = json['startFavoriteID'];
    return RunRouteSuggestions(
      username: username,
      enabled: json['enabled'] != false,
      preferences: {...enumListFromRaw(RoutePreference.values, json['preferences'])},
      startFavoriteID: favorite is String ? favorite : null,
      entries: {
        for (final entry in [
          if (rawEntries is List)
            for (final item in rawEntries) ?RunSuggestionEntry.fromJson(item, username: username),
        ])
          entry.unitID: entry,
      },
      declined: [
        if (rawDeclined is List)
          for (final item in rawDeclined) ?RouteFootprint.fromJson(item),
      ],
    );
  }
}

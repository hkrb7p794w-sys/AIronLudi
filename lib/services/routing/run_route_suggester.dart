import 'package:coach_core/coach_core.dart';

import 'location_source.dart';
import 'route_stores.dart';

/// Geplante Laufeinheit, für die eine Route vorgeschlagen wird.
final class RunRouteUnit {
  const RunRouteUnit({required this.unitID, required this.day, required this.title, required this.brief});

  final String unitID;
  final CalendarDay day;
  final String title;
  final RunRouteBrief brief;
}

/// Kein Startpunkt bekannt (kein Favorit, kein Standort).
final class RunRouteNoStart implements Exception {
  const RunRouteNoStart(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Schlägt zu einer geplanten Laufeinheit eine Runde vor: Gelände und Distanz aus der Einheit
/// ([RunRouteBriefs]), Richtung und Auswahl so, dass sie sich von den Strecken der letzten Wochen unterscheidet
/// ([RouteVariety]). Der Vorschlag bleibt gespeichert, bis er angenommen oder abgelehnt wird.
final class RunRouteSuggester {
  RunRouteSuggester({
    required this.store,
    required this.backend,
    required this.location,
    this.features,
    this.roundTrips,
    this.runThresholdPace,
  });

  final RouteStore store;
  final RoutingBackend backend;
  final LocationSource location;
  final RouteFeatureSource? features;
  final RoundTripSource? roundTrips;
  final int? runThresholdPace;

  /// Offener Vorschlag der Einheit, sonst `null`.
  PlannedRoute? pending(String unitID) {
    final entry = store.runSuggestions.entries[unitID];
    return entry?.status == RunSuggestionStatus.pending ? entry?.route : null;
  }

  RunSuggestionStatus? status(String unitID) => store.runSuggestions.entries[unitID]?.status;

  /// Start der Runden: gewählter Favorit, sonst „Zuhause“, sonst der eigene Standort.
  Future<GeoPoint> start() async {
    final favorites = store.favorites;
    final chosen = store.runSuggestions.startFavoriteID;
    for (final place in favorites) {
      if (place.id == chosen) return place.point;
    }
    for (final place in favorites) {
      if (place.name.trim().toLowerCase() == 'zuhause') return place.point;
    }
    try {
      // Höchstens 20 s (Ortung hängt sonst z. B. ohne GPS-Empfang).
      return await location.current().timeout(const Duration(seconds: 20));
    } on Object {
      // Ohne Freigabe, Ortung aus oder kein Gerät (Tests): Hinweis statt Fehler.
      throw const RunRouteNoStart(
        'Kein Startpunkt: Speichere einen Favoriten (z. B. „Zuhause“) oder erlaube den Standort.',
      );
    }
  }

  /// Spuren der letzten Wochen: gespeicherte und gelaufene Routen sowie abgelehnte Vorschläge.
  List<RouteFootprint> footprints(CalendarDay day) => RouteVariety.recent([
    for (final route in [...store.openRoutes, ...store.archive])
      if (route.discipline == RouteDiscipline.run || route.discipline == RouteDiscipline.walk)
        RouteFootprint.of(
          route.points,
          route.plannedDay ??
              (route.completedAt == null
                  ? CalendarDay.fromDate(route.createdAt.toLocal())
                  : CalendarDay.fromDate(route.completedAt!.toLocal())),
        ),
    ...store.runSuggestions.declined,
  ], day);

  /// Gleichbleibender Startwert je Einheit (nicht `String.hashCode`, das wechselt zwischen Starts).
  static int seedFor(String unitID, int declines) =>
      unitID.codeUnits.fold(17, (hash, unit) => (hash * 31 + unit) & 0x3fffffff) + declines * 7919;

  /// Vorschlag holen (gespeichert) oder neu planen. Wirft [RunRouteNoStart], [NoRouteFound] bzw.
  /// [RoutingUnavailable].
  Future<PlannedRoute> suggest(RunRouteUnit unit) async {
    if (pending(unit.unitID) case final route?) return route;
    final declines = store.runSuggestions.entries[unit.unitID]?.declines ?? 0;
    final start = await this.start();
    final recent = footprints(unit.day);
    final seed = seedFor(unit.unitID, declines);
    final bearing = RouteVariety.bearing(start, recent, seed: seed);
    final routes = await RoutePlanner(backend, features: features, roundTrips: roundTrips).generate(
      unit.brief.request(start, bearingDegrees: bearing),
      username: store.username,
      seed: seed,
      runThresholdPace: runThresholdPace,
    );
    final picked = RouteVariety.pick(routes, recent)!..name = unit.title;
    await store.updateRunSuggestions(
      (state) => state.entries[unit.unitID] = RunSuggestionEntry(
        unitID: unit.unitID,
        day: unit.day,
        route: picked,
        declines: declines,
      ),
    );
    return picked;
  }

  /// Annehmen: Route der Einheit zuordnen und speichern.
  Future<PlannedRoute?> accept(RunRouteUnit unit) async {
    final route = pending(unit.unitID);
    if (route == null) return null;
    route
      ..plannedDay = unit.day
      ..slotID = unit.unitID
      ..slotTitle = unit.title;
    await store.save(route);
    await store.updateRunSuggestions((state) {
      final entry = state.entries[unit.unitID];
      if (entry == null) return;
      entry
        ..status = RunSuggestionStatus.accepted
        ..route = null;
    });
    return route;
  }

  /// Ablehnen: Strecke merken (wird nicht wieder vorgeschlagen); [another]: gleich einen neuen Vorschlag, sonst für
  /// diese Einheit keine Route mehr.
  Future<void> decline(RunRouteUnit unit, {bool another = true}) => store.updateRunSuggestions((state) {
    final entry = state.entries[unit.unitID] ?? RunSuggestionEntry(unitID: unit.unitID, day: unit.day);
    if (entry.route case final route?) state.declined.add(RouteFootprint.of(route.points, unit.day));
    entry
      ..route = null
      ..declines += 1
      ..status = another ? RunSuggestionStatus.pending : RunSuggestionStatus.declined;
    state.entries[unit.unitID] = entry;
  });

  /// Für diese Einheit doch wieder vorschlagen.
  Future<void> reopen(RunRouteUnit unit) => store.updateRunSuggestions((state) {
    state.entries[unit.unitID]?.status = RunSuggestionStatus.pending;
  });
}

import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../services/routing/route_stores.dart';
import '../../services/routing/routing_providers.dart';
import '../endurance/endurance_controller.dart';

/// Was ein Tipp nach „Start oder Ziel ändern“ bzw. ein langes Drücken setzt.
enum PinTarget { start, destination }

/// Zustand und Abläufe des Routenplaners (Vorgaben, Punkte, Vorschläge). Lebt im Container des Benutzers und überdauert
/// das Verlassen des Planers: Vorschläge gehen nicht verloren, eine laufende Planung rechnet weiter. Vorschläge
/// erscheinen einzeln, sobald sie fertig sind.
final class RoutePlannerController extends ChangeNotifier {
  RoutePlannerController({
    required this.store,
    required this._backend,
    required this._features,
    required this._runThresholdPace,
  }) {
    final settings = store.settings;
    discipline = settings.discipline;
    shape = settings.shape;
    kilometers = settings.distanceKilometers.clamp(minKm, maxKm).toDouble();
    preferences = {...settings.preferences};
    if (settings.elevationGain case final gain?) {
      wantsElevation = true;
      elevation = gain;
    }
  }

  final RouteStore store;
  final RoutingBackend Function() _backend;
  final RouteFeatureSource? Function() _features;
  final int? Function() _runThresholdPace;

  // Vorgaben
  late RouteDiscipline discipline;
  late RouteShape shape;
  late double kilometers;
  bool wantsElevation = false;
  int elevation = 150;
  CompassDirection direction = CompassDirection.north;
  Set<RoutePreference> preferences = {};

  // Punkte
  PinTarget pin = PinTarget.start;

  /// Nach „Startpunkt ändern“: der nächste Tipp setzt den Punkt, auch wenn Vorschläge vorliegen.
  bool editingPins = false;
  GeoPoint? start;
  bool startFromLocation = false;
  GeoPoint? destination;

  /// Adressen aus der Adresszeile (`null`: Punkt kam von Karte oder Standort).
  String? startAddress;
  String? destinationAddress;

  /// Eigener Standort auf der Karte (blauer Punkt); setzt keinen Start.
  GeoPoint? myLocation;

  /// Einheit des Ausdauerplans, für die geplant wird (Route wird ihr beim Speichern zugeordnet).
  ({CalendarDay day, String slotID, String title})? forSlot;

  // Planung
  bool planning = false;
  String? progress;
  String? problem;
  int seed = DateTime.now().millisecondsSinceEpoch % 100000;
  List<PlannedRoute> routes = const [];
  int selected = 0;
  final Set<String> saved = {};

  /// Zählt bei jedem neuen Satz Vorschläge hoch (die Karte richtet sich dann neu aus).
  int fitGeneration = 0;
  int _run = 0;

  double get minKm => 1;
  double get maxKm => RouteRequest.maxDistance(discipline) / 1000;
  int get maxElevation => switch (discipline) {
    RouteDiscipline.roadBike || RouteDiscipline.gravel => 4000,
    RouteDiscipline.run => 2000,
    RouteDiscipline.walk => 1000,
  };

  PlannedRoute? get current => routes.isEmpty ? null : routes[selected.clamp(0, routes.length - 1)];

  /// Vorschläge liegen vor: Antippen verschiebt keine Punkte (Ansichtsmodus).
  bool get pinsLocked => routes.isNotEmpty && !editingPins;

  RouteRequest? get request {
    final start = this.start;
    if (start == null) return null;
    return RouteRequest(
      discipline: discipline,
      shape: shape,
      start: start,
      destination: shape == RouteShape.toDestination ? destination : null,
      bearingDegrees: shape == RouteShape.direction ? direction.degrees : null,
      distanceMeters: kilometers * 1000,
      elevationGainMeters: wantsElevation ? elevation.toDouble() : null,
      preferences: preferences,
    );
  }

  /// Ändern und neu zeichnen.
  void update(void Function(RoutePlannerController planner) change) {
    change(this);
    notifyListeners();
  }

  /// Vorschläge verwerfen (Vorgaben geändert). Eine laufende Planung wird nicht mehr übernommen.
  void clearResults() {
    routes = const [];
    selected = 0;
    problem = null;
    if (planning) {
      _run++;
      planning = false;
    }
  }

  void setDiscipline(RouteDiscipline value) => update((planner) {
    discipline = value;
    kilometers = kilometers.clamp(minKm, maxKm).toDouble();
    elevation = math.min(elevation, maxElevation);
    clearResults();
  });

  void setShape(RouteShape value) => update((planner) {
    shape = value;
    pin = shape == RouteShape.toDestination && start != null && destination == null
        ? PinTarget.destination
        : PinTarget.start;
    clearResults();
  });

  void useLocation(GeoPoint point) => update((planner) {
    start = point;
    startFromLocation = true;
    startAddress = null;
    if (shape == RouteShape.toDestination && destination == null) pin = PinTarget.destination;
    clearResults();
  });

  void placePin(GeoPoint point) => update((planner) {
    editingPins = false;
    if (shape == RouteShape.toDestination && pin == PinTarget.destination) {
      destination = point;
      destinationAddress = null;
      pin = PinTarget.start;
    } else {
      start = point;
      startFromLocation = false;
      startAddress = null;
      if (shape == RouteShape.toDestination && destination == null) pin = PinTarget.destination;
    }
    clearResults();
  });

  /// Adresse gewählt: ausdrückliche Eingabe, setzt den Punkt auch über vorhandenen Vorschlägen.
  void selectAddress(Place place, {required bool isDestination}) => update((planner) {
    if (isDestination) {
      destination = place.point;
      destinationAddress = place.label;
    } else {
      start = place.point;
      startAddress = place.label;
      startFromLocation = false;
      if (shape == RouteShape.toDestination && destination == null) pin = PinTarget.destination;
    }
    editingPins = false;
    clearResults();
  });

  void changeStart() => update((planner) {
    editingPins = true;
    pin = PinTarget.start;
  });

  void reset() => update((planner) {
    start = null;
    destination = null;
    startFromLocation = false;
    startAddress = null;
    destinationAddress = null;
    editingPins = false;
    pin = PinTarget.start;
    forSlot = null;
    clearResults();
  });

  void select(int index) => update((planner) => selected = index.clamp(0, math.max(0, routes.length - 1)));

  /// Für eine Einheit des Ausdauerplans planen: Disziplin und Distanz vorbelegen, Vorschläge verwerfen.
  void prepareForSlot({
    required RouteDiscipline discipline,
    required double kilometers,
    required CalendarDay day,
    required String slotID,
    required String title,
  }) => update((planner) {
    this.discipline = discipline;
    this.kilometers = kilometers.clamp(minKm, maxKm).toDouble();
    forSlot = (day: day, slotID: slotID, title: title);
    clearResults();
  });

  /// Plant; Vorschläge kommen einzeln dazu. Gibt `false` zurück, wenn die Vorgaben unvollständig sind ([problem]).
  Future<bool> plan({bool reroll = false}) async {
    final request = this.request;
    if (request == null) {
      update((planner) => problem = 'Bitte zuerst einen Startpunkt wählen: Adresse, Standort oder Pin auf der Karte.');
      return false;
    }
    if (request.problem case final text?) {
      update((planner) => problem = text);
      return false;
    }
    if (reroll) seed++;
    final run = ++_run;
    update((planner) {
      planning = true;
      progress = 'Wegenetz wird abgefragt …';
      problem = null;
      routes = const [];
      selected = 0;
    });
    unawaited(
      store.updateSettings(
        (settings) => settings
          ..discipline = discipline
          ..shape = shape
          ..distanceKilometers = kilometers
          ..elevationGain = wantsElevation ? elevation : null
          ..preferences = {...preferences},
      ),
    );
    try {
      final result = await RoutePlanner(_backend(), features: _features()).generate(
        request,
        username: store.username,
        seed: seed,
        runThresholdPace: _runThresholdPace(),
        onProgress: (message) {
          if (run == _run) update((planner) => progress = message);
        },
        onRoute: (route) {
          if (run != _run) return;
          _attachSlot(route);
          update((planner) {
            routes = [...routes, route];
            editingPins = false;
            if (routes.length == 1) fitGeneration++;
          });
        },
        isCancelled: () => run != _run,
      );
      if (run != _run) return true;
      // Vorschläge, die schon einzeln kamen, nicht doppelt übernehmen.
      final known = {for (final route in routes) route.id};
      final missing = [
        for (final route in result)
          if (!known.contains(route.id)) route,
      ];
      for (final route in missing) {
        _attachSlot(route);
      }
      if (missing.isNotEmpty) update((planner) => routes = [...routes, ...missing]);
    } on NoRouteFound catch (error) {
      if (run == _run) update((planner) => problem = error.message);
    } on RoutingUnavailable catch (error) {
      if (run == _run) {
        update(
          (planner) => problem =
              '${error.message} Die öffentlichen Routing-Server sind gerade nicht erreichbar – bitte gleich noch '
              'einmal versuchen.',
        );
      }
    } on ArgumentError catch (error) {
      if (run == _run) update((planner) => problem = '${error.message}');
    } finally {
      if (run == _run) update((planner) => planning = false);
    }
    return true;
  }

  /// Vorschläge für eine Einheit tragen deren Tag und Titel (wirksam beim Speichern).
  void _attachSlot(PlannedRoute route) {
    if (forSlot case final slot?) {
      route
        ..plannedDay = slot.day
        ..slotID = slot.slotID
        ..slotTitle = slot.title;
    }
  }

  Future<void> save(PlannedRoute route) async {
    await store.save(route);
    update((planner) => saved.add(route.id));
  }

  void markSaved(PlannedRoute route) => update((planner) => saved.add(route.id));
}

final routePlannerControllerProvider = ChangeNotifierProvider<RoutePlannerController>(
  (ref) => RoutePlannerController(
    // Nur lesen: Beobachten würde den Planer bei jedem Speichern neu anlegen (Vorschläge weg).
    store: ref.read(routeStoreProvider),
    backend: () => ref.read(routingBackendProvider),
    features: () => ref.read(routeFeatureSourceProvider),
    runThresholdPace: () => ref.read(enduranceControllerProvider).plan?.request.thresholds.runThresholdPace,
  ),
);

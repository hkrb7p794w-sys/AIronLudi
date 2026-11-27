// Routenplaner im Reiter Training: Einstieg, Standort als Start, Vorschläge, Speichern, Übernahme für heute, Gebiete.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aironludi/features/routes/address_field.dart';
import 'package:aironludi/features/routes/exploration_screen.dart';
import 'package:aironludi/features/routes/follow_route_screen.dart';
import 'package:aironludi/features/routes/my_location.dart';
import 'package:aironludi/features/routes/route_detail_screen.dart';
import 'package:aironludi/features/routes/route_draw_screen.dart';
import 'package:aironludi/features/routes/route_parts.dart';
import 'package:aironludi/features/routes/route_planner_controller.dart';
import 'package:aironludi/features/routes/route_planner_screen.dart';
import 'package:aironludi/features/routes/routes_screen.dart';
import 'package:aironludi/platform/notifications.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/services/routing/garmin_course_service.dart';
import 'package:aironludi/services/routing/location_source.dart';
import 'package:aironludi/services/routing/route_weather_service.dart';
import 'package:aironludi/services/routing/routing_providers.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

const home = GeoPoint(52.52, 13.405);

final class FakeLocation implements LocationSource {
  /// Positionen für „Route folgen“ (vom Test gesteuert).
  final positions = StreamController<GeoPoint>.broadcast();

  @override
  Future<GeoPoint> current() async => home;

  /// Zuletzt angefragt: Ortung auch bei gesperrtem Bildschirm.
  bool? background;

  @override
  Stream<GeoPoint> watch({bool background = false}) {
    this.background = background;
    return positions.stream;
  }
}

/// Router ohne Netz: läuft die Wegpunkte ab (Umwegfaktor 1,3) und liefert Höhen.
final class FakeRouting implements RoutingBackend {
  int calls = 0;

  /// Kein Weg bekannt (z. B. Brücke nach Baustelle in OSM gesperrt).
  bool noRoute = false;

  /// Wegpunkte je Anfrage.
  final List<List<GeoPoint>> waypointLists = [];
  final List<Set<RoutePreference>> preferences = [];
  final List<RouteDiscipline> disciplines = [];

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
    Set<RoutePreference> preferences = const {},
  }) async {
    calls++;
    waypointLists.add(waypoints);
    this.preferences.add(preferences);
    disciplines.add(discipline);
    if (noRoute) throw const NoRouteFound('Kein Weg');
    final points = <GeoPoint>[];
    for (var index = 1; index < waypoints.length; index++) {
      final a = waypoints[index - 1];
      final b = waypoints[index];
      for (var step = 0; step < 10; step++) {
        final t = step / 10;
        points.add(
          GeoPoint(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
            elevation: 40 + step * 2.0,
          ),
        );
      }
    }
    points.add(waypoints.last.withElevation(40));
    return RoutedPath(points: points, distanceMeters: Geo.length(points), engine: 'Test');
  }

  @override
  Future<List<double?>> elevations(List<GeoPoint> points) async => [for (final _ in points) 50];
}

/// Adresssuche ohne Netz: findet „Hauptstraße“ und „Hafen“ in der Nähe.
final class FakePlaces implements PlaceSearch {
  final List<String> queries = [];

  @override
  Future<List<Place>> search(String query, {GeoPoint? near, bool typing = false}) async {
    queries.add(query);
    if (query.contains('Hafen')) {
      return [Place(title: 'Hafen', detail: '10117 Berlin', point: Geo.destination(home, 90, 3000))];
    }
    return [
      Place(title: 'Hauptstraße 5', detail: '10827 Berlin', point: Geo.destination(home, 200, 1500)),
      Place(title: 'Hauptstraße 50', detail: '10827 Berlin', point: Geo.destination(home, 210, 1800)),
    ];
  }
}

/// Overpass ohne Netz: Uferwege rund um den Start.
final class FakeFeatures implements RouteFeatureSource {
  int requests = 0;

  @override
  Future<List<GeoPoint>> attractors(
    GeoPoint center,
    double radiusMeters,
    Set<RoutePreference> preferences, {
    RouteDiscipline discipline = RouteDiscipline.run,
  }) async {
    requests++;
    return [for (var angle = 0; angle < 360; angle += 30) Geo.destination(center, angle.toDouble(), 1500)];
  }
}

/// Punkte unterwegs ohne Netz: ein Trinkbrunnen am Start.
final class FakePois implements RoutePoiSource {
  int requests = 0;

  @override
  Future<List<RoutePoi>> pois(List<GeoPoint> route, {required Set<PoiKind> kinds}) async {
    requests++;
    return [RoutePoi(kind: PoiKind.water, point: route.first, name: 'Brunnen')];
  }
}

/// Overpass gestört.
final class FailingFeatures extends FakeFeatures {
  @override
  Future<List<GeoPoint>> attractors(
    GeoPoint center,
    double radiusMeters,
    Set<RoutePreference> preferences, {
    RouteDiscipline discipline = RouteDiscipline.run,
  }) async {
    requests++;
    throw const RoutingUnavailable('Overpass gestört');
  }
}

/// Vorhersage: 8 °C, Wind 20 km/h aus Süden, den ganzen Tag.
final class FakeWeather implements WeatherSource {
  int calls = 0;

  @override
  Future<List<WeatherHour>> forecast(GeoPoint point, CalendarDay day) async {
    calls++;
    return [
      for (var hour = 0; hour < 24; hour++)
        WeatherHour(
          time: DateTime(day.year, day.month, day.day, hour),
          temperature: 8,
          windSpeed: 20,
          windFrom: 180,
          windGusts: 40,
          precipitationProbability: 10,
          weatherCode: 3,
        ),
    ];
  }
}

/// Garmin-Konto, das jeden Kurs mit der ID 42 annimmt.
final fakeGarmin = GarminCourseTarget(
  isLoggedIn: () => true,
  sender: ({required method, required path, required json}) async =>
      Uint8List.fromList(utf8.encode('{"courseId": 42}')),
);

Future<ProviderContainer> openPlanner(
  WidgetTester tester,
  FakeRouting routing, {
  FakeFeatures? features,
  FakePlaces? places,
  FakeLocation? location,
  FakeNotificationCenter? notifications,
}) async {
  OsmTiles.cacheDisabled = true;
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    await tester.runAsync(
      () => app(
        onboarded: true,
        overrides: [
          routingBackendProvider.overrideWithValue(routing),
          routeFeatureSourceProvider.overrideWithValue(features ?? FakeFeatures()),
          placeSearchProvider.overrideWithValue(places ?? FakePlaces()),
          routePoiSourceProvider.overrideWithValue(FakePois()),
          locationSourceProvider.overrideWithValue(location ?? FakeLocation()),
          garminCourseTargetProvider.overrideWithValue(fakeGarmin),
          weatherSourceProvider.overrideWithValue(FakeWeather()),
          notificationCenterProvider.overrideWithValue(notifications),
        ],
      ),
    ) as Widget,
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
  await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Plan')));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  await tapCentered(tester, find.text('Routen'));
  await tester.tap(find.text('Neue Route planen'));
  await tester.pumpAndSettle();
  return container;
}

/// Tippen auf die Karte (Mitte plus [offset]) und die Erkennung von Doppeltipps abwarten.
Future<void> tapMap(WidgetTester tester, {Offset offset = Offset.zero}) async {
  await tester.tapAt(tester.getCenter(find.byType(FlutterMap)) + offset);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

/// Element in die Mitte scrollen (nicht unter die schwebende Tab-Leiste) und antippen.
Future<void> tapCentered(WidgetTester tester, Finder finder, {double delta = 300}) async {
  // Direkt über die Scroll-Position statt per Wischen (Wischen über der Karte verschiebt nur die Karte).
  final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  for (var step = 0; step < 60 && finder.evaluate().isEmpty; step++) {
    position.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
    await tester.pump();
  }
  await tester.runAsync(() => Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Route planen, speichern, für heute übernehmen; Gebiete optional', (tester) async {
    OsmTiles.cacheDisabled = true;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final routing = FakeRouting();
    final features = FakeFeatures();
    final weather = FakeWeather();
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [
            routingBackendProvider.overrideWithValue(routing),
            routeFeatureSourceProvider.overrideWithValue(features),
            routePoiSourceProvider.overrideWithValue(FakePois()),
            locationSourceProvider.overrideWithValue(FakeLocation()),
            garminCourseTargetProvider.overrideWithValue(fakeGarmin),
            weatherSourceProvider.overrideWithValue(weather),
          ],
        ),
      ) as Widget,
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Plan')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    await tapCentered(tester, find.text('Routen'));
    expect(find.byType(RoutesScreen), findsOneWidget);
    expect(find.text('Meine Karte'), findsNothing);

    await tester.tap(find.text('Neue Route planen'));
    await tester.pumpAndSettle();
    expect(find.byType(RoutePlannerScreen), findsOneWidget);

    // Ohne Start: Hinweis statt Anfrage.
    await tapCentered(tester, find.text('Routen vorschlagen'));
    expect(find.textContaining('Bitte zuerst einen Startpunkt'), findsOneWidget);
    expect(routing.calls, 0);

    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    expect(find.text('Start: dein Standort'), findsOneWidget);

    await tester.tap(find.text('Rennrad'));
    await tester.pumpAndSettle();
    expect(find.text('Asphalt: Radwege und ruhige Straßen'), findsOneWidget);

    // Umgebung: am Wasser.
    await tapCentered(tester, find.text('Am Wasser'), delta: -300);
    expect(find.text(RoutePreference.water.detail), findsOneWidget);

    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.calls, greaterThan(0));
    expect(routing.preferences.first, {RoutePreference.water});
    expect(features.requests, 1);
    expect(find.text('Neu würfeln'), findsOneWidget);
    expect(find.textContaining('% Am Wasser'), findsWidgets);

    // Antippen der Karte öffnet das Vollbild; Start und Vorschläge bleiben stehen.
    final start = container.read(routeStoreProvider).settings;
    expect(start.preferences, {RoutePreference.water});
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    final callsBefore = routing.calls;
    await tapMap(tester, offset: const Offset(40, 30));
    expect(find.byType(FullscreenRouteMap), findsOneWidget);
    expect(find.text('Lange drücken verschiebt den Start und plant neu.'), findsOneWidget);
    // Vorschläge auch im Vollbild wählbar.
    await tester.tap(find.textContaining('${RouteVariant.hilly.label} ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenRouteMap), findsNothing);
    expect(find.text('Antippen: Vollbild · lange drücken verschiebt den Start.'), findsOneWidget);
    expect(routing.calls, callsBefore);
    // „Startpunkt ändern“ gibt es nur, solange die Vorschläge noch da sind.
    expect(find.text('Startpunkt ändern'), findsOneWidget);

    final list = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var step = 0; step < 40 && find.text('Neu würfeln').evaluate().isEmpty; step++) {
      list.jumpTo((list.pixels + 300).clamp(0, list.maxScrollExtent));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    for (final variant in RouteVariant.values) {
      expect(find.text(variant.label), findsWidgets);
    }

    await tapCentered(tester, find.text('Sichern'));
    final store = container.read(routeStoreProvider);
    expect(store.routes.length, 1);
    expect(store.routes.single.discipline, RouteDiscipline.roadBike);
    expect(store.routes.single.username, store.username);

    // In Einheit übernehmen → Heute.
    await tester.tap(find.text('In Einheit übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Heute')));
    await tester.pumpAndSettle();
    expect(store.plannedOn(CalendarDay.today()).length, 1);

    // Gespeicherte Route öffnen.
    await tester.tap(find.text('Gesichert – öffnen'));
    await tester.pumpAndSettle();
    expect(find.byType(RouteDetailScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Als GPX teilen'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Als GPX teilen'), findsOneWidget);
    expect(find.textContaining('Geplant für heute'), findsOneWidget);
    // Wetter für den geplanten Tag am Start.
    await tester.scrollUntilVisible(find.text('Wetter heute'), -300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Wetter heute'), findsOneWidget);
    expect(find.textContaining('8 °C · bewölkt'), findsOneWidget);
    expect(find.text('Wind 20 km/h aus S, Böen 40'), findsOneWidget);
    expect(weather.calls, 1);

    // An Uhr senden: Auswahl der Hersteller mit passendem Format.
    await tapCentered(tester, find.text('An Uhr senden'));
    expect(find.text('Garmin'), findsOneWidget);
    expect(find.text('Apple Watch'), findsOneWidget);
    // Karte auf die Uhr (Garmin-Datenfeld): ohne Worker nur ein Hinweis.
    expect(find.text('Karte auf die Uhr (Garmin)'), findsOneWidget);
    expect(find.textContaining('eigene Worker nötig'), findsWidgets);
    expect(find.text('FIT'), findsWidgets);
    // Direkt an Garmin Connect: Kurs-ID landet an der gespeicherten Route.
    await tester.tap(find.text('Direkt an Garmin Connect senden'));
    for (var step = 0; step < 20 && find.textContaining('Training › Strecken').evaluate().isEmpty; step++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('Training › Strecken'), findsOneWidget);
    expect(find.text('In Garmin Connect öffnen'), findsOneWidget);
    expect(store.routes.single.garminCourseID, 42);
    Navigator.of(tester.element(find.text('Garmin'))).pop();
    await tester.pumpAndSettle();

    // Von Hand abschließen: ins Archiv, nicht mehr „für heute“.
    await tapCentered(tester, find.text('Als erledigt markieren'));
    expect(store.archive.single.isCompleted, isTrue);
    expect(store.plannedOn(CalendarDay.today()), isEmpty);
    expect(find.textContaining('Erledigt am'), findsOneWidget);

    // Kilometermarken auf der Karte der Route.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byType(KilometerMarkers), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    Navigator.of(tester.element(find.byType(RouteDetailScreen))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(RoutePlannerScreen))).pop();
    await tester.pumpAndSettle();

    // Routen-Übersicht: Route steht im Archiv.
    expect(find.text('ARCHIV'), findsOneWidget);
    expect(find.textContaining('erledigt am'), findsOneWidget);

    // Gebiete einschalten: Karte erscheint.
    await tapCentered(tester, find.text('Gebiete anzeigen'));
    expect(store.settings.explorationEnabled, isTrue);
    await tapCentered(tester, find.text('Meine Karte'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(ExplorationScreen), findsOneWidget);
    expect(find.text('Kacheln erkundet'), findsOneWidget);
  });

  testWidgets('Frei planen: Punkte antippen, zeichnen, rückgängig, Rundweg schließen, speichern', (tester) async {
    final routing = FakeRouting();
    final container = await openPlanner(tester, routing);
    await tester.tap(find.text('Frei planen'));
    await tester.pumpAndSettle();
    expect(find.byType(RouteDrawScreen), findsOneWidget);
    expect(find.text('Tippe den Start an oder suche eine Adresse (Lupe).'), findsOneWidget);

    // Start und ein Wegpunkt: ein Abschnitt, Werte in der Leiste.
    await tapMap(tester);
    expect(find.textContaining('Nächsten Punkt antippen'), findsOneWidget);
    await tapMap(tester, offset: const Offset(80, -60));
    expect(routing.calls, 1);
    expect(find.text('0 m'), findsNothing);
    expect(find.textContaining('hm'), findsWidgets);

    // Zeichnen: Strich wird zu einem weiteren Abschnitt.
    await tester.tap(find.text('Zeichnen'));
    await tester.pumpAndSettle();
    await tester.dragFrom(tester.getCenter(find.byType(FlutterMap)) + const Offset(80, -60), const Offset(-120, 90));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(routing.calls, 2);

    // Rückgängig entfernt den Strich, Rundweg schließen routet zurück zum Start.
    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rundweg schließen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(routing.calls, 3);

    await tester.tap(find.text('Sichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(RouteDetailScreen), findsOneWidget);
    final store = container.read(routeStoreProvider);
    final saved = store.routes.single;
    expect(saved.request.shape, RouteShape.drawn);
    expect(saved.isLoop, isTrue);
    expect(saved.username, store.username);
  });

  testWidgets('Frei planen: Luftlinie, wo die Karte keinen Weg kennt', (tester) async {
    final routing = FakeRouting();
    final container = await openPlanner(tester, routing);
    await tester.tap(find.text('Frei planen'));
    await tester.pumpAndSettle();
    await tapMap(tester);
    await tapMap(tester, offset: const Offset(100, 0));
    expect(routing.calls, 1);

    // Kein Weg bekannt: die Meldung bietet die Luftlinie an.
    routing.noRoute = true;
    await tapMap(tester, offset: const Offset(100, -100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('kennt die Karte keinen Weg'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Luftlinie'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Luftlinie', findRichText: true), findsWidgets);
    expect(find.textContaining(RegExp(r'· [\d,]+ k?m Luftlinie')), findsOneWidget);

    // Umschalter: nächste Punkte direkt, ohne Router.
    await tester.tap(find.byTooltip('Nächste Punkte als Luftlinie verbinden'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Luftlinie: Neue Punkte werden direkt verbunden'), findsOneWidget);
    final calls = routing.calls;
    await tapMap(tester, offset: const Offset(0, -100));
    expect(routing.calls, calls);

    // Abschnitt per Wegpunkt zurück auf Wege: wird geroutet.
    routing.noRoute = false;
    await tester.tap(find.byTooltip('Nächste Punkte wieder auf Wegen'));
    await tester.pumpAndSettle();
    await tapMap(tester, offset: const Offset(100, -100));
    expect(find.text('Punkt 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Abschnitt bis hier wieder auf Wege legen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(routing.calls, calls + 1);

    await tester.tap(find.byTooltip('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final saved = container.read(routeStoreProvider).routes.single;
    expect(saved.request.shape, RouteShape.drawn);
    expect(saved.stats.distanceMeters, greaterThan(0));
  });

  testWidgets('Zum Ziel ohne Wunschdistanz: direkt zum Ziel, z. B. Lauf zur Arbeit', (tester) async {
    final routing = FakeRouting();
    final places = FakePlaces();
    final container = await openPlanner(tester, routing, places: places);
    await tester.enterText(find.widgetWithText(TextField, 'Startadresse oder Ort'), 'Hauptstr');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hauptstraße 5'));
    await tester.pumpAndSettle();

    await tapCentered(tester, find.text('Zum Ziel'));
    expect(find.text('Mit Wunschdistanz'), findsOneWidget);
    await tapCentered(tester, find.text('Mit Wunschdistanz'));
    expect(find.text('Aus: direkt zum Ziel, z. B. Lauf zur Arbeit'), findsOneWidget);
    final destination = find.widgetWithText(TextField, 'Zieladresse oder Ort');
    await tapCentered(tester, destination);
    await tester.enterText(destination, 'Hafen');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    // Keine Distanzwahl, nur die Schätzung.
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('ca. '), findsWidgets);

    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.calls, greaterThan(0));
    // Je Variante genau eine Anfrage direkt von Start zum Ziel.
    for (final waypoints in routing.waypointLists) {
      expect(waypoints.length, 2);
    }
    final planner = container.read(routePlannerControllerProvider);
    expect(planner.routes, isNotEmpty);
    expect(planner.routes.first.request.isDirect, isTrue);
    // Die Wahl bleibt für das nächste Mal.
    expect(container.read(routeStoreProvider).settings.directToDestination, isTrue);
  });

  testWidgets('Start und Ziel per Adresszeile', (tester) async {
    final routing = FakeRouting();
    final places = FakePlaces();
    final container = await openPlanner(tester, routing, places: places);

    // Tippen: Vorschläge nach kurzer Pause, Auswahl setzt den Start.
    await tester.enterText(find.widgetWithText(TextField, 'Startadresse oder Ort'), 'Hauptstr');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(places.queries, ['Hauptstr']);
    expect(find.text('Hauptstraße 50'), findsOneWidget);
    await tester.tap(find.text('Hauptstraße 5'));
    await tester.pumpAndSettle();
    expect(find.text('Start: gesuchte Adresse'), findsOneWidget);
    expect(find.text('Hauptstraße 5, 10827 Berlin'), findsOneWidget);

    // Stern: Start als Favorit „Zuhause“ merken; beim nächsten Antippen der Adresszeile erscheint er.
    await tester.tap(find.byTooltip('Als Favorit speichern').first);
    await tester.pumpAndSettle();
    expect(find.text('Als Favorit speichern'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Zuhause');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Sichern')));
    await tester.pumpAndSettle();
    final store = container.read(routeStoreProvider);
    expect(store.favorites.single.name, 'Zuhause');
    expect(store.favorites.single.address, 'Hauptstraße 5, 10827 Berlin');
    expect(find.byTooltip('Aus Favoriten entfernen'), findsOneWidget);

    // Zum Ziel: Zieladresse per Eingabetaste, ein Treffer wird gleich übernommen.
    await tapCentered(tester, find.text('Zum Ziel'));
    final destination = find.widgetWithText(TextField, 'Zieladresse oder Ort');
    await tapCentered(tester, destination);
    // Favorit beim Antippen sichtbar, noch bevor getippt wird.
    expect(find.descendant(of: find.byType(AddressField).last, matching: find.text('Zuhause')), findsOneWidget);
    await tester.enterText(destination, 'Hafen');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('Hafen, 10117 Berlin'), findsOneWidget);
    // Hinweis „als Favorit gespeichert“ ausblenden (liegt über dem Knopf).
    ScaffoldMessenger.of(tester.element(find.byType(RoutePlannerScreen))).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.calls, greaterThan(0));
    expect(find.textContaining('Bitte'), findsNothing);
  });

  testWidgets('Spazieren als eigene Disziplin', (tester) async {
    final routing = FakeRouting();
    await openPlanner(tester, routing);
    expect(find.text('Gravel'), findsOneWidget);
    expect(find.text('Gravel/Allround'), findsNothing);
    // „Mein Standort“: blauer Punkt auf der Karte, aber kein Start.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mein Standort').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(tester.widget<MyLocationLayer>(find.byType(MyLocationLayer).first).point, home);
    expect(find.text('oder einen Pin auf der Karte setzen'), findsOneWidget);
    expect(routing.calls, 0);
    await tapCentered(tester, find.text('Spazieren'));
    expect(find.text(RouteDiscipline.walk.surfaces), findsOneWidget);
    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.disciplines.toSet(), {RouteDiscipline.walk});
  });

  testWidgets('Vorschläge bleiben beim Verlassen erhalten und kommen einzeln', (tester) async {
    final routing = FakeRouting();
    final container = await openPlanner(tester, routing);
    final planner = container.read(routePlannerControllerProvider);
    final counts = <int>[];
    void listener() => counts.add(planner.routes.length);
    planner.addListener(listener);
    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    planner.removeListener(listener);
    // Erst einer, dann zwei, dann drei Vorschläge.
    expect(counts.toSet().containsAll({1, 2, 3}), isTrue);
    expect(planner.routes.length, 3);

    // Planer verlassen und wieder öffnen: Vorschläge und Start sind noch da.
    Navigator.of(tester.element(find.byType(RoutePlannerScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neue Route planen'));
    await tester.pumpAndSettle();
    expect(find.text('Start: dein Standort'), findsOneWidget);
    expect(find.text('Startpunkt ändern'), findsOneWidget);
    expect(planner.routes.length, 3);
    final calls = routing.calls;
    await tapCentered(tester, find.text('Neu würfeln'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.calls, greaterThan(calls));

    // Zurücksetzen leert alles.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Planer zurücksetzen'));
    await tester.pumpAndSettle();
    expect(planner.routes, isEmpty);
    expect(planner.start, isNull);
  });

  testWidgets('Route für eine Einheit des Ausdauerplans: vorbelegt und beim Speichern zugeordnet', (tester) async {
    final routing = FakeRouting();
    final container = await openPlanner(tester, routing);
    Navigator.of(tester.element(find.byType(RoutePlannerScreen))).pop();
    await tester.pumpAndSettle();
    final planner = container.read(routePlannerControllerProvider);
    final day = CalendarDay.today().adding(2);
    final suggestion = RouteForWorkout.suggest(isBike: false, isRun: true, minutes: 60, runThresholdPace: 240)!;
    planner.prepareForSlot(
      discipline: suggestion.discipline,
      kilometers: suggestion.kilometers,
      day: day,
      slotID: 'slot-42',
      title: 'Langer Lauf',
    );
    await tester.tap(find.text('Neue Route planen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Für „Langer Lauf“'), findsOneWidget);
    expect(planner.kilometers, 12);
    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tapCentered(tester, find.text('Sichern'));
    final saved = container.read(routeStoreProvider).openRoutes.single;
    expect(saved.slotID, 'slot-42');
    expect(saved.slotTitle, 'Langer Lauf');
    expect(saved.plannedDay, day);
  });

  testWidgets('Hinweis, wenn „Am Wasser“ gerade nicht berücksichtigt werden kann', (tester) async {
    final routing = FakeRouting();
    await openPlanner(tester, routing, features: FailingFeatures());
    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    await tapCentered(tester, find.text('Am Wasser'));
    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.calls, greaterThan(0));
    expect(find.textContaining('„Am Wasser“ sind gerade nicht erreichbar'), findsOneWidget);
  });

  testWidgets('Frei planen: Wegpunkte wählen, verschieben, einfügen und löschen', (tester) async {
    final routing = FakeRouting();
    await openPlanner(tester, routing);
    await tester.tap(find.text('Frei planen'));
    await tester.pumpAndSettle();
    await tapMap(tester);
    await tapMap(tester, offset: const Offset(120, 0));
    await tapMap(tester, offset: const Offset(120, 120));
    expect(routing.calls, 2);

    // Mittleren Punkt antippen: gewählt, Werkzeuge erscheinen.
    await tapMap(tester, offset: const Offset(120, 0));
    expect(find.text('Punkt 1'), findsOneWidget);
    expect(find.textContaining('Punkt gewählt: verschieben, löschen'), findsOneWidget);

    // Verschieben: nächster Tipp setzt die neue Lage, beide Nachbarabschnitte werden neu geroutet.
    await tester.tap(find.byTooltip('Punkt verschieben'));
    await tester.pumpAndSettle();
    expect(find.text('Tippe auf die neue Position des Punkts.'), findsOneWidget);
    await tapMap(tester, offset: const Offset(150, -40));
    expect(routing.calls, 4);

    // Löschen: Nachbarn werden direkt verbunden (ein Abschnitt neu).
    await tester.tap(find.byTooltip('Punkt löschen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(routing.calls, 5);
    expect(find.text('Punkt 1'), findsNothing);

    // Rückgängig holt den Punkt zurück.
    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pumpAndSettle();
    await tapMap(tester, offset: const Offset(150, -40));
    expect(find.text('Punkt 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Fertig'));
    await tester.pumpAndSettle();
    expect(find.text('Punkt 1'), findsNothing);

    // Lange auf die Linie drücken fügt dort einen Punkt ein (zwei Abschnitte neu geroutet).
    final calls = routing.calls;
    await tester.longPressAt(tester.getCenter(find.byType(FlutterMap)) + const Offset(75, -20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(routing.calls, calls + 2);
    expect(find.text('Punkt 1'), findsOneWidget);
  });

  testWidgets('Gassi: Hundewiese nur beim Spazieren, Punkte unterwegs, Vorlage mit einem Tipp', (tester) async {
    final routing = FakeRouting();
    final container = await openPlanner(tester, routing);
    expect(find.text('Hundewiese'), findsNothing);
    await tapCentered(tester, find.text('Spazieren'));
    expect(find.text('Hundewiese'), findsOneWidget);
    await tapCentered(tester, find.text('Hundewiese'));
    final planner = container.read(routePlannerControllerProvider);
    expect(planner.preferences, {RoutePreference.dogPark});
    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.disciplines.toSet(), {RouteDiscipline.walk});

    // Punkte unterwegs: Trinkbrunnen auf der Karte.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Trinkbrunnen: Brunnen'), findsOneWidget);

    // Als Vorlage speichern.
    await tester.tap(find.byTooltip('Als Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Als Vorlage speichern'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Gassi');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Sichern')));
    await tester.pumpAndSettle();
    final store = container.read(routeStoreProvider);
    expect(store.templates.single.name, 'Gassi');
    expect(store.templates.single.preferences, {RoutePreference.dogPark});

    // Wechsel zu Laufen entfernt die Hundewiese.
    await tapCentered(tester, find.text('Laufen'), delta: -300);
    expect(planner.preferences, isEmpty);

    // In der Übersicht: Vorlage antippen plant sofort wieder als Spaziergang.
    ScaffoldMessenger.of(tester.element(find.byType(RoutePlannerScreen))).hideCurrentSnackBar();
    Navigator.of(tester.element(find.byType(RoutePlannerScreen))).pop();
    await tester.pumpAndSettle();
    final calls = routing.calls;
    await tapCentered(tester, find.text('Gassi'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(RoutePlannerScreen), findsOneWidget);
    expect(routing.calls, greaterThan(calls));
    expect(planner.discipline, RouteDiscipline.walk);
    expect(planner.routes, isNotEmpty);
  });

  testWidgets('Route folgen: Standort live, Fortschritt, Warnung abseits der Route – auch bei gesperrtem Bildschirm', (
    tester,
  ) async {
    final routing = FakeRouting();
    final location = FakeLocation();
    final notifications = FakeNotificationCenter();
    await openPlanner(tester, routing, location: location, notifications: notifications);
    await tapCentered(tester, find.text('Aktueller Standort'), delta: -300);
    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tapCentered(tester, find.text('Sichern'));
    await tapCentered(tester, find.text('Gesichert – öffnen'));
    await tapCentered(tester, find.text('Route folgen'));
    expect(find.byType(FollowRouteScreen), findsOneWidget);
    expect(find.text('Standort wird gesucht …'), findsOneWidget);
    // Ortung läuft auch bei gesperrtem Bildschirm weiter; der Bildschirm muss nicht anbleiben.
    expect(location.background, isTrue);
    expect(find.textContaining('Du kannst den Bildschirm sperren'), findsOneWidget);
    await tester.tap(find.byTooltip('Bildschirm anlassen'));
    await tester.pump();
    expect(find.text('Bildschirm bleibt an.'), findsOneWidget);

    location.positions.add(home);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Auf der Route'), findsOneWidget);

    // Zweimal weit weg: Warnung.
    final away = Geo.destination(home, 225, 3000);
    location.positions.add(away);
    await tester.pump();
    location.positions.add(away);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Abseits der Route'), findsOneWidget);
    // Im Vordergrund: Vibration, keine Mitteilung.
    expect(notifications.shown, isEmpty);

    // Bildschirm gesperrt: zurück auf die Route, dann wieder weg – jetzt als Mitteilung.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    location.positions.add(home);
    await tester.pump();
    location.positions.add(home);
    await tester.pump();
    location.positions.add(away);
    await tester.pump();
    location.positions.add(away);
    await tester.pump();
    expect(notifications.shown.single.$2, 'Abseits der Route');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(notifications.removedDelivered, contains('coach.route.follow'));

    await tester.tap(find.byTooltip('Beenden'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowRouteScreen), findsNothing);
  });
}

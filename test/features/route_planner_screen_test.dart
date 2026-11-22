// Routenplaner im Reiter Training: Einstieg, Standort als Start, Vorschläge, Speichern, Übernahme für heute, Gebiete.
import 'package:aironludi/features/routes/address_field.dart';
import 'package:aironludi/features/routes/exploration_screen.dart';
import 'package:aironludi/features/routes/my_location.dart';
import 'package:aironludi/features/routes/route_detail_screen.dart';
import 'package:aironludi/features/routes/route_draw_screen.dart';
import 'package:aironludi/features/routes/route_parts.dart';
import 'package:aironludi/features/routes/route_planner_controller.dart';
import 'package:aironludi/features/routes/route_planner_screen.dart';
import 'package:aironludi/features/routes/routes_screen.dart';
import 'package:aironludi/services/routing/location_source.dart';
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
  @override
  Future<GeoPoint> current() async => home;
}

/// Router ohne Netz: läuft die Wegpunkte ab (Umwegfaktor 1,3) und liefert Höhen.
final class FakeRouting implements RoutingBackend {
  int calls = 0;
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
    this.preferences.add(preferences);
    disciplines.add(discipline);
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

Future<ProviderContainer> openPlanner(
  WidgetTester tester,
  FakeRouting routing, {
  FakeFeatures? features,
  FakePlaces? places,
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
          locationSourceProvider.overrideWithValue(FakeLocation()),
        ],
      ),
    ) as Widget,
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
  await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Training')));
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
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [
            routingBackendProvider.overrideWithValue(routing),
            routeFeatureSourceProvider.overrideWithValue(features),
            locationSourceProvider.overrideWithValue(FakeLocation()),
          ],
        ),
      ) as Widget,
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
    await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text('Training')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    await tapCentered(tester, find.text('Routen'));
    expect(find.byType(RoutesScreen), findsOneWidget);
    expect(find.text('Gebiete anzeigen'), findsOneWidget);
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

    await tapCentered(tester, find.text('Speichern'));
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
    await tester.tap(find.text('Gespeichert – öffnen'));
    await tester.pumpAndSettle();
    expect(find.byType(RouteDetailScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Als GPX teilen'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Als GPX teilen'), findsOneWidget);
    expect(find.textContaining('Geplant für heute'), findsOneWidget);

    // An Uhr senden: Auswahl der Hersteller mit passendem Format.
    await tapCentered(tester, find.text('An Uhr senden'));
    expect(find.text('Garmin'), findsOneWidget);
    expect(find.text('Apple Watch'), findsOneWidget);
    expect(find.text('FIT'), findsWidgets);
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
    expect(find.text('Nächsten Punkt antippen. Zoomen und Verschieben wie gewohnt.'), findsOneWidget);
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

    await tester.tap(find.text('Speichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(RouteDetailScreen), findsOneWidget);
    final store = container.read(routeStoreProvider);
    final saved = store.routes.single;
    expect(saved.request.shape, RouteShape.drawn);
    expect(saved.isLoop, isTrue);
    expect(saved.username, store.username);
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
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Speichern')));
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
}

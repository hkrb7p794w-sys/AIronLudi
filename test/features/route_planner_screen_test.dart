// Routenplaner im Reiter Training: Einstieg, Standort als Start, Vorschläge, Speichern, Übernahme für heute, Gebiete.
import 'package:aironludi/features/routes/exploration_screen.dart';
import 'package:aironludi/features/routes/route_detail_screen.dart';
import 'package:aironludi/features/routes/route_parts.dart';
import 'package:aironludi/features/routes/route_planner_screen.dart';
import 'package:aironludi/features/routes/routes_screen.dart';
import 'package:aironludi/services/routing/location_source.dart';
import 'package:aironludi/services/routing/routing_providers.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
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

  @override
  Future<RoutedPath> route(
    List<GeoPoint> waypoints, {
    required RouteDiscipline discipline,
    required RouteVariant variant,
    double? elevationGain,
    double? distanceMeters,
  }) async {
    calls++;
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

/// Element in die Mitte scrollen (nicht unter die schwebende Tab-Leiste) und antippen.
Future<void> tapCentered(WidgetTester tester, Finder finder, {double delta = 300}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, delta, scrollable: find.byType(Scrollable).first);
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
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [
            routingBackendProvider.overrideWithValue(routing),
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

    await tapCentered(tester, find.text('Routen vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(routing.calls, greaterThan(0));
    expect(find.text('Neu würfeln'), findsOneWidget);
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
    Navigator.of(tester.element(find.byType(RouteDetailScreen))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(RoutePlannerScreen))).pop();
    await tester.pumpAndSettle();

    // Gebiete einschalten: Karte erscheint.
    expect(find.textContaining('Geplant für heute'), findsOneWidget);
    await tester.tap(find.text('Gebiete anzeigen'));
    await tester.pumpAndSettle();
    expect(store.settings.explorationEnabled, isTrue);
    await tester.tap(find.text('Meine Karte'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(ExplorationScreen), findsOneWidget);
    expect(find.text('Kacheln erkundet'), findsOneWidget);
  });
}

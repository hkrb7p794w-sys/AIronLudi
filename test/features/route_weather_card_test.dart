// Wetter-Karte der Route: Startzeit wählen, Wind je Hälfte, „Richtung umkehren“ bei Gegenwind zum Schluss.
import 'package:aironludi/features/routes/route_weather_card.dart';
import 'package:aironludi/services/routing/routing_providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'route_planner_screen_test.dart' show FakeWeather;

const start = GeoPoint(52.52, 13.405);

PlannedRoute outAndBack({CalendarDay? day}) => PlannedRoute(
  id: 'r',
  username: 'anna',
  name: 'Hin und zurück',
  request: const RouteRequest(
    discipline: RouteDiscipline.roadBike,
    shape: RouteShape.loop,
    start: start,
    distanceMeters: 4000,
  ),
  variant: RouteVariant.balanced,
  // Hin nach Norden, zurück nach Süden: Wind aus Süden heißt erst Rückenwind, dann Gegenwind.
  points: [
    for (var index = 0; index <= 20; index++) Geo.destination(start, 0, index * 100.0),
    for (var index = 19; index >= 0; index--) Geo.destination(start, 0, index * 100.0),
  ],
  engine: 'Test',
  createdAt: DateTime.utc(2026, 11, 23),
  plannedDay: day,
);

Future<void> pumpCard(WidgetTester tester, PlannedRoute route, {void Function(PlannedRoute)? onReverse}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [weatherSourceProvider.overrideWithValue(FakeWeather())],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteWeatherCard(route: route, onReverse: onReverse),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Gegenwind zum Schluss: Hinweis und „Richtung umkehren“', (tester) async {
    PlannedRoute? reversed;
    final route = outAndBack(day: CalendarDay.today().adding(1));
    await pumpCard(tester, route, onReverse: (value) => reversed = value);
    expect(find.text('Wetter morgen'), findsOneWidget);
    expect(find.textContaining('andersherum'), findsOneWidget);
    await tester.tap(find.text('13 Uhr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Richtung umkehren'));
    expect(reversed!.points.first, route.points.last);
  });

  testWidgets('Zu weit in der Zukunft: nur ein Hinweis, keine Anfrage', (tester) async {
    await pumpCard(tester, outAndBack(day: CalendarDay.today().adding(30)));
    expect(find.textContaining('ab 15 Tage'), findsOneWidget);
    expect(find.text('Richtung umkehren'), findsNothing);
  });
}

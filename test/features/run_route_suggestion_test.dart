// Routenvorschlag zur geplanten Laufeinheit: passend zum Training, annehmen oder ablehnen, Einstellungen.
import 'package:aironludi/features/plan/plan_screen.dart';
import 'package:aironludi/features/routes/route_parts.dart';
import 'package:aironludi/features/routes/run_route_suggestion_card.dart';
import 'package:aironludi/features/settings/discipline_settings.dart';
import 'package:aironludi/services/routing/routing_providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;
import 'route_planner_screen_test.dart' show FakeFeatures, FakeLocation, FakePois, FakeRouting;

/// In die Mitte scrollen (nicht unter die schwebende Tab-Leiste) und tippen.
Future<void> tapCentered(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() => Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}

void main() {
  final day = CalendarDay.today().adding(1);
  const slot = SessionSlot(TrainingSport.run, SessionIntensity.hard);

  Future<ProviderContainer> open(WidgetTester tester, FakeRouting routing, {Widget? screen}) async {
    OsmTiles.cacheDisabled = true;
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [
            routingBackendProvider.overrideWithValue(routing),
            routeFeatureSourceProvider.overrideWithValue(FakeFeatures()),
            routePoiSourceProvider.overrideWithValue(FakePois()),
            locationSourceProvider.overrideWithValue(FakeLocation()),
          ],
        ),
      ) as Widget,
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    // Nicht abgewartet: Die Seite bleibt bis zum Testende offen.
    // ignore: unawaited_futures
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => screen ?? SessionGuideScreen(slot: slot, day: day, minutes: 45),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    // Container des Benutzers (wie die geöffnete Seite).
    return ProviderScope.containerOf(tester.element(find.byType(screen?.runtimeType ?? SessionGuideScreen)));
  }

  testWidgets('Vorschlag zur Tempoeinheit: flach, ablehnen bringt eine andere Runde, annehmen ordnet zu', (
    tester,
  ) async {
    final routing = FakeRouting();
    final container = await open(tester, routing);
    expect(find.byType(RunRouteSuggestionCard), findsOneWidget);
    expect(find.text('Routenvorschlag'), findsOneWidget);
    expect(find.textContaining('Tempo und Intervalle: flach'), findsOneWidget);
    final store = container.read(routeStoreProvider);
    final unitID = 'woche:${day.iso}:run:hard';
    final first = store.runSuggestions.entries[unitID]!.route!;
    expect(first.request.elevationGainMeters, isNotNull);
    // Noch nicht in der Ablage.
    expect(store.routes, isEmpty);

    // Ablehnen: Spur gemerkt, neuer Vorschlag.
    await tapCentered(tester, find.text('Ablehnen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final state = store.runSuggestions;
    expect(state.declined.length, 1);
    final second = state.entries[unitID]!.route!;
    expect(second.id, isNot(first.id));

    // Annehmen: Route gehört zur Einheit, Karte verschwindet.
    await tapCentered(tester, find.text('Annehmen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final saved = store.routes.single;
    expect(saved.id, second.id);
    expect(saved.slotID, unitID);
    expect(saved.plannedDay, day);
    expect(store.runSuggestions.entries[unitID]!.status, RunSuggestionStatus.accepted);
    expect(find.byType(RunRouteSuggestionCard), findsNothing);
  });

  testWidgets('„Für diese Einheit keine Route“ blendet aus; „Doch eine Route vorschlagen“ holt ihn zurück', (
    tester,
  ) async {
    final routing = FakeRouting();
    final container = await open(tester, routing);
    await tapCentered(tester, find.text('Für diese Einheit keine Route'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Routenvorschlag'), findsNothing);
    expect(find.text('Doch eine Route vorschlagen'), findsOneWidget);
    expect(
      container.read(routeStoreProvider).runSuggestions.entries.values.single.status,
      RunSuggestionStatus.declined,
    );
    await tapCentered(tester, find.text('Doch eine Route vorschlagen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Routenvorschlag'), findsOneWidget);
  });

  testWidgets('Einstellungen: aus schaltet Vorschläge ab, Gelände wird übernommen', (tester) async {
    final routing = FakeRouting();
    final container = await open(tester, routing, screen: const EnduranceSettingsScreen(sport: TrainingSport.run));
    await tester.scrollUntilVisible(
      find.text('Am liebsten laufe ich …'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tapCentered(tester, find.text(RoutePreference.nature.label));
    final store = container.read(routeStoreProvider);
    expect(store.runSuggestions.preferences, {RoutePreference.nature});
    await tapCentered(tester, find.text('Routen zu geplanten Läufen vorschlagen'));
    expect(store.runSuggestions.enabled, isFalse);

    // Ohne Vorschläge: die Einheit zeigt nur „Route dazu planen“.
    Navigator.of(tester.element(find.byType(EnduranceSettingsScreen))).pop();
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    // ignore: unawaited_futures
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SessionGuideScreen(slot: slot, day: day, minutes: 45),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RunRouteSuggestionCard), findsNothing);
    expect(routing.calls, 0);
  });
}

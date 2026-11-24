// Schnellaktionen, Widgets und `coach://open/…` führen ihre Aktion aus (vorher öffneten sie nur den Reiter).
import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/app/router.dart';
import 'package:aironludi/features/health/health_screen.dart';
import 'package:aironludi/features/nutrition/product_search_screen.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> start(WidgetTester tester) async {
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
}

/// Wie `openRoute` aus deep_links.dart (dort mit `Ref`).
Future<void> open(WidgetTester tester, ProviderContainer container, AppRoute route, {MealCategory? category}) async {
  container.read(pendingRouteProvider.notifier).open(PendingRoute(route, mealCategory: category));
  container.read(routerProvider).go(tabPath(route.tab));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('„Mahlzeit erfassen“ öffnet das Erfassen mit der gewünschten Mahlzeit', (tester) async {
    final container = await start(tester);
    await open(tester, container, AppRoute.logMeal, category: MealCategory.dinner);
    expect(find.byType(ProductSearchScreen), findsOneWidget);
    expect(tester.widget<ProductSearchScreen>(find.byType(ProductSearchScreen)).category, MealCategory.dinner);
    expect(container.read(pendingRouteProvider), isNull);
  });

  testWidgets('„Health öffnen“ öffnet die Gesundheitsseite', (tester) async {
    final container = await start(tester);
    await open(tester, container, AppRoute.health);
    expect(find.byType(HealthScreen), findsOneWidget);
    expect(container.read(pendingRouteProvider), isNull);
  });
}

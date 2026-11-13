// Port von CoachCoreTests/AppRouteTests.swift (ohne die Fälle zu Wasser und Widget-Snapshot, die mit ihren
// Modulen folgen).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  group('AppRoute', () {
    test('Link hin und zurück', () {
      for (final route in AppRoute.values) {
        expect(AppRoute.fromUri(route.uri), route);
      }
      expect(AppRoute.logMeal.uri.toString(), 'coach://open/logMeal');
    });

    test('fremde Links werden ignoriert', () {
      expect(AppRoute.fromUri(Uri.parse('coach://join?worker=https://x&token=a&league=abcdef')), isNull);
      expect(AppRoute.fromUri(Uri.parse('coach://open/somethingNew')), isNull);
      expect(AppRoute.fromUri(Uri.parse('https://open/logMeal')), isNull);
    });

    test('Gym und AI liegen in anderen Reitern', () {
      expect(AppRoute.startWorkout.tab, AppTab.training);
      expect(AppRoute.gym.tab, AppTab.training);
      expect(AppRoute.startWorkout.opensArea, AppRoute.gym);
      expect(AppRoute.aiAnalysis.tab, AppTab.today);
      expect(AppRoute.aiAnalysis.opensArea, AppRoute.ai);
      expect(AppRoute.health.tab, AppTab.training);
      expect(AppRoute.health.opensArea, isNull);
      expect(AppRoute.logMeal.tab, AppTab.nutrition);
      // Jede Route mit Bereich braucht eine Zielansicht, die sie übernimmt.
      for (final route in AppRoute.values.where((route) => route.opensArea != null)) {
        expect(route.hasAction, isTrue, reason: route.name);
      }
    });

    test('Schnellaktionen nur, wenn sie funktionieren', () {
      expect(QuickActions.routes(trainsStrength: true, aiAvailable: true), [
        AppRoute.startWorkout,
        AppRoute.logMeal,
        AppRoute.health,
        AppRoute.aiAnalysis,
      ]);
      expect(QuickActions.routes(trainsStrength: false, aiAvailable: false), [AppRoute.logMeal, AppRoute.health]);
      expect(
        QuickActions.routes(trainsStrength: true, aiAvailable: true).length,
        lessThanOrEqualTo(QuickActions.limit),
      );
    });

    test('Mahlzeiten-Link trägt die Mahlzeit', () {
      final uri = AppRoute.logMealUri(MealCategory.lunch);
      expect(uri.toString(), 'coach://open/logMeal?mahlzeit=mittagessen');
      expect(AppRoute.fromUri(uri), AppRoute.logMeal);
      expect(AppRoute.mealCategoryFrom(uri), MealCategory.lunch);
      expect(AppRoute.mealCategoryFrom(AppRoute.logMeal.uri), isNull);
    });
  });

  group('AppAppearance', () {
    test('gespeicherte Werte hin und zurück', () {
      for (final appearance in AppAppearance.values) {
        expect(AppAppearance.fromStored(appearance.name), appearance);
      }
    });

    test('unbekannte Werte folgen dem System', () {
      expect(AppAppearance.fromStored(null), AppAppearance.system);
      expect(AppAppearance.fromStored('sepia'), AppAppearance.system);
    });
  });
}

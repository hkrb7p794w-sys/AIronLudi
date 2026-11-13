import '../nutrition/meal_category.dart';

/// Reiter der App. Gym liegt im Reiter Training, die KI-Empfehlungen sind von „Heute“ aus erreichbar
/// (Entscheidung vom 10.11.2026: Platz für den Reiter „Aktivitäten“).
enum AppTab { today, activities, training, nutrition }

/// Ziele, die von außen angesprungen werden: Schnellaktionen am App-Icon, Kurzbefehle/Siri und Widgets. Eine Route
/// wählt den Reiter und optional eine Aktion darin; als Link `coach://open/<route>`.
enum AppRoute {
  today('Heute', null),

  /// Gesundheitsbereich (Morning Report, Widgets, Body Battery) im Reiter Training.
  health('Health öffnen', 'Morning Report, Body Battery, Schlaf'),
  nutrition('Ernährung', null),

  /// Erfassen-Bildschirm der Ernährung öffnen.
  logMeal('Mahlzeit erfassen', 'Foto, Text, Barcode oder Suche'),
  gym('Gym', null),

  /// Laufende Einheit öffnen, sonst die nächste geplante starten (zählt erst mit dem ersten Satz).
  startWorkout('Training starten', 'Nächste Einheit oder laufende fortsetzen'),
  ai('AI', null),

  /// KI-Analyse über alle Themen anstoßen (nur wenn die KI eingerichtet und erlaubt ist).
  aiAnalysis('KI-Analyse starten', 'Alle Themen auswerten');

  const AppRoute(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  static const scheme = 'coach';
  static const host = 'open';

  /// Route aus einem Link `coach://open/<route>`, sonst `null`.
  static AppRoute? fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final name = uri.pathSegments.where((segment) => segment.isNotEmpty).firstOrNull ?? '';
    return values.where((route) => route.name == name).firstOrNull;
  }

  Uri get uri => Uri.parse('$scheme://$host/$name');

  /// „Mahlzeit erfassen“ für eine bestimmte Mahlzeit (Mahlzeiten-Widget): `coach://open/logMeal?mahlzeit=…`.
  static Uri logMealUri(MealCategory category) => Uri.parse('${logMeal.uri}?mahlzeit=${category.rawValue}');

  /// Mahlzeit aus einem Link (`?mahlzeit=mittagessen`), sonst `null`.
  static MealCategory? mealCategoryFrom(Uri uri) => MealCategory.fromRaw(uri.queryParameters['mahlzeit']);

  /// Reiter der Route. Gym-Ziele öffnen den Gym-Bereich im Reiter Training, KI-Ziele die Empfehlungen über „Heute“.
  AppTab get tab => switch (this) {
    today || ai || aiAnalysis => AppTab.today,
    health || gym || startWorkout => AppTab.training,
    nutrition || logMeal => AppTab.nutrition,
  };

  /// Aktion im Reiter, die die Zielansicht einmal ausführt (danach gilt die Route als erledigt).
  bool get hasAction => switch (this) {
    health || logMeal || gym || startWorkout || ai || aiAnalysis => true,
    today || nutrition => false,
  };

  /// Bereich, den der Reiter zuerst öffnen muss, bevor die Zielansicht die Aktion übernimmt.
  AppRoute? get opensArea => switch (this) {
    gym || startWorkout => gym,
    ai || aiAnalysis => ai,
    _ => null,
  };
}

/// Schnellaktionen beim langen Drücken auf das App-Icon. iOS zeigt höchstens vier eigene Einträge; angeboten wird
/// nur, was für die Person auch funktioniert (kein „Training starten“ ohne Krafttraining, keine KI ohne Worker).
abstract final class QuickActions {
  static const limit = 4;

  static List<AppRoute> routes({required bool trainsStrength, required bool aiAvailable}) {
    final routes = <AppRoute>[
      if (trainsStrength) AppRoute.startWorkout,
      AppRoute.logMeal,
      AppRoute.health,
      if (aiAvailable) AppRoute.aiAnalysis,
    ];
    return routes.take(limit).toList();
  }
}

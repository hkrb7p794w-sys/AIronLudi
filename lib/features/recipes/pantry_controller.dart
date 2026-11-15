import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/coach_settings.dart';
import '../../services/ai/ai_client.dart';

/// Rezepte aus einem Foto von Kühlschrank oder Vorratsschrank: Foto an die KI, erkannte Lebensmittel korrigieren,
/// Rückfragen zu kleinen fehlenden Zutaten beantworten („Ist noch Butter da?“). Die Antworten klären die Vorschläge
/// sofort, ohne neue Anfrage; erst „Neu vorschlagen“ fragt die KI mit Liste und Antworten noch einmal
/// (`PantryRecipes`).
final class PantryController extends ChangeNotifier {
  PantryController({required this._ai, required this._settings, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AIClient _ai;
  final CoachSettings _settings;
  final DateTime Function() _clock;

  Uint8List? photo;
  PantryResult? result;
  List<String> detected = [];
  final Set<String> confirmed = {};
  final Set<String> denied = {};
  bool isWorking = false;
  String? errorMessage;

  bool get canAsk => _ai.allows(PantryRecipes.task);

  List<PantryRecipe> get recipes => result?.recipes ?? const [];

  List<String> get questions => PantryRecipes.questions(recipes, confirmed: confirmed, denied: denied);

  PantryRecipeStatus status(PantryRecipe recipe) => PantryRecipes.status(recipe, confirmed: confirmed, denied: denied);

  /// Kein Vorschlag geht mehr (alle an „nicht da“ gescheitert) – dann lohnt „Neu vorschlagen“.
  bool get allBlocked => recipes.isNotEmpty && recipes.every((recipe) => status(recipe) == PantryRecipeStatus.blocked);

  void setPhoto(Uint8List data) {
    photo = data;
    result = null;
    detected = [];
    confirmed.clear();
    denied.clear();
    errorMessage = null;
    notifyListeners();
  }

  /// Antwort auf „Ist noch … da?“.
  void answer(String ingredient, {required bool available}) {
    final id = PantryRecipes.key(ingredient);
    confirmed.removeWhere((name) => PantryRecipes.key(name) == id);
    denied.removeWhere((name) => PantryRecipes.key(name) == id);
    (available ? confirmed : denied).add(ingredient);
    notifyListeners();
  }

  void removeDetected(String name) {
    detected = [
      for (final item in detected)
        if (PantryRecipes.key(item) != PantryRecipes.key(name)) item,
    ];
    notifyListeners();
  }

  void addDetected(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || detected.any((item) => PantryRecipes.key(item) == PantryRecipes.key(trimmed))) return;
    detected = [...detected, trimmed];
    notifyListeners();
  }

  /// Erste Anfrage mit dem Foto bzw. – nach Korrekturen und Antworten – „Neu vorschlagen“.
  Future<void> suggest() async {
    final image = photo;
    if (isWorking || (image == null && detected.isEmpty)) return;
    if (!_ai.isConfigured) {
      errorMessage = AIClientError.notConfigured.message;
      notifyListeners();
      return;
    }
    isWorking = true;
    errorMessage = null;
    notifyListeners();
    try {
      final input = PantryRecipes.input(
        category: () {
          final now = _clock();
          return MealCategory.guess(hour: now.hour, minute: now.minute);
        }(),
        targetKilocalories: null,
        diet: _settings.nutrition.diet,
        preferences: _settings.recipes,
        pantry: _settings.pantry,
        detected: detected,
        confirmed: confirmed,
        denied: denied,
      );
      final response = await _ai.run(
        PantryRecipes.task,
        input: input,
        images: [if (image != null) AIImage(mimeType: 'image/jpeg', data: image)],
      );
      final parsed = PantryRecipes.result(
        response.output,
        diet: _settings.nutrition.diet,
        allergens: _settings.recipes.allergens,
        pantry: _settings.pantry,
        confirmed: confirmed,
      );
      if (parsed == null) {
        errorMessage = 'Die KI hat nichts Brauchbares geliefert. Bitte ein helleres Foto versuchen.';
        return;
      }
      result = parsed;
      // Die korrigierte Liste bleibt; neu Erkanntes kommt dazu.
      final known = {for (final item in detected) PantryRecipes.key(item)};
      detected = [
        ...detected,
        for (final item in parsed.detected)
          if (!known.contains(PantryRecipes.key(item))) item,
      ];
      if (parsed.recipes.isEmpty) errorMessage = 'Keine passenden Gerichte erhalten – Liste ergänzen und neu fragen.';
    } on AIClientError catch (error) {
      errorMessage = error.message;
    } on Object catch (error) {
      errorMessage = '$error';
    } finally {
      isWorking = false;
      notifyListeners();
    }
  }
}

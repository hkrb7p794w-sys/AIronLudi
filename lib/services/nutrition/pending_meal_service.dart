import 'dart:async';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../platform/notifications.dart';
import '../ai/ai_client.dart';
import 'pending_analysis.dart';

/// KI-Analyse einer Mahlzeit aus Foto und/oder Beschreibung (Aufgabe `meal_analyze`).
abstract final class MealAnalyzer {
  /// Fragt die KI; wirft bei Fehlern, auch wenn sie keine Lebensmittel erkannt hat.
  static Future<MealAnalysis> request(
    AIClient ai,
    CoachSettings settings, {
    required String text,
    Uint8List? photo,
    required List<StoredFood> foods,
  }) async {
    final input = {
      'text': text,
      'diet': settings.nutrition.diet.rawValue,
      'personalFoods': [for (final food in foods.take(40)) food.name],
    };
    final response = await ai.run(
      'meal_analyze',
      input: input,
      images: photo == null ? const [] : [AIImage(mimeType: 'image/jpeg', data: photo)],
    );
    final analysis = MealAnalysis.fromOutput(response.output);
    if (analysis == null) throw const AIClientError.http(200, 'Die KI hat keine Lebensmittel erkannt.');
    return analysis;
  }

  /// Eigene, schon einmal gespeicherte Lebensmittel haben Vorrang vor der KI-Schätzung (Nährwerte je 100 g).
  static MealItem preferKnownFood(MealItem item, List<StoredFood> foods) {
    final known = foods.where((food) => food.name.toLowerCase() == item.name.toLowerCase()).firstOrNull?.item;
    if (known == null || known.source == MealItemSource.ai) return item;
    return item.copy()
      ..per100g = known.per100g.copy()
      ..source = known.source
      ..barcode = known.barcode;
  }

  /// Lohnt ein späterer Versuch? Netz weg, Zeitüberschreitung, KI überlastet oder Kontingent ausgeschöpft – nicht bei
  /// abgelehnter Anmeldung, ausgeschalteter KI oder wenn die KI auf dem Foto nichts erkannt hat.
  static bool isTemporary(Object error) => switch (error) {
    AINetworkError() || TimeoutException() => true,
    AIHttpError(:final status) => status == 408 || status == 429 || status >= 500,
    _ => false,
  };

  static String message(Object error) => error is AIClientError ? error.message : '$error';
}

/// Wertet wartende Mahlzeiten aus ([PendingAnalysisStore]): auf Wunsch sofort mit Editor (App), mit [autoLog] ohne
/// Rückfrage – dann trägt der Dienst Gericht, Mengen, Makros und Uhrzeit der Aufnahme selbst ein, auch im
/// Hintergrundabruf bei geschlossener App, und meldet das per Mitteilung.
final class PendingMealService {
  PendingMealService({
    required this.store,
    required this._ai,
    required this._meals,
    required this._settings,
    this._notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const notificationPrefix = 'coach.pendingMeal.';

  /// Art der Mitteilung (`info['kind']`): öffnet nur die App.
  static const notificationKind = 'pendingMeal';

  final PendingAnalysisStore store;
  final AIClient _ai;
  final MealRepository _meals;
  final CoachSettings _settings;
  final NotificationCenterBridge? _notifications;
  final DateTime Function() _clock;

  bool get isConfigured => _ai.isConfigured;

  /// Wertet [item] aus und ruft [then] mit dem Ergebnis auf; erst danach verschwindet die Auswertung aus der
  /// Warteschlange (bricht die App dazwischen ab, bleibt das Foto erhalten). Fehler: Versuch mit Meldung vermerkt,
  /// automatisches Eintragen nur bei vorübergehenden Fehlern weiter, Fehler weitergereicht. `false`, wenn gerade ein
  /// anderer Ablauf daran arbeitet oder sie inzwischen erledigt ist.
  Future<bool> analyze(
    PendingAnalysis item, {
    required List<StoredFood> foods,
    required FutureOr<void> Function(PendingAnalysis item, MealAnalysis analysis) then,
  }) async {
    if (!store.claim(item, now: _clock())) return false;
    try {
      final current = store.reload(item);
      if (current == null) return false;
      try {
        final analysis = await MealAnalyzer.request(
          _ai,
          _settings,
          text: current.text,
          photo: store.photo(current),
          foods: foods,
        );
        await then(current, analysis);
        store.remove(current);
        return true;
      } on Object catch (error) {
        // In der Zwischenzeit verworfen: nicht wieder anlegen.
        final latest = store.reload(current);
        if (latest != null) {
          store.put(
            latest.failed(MealAnalyzer.message(error), now: _clock(), keepAuto: MealAnalyzer.isTemporary(error)),
          );
        }
        rethrow;
      }
    } finally {
      store.release(item);
    }
  }

  /// Fällige automatische Einträge auswerten und speichern; [notify]: per Mitteilung melden (Hintergrund).
  Future<List<StoredMeal>> processDue({bool notify = false}) async {
    if (!_ai.isConfigured) return const [];
    final due = [
      for (final item in store.load())
        if (item.autoLog && item.isDue(_clock())) item,
    ];
    if (due.isEmpty) return const [];
    final foods = await _meals.foods();
    final logged = <StoredMeal>[];
    for (final item in due) {
      try {
        await analyze(item, foods: foods, then: (item, analysis) async => logged.add(await log(item, analysis, foods)));
      } on Object {
        // Vermerkt; der nächste Versuch kommt nach [PendingMealRetry.delay].
      }
    }
    if (notify) {
      for (final meal in logged) {
        await _notify(meal);
      }
    }
    return logged;
  }

  /// Bleiben automatische Einträge offen (für die Planung des nächsten Hintergrundlaufs)?
  bool get hasAutoLog => store.load().any((item) => item.autoLog);

  /// Ergebnis ohne Editor eintragen: Tag und Uhrzeit der Aufnahme, Mahlzeit wie vorgewählt, sonst laut KI, sonst nach
  /// Uhrzeit.
  Future<StoredMeal> log(PendingAnalysis item, MealAnalysis analysis, List<StoredFood> foods) async {
    final at = item.eatenAt;
    final items = [for (final food in analysis.items) MealAnalyzer.preferKnownFood(food, foods).copy()..id = newUuid()];
    final record = StoredMeal(
      day: CalendarDay.fromDate(at),
      createdAt: at,
      category: item.category ?? analysis.category ?? MealCategory.guess(hour: at.hour, minute: at.minute),
      title: analysis.title.isNotEmpty ? analysis.title : (item.text.trim().isEmpty ? 'Mahlzeit' : item.text.trim()),
      hint: [analysis.hint, autoHint].where((part) => part.isNotEmpty).join(' '),
      items: items,
    );
    await _meals.save(record);
    await _meals.rememberFoods(items, at: at);
    await _meals.replaceFuelPlaceholders(record);
    return record;
  }

  /// Hinweis an automatisch eingetragenen Mahlzeiten.
  static const autoHint = 'Automatisch nachgetragen – bitte prüfen.';

  Future<void> _notify(StoredMeal meal) async {
    final center = _notifications;
    if (center == null) return;
    final kcal = meal.items.fold<double>(0, (sum, item) => sum + (item.amounts[Nutrient.kcal] ?? 0)).round();
    final time = DateFormat.Hm('de_DE').format(meal.createdAt);
    // Kurz in der Zukunft: Mitteilungen lassen sich nur planen.
    final at = _clock().add(const Duration(seconds: 3));
    try {
      await center.add(
        LocalNotification(
          id: '$notificationPrefix${meal.id}',
          title: 'Mahlzeit nachgetragen',
          body: '${meal.title} · $kcal kcal · ${meal.category.label} um $time',
          day: CalendarDay.fromDate(at),
          hour: at.hour,
          minute: at.minute,
          second: at.second,
          info: const {'kind': notificationKind},
        ),
      );
    } on Object {
      // Ohne Mitteilung: die Mahlzeit steht trotzdem im Tagebuch.
    }
  }
}

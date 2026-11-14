import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../data/settings/settings_store.dart';
import '../../services/ai/ai_client.dart';
import '../ai/coach_facts.dart';

/// Rezeptideen für einen frei gewählten Zeitraum (1 bis 14 Tage): gleiche Tagesziele aus dem Durchschnitt einer
/// typischen Woche, Lücken der letzten zwei Wochen und häufige Lebensmittel als Eingabe; die KI schlägt Gerichte vor,
/// die Regeln prüfen und passen an. Tage ohne brauchbare Rezepte werden einmal nachgefordert (Port von
/// `RecipeViewModel`, Teil Wochen-Rezepte).
final class RecipeController extends ChangeNotifier {
  RecipeController({required this._store, Future<Directory> Function()? folder, DateTime Function()? clock})
    : _folder = folder ?? getApplicationSupportDirectory,
      _clock = clock ?? DateTime.now {
    final today = CalendarDay.fromDate(_clock());
    checked = {...?_store.read(SettingsKeys.recipesChecked, _strings, null)};
    start = CalendarDay.tryParse(_store.string(SettingsKeys.recipesPeriodStart) ?? '') ?? today;
    final stored = _store.intValue(SettingsKeys.recipesPeriodDays) ?? 0;
    length = stored > 0 ? stored.clamp(1, RecipePlanner.maxPeriodDays) : defaultLength;
  }

  static const defaultLength = 7;

  final SettingsStore _store;
  final Future<Directory> Function() _folder;
  final DateTime Function() _clock;

  late CalendarDay start;
  late int length;
  WeeklyRecipePlan? plan;
  List<RecipeDayTarget> targets = const [];
  List<String> gaps = const [];
  bool isWorking = false;
  String? errorMessage;

  /// Abgehakte Einträge der Einkaufsliste.
  Set<String> checked = {};

  static List<String>? _strings(Object? json) => json is List ? [for (final item in json) '$item'] : null;

  Future<File> _file() async => File(p.join((await _folder()).path, 'recipes.json'));

  /// Gespeicherten Plan laden (im JSON-Format der Swift-App).
  Future<void> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      plan = WeeklyRecipePlan.fromJson(jsonDecode(await file.readAsString()));
      notifyListeners();
    } on Object {
      // Kein oder unlesbarer Plan.
    }
  }

  /// Zeitraum wählen (ab heute, 1 bis 14 Tage); die Ziele werden mit dem nächsten `update` neu berechnet.
  void setPeriod({required CalendarDay start, required int days}) {
    final today = CalendarDay.fromDate(_clock());
    this.start = start < today ? today : start;
    length = days.clamp(1, RecipePlanner.maxPeriodDays);
    unawaited(_store.setString(SettingsKeys.recipesPeriodStart, this.start.iso));
    unawaited(_store.setInt(SettingsKeys.recipesPeriodDays, length));
    notifyListeners();
  }

  /// Tage des Zeitraums, für die es noch keine Rezepte gibt.
  List<RecipeDayTarget> get missing => RecipePlanner.missing(targets, plan: plan);

  /// Geplante Einheiten eines Tages: eigener Wochenplan (mit Ausnahmen) oder Saisonplan.
  static ({List<TemplateItem> items, List<String> sessions}) planned(CalendarDay day, CoachSettings settings) {
    if (settings.profile.mode == ProfileMode.personal) {
      final schedule = settings.schedule(day);
      final weekday = Weekday.of(day);
      return (
        items: schedule.templateItems(weekday),
        sessions: [for (final slot in schedule.slots(weekday)) slot.title],
      );
    }
    final items = SeasonPlan.state(today: day, config: settings.season, week: WeeklyVolume()).todayFixed;
    return (items: items, sessions: [for (final item in items) item.text]);
  }

  /// Tagesziele und Lücken neu berechnen. Die Ziele sind an jedem Tag gleich: der Durchschnitt der nächsten sieben Tage
  /// aus Plan und Ernährungszielen – die Rezepte hängen nicht an einzelnen Trainingstagen.
  void update({
    required CoachSettings settings,
    required GarminProfile? garminProfile,
    required List<StoredMeal> meals,
  }) {
    final today = CalendarDay.fromDate(_clock());
    // Ein gespeicherter Beginn in der Vergangenheit rückt auf heute.
    if (start < today) start = today;
    final reference = [
      for (var offset = 0; offset < 7; offset++)
        () {
          final day = today.adding(offset);
          final planned = RecipeController.planned(day, settings);
          final values = NutritionPlanner.compute(
            activities: const [],
            planItems: planned.items,
            settings: settings.nutrition,
            garminProfile: garminProfile,
            day: day,
            hasGarminData: false,
          );
          return RecipeDayTarget.fromTargets(day: day, sessions: planned.sessions, targets: values);
        }(),
    ];
    targets = RecipePlanner.uniformTargets(
      days: RecipePlanner.period(start: start, days: length),
      reference: reference,
    );
    gaps = nutritionGaps(meals: meals, settings: settings, garminProfile: garminProfile, today: today);
    notifyListeners();
  }

  /// Rezepte für den Zeitraum erstellen. [missingOnly]: nur Tage ohne Rezepte ergänzen, vorhandene bleiben.
  Future<void> generate({
    required AIClient ai,
    required CoachSettings settings,
    required List<String> favorites,
    bool missingOnly = false,
  }) async {
    if (!ai.isConfigured) {
      errorMessage = 'Für Rezeptideen muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker).';
      notifyListeners();
      return;
    }
    final wanted = missingOnly ? missing : targets;
    if (isWorking || wanted.isEmpty) return;
    isWorking = true;
    notifyListeners();
    final now = _clock();
    try {
      final first = await _requestDays(wanted, ai: ai, settings: settings, favorites: favorites, now: now);
      var result = first.plan;
      // Tage ohne brauchbare Rezepte (Antwort unvollständig oder alle Gerichte verworfen) genau einmal nachfordern.
      final open = RecipePlanner.missing(wanted, plan: result);
      if (open.isNotEmpty && result != null) {
        final second = (await _requestDays(open, ai: ai, settings: settings, favorites: favorites, now: now)).plan;
        if (second != null) result = result.adding(second);
      }
      if (result == null) {
        errorMessage =
            first.failures.firstOrNull ?? 'Die KI hat keine brauchbaren Rezepte geliefert. Bitte erneut versuchen.';
        return;
      }
      var merged = result;
      if (missingOnly && plan != null) merged = plan!.adding(merged);
      // Hinweise zu fehlenden Tagen sind nach dem zweiten Anlauf überholt; unten steht der aktuelle Stand.
      final stillOpen = RecipePlanner.missing(targets, plan: merged);
      merged.notes = [
        for (final note in merged.notes)
          if (!note.endsWith('keine Rezepte erhalten.') && !note.endsWith('versucht es noch einmal.')) note,
        if (stillOpen.isNotEmpty)
          'Für ${stillOpen.length} ${stillOpen.length == 1 ? 'Tag' : 'Tage'} gab es keine passenden Rezepte. '
              '„Fehlende Tage erstellen“ versucht es noch einmal.',
      ];
      await _storePlan(merged, keepChecked: missingOnly);
      errorMessage = null;
    } finally {
      isWorking = false;
      notifyListeners();
    }
  }

  /// Nebeneinander in Teilen: Eine Antwort über viele Tage überschreitet das Antwortlimit der KI.
  Future<({WeeklyRecipePlan? plan, List<String> failures})> _requestDays(
    List<RecipeDayTarget> days, {
    required AIClient ai,
    required CoachSettings settings,
    required List<String> favorites,
    required DateTime now,
  }) async {
    final results = await Future.wait([
      for (final batch in RecipeBatches.batches(days))
        _requestBatch(batch, ai: ai, settings: settings, favorites: favorites, now: now),
    ]);
    final parts = [for (final result in results) ?result.plan];
    final failures = [for (final result in results) ?result.failure];
    return (plan: RecipeBatches.merged(parts, created: now), failures: failures);
  }

  /// Ein Teil der Woche. Bei einem vorübergehenden Ausfall genau ein zweiter Versuch, damit keine Kosten auflaufen.
  Future<({WeeklyRecipePlan? plan, String? failure})> _requestBatch(
    List<RecipeDayTarget> days, {
    required AIClient ai,
    required CoachSettings settings,
    required List<String> favorites,
    required DateTime now,
  }) async {
    final nutrition = settings.nutrition;
    final input = RecipePlanner.input(
      days: days,
      preferences: settings.recipes,
      diet: nutrition.diet,
      goal: settings.coachingProfile.goal.label,
      gaps: gaps,
      favorites: favorites,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await ai.run('weekly_recipes', input: input);
        final plan = RecipePlanner.plan(
          response.output,
          targets: days,
          diet: nutrition.diet,
          allergens: settings.recipes.allergens,
          source: 'KI · ${response.model}',
          created: now,
        );
        if (plan == null) {
          return (plan: null, failure: 'Die KI hat keine brauchbaren Rezepte geliefert. Bitte erneut versuchen.');
        }
        return (plan: plan, failure: null);
      } on AIHttpError catch (error) {
        if (attempt == 0 && AIErrorText.isTemporary(error.status)) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        return (plan: null, failure: error.message);
      } on Object catch (error) {
        return (plan: null, failure: error is AIClientError ? error.message : '$error');
      }
    }
    return (plan: null, failure: AIErrorText.message(status: 502, code: null, detail: ''));
  }

  void toggle(ShoppingItem item) {
    checked.contains(item.id) ? checked.remove(item.id) : checked.add(item.id);
    unawaited(_store.setJson(SettingsKeys.recipesChecked, checked.toList()));
    notifyListeners();
  }

  Future<void> _storePlan(WeeklyRecipePlan value, {bool keepChecked = false}) async {
    plan = value;
    if (!keepChecked) {
      checked = {};
      await _store.setJson(SettingsKeys.recipesChecked, const <String>[]);
    }
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(value.toJson()), flush: true);
    } on Object {
      // Der Plan bleibt im Speicher.
    }
  }
}

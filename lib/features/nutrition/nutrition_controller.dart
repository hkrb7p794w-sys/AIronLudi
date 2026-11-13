import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../services/ai/ai_client.dart';
import '../../services/nutrition/open_food_facts_client.dart';
import '../../services/nutrition/pending_analysis.dart';

/// Entwurf einer Mahlzeit, der im Editor geprüft und dann gespeichert wird.
final class MealDraft {
  MealDraft({
    this.record,
    required this.title,
    required this.category,
    required this.hint,
    required this.items,
    this.date,
    this.photo,
    this.possiblyMissing = const [],
  }) : id = newUuid();

  final String id;

  /// Bearbeitete Mahlzeit; `null` = neue.
  final StoredMeal? record;
  String title;
  MealCategory category;
  String hint;
  List<MealItem> items;

  /// Zeitpunkt; `null` = gewählter Tag zur aktuellen Uhrzeit.
  DateTime? date;

  /// Foto der KI-Analyse (verkleinert), damit Ergänzungen dieselbe Mahlzeit sehen.
  Uint8List? photo;

  /// Oft übersehene Bestandteile laut KI („Bratöl“, „Soße“) zum Antippen.
  List<String> possiblyMissing;
}

/// Tagesziele, Summen und die Wege, eine Mahlzeit zu erfassen (Foto, Text, Barcode, manuell). Port von
/// `NutritionViewModel`.
final class NutritionController extends ChangeNotifier {
  NutritionController({
    required this._meals,
    required this._settings,
    required this._ai,
    OpenFoodFactsClient? openFoodFacts,
    this._pendingStore,
    DateTime Function()? clock,
  }) : _openFoodFacts = openFoodFacts ?? OpenFoodFactsClient(),
       _clock = clock ?? DateTime.now {
    today = CalendarDay.fromDate(_clock());
    pending = _pendingStore?.load() ?? [];
  }

  final MealRepository _meals;
  final CoachSettings _settings;
  final AIClient _ai;
  final OpenFoodFactsClient _openFoodFacts;
  final PendingAnalysisStore? _pendingStore;
  final DateTime Function() _clock;

  /// Heute laut letzter Aktualisierung.
  late CalendarDay today;

  /// Im Wochenstreifen gewählter Tag; `null` = heute.
  CalendarDay? selectedDay;
  CalendarDay get day => selectedDay ?? today;

  /// Zuletzt per Schnell-Leiste eingetragen – für „Rückgängig“.
  ({StoredMeal record, String label})? lastLogged;
  NutritionTargets? targets;
  NutrientValues totals = NutrientValues();
  bool isWorking = false;
  List<String> reviewPoints = [];
  String? reviewModel;
  List<String> reviewSources = [];
  String? errorMessage;
  MealDraft? draft;

  /// Zeitpunkt des letzten Speicherns im Entwurf (z. B. Rezept „eingetragen“).
  DateTime? lastSaved;

  /// Vorgewählte Mahlzeit (z. B. „+“ bei „Mittagessen“ im Widget); gilt für den nächsten Entwurf.
  MealCategory? preferredCategory;

  /// Barcode ohne Treffer bei Open Food Facts – selbst anlegen oder Etikett fotografieren.
  String? missingBarcode;

  /// Fotos und Beschreibungen, die ohne Netz nicht ausgewertet werden konnten.
  List<PendingAnalysis> pending = [];

  List<Recipe> nowSuggestions = [];
  List<String> nowNotes = [];

  Object? _lastError;

  void _changed() => notifyListeners();

  /// Vorgewählte Mahlzeit vor der Einschätzung der KI, sonst deren Vorschlag, sonst Uhrzeit.
  MealCategory currentCategoryOr(MealCategory? guess) {
    if (preferredCategory case final preferred?) {
      preferredCategory = null;
      return preferred;
    }
    return guess ?? category(_clock());
  }

  /// Mahlzeit für einen neuen Entwurf: vorgewählt, sonst nach Uhrzeit.
  MealCategory currentCategory(DateTime date) {
    if (preferredCategory case final preferred?) {
      preferredCategory = null;
      return preferred;
    }
    return category(date);
  }

  static MealCategory category(DateTime date) => MealCategory.guess(hour: date.hour, minute: date.minute);

  void update({
    required List<StoredMeal> meals,
    required List<GarminActivity> activities,
    required GarminProfile? profile,
    required bool hasGarminData,
    RecoveryLevel? recovery,
    DateTime? now,
  }) {
    today = CalendarDay.fromDate(now ?? _clock());
    if (selectedDay == today) selectedDay = null;
    final day = this.day;
    targets = targetsFor(
      day,
      activities: activities,
      settings: _settings,
      profile: profile,
      hasGarminData: hasGarminData,
      recovery: day == today ? recovery : null,
    );
    totals = NutritionSummary.totals([
      for (final meal in meals)
        if (meal.day == day) ...meal.items,
    ]);
    _changed();
  }

  /// Tagesziele für einen Tag: Saisonplan aus der Musterwoche, persönliches Profil aus den eigenen Einheiten.
  static NutritionTargets targetsFor(
    CalendarDay day, {
    required List<GarminActivity> activities,
    required CoachSettings settings,
    required GarminProfile? profile,
    required bool hasGarminData,
    RecoveryLevel? recovery,
  }) {
    final dayActivities = activities.where((activity) => activity.day == day).toList();
    final List<TemplateItem> planItems;
    if (settings.profile.mode == ProfileMode.season) {
      final week = WeeklyVolume.from(activities, weekContaining: day);
      planItems = SeasonPlan.state(today: day, config: settings.season, week: week).todayFixed;
    } else {
      final schedule = settings.schedule(day);
      final weekday = Weekday.of(day);
      final runs = RunPlanner.week(
        profile: settings.profile,
        schedule: schedule,
        monday: PlanAdjustments.monday(day),
        activities: activities,
      )?.sessions.where((session) => session.weekday == weekday).map((session) => session.minutes).toList();
      planItems = schedule.templateItems(weekday, runMinutes: runs ?? const []);
    }
    // Krankheit zählt wie „Pause“: Die geplante Einheit findet nicht statt.
    final sick = settings.illnessDay;
    final isSick = sick != null && sick <= day && sick.daysUntil(day) <= MissedSessions.illnessEasyDays;
    return NutritionPlanner.compute(
      activities: dayActivities,
      planItems: planItems,
      settings: settings.nutrition,
      garminProfile: profile,
      day: day,
      hasGarminData: hasGarminData,
      recovery: isSick ? RecoveryLevel.pause : recovery,
    );
  }

  // Was jetzt?

  /// Drei Gerichte zu dem, was heute noch übrig ist; Ernährungsweise und Allergene prüft die App.
  Future<void> suggestNow(List<StoredFood> foods, {DateTime? now}) async {
    final targets = this.targets;
    if (targets == null) return;
    if (!_ai.isConfigured) {
      errorMessage = AIClientError.notConfigured.message;
      _changed();
      return;
    }
    final remaining = NutrientValues();
    for (final nutrient in const [Nutrient.kcal, Nutrient.protein, Nutrient.carbs, Nutrient.fat]) {
      final left = (targets.values[nutrient] ?? 0) - (totals[nutrient] ?? 0);
      remaining[nutrient] = left > 0 ? left : 0;
    }
    final kcal = MealNow.targetKilocalories(remaining[Nutrient.kcal] ?? 0);
    if (kcal == null) {
      nowSuggestions = [];
      nowNotes = ['Heute ist kaum noch etwas übrig – höchstens ein kleiner, proteinreicher Snack.'];
      _changed();
      return;
    }
    await _work(() async {
      final input = MealNow.input(
        remaining: remaining,
        category: currentCategory(now ?? _clock()),
        diet: _settings.nutrition.diet,
        preferences: _settings.recipes,
        pantry: _settings.pantry,
        favorites: [for (final food in foods.take(15)) food.name],
      );
      final response = await _ai.run('meal_now', input: input);
      final result = MealNow.suggestions(
        response.output,
        targetKilocalories: kcal,
        diet: _settings.nutrition.diet,
        allergens: _settings.recipes.allergens,
      );
      nowSuggestions = result.recipes;
      nowNotes = result.notes;
      if (result.recipes.isEmpty) errorMessage = 'Keine passenden Vorschläge erhalten – bitte noch einmal.';
    });
  }

  /// Vorschlag übernehmen: Entwurf zum Prüfen (Portion, Zutaten, Zeitpunkt).
  void draftFromRecipe(
    Recipe recipe, {
    String hint = 'Vorschlag „Was jetzt?“ (Nährwerte KI-geschätzt)',
    DateTime? now,
  }) {
    draft = MealDraft(
      title: recipe.title,
      category: currentCategory(now ?? _clock()),
      hint: hint,
      items: recipe.ingredients,
    );
    _changed();
  }

  // Ohne Netz

  /// Nächste wartende Auswertung versuchen; bleibt bei Netzfehler in der Warteschlange.
  Future<void> retryPending(List<StoredFood> foods) async {
    if (pending.isEmpty || isWorking || draft != null || !_ai.isConfigured) return;
    final next = pending.first;
    final ok = await analyze(next.text, photo: _pendingStore?.photo(next), foods: foods, queueOnNetworkError: false);
    if (ok) await removePending(next);
  }

  Future<void> removePending(PendingAnalysis item) async {
    _pendingStore?.deletePhoto(item);
    pending = pending.where((other) => other.id != item.id).toList();
    await _pendingStore?.save(pending);
    _changed();
  }

  // Kopieren und verschieben

  /// Mahlzeit heute (bzw. am gewählten Tag) erneut eintragen.
  Future<void> repeatMeal(StoredMeal record, {DateTime? now}) => log(
    title: record.title,
    category: currentCategory(now ?? _clock()),
    items: record.items,
    label: '${record.title} erneut eingetragen',
    now: now,
  );

  Future<void> move(StoredMeal record, MealCategory category) async {
    record.category = category;
    await _meals.save(record);
    _changed();
  }

  // Erfassen

  void newManualDraft({DateTime? now}) {
    draft = MealDraft(
      title: '',
      category: currentCategory(now ?? _clock()),
      hint: '',
      items: [MealItem(name: '', grams: 100, source: MealItemSource.manual, per100g: NutrientValues())],
    );
    _changed();
  }

  /// Unbekannter Barcode: leere Position mit Barcode – beim Speichern merkt sich die App das Produkt.
  void draftForMissingBarcode(String barcode, {DateTime? now}) {
    missingBarcode = null;
    final item = MealItem(name: '', grams: 100, source: MealItemSource.manual, per100g: NutrientValues())
      ..barcode = barcode;
    draft = MealDraft(
      title: '',
      category: currentCategory(now ?? _clock()),
      hint: 'Werte vom Etikett je 100 g',
      items: [item],
    );
    _changed();
  }

  /// Nährwerttabelle fotografiert: die KI liest Name, Werte je 100 g und Portion; gespeichert unter dem Barcode.
  /// [photo] ist bereits verkleinert (ohne EXIF/GPS).
  Future<void> readLabel(Uint8List photo, {String? barcode, DateTime? now}) async {
    if (!_ai.isConfigured) {
      errorMessage = AIClientError.notConfigured.message;
      _changed();
      return;
    }
    await _work(() async {
      final response = await _ai.run(
        'nutrition_label',
        images: [AIImage(mimeType: 'image/jpeg', data: photo)],
      );
      final item = NutritionLabel.item(response.output);
      if (item == null) throw const AIClientError.http(200, 'Auf dem Foto war keine Nährwerttabelle lesbar.');
      item.barcode = barcode;
      draft = MealDraft(
        title: item.name,
        category: currentCategory(now ?? _clock()),
        hint: 'Vom Etikett gelesen – bitte kurz prüfen.',
        items: [item],
      );
    });
  }

  /// Entwurf mit einem bekannten Lebensmittel (Suche), Menge wie zuletzt.
  void draftWithItem(MealItem item, {DateTime? now}) {
    final fresh = item.copy()..id = newUuid();
    draft = MealDraft(title: item.name, category: currentCategory(now ?? _clock()), hint: '', items: [fresh]);
    _changed();
  }

  /// Zeitpunkt für einen Eintrag am gewählten Tag: heute jetzt, sonst derselbe Tag zur aktuellen Uhrzeit.
  DateTime timestamp({DateTime? now}) {
    final at = now ?? _clock();
    today = CalendarDay.fromDate(at);
    if (day == today) return at;
    return DateTime(day.year, day.month, day.day, at.hour, at.minute);
  }

  /// Ein Tipp: Mahlzeit sofort eintragen (Schnell-Leiste, „wie gestern“, Suche, Wasser) – mit „Rückgängig“.
  Future<void> log({
    required String title,
    required MealCategory category,
    required List<MealItem> items,
    String? label,
    DateTime? now,
  }) async {
    final fresh = [for (final item in items) item.copy()..id = newUuid()];
    if (fresh.isEmpty) return;
    // Die App kann über Mitternacht offen geblieben sein.
    final at = now ?? _clock();
    today = CalendarDay.fromDate(at);
    final record = StoredMeal(
      day: day,
      createdAt: timestamp(now: at),
      category: category,
      title: title,
      items: fresh,
    );
    await _meals.save(record);
    await _meals.rememberFoods(fresh, at: at);
    lastLogged = (record: record, label: label ?? '$title eingetragen');
    _changed();
  }

  Future<void> undoLastLog() async {
    final record = lastLogged?.record;
    if (record == null) return;
    await _meals.delete(record.id);
    lastLogged = null;
    _changed();
  }

  void clearLastLogged() {
    lastLogged = null;
    _changed();
  }

  void edit(StoredMeal record) {
    draft = MealDraft(
      record: record,
      title: record.title,
      category: record.category,
      hint: record.hint,
      items: [for (final item in record.items) item.copy()],
      date: record.createdAt,
    );
    _changed();
  }

  /// KI-Analyse von Foto und/oder Text. Ohne Netz landet die Mahlzeit in der Warteschlange statt im Fehler. [photo]
  /// ist bereits verkleinert (ohne EXIF/GPS).
  Future<bool> analyze(
    String text, {
    Uint8List? photo,
    required List<StoredFood> foods,
    bool queueOnNetworkError = true,
  }) async {
    if (!_ai.isConfigured) {
      errorMessage = AIClientError.notConfigured.message;
      _changed();
      return false;
    }
    var succeeded = false;
    _lastError = null;
    await _work(() async {
      final input = {
        'text': text,
        'diet': _settings.nutrition.diet.rawValue,
        'personalFoods': [for (final food in foods.take(40)) food.name],
      };
      final response = await _ai.run(
        'meal_analyze',
        input: input,
        images: photo == null ? const [] : [AIImage(mimeType: 'image/jpeg', data: photo)],
      );
      final analysis = MealAnalysis.fromOutput(response.output);
      if (analysis == null) throw const AIClientError.http(200, 'Die KI hat keine Lebensmittel erkannt.');
      draft = MealDraft(
        title: analysis.title.isEmpty ? text : analysis.title,
        category: currentCategoryOr(analysis.category),
        hint: analysis.hint,
        items: [for (final item in analysis.items) preferKnownFood(item, foods)],
        photo: photo,
        possiblyMissing: analysis.possiblyMissing,
      );
      succeeded = true;
    });
    if (!succeeded && queueOnNetworkError && _lastError is AINetworkError && _pendingStore != null) {
      final item = _pendingStore.create(text: text, photo: photo);
      pending = [...pending, item];
      await _pendingStore.save(pending);
      errorMessage = 'Ohne Netz gespeichert – wird ausgewertet, sobald du wieder online bist.';
      _changed();
    }
    return succeeded;
  }

  /// Ergänzt einen Entwurf per KI („noch 150 g Hähnchenbrust und 1 EL Olivenöl“). Liefert nur die neuen Positionen; die
  /// bestehenden schickt die App als Bestand mit, damit die KI sie nicht wiederholt – überschrieben wird nie etwas.
  Future<({List<MealItem> items, String hint})?> amend(
    List<MealItem> items,
    String text, {
    Uint8List? photo,
    required List<StoredFood> foods,
  }) async {
    final request = text.trim();
    if (request.isEmpty) return null;
    final input = {
      'text': request,
      'diet': _settings.nutrition.diet.rawValue,
      'bestand': [
        for (final item in items) {'name': item.name, 'menge_g': item.grams},
      ],
    };
    try {
      final response = await _ai.run(
        'meal_amend',
        input: input,
        images: photo == null ? const [] : [AIImage(mimeType: 'image/jpeg', data: photo)],
      );
      final amendment = MealAnalysis.amendment(response.output);
      errorMessage = null;
      return (items: [for (final item in amendment.items) preferKnownFood(item, foods)], hint: amendment.hint);
    } on Object catch (error) {
      errorMessage = error is AIClientError ? error.message : '$error';
      _changed();
      return null;
    }
  }

  Future<void> lookup(String barcode, List<StoredFood> foods) async {
    await _work(() async {
      final key = 'barcode:$barcode';
      MealItem? item = foods.where((food) => food.key == key).firstOrNull?.item;
      if (item == null) {
        try {
          final product = await _openFoodFacts.product(barcode);
          item = product.item();
          await _meals.storeFood(item);
        } on FoodLookupError catch (error) {
          if (error == FoodLookupError.notFound) {
            missingBarcode = barcode;
            return;
          }
          rethrow;
        }
      }
      final fresh = item.copy()..id = newUuid();
      final existing = draft;
      if (existing != null) {
        existing.items = [...existing.items, fresh];
      } else {
        draft = MealDraft(title: fresh.name, category: category(_clock()), hint: '', items: [fresh]);
      }
    });
  }

  /// Speichert den Entwurf und merkt sich die Lebensmittel für Vorschläge und KI-Hinweise.
  Future<void> save(MealDraft draft) async {
    today = CalendarDay.fromDate(_clock());
    final items = draft.items.where((item) => item.name.trim().isNotEmpty && item.grams > 0).toList();
    if (items.isEmpty) {
      errorMessage = 'Mindestens eine Position mit Name und Menge eintragen.';
      _changed();
      return;
    }
    final title = draft.title.isEmpty ? items.map((item) => item.name).join(', ') : draft.title;
    if (draft.record case final record?) {
      record
        ..title = title
        ..category = draft.category
        ..items = items;
      if (draft.date case final date?) {
        record
          ..createdAt = date
          ..day = CalendarDay.fromDate(date);
      }
      await _meals.save(record);
    } else {
      // Ohne eigenen Zeitpunkt: gewählter Tag zur aktuellen Uhrzeit.
      final day = draft.date == null ? this.day : CalendarDay.fromDate(draft.date!);
      await _meals.save(
        StoredMeal(
          day: day,
          createdAt: draft.date ?? timestamp(),
          category: draft.category,
          title: title,
          hint: draft.hint,
          items: items,
        ),
      );
    }
    await _meals.rememberFoods(items, at: _clock());
    this.draft = null;
    lastSaved = _clock();
    _changed();
  }

  Future<void> delete(StoredMeal record) async {
    await _meals.delete(record.id);
    _changed();
  }

  // Auswertung

  /// Regeln, auf die sich die Ernährungsauswertung stützen darf.
  static const reviewEvidence = [
    'nutrition.energy',
    'nutrition.carbs',
    'nutrition.protein',
    'nutrition.reds',
    'recovery.sleep',
  ];

  Future<void> review({
    required List<StoredMeal> meals,
    required List<GarminActivity> activities,
    required String recovery,
  }) async {
    final targets = this.targets;
    if (targets == null) return;
    if (!_ai.isConfigured) {
      errorMessage = AIClientError.notConfigured.message;
      _changed();
      return;
    }
    await _work(() async {
      final todays = meals.where((meal) => meal.day == day).toList();
      // Saisonplan: Wochentag, Phase und Fixpunkte aus dem Plan; sonst Ziel und eigene Einheiten des Tages.
      final String weekdayName;
      final String phaseName;
      final List<String> plannedTexts;
      if (_settings.profile.mode == ProfileMode.season) {
        final week = WeeklyVolume.from(activities, weekContaining: day);
        final plan = SeasonPlan.state(today: day, config: _settings.season, week: week);
        weekdayName = plan.weekday;
        phaseName = plan.phase.rawValue;
        plannedTexts = [for (final item in plan.todayFixed) item.text];
      } else {
        final weekday = Weekday.of(day);
        weekdayName = weekday.long;
        phaseName = _settings.coachingProfile.goal.label;
        plannedTexts = [for (final slot in _settings.schedule(day).slots(weekday)) slot.title];
      }
      final training = [
        for (final activity in activities.where((activity) => activity.day == day))
          '${activity.name ?? activity.typeKey ?? 'Aktivität'} ${((activity.durationSeconds ?? 0) / 60).round()} min'
              '${activity.trainingLoad == null ? '' : ', Belastung ${activity.trainingLoad!.round()}'}',
      ];
      final input = {
        'weekday': weekdayName,
        'time': DateFormat.Hm('de_DE').format(_clock()),
        'dayType': targets.dayType.label,
        'dayTypeSource': targets.source.rawValue,
        'phase': phaseName,
        'training': training,
        'planned': plannedTexts,
        'recovery': recovery,
        'goal': _settings.nutrition.goal.label,
        'diet': _settings.nutrition.diet.label,
        'mealCount': todays.length.toDouble(),
        'meals': [for (final meal in todays) '${meal.category.label}: ${meal.title}'],
        'nutrients': [
          for (final nutrient in Nutrient.values)
            if (targets.values[nutrient] case final target?)
              {
                'label': nutrient.label,
                'unit': nutrient.unit,
                'actual': totals[nutrient] ?? 0,
                'target': target,
                'upperLimit': nutrient.isUpperLimit,
              },
        ],
        'evidence': CoachingNote.evidenceInput(reviewEvidence),
      };
      final response = await _ai.run('nutrition_review', input: input);
      reviewPoints = CoachingNote.points(response.output);
      reviewSources = CoachingNote.sources(response.output);
      reviewModel = response.model;
    });
  }

  // Hilfen

  /// Eigene, schon einmal gespeicherte Lebensmittel haben Vorrang vor der KI-Schätzung (Nährwerte je 100 g).
  static MealItem preferKnownFood(MealItem item, List<StoredFood> foods) {
    final known = foods.where((food) => food.name.toLowerCase() == item.name.toLowerCase()).firstOrNull?.item;
    if (known == null || known.source == MealItemSource.ai) return item;
    return item.copy()
      ..per100g = known.per100g.copy()
      ..source = known.source
      ..barcode = known.barcode;
  }

  Future<void> _work(Future<void> Function() operation) async {
    if (isWorking) return;
    isWorking = true;
    errorMessage = null;
    _lastError = null;
    _changed();
    try {
      await operation();
    } on Object catch (error) {
      _lastError = error;
      errorMessage = switch (error) {
        AIClientError(:final message) || FoodLookupError(:final message) => message,
        _ => '$error',
      };
    } finally {
      isWorking = false;
      _changed();
    }
  }
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/day_change.dart';
import '../../app/deep_links.dart';
import '../../app/training_data_reload.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/large_title.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import '../evidence/evidence_views.dart';
import '../fuel/fuel_planner_screen.dart';
import '../recipes/recipe_views.dart';
import '../settings/nutrition_settings_screen.dart';
import 'bls_views.dart';
import 'brand_product_results.dart';
import 'capture_views.dart';
import 'meal_editor.dart';
import 'meal_share_views.dart';
import 'meal_shortcuts.dart';
import 'nutrition_controller.dart';
import 'nutrition_plan_views.dart';
import 'product_search_screen.dart';
import 'weight_views.dart';

part 'nutrition_day_parts.dart';
part 'nutrition_entry_parts.dart';
part 'nutrition_sections.dart';

String mealSummary(List<MealItem> items) {
  final totals = NutritionSummary.totals(items);
  final grams = items.length == 1 ? '${GermanFormat.number(items[0].grams)} ${items[0].isDrink ? 'ml' : 'g'} · ' : '';
  return '$grams${(totals[Nutrient.kcal] ?? 0).round()} kcal · ${(totals[Nutrient.protein] ?? 0).round()} g Protein';
}

/// Ernährung des Tages: Ziele nach Training, Mahlzeiten, Erfassen und die gemeinsame KI-Auswertung von Ernährung und
/// Training (Port von `NutritionView.swift`).
class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen>
    with PendingRouteHandler<NutritionScreen>, TrainingDataReload<NutritionScreen> {
  /// Neue Aktivität, Tageswerte oder Gym-Einheit in der Datenbank (gleich aus welcher Quelle): neu laden.
  @override
  Future<void> reloadTrainingData() => _reload();

  @override
  Set<AppRoute> get handledRoutes => const {AppRoute.logMeal};

  @override
  void handlePendingRoute(PendingRoute pending) => unawaited(_showLogger(category: pending.mealCategory));

  late final NutritionController _controller;
  List<StoredMeal> _meals = const [];
  List<StoredFood> _foods = const [];
  List<GarminActivity> _activities = const [];
  List<DailyMetrics> _days = const [];
  final _query = TextEditingController();
  bool _searching = false;
  MealDraft? _openDraft;

  @override
  void initState() {
    super.initState();
    _controller = NutritionController(
      meals: ref.read(mealRepositoryProvider),
      settings: ref.read(coachSettingsProvider),
      ai: ref.read(aiClientProvider),
      openFoodFacts: ref.read(openFoodFactsProvider),
      pendingStore: ref.read(pendingAnalysisStoreProvider),
    )..addListener(_controllerChanged);
    _query.addListener(() => setState(() {}));
    unawaited(_reload().then((_) => _controller.retryPending(_foods)));
    // Mahlzeiten von anderswo (z. B. Fuel Planner aus einer Einheit des Ausdauerplans) sofort zeigen.
    _mealChanges = ref.read(mealDataChangesProvider).listen((_) => _reloadSoon());
  }

  StreamSubscription<void>? _mealChanges;
  bool _reloadQueued = false;

  /// Mehrere Änderungen kurz hintereinander: einmal neu laden.
  void _reloadSoon() {
    if (_reloadQueued) return;
    _reloadQueued = true;
    scheduleMicrotask(() {
      _reloadQueued = false;
      if (mounted) unawaited(_reload());
    });
  }

  @override
  void dispose() {
    unawaited(_mealChanges?.cancel());
    _controller
      ..removeListener(_controllerChanged)
      ..dispose();
    _query.dispose();
    super.dispose();
  }

  /// Neuer Entwurf (Analyse, Barcode, Vorschlag): Editor öffnen.
  void _controllerChanged() {
    if (!mounted) return;
    setState(() {});
    final draft = _controller.draft;
    if (draft != null && draft != _openDraft) {
      _openDraft = draft;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditor(draft));
    }
    if (_controller.errorMessage case final message?) {
      _controller.errorMessage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hinweis'),
            content: Text(message),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
      });
    }
    if (_controller.missingBarcode case final barcode?) {
      _controller.missingBarcode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _draftForMissing(barcode));
    }
  }

  /// Barcode ohne Treffer: Etikett fotografieren (KI liest ab) oder Werte selbst eintragen.
  Future<void> _draftForMissing(String barcode) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (_) => MissingBarcodeSheet(barcode: barcode),
    );
    if (!mounted) return;
    switch (result) {
      case MissingBarcodeSheet.create:
        _controller.draftForMissingBarcode(barcode);
      case final Uint8List photo:
        await _controller.readLabel(photo, barcode: barcode);
    }
  }

  Future<void> _openEditor(MealDraft draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MealEditorScreen(draft: draft, controller: _controller, foods: _foods),
      ),
    );
    if (_controller.draft == draft) _controller.draft = null;
    _openDraft = null;
    await _reload();
  }

  Future<void> _reload() async {
    final meals = ref.read(mealRepositoryProvider);
    final today = CalendarDay.today();
    final results = await (
      meals.all(),
      meals.foods(),
      ref.read(activityRepositoryProvider).all(),
      ref.read(metricsRepositoryProvider).range(from: today.adding(-120), to: today),
    ).wait;
    if (!mounted) return;
    _meals = results.$1;
    _foods = results.$2;
    _activities = results.$3;
    _days = results.$4;
    final form = FitnessForm.seriesUntil(_activities, today: today);
    _controller.update(
      meals: _meals,
      activities: _activities,
      profile: ref.read(appModelProvider).sync.profile,
      hasGarminData: _days.isNotEmpty,
      recovery: RecoveryEvaluator.today(days: _days, form: form, today: today).level,
    );
  }

  /// Aktion des Controllers, danach Daten neu laden und Erinnerungen neu planen.
  Future<void> _after(Future<void> action) async {
    await action;
    await _reload();
    unawaited(ref.read(appModelProvider).refreshReminders());
  }

  List<StoredMeal> get _todaysMeals => [
    for (final meal in _meals)
      if (meal.day == _controller.day) meal,
  ];

  HydrationTotal get _water => Hydration.total([for (final meal in _todaysMeals) ...meal.items]);

  void _logWater(double milliliters) => _after(
    _controller.log(
      title: 'Wasser',
      category: NutritionController.category(DateTime.now()),
      items: [MealItem.water(milliliters: milliliters)],
      label: '${milliliters.round()} ml Wasser',
    ),
  );

  String get _recoveryText {
    final state = RecoveryEvaluator.today(
      days: _days,
      form: FitnessForm.seriesUntil(_activities, today: _controller.day),
      today: _controller.day,
    );
    return state.isKnown ? state.recommendation.label : 'keine Daten';
  }

  bool get _showsCheckIn {
    final settings = ref.read(coachSettingsProvider);
    final nutrition = settings.nutrition;
    final start = _controller.today.adding(-NutritionCheckIn.dataWindowDays);
    return NutritionCheckIn.isDue(
      today: _controller.today,
      last: nutrition.lastCheckInDay,
      withheld: nutrition.weightTargetsWithheld,
      weighIns: [
        for (final entry in ref.read(appModelProvider).allWeights)
          if (entry.day >= start) entry.day,
      ],
      mealDays: [for (final meal in _meals.reversed.take(200)) meal.day],
    );
  }

  // Oberfläche

  @override
  Widget build(BuildContext context) {
    listenPendingRoutes();
    // Neuer Kalendertag (Mitternacht, Rückkehr in die App): neu laden wie `onDayChange`.
    ref.listen(currentDayProvider, (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final controller = _controller;
    final isToday = controller.day == controller.today;
    final title = isToday ? 'Ernährung' : DateFormat('EEE, d. MMM', 'de_DE').format(controller.day.referenceDate);
    final searching = _query.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Lebensmittel, Marke oder Mahlzeit suchen',
                  border: InputBorder.none,
                ),
              )
            : CollapsingTitle(child: Text(title)),
        actions: [
          IconButton(
            tooltip: _searching ? 'Suche schließen' : 'Suchen',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query.clear();
            }),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                if (searching)
                  ..._searchResults()
                else ...[
                  LargeTitleHeader(title),
                  _DayStrip(
                    selected: controller.day,
                    today: controller.today,
                    onSelect: (day) {
                      controller.selectedDay = day == controller.today ? null : day;
                      unawaited(_reload());
                    },
                  ),
                  if (controller.pending.isNotEmpty) _pendingSection(),
                  for (final card in settings.nutritionDashboard.visible) ..._dashboardCard(card),
                  // Wochen-Check-in unter dem Tag (Roast, Konzept 6.4): bleibt sichtbar, solange er fällig ist.
                  if (_showsCheckIn) _checkInSection(),
                ],
                if (DateTime.now().hour >= 18 || controller.reviewPoints.isNotEmpty) _reviewSection(),
                FormSection(
                  header: 'Planen',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.soup_kitchen_outlined),
                      title: const Text('Rezeptideen für die kommende Woche'),
                      trailing: const DisclosureChevron(),
                      onTap: () => _push((_) => const RecipesScreen()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.restaurant),
                      title: const Text('Eigene Rezepte und Meal-Prep'),
                      trailing: const DisclosureChevron(),
                      onTap: () =>
                          _push((_) => OwnRecipesScreen(log: (recipe, grams) => _logOwnRecipe(recipe, grams: grams))),
                    ),
                    ListTile(
                      leading: const Icon(Icons.local_drink_outlined),
                      title: const Text('Verpflegung'),
                      subtitle: const Text('Vor, während und nach dem Training'),
                      trailing: const DisclosureChevron(),
                      onTap: () => _push((_) => const FuelPlannerScreen()),
                    ),
                  ],
                ),
                FormSection(
                  header: 'Verlauf',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Woche und Auswertung'),
                      trailing: const DisclosureChevron(),
                      onTap: () => _push(
                        (_) => NutritionWeekScreen(
                          summary: _weekSummary,
                          weights: ref.read(appModelProvider).allWeights,
                          goal: settings.nutrition.goal,
                          review: ListenableBuilder(listenable: _controller, builder: (_, _) => _reviewSection()),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.monitor_weight_outlined),
                      title: const Text('Gewichtsverlauf'),
                      trailing: const DisclosureChevron(),
                      onTap: () => _push((_) => const WeightTrendScreen()),
                    ),
                  ],
                ),
                FormSection(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Übersicht anpassen'),
                      onTap: () => _push((_) => const NutritionDashboardEditor(), fullscreen: true),
                    ),
                    if (ref.watch(aiClientProvider).isConfigured)
                      ListTile(
                        leading: const Icon(Icons.move_to_inbox_outlined),
                        title: const Text('Geteilte Mahlzeit öffnen'),
                        onTap: () => _push((_) => const ReceivedMealScreen(), fullscreen: true),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (controller.isWorking)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [CircularProgressIndicator(), SizedBox(height: 12), Text('Wird ausgewertet …')],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (controller.lastLogged case final last?)
            _UndoBar(
              label: last.label,
              onUndo: () => _after(controller.undoLastLog()),
              onTimeout: controller.clearLastLogged,
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            height: 64,
            child: FloatingActionButton(
              tooltip: 'Erfassen',
              shape: const CircleBorder(),
              onPressed: _showLogger,
              child: const Icon(Icons.add, size: 32),
            ),
          ),
        ],
      ),
    );
  }

  /// Was beim Erfassen sofort bereitsteht: zuletzt, häufig, Rezepte, Favoriten.
  CaptureShortcuts get _captureShortcuts {
    final entries = MealRepository.entries(_meals);
    final category = NutritionController.category(DateTime.now());
    final settings = ref.read(coachSettingsProvider);
    return CaptureShortcuts(
      recent: MealShortcuts.recent(entries),
      frequent: MealShortcuts.frequent(entries, today: _controller.day),
      recipes: settings.ownRecipes,
      favorites: settings.favoriteMeals,
      log: (title, items) =>
          _after(_controller.log(title: title, category: category, items: items.map(MealPortion.restored).toList())),
      open: (title, items) => _controller.present(
        MealDraft(
          title: title,
          category: category,
          hint: '',
          items: [for (final item in items) MealPortion.restored(item)..id = newUuid()],
        ),
      ),
      logRecipe: _logOwnRecipe,
    );
  }

  /// Erfassen, Suche zuerst: Vorschläge zur Mahlzeit, Korb mit „+“, Eintragen in einem Schritt. Die anderen Wege
  /// (Scannen, KI mit Foto/Text, Nur kcal, Manuell) stehen dort als Reiter.
  /// Suche leeren und schließen (nach dem Eintragen eines Treffers).
  void _closeSearch() => setState(() {
    _query.clear();
    _searching = false;
  });

  /// Durchsuchbar in „Erfassen“: eigene Lebensmittel und alles, was in den letzten 60 Tagen eingetragen wurde (sonst
  /// verschwänden die Vorschläge beim Tippen, und „Brokkoli“ fände nur fremde Einträge).
  List<MealItem> _searchableFoods(MealCategory category) {
    final own = [for (final food in _foods) ?food.item];
    final names = {for (final item in own) FoodSearch.normalized(item.name)};
    final history = ProductSearch.picks(
      MealRepository.entries(_meals),
      category: category,
      today: _controller.day,
      limit: 500,
    );
    return [
      ...own,
      for (final item in history)
        if (names.add(FoodSearch.normalized(item.name))) item,
    ];
  }

  Future<void> _showLogger({MealCategory? category}) async {
    final chosen = category ?? NutritionController.category(DateTime.now());
    final result = await Navigator.of(context).push<FoodLogResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductSearchScreen(
          own: _searchableFoods(chosen),
          picks: ProductSearch.picks(MealRepository.entries(_meals), category: chosen, today: _controller.day),
          category: chosen,
          eaten: _controller.totals,
          targets: _controller.targets?.values,
        ),
      ),
    );
    if (!mounted) return;
    switch (result) {
      case FoodLogItems(:final items, :final category):
        final names = items.map((item) => item.name).toList();
        final title = names.length <= 2 ? names.join(', ') : '${names.take(2).join(', ')} +${names.length - 2}';
        await _after(_controller.log(title: title, category: category, items: items));
      case FoodLogOther(other: null):
        await _showCapture();
      case FoodLogOther(:final other?):
        await _handleOther(other);
      case null:
        await _reload();
    }
  }

  /// KI-Erfassung: Foto und Text zusammen, darunter Barcode, manuell und „Nur Kalorien“.
  Future<void> _showCapture() async {
    final result = await Navigator.of(context).push<CaptureResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => CaptureScreen(shortcuts: _captureShortcuts)),
    );
    if (!mounted) return;
    switch (result) {
      case CaptureAnalyze(:final text, :final photo):
        await _controller.analyze(text, photo: photo, foods: _foods);
        await _reload();
      case CaptureChoose(:final other):
        await _handleOther(other);
      case null:
        await _reload();
    }
  }

  Future<void> _handleOther(CaptureOther other) async {
    switch (other) {
      case CaptureOther.manual:
        _controller.newManualDraft();
      case CaptureOther.search:
        await _showLogger();
      case CaptureOther.barcode:
        final code = await Navigator.of(context)
            .push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BarcodeEntryScreen()));
        if (code != null) {
          await _controller.lookup(code, _foods);
          await _reload();
        }
      case CaptureOther.quick:
        final quick = await Navigator.of(context).push<(String, MealCategory, MealItem)>(
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QuickEntryScreen()),
        );
        if (quick != null) {
          await _after(_controller.log(title: quick.$1, category: quick.$2, items: [quick.$3]));
        }
    }
  }

  // Karten

  List<Widget> _dashboardCard(NutritionCard card) {
    final controller = _controller;
    final targets = controller.targets;
    switch (card) {
      case NutritionCard.budget:
        return [
          if (targets != null)
            _BudgetSection(
              targets: targets,
              totals: controller.totals,
              intake: controller.intake,
              adjustment: ref.read(coachSettingsProvider).nutrition.adjustmentOn(controller.day),
              onAdjust: (adjustment) {
                final settings = ref.read(coachSettingsProvider);
                settings.nutrition = settings.nutrition.copy()..setAdjustment(adjustment, day: controller.day);
                unawaited(_reload());
              },
            ),
        ];
      case NutritionCard.summary:
        final shown = _todaysMeals.where((meal) => !meal.isWater).length;
        return [
          _DaySummarySection(
            summary: NutritionDaySummary(
              eaten: controller.totals[Nutrient.kcal] ?? 0,
              goal: targets?.values[Nutrient.kcal],
              meals: shown,
            ),
            totals: controller.totals,
            targets: targets?.values,
          ),
        ];
      case NutritionCard.water:
        final target = targets?.values[Nutrient.water];
        return [if (target != null) _WaterSection(water: _water, target: target, onAdd: _logWater)];
      case NutritionCard.ideas:
        return [
          if (targets != null && controller.day == controller.today)
            FormSection(
              footer: 'Drei Ideen passend zu dem, was heute noch übrig ist – gern mit deinem Vorrat.',
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Was esse ich jetzt?', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: _showNow,
                ),
              ],
            ),
        ];
      case NutritionCard.quick:
        return [_quickSection()];
      case NutritionCard.meals:
        return _mealsSection();
      case NutritionCard.nutrients:
        return [if (targets != null) _TargetsSection(targets: targets, intake: controller.intake)];
    }
  }

  Future<void> _showNow() async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MealNowScreen(
          controller: _controller,
          pantry: ref.read(coachSettingsProvider).pantry,
          generate: () => _controller.suggestNow(_foods),
        ),
      ),
    );
    if (recipe != null) _controller.draftFromRecipe(recipe);
  }

  /// Woche des gewählten Tages: Energie gegen das Ziel, Protein, Trainingstage.
  NutritionWeekSummary get _weekSummary {
    final day = _controller.day;
    final monday = day.adding(-day.weekdayIndex);
    final settings = ref.read(coachSettingsProvider);
    final profile = ref.read(appModelProvider).sync.profile;
    return NutritionWeek.summary(
      entries: MealRepository.entries(_meals),
      monday: monday,
      targets: {
        for (var offset = 0; offset < 7; offset++)
          monday.adding(offset): NutritionController.targetsFor(
            monday.adding(offset),
            activities: _activities,
            settings: settings,
            profile: profile,
            hasGarminData: _days.isNotEmpty,
          ).values,
      },
      trainedDays: {for (final activity in _activities) ?activity.day},
      today: _controller.today,
    );
  }

  Future<void> _push(Widget Function(BuildContext context) builder, {bool fullscreen = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: fullscreen, builder: builder));
    if (mounted) await _reload();
  }

  Widget _quickSection() {
    final entries = MealRepository.entries(_meals);
    final category = NutritionController.category(DateTime.now());
    final day = _controller.day;
    final suggestions = MealSuggestions.frequent(entries, category: category, today: day, limit: 4);
    final yesterday = MealSuggestions.yesterday(entries, category: category, today: day);
    final stock = [
      for (final recipe in ref.read(coachSettingsProvider).ownRecipes)
        if ((recipe.remainingPortions ?? 0) >= 0.5) recipe,
    ];
    if (suggestions.isEmpty && yesterday.isEmpty && stock.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: 'Schnell: ${category.label}',
      children: [
        for (final recipe in stock)
          _QuickRow(
            title: '${recipe.name} · noch ${PortionGuess.format(recipe.remainingPortions ?? 0)} Portionen',
            detail: mealSummary([recipe.item()]),
            onAdd: () => _logOwnRecipe(recipe),
          ),
        if (yesterday.isNotEmpty)
          _QuickRow(
            title: 'Wie gestern: ${yesterday.map((entry) => entry.title).join(', ')}',
            detail: mealSummary([for (final entry in yesterday) ...entry.items]),
            onAdd: () => _after(
              _controller.log(
                title: yesterday.map((entry) => entry.title).join(', '),
                category: category,
                items: [for (final entry in yesterday) ...entry.items],
                label: '${category.label} wie gestern eingetragen',
              ),
            ),
          ),
        for (final suggestion in suggestions)
          _QuickRow(
            title: suggestion.title,
            detail: mealSummary(suggestion.items),
            onAdd: () => _after(_controller.log(title: suggestion.title, category: category, items: suggestion.items)),
          ),
      ],
    );
  }

  /// Portion (oder Gramm) vom Topf eintragen und den Vorrat verringern.
  Future<void> _logOwnRecipe(OwnRecipe recipe, {double? grams}) async {
    final item = recipe.item(grams: grams);
    await _after(
      _controller.log(title: recipe.name, category: NutritionController.category(DateTime.now()), items: [item]),
    );
    final settings = ref.read(coachSettingsProvider);
    settings.ownRecipes = [
      for (final other in settings.ownRecipes)
        if (other.id == recipe.id) (other..consume(item.grams)) else other,
    ];
  }

  /// Mahlzeiten nach Kategorie mit Summe je Kategorie; Wasser steht beim Wasser-Balken.
  List<Widget> _mealsSection() {
    final shown = _todaysMeals.where((meal) => !meal.isWater).toList();
    return [
      if (shown.isEmpty)
        const FormSection(
          header: 'Mahlzeiten',
          children: [
            ListTile(title: Text('Noch nichts erfasst. Oben ein Vorschlag mit einem Tipp – oder über „+“ eintragen.')),
          ],
        ),
      for (final category in MealCategory.values)
        if (shown.where((meal) => meal.category == category).toList() case final items when items.isNotEmpty)
          FormSection(
            header:
                '${category.label} · ${(NutritionSummary.totals([for (final meal in items) ...meal.items])[Nutrient.kcal] ?? 0).round()} kcal',
            children: [
              for (final meal in items)
                Dismissible(
                  key: ValueKey(meal.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: AppColors.of(context).alert,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: AppPalette.onColor),
                  ),
                  onDismissed: (_) => _after(_controller.delete(meal)),
                  child: _MealRow(
                    meal: meal,
                    onTap: () => _controller.edit(meal),
                    onLongPress: () => _mealActions(meal),
                  ),
                ),
            ],
          ),
    ];
  }
}

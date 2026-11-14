import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';
import 'bls_views.dart';
import 'capture_views.dart';
import 'meal_editor.dart';
import 'meal_shortcuts.dart';
import 'nutrition_controller.dart';

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

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
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
  }

  @override
  void dispose() {
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
    final settings = ref.watch(coachSettingsProvider);
    final controller = _controller;
    final isToday = controller.day == controller.today;
    final searching = _query.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Lebensmittel oder Mahlzeit suchen',
                  border: InputBorder.none,
                ),
              )
            : Text(isToday ? 'Ernährung' : DateFormat('EEE, d. MMM', 'de_DE').format(controller.day.referenceDate)),
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
                  _DayStrip(
                    selected: controller.day,
                    today: controller.today,
                    onSelect: (day) {
                      controller.selectedDay = day == controller.today ? null : day;
                      unawaited(_reload());
                    },
                  ),
                  if (controller.pending.isNotEmpty) _pendingSection(),
                  if (_showsCheckIn) _checkInSection(),
                  for (final card in settings.nutritionDashboard.visible) ..._dashboardCard(card),
                ],
                if (DateTime.now().hour >= 18 || controller.reviewPoints.isNotEmpty) _reviewSection(),
                FormSection(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Übersicht anpassen'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => const NutritionDashboardEditor(),
                        ),
                      ),
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
              onPressed: _showCapture,
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

  /// Erfassen: Foto und Text zusammen, darunter Barcode, manuell und „Nur Kalorien“.
  Future<void> _showCapture() async {
    final result = await Navigator.of(context).push<CaptureResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => CaptureScreen(shortcuts: _captureShortcuts)),
    );
    if (!mounted) return;
    switch (result) {
      case CaptureAnalyze(:final text, :final photo):
        await _controller.analyze(text, photo: photo, foods: _foods);
        await _reload();
      case CaptureChoose(other: CaptureOther.manual):
        _controller.newManualDraft();
      case CaptureChoose(other: CaptureOther.barcode):
        final code = await Navigator.of(context)
            .push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BarcodeEntryScreen()));
        if (code != null) {
          await _controller.lookup(code, _foods);
          await _reload();
        }
      case CaptureChoose(other: CaptureOther.quick):
        final quick = await Navigator.of(context).push<(String, MealCategory, MealItem)>(
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QuickEntryScreen()),
        );
        if (quick != null) {
          await _after(_controller.log(title: quick.$1, category: quick.$2, items: [quick.$3]));
        }
      case null:
        await _reload();
    }
  }

  // Karten

  List<Widget> _dashboardCard(NutritionCard card) {
    final controller = _controller;
    final targets = controller.targets;
    switch (card) {
      case NutritionCard.budget:
        return [if (targets != null) _BudgetSection(targets: targets, totals: controller.totals)];
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
        return [if (targets != null) _TargetsSection(targets: targets, totals: controller.totals)];
    }
  }

  Future<void> _showNow() async {
    await _controller.suggestNow(_foods);
    if (!mounted) return;
    final recipe = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final note in _controller.nowNotes)
              ListTile(leading: const Icon(Icons.info_outline), title: Text(note)),
            for (final recipe in _controller.nowSuggestions)
              ListTile(
                title: Text(recipe.title),
                subtitle: Text(mealSummary(recipe.ingredients)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(recipe),
              ),
          ],
        ),
      ),
    );
    if (recipe != null) _controller.draftFromRecipe(recipe);
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
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
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

  Future<void> _mealActions(StoredMeal meal) async {
    final settings = ref.read(coachSettingsProvider);
    final favorite = MealShortcuts.favorite(meal.items, favorites: settings.favoriteMeals);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Erneut eintragen'),
              onTap: () {
                Navigator.of(sheet).pop();
                _after(_controller.repeatMeal(meal));
              },
            ),
            for (final target in MealCategory.values.where((category) => category != meal.category))
              ListTile(
                leading: const Icon(Icons.swap_vert),
                title: Text('Verschieben nach ${target.label}'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _after(_controller.move(meal, target));
                },
              ),
            ListTile(
              leading: const Icon(Icons.pie_chart_outline),
              title: const Text('Gegessene Menge anpassen'),
              onTap: () {
                Navigator.of(sheet).pop();
                _controller.edit(meal);
              },
            ),
            if (favorite != null)
              ListTile(
                leading: const Icon(Icons.star_border),
                title: const Text('Aus Favoriten entfernen'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  settings.favoriteMeals = settings.favoriteMeals.where((other) => other.id != favorite.id).toList();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text('Als Favorit merken'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  settings.favoriteMeals = [
                    ...settings.favoriteMeals,
                    FavoriteMeal(title: meal.title, items: meal.items, category: meal.category),
                  ];
                },
              ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('Als eigenes Rezept speichern'),
              subtitle: const Text('Unter „Eigene Rezepte“ Portionen und gekochtes Gewicht für Meal-Prep festlegen.'),
              onTap: () {
                Navigator.of(sheet).pop();
                settings.ownRecipes = [...settings.ownRecipes, OwnRecipe.fromMeal(meal.title, meal.items)];
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Löschen', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(sheet).pop();
                _after(_controller.delete(meal));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingSection() => FormSection(
    header: 'Wartet auf Netz',
    footer: 'Ohne Netz gespeichert. Wird automatisch ausgewertet, sobald die App wieder online ist.',
    children: [
      for (final item in _controller.pending)
        Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(color: Colors.red),
          onDismissed: (_) => _controller.removePending(item),
          child: ListTile(
            leading: Icon(item.hasPhoto ? Icons.photo_outlined : Icons.chat_bubble_outline),
            title: Text(item.text.isEmpty ? 'Foto' : item.text, maxLines: 1),
            trailing: Text(DateFormat.Hm('de_DE').format(item.created.toLocal())),
          ),
        ),
      ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Jetzt auswerten'),
        onTap: () => _after(_controller.retryPending(_foods)),
      ),
    ],
  );

  Widget _checkInSection() => FormSection(
    header: 'Wochen-Check-in',
    footer:
        'Einmal pro Woche: Passt dein Verlauf zum Ziel? Falls nicht, schlägt die App eine Anpassung der Tagesziele vor '
        '– sie ändert nichts ohne dein OK.',
    children: [
      ListTile(
        title: const Text('Diese Woche überspringen'),
        onTap: () {
          final settings = ref.read(coachSettingsProvider);
          settings.nutrition = settings.nutrition.copy()..lastCheckInDay = _controller.today;
        },
      ),
    ],
  );

  Widget _reviewSection() {
    final ai = ref.watch(aiClientProvider);
    final controller = _controller;
    return FormSection(
      header: 'KI-Auswertung',
      footer: controller.reviewModel != null
          ? 'KI · ${controller.reviewModel}. Schätzungen – Nährwerte aus Fotos können deutlich abweichen.'
          : (!ai.isConfigured ? 'Dafür den KI-Worker in den Einstellungen einrichten.' : null),
      children: [
        for (final point in controller.reviewPoints) ListTile(title: Text(point)),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Ernährung und Training auswerten'),
          enabled: !controller.isWorking && ai.allows('nutrition_review'),
          onTap: () => controller.review(meals: _meals, activities: _activities, recovery: _recoveryText),
        ),
        if (controller.reviewPoints.isNotEmpty)
          EvidenceDisclosure(ruleIDs: [...controller.reviewSources, ...NutritionController.reviewEvidence]),
      ],
    );
  }

  // Suche

  /// Eigene Lebensmittel und frühere Mahlzeiten; Antippen öffnet den Entwurf, „+“ trägt sofort ein.
  List<Widget> _searchResults() {
    final query = _query.text;
    final entries = MealRepository.entries(_meals);
    final groups = <String, List<MealEntry>>{};
    for (final entry in entries.where((entry) => entry.items.length > 1)) {
      (groups[FoodSearch.normalized(entry.title)] ??= []).add(entry);
    }
    MealEntry latest(List<MealEntry> group) => group.reduce((a, b) => b.date.isAfter(a.date) ? b : a);
    final mealCandidates = [
      for (final MapEntry(:key, value: group) in groups.entries)
        FoodSearchCandidate(
          id: 'meal:$key',
          title: latest(group).title,
          useCount: group.length,
          lastUsed: latest(group).date,
        ),
    ];
    final foundFoods = FoodSearch.rank([for (final food in _foods) food.candidate], query: query);
    final foundMeals = FoodSearch.rank(mealCandidates, query: query, limit: 6);
    final foundBLS = query.runes.length >= 3 ? BLS.search(query, limit: 8) : const <BLSFood>[];
    final category = NutritionController.category(DateTime.now());
    void done() => setState(() {
      _query.clear();
      _searching = false;
    });
    return [
      if (foundFoods.isEmpty && foundMeals.isEmpty && foundBLS.isEmpty)
        const FormSection(children: [ListTile(title: Text('Nichts gefunden. Über „+“ eintragen.'))]),
      if (foundMeals.isNotEmpty)
        FormSection(
          header: 'Frühere Mahlzeiten',
          children: [
            for (final candidate in foundMeals)
              if (groups[candidate.id.substring(5)] case final group?)
                _QuickRow(
                  title: latest(group).title,
                  detail: mealSummary(latest(group).items),
                  onAdd: () {
                    _after(_controller.log(title: latest(group).title, category: category, items: latest(group).items));
                    done();
                  },
                ),
          ],
        ),
      if (foundFoods.isNotEmpty)
        FormSection(
          header: 'Lebensmittel',
          children: [
            for (final candidate in foundFoods)
              if (_foods.where((food) => food.candidate.id == candidate.id).firstOrNull?.item case final item?)
                _QuickRow(
                  title: item.name,
                  detail: mealSummary([item]),
                  onAdd: () {
                    _after(_controller.log(title: item.name, category: category, items: [item]));
                    done();
                  },
                  onOpen: () {
                    _controller.draftWithItem(item);
                    done();
                  },
                ),
          ],
        ),
      if (foundBLS.isNotEmpty)
        FormSection(
          header: 'Bundeslebensmittelschlüssel',
          footer: 'Öffnet den Entwurf mit 100 g. Quelle: ${BLS.attribution}.',
          children: [
            for (final food in foundBLS)
              _QuickRow(
                title: food.name,
                detail: blsSummary(food.per100g),
                onAdd: () {
                  _controller.draftWithItem(food.item());
                  done();
                },
              ),
          ],
        ),
    ];
  }
}

/// Wochenstreifen: Tag antippen zum Ansehen und Nachtragen.
class _DayStrip extends StatefulWidget {
  const _DayStrip({required this.selected, required this.today, required this.onSelect});

  final CalendarDay selected;
  final CalendarDay today;
  final ValueChanged<CalendarDay> onSelect;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = widget.today;
    final monday = today.adding(-today.weekdayIndex + _weekOffset * 7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Vorige Woche',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _weekOffset -= 1),
          ),
          for (var offset = 0; offset < 7; offset++)
            Expanded(
              child: () {
                final day = monday.adding(offset);
                final future = today < day;
                return Semantics(
                  label: DateFormat('EEEE, d. MMMM', 'de_DE').format(day.referenceDate),
                  selected: day == widget.selected,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: future ? null : () => widget.onSelect(day),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: day == widget.selected ? scheme.primary.withValues(alpha: 0.2) : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(Weekday.of(day).short, style: const TextStyle(fontSize: 11)),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: future ? scheme.onSurfaceVariant.withValues(alpha: 0.5) : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
            ),
          IconButton(
            tooltip: 'Nächste Woche',
            icon: const Icon(Icons.chevron_right),
            onPressed: _weekOffset >= 0 ? null : () => setState(() => _weekOffset += 1),
          ),
        ],
      ),
    );
  }
}

/// Auf einen Blick: übrige kcal im Ring, Protein/KH/Fett als „noch … g“.
class _BudgetSection extends StatelessWidget {
  const _BudgetSection({required this.targets, required this.totals});

  final NutritionTargets targets;
  final NutrientValues totals;

  @override
  Widget build(BuildContext context) {
    final kcal = NutritionBudget.line(Nutrient.kcal, targets: targets.values, totals: totals);
    return FormSection(
      header: '${targets.dayType.label} · ${targets.source.rawValue}',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (kcal != null) _CalorieRing(line: kcal),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    for (final nutrient in NutritionBudget.main)
                      if (NutritionBudget.line(nutrient, targets: targets.values, totals: totals) case final line?)
                        _MacroBar(line: line),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalorieRing extends StatelessWidget {
  const _CalorieRing({required this.line});

  final BudgetLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = line.remaining.abs().round();
    return Semantics(
      label: '$amount Kilokalorien ${line.remaining >= 0 ? 'übrig' : 'über dem Ziel'}',
      excludeSemantics: true,
      child: SizedBox(
        width: 112,
        height: 112,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: line.progress,
                strokeWidth: 12,
                strokeCap: StrokeCap.round,
                backgroundColor: scheme.surfaceContainerHighest,
                color: line.isOver ? Colors.red : scheme.primary,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$amount', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  line.remaining >= 0 ? 'kcal übrig' : 'kcal drüber',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.line});

  final BudgetLine line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(line.nutrient.label),
            const Spacer(),
            Text(
              NutritionBudget.remainingText(line),
              style: TextStyle(fontWeight: FontWeight.bold, color: line.isOver ? Colors.red : null),
            ),
          ],
        ),
        const SizedBox(height: 3),
        LinearProgressIndicator(value: line.progress, color: line.isOver ? Colors.red : null),
      ],
    ),
  );
}

/// Wasser mit Glas-Knopf: Antippen +250 ml, gedrückt halten für andere Mengen.
class _WaterSection extends StatelessWidget {
  const _WaterSection({required this.water, required this.target, required this.onAdd});

  final HydrationTotal water;
  final double target;
  final ValueChanged<double> onAdd;

  @override
  Widget build(BuildContext context) => FormSection(
    children: [
      ListTile(
        leading: const Icon(Icons.water_drop, color: Colors.cyan),
        title: Text('Wasser ${GermanFormat.decimal(water.total / 1000)} / ${GermanFormat.decimal(target / 1000)} l'),
        subtitle: water.food >= 50 ? Text('davon ${GermanFormat.decimal(water.food / 1000)} l aus Essen') : null,
        trailing: GestureDetector(
          onLongPress: () async {
            final box = context.findRenderObject()! as RenderBox;
            final position = box.localToGlobal(Offset(box.size.width, 0));
            final amount = await showMenu<double>(
              context: context,
              position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
              items: [
                for (final amount in const [150.0, 330.0, 500.0, 750.0])
                  PopupMenuItem(value: amount, child: Text('${amount.round()} ml')),
              ],
            );
            if (amount != null) onAdd(amount);
          },
          child: Semantics(
            hint: 'Gedrückt halten für andere Mengen',
            child: FilledButton.tonalIcon(
              onPressed: () => onAdd(250),
              icon: const Icon(Icons.add),
              label: const Text('+250 ml'),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Tagesübersicht als Kacheln: gegessen, Ziel, übrig, Fortschritt, Mahlzeiten und Makros.
class _DaySummarySection extends StatelessWidget {
  const _DaySummarySection({required this.summary, required this.totals, required this.targets});

  final NutritionDaySummary summary;
  final NutrientValues totals;
  final NutrientValues? targets;

  @override
  Widget build(BuildContext context) {
    final remaining = summary.remaining;
    final tiles = [
      ('Gegessen', '${summary.eaten.round()}', 'kcal'),
      ('Ziel', summary.goal == null ? '–' : '${summary.goal!.round()}', 'kcal'),
      ((remaining ?? 0) >= 0 ? 'Übrig' : 'Drüber', remaining == null ? '–' : '${remaining.abs().round()}', 'kcal'),
      ('Fortschritt', summary.percent?.toString() ?? '–', '%'),
      ('Mahlzeiten', '${summary.meals}', 'erfasst'),
      for (final nutrient in const [Nutrient.protein, Nutrient.carbs, Nutrient.fat])
        (
          nutrient.label,
          '${(totals[nutrient] ?? 0).round()}',
          targets?[nutrient] == null ? 'g' : 'von ${targets![nutrient]!.round()} g',
        ),
    ];
    final scheme = Theme.of(context).colorScheme;
    return FormSection(
      header: 'Tagesübersicht',
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (title, value, unit) in tiles)
                Container(
                  width: 96,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 1),
                      Text(unit, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), maxLines: 1),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Alle Nährstoffe mit Ziel – aufklappbar, damit oben nur das Wichtige steht.
class _TargetsSection extends StatelessWidget {
  const _TargetsSection({required this.targets, required this.totals});

  static const primary = [
    Nutrient.kcal,
    Nutrient.protein,
    Nutrient.carbs,
    Nutrient.fat,
    Nutrient.fiber,
    Nutrient.water,
  ];

  final NutritionTargets targets;
  final NutrientValues totals;

  static String format(double value) => value >= 10 ? '${value.round()}' : GermanFormat.decimal(value);

  @override
  Widget build(BuildContext context) {
    final order = [...primary, ...Nutrient.values.where((nutrient) => !primary.contains(nutrient))];
    final reference = targets.referenceWeightKilograms < targets.profile.weightKilograms
        ? ' (bezogen auf ${GermanFormat.number(targets.referenceWeightKilograms.roundToDouble())} kg).'
        : '.';
    return FormSection(
      footer:
          'Grundumsatz ${targets.basalMetabolicRate.toInt()} kcal, Training ${targets.exerciseKilocalories.toInt()} kcal, '
          'Protein ${GermanFormat.decimal(targets.proteinPerKilogram)} g/kg$reference'
          '${targets.energyAvailabilityFloorApplied ? ' Energie auf Mindestverfügbarkeit angehoben.' : ''}',
      children: [
        ExpansionTile(
          title: const Text('Alle Nährstoffe'),
          children: [
            for (final nutrient in order)
              () {
                final actual = totals[nutrient];
                final target = targets.values[nutrient];
                final percent = NutritionSummary.percent(actual, target);
                final actualText = (target ?? 0) >= 10 ? '${(actual ?? 0).round()}' : format(actual ?? 0);
                return ListTile(
                  title: Text(nutrient.label),
                  trailing: Text('$actualText / ${target == null ? '–' : format(target)} ${nutrient.unit}'),
                  subtitle: percent == null
                      ? null
                      : LinearProgressIndicator(
                          value: (percent > 100 ? 100 : percent) / 100,
                          color: nutrient.isUpperLimit
                              ? (percent > 100 ? Colors.red : Colors.orange)
                              : (percent >= 100 ? Colors.green : null),
                        ),
                );
              }(),
          ],
        ),
      ],
    );
  }
}

/// Zeile mit großem „+“ (sofort eintragen); optional öffnet Antippen den Entwurf.
class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.title, required this.detail, required this.onAdd, this.onOpen});

  final String title;
  final String detail;
  final VoidCallback onAdd;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, maxLines: 2),
    subtitle: Text(detail),
    onTap: onOpen ?? onAdd,
    trailing: IconButton(
      tooltip: '$title eintragen',
      iconSize: 32,
      icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
      onPressed: onAdd,
    ),
  );
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.onTap, required this.onLongPress});

  final StoredMeal meal;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final totals = NutritionSummary.totals(meal.items);
    return ListTile(
      title: Text(meal.title, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text('${(totals[Nutrient.kcal] ?? 0).round()} kcal'),
      subtitle: Text(
        '${meal.category.label} · Protein ${(totals[Nutrient.protein] ?? 0).round()} g · '
        'KH ${(totals[Nutrient.carbs] ?? 0).round()} g · Fett ${(totals[Nutrient.fat] ?? 0).round()} g',
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// „Rückgängig“ nach einem Schnell-Eintrag; verschwindet nach 5 Sekunden.
class _UndoBar extends StatefulWidget {
  const _UndoBar({required this.label, required this.onUndo, required this.onTimeout});

  final String label;
  final VoidCallback onUndo;
  final VoidCallback onTimeout;

  @override
  State<_UndoBar> createState() => _UndoBarState();
}

class _UndoBarState extends State<_UndoBar> {
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), widget.onTimeout);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_UndoBar old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    shape: const StadiumBorder(),
    child: Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 120, minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            TextButton(
              onPressed: widget.onUndo,
              child: const Text('Rückgängig', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// „Nur Kalorien“: Restaurant, Kantine, unterwegs – Schätzung ohne Lebensmittel.
class QuickEntryScreen extends StatefulWidget {
  const QuickEntryScreen({super.key});

  @override
  State<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends State<QuickEntryScreen> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  MealCategory _category = NutritionController.category(DateTime.now());

  @override
  void initState() {
    super.initState();
    _kcal.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final controller in [_name, _kcal, _protein, _carbs, _fat]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _number(String label, String unit, TextEditingController controller) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: unit),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kcal = parseNumber(_kcal.text) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nur Kalorien'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: kcal <= 0
                ? null
                : () {
                    final title = _name.text.trim().isEmpty ? 'Schnell-Eintrag' : _name.text.trim();
                    final item = QuickMealItem.quick(
                      name: title,
                      kilocalories: kcal,
                      protein: parseNumber(_protein.text),
                      carbs: parseNumber(_carbs.text),
                      fat: parseNumber(_fat.text),
                    );
                    Navigator.of(context).pop((title, _category, item));
                  },
            child: const Text('Eintragen'),
          ),
        ],
      ),
      body: ListView(
        children: [
          FormSection(
            footer: 'Nur Kalorien reichen; Makros helfen bei der Tagesbilanz. Wird als Schätzung markiert.',
            children: [
              _number('Kalorien', 'kcal', _kcal),
              _number('Protein', 'g', _protein),
              _number('Kohlenhydrate', 'g', _carbs),
              _number('Fett', 'g', _fat),
            ],
          ),
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Was war es? (optional)'),
                ),
              ),
              ListTile(
                title: const Text('Mahlzeit'),
                trailing: DropdownButton<MealCategory>(
                  value: _category,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final category in MealCategory.values)
                      DropdownMenuItem(value: category, child: Text(category.label)),
                  ],
                  onChanged: (category) => setState(() => _category = category ?? _category),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Karten ein- und ausblenden und sortieren.
class NutritionDashboardEditor extends ConsumerWidget {
  const NutritionDashboardEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final dashboard = settings.nutritionDashboard;
    void change(void Function(NutritionDashboard value) update) {
      final copy = NutritionDashboard.fromJson(dashboard.toJson());
      update(copy);
      settings.nutritionDashboard = copy;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Übersicht anpassen'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView(
              onReorderItem: (from, to) =>
                  change((value) => value.move(fromOffsets: {from}, toOffset: to > from ? to + 1 : to)),
              children: [
                for (final card in dashboard.order)
                  SwitchListTile(
                    key: ValueKey(card),
                    secondary: const Icon(Icons.drag_handle),
                    title: Text(card.label),
                    value: !dashboard.hidden.contains(card),
                    onChanged: (visible) => change((value) => value.setVisible(card, visible: visible)),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Ziehen zum Sortieren. Ausgeblendete Karten bleiben hier und lassen sich jederzeit wieder einschalten.',
            ),
          ),
          TextButton(
            onPressed: () => settings.nutritionDashboard = NutritionDashboard(),
            child: const Text('Standard wiederherstellen'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

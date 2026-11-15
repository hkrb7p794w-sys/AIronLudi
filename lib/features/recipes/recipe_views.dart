import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/user_providers.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../activities/activity_parts.dart';
import '../evidence/evidence_views.dart';
import '../nutrition/meal_editor.dart';
import '../nutrition/nutrition_controller.dart';
import '../today/now_views.dart';
import 'cook_plan_views.dart';
import 'pantry_views.dart';
import 'recipe_controller.dart';

int _rounded(double? value) => (value ?? 0).round();

/// Rezeptideen für einen frei gewählten Zeitraum, passend zu Zielen und Ernährungsweise; dazu die Einkaufsliste (Port
/// von `RecipesView`).
class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  late final RecipeController _controller = RecipeController(
    store: ref.read(settingsStoreProvider),
    folder: ref.read(userDirectoryProvider),
  )..addListener(_changed);
  List<StoredMeal> _meals = const [];
  List<StoredFood> _foods = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final repository = ref.read(mealRepositoryProvider);
    final results = await (repository.all(), repository.foods()).wait;
    if (!mounted) return;
    _meals = results.$1;
    _foods = results.$2;
    _update();
  }

  void _update() => _controller.update(
    settings: ref.read(coachSettingsProvider),
    garminProfile: ref.read(garminSyncServiceProvider).profile,
    meals: _meals,
  );

  Future<void> _generate({bool missingOnly = false}) => _controller.generate(
    ai: ref.read(aiClientProvider),
    settings: ref.read(coachSettingsProvider),
    favorites: [for (final food in _foods.take(15)) food.name],
    missingOnly: missingOnly,
  );

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _controller.start.referenceDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) return;
    _controller.setPeriod(start: CalendarDay.fromDate(picked), days: _controller.length);
    _update();
  }

  void _setLength(int days) {
    _controller.setPeriod(start: _controller.start, days: days);
    _update();
  }

  @override
  Widget build(BuildContext context) {
    // Ziele hängen an Profil, Plan und Ernährungszielen.
    ref.listen(coachSettingsProvider, (_, _) => _update());
    final controller = _controller;
    final plan = controller.plan;
    final first = controller.targets.firstOrNull;
    final last = controller.targets.lastOrNull;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Rezeptideen')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              FormSection(
                footer:
                    'Aus dem Kühlschrank: Foto machen, die KI schlägt passende Gerichte vor und fragt nach, wenn nur '
                    'Kleinigkeiten wie Butter oder Milch fehlen.',
                children: [
                  ListTile(
                    leading: const Icon(Icons.kitchen_outlined),
                    title: const Text('Was koche ich daraus? (Foto)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => const PantryRecipesScreen())),
                  ),
                ],
              ),
              FormSection(
                footer: 'Für dich, eine verbundene Person oder euch beide; auch zum Vorkochen für mehrere Tage.',
                children: [
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Kochen planen: für wen, wie viel'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CookPlanScreen(
                          recipes: controller,
                          favorites: [for (final food in _foods.take(10)) food.name],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              FormSection(
                children: [
                  ListTile(title: const Text('Ab'), trailing: Text(formatDay(controller.start)), onTap: _pickStart),
                  ListTile(
                    title: Text('${controller.length} ${controller.length == 1 ? 'Tag' : 'Tage'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Weniger',
                          icon: const Icon(Icons.remove),
                          onPressed: controller.length > 1 ? () => _setLength(controller.length - 1) : null,
                        ),
                        IconButton(
                          tooltip: 'Mehr',
                          icon: const Icon(Icons.add),
                          onPressed: controller.length < RecipePlanner.maxPeriodDays
                              ? () => _setLength(controller.length + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (first != null && last != null)
                    ListTile(
                      title: Text(
                        first.day == last.day
                            ? formatDay(first.day)
                            : '${shortDate(first.day)} – ${shortDate(last.day)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Ziel je Tag: ${first.kcal.toInt()} kcal, ${first.protein.toInt()} g Protein, '
                        '${first.carbs.toInt()} g KH – der Durchschnitt deiner Woche, an jedem Tag gleich. Die KI '
                        'schlägt Gerichte vor; die App prüft Ernährungsweise und Allergene und passt die Mengen an.',
                      ),
                    ),
                  ListTile(
                    enabled: !controller.isWorking,
                    leading: const Icon(Icons.auto_awesome),
                    title: Text(plan == null ? 'Rezeptideen erstellen' : 'Neu erstellen'),
                    textColor: Theme.of(context).colorScheme.primary,
                    onTap: _generate,
                  ),
                  if (plan != null && controller.missing.isNotEmpty)
                    ListTile(
                      enabled: !controller.isWorking,
                      leading: const Icon(Icons.add_circle_outline),
                      title: Text('Fehlende Tage erstellen (${controller.missing.length})'),
                      onTap: () => _generate(missingOnly: true),
                    ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Wünsche und Allergene'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const RecipePreferencesScreen()),
                    ),
                  ),
                  if (controller.errorMessage case final error?)
                    ListTile(
                      title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.red)),
                    ),
                ],
              ),
              if (controller.gaps.isNotEmpty)
                FormSection(
                  header: 'Wird gezielt ausgeglichen',
                  footer: 'Aus deinen erfassten Mahlzeiten der letzten 14 Tage (unter 80 % des Ziels).',
                  children: [for (final gap in controller.gaps) ListTile(dense: true, title: Text(gap))],
                ),
              if (plan != null) ...[
                if (plan.notes.isNotEmpty)
                  FormSection(
                    header: 'Prüfung',
                    children: [
                      for (final note in plan.notes)
                        ListTile(dense: true, leading: const Icon(Icons.verified_user_outlined), title: Text(note)),
                    ],
                  ),
                for (final target in controller.targets) _RecipeDaySection(target: target, day: plan.day(target.day)),
                FormSection(
                  footer:
                      'Quelle: ${plan.source}. Nährwerte der Zutaten sind KI-Schätzungen wie bei der Mahlzeiten-Analyse.',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.shopping_cart_outlined),
                      title: const Text('Einkaufsliste für den Zeitraum'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => ShoppingListScreen(controller: controller))),
                    ),
                  ],
                ),
              ],
              const FormSection(children: [EvidenceDisclosure(ruleIDs: RecipePlanner.evidence)]),
              if (plan == null && !controller.isWorking)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Noch keine Rezeptideen für diesen Zeitraum.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary),
                  ),
                ),
            ],
          ),
          if (controller.isWorking)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 12,
                    children: [
                      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      Text('Rezepte werden erstellt …', style: TextStyle(color: secondary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecipeDaySection extends StatelessWidget {
  const _RecipeDaySection({required this.target, required this.day});

  final RecipeDayTarget target;
  final RecipeDay? day;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: formatDay(target.day),
      children: [
        if (day == null)
          ListTile(
            title: Text(
              'Für diesen Tag gibt es noch keine Rezepte – oben „Fehlende Tage erstellen“.',
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          )
        else ...[
          for (final recipe in day.recipes)
            ListTile(
              title: Text(recipe.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${recipe.meal.label} · ${recipe.minutes} min · ${_rounded(recipe.totals[Nutrient.kcal])} kcal · '
                '${_rounded(recipe.totals[Nutrient.protein])} g Protein',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => RecipeDetailScreen(recipe: recipe))),
            ),
          ListTile(
            dense: true,
            title: Text(
              'Summe: ${_rounded(day.totals[Nutrient.kcal])} kcal, ${_rounded(day.totals[Nutrient.protein])} g Protein'
              '${day.scale == 1 ? '' : ' · Mengen ×${GermanFormat.number(day.scale)}'}',
              style: TextStyle(color: secondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ein Rezept mit Zutaten und Schritten; „Als Mahlzeit eintragen …“ öffnet den Entwurf (Port von `RecipeDetailView`).
class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipe});

  final Recipe recipe;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  /// Erst beim Eintragen angelegt (nicht in `dispose`, dort ist `ref` nicht mehr nutzbar).
  NutritionController? _nutritionController;

  NutritionController get _nutrition => _nutritionController ??= NutritionController(
    meals: ref.read(mealRepositoryProvider),
    settings: ref.read(coachSettingsProvider),
    ai: ref.read(aiClientProvider),
    openFoodFacts: ref.read(openFoodFactsProvider),
  );
  bool _logged = false;

  @override
  void dispose() {
    _nutritionController?.dispose();
    super.dispose();
  }

  Future<void> _log() async {
    final recipe = widget.recipe;
    final draft = MealDraft(
      title: recipe.title,
      category: NutritionController.category(DateTime.now()),
      hint: 'Aus Rezeptidee (Nährwerte KI-geschätzt)',
      items: recipe.ingredients,
    );
    _nutrition.present(draft);
    final foods = await ref.read(mealRepositoryProvider).foods();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MealEditorScreen(draft: draft, controller: _nutrition, foods: foods),
      ),
    );
    if (_nutrition.lastSaved != null && mounted) setState(() => _logged = true);
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final totals = recipe.totals;
    return Scaffold(
      appBar: AppBar(title: Text(recipe.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              LabeledRow(label: 'Mahlzeit', value: recipe.meal.label),
              LabeledRow(label: 'Zubereitung', value: '${recipe.minutes} min'),
              LabeledRow(label: 'Energie', value: '${_rounded(totals[Nutrient.kcal])} kcal'),
              LabeledRow(
                label: 'Protein · KH · Fett',
                value: [
                  for (final nutrient in const [Nutrient.protein, Nutrient.carbs, Nutrient.fat])
                    '${_rounded(totals[nutrient])} g',
                ].join(' · '),
              ),
              if (totals[Nutrient.fiber] case final fiber?)
                LabeledRow(label: 'Ballaststoffe', value: '${fiber.round()} g'),
            ],
          ),
          FormSection(
            header: 'Zutaten (1 Person)',
            children: [
              for (final item in recipe.ingredients)
                LabeledRow(label: item.name, value: '${GermanFormat.number(item.grams)} g'),
            ],
          ),
          if (recipe.steps.isNotEmpty)
            FormSection(
              header: 'Zubereitung',
              children: [
                for (final (index, step) in recipe.steps.indexed)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 10,
                      child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                    ),
                    title: Text(step),
                  ),
              ],
            ),
          FormSection(
            footer: 'Öffnet den Entwurf: Menge (½, 2 Portionen), Zutaten und Zeitpunkt anpassen, dann speichern.',
            children: [
              // Erst prüfen: Portion, Zutaten tauschen, Zeitpunkt – nichts landet ungefragt im Tagebuch.
              ListTile(
                leading: Icon(_logged ? Icons.check : Icons.add),
                title: Text(_logged ? 'Eingetragen' : 'Als Mahlzeit eintragen …'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: _log,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Einkaufsliste nach Abteilungen mit Vorrat (Port von `ShoppingListView`).
class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key, required this.controller});

  final RecipeController controller;

  static String amount(double grams) =>
      grams >= 1000 ? '${GermanFormat.number((grams / 100).round() / 10)} kg' : '${grams.toInt()} g';

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  /// Gewählter Ausschnitt; `null` = erster bzw. letzter Tag mit Rezepten.
  CalendarDay? _from;
  CalendarDay? _to;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _togglePantry(String name) {
    final settings = ref.read(coachSettingsProvider);
    settings.pantry = settings.pantry.contains(name)
        ? [
            for (final item in settings.pantry)
              if (item != name) item,
          ]
        : [...settings.pantry, name];
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final controller = widget.controller;
    final plan = controller.plan;
    final servings = settings.recipes.servings;
    final days = [
      for (final day in plan?.days ?? const <RecipeDay>[])
        if (day.recipes.isNotEmpty) day.day,
    ]..sort();
    final today = CalendarDay.today();
    final first = _from ?? days.firstOrNull ?? today;
    final candidate = _to ?? days.lastOrNull ?? first;
    final last = candidate < first ? first : candidate;
    final items = plan == null
        ? const <ShoppingItem>[]
        : RecipePlanner.shoppingList(plan, servings: servings, from: first, to: last);
    final groups = <ShoppingAisle, List<ShoppingItem>>{};
    for (final item in items) {
      (groups[item.aisle] ??= []).add(item);
    }
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final count = days.where((day) => day >= first && day <= last).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkaufsliste'),
        actions: [
          IconButton(
            tooltip: 'Teilen',
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                subject: 'Einkaufsliste',
                text: items.map((item) => '${item.name}: ${ShoppingListScreen.amount(item.grams)}').join('\n'),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (days.length > 1)
            FormSection(
              header: 'Zeitraum',
              footer: 'Alle Rezepte von $count ${count == 1 ? 'Tag' : 'Tagen'} zusammengeführt.',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<CalendarDay>(
                    initialValue: first,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Von'),
                    items: [for (final day in days) DropdownMenuItem(value: day, child: Text(formatDay(day)))],
                    onChanged: (day) => setState(() => _from = day),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<CalendarDay>(
                    key: ValueKey(first),
                    initialValue: last,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bis'),
                    items: [
                      for (final day in days)
                        if (day >= first) DropdownMenuItem(value: day, child: Text(formatDay(day))),
                    ],
                    onChanged: (day) => setState(() => _to = day),
                  ),
                ),
              ],
            ),
          // Nach Supermarkt-Abteilung, damit man den Laden einmal durchläuft statt hin und her.
          for (final aisle in ShoppingAisle.values)
            if (groups[aisle] case final list?)
              FormSection(
                header: aisle.label,
                children: [
                  for (final item in list)
                    ListTile(
                      minTileHeight: 44,
                      leading: Icon(
                        controller.checked.contains(item.id) ? Icons.check_circle : Icons.circle_outlined,
                        color: controller.checked.contains(item.id) ? Colors.green : secondary,
                      ),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          decoration: controller.checked.contains(item.id) ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(ShoppingListScreen.amount(item.grams), style: TextStyle(color: secondary)),
                          IconButton(
                            tooltip: settings.pantry.contains(item.name) ? 'Nicht mehr da' : 'Habe ich da',
                            icon: Icon(
                              settings.pantry.contains(item.name) ? Icons.inventory_2 : Icons.inventory_2_outlined,
                              color: Colors.teal,
                            ),
                            onPressed: () => _togglePantry(item.name),
                          ),
                        ],
                      ),
                      onTap: () => controller.toggle(item),
                    ),
                ],
              ),
          FormSection(
            header: 'Vorrat',
            footer: 'Mengen für $servings ${servings == 1 ? 'Person' : 'Personen'}, roh bzw. wie eingekauft.',
            children: [
              if (settings.pantry.isEmpty)
                ListTile(
                  title: Text(
                    'Bei einer Zutat auf das Kisten-Symbol tippen › „Habe ich da“. „Was jetzt?“ kocht dann bevorzugt mit '
                    'deinem Vorrat.',
                    style: TextStyle(color: secondary),
                  ),
                )
              else
                for (final name in settings.pantry)
                  ListTile(
                    title: Text(name),
                    trailing: IconButton(
                      tooltip: 'Entfernen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _togglePantry(name),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wünsche und Allergene für die Rezeptideen (Port von `RecipePreferencesView`).
class RecipePreferencesScreen extends ConsumerStatefulWidget {
  const RecipePreferencesScreen({super.key});

  @override
  ConsumerState<RecipePreferencesScreen> createState() => _RecipePreferencesScreenState();
}

class _RecipePreferencesScreenState extends ConsumerState<RecipePreferencesScreen> {
  late final _dislikes = TextEditingController(text: ref.read(coachSettingsProvider).recipes.dislikes);

  @override
  void dispose() {
    _dislikes.dispose();
    super.dispose();
  }

  void _change(void Function(RecipePreferences recipes) change) {
    final settings = ref.read(coachSettingsProvider);
    final recipes = settings.recipes;
    change(recipes);
    settings.recipes = recipes;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final recipes = settings.recipes;
    Widget stepper(String text, {required VoidCallback? less, required VoidCallback? more}) => ListTile(
      title: Text(text),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: 'Weniger', icon: const Icon(Icons.remove), onPressed: less),
          IconButton(tooltip: 'Mehr', icon: const Icon(Icons.add), onPressed: more),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezept-Wünsche'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<Diet>(
                  initialValue: settings.nutrition.diet,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ernährungsweise'),
                  items: [for (final diet in Diet.values) DropdownMenuItem(value: diet, child: Text(diet.label))],
                  onChanged: (diet) {
                    if (diet == null) return;
                    final nutrition = settings.nutrition..diet = diet;
                    settings.nutrition = nutrition;
                  },
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Allergene und Unverträglichkeiten',
            children: [
              for (final allergen in Allergen.values)
                SwitchListTile(
                  title: Text(allergen.label),
                  value: recipes.allergens.contains(allergen),
                  onChanged: (on) => _change((recipes) {
                    final allergens = {...recipes.allergens};
                    on ? allergens.add(allergen) : allergens.remove(allergen);
                    recipes.allergens = allergens;
                  }),
                ),
            ],
          ),
          FormSection(
            header: 'Wünsche',
            footer:
                'Allergene prüft die App bei jeder Zutat noch einmal selbst und verwirft unpassende Rezepte. Bei einer '
                'ernsten Allergie trotzdem jede Zutat selbst kontrollieren.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _dislikes,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Mag ich nicht, z. B. Pilze, Koriander'),
                  onChanged: (text) => _change((recipes) => recipes.dislikes = text),
                ),
              ),
              stepper(
                'Höchstens ${recipes.maxMinutes} min Zubereitung',
                less: recipes.maxMinutes > 10 ? () => _change((recipes) => recipes.maxMinutes -= 5) : null,
                more: recipes.maxMinutes < 90 ? () => _change((recipes) => recipes.maxMinutes += 5) : null,
              ),
              SwitchListTile(
                title: const Text('Snack pro Tag'),
                value: recipes.snacks,
                onChanged: (on) => _change((recipes) => recipes.snacks = on),
              ),
              SwitchListTile(
                title: const Text('Abends für den nächsten Mittag mitkochen'),
                value: recipes.mealPrep,
                onChanged: (on) => _change((recipes) => recipes.mealPrep = on),
              ),
              stepper(
                'Einkauf für ${recipes.servings} ${recipes.servings == 1 ? 'Person' : 'Personen'}',
                less: recipes.servings > 1 ? () => _change((recipes) => recipes.servings -= 1) : null,
                more: recipes.servings < 6 ? () => _change((recipes) => recipes.servings += 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

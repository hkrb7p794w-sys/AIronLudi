import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import 'nutrition_controller.dart';

/// „Was esse ich jetzt?“: drei Ideen zu den übrigen Makros, auf Wunsch mit dem Vorrat aus der Einkaufsliste
/// (Port von `MealNowSheet`). Gibt das übernommene Rezept zurück.
class MealNowScreen extends StatefulWidget {
  const MealNowScreen({super.key, required this.controller, required this.pantry, required this.generate});

  final NutritionController controller;
  final List<String> pantry;
  final Future<void> Function() generate;

  @override
  State<MealNowScreen> createState() => _MealNowScreenState();
}

class _MealNowScreenState extends State<MealNowScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    if (widget.controller.nowSuggestions.isEmpty) unawaited(widget.generate());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final targets = controller.targets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Was jetzt?'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
        leadingWidth: 100,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          FormSection(
            children: [
              if (targets != null)
                ListTile(
                  title: Text(
                    'Noch übrig: ${[
                      for (final nutrient in const [Nutrient.kcal, Nutrient.protein, Nutrient.carbs, Nutrient.fat]) '${math.max(0.0, (targets.values[nutrient] ?? 0) - (controller.totals[nutrient] ?? 0)).round()} '
                            '${nutrient.unit}${nutrient == Nutrient.kcal ? '' : ' ${nutrient.label}'}',
                    ].join(' · ')}',
                  ),
                ),
              ListTile(
                title: Text(
                  widget.pantry.isEmpty
                      ? 'Tipp: In der Einkaufsliste „Habe ich da“ abhaken – dann kocht die KI mit deinem Vorrat.'
                      : 'Vorrat: ${widget.pantry.take(8).join(', ')}',
                  style: secondary,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(controller.nowSuggestions.isEmpty ? 'Ideen holen' : 'Neue Ideen'),
                enabled: !controller.isWorking,
                onTap: widget.generate,
                trailing: controller.isWorking
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
              ),
            ],
          ),
          for (final recipe in controller.nowSuggestions)
            FormSection(
              children: [
                ListTile(
                  title: Text(recipe.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${recipe.minutes} min · ${(recipe.totals[Nutrient.kcal] ?? 0).round()} kcal · '
                        '${(recipe.totals[Nutrient.protein] ?? 0).round()} g Protein',
                        style: secondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [for (final item in recipe.ingredients) '${GermanFormat.number(item.grams)} g ${item.name}']
                            .join(', '),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle),
                  title: const Text('Übernehmen und prüfen', style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.of(context).pop(recipe),
                ),
              ],
            ),
          if (controller.nowNotes.isNotEmpty)
            FormSection(
              footer: 'Ernährungsweise und Allergene prüft die App selbst; Mengen sind auf dein Ziel skaliert.',
              children: [
                for (final note in controller.nowNotes)
                  ListTile(dense: true, leading: const Icon(Icons.verified_user_outlined), title: Text(note)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Eigene Rezepte mit Portionen und Vorrat (Meal-Prep): einmal kochen, mehrere Tage eintragen.
class OwnRecipesScreen extends ConsumerWidget {
  const OwnRecipesScreen({super.key, required this.log});

  final void Function(OwnRecipe recipe, double? grams) log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final recipes = settings.ownRecipes;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Eigene Rezepte')),
      body: recipes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restaurant, size: 48),
                    SizedBox(height: 12),
                    Text('Noch keine eigenen Rezepte', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      'Eine Mahlzeit gedrückt halten › „Als eigenes Rezept speichern“.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                for (final recipe in recipes)
                  Dismissible(
                    key: ValueKey(recipe.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => settings.ownRecipes = [
                      for (final other in settings.ownRecipes)
                        if (other.id != recipe.id) other,
                    ],
                    child: ListTile(
                      title: Text(recipe.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${recipe.portions} Portionen à ${GermanFormat.number(recipe.item().grams.roundToDouble())} g · '
                        '${(recipe.item().amounts[Nutrient.kcal] ?? 0).round()} kcal'
                        '${recipe.remainingPortions == null ? '' : ' · noch ${PortionGuess.format(recipe.remainingPortions!)}'}',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      trailing: IconButton(
                        tooltip: 'Bearbeiten',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final updated = await Navigator.of(context).push<OwnRecipe>(
                            MaterialPageRoute(fullscreenDialog: true, builder: (_) => OwnRecipeEditor(recipe: recipe)),
                          );
                          if (updated == null) return;
                          settings.ownRecipes = [
                            for (final other in settings.ownRecipes) other.id == updated.id ? updated : other,
                          ];
                        },
                      ),
                      onTap: () async {
                        final grams = await showModalBottomSheet<double>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (_) => LogOwnRecipeSheet(recipe: recipe),
                        );
                        if (grams != null) log(recipe, grams);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Portionen, gekochtes Gewicht und „Neu gekocht“ (Vorrat auffüllen). Gibt die geänderte Kopie zurück.
class OwnRecipeEditor extends StatefulWidget {
  const OwnRecipeEditor({super.key, required this.recipe});

  final OwnRecipe recipe;

  @override
  State<OwnRecipeEditor> createState() => _OwnRecipeEditorState();
}

class _OwnRecipeEditorState extends State<OwnRecipeEditor> {
  late final OwnRecipe _recipe = OwnRecipe.fromJson(widget.recipe.toJson())!;
  late final _name = TextEditingController(text: _recipe.name);
  late final _cooked = TextEditingController(
    text: _recipe.cookedGrams == null ? '' : _recipe.cookedGrams!.round().toString(),
  );

  @override
  void dispose() {
    _name.dispose();
    _cooked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final raw = GermanFormat.number(
      recipe.ingredients.fold<double>(0, (sum, item) => sum + item.grams).roundToDouble(),
    );
    final canSave = _name.text.trim().isNotEmpty && recipe.ingredients.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezept'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: canSave
                ? () => Navigator.of(context).pop(
                    recipe
                      ..name = _name.text.trim()
                      ..cookedGrams = parseNumber(_cooked.text),
                  )
                : null,
            child: const Text('Sichern'),
          ),
        ],
      ),
      body: ListView(
        children: [
          FormSection(
            footer:
                'Ohne gekochtes Gewicht zählt die Summe der Zutaten ($raw g). Gewogen ist genauer: Beim Kochen '
                'verdunstet Wasser.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ListTile(
                title: Text('${recipe.portions} Portionen'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Weniger Portionen',
                      icon: const Icon(Icons.remove),
                      onPressed: recipe.portions > 1 ? () => setState(() => recipe.portions -= 1) : null,
                    ),
                    IconButton(
                      tooltip: 'Mehr Portionen',
                      icon: const Icon(Icons.add),
                      onPressed: recipe.portions < 20 ? () => setState(() => recipe.portions += 1) : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _cooked,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Gekocht gewogen',
                    hintText: 'optional',
                    suffixText: 'g',
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            children: [
              ListTile(
                leading: const Icon(Icons.soup_kitchen_outlined),
                title: Text('Neu gekocht – ${recipe.portions} Portionen im Vorrat'),
                onTap: () => setState(() => recipe.remainingPortions = recipe.portions.toDouble()),
              ),
              if (recipe.remainingPortions case final remaining?) ...[
                LabeledRow(label: 'Vorrat', value: '${PortionGuess.format(remaining)} Portionen'),
                ListTile(
                  title: const Text('Vorrat leeren', style: TextStyle(color: Colors.red)),
                  onTap: () => setState(() => recipe.remainingPortions = null),
                ),
              ],
            ],
          ),
          FormSection(
            header: 'Zutaten (ganzer Topf)',
            children: [
              for (final item in recipe.ingredients)
                Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(color: Colors.red),
                  onDismissed: (_) => setState(() => recipe.ingredients.removeWhere((other) => other.id == item.id)),
                  child: LabeledRow(label: item.name, value: item.amountLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eine Portion oder eine gewogene Menge vom Topf eintragen; gibt die Gramm zurück.
class LogOwnRecipeSheet extends StatefulWidget {
  const LogOwnRecipeSheet({super.key, required this.recipe});

  final OwnRecipe recipe;

  @override
  State<LogOwnRecipeSheet> createState() => _LogOwnRecipeSheetState();
}

class _LogOwnRecipeSheetState extends State<LogOwnRecipeSheet> {
  final _grams = TextEditingController();

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portion = widget.recipe.item();
    final grams = parseNumber(_grams.text) ?? 0;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.recipe.name, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'PORTIONEN À ${GermanFormat.number(portion.grams.roundToDouble())} G',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Row(
              spacing: 8,
              children: [
                for (final count in PortionGuess.quickCounts)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(portion.grams * count),
                      child: Text(PortionGuess.format(count)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('ODER GEWOGEN', style: theme.textTheme.labelMedium),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grams,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: 'Gramm vom Topf', suffixText: 'g'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                TextButton(
                  onPressed: grams > 0 ? () => Navigator.of(context).pop(grams) : null,
                  child: const Text('Eintragen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Woche: Energie je Tag gegen das Ziel, Protein im Schnitt, Trainingstage, Gewichtstrend – und die KI-Auswertung.
class NutritionWeekScreen extends StatelessWidget {
  const NutritionWeekScreen({
    super.key,
    required this.summary,
    required this.weights,
    required this.goal,
    required this.review,
  });

  final NutritionWeekSummary summary;
  final List<WeightEntry> weights;
  final NutritionGoal goal;
  final Widget review;

  /// Ampel aus den Schutzgrenzen: zu schnell abnehmen ist nicht nachhaltig.
  static String? paceNote(NutritionGoal goal, double percent) {
    if (goal == NutritionGoal.lose && percent < -GoalRules.maxLossPercentPerWeek) {
      return 'Du nimmst schneller ab als 1 % pro Woche – etwas mehr essen, damit es nachhaltig bleibt.';
    }
    if (goal == NutritionGoal.lose && percent > 0) {
      return 'Das Gewicht steigt trotz Ziel Abnehmen – Einträge und Portionen prüfen.';
    }
    if (goal == NutritionGoal.gain && percent > GoalRules.maxGainPercentPerWeek) {
      return 'Du nimmst schneller zu als geplant – Überschuss etwas verringern.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = WeightTrend.trend(weights, today: CalendarDay.today());
    final maxY = [
      for (final day in summary.days) ...[day.kilocalories, ?day.targetKilocalories],
    ].fold<double>(500, math.max);
    return Scaffold(
      appBar: AppBar(title: const Text('Woche')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Diese Woche',
            footer: 'Nur Tage mit Einträgen zählen für den Schnitt. Orange = Trainingstag, Raute = Tagesziel.',
            children: [
              Semantics(
                label: 'Kalorien je Tag, Raute = Ziel, orange = Trainingstag',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: SizedBox(
                    height: 180,
                    child: BarChart(
                      BarChartData(
                        maxY: maxY * 1.1,
                        barGroups: [
                          for (final (index, day) in summary.days.indexed)
                            BarChartGroupData(
                              x: index,
                              barRods: [
                                BarChartRodData(
                                  toY: day.kilocalories,
                                  width: 18,
                                  color: day.trained ? Colors.orange : theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                        ],
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) => SideTitleWidget(
                                meta: meta,
                                child: Text(Weekday.of(summary.days[value.toInt()].day).short),
                              ),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
              ),
              // Ziele als Rauten über den Balken (fl_chart kennt keine Punkte im Balkendiagramm).
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                child: Row(
                  children: [
                    for (final day in summary.days)
                      Expanded(
                        child: Text(
                          day.targetKilocalories == null ? '' : '◆ ${day.targetKilocalories!.round()}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              if (summary.averageKilocalories case final average?)
                LabeledRow(
                  label: 'Schnitt',
                  value:
                      '${average.toInt()} kcal'
                      '${summary.averageTargetKilocalories == null ? '' : ' / ${summary.averageTargetKilocalories!.toInt()}'}',
                ),
              if (summary.averageProtein case final protein?)
                LabeledRow(label: 'Protein im Schnitt', value: '${protein.toInt()} g'),
            ],
          ),
          if (trend != null)
            FormSection(
              header: 'Gewicht',
              children: [
                LabeledRow(label: 'Trend', value: '${GermanFormat.decimal(trend.weeklyPercent)} % pro Woche'),
                if (paceNote(goal, trend.weeklyPercent) case final note?)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text(note, style: const TextStyle(color: Colors.orange)),
                  ),
              ],
            ),
          review,
        ],
      ),
    );
  }
}

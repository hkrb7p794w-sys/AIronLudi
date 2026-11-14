import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

/// Was beim Erfassen sofort bereitsteht: zuletzt, häufig, Rezepte, Favoriten. „+“ trägt mit einem Tipp ein
/// (mit Rückgängig), Antippen öffnet den Entwurf zum Anpassen. Eintragen legt immer eine Kopie an – Rezepte und
/// Favoriten bleiben unverändert (Port von `MealShortcutViews.swift`).
class CaptureShortcuts {
  const CaptureShortcuts({
    this.recent = const [],
    this.frequent = const [],
    this.recipes = const [],
    this.favorites = const [],
    this.log = _ignore,
    this.open = _ignore,
    this.logRecipe = _ignoreRecipe,
  });

  static void _ignore(String _, List<MealItem> _) {}
  static void _ignoreRecipe(OwnRecipe _) {}

  final List<MealEntry> recent;
  final List<MealSuggestion> frequent;
  final List<OwnRecipe> recipes;
  final List<FavoriteMeal> favorites;

  /// Sofort eintragen.
  final void Function(String title, List<MealItem> items) log;

  /// Im Entwurf öffnen.
  final void Function(String title, List<MealItem> items) open;
  final void Function(OwnRecipe recipe) logRecipe;

  bool get isEmpty => recent.isEmpty && frequent.isEmpty && recipes.isEmpty && favorites.isEmpty;
}

enum ShortcutTab {
  recent('Zuletzt'),
  frequent('Häufig'),
  recipes('Rezepte'),
  favorites('Favoriten');

  const ShortcutTab(this.label);

  final String label;
}

class CaptureShortcutsSection extends StatefulWidget {
  const CaptureShortcutsSection({super.key, required this.shortcuts, required this.done});

  final CaptureShortcuts shortcuts;
  final VoidCallback done;

  @override
  State<CaptureShortcutsSection> createState() => _CaptureShortcutsSectionState();
}

class _CaptureShortcutsSectionState extends State<CaptureShortcutsSection> {
  ShortcutTab? _tab;

  ShortcutTab get _firstTab {
    final shortcuts = widget.shortcuts;
    if (shortcuts.recent.isNotEmpty) return ShortcutTab.recent;
    if (shortcuts.favorites.isNotEmpty) return ShortcutTab.favorites;
    if (shortcuts.recipes.isNotEmpty) return ShortcutTab.recipes;
    return ShortcutTab.frequent;
  }

  static int _kcal(List<MealItem> items) => (NutritionSummary.totals(items)[Nutrient.kcal] ?? 0).round();

  List<Widget> _rows(List<(String, List<MealItem>)> meals, {String? empty}) => [
    if (meals.isEmpty && empty != null) _Hint(empty),
    for (final (title, items) in meals)
      ShortcutRow(
        title: title,
        subtitle:
            '${GermanFormat.number(items.fold<double>(0, (sum, item) => sum + item.grams).roundToDouble())} g · '
            '${_kcal(items)} kcal',
        onAdd: () {
          widget.shortcuts.log(title, items);
          widget.done();
        },
        onOpen: () {
          widget.shortcuts.open(title, items);
          widget.done();
        },
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final shortcuts = widget.shortcuts;
    if (shortcuts.isEmpty) return const SizedBox.shrink();
    final current = _tab ?? _firstTab;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SCHNELL WIEDER EINTRAGEN', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          SegmentedButton<ShortcutTab>(
            showSelectedIcon: false,
            segments: [
              for (final tab in ShortcutTab.values)
                ButtonSegment(
                  value: tab,
                  label: FittedBox(child: Text(tab.label)),
                ),
            ],
            selected: {current},
            onSelectionChanged: (selection) => setState(() => _tab = selection.first),
          ),
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Column(
              children: switch (current) {
                ShortcutTab.recent => _rows([
                  for (final entry in shortcuts.recent) (entry.title, entry.items),
                ], empty: 'Noch nichts erfasst.'),
                ShortcutTab.frequent => _rows([
                  for (final suggestion in shortcuts.frequent) (suggestion.title, suggestion.items),
                ], empty: 'Erscheint, sobald du etwas öfter isst.'),
                ShortcutTab.recipes => [
                  if (shortcuts.recipes.isEmpty)
                    const _Hint('Noch keine Rezepte. Eine Mahlzeit lange drücken › „Als eigenes Rezept speichern“.'),
                  for (final recipe in shortcuts.recipes)
                    ShortcutRow(
                      title: recipe.name,
                      subtitle: 'Rezept · 1 Portion · ${_kcal([recipe.item()])} kcal',
                      onAdd: () {
                        shortcuts.logRecipe(recipe);
                        widget.done();
                      },
                      onOpen: () {
                        shortcuts.open(recipe.name, [recipe.item()]);
                        widget.done();
                      },
                    ),
                ],
                ShortcutTab.favorites => [
                  if (shortcuts.favorites.isEmpty)
                    const _Hint('Noch keine Favoriten. Eine Mahlzeit lange drücken › „Als Favorit merken“.'),
                  ..._rows([for (final favorite in shortcuts.favorites) (favorite.title, favorite.items)]),
                ],
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '„+“ trägt sofort ein, Antippen öffnet die Mahlzeit zum Anpassen.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}

/// Zeile: Antippen öffnet, großes „+“ trägt ein.
class ShortcutRow extends StatelessWidget {
  const ShortcutRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onAdd,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, maxLines: 2),
    subtitle: Text(subtitle),
    onTap: onOpen,
    trailing: IconButton(
      tooltip: '$title eintragen',
      iconSize: 32,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
      onPressed: onAdd,
    ),
  );
}

part of 'nutrition_screen.dart';

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
      title: Text(meal.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600)),
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
            Icon(Icons.check_circle, color: AppColors.of(context).good),
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
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
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
                  SwitchListTile.adaptive(
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

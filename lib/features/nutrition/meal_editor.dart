import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/meal_repository.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import 'bls_views.dart';
import 'nutrition_controller.dart';

bool isUncertain(MealItem item) => item.confidence == 'niedrig' || item.confidence == 'mittel';

/// Prüfen und Anpassen einer Mahlzeit vor dem Speichern. Oben steht, was danach vom Tag übrig ist; Positionen sind
/// kompakte Zeilen mit ± (Portion bzw. 10 g), Antippen öffnet Menge und Nährwerte. Unsichere Schätzungen sind gelb
/// markiert.
class MealEditorScreen extends ConsumerStatefulWidget {
  const MealEditorScreen({super.key, required this.draft, required this.controller, required this.foods});

  final MealDraft draft;
  final NutritionController controller;
  final List<StoredFood> foods;

  @override
  ConsumerState<MealEditorScreen> createState() => _MealEditorScreenState();
}

class _MealEditorScreenState extends ConsumerState<MealEditorScreen> {
  MealDraft get draft => widget.draft;
  late final _title = TextEditingController(text: draft.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Übrige kcal des Tages ohne diese Mahlzeit (beim Bearbeiten zählt die alte Fassung nicht doppelt).
  double? get _remainingBefore {
    final target = widget.controller.targets?.values[Nutrient.kcal];
    if (target == null) return null;
    final old = draft.record == null ? 0 : NutritionSummary.totals(draft.record!.items)[Nutrient.kcal] ?? 0;
    return target - ((widget.controller.totals[Nutrient.kcal] ?? 0) - old);
  }

  Future<void> _openItem(MealItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailScreen(item: item, onChanged: () => setState(() {})),
      ),
    );
    setState(() {});
  }

  Future<void> _pickDate() async {
    final current = draft.date ?? widget.controller.timestamp();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(hours: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return;
    setState(() {
      draft.date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      draft.category = NutritionController.category(draft.date!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiClientProvider);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(draft.record == null ? 'Neue Mahlzeit' : 'Mahlzeit bearbeiten'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: () async {
              draft.title = _title.text;
              await widget.controller.save(draft);
              if (widget.controller.draft == null && context.mounted) Navigator.of(context).pop();
              if (widget.controller.errorMessage case final message? when context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
              }
            },
            child: const Text('Speichern', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        children: [
          FormSection(
            children: [DraftSummary(items: draft.items, remainingBefore: _remainingBefore)],
          ),
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
              ),
              ListTile(
                title: const Text('Mahlzeit'),
                trailing: DropdownButton<MealCategory>(
                  value: draft.category,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final category in MealCategory.values)
                      DropdownMenuItem(value: category, child: Text(category.label)),
                  ],
                  onChanged: (category) => setState(() => draft.category = category ?? draft.category),
                ),
              ),
              // Nachtragen: Zeitpunkt wählen, die Mahlzeit folgt der Uhrzeit.
              ListTile(
                title: const Text('Zeitpunkt'),
                trailing: Text(
                  DateFormat('d. MMM, HH:mm', 'de_DE').format(draft.date ?? widget.controller.timestamp()),
                ),
                onTap: _pickDate,
              ),
              if (draft.hint.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(draft.hint, style: muted),
                ),
            ],
          ),
          FormSection(
            header: 'Positionen',
            footer: draft.items.any(isUncertain) ? 'Gelb = unsichere Schätzung, bitte Menge prüfen.' : null,
            children: [
              for (final item in draft.items)
                Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) =>
                      setState(() => draft.items = draft.items.where((other) => other != item).toList()),
                  child: _ItemRow(item: item, onOpen: () => _openItem(item), onChanged: () => setState(() {})),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Position hinzufügen'),
                onTap: () {
                  final item = MealItem(name: '', grams: 100, source: MealItemSource.manual, per100g: NutrientValues());
                  setState(() => draft.items = [...draft.items, item]);
                  _openItem(item);
                },
              ),
              if (widget.foods.isNotEmpty)
                PopupMenuButton<StoredFood>(
                  onSelected: (food) {
                    final item = food.item;
                    if (item != null) setState(() => draft.items = [...draft.items, item.copy()..id = newUuid()]);
                  },
                  itemBuilder: (_) => [
                    for (final food in widget.foods.take(30)) PopupMenuItem(value: food, child: Text(food.name)),
                  ],
                  child: const ListTile(leading: Icon(Icons.star_border), title: Text('Aus eigenen Lebensmitteln')),
                ),
            ],
          ),
          if (ai.allows('meal_amend'))
            AmendSection(
              draft: draft,
              controller: widget.controller,
              foods: widget.foods,
              onChanged: () => setState(() {}),
            ),
          if (draft.record != null && draft.items.isNotEmpty)
            EatenAmountSection(items: draft.items, onChanged: (items) => setState(() => draft.items = items)),
          if (draft.items.isNotEmpty && draft.record == null)
            FormSection(
              header: 'Menge für alle',
              footer: 'Halbe Portion gegessen oder doppelt? Alle Positionen auf einmal anpassen.',
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      for (final factor in const [0.5, 1.5, 2.0])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => draft.items = [for (final item in draft.items) item.scaledBy(factor)]),
                              child: Text('× ${PortionGuess.format(factor)}'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Summe groß oben: kcal, Makros und „danach … kcal übrig“; Lücken in den Nährwerten werden genannt.
class DraftSummary extends StatelessWidget {
  const DraftSummary({super.key, required this.items, required this.remainingBefore});

  final List<MealItem> items;
  final double? remainingBefore;

  @override
  Widget build(BuildContext context) {
    final totals = NutritionSummary.totals(items);
    final kcal = totals[Nutrient.kcal] ?? 0;
    final theme = Theme.of(context);
    final missing = NutrientCheck.missing(Nutrient.protein, items);
    final after = remainingBefore == null ? null : remainingBefore! - kcal;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${kcal.round()} kcal',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (after != null)
                Text(
                  after >= 0 ? 'danach ${after.round()} übrig' : 'danach ${(-after).round()} drüber',
                  style: TextStyle(color: after >= 0 ? theme.colorScheme.onSurfaceVariant : Colors.red),
                ),
            ],
          ),
          Text(
            'Protein ${(totals[Nutrient.protein] ?? 0).round()} g · KH ${(totals[Nutrient.carbs] ?? 0).round()} g · '
            'Fett ${(totals[Nutrient.fat] ?? 0).round()} g',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (missing > 0 && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                missing == 1
                    ? 'Bei 1 Position fehlen Makros – Summe ohne sie.'
                    : 'Bei $missing Positionen fehlen Makros.',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kompakte Zeile: Name, Menge, kcal und Protein; ± ändert um eine Portion bzw. 10 g.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onOpen, required this.onChanged});

  final MealItem item;
  final VoidCallback onOpen;
  final VoidCallback onChanged;

  void _step(double direction) {
    if (item.portionCount case final count?) {
      final next = count + direction * (count < 1 ? 0.5 : 1);
      item.setPortions(next < 0 ? 0 : next);
    } else {
      final next = item.grams + direction * 10;
      item.grams = next < 0 ? 0 : next;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final amounts = item.amounts;
    return ListTile(
      leading: isUncertain(item)
          ? Semantics(
              label: 'Unsichere Schätzung',
              child: const CircleAvatar(radius: 4, backgroundColor: Colors.amber),
            )
          : null,
      title: Text(item.name.isEmpty ? 'Neue Position' : item.name, maxLines: 1),
      subtitle: Text(
        '${item.amountLabel} · ${(amounts[Nutrient.kcal] ?? 0).round()} kcal · '
        '${(amounts[Nutrient.protein] ?? 0).round()} g P${item.source == MealItemSource.ai ? ' · geschätzt' : ''}',
      ),
      onTap: onOpen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(tooltip: 'Weniger', icon: const Icon(Icons.remove), onPressed: () => _step(-1)),
          IconButton.filledTonal(tooltip: 'Mehr', icon: const Icon(Icons.add), onPressed: () => _step(1)),
        ],
      ),
    );
  }
}

/// Menge (Portionen oder Gramm), eigene Portion und Nährwerte je 100 g einer Position.
class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.item, required this.onChanged});

  final MealItem item;
  final VoidCallback onChanged;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  MealItem get item => widget.item;
  bool _inPortions = true;
  late final _name = TextEditingController(text: item.name);
  late final _portionName = TextEditingController(text: item.portion?.name ?? '');
  late final _portionGrams = TextEditingController(
    text: item.portion == null ? '' : GermanFormat.decimal(item.portion!.grams),
  );
  late final _grams = TextEditingController(text: GermanFormat.decimal(item.grams));

  static const _nutrients = [
    Nutrient.kcal,
    Nutrient.protein,
    Nutrient.carbs,
    Nutrient.sugar,
    Nutrient.fat,
    Nutrient.saturatedFat,
    Nutrient.fiber,
  ];

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _setGrams(double grams) {
    item.grams = grams < 0 ? 0 : grams;
    _grams.text = GermanFormat.decimal(item.grams);
    _changed();
  }

  @override
  void dispose() {
    for (final controller in [_name, _portionName, _portionGrams, _grams]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = item.isDrink ? 'ml' : 'g';
    final blsFood = item.source == MealItemSource.bls && item.blsCode != null ? BLS.food(item.blsCode!) : null;
    final warning = NutrientCheck.energyMismatch(item.per100g);
    final portion = item.portion;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name.isEmpty ? 'Position' : item.name),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        children: [
          FormSection(
            footer: item.source == MealItemSource.ai
                ? 'Nährwerte sind von der KI geschätzt. Im Bundeslebensmittelschlüssel (BLS) stehen gemessene Werte.'
                : null,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Lebensmittel'),
                  onChanged: (text) {
                    item.name = text;
                    widget.onChanged();
                  },
                ),
              ),
              ListTile(
                leading: blsFood == null ? const Icon(Icons.search) : null,
                title: Text(blsFood == null ? 'Nährwerte aus dem BLS übernehmen' : 'BLS'),
                trailing: blsFood == null ? null : Text(blsFood.name),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BLSPickerScreen(
                      initialQuery: item.searchTerm ?? item.name,
                      onSelect: (food) {
                        final applied = BLS.apply(food, item);
                        item
                          ..name = applied.name
                          ..per100g = applied.per100g
                          ..source = applied.source
                          ..blsCode = applied.blsCode
                          ..isDrink = applied.isDrink;
                        _name.text = item.name;
                        _changed();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Menge · ${(item.amounts[Nutrient.kcal] ?? 0).round()} kcal',
            children: [
              if (portion != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment(value: true, label: Text('Portionen')),
                      ButtonSegment(value: false, label: Text(item.isDrink ? 'ml' : 'Gramm')),
                    ],
                    selected: {_inPortions},
                    onSelectionChanged: (selection) => setState(() => _inPortions = selection.first),
                  ),
                ),
              if (portion != null && _inPortions) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (final count in PortionGuess.quickCounts)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: ((item.portionCount ?? 0) - count).abs() < 0.01
                                ? FilledButton(onPressed: () {}, child: Text(PortionGuess.format(count)))
                                : OutlinedButton(
                                    onPressed: () {
                                      item.setPortions(count);
                                      _changed();
                                    },
                                    child: Text(PortionGuess.format(count)),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  title: Text('${PortionGuess.format(item.portionCount ?? 0)} × ${portion.name}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Weniger',
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          final next = (item.portionCount ?? 0) - 0.5;
                          item.setPortions(next < 0 ? 0 : next);
                          _changed();
                        },
                      ),
                      IconButton(
                        tooltip: 'Mehr',
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final next = (item.portionCount ?? 0) + 0.5;
                          item.setPortions(next > 50 ? 50 : next);
                          _changed();
                        },
                      ),
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      OutlinedButton(onPressed: () => _setGrams(item.grams - 10), child: const Text('−10')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _grams,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: 'Menge', suffixText: unit),
                          onChanged: (text) {
                            item.grams = parseNumber(text) ?? item.grams;
                            _changed();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: () => _setGrams(item.grams + 10), child: const Text('+10')),
                    ],
                  ),
                ),
              if (item.amountText case final text? when text.isNotEmpty)
                ListTile(title: Text('Schätzung: $text', style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
          FormSection(
            header: 'Eigene Portion',
            footer: 'Die App merkt sich Portion und Menge je Lebensmittel für das nächste Mal.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _portionName,
                  decoration: const InputDecoration(labelText: 'Name, z. B. Scheibe'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _portionGrams,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Gramm je Portion', suffixText: 'g'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ListTile(
                title: Text(portion == null ? 'Portion festlegen' : 'Portion ändern'),
                enabled: (parseNumber(_portionGrams.text) ?? 0) > 0,
                onTap: () {
                  final grams = parseNumber(_portionGrams.text);
                  if (grams == null || grams <= 0) return;
                  final name = _portionName.text.trim();
                  item.portion = Portion(name.isEmpty ? 'Portion' : name, grams);
                  _inPortions = true;
                  _changed();
                },
              ),
            ],
          ),
          FormSection(
            header: 'Nährwerte je 100 $unit',
            footer: '„–“ = unbekannt; zählt in der Summe nicht mit. Quelle: ${mealItemSourceText(item)}.',
            children: [
              for (final nutrient in _nutrients)
                _NutrientField(
                  key: ValueKey('${item.id}-${nutrient.rawValue}-${item.source.rawValue}'),
                  nutrient: nutrient,
                  value: item.per100g[nutrient],
                  onChanged: (value) {
                    item.per100g[nutrient] = value;
                    _changed();
                  },
                ),
              if (warning != null)
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  title: Text(warning, style: const TextStyle(color: Colors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _NutrientField extends StatefulWidget {
  const _NutrientField({super.key, required this.nutrient, required this.value, required this.onChanged});

  final Nutrient nutrient;
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  State<_NutrientField> createState() => _NutrientFieldState();
}

class _NutrientFieldState extends State<_NutrientField> {
  late final _text = TextEditingController(text: widget.value == null ? '' : GermanFormat.decimal(widget.value!));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(widget.nutrient.label),
    trailing: SizedBox(
      width: 130,
      child: TextField(
        controller: _text,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: '–', suffixText: widget.nutrient.unit, border: InputBorder.none),
        onChanged: (text) => widget.onChanged(text.trim().isEmpty ? null : parseNumber(text)),
      ),
    ),
  );
}

/// Gegessene Menge einer gespeicherten Mahlzeit anteilig anpassen.
class EatenAmountSection extends StatelessWidget {
  const EatenAmountSection({super.key, required this.items, required this.onChanged});

  final List<MealItem> items;
  final ValueChanged<List<MealItem>> onChanged;

  @override
  Widget build(BuildContext context) {
    final fraction = MealPortion.eatenFraction(items);
    return FormSection(
      header: 'Gegessen: ${MealPortion.label(items)}',
      footer:
          'Kalorien und Nährwerte passen sich anteilig an. Nur dieser Eintrag ändert sich – Rezepte und Favoriten '
          'bleiben, wie sie sind.',
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (final preset in MealPortion.presets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: (fraction - preset).abs() < 0.005
                        ? FilledButton(onPressed: () {}, child: Text('${(preset * 100).round()} %'))
                        : OutlinedButton(
                            onPressed: () => onChanged(MealPortion.adjusted(items, preset)),
                            child: Text('${(preset * 100).round()} %'),
                          ),
                  ),
                ),
            ],
          ),
        ),
        Slider(
          value: fraction.clamp(0.05, 1.5),
          min: 0.05,
          max: 1.5,
          divisions: 29,
          label: 'Gegessen',
          onChanged: (value) => onChanged(MealPortion.adjusted(items, (value * 20).round() / 20)),
        ),
      ],
    );
  }
}

/// „Fehlt etwas?“ im Entwurf: per Text oder über Hinweise auf oft Übersehenes ergänzen. Die KI liefert nur neue
/// Positionen, die angehängt werden; bestehende bleiben, wie sie sind, und lassen sich weiter bearbeiten.
class AmendSection extends StatefulWidget {
  const AmendSection({
    super.key,
    required this.draft,
    required this.controller,
    required this.foods,
    required this.onChanged,
  });

  final MealDraft draft;
  final NutritionController controller;
  final List<StoredFood> foods;
  final VoidCallback onChanged;

  @override
  State<AmendSection> createState() => _AmendSectionState();
}

class _AmendSectionState extends State<AmendSection> {
  final _text = TextEditingController();
  bool _working = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _amend() async {
    final draft = widget.draft;
    setState(() => _working = true);
    final result = await widget.controller.amend(draft.items, _text.text, photo: draft.photo, foods: widget.foods);
    if (!mounted) return;
    setState(() {
      _working = false;
      if (result == null) {
        _note = widget.controller.errorMessage;
        return;
      }
      if (result.items.isEmpty) {
        _note = result.hint.isEmpty ? 'Nichts zu ergänzen erkannt – bitte genauer beschreiben.' : result.hint;
        return;
      }
      draft.items = [...draft.items, ...result.items];
      final kcal = (NutritionSummary.totals(result.items)[Nutrient.kcal] ?? 0).round();
      _note =
          'Ergänzt: ${result.items.map((item) => item.name).join(', ')} ($kcal kcal, geschätzt).'
          '${result.hint.isEmpty ? '' : ' ${result.hint}'}';
      final added = {for (final item in result.items) FoodSearch.normalized(item.name)};
      draft.possiblyMissing = draft.possiblyMissing
          .where((hint) => !added.any((name) => name.contains(FoodSearch.normalized(hint))))
          .toList();
      _text.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return FormSection(
      header: 'Fehlt etwas?',
      footer:
          'Ergänzungen kommen als neue Positionen dazu – nichts Bestehendes wird überschrieben. Mengen und Nährwerte '
          'der KI sind Schätzungen; prüfe sie oder ändere sie durch Antippen.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'z. B. noch 150 g Hähnchenbrust und 1 EL Olivenöl'),
          ),
        ),
        if (draft.possiblyMissing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final hint in draft.possiblyMissing)
                  ActionChip(
                    label: Text('+ $hint'),
                    onPressed: () => _text.text = _text.text.isEmpty ? hint : '${_text.text}, $hint',
                  ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: Text(_working ? 'Wird ergänzt …' : 'Per KI ergänzen'),
          enabled: !_working && _text.text.trim().isNotEmpty,
          onTap: _amend,
        ),
        if (_note case final note?) ListTile(title: Text(note, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

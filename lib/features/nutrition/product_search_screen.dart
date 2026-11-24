import 'dart:async';

import 'package:coach_core/coach_core.dart' hide Badge;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/nutrition/open_food_facts_client.dart';
import '../../services/providers.dart';
import '../../ui/kpi_ring.dart';
import '../../ui/tokens.dart';
import 'capture_views.dart';

/// Ergebnis der Erfassung: Positionen zum Eintragen oder ein anderer Weg (Scannen, KI, Nur kcal, Manuell).
sealed class FoodLogResult {
  const FoodLogResult();
}

final class FoodLogItems extends FoodLogResult {
  const FoodLogItems(this.items, this.category);

  final List<MealItem> items;
  final MealCategory category;
}

final class FoodLogOther extends FoodLogResult {
  const FoodLogOther(this.other);

  /// `null` = KI (Foto oder Text).
  final CaptureOther? other;
}

String _number(double value) => GermanFormat.number(value.roundToDouble());

/// Kurzzeile wie „47 kcal · 8 P · 3 K · 0 F · 75 g“ für eine Menge.
String foodLine(NutrientValues per100g, double grams) {
  String part(Nutrient nutrient, String unit) => switch (per100g[nutrient]) {
    final value? => '${_number(value * grams / 100)}$unit',
    null => '–$unit',
  };
  return [
    part(Nutrient.kcal, ' kcal'),
    part(Nutrient.protein, ' P'),
    part(Nutrient.carbs, ' K'),
    part(Nutrient.fat, ' F'),
    '${_number(grams)} g',
  ].join(' · ');
}

/// Symbol nach Art des Lebensmittels: Getränk, eiweißreich, fettreich, leicht (Obst/Gemüse) oder kohlenhydratreich.
(IconData, Color) foodIcon(NutrientValues per100g, {required bool isDrink}) {
  if (isDrink) return (Icons.local_drink_outlined, AppPalette.lightBlue);
  final kcal = per100g[Nutrient.kcal] ?? 0;
  final protein = (per100g[Nutrient.protein] ?? 0) * 4;
  final fat = (per100g[Nutrient.fat] ?? 0) * 9;
  if (kcal > 0 && protein / kcal >= 0.35) return (Icons.egg_alt_outlined, AppPalette.deepOrange);
  if (kcal > 0 && fat / kcal >= 0.55) return (Icons.spa_outlined, AppPalette.amber);
  if (kcal < 70) return (Icons.eco_outlined, AppPalette.green);
  return (Icons.bakery_dining_outlined, AppPalette.brown);
}

/// Lebensmittel erfassen, Suche zuerst: Vorschläge passend zur Mahlzeit, „+“ legt mit der üblichen Menge in den Korb,
/// Antippen wählt die Menge. Eigene Lebensmittel und BLS sofort beim Tippen, Markenprodukte (Open Food Facts) kurz
/// danach. Oben die Tageskalorien samt Korb, unten Suchfeld und „Eintragen“ – mit dem Daumen erreichbar.
class ProductSearchScreen extends ConsumerStatefulWidget {
  const ProductSearchScreen({
    super.key,
    this.own = const [],
    this.picks = const [],
    this.category,
    this.eaten,
    this.targets,
    this.initialQuery = '',
  });

  /// Eigene bzw. schon genutzte Lebensmittel (häufig genutzte zuerst).
  final List<MealItem> own;

  /// Vorschläge ohne Suchbegriff (`ProductSearch.picks`).
  final List<MealItem> picks;
  final MealCategory? category;

  /// Heute schon gegessen und Tagesziele (für die Anzeige oben).
  final NutrientValues? eaten;
  final NutrientValues? targets;
  final String initialQuery;

  @override
  ConsumerState<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends ConsumerState<ProductSearchScreen> {
  late final _query = TextEditingController(text: widget.initialQuery);
  late MealCategory _category = widget.category ?? MealCategory.guess(hour: DateTime.now().hour, minute: 0);
  ProductFilter _filter = const ProductFilter();
  Timer? _debounce;
  final _online = <String, List<FoodProduct>>{};
  final _basket = <({String id, MealItem item})>[];
  String? _loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  String get _key => FoodSearch.normalized(_query.text);

  /// Online erst nach einer Pause beim Tippen (Open Food Facts erlaubt nur wenige Suchen je Minute); Ergebnisse je
  /// Suchbegriff gemerkt.
  void _schedule() {
    _debounce?.cancel();
    setState(() => _error = null);
    final key = _key;
    if (key.length < ProductSearch.onlineMinimumLength || _online.containsKey(key)) return;
    if (!_filter.includes(ProductSource.openFoodFacts)) return;
    _debounce = Timer(const Duration(milliseconds: 700), () => unawaited(_search(key)));
  }

  Future<void> _search(String key) async {
    setState(() => _loading = key);
    try {
      final products = await ref.read(openFoodFactsProvider).search(_query.text);
      _online[key] = [for (final product in products) FoodProduct.openFoodFacts(product)];
    } on FoodLookupError catch (error) {
      _error = error.message;
    } on Object catch (error) {
      _error = 'Open Food Facts nicht erreichbar: $error';
    }
    if (mounted) setState(() => _loading = null);
  }

  void _add(FoodProduct product, {double? grams}) {
    HapticFeedback.selectionClick();
    setState(() => _basket.add((id: product.id, item: product.item(grams: grams ?? product.defaultGrams))));
  }

  Future<void> _choose(FoodProduct product) async {
    final item = await showModalBottomSheet<MealItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductAmountSheet(product: product),
    );
    if (item != null && mounted) setState(() => _basket.add((id: product.id, item: item)));
  }

  int _count(FoodProduct product) => _basket.where((entry) => entry.id == product.id).length;

  NutrientValues get _basketTotals => NutritionSummary.totals([for (final entry in _basket) entry.item]);

  void _finish() => Navigator.of(context).pop(FoodLogItems([for (final entry in _basket) entry.item], _category));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = _key;
    final local = ProductSearch.local(_query.text, own: widget.own, filter: _filter);
    final online = (_online[key] ?? const <FoodProduct>[]).where(_filter.matches).toList();
    final picks = [for (final item in widget.picks) FoodProduct.own(item)];
    final pickNames = {for (final item in widget.picks) FoodSearch.normalized(item.name)};
    final recent = [
      for (final item in widget.own)
        if (!pickNames.contains(FoodSearch.normalized(item.name))) FoodProduct.own(item),
    ].take(12).toList();
    final secondary = theme.colorScheme.onSurfaceVariant;

    Widget row(FoodProduct product) =>
        _FoodRow(product: product, count: _count(product), onAdd: () => _add(product), onTap: () => _choose(product));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Schließen',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: _CategoryChip(category: _category, onChanged: (category) => setState(() => _category = category)),
        actions: [
          if (widget.targets?[Nutrient.kcal] case final goal? when goal > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _KilocaloriePill(
                eaten: (widget.eaten?[Nutrient.kcal] ?? 0) + (_basketTotals[Nutrient.kcal] ?? 0),
                goal: goal,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _Ways(onSelect: (other) => Navigator.of(context).pop(FoodLogOther(other))),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (key.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      spacing: 8,
                      children: [
                        for (final source in ProductSource.values)
                          FilterChip(
                            label: Text(source.label),
                            selected: _filter.sources.contains(source),
                            onSelected: (on) {
                              final sources = {..._filter.sources};
                              on ? sources.add(source) : sources.remove(source);
                              setState(() => _filter = _filter.copyWith(sources: sources));
                              _schedule();
                            },
                          ),
                        FilterChip(
                          label: const Text('Viel Protein'),
                          selected: _filter.highProtein,
                          onSelected: (on) => setState(() => _filter = _filter.copyWith(highProtein: on)),
                        ),
                        FilterChip(
                          label: const Text('Kalorienarm'),
                          selected: _filter.lowCalorie,
                          onSelected: (on) => setState(() => _filter = _filter.copyWith(lowCalorie: on)),
                        ),
                      ],
                    ),
                  ),
                if (key.isEmpty) ...[
                  if (picks.isNotEmpty)
                    _Group(
                      title: 'Vorschläge · ${_category.label}',
                      children: [for (final product in picks) row(product)],
                    ),
                  if (recent.isNotEmpty)
                    _Group(title: 'Zuletzt verwendet', children: [for (final product in recent) row(product)]),
                  if (picks.isEmpty && recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unten ein Lebensmittel oder Produkt suchen, z. B. „Skyr“. Was du oft isst, steht hier künftig '
                        'als Vorschlag zur passenden Mahlzeit.',
                        style: TextStyle(color: secondary),
                      ),
                    ),
                ],
                if (local.isNotEmpty)
                  _Group(title: 'Lebensmittel', children: [for (final product in local.take(30)) row(product)]),
                if (_filter.includes(ProductSource.openFoodFacts) && key.length >= ProductSearch.onlineMinimumLength)
                  _Group(
                    title: 'Markenprodukte',
                    footer:
                        'Quelle: Open Food Facts (ODbL). Angaben der Community – bitte mit der Packung vergleichen.',
                    children: [
                      if (_loading == key)
                        const ListTile(
                          leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          title: Text('Suche bei Open Food Facts …'),
                        )
                      else if (_error case final error?)
                        ListTile(
                          leading: Icon(Icons.wifi_off, color: AppColors.of(context).caution),
                          title: Text(error, style: AppText.footnote(context)),
                          trailing: TextButton(onPressed: () => unawaited(_search(key)), child: const Text('Erneut')),
                        )
                      else if (_online.containsKey(key) && online.isEmpty)
                        const ListTile(title: Text('Keine Markenprodukte gefunden.'))
                      else
                        for (final product in online) row(product),
                    ],
                  ),
                if (key.isNotEmpty && local.isEmpty && !_filter.includes(ProductSource.openFoodFacts))
                  const ListTile(title: Text('Nichts gefunden.')),
              ],
            ),
          ),
          _BottomBar(
            query: _query,
            basket: [for (final entry in _basket) entry.item],
            totals: _basketTotals,
            onRemove: (index) => setState(() => _basket.removeAt(index)),
            onChanged: _schedule,
            onSubmitted: () {
              _debounce?.cancel();
              if (_key.length >= ProductSearch.onlineMinimumLength &&
                  !_online.containsKey(_key) &&
                  _filter.includes(ProductSource.openFoodFacts)) {
                unawaited(_search(_key));
              }
            },
            onLog: _basket.isEmpty ? null : _finish,
          ),
        ],
      ),
    );
  }
}

/// Mahlzeit wählen (Frühstück, Mittagessen …), vorbelegt nach Uhrzeit.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.onChanged});

  final MealCategory category;
  final ValueChanged<MealCategory> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<MealCategory>(
    tooltip: 'Mahlzeit',
    initialValue: category,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final value in MealCategory.values) PopupMenuItem(value: value, child: Text(value.label)),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Flexible(
            child: Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.callout(context).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    ),
  );
}

/// „1.661 / 2.822“ mit Ring: Tageskalorien einschließlich Korb gegen das Ziel.
class _KilocaloriePill extends StatelessWidget {
  const _KilocaloriePill({required this.eaten, required this.goal});

  final double eaten;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final fraction = eaten / goal;
    final color = fraction > 1.1
        ? AppColors.of(context).alert
        : fraction > 1
        ? AppColors.of(context).caution
        : Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '${_number(eaten)} von ${_number(goal)} kcal',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ProgressRing(fraction: fraction, color: color, size: 28, stroke: 4),
          Text(
            '${_number(eaten)} / ${_number(goal)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// Andere Wege zu erfassen, als Reiter über der Suche.
class _Ways extends StatelessWidget {
  const _Ways({required this.onSelect});

  final ValueChanged<CaptureOther?> onSelect;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget way(String label, IconData icon, CaptureOther? other, {bool selected = false}) => Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: selected ? null : () => onSelect(other),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? primary : Colors.transparent, width: 3)),
          ),
          child: Row(
            spacing: 6,
            children: [
              Icon(icon, size: 20, color: selected ? primary : null),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: selected ? primary : null),
              ),
            ],
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          way('Suchen', Icons.search, null, selected: true),
          way('Scannen', Icons.qr_code_scanner, CaptureOther.barcode),
          way('KI · Foto/Text', Icons.auto_awesome, null),
          way('Nur kcal', Icons.bolt, CaptureOther.quick),
          way('Manuell', Icons.edit_note, CaptureOther.manual),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.footer});

  final String title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        ...children,
        if (footer case final footer?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(footer, style: AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// Eine Zeile: Symbol, Name, Kurzzeile für die übliche Menge, „+“ (im Korb mit Anzahl).
class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.product, required this.count, required this.onAdd, required this.onTap});

  final FoodProduct product;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = foodIcon(product.per100g, isDrink: product.item(grams: 1).isDrink);
    final grams = product.defaultGrams;
    final serving = product.servingText;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          spacing: 14,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 22),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
                  Text(
                    foodLine(product.per100g, grams) +
                        (serving != null && product.servingGrams == grams ? ' ($serving)' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (product.source == ProductSource.openFoodFacts)
              const Tooltip(message: 'Markenprodukt (Open Food Facts)', child: Icon(Icons.storefront, size: 16)),
            Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: IconButton.filledTonal(
                tooltip: '${product.title} hinzufügen',
                icon: Icon(count > 0 ? Icons.check : Icons.add),
                onPressed: onAdd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unten: Korb (antippen = entfernen), Summe, Suchfeld und „Eintragen“.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.query,
    required this.basket,
    required this.totals,
    required this.onRemove,
    required this.onChanged,
    required this.onSubmitted,
    required this.onLog,
  });

  final TextEditingController query;
  final List<MealItem> basket;
  final NutrientValues totals;
  final ValueChanged<int> onRemove;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              if (basket.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 6,
                    children: [
                      for (final (index, item) in basket.indexed)
                        InputChip(
                          label: Text('${item.name} · ${_number(item.grams)} g'),
                          onDeleted: () => onRemove(index),
                          deleteButtonTooltipMessage: 'Entfernen',
                        ),
                    ],
                  ),
                ),
                Text(
                  '${basket.length} ${basket.length == 1 ? 'Position' : 'Positionen'} · '
                  '${_number(totals[Nutrient.kcal] ?? 0)} kcal · ${_number(totals[Nutrient.protein] ?? 0)} g Protein · '
                  '${_number(totals[Nutrient.carbs] ?? 0)} g KH · ${_number(totals[Nutrient.fat] ?? 0)} g Fett',
                  style: AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: TextField(
                      controller: query,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Suchen …',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: ListenableBuilder(
                          listenable: query,
                          builder: (_, _) => query.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  tooltip: 'Leeren',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    query.clear();
                                    onChanged();
                                  },
                                ),
                        ),
                        isDense: true,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(99),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => onChanged(),
                      onSubmitted: (_) => onSubmitted(),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: onLog,
                    child: Text(basket.isEmpty ? 'Eintragen' : 'Eintragen (${basket.length})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductAmountSheet extends StatefulWidget {
  const ProductAmountSheet({super.key, required this.product});

  final FoodProduct product;

  @override
  State<ProductAmountSheet> createState() => _ProductAmountSheetState();
}

class _ProductAmountSheetState extends State<ProductAmountSheet> {
  late double _grams = widget.product.servingGrams ?? 100;
  late final _field = TextEditingController(text: GermanFormat.number(_grams));

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set(double grams) {
    setState(() => _grams = grams);
    _field.text = GermanFormat.number(grams);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final serving = product.servingGrams;
    String value(Nutrient nutrient, String unit) => switch (product.amount(nutrient, _grams)) {
      final amount? => '${GermanFormat.number(amount.roundToDouble())} $unit',
      null => '–',
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(product.title, style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                children: [
                  if (serving != null)
                    ChoiceChip(
                      label: Text(product.servingText ?? 'Portion (${GermanFormat.number(serving)} g)'),
                      selected: _grams == serving,
                      onSelected: (_) => _set(serving),
                    ),
                  ChoiceChip(label: const Text('100 g'), selected: _grams == 100, onSelected: (_) => _set(100)),
                ],
              ),
              TextField(
                controller: _field,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                decoration: const InputDecoration(labelText: 'Menge', suffixText: 'g'),
                onChanged: (text) {
                  final grams = double.tryParse(text.replaceAll(',', '.'));
                  if (grams != null && grams > 0) setState(() => _grams = grams);
                },
              ),
              Text(
                '${value(Nutrient.kcal, 'kcal')} · Protein ${value(Nutrient.protein, 'g')} · '
                'Kohlenhydrate ${value(Nutrient.carbs, 'g')} · Fett ${value(Nutrient.fat, 'g')}',
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Zur Mahlzeit hinzufügen'),
                onPressed: _grams > 0 && _grams <= 5000
                    ? () => Navigator.of(context).pop(product.item(grams: _grams))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

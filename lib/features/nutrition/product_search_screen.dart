import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/nutrition/open_food_facts_client.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';

String _per100(NutrientValues values) {
  const parts = [(Nutrient.kcal, 'kcal'), (Nutrient.protein, 'g P'), (Nutrient.carbs, 'g KH'), (Nutrient.fat, 'g F')];
  return [
    for (final (nutrient, unit) in parts)
      if (values[nutrient] case final value?) '${GermanFormat.number(value.roundToDouble())} $unit',
  ].join(' · ');
}

/// Produkt suchen: eigene Lebensmittel und BLS sofort beim Tippen, Markenprodukte (Open Food Facts) kurz danach.
/// Filter nach Herkunft, „viel Protein“ und „kalorienarm“; Nährwerte je 100 g und je Portion. Antippen → Menge wählen →
/// Position für die Mahlzeit (Rückgabe).
class ProductSearchScreen extends ConsumerStatefulWidget {
  const ProductSearchScreen({super.key, this.own = const [], this.initialQuery = ''});

  /// Eigene bzw. schon genutzte Lebensmittel.
  final List<MealItem> own;
  final String initialQuery;

  @override
  ConsumerState<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends ConsumerState<ProductSearchScreen> {
  late final _query = TextEditingController(text: widget.initialQuery);
  ProductFilter _filter = const ProductFilter();
  Timer? _debounce;
  final _online = <String, List<FoodProduct>>{};
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

  Future<void> _choose(FoodProduct product) async {
    final item = await showModalBottomSheet<MealItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductAmountSheet(product: product),
    );
    if (item != null && mounted) Navigator.of(context).pop(item);
  }

  Widget _chip(String label, {required bool selected, required ValueChanged<bool> onSelected}) =>
      FilterChip(label: Text(label), selected: selected, onSelected: onSelected);

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final local = ProductSearch.local(_query.text, own: widget.own, filter: _filter);
    final online = (_online[key] ?? const <FoodProduct>[]).where(_filter.matches).toList();
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    void toggleSource(ProductSource source, bool on) {
      final sources = {..._filter.sources};
      on ? sources.add(source) : sources.remove(source);
      setState(() => _filter = _filter.copyWith(sources: sources));
      _schedule();
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: widget.initialQuery.isEmpty,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Produkt suchen, z. B. „Skyr“', border: InputBorder.none),
          onChanged: (_) => _schedule(),
          onSubmitted: (_) {
            _debounce?.cancel();
            if (_key.length >= ProductSearch.onlineMinimumLength &&
                !_online.containsKey(_key) &&
                _filter.includes(ProductSource.openFoodFacts)) {
              unawaited(_search(_key));
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              spacing: 8,
              children: [
                for (final source in ProductSource.values)
                  _chip(
                    source.label,
                    selected: _filter.sources.contains(source),
                    onSelected: (on) => toggleSource(source, on),
                  ),
                _chip(
                  'Viel Protein',
                  selected: _filter.highProtein,
                  onSelected: (on) => setState(() => _filter = _filter.copyWith(highProtein: on)),
                ),
                _chip(
                  'Kalorienarm',
                  selected: _filter.lowCalorie,
                  onSelected: (on) => setState(() => _filter = _filter.copyWith(lowCalorie: on)),
                ),
              ],
            ),
          ),
          if (key.isEmpty)
            FormSection(
              children: [
                ListTile(
                  title: Text(
                    'Suchbegriff eingeben. Eigene Lebensmittel und der Bundeslebensmittelschlüssel erscheinen sofort, '
                    'Markenprodukte aus Open Food Facts ab drei Zeichen.',
                    style: TextStyle(color: secondary),
                  ),
                ),
              ],
            ),
          if (local.isNotEmpty)
            FormSection(
              header: 'Lebensmittel',
              children: [
                for (final product in local.take(30)) _ProductTile(product: product, onTap: () => _choose(product)),
              ],
            ),
          if (_filter.includes(ProductSource.openFoodFacts) && key.length >= ProductSearch.onlineMinimumLength)
            FormSection(
              header: 'Markenprodukte',
              footer:
                  'Quelle: Open Food Facts (ODbL). Angaben der Community, Nährwerte bitte mit der Packung vergleichen.',
              children: [
                if (_loading == key)
                  const ListTile(
                    leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    title: Text('Suche bei Open Food Facts …'),
                  )
                else if (_error case final error?)
                  ListTile(
                    leading: const Icon(Icons.wifi_off, color: Colors.orange),
                    title: Text(error, style: const TextStyle(fontSize: 13)),
                    trailing: TextButton(onPressed: () => unawaited(_search(key)), child: const Text('Erneut')),
                  )
                else if (_online.containsKey(key) && online.isEmpty)
                  const ListTile(title: Text('Keine Markenprodukte gefunden.'))
                else
                  for (final product in online) _ProductTile(product: product, onTap: () => _choose(product)),
              ],
            ),
          if (key.isNotEmpty && local.isEmpty && !_filter.includes(ProductSource.openFoodFacts))
            const FormSection(children: [ListTile(title: Text('Nichts gefunden.'))]),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final FoodProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final serving = product.servingGrams;
    return ListTile(
      title: Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text('je 100 g: ${_per100(product.per100g)}', style: secondary),
          if (serving != null)
            Text(
              'Portion (${GermanFormat.number(serving)} g): '
              '${GermanFormat.number((product.amount(Nutrient.kcal, serving) ?? 0).roundToDouble())} kcal',
              style: secondary,
            ),
        ],
      ),
      trailing: AppChip(
        text: product.source.label,
        color: switch (product.source) {
          ProductSource.own => Colors.purple,
          ProductSource.bls => Colors.teal,
          ProductSource.openFoodFacts => Colors.orange,
        },
      ),
      onTap: onTap,
    );
  }
}

/// Menge wählen (Portion, 100 g oder eigene Gramm), Nährwerte dafür sehen, hinzufügen.
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

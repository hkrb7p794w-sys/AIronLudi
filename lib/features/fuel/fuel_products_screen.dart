import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'fuel_parts.dart';
import 'fuel_stock_screen.dart';

/// Eigene Gels, Getränke, Riegel und DIY-Mischungen; darunter die mitgelieferten (nur lesen).
class FuelProductsScreen extends ConsumerWidget {
  const FuelProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(fuelStoreProvider);
    Future<void> open([FuelProduct? product]) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => FuelProductEditor(product: product)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Produkte'),
        actions: [
          IconButton(
            tooltip: 'Vorrat',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () =>
                unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FuelStockScreen()))),
          ),
          IconButton(tooltip: 'Produkt anlegen', icon: const Icon(Icons.add), onPressed: () => unawaited(open())),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          FormSection(
            header: 'Eigene',
            footer: store.ownProducts.isEmpty
                ? 'Lege deine Gels, Getränke oder eine eigene Mischung aus Maltodextrin, Fruktose und Salz an – der Plan '
                      'rechnet dann aus, wie viele Flaschen, Gels und Gramm Pulver du brauchst.'
                : null,
            children: [
              for (final product in store.ownProducts)
                ListTile(
                  leading: Icon(_icon(product.kind)),
                  title: Text(product.name),
                  subtitle: Text(_withStock(product, store)),
                  trailing: const DisclosureChevron(),
                  onTap: () => unawaited(open(product)),
                ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Produkt oder Mischung anlegen'),
                onTap: () => unawaited(open()),
              ),
            ],
          ),
          FormSection(
            header: 'Mitgeliefert',
            footer: 'Typische Werte ohne Marke. Für genaue Zahlen eigene Produkte vom Etikett anlegen.',
            children: [
              for (final product in FuelProducts.all)
                ListTile(
                  leading: Icon(_icon(product.kind)),
                  title: Text(product.name),
                  subtitle: Text(_withStock(product, store)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _withStock(FuelProduct product, FuelStore store) {
    final count = store.stock[product.id]?.count ?? 0;
    final summary = fuelProductSummary(product);
    return count <= 0 ? summary : '$summary · ${GermanFormat.decimal(count)} im Vorrat';
  }

  static IconData _icon(FuelProductKind kind) => switch (kind) {
    FuelProductKind.gel => Icons.bolt,
    FuelProductKind.drink => Icons.local_drink,
    FuelProductKind.drinkMix => Icons.science_outlined,
    FuelProductKind.bar => Icons.view_agenda_outlined,
    FuelProductKind.chew => Icons.grain,
    FuelProductKind.food => Icons.restaurant,
    FuelProductKind.electrolyte => Icons.grain_outlined,
  };
}

/// Produkt anlegen bzw. ändern; bei „Eigene Mischung“ aus den Zutaten je Flasche.
class FuelProductEditor extends ConsumerStatefulWidget {
  const FuelProductEditor({super.key, this.product});

  final FuelProduct? product;

  @override
  ConsumerState<FuelProductEditor> createState() => _FuelProductEditorState();
}

class _FuelProductEditorState extends ConsumerState<FuelProductEditor> {
  late FuelProductKind _kind = widget.product?.kind ?? FuelProductKind.gel;
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _serving = TextEditingController(text: widget.product?.servingLabel ?? '');
  late final Map<String, TextEditingController> _fields = {
    for (final MapEntry(:key, :value) in _initial.entries)
      key: TextEditingController(text: value == null || value == 0 ? '' : GermanFormat.number(value)),
  };

  Map<String, double?> get _initial {
    final p = widget.product;
    final mix = p?.mix;
    return {
      'carbs': p?.carbs,
      'fructose': p?.fructose,
      'sodium': p?.sodium,
      'caffeine': p?.caffeine,
      'protein': p?.protein,
      'fat': p?.fat,
      'grams': p == null || p.isDrink ? null : p.servingGrams,
      'volume': p?.isDrink ?? false ? p!.volumeMilliliters : null,
      'maltodextrin': mix?.maltodextrin,
      'dextrose': mix?.dextrose,
      'mixFructose': mix?.fructose,
      'sucrose': mix?.sucrose,
      'salt': mix?.salt,
      'water': mix?.waterMilliliters ?? 500,
      'mixCaffeine': mix?.caffeineMilligrams,
    };
  }

  @override
  void initState() {
    super.initState();
    for (final controller in _fields.values) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _serving.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _value(String key) => (parseNumber(_fields[key]!.text) ?? 0).clamp(0, 5000).toDouble();
  double? _optional(String key) => parseNumber(_fields[key]!.text);

  FuelMix get _mix => FuelMix(
    maltodextrin: _value('maltodextrin'),
    dextrose: _value('dextrose'),
    fructose: _value('mixFructose'),
    sucrose: _value('sucrose'),
    salt: _value('salt'),
    waterMilliliters: _value('water'),
    caffeineMilligrams: _value('mixCaffeine'),
  );

  FuelProduct? get _product {
    final name = _name.text.trim();
    if (name.isEmpty) return null;
    final id = widget.product?.id ?? FuelProducts.newId();
    if (_kind == FuelProductKind.drinkMix) {
      final mix = _mix;
      if (mix.waterMilliliters <= 0) return null;
      return FuelProduct.fromMix(id: id, name: name, mix: mix);
    }
    final carbs = _value('carbs');
    final fructose = _optional('fructose');
    return FuelProduct(
      id: id,
      name: name,
      kind: _kind,
      carbs: carbs,
      servingLabel: _serving.text.trim().isEmpty ? null : _serving.text.trim(),
      servingGrams: _kind.isDrink ? _value('volume') : _value('grams'),
      volumeMilliliters: _kind.isDrink ? _value('volume') : 0,
      fructose: fructose?.clamp(0, carbs).toDouble(),
      sodium: _value('sodium'),
      caffeine: _value('caffeine'),
      protein: _value('protein'),
      fat: _value('fat'),
    );
  }

  Future<void> _save() async {
    final product = _product;
    if (product == null) return;
    final store = ref.read(fuelStoreProvider);
    if (store.hasForeignData) return;
    await store.saveProduct(product);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.product?.id;
    if (id == null) return;
    final store = ref.read(fuelStoreProvider);
    final used = store.plansUsing(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Produkt löschen?'),
        content: Text(
          used == 0
              ? 'Es wird in keinem gespeicherten Plan genutzt.'
              : 'Es steckt in $used gespeicherten ${used == 1 ? 'Plan' : 'Plänen'} – dort meldet der Plan es dann als '
                    'fehlend, bis du ein anderes wählst.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.deleteProduct(id);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(String key, String label) => NumberField(label: label, controller: _fields[key]!);

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final isMix = _kind == FuelProductKind.drinkMix;
    final mix = _mix;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Neues Produkt' : 'Produkt'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        actions: [
          TextButton(onPressed: product == null ? null : () => unawaited(_save()), child: const Text('Sichern')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: InputBorder.none),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<FuelProductKind>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Art', border: InputBorder.none),
                  items: [
                    for (final kind in FuelProductKind.values) DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: (kind) => setState(() => _kind = kind ?? _kind),
                ),
              ),
              if (!isMix)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _serving,
                    decoration: InputDecoration(
                      labelText: 'Portion heißt',
                      hintText: _kind.servingLabel,
                      border: InputBorder.none,
                    ),
                  ),
                ),
            ],
          ),
          if (isMix)
            FormSection(
              header: 'Zutaten je Flasche',
              footer:
                  'Maltodextrin zählt mit 95 %, Dextrose (Monohydrat) mit 91 %, Haushaltszucker zur Hälfte als '
                  'Fruktose. 1 g Kochsalz = 393 mg Natrium.',
              children: [
                _field('water', 'Wasser (ml)'),
                _field('maltodextrin', 'Maltodextrin (g)'),
                _field('dextrose', 'Dextrose (g)'),
                _field('mixFructose', 'Fruktose (g)'),
                _field('sucrose', 'Haushaltszucker (g)'),
                _field('salt', 'Kochsalz (g)'),
                _field('mixCaffeine', 'Koffein (mg, optional)'),
              ],
            )
          else
            FormSection(
              header: 'Je Portion',
              children: [
                if (_kind.isDrink) _field('volume', 'Inhalt (ml)') else _field('grams', 'Gewicht (g)'),
                _field('carbs', 'Kohlenhydrate (g)'),
                _field('fructose', 'davon Fruktose (g, falls bekannt)'),
                _field('sodium', 'Natrium (mg)'),
                _field('caffeine', 'Koffein (mg)'),
                _field('protein', 'Protein (g)'),
                _field('fat', 'Fett (g)'),
              ],
            ),
          if (product != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LiquidSpacing.page),
              child: LiquidCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text('Ergibt', style: LiquidText.sectionHeader(context)),
                    Text(fuelProductSummary(product)),
                    if (isMix) ...[
                      Text(
                        '${GermanFormat.decimal(mix.concentration)} % Kohlenhydrate · ${mix.powderGrams.round()} g '
                        'Pulver je Flasche · ${product.kilocalories.round()} kcal',
                        style: LiquidText.label(context),
                      ),
                      if (mix.concentration > FuelMix.highConcentration)
                        Text(
                          'Über 10 %: Der Magen leert sich langsamer – mit Wasser nachspülen, im Training testen.',
                          style: LiquidText.label(context).copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          if (widget.product != null)
            FormSection(
              children: [
                ListTile(
                  title: Text('Löschen', style: TextStyle(color: AppColors.of(context).alert)),
                  onTap: () => unawaited(_delete()),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

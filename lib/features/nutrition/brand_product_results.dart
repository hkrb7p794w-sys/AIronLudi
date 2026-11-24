import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/nutrition/open_food_facts_client.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import 'bls_views.dart';
import 'product_search_screen.dart';

/// „Markenprodukte“ aus Open Food Facts zu einem Suchbegriff – für die Schnellsuche im Reiter Ernährung (unter den
/// eigenen Lebensmitteln und dem BLS). Fragt erst nach einer Tipp-Pause und ab drei Zeichen; Ergebnisse merkt sich
/// der Client je Suchbegriff. Jede Zeile zeigt die Nährwerte je Portion bzw. 100 g und je 100 g.
class BrandProductResults extends ConsumerStatefulWidget {
  const BrandProductResults({super.key, required this.query, required this.onAdd, required this.onOpen});

  final String query;

  /// „+“: sofort mit der üblichen Menge (Packungsportion, sonst 100 g) eintragen.
  final void Function(MealItem item) onAdd;

  /// Antippen: im Entwurf öffnen, um die Menge anzupassen.
  final void Function(MealItem item) onOpen;

  /// Pause beim Tippen, bevor online gesucht wird.
  static const debounce = Duration(milliseconds: 700);

  @override
  ConsumerState<BrandProductResults> createState() => _BrandProductResultsState();
}

class _BrandProductResultsState extends ConsumerState<BrandProductResults> {
  Timer? _timer;
  String? _loading;
  String? _error;
  final _results = <String, List<FoodProduct>>{};

  String get _key => FoodSearch.normalized(widget.query);

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(BrandProductResults old) {
    super.didUpdateWidget(old);
    if (FoodSearch.normalized(old.query) != _key) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _error = null;
    final key = _key;
    if (key.length < ProductSearch.onlineMinimumLength || _results.containsKey(key)) return;
    _timer = Timer(BrandProductResults.debounce, () => unawaited(_search(key)));
  }

  Future<void> _search(String key) async {
    setState(() {
      _loading = key;
      _error = null;
    });
    String? error;
    try {
      final products = await ref.read(openFoodFactsProvider).search(widget.query);
      _results[key] = [for (final product in products) FoodProduct.openFoodFacts(product)];
    } on FoodLookupError catch (failure) {
      error = failure.message;
    } on Object catch (failure) {
      error = 'Open Food Facts nicht erreichbar: $failure';
    }
    if (!mounted) return;
    setState(() {
      if (_loading == key) _loading = null;
      if (key == _key) _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    if (key.length < ProductSearch.onlineMinimumLength) return const SizedBox.shrink();
    final products = _results[key];
    final secondary = AppText.footnote(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'Markenprodukte',
      footer: 'Quelle: Open Food Facts (ODbL). Angaben der Community – bitte mit der Packung vergleichen.',
      children: [
        if (_error case final error?)
          ListTile(
            leading: Icon(Icons.wifi_off, color: AppColors.of(context).caution),
            title: Text(error, style: AppText.footnote(context)),
            trailing: TextButton(onPressed: () => unawaited(_search(key)), child: const Text('Erneut')),
          )
        else if (products == null)
          const ListTile(
            leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text('Suche bei Open Food Facts …'),
          )
        else if (products.isEmpty)
          ListTile(title: Text('Keine Markenprodukte zu „${widget.query.trim()}“ gefunden.', style: secondary))
        else
          for (final product in products.take(12))
            ListTile(
              title: Text(product.title, maxLines: 2),
              subtitle: Text(
                '${foodLine(product.per100g, product.defaultGrams)}'
                '${product.servingText != null && product.servingGrams != null ? ' (${product.servingText})' : ''}\n'
                '${blsSummary(product.per100g)}',
                style: secondary,
              ),
              isThreeLine: true,
              onTap: () => widget.onOpen(product.item(grams: product.defaultGrams)),
              trailing: IconButton(
                tooltip: '${product.title} eintragen',
                iconSize: 32,
                icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
                onPressed: () => widget.onAdd(product.item(grams: product.defaultGrams)),
              ),
            ),
      ],
    );
  }
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import '../../ui/kpi_ring.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'fuel_parts.dart';

/// Kurzfassung des Vorrats für die Übersicht: „12 Portionen · 1 läuft bald ab“.
String fuelStockSummary(FuelStore store, CalendarDay today) {
  final entries = store.stock.entries.where((entry) => entry.value.count > 0).toList();
  if (entries.isEmpty) return 'Noch nichts erfasst';
  final total = entries.fold(0.0, (sum, entry) => sum + entry.value.count);
  final soon = entries.where((entry) => entry.value.expiresSoon(today)).length;
  final expired = entries.where((entry) => entry.value.expiredOn(today)).length;
  return [
    '${GermanFormat.decimal(total)} ${total == 1 ? 'Portion' : 'Portionen'} von ${entries.length} '
        '${entries.length == 1 ? 'Produkt' : 'Produkten'}',
    if (soon > 0) '$soon läuft bald ab',
    if (expired > 0) '$expired abgelaufen',
  ].join(' · ');
}

/// Vorrat: wie viel von welchem Produkt da ist und bis wann es haltbar ist. Der Planer braucht ihn zuerst auf.
class FuelStockScreen extends ConsumerWidget {
  const FuelStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(fuelStoreProvider);
    final today = CalendarDay.today();
    final stock = store.stock;
    final inStock = [
      for (final product in store.allProducts)
        if (stock[product.id] != null) product,
    ];
    final others = [
      for (final product in store.allProducts)
        if (stock[product.id] == null) product,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Vorrat')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          FormSection(
            footer:
                'Vorrätige Gels, Riegel und Getränke plant die Verpflegung automatisch ein – bald ablaufende zuerst. '
                'Beim Übernehmen ins Tagebuch wird abgebucht, „Rückgängig“ bucht zurück.',
            children: [
              SwitchListTile(
                title: const Text('Vorrat zuerst aufbrauchen'),
                value: store.profile.useStockFirst,
                onChanged: store.hasForeignData
                    ? null
                    : (value) => unawaited(store.saveProfile(store.profile.copyWith(useStockFirst: value))),
              ),
            ],
          ),
          FormSection(
            header: 'Im Vorrat',
            children: [
              if (inStock.isEmpty) const ListTile(title: Text('Noch nichts – unten ein Produkt hinzufügen.')),
              for (final product in inStock) _StockRow(product: product, stock: stock[product.id]!, today: today),
            ],
          ),
          FormSection(
            header: 'Hinzufügen',
            children: [
              for (final product in others)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(product.name),
                  subtitle: Text(fuelProductSummary(product)),
                  onTap: store.hasForeignData
                      ? null
                      : () => unawaited(store.setStock(product.id, const FuelStock(count: 1))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockRow extends ConsumerWidget {
  const _StockRow({required this.product, required this.stock, required this.today});

  final FuelProduct product;
  final FuelStock stock;
  final CalendarDay today;

  Future<void> _pickDate(BuildContext context, FuelStore store) async {
    final current = stock.bestBefore ?? today.adding(180);
    final picked = await showDatePicker(
      context: context,
      helpText: 'Mindestens haltbar bis',
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null) return;
    await store.setStock(product.id, stock.copyWith(bestBefore: () => CalendarDay.fromDate(picked)));
  }

  /// Mit dem aktuellen Stand rechnen (nicht dem beim letzten Aufbau), damit schnelle Tipps alle zählen.
  Future<void> _change(FuelStore store, int delta) {
    final current = store.stock[product.id] ?? stock;
    final count = current.count + delta;
    return store.setStock(product.id, count <= 0 ? null : current.copyWith(count: count));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(fuelStoreProvider);
    final date = stock.bestBefore;
    final expired = stock.expiredOn(today);
    final soon = stock.expiresSoon(today);
    final unit = product.isDrink ? (stock.count == 1 ? 'Flasche' : 'Flaschen') : product.serving;
    return ListTile(
      title: Text(product.name),
      subtitle: Text(
        date == null
            ? 'Haltbarkeit antippen zum Eintragen'
            : 'haltbar bis ${GermanFormat.date(date)}${expired
                  ? ' – abgelaufen, wird nicht eingeplant'
                  : soon
                  ? ' – bald, wird zuerst aufgebraucht'
                  : ''}',
        style: TextStyle(
          color: expired
              ? kpiColor(KpiStatus.critical)
              : soon
              ? kpiColor(KpiStatus.moderate)
              : null,
        ),
      ),
      onTap: store.hasForeignData ? null : () => unawaited(_pickDate(context, store)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Eins weniger',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: store.hasForeignData ? null : () => unawaited(_change(store, -1)),
          ),
          SizedBox(
            width: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(GermanFormat.decimal(stock.count), style: LiquidText.kpi(context, size: 18)),
                Text(
                  unit,
                  style: AppText.caption(context).copyWith(color: AppColors.muted(context)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Eins mehr',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: store.hasForeignData ? null : () => unawaited(_change(store, 1)),
          ),
        ],
      ),
    );
  }
}

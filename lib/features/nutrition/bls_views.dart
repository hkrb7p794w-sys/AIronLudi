import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

import '../../ui/components.dart';

/// Herkunft der Nährwerte für Fußnoten: BLS mit Eintrag, KI als Schätzung.
String mealItemSourceText(MealItem item) => switch (item.source) {
  MealItemSource.bls => '${BLS.sourceLabel}${item.blsCode == null ? '' : ' – ${BLS.food(item.blsCode!)?.name ?? ''}'}',
  MealItemSource.ai => 'KI, geschätzt',
  _ => item.source.rawValue,
};

/// Kernwerte je 100 g.
String blsSummary(NutrientValues values) {
  const parts = [(Nutrient.kcal, 'kcal'), (Nutrient.protein, 'g P'), (Nutrient.carbs, 'g KH'), (Nutrient.fat, 'g F')];
  return 'je 100 g: ${[for (final (nutrient, unit) in parts)
    if (values[nutrient] case final value?) '${value.round()} $unit'].join(' · ')}';
}

/// Lebensmittel im Bundeslebensmittelschlüssel suchen und übernehmen (offline, rund 7.000 Einträge).
class BLSPickerScreen extends StatefulWidget {
  const BLSPickerScreen({super.key, required this.initialQuery, required this.onSelect});

  final String initialQuery;
  final ValueChanged<BLSFood> onSelect;

  @override
  State<BLSPickerScreen> createState() => _BLSPickerScreenState();
}

class _BLSPickerScreenState extends State<BLSPickerScreen> {
  late final _query = TextEditingController(text: widget.initialQuery)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text;
    final results = BLS.search(query, limit: 40);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: widget.initialQuery.isEmpty,
          decoration: const InputDecoration(hintText: 'Lebensmittel im BLS', border: InputBorder.none),
        ),
      ),
      body: ListView(
        children: [
          FormSection(
            footer: 'Quelle: ${BLS.attribution}. Nährwerte je 100 g, so wie im Namen beschrieben (roh, gekocht …).',
            children: [
              if (results.isEmpty)
                ListTile(
                  title: Text(
                    query.runes.length < 2 ? 'Suchbegriff eingeben, z. B. „Haferflocken“.' : 'Nichts gefunden.',
                  ),
                ),
              for (final food in results)
                ListTile(
                  title: Text(food.name, maxLines: 2),
                  subtitle: Text(blsSummary(food.per100g)),
                  onTap: () {
                    widget.onSelect(food);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

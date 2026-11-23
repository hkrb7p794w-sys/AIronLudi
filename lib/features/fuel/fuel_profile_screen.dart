import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import 'fuel_parts.dart';

/// Persönliches Profil: Verträglichkeit, Schweiß, Koffein, Takt und Standard-Produkte für neue Pläne.
class FuelProfileScreen extends ConsumerStatefulWidget {
  const FuelProfileScreen({super.key});

  @override
  ConsumerState<FuelProfileScreen> createState() => _FuelProfileScreenState();
}

class _FuelProfileScreenState extends ConsumerState<FuelProfileScreen> {
  late FuelProfile _profile = ref.read(fuelStoreProvider).profile;
  late final _sweat = TextEditingController(text: _text(_profile.sweatRateLitersPerHour));
  late final _sodium = TextEditingController(text: _text(_profile.sodiumPerLiter));
  final _before = TextEditingController();
  final _after = TextEditingController();
  final _drank = TextEditingController();
  final _minutes = TextEditingController(text: '60');

  static String _text(double? value) => value == null ? '' : GermanFormat.number(value);

  @override
  void dispose() {
    for (final controller in [_sweat, _sodium, _before, _after, _drank, _minutes]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _set(FuelProfile profile) {
    setState(() => _profile = profile);
    final store = ref.read(fuelStoreProvider);
    if (!store.hasForeignData) unawaited(store.saveProfile(profile));
  }

  void _measure() {
    final rate = FuelProfile.measuredSweatRate(
      weightBefore: parseNumber(_before.text) ?? 0,
      weightAfter: parseNumber(_after.text) ?? 0,
      drankLiters: parseNumber(_drank.text) ?? 0,
      minutes: (parseNumber(_minutes.text) ?? 0).round(),
    );
    if (rate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Werte prüfen – kein Verlust erkennbar.')));
      return;
    }
    _sweat.text = GermanFormat.number(rate);
    _set(_profile.copyWith(sweatRateLitersPerHour: () => rate));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(fuelStoreProvider);
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Mein Profil')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (store.hasForeignData)
            const FormSection(
              children: [ListTile(title: Text('Der gespeicherte Stand gehört einem anderen Benutzer – nur lesen.'))],
            ),
          FormSection(
            header: 'Magen-Darm-Verträglichkeit',
            footer: '${p.gut.detail}. Der Darm ist trainierbar: je Woche etwa 10 g/h mehr üben.',
            children: [
              for (final gut in GutTolerance.values)
                ListTile(
                  title: Text(gut.label),
                  subtitle: Text('bis ${gut.maxCarbsPerHour} g/h'),
                  trailing: gut == p.gut ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                  selected: gut == p.gut,
                  onTap: () => _set(p.copyWith(gut: gut)),
                ),
            ],
          ),
          FormSection(
            header: 'Schweiß',
            footer: 'Ohne Messung schätzt der Plan aus Intensität, Gewicht, Temperatur und Luftfeuchte.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _sweat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Schweißrate gemessen (l/h)',
                    hintText: 'leer = schätzen',
                    border: InputBorder.none,
                  ),
                  onChanged: (text) {
                    final value = parseNumber(text);
                    _set(p.copyWith(sweatRateLitersPerHour: () => value != null && value > 0 ? value : null));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<SweatSaltiness>(
                  initialValue: p.saltiness,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Salzverlust', border: InputBorder.none),
                  items: [
                    for (final saltiness in SweatSaltiness.values)
                      DropdownMenuItem(
                        value: saltiness,
                        child: Text('${saltiness.label.split(' ').first} (${saltiness.sodiumPerLiter} mg/l)'),
                      ),
                  ],
                  onChanged: (value) => _set(p.copyWith(saltiness: value)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _sodium,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Natrium im Schweiß gemessen (mg/l, optional)',
                    border: InputBorder.none,
                  ),
                  onChanged: (text) {
                    final value = parseNumber(text);
                    _set(p.copyWith(sodiumPerLiter: () => value != null && value > 0 ? value : null));
                  },
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Schweißrate messen',
            footer: 'Vor und nach einer Einheit nackt wiegen, Getrunkenes in Litern dazu. 1 kg ≈ 1 l.',
            children: [
              NumberField(label: 'Gewicht vorher (kg)', controller: _before),
              NumberField(label: 'Gewicht nachher (kg)', controller: _after),
              NumberField(label: 'Getrunken (l)', controller: _drank),
              NumberField(label: 'Dauer (min)', controller: _minutes, decimal: false),
              ListTile(leading: const Icon(Icons.calculate_outlined), title: const Text('Berechnen'), onTap: _measure),
            ],
          ),
          FormSection(
            header: 'Koffein und Takt',
            footer:
                'Koffein nur, wenn du es im Plan einschaltest. Belegt sind 3–6 mg/kg; mehr bringt nur Nebenwirkungen.',
            children: [
              ListTile(
                title: const Text('Koffein'),
                trailing: Text('${GermanFormat.decimal(p.caffeineMgPerKg)} mg/kg'),
              ),
              Slider(
                value: p.caffeineMgPerKg.clamp(1, 6),
                min: 1,
                max: 6,
                divisions: 10,
                onChanged: (value) => _set(p.copyWith(caffeineMgPerKg: (value * 2).roundToDouble() / 2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SegmentedButton<int>(
                  segments: [
                    for (final interval in fuelIntervals) ButtonSegment(value: interval, label: Text('$interval min')),
                  ],
                  selected: {p.intervalMinutes},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => _set(p.copyWith(intervalMinutes: value.first)),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Standard-Produkte unterwegs',
            footer: 'Werden in jedem neuen Plan vorausgewählt.',
            children: [
              for (final product in store.allProducts)
                CheckboxListTile(
                  value: p.setup.contains(product.id),
                  onChanged: (value) => _set(
                    p.copyWith(
                      setup: [
                        for (final id in p.setup)
                          if (id != product.id) id,
                        if (value == true) product.id,
                      ],
                    ),
                  ),
                  title: Text(product.name),
                  subtitle: Text(fuelProductSummary(product)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

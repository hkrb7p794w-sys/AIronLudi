import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import 'fuel_parts.dart';

/// Szenario einstellen: Sportart, Dauer, Intensität, Bedingungen, Verträglichkeit, Produkte. Gibt
/// `(Szenario, Produkt-IDs)` zurück.
class FuelScenarioScreen extends ConsumerStatefulWidget {
  const FuelScenarioScreen({super.key, required this.scenario, required this.productIDs, this.isNew = true});

  final FuelScenario scenario;
  final List<String> productIDs;
  final bool isNew;

  @override
  ConsumerState<FuelScenarioScreen> createState() => _FuelScenarioScreenState();
}

class _FuelScenarioScreenState extends ConsumerState<FuelScenarioScreen> {
  late FuelScenario _s = widget.scenario;
  late final List<String> _ids = [...widget.productIDs];
  late final _title = TextEditingController(text: widget.scenario.title);
  late final _distance = TextEditingController(
    text: widget.scenario.distanceMeters == null ? '' : GermanFormat.decimal(widget.scenario.distanceMeters! / 1000),
  );

  static const _nextOptions = <int?>[null, 3, 4, 6, 8, 12];

  @override
  void dispose() {
    _title.dispose();
    _distance.dispose();
    super.dispose();
  }

  void _set(FuelScenario value) => setState(() => _s = value);

  void _done() {
    final km = parseNumber(_distance.text);
    final result = _s.copyWith(
      title: _title.text.trim(),
      distanceMeters: () => km == null || km <= 0 ? null : (km * 1000).round(),
    );
    Navigator.of(context).pop((result, List<String>.of(_ids)));
  }

  Future<void> _pickDay() async {
    final today = CalendarDay.today();
    final current = _s.day ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
    );
    if (picked != null) _set(_s.copyWith(day: () => CalendarDay.fromDate(picked)));
  }

  Future<void> _pickStart() async {
    final start = _s.startMinuteOfDay ?? 9 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
    );
    if (picked != null) _set(_s.copyWith(startMinuteOfDay: () => picked.hour * 60 + picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(fuelStoreProvider);
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Neuer Plan' : 'Szenario'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        actions: [TextButton(onPressed: _done, child: Text(widget.isNew ? 'Berechnen' : 'Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          FormSection(
            header: 'Einheit',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: s.displayTitle,
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sport in FuelSport.values)
                      ChoiceChip(
                        avatar: Icon(Icons.circle, size: 10, color: sport.color),
                        label: Text(sport.label),
                        selected: s.sport == sport,
                        onSelected: (_) => _set(s.copyWith(sport: sport)),
                      ),
                  ],
                ),
              ),
              ListTile(dense: true, title: Text(s.sport.detail, style: LiquidText.label(context))),
              ListTile(title: const Text('Dauer'), trailing: Text(_duration(s.minutes))),
              Slider(
                value: s.minutes.clamp(15, 720).toDouble(),
                min: 15,
                max: 720,
                divisions: (720 - 15) ~/ 5,
                label: _duration(s.minutes),
                onChanged: (value) => _set(s.copyWith(minutes: value.round())),
              ),
              NumberField(label: 'Distanz in km (optional)', controller: _distance),
            ],
          ),
          FormSection(
            header: 'Intensität',
            footer: s.isRace
                ? 'Wettkampf: höchste Stufe unterwegs, mehr Kohlenhydrate vorher und Carboloading ab 90 min.'
                : s.intensity.detail,
            children: [
              SwitchListTile(
                title: const Text('Wettkampf / Schlüsseleinheit'),
                value: s.isRace,
                onChanged: (value) => _set(s.copyWith(isRace: value)),
              ),
              if (!s.isRace)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SegmentedButton<FuelIntensity>(
                    segments: [
                      for (final intensity in FuelIntensity.values)
                        ButtonSegment(value: intensity, label: Text(intensity.label)),
                    ],
                    selected: {s.intensity},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) => _set(s.copyWith(intensity: value.first)),
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Bedingungen',
            children: [
              ListTile(
                title: const Text('Temperatur'),
                trailing: Text('${GermanFormat.decimal(s.temperatureCelsius)} °C'),
              ),
              Slider(
                value: s.temperatureCelsius.clamp(-10, 40),
                min: -10,
                max: 40,
                divisions: 50,
                label: '${s.temperatureCelsius.round()} °C',
                onChanged: (value) => _set(s.copyWith(temperatureCelsius: value.roundToDouble())),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SegmentedButton<FuelHumidity>(
                  segments: [
                    for (final humidity in FuelHumidity.values)
                      ButtonSegment(value: humidity, label: Text(humidity.label)),
                  ],
                  selected: {s.humidity},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => _set(s.copyWith(humidity: value.first)),
                ),
              ),
              if (s.sport != FuelSport.swim)
                SwitchListTile(
                  title: const Text('Drinnen'),
                  subtitle: const Text('Rolle, Laufband, Halle – kein Fahrtwind'),
                  value: s.indoor,
                  onChanged: (value) => _set(s.copyWith(indoor: value)),
                ),
              ListTile(
                title: const Text('Tag'),
                trailing: Text(s.day == null ? 'heute' : GermanFormat.date(s.day!)),
                onTap: _pickDay,
              ),
              ListTile(
                title: const Text('Start'),
                subtitle: const Text('Für Uhrzeiten im Zeitstrahl und den Koffein-Hinweis'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.startMinuteOfDay == null ? 'offen' : fuelClock(s.startMinuteOfDay!)),
                    if (s.startMinuteOfDay != null)
                      IconButton(
                        tooltip: 'Startzeit entfernen',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _set(s.copyWith(startMinuteOfDay: () => null)),
                      ),
                  ],
                ),
                onTap: _pickStart,
              ),
            ],
          ),
          FormSection(
            header: 'Magen-Darm-Verträglichkeit',
            footer: '${s.gut.detail}. Bis ${s.gut.maxCarbsPerHour} g Kohlenhydrate je Stunde.',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SegmentedButton<GutTolerance>(
                  segments: [for (final gut in GutTolerance.values) ButtonSegment(value: gut, label: Text(gut.label))],
                  selected: {s.gut},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => _set(s.copyWith(gut: value.first)),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Davor und danach',
            children: [
              SwitchListTile(
                title: const Text('Nüchtern'),
                subtitle: const Text('Mindestens 8 h ohne Essen'),
                value: s.fasted,
                onChanged: (value) => _set(s.copyWith(fasted: value)),
              ),
              SwitchListTile(
                title: const Text('Koffein'),
                subtitle: Text('${GermanFormat.decimal(s.caffeineMgPerKg)} mg/kg'),
                value: s.caffeine,
                onChanged: (value) => _set(s.copyWith(caffeine: value)),
              ),
              if (s.caffeine)
                Slider(
                  value: s.caffeineMgPerKg.clamp(1, 6),
                  min: 1,
                  max: 6,
                  divisions: 10,
                  label: '${GermanFormat.decimal(s.caffeineMgPerKg)} mg/kg',
                  onChanged: (value) => _set(s.copyWith(caffeineMgPerKg: (value * 2).roundToDouble() / 2)),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonFormField<int?>(
                  initialValue: _nextOptions.contains(s.hoursUntilNext) ? s.hoursUntilNext : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nächste Einheit in', border: InputBorder.none),
                  items: [
                    for (final hours in _nextOptions)
                      DropdownMenuItem(value: hours, child: Text(hours == null ? 'mehr als 24 h' : '$hours h')),
                  ],
                  onChanged: (hours) => _set(s.copyWith(hoursUntilNext: () => hours)),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Zeitstrahl',
            footer: s.sport == FuelSport.swim ? 'Schwimmen: mindestens alle 20 min am Beckenrand.' : null,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SegmentedButton<int>(
                  segments: [
                    for (final interval in fuelIntervals)
                      ButtonSegment(value: interval, label: Text('alle $interval min')),
                  ],
                  selected: {s.intervalMinutes},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => _set(s.copyWith(intervalMinutes: value.first)),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Produkte unterwegs',
            footer:
                'Das erste Getränk deckt die Flüssigkeit, Gels und Riegel den Rest der Kohlenhydrate, Salztabletten das '
                'Natrium. Eigene Produkte und Mischungen unter Fuel Planner › Meine Produkte.',
            children: [
              for (final product in store.allProducts)
                CheckboxListTile(
                  value: _ids.contains(product.id),
                  onChanged: (value) => setState(() {
                    _ids.remove(product.id);
                    if (value == true) _ids.add(product.id);
                  }),
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

  static String _duration(int minutes) =>
      minutes < 60 ? '$minutes min' : '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h';
}

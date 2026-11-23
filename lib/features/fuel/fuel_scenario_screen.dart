import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fuel/fuel_store.dart';
import '../../services/fuel/fuel_weather_service.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import 'fuel_parts.dart';

/// Häufige Szenarien mit einem Tipp.
final class FuelPreset {
  const FuelPreset(
    this.label,
    this.sport,
    this.minutes, {
    this.intensity = FuelIntensity.easy,
    this.race = false,
    this.meters,
  });

  final String label;
  final FuelSport sport;
  final int minutes;
  final FuelIntensity intensity;
  final bool race;
  final int? meters;

  static const all = [
    FuelPreset('Lockerer Lauf', FuelSport.run, 45),
    FuelPreset('Intervalle', FuelSport.run, 75, intensity: FuelIntensity.threshold),
    FuelPreset('Lange Radfahrt', FuelSport.bike, 180),
    FuelPreset('Krafttraining', FuelSport.strength, 75, intensity: FuelIntensity.tempo),
    FuelPreset('Halbmarathon', FuelSport.run, 110, race: true, meters: 21097),
    FuelPreset('Marathon', FuelSport.run, 240, race: true, meters: 42195),
    FuelPreset('Radmarathon', FuelSport.bike, 300, race: true),
    FuelPreset('Mitteldistanz', FuelSport.triathlon, 330, race: true),
    FuelPreset('Hyrox', FuelSport.hybrid, 90, race: true),
  ];

  FuelScenario applyTo(FuelScenario s) => s.copyWith(
    sport: sport,
    minutes: minutes,
    intensity: intensity,
    isRace: race,
    distanceMeters: () => meters,
    swimMinutes: () => null,
    bikeMinutes: () => null,
    title: label,
  );
}

/// Szenario einstellen: oben das Wesentliche (Vorlage, Sportart, Dauer, Intensität, Wetter), darunter eingeklappt der
/// Rest. Gibt `(Szenario, Produkt-IDs)` zurück.
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
  late final _distance = TextEditingController(text: _km(widget.scenario.distanceMeters));
  late final _swim = TextEditingController(text: widget.scenario.swimMinutes?.toString() ?? '');
  late final _bike = TextEditingController(text: widget.scenario.bikeMinutes?.toString() ?? '');
  bool _loadingWeather = false;
  String? _weatherMessage;

  static const _durations = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300];
  static const _nextOptions = <int?>[null, 3, 4, 6, 8, 12];

  static String _km(int? meters) => meters == null ? '' : GermanFormat.decimal(meters / 1000);

  @override
  void dispose() {
    for (final controller in [_title, _distance, _swim, _bike]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _set(FuelScenario value) => setState(() => _s = value);

  void _preset(FuelPreset preset) {
    _set(preset.applyTo(_s));
    _title.text = preset.label;
    _distance.text = _km(preset.meters);
    _swim.clear();
    _bike.clear();
  }

  void _done() {
    final km = parseNumber(_distance.text);
    final swim = int.tryParse(_swim.text.trim());
    final bike = int.tryParse(_bike.text.trim());
    final triathlon = _s.sport == FuelSport.triathlon;
    final result = _s.copyWith(
      title: _title.text.trim(),
      distanceMeters: () => km == null || km <= 0 ? null : (km * 1000).round(),
      swimMinutes: () => triathlon && swim != null && swim > 0 ? swim : null,
      bikeMinutes: () => triathlon && bike != null && bike > 0 ? bike : null,
    );
    Navigator.of(context).pop((result, List<String>.of(_ids)));
  }

  Future<void> _weather() async {
    setState(() {
      _loadingWeather = true;
      _weatherMessage = null;
    });
    String message;
    try {
      final (scenario, text) = await ref.read(fuelWeatherServiceProvider).apply(_s);
      if (!mounted) return;
      _s = scenario;
      message = text;
    } on FuelWeatherProblem catch (problem) {
      message = problem.message;
    }
    if (!mounted) return;
    setState(() {
      _loadingWeather = false;
      _weatherMessage = message;
    });
  }

  Future<void> _pickDuration() async {
    final controller = TextEditingController(text: _clock(_s.minutes));
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dauer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(helperText: 'h:mm oder Minuten, z. B. 1:45 oder 105'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_parseDuration(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes != null && minutes >= 10 && minutes <= 24 * 60) _set(_s.copyWith(minutes: minutes));
  }

  static int? _parseDuration(String text) {
    final value = text.trim();
    final parts = value.split(':');
    if (parts.length == 2) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      if (hours == null || minutes == null || minutes >= 60) return null;
      return hours * 60 + minutes;
    }
    return int.tryParse(value);
  }

  static String _clock(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

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
    final start = _s.startMinuteOfDay ?? FuelWeather.defaultStartMinute;
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
    final split = FuelRules.triathlonSplit(s);
    final selected = store.resolve(_ids);
    final carbs = FuelRules.carbsPerHour(s);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Neuer Plan' : 'Szenario'),
        leading: IconButton(
          tooltip: 'Abbrechen',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [TextButton(onPressed: _done, child: Text(widget.isNew ? 'Berechnen' : 'Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          if (widget.isNew)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                children: [
                  for (final preset in FuelPreset.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(label: Text(preset.label), onPressed: () => _preset(preset)),
                    ),
                ],
              ),
            ),
          FormSection(
            header: 'Einheit',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              ListTile(
                title: const Text('Dauer'),
                subtitle: const Text('Tippen für h:mm'),
                onTap: _pickDuration,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '5 Minuten weniger',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: s.minutes <= 15 ? null : () => _set(s.copyWith(minutes: s.minutes - 5)),
                    ),
                    Text(_clock(s.minutes), style: LiquidText.kpi(context, size: 20)),
                    IconButton(
                      tooltip: '5 Minuten mehr',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _set(s.copyWith(minutes: s.minutes + 5)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: [
                    for (final minutes in _durations)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(minutes < 60 ? '$minutes min' : '${GermanFormat.decimal(minutes / 60)} h'),
                          selected: s.minutes == minutes,
                          onSelected: (_) => _set(s.copyWith(minutes: minutes)),
                        ),
                      ),
                  ],
                ),
              ),
              if (s.sport == FuelSport.triathlon) ...[
                NumberField(label: 'Schwimmen in min (leer = ${split.swim})', controller: _swim, decimal: false),
                NumberField(label: 'Rad in min (leer = ${split.bike})', controller: _bike, decimal: false),
              ],
            ],
          ),
          FormSection(
            header: 'Intensität',
            footer: s.isRace
                ? 'Wettkampf: höchste Stufe unterwegs, mehr Kohlenhydrate vorher, Carboloading ab 90 min.'
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
            header: 'Wetter',
            footer: _weatherMessage,
            children: [
              ListTile(
                leading: _loadingWeather
                    ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_outlined),
                title: const Text('Aus der Vorhersage übernehmen'),
                subtitle: const Text('Ort der Route zur Einheit, „Zuhause“ oder dein Standort'),
                enabled: !_loadingWeather,
                onTap: () => unawaited(_weather()),
              ),
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
            ],
          ),
          _Collapsible(
            title: 'Produkte unterwegs',
            summary: selected.isEmpty
                ? (carbs > 0 ? 'Keine gewählt – der Plan nimmt „Gel klassisch“' : 'Keine gewählt')
                : selected.map((product) => product.name).join(', '),
            footer:
                'Getränke decken die Flüssigkeit (mehrere im Wechsel), Gels und Riegel den Rest der Kohlenhydrate, '
                'Salztabletten das Natrium. Eigene Produkte unter Fuel Planner › Meine Produkte.',
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
          _Collapsible(
            title: 'Weitere Einstellungen',
            summary: [
              s.gut.label,
              if (s.caffeine) 'Koffein',
              if (s.fasted) 'nüchtern',
              s.day == null || s.day == CalendarDay.today() ? 'heute' : GermanFormat.date(s.day!),
              if (s.startMinuteOfDay case final start?) 'Start ${fuelClock(start)}',
              'alle ${s.intervalMinutes} min',
            ].join(' · '),
            children: [
              ListTile(dense: true, title: Text('Magen-Darm-Verträglichkeit', style: LiquidText.label(context))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: SegmentedButton<GutTolerance>(
                  segments: [for (final gut in GutTolerance.values) ButtonSegment(value: gut, label: Text(gut.label))],
                  selected: {s.gut},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => _set(s.copyWith(gut: value.first)),
                ),
              ),
              ListTile(
                dense: true,
                title: Text('${s.gut.detail}. Bis ${s.gut.maxCarbsPerHour} g/h.', style: LiquidText.label(context)),
              ),
              ListTile(
                title: const Text('Tag'),
                trailing: Text(s.day == null || s.day == CalendarDay.today() ? 'heute' : GermanFormat.date(s.day!)),
                onTap: _pickDay,
              ),
              ListTile(
                title: const Text('Start'),
                subtitle: const Text('Für Uhrzeiten, Wetter und Koffein-Hinweis'),
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
              SwitchListTile(
                title: const Text('Nüchtern'),
                subtitle: const Text('Mindestens 8 h ohne Essen'),
                value: s.fasted,
                onChanged: (value) => _set(s.copyWith(fasted: value)),
              ),
              SwitchListTile(
                title: const Text('Koffein'),
                subtitle: Text('${GermanFormat.decimal(s.caffeineMgPerKg)} mg/kg, höchstens 6 mg/kg'),
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
              ListTile(dense: true, title: Text('Takt unterwegs', style: LiquidText.label(context))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<int>(
                  segments: [
                    for (final interval in fuelIntervals) ButtonSegment(value: interval, label: Text('$interval min')),
                  ],
                  selected: {s.intervalMinutes},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => _set(s.copyWith(intervalMinutes: value.first)),
                ),
              ),
              NumberField(label: 'Distanz in km (optional)', controller: _distance),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: s.copyWith(title: '').displayTitle,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eingeklappter Abschnitt mit Zusammenfassung.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.title, required this.summary, required this.children, this.footer});

  final String title;
  final String summary;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 12, LiquidSpacing.page, 0),
    child: LiquidCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(title),
          subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
          children: [
            ...children,
            if (footer case final footer?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(footer, style: LiquidText.label(context)),
              ),
          ],
        ),
      ),
    ),
  );
}

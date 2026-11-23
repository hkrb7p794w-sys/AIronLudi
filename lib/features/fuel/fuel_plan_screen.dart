import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/fuel/fuel_diary_writer.dart';
import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import '../../ui/kpi_ring.dart';
import '../../ui/liquid.dart';
import 'fuel_parts.dart';
import 'fuel_scenario_screen.dart';

/// Ein Verpflegungsplan: Zielwerte als Ringe, Kreisdiagramme, Zeitstrahl je Phase, Packliste, Hinweise und
/// „Ins Tagebuch“. Der Plan wird bei jeder Änderung neu gerechnet (Regeln aus `FuelPlanner`).
class FuelPlanScreen extends ConsumerStatefulWidget {
  const FuelPlanScreen({super.key, required this.scenario, required this.productIDs, this.planID});

  final FuelScenario scenario;
  final List<String> productIDs;

  /// Gespeicherter Plan (sonst noch nicht gespeichert).
  final String? planID;

  @override
  ConsumerState<FuelPlanScreen> createState() => _FuelPlanScreenState();
}

class _FuelPlanScreenState extends ConsumerState<FuelPlanScreen> {
  late FuelScenario _scenario = widget.scenario;
  late List<String> _productIDs = widget.productIDs;
  late String? _planID = widget.planID;
  FuelPhase _phase = FuelPhase.intra;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _dirty = widget.planID == null;
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push<(FuelScenario, List<String>)>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FuelScenarioScreen(scenario: _scenario, productIDs: _productIDs, isNew: false),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _scenario = result.$1;
      _productIDs = result.$2;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final store = ref.read(fuelStoreProvider);
    if (store.hasForeignData) {
      _show('Der Fuel Planner gehört einem anderen Benutzer – nichts gespeichert.');
      return;
    }
    final id = _planID ?? newUuid();
    setState(() {
      _planID = id;
      _dirty = false;
    });
    _show('Plan gespeichert');
    await store.savePlan(_scenario, _productIDs, id: id);
  }

  Future<void> _log(FuelPlan plan) async {
    final phases = await showModalBottomSheet<Set<FuelPhase>>(
      context: context,
      showDragHandle: true,
      // Über der Tab-Leiste, damit „Übernehmen“ nicht verdeckt ist.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _LogSheet(plan: plan),
    );
    if (phases == null || phases.isEmpty || !mounted) return;
    final saved = await writeFuelPlanToDiary(ref.read(mealRepositoryProvider), plan, phases: phases);
    if (_planID case final id?) await ref.read(fuelStoreProvider).markLogged(id);
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    final day = plan.scenario.day;
    final where = day == null || day == CalendarDay.today() ? 'heute' : 'am ${GermanFormat.date(day)}';
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${saved.length} ${saved.length == 1 ? 'Eintrag' : 'Einträge'} $where im Tagebuch'),
          action: SnackBarAction(
            label: 'Rückgängig',
            onPressed: () {
              final meals = ref.read(mealRepositoryProvider);
              for (final meal in saved) {
                unawaited(meals.delete(meal.id));
              }
            },
          ),
        ),
      );
  }

  void _show(String text) => ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(fuelStoreProvider);
    final products = store.resolve(_productIDs);
    final plan = FuelPlanner.plan(_scenario, setup: products);
    final s = _scenario;
    final t = plan.targets;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.displayTitle),
        actions: [
          TextButton(
            onPressed: _dirty ? () => unawaited(_save()) : null,
            child: Text(_dirty ? 'Sichern' : 'Gesichert'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 40),
        children: [
          LiquidAppear(child: _header(context, plan)),
          const SizedBox(height: LiquidSpacing.m),
          LiquidCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Text('Unterwegs je Stunde', style: LiquidText.sectionHeader(context)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FuelTargetRing(
                        value: '${t.carbsPerHour}',
                        unit: 'g/h',
                        label: 'Kohlenhydrate',
                        coverage: plan.carbCoverage,
                      ),
                    ),
                    Expanded(
                      child: FuelTargetRing(
                        value: '${t.fluidPerHour}',
                        unit: 'ml/h',
                        label: 'Flüssigkeit',
                        coverage: plan.fluidCoverage,
                      ),
                    ),
                    Expanded(
                      child: FuelTargetRing(
                        value: '${t.sodiumPerHour}',
                        unit: 'mg/h',
                        label: 'Natrium',
                        coverage: plan.sodiumCoverage,
                      ),
                    ),
                  ],
                ),
                Text(
                  [
                    'Schweiß ≈ ${GermanFormat.decimal(t.sweatRate)} l/h${s.sweatRateLitersPerHour != null ? ' (gemessen)' : ''}',
                    if (plan.caffeine case final caffeine?) 'Koffein ${caffeine.total.round()} mg',
                  ].join(' · '),
                  style: LiquidText.label(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: LiquidSpacing.m),
          _charts(context, plan),
          if (plan.carbLoading case final loading?) ...[
            const SizedBox(height: LiquidSpacing.m),
            _carbLoading(context, loading),
          ],
          const SizedBox(height: LiquidSpacing.l),
          SegmentedButton<FuelPhase>(
            segments: [for (final phase in FuelPhase.values) ButtonSegment(value: phase, label: Text(phase.label))],
            selected: {_phase},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _phase = value.first),
          ),
          const SizedBox(height: LiquidSpacing.m),
          LiquidSwitcher(
            child: KeyedSubtree(key: ValueKey(_phase), child: _timeline(context, plan)),
          ),
          if (plan.packing.isNotEmpty) ...[const SizedBox(height: LiquidSpacing.m), _packing(context, plan)],
          if (plan.notes.isNotEmpty) ...[const SizedBox(height: LiquidSpacing.m), _notes(context, plan)],
          const SizedBox(height: LiquidSpacing.l),
          FilledButton.icon(
            onPressed: () => unawaited(_log(plan)),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Ins Ernährungstagebuch übernehmen'),
          ),
          const SizedBox(height: 8),
          Text(
            'Richtwerte nach ACSM, ISSN und aktueller Studienlage – Verträglichkeit im Training testen, nie erst am '
            'Wettkampftag.',
            style: LiquidText.label(context),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, FuelPlan plan) {
    final s = plan.scenario;
    final chips = [
      '${s.minutes} min',
      if (s.distanceMeters case final meters?) '${GermanFormat.decimal(meters / 1000)} km',
      s.isRace ? 'Wettkampf' : s.intensity.label,
      '${GermanFormat.decimal(s.temperatureCelsius)} °C',
      if (s.humidity != FuelHumidity.normal) s.humidity.label,
      if (s.indoor) 'drinnen',
      s.gut.label,
      if (s.fasted) 'nüchtern',
      if (s.day case final day?) GermanFormat.date(day),
      if (s.startMinuteOfDay case final start?) 'Start ${fuelClock(start)}',
    ];
    return LiquidCard(
      onTap: () => unawaited(_edit()),
      semanticLabel: 'Szenario anpassen',
      child: Row(
        spacing: 14,
        children: [
          SportIcon(symbol: s.sport.symbol, color: s.sport.color, size: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(s.sport.label, style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final chip in chips) AppChip(text: chip, color: s.sport.color)],
                ),
              ],
            ),
          ),
          const Icon(Icons.tune),
        ],
      ),
    );
  }

  Widget _charts(BuildContext context, FuelPlan plan) {
    final delivered = plan.intraDelivered;
    final share = delivered.fructoseShare;
    final ratio = plan.targets.ratio;
    final all = plan.all;
    return LiquidCard(
      child: Column(
        spacing: 16,
        children: [
          if (delivered.carbs > 0)
            FuelDonut(
              title: 'Glukose : Fruktose unterwegs',
              center: share == null ? '?' : '${(share * 100).round()} %',
              slices: share == null
                  ? [FuelSlice('Ohne Fruktose-Angabe', delivered.carbs, FuelChartColors.first(context))]
                  : [
                      FuelSlice(
                        'Glukose/Maltodextrin',
                        1 - share,
                        FuelChartColors.first(context),
                        valueText: '${((1 - share) * 100).round()} %',
                      ),
                      FuelSlice(
                        'Fruktose',
                        share,
                        FuelChartColors.second(context),
                        valueText: '${(share * 100).round()} %',
                      ),
                    ],
              caption: ratio == FuelRatio.single
                  ? 'Empfohlen: ${ratio.label}'
                  : 'Empfohlen: ${ratio.label} (${(ratio.fructoseShare * 100).round()} % Fruktose)',
            ),
          FuelDonut(
            title: 'Makros gesamt (${all.kilocalories.round()} kcal)',
            slices: [
              FuelSlice(
                'Kohlenhydrate',
                all.carbs * 4,
                FuelChartColors.first(context),
                valueText: '${all.carbs.round()} g',
              ),
              FuelSlice(
                'Protein',
                all.protein * 4,
                FuelChartColors.second(context),
                valueText: '${all.protein.round()} g',
              ),
              FuelSlice('Fett', all.fat * 9, FuelChartColors.third(context), valueText: '${all.fat.round()} g'),
            ],
            caption: 'Vorher, unterwegs und danach zusammen',
          ),
        ],
      ),
    );
  }

  Widget _carbLoading(BuildContext context, FuelCarbLoading loading) => LiquidCard(
    child: Row(
      spacing: 12,
      children: [
        Icon(Icons.battery_charging_full, color: Theme.of(context).colorScheme.primary),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                loading.days == 2 ? 'Carboloading 36–48 h vorher' : 'Vortag kohlenhydratbetont',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${GermanFormat.decimal(loading.gramsPerKilogram)} g/kg = ${loading.gramsPerDay.round()} g '
                'Kohlenhydrate je Tag${loading.days == 2 ? ' (2 Tage)' : ''}',
              ),
              Text(
                'Ballaststoff- und fettarm: Weißbrot, Reis, Nudeln, Säfte. +1–2 kg auf der Waage sind gewollt.',
                style: LiquidText.label(context),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _timeline(BuildContext context, FuelPlan plan) {
    final steps = plan.steps(_phase);
    final total = plan.total(_phase);
    final start = plan.scenario.startMinuteOfDay;
    String? clock(FuelStep step) {
      if (start == null) return null;
      return fuelClock(start + step.minute + (step.phase == FuelPhase.post ? plan.scenario.minutes : 0));
    }

    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(child: Text(FuelDiary.title(_phase), style: Theme.of(context).textTheme.titleMedium)),
              if (total.carbs > 0 || total.fluid > 0)
                Text(
                  [
                    if (total.carbs > 0) '${total.carbs.round()} g KH',
                    if (total.fluid > 0) '${GermanFormat.decimal(total.fluid / 1000)} l',
                  ].join(' · '),
                  style: LiquidText.label(context),
                ),
            ],
          ),
          if (steps.isEmpty)
            Text(
              _phase == FuelPhase.intra
                  ? 'Unterwegs ist nichts nötig – Wasser nach Durst.'
                  : 'Für diese Phase gibt es nichts Besonderes.',
              style: LiquidText.label(context),
            )
          else
            for (final (index, step) in steps.indexed)
              FuelTimelineRow(step: step, isLast: index == steps.length - 1, clock: clock(step)),
        ],
      ),
    );
  }

  Widget _packing(BuildContext context, FuelPlan plan) => LiquidCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Packliste', style: Theme.of(context).textTheme.titleMedium),
        for (final item in plan.packing)
          Row(
            spacing: 10,
            children: [
              const Icon(Icons.check_box_outline_blank, size: 20),
              Expanded(child: Text(item.line)),
            ],
          ),
        if (plan.intraWater > 0)
          Row(
            spacing: 10,
            children: [
              const Icon(Icons.water_drop_outlined, size: 20),
              Expanded(child: Text('${GermanFormat.decimal(plan.intraWater / 1000)} l Wasser')),
            ],
          ),
      ],
    ),
  );

  Widget _notes(BuildContext context, FuelPlan plan) => Column(
    spacing: 8,
    children: [
      for (final note in plan.notes)
        LiquidCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          tint: note.isWarning ? kpiColor(KpiStatus.moderate) : null,
          child: Row(
            spacing: 10,
            children: [
              Icon(
                note.isWarning ? Icons.warning_amber_rounded : Icons.info_outline,
                color: note.isWarning ? kpiColor(KpiStatus.moderate) : Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              Expanded(child: Text(note.text)),
            ],
          ),
        ),
    ],
  );
}

/// Auswahl der Phasen für das Tagebuch.
class _LogSheet extends StatefulWidget {
  const _LogSheet({required this.plan});

  final FuelPlan plan;

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  late final Set<FuelPhase> _phases = {
    for (final phase in FuelPhase.values)
      if (FuelDiary.entry(widget.plan, phase) != null) phase,
  };

  @override
  Widget build(BuildContext context) {
    final day = widget.plan.scenario.day;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ins Tagebuch übernehmen', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              day == null || day == CalendarDay.today()
                  ? 'Für heute. Die Trainings-Kohlenhydrate zählen dann in deiner Tagesbilanz.'
                  : 'Für den ${GermanFormat.date(day)}. Die Trainings-Kohlenhydrate zählen dann in der Tagesbilanz.',
              style: LiquidText.label(context),
            ),
            const SizedBox(height: 8),
            for (final phase in FuelPhase.values)
              if (FuelDiary.entry(widget.plan, phase) case final entry?)
                CheckboxListTile(
                  value: _phases.contains(phase),
                  onChanged: (value) => setState(() => value == true ? _phases.add(phase) : _phases.remove(phase)),
                  title: Text(entry.title),
                  subtitle: Text(
                    '${(entry.totals[Nutrient.kcal] ?? 0).round()} kcal · '
                    '${(entry.totals[Nutrient.carbs] ?? 0).round()} g KH · '
                    '${Hydration.total(entry.items).total.round()} ml',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _phases.isEmpty ? null : () => Navigator.of(context).pop(_phases),
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      ),
    );
  }
}

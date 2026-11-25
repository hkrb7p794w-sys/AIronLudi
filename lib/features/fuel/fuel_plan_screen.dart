import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../../services/fuel/fuel_diary_writer.dart';
import '../../services/fuel/fuel_store.dart';
import '../../ui/components.dart';
import '../../ui/kpi_ring.dart';
import '../../ui/liquid.dart';
import 'fuel_parts.dart';
import 'fuel_scenario_screen.dart';

part 'fuel_plan_parts.dart';

/// Verknüpfung mit einer geplanten Einheit: erkennt, ob sie sich seit dem Speichern geändert hat.
final class FuelPlanLink {
  const FuelPlanLink({required this.label, required this.matches, required this.update});

  /// „Einheit“ bzw. „Wochenplan“.
  final String label;
  final bool Function(FuelScenario scenario) matches;
  final FuelScenario Function(FuelScenario scenario) update;
}

/// Ein Verpflegungsplan: Zielwerte als Ringe, Kreisdiagramme, Zeitstrahl je Phase, Packliste, Hinweise und
/// „Ins Tagebuch“. Der Plan wird bei jeder Änderung neu gerechnet (Regeln aus `FuelPlanner`).
class FuelPlanScreen extends ConsumerStatefulWidget {
  const FuelPlanScreen({
    super.key,
    required this.scenario,
    required this.productIDs,
    this.planID,
    this.link,
    this.everyday = false,
    this.mealChoices = const {},
  });

  /// Aus einem gespeicherten Plan (mit Alltag-Modus und gewählten Vorschlägen).
  factory FuelPlanScreen.saved(SavedFuelPlan saved, {FuelPlanLink? link}) => FuelPlanScreen(
    scenario: saved.scenario,
    productIDs: saved.productIDs,
    planID: saved.id,
    link: link,
    everyday: saved.everyday,
    mealChoices: saved.mealChoices,
  );

  final FuelScenario scenario;
  final List<String> productIDs;

  /// Unterwegs mit Alltagslebensmitteln statt Sportnahrung.
  final bool everyday;

  /// Gewählter Vorschlag je Zeitpunkt (`phase:minute` → Vorlage).
  final Map<String, String> mealChoices;

  /// Gespeicherter Plan (sonst noch nicht gespeichert).
  final String? planID;
  final FuelPlanLink? link;

  @override
  ConsumerState<FuelPlanScreen> createState() => _FuelPlanScreenState();
}

class _FuelPlanScreenState extends ConsumerState<FuelPlanScreen> {
  late FuelScenario _scenario = widget.scenario;
  late List<String> _productIDs = widget.productIDs;
  late String? _planID = widget.planID;
  FuelPhase _phase = FuelPhase.intra;
  late bool _dirty = widget.planID == null;
  late bool _everyday = widget.everyday;
  late final Map<String, String> _mealChoices = {...widget.mealChoices};

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

  /// Speichert (falls nötig) und gibt die ID zurück; `null`, wenn der Stand einem anderen Benutzer gehört.
  Future<String?> _ensureSaved({bool announce = false}) async {
    final store = ref.read(fuelStoreProvider);
    if (store.hasForeignData) {
      _show('Der Verpflegungsplan gehört einem anderen Benutzer – nichts gespeichert.');
      return null;
    }
    final id = _planID ?? newUuid();
    final needsSave = _dirty || store.plan(id) == null;
    setState(() {
      _planID = id;
      _dirty = false;
    });
    if (announce) _show('Plan gespeichert');
    if (needsSave) {
      await store.savePlan(_scenario, _productIDs, id: id, everyday: _everyday, mealChoices: _mealChoices);
    }
    return id;
  }

  void _updateFromLink() {
    final link = widget.link;
    if (link == null) return;
    setState(() {
      _scenario = link.update(_scenario);
      _dirty = true;
    });
  }

  Future<void> _log(FuelPlan plan) async {
    final meals = ref.read(mealRepositoryProvider);
    final day = plan.scenario.day ?? CalendarDay.today();
    final dayMeals = await meals.day(day);
    if (!mounted) return;
    final conflicts = fuelDiaryConflicts(plan, dayMeals, planID: _planID);
    final previous = _planID == null ? null : ref.read(fuelStoreProvider).plan(_planID!);
    final phases = await showModalBottomSheet<Set<FuelPhase>>(
      context: context,
      showDragHandle: true,
      // Über der Tab-Leiste, damit „Übernehmen“ nicht verdeckt ist.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _LogSheet(plan: plan, conflicts: conflicts, relog: previous?.loggedAt != null),
    );
    if (phases == null || phases.isEmpty || !mounted) return;
    final id = await _ensureSaved();
    if (id == null || !mounted) return;
    final store = ref.read(fuelStoreProvider);
    final before = store.plan(id);
    final result = await writeFuelPlanToDiary(
      meals,
      plan,
      planID: id,
      phases: phases,
      previousMealIDs: before?.loggedMealIDs ?? const [],
    );
    // Unterwegs mit Sportnahrung: was aus dem Vorrat kommt, wird abgebucht.
    final consumed = <String, double>{
      if (phases.contains(FuelPhase.intra) && !_everyday)
        for (final item in plan.packing)
          if (item.fromStock > 0) item.product.id: item.fromStock.toDouble(),
    };
    await store.markLogged(id, [for (final meal in result.saved) meal.id], consumed: consumed);
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    final where = day == CalendarDay.today() ? 'heute' : 'am ${GermanFormat.date(day)}';
    final count = result.saved.length;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$count ${count == 1 ? 'Eintrag' : 'Einträge'} $where im Tagebuch'
            '${result.removed.isNotEmpty ? ' (bisherige ersetzt)' : ''}'
            '${consumed.isEmpty ? '' : ' · ${consumed.values.fold(0.0, (a, b) => a + b).round()} aus dem Vorrat abgebucht'}',
          ),
          action: SnackBarAction(label: 'Rückgängig', onPressed: () => unawaited(_undo(meals, result, before))),
        ),
      );
  }

  Future<void> _undo(MealRepository meals, FuelDiaryResult result, SavedFuelPlan? before) async {
    await undoFuelDiary(meals, result);
    final store = ref.read(fuelStoreProvider);
    final current = _planID == null ? null : store.plan(_planID!);
    if (current == null) return;
    await store.restoreLogged(before ?? current.unlogged());
  }

  /// Plan mit Sportnahrung (gewählt plus Vorrat) oder mit Alltagslebensmitteln.
  FuelPlan _plan(FuelStore store) {
    final day = _scenario.day ?? CalendarDay.today();
    if (_everyday) {
      final snacks = FuelSnacks.choose(_scenario.sport, home: store.profile.homeFilter);
      return FuelPlanner.plan(_scenario, setup: [for (final snack in snacks) snack.product]);
    }
    final chosen = store.resolve(_productIDs);
    final useStock = store.profile.useStockFirst;
    return FuelPlanner.plan(
      _scenario,
      setup: store.setupWithStock(_productIDs, day),
      missingProducts: _productIDs.length - chosen.length,
      stock: useStock ? store.usableStock(day) : const {},
      bestBefore: useStock ? store.bestBefore(day) : const {},
    );
  }

  static String _choiceKey(FuelStep step) => '${step.phase.name}:${step.minute}';

  void _show(String text) => ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(fuelStoreProvider);
    final plan = _plan(store);
    final link = widget.link;
    final stale = link != null && !link.matches(_scenario);
    return Scaffold(
      appBar: AppBar(
        title: Text(_scenario.displayTitle),
        actions: [
          TextButton(
            onPressed: _dirty ? () => unawaited(_ensureSaved(announce: true)) : null,
            child: Text(_dirty ? 'Sichern' : 'Gesichert'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 120),
        children: [
          if (stale) ...[
            LiquidCard(
              tint: kpiColor(KpiStatus.moderate),
              onTap: _updateFromLink,
              semanticLabel: 'Plan an die geänderte ${link.label} anpassen',
              child: Row(
                spacing: 10,
                children: [
                  Icon(Icons.update, color: kpiColor(KpiStatus.moderate)),
                  Expanded(child: Text('Die ${link.label} hat sich geändert. Tippen, um den Plan anzupassen.')),
                ],
              ),
            ),
            const SizedBox(height: LiquidSpacing.m),
          ],
          LiquidAppear(child: _header(context, plan)),
          const SizedBox(height: LiquidSpacing.m),
          _targets(context, plan),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: LiquidSpacing.m),
            for (final note in plan.warnings) _NoteCard(note: note),
          ],
          const SizedBox(height: LiquidSpacing.l),
          SegmentedButton<FuelPhase>(
            segments: [for (final phase in FuelPhase.values) ButtonSegment(value: phase, label: Text(phase.label))],
            selected: {_phase},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _phase = value.first),
          ),
          if (_phase == FuelPhase.intra) ...[
            const SizedBox(height: LiquidSpacing.s),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Sportnahrung'), icon: Icon(Icons.bolt)),
                ButtonSegment(value: true, label: Text('Alltag'), icon: Icon(Icons.kitchen_outlined)),
              ],
              selected: {_everyday},
              onSelectionChanged: (value) => setState(() {
                _everyday = value.first;
                _dirty = true;
              }),
            ),
          ],
          const SizedBox(height: LiquidSpacing.m),
          LiquidSwitcher(
            child: KeyedSubtree(key: ValueKey((_phase, _everyday)), child: _timeline(context, plan, store)),
          ),
          if (_phase == FuelPhase.pre && plan.carbLoading != null) ...[
            const SizedBox(height: LiquidSpacing.m),
            _carbLoading(context, plan.carbLoading!),
          ],
          if (_phase == FuelPhase.intra && plan.packing.isNotEmpty) ...[
            const SizedBox(height: LiquidSpacing.m),
            _packing(context, plan),
            const SizedBox(height: LiquidSpacing.m),
            _howTo(context, plan),
          ],
          const SizedBox(height: LiquidSpacing.m),
          _charts(context, plan),
          if (plan.infos.isNotEmpty) ...[const SizedBox(height: LiquidSpacing.m), _infos(context, plan)],
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
      _duration(s.minutes),
      s.isRace ? 'Wettkampf' : s.intensity.label,
      '${GermanFormat.decimal(s.temperatureCelsius)} °C${s.humidity == FuelHumidity.humid ? ', schwül' : ''}',
      s.gut.label,
      if (s.day case final day?) day == CalendarDay.today() ? 'heute' : GermanFormat.date(day),
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

  /// Wie viel Natrium je Liter Getränk nötig wäre – verglichen mit üblichen Sportgetränken (ACSM 2007).
  static String _sodiumLine(int perLiter) {
    final (low, high) = (FuelRules.acsmDrinkSodium.low, FuelRules.acsmDrinkSodium.high);
    if (perLiter > high) {
      return 'Natrium: ≈ $perLiter mg je Liter Getränk nötig – mehr als Sportgetränke haben ($low–$high mg/l); '
          'den Rest über Salztablette oder salzige Snacks.';
    }
    if (perLiter < low) return 'Natrium: ≈ $perLiter mg je Liter Getränk – ein Sportgetränk deckt das.';
    return 'Natrium: ≈ $perLiter mg je Liter Getränk – wie ein Sportgetränk ($low–$high mg/l).';
  }

  static String _duration(int minutes) =>
      minutes < 60 ? '$minutes min' : '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h';

  Widget _targets(BuildContext context, FuelPlan plan) {
    final t = plan.targets;
    final s = plan.scenario;
    final segments = [
      for (final segment in t.segments)
        if (t.segments.length > 1)
          segment.canEat ? '${segment.sport.label} ${segment.carbsPerHour} g/h' : '${segment.sport.label}: nichts',
    ];
    final sodiumPerLiter = t.sodiumPerLiterDrink;
    final lines = [
      if (segments.isNotEmpty) segments.join(' · '),
      if (t.fluidPerHour > 0)
        'Schweiß ≈ ${GermanFormat.decimal(t.sweatRate)} l/h ${t.sweatEstimated ? '(geschätzt)' : '(gemessen)'} – '
            'nie mehr als ${t.maxFluidPerHour} ml/h trinken',
      if (sodiumPerLiter != null && t.sodiumPerHour > 0) _sodiumLine(sodiumPerLiter),
      if (plan.caffeine case final caffeine?)
        'Koffein ${caffeine.total.round()} mg (${GermanFormat.decimal(caffeine.total / s.weightKilograms)} mg/kg)',
    ];
    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text('UNTERWEGS JE STUNDE', style: LiquidText.sectionHeader(context)),
          Row(
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
                  generousAbove: true,
                ),
              ),
            ],
          ),
          for (final line in lines) Text(line, style: LiquidText.label(context)),
          if (t.sweatEstimated && t.fluidPerHour > 0)
            Text(
              'Tipp: Schweißrate einmal messen (Verpflegung › Mein Profil) – die Schätzung kann um ±0,5 l/h abweichen.',
              style: LiquidText.label(context),
            ),
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

  Widget _timeline(BuildContext context, FuelPlan plan, FuelStore store) {
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
            for (final (index, step) in steps.indexed) ...[
              FuelTimelineRow(step: step, isLast: index == steps.length - 1, clock: clock(step)),
              if (FuelMeals.suggest(step, home: store.profile.homeFilter) case final suggestions
                  when suggestions.isNotEmpty)
                _SuggestionCard(
                  suggestions: suggestions,
                  chosen: _mealChoices[_choiceKey(step)],
                  onChoose: (template) => setState(() {
                    _mealChoices[_choiceKey(step)] = template;
                    _dirty = true;
                  }),
                ),
            ],
          if (_phase != FuelPhase.intra)
            for (final tip in FuelHowTo.phase(_phase, plan.scenario))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                  Expanded(child: Text(tip, style: LiquidText.label(context))),
                ],
              ),
        ],
      ),
    );
  }

  /// „So nimmst du es“: Sportart und je Produkt ein Satz.
  Widget _howTo(BuildContext context, FuelPlan plan) => LiquidCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('So nimmst du es', style: Theme.of(context).textTheme.titleMedium),
        Text(FuelHowTo.sport(plan.scenario.sport)),
        for (final item in plan.packing)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${item.product.name}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: FuelHowTo.product(item.product)),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _packing(BuildContext context, FuelPlan plan) => LiquidCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Packliste', style: Theme.of(context).textTheme.titleMedium),
        for (final item in plan.packing)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              const Icon(Icons.check_box_outline_blank, size: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.line),
                    if (item.stockLine case final stock?)
                      Text(
                        stock,
                        style: LiquidText.label(context)
                            .copyWith(color: item.toBuy > 0 ? kpiColor(KpiStatus.moderate) : kpiColor(KpiStatus.good)),
                      ),
                  ],
                ),
              ),
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

  /// Hinweise kompakt: eingeklappt, nur die erste Zeile sichtbar.
  Widget _infos(BuildContext context, FuelPlan plan) {
    final infos = plan.infos;
    return LiquidCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
          title: Text(infos.length == 1 ? 'Hinweis' : '${infos.length} Hinweise'),
          subtitle: Text(infos.first.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final note in infos)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    const Text('•'),
                    Expanded(child: Text(note.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

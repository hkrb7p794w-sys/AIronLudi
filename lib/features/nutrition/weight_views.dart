import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/platform_names.dart';
import '../../ui/tokens.dart';
import '../evidence/evidence_views.dart';

String _signed(double value) => (value > 0 ? '+' : (value < 0 ? '−' : '')) + GermanFormat.number(value.abs());

String _shortDate(CalendarDay day) => DateFormat('d. MMM', 'de_DE').format(day.referenceDate);

/// Gewichtsverlauf: Wägungen eintragen (oder von Garmin), Trend über 28 Tage und Vorschlag, die Tagesenergie
/// nachzusteuern. Die Anpassung übernimmt die Person selbst; die App ändert nichts ohne Zustimmung
/// (Port von `WeightTrendView.swift`).
class WeightTrendScreen extends ConsumerStatefulWidget {
  const WeightTrendScreen({super.key});

  @override
  ConsumerState<WeightTrendScreen> createState() => _WeightTrendScreenState();
}

class _WeightTrendScreenState extends ConsumerState<WeightTrendScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  DateTime _date = DateTime.now();
  List<StoredMeal> _meals = const [];
  List<GarminActivity> _activities = const [];

  CalendarDay get _today => CalendarDay.today();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    unawaited(_load());
    // Ansehen zählt als Wochen-Check-in (`NutritionCheckIn`) – nach dem ersten Bild, nicht während des Aufbaus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(coachSettingsProvider);
      if (settings.nutrition.lastCheckInDay != _today) {
        settings.nutrition = settings.nutrition.copy()..lastCheckInDay = _today;
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await (ref.read(mealRepositoryProvider).all(), ref.read(activityRepositoryProvider).all()).wait;
    if (!mounted) return;
    setState(() {
      _meals = results.$1;
      _activities = results.$2;
    });
  }

  double? get _parsedInput {
    final value = double.tryParse(_input.text.trim().replaceAll(',', '.'));
    return value != null && value >= 30 && value <= 250 ? value : null;
  }

  void _change(CoachSettings settings, void Function(NutritionSettings nutrition) update) {
    final copy = settings.nutrition.copy();
    update(copy);
    settings.nutrition = copy;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final model = ref.watch(appModelProvider);
    final garmin = model.sync.profile;
    final today = _today;
    final entries = WeightTrend.merged(model.allWeights);
    final nutrition = settings.nutrition;
    final body = nutrition.profile(garmin, on: today);
    final safety = GoalRules.weightGuard(nutrition, body);
    final result = WeightTrend.trend(entries, today: today);
    final expenditure = _expenditure(settings, garmin, entries, body);
    // Geplantes Tempo in % pro Woche; ohne Tempo bei Ab- oder Zunehmen gibt es keinen Vergleich.
    final planKnown = nutrition.weeklyWeightChangePercent != null || nutrition.goal == NutritionGoal.maintain;
    final plannedPercent = nutrition.weeklyWeightChangePercent;
    final forecast = plannedPercent != null && plannedPercent < 0
        ? WeightForecast.compute(
            currentKilograms: entries.lastOrNull?.kilograms ?? body.weightKilograms,
            weeklyChangePercent: plannedPercent,
            heightCentimeters: body.heightCentimeters,
            maintenanceKilocalories: NutritionPlanner.mifflinStJeor(body) * nutrition.activityFactor,
            target: settings.profile.targets.targetWeightKilograms,
            today: today,
          )
        : null;
    final theme = Theme.of(context);
    TextStyle? secondary([Color? color]) =>
        theme.textTheme.bodyMedium?.copyWith(color: color ?? theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Gewichtsverlauf')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Wägung eintragen',
            footer: 'Wägungen aus deinen Datenquellen (Waage, Uhr, Gesundheitsdaten) kommen beim Abruf dazu; deine Eingabe hat Vorrang.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Gewicht', suffixText: 'kg'),
                ),
              ),
              ListTile(
                title: const Text('Tag'),
                trailing: Text(GermanFormat.date(CalendarDay.fromDate(_date))),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_circle),
                title: const Text('Eintragen'),
                enabled: _parsedInput != null,
                onTap: () {
                  final value = _parsedInput;
                  if (value == null) return;
                  settings.logWeight(value, on: CalendarDay.fromDate(_date));
                  model.refreshGoalGuards();
                  _input.clear();
                  _focus.unfocus();
                },
              ),
            ],
          ),
          if (result != null)
            _trendSection(result, entries, settings, expenditure, safety, planKnown, plannedPercent)
          else
            FormSection(
              children: [
                ListTile(
                  title: Text(
                    'Für einen Trend braucht die App mindestens ${WeightTrend.minimumEntries} Wägungen über '
                    '${WeightTrend.minimumSpanDays} Tage. Am besten täglich morgens nach dem Aufstehen wiegen.',
                    style: secondary(),
                  ),
                ),
              ],
            ),
          if (forecast != null) _forecastSection(forecast),
          if (safety != WeightGoalGuard.noTargets)
            if (_intakeForecast(
                  settings,
                  garmin,
                  body,
                  expenditure,
                  entries.lastOrNull?.kilograms ?? body.weightKilograms,
                )
                case final intakeForecast?)
              _intakeForecastSection(intakeForecast, measured: expenditure?.$1.plausible ?? false),
          if (expenditure != null && safety != WeightGoalGuard.noTargets)
            _expenditureSection(expenditure.$1, expenditure.$2, settings, safety),
          if (nutrition.energyAdjustmentKilocalories != 0)
            FormSection(
              footer: 'Die Anpassung gilt für alle Tagesziele. Die Untergrenze für die Energieverfügbarkeit bleibt bestehen.',
              children: [
                LabeledRow(
                  label: 'Aktuelle Anpassung',
                  value:
                      '${nutrition.energyAdjustmentKilocalories > 0 ? '+' : '−'}'
                      '${nutrition.energyAdjustmentKilocalories.abs().toInt()} kcal pro Tag',
                ),
                ListTile(
                  title: Text('Zurücksetzen', style: TextStyle(color: AppColors.of(context).alert)),
                  onTap: () => _change(settings, (value) => value.energyAdjustmentKilocalories = 0),
                ),
              ],
            ),
          FormSection(
            header: 'Verlauf',
            children: [
              if (entries.isEmpty) ListTile(title: Text('Noch keine Wägungen.', style: secondary())),
              for (final entry in entries.reversed.take(60))
                Dismissible(
                  key: ValueKey(entry.id),
                  direction: entry.source == WeightSource.manual ? DismissDirection.endToStart : DismissDirection.none,
                  background: Container(color: AppColors.of(context).alert),
                  onDismissed: (_) => settings.weights = [
                    for (final other in settings.weights)
                      if (other.day != entry.day) other,
                  ],
                  child: ListTile(
                    title: Text(GermanFormat.date(entry.day)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${GermanFormat.number(entry.kilograms)} kg',
                          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          weightSourceIcon(entry.source),
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                          semanticLabel: weightSourceLabel(entry.source),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Verbrauch laut Ernährung und Gewicht mit dem Bedarf laut Formel an denselben Tagen.
  Map<CalendarDay, double> _intake() {
    final intake = <CalendarDay, double>{};
    for (final meal in _meals) {
      intake[meal.day] = (intake[meal.day] ?? 0) + (NutritionSummary.totals(meal.items)[Nutrient.kcal] ?? 0);
    }
    return intake;
  }

  /// Bedarf laut Formel ohne Ziel, Anpassungen und eigene Makros (Grundumsatz × Alltag + Training des Tages), Schnitt
  /// über die Tage mit Einträgen seit [start].
  double? _formulaMaintenance(CoachSettings settings, GarminProfile? garmin, Iterable<CalendarDay> days) {
    final values = [
      for (final day in days)
        NutritionPlanner.compute(
          activities: _activities.where((activity) => activity.day == day).toList(),
          planItems: const [],
          settings: settings.nutrition,
          garminProfile: garmin,
          day: day,
          hasGarminData: true,
        ).maintenanceKilocalories,
    ];
    return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  }

  (ExpenditureResult, double)? _expenditure(
    CoachSettings settings,
    GarminProfile? garmin,
    List<WeightEntry> entries,
    BodyProfile body,
  ) {
    final today = _today;
    final intake = _intake();
    final result = Expenditure.estimate(
      intake: intake,
      weights: entries,
      today: today,
      basalMetabolicRate: NutritionPlanner.mifflinStJeor(body),
    );
    if (result == null) return null;
    final start = today.adding(-Expenditure.windowDays);
    final formula = _formulaMaintenance(settings, garmin, intake.keys.where((day) => day >= start && day < today));
    return formula == null ? null : (result, formula);
  }

  /// „Wenn du weiter so isst“: gegen den gemessenen Verbrauch, sonst gegen die Formel.
  IntakeForecastResult? _intakeForecast(
    CoachSettings settings,
    GarminProfile? garmin,
    BodyProfile body,
    (ExpenditureResult, double)? expenditure,
    double weight,
  ) {
    final today = _today;
    final intake = _intake();
    final measured = expenditure != null && expenditure.$1.plausible ? expenditure.$1.kilocalories : null;
    final start = today.adding(-IntakeForecast.windowDays);
    final maintenance =
        measured ?? _formulaMaintenance(settings, garmin, intake.keys.where((day) => day >= start && day < today));
    if (maintenance == null) return null;
    return IntakeForecast.compute(intake: intake, maintenance: maintenance, weightKilograms: weight, today: today);
  }

  Widget _intakeForecastSection(IntakeForecastResult result, {required bool measured}) {
    final balance = result.dailyBalance.round();
    return FormSection(
      header: 'Wenn du weiter so isst',
      footer:
          'Geglätteter Schnitt der letzten ${result.days} erfassten Tage gegen deinen ${measured ? 'gemessenen ' : ''}'
          'Bedarf. Realistisch heißt: höchstens 1 % des Körpergewichts pro Woche ab- bzw. 0,5 % zunehmen – mehr ist '
          'kein Fett- oder Muskelgewebe, sondern Wasser und Glykogen. Die ersten Tage zeigt die Waage deshalb oft '
          'mehr oder weniger als hier. Der Körper passt sich an; die App rechnet nicht weiter als 4 Wochen.',
      children: [
        ListTile(title: Text(IntakeForecast.sentence(result))),
        LabeledRow(label: 'Im Schnitt gegessen', value: '${result.averageIntake.round()} kcal'),
        LabeledRow(label: 'Bedarf', value: '${result.maintenance.round()} kcal'),
        LabeledRow(
          label: 'Bilanz',
          value:
              '${balance > 0
                  ? '+'
                  : balance < 0
                  ? '−'
                  : ''}${balance.abs()} kcal pro Tag',
        ),
        LabeledRow(
          label: 'Pro Woche',
          value:
              '${result.weeklyKilograms > 0
                  ? '+'
                  : result.weeklyKilograms < 0
                  ? '−'
                  : ''}'
              '${GermanFormat.decimal(result.weeklyKilograms.abs())} kg',
        ),
        if (result.capped)
          ListTile(
            leading: Icon(Icons.info_outline, color: AppColors.of(context).caution),
            title: Text(
              'Rechnerisch wären es ${GermanFormat.decimal(result.rawWeeklyKilograms.abs())} kg pro Woche. So schnell '
              'geht es als Körpergewebe nicht – ein großer Teil wäre Wasser, und bei starkem Defizit leidet die '
              'Muskulatur.',
            ),
          ),
      ],
    );
  }

  Widget _trendSection(
    WeightTrendResult result,
    List<WeightEntry> entries,
    CoachSettings settings,
    (ExpenditureResult, double)? expenditure,
    WeightGoalGuard safety,
    bool planKnown,
    double? plannedPercent,
  ) {
    final theme = Theme.of(context);
    final today = _today;
    final start = today.adding(-(WeightTrend.windowDays - 1));
    final recent = entries.where((entry) => entry.day >= start).toList();
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final List<Widget> advice;
    if (expenditure != null && expenditure.$1.plausible && safety != WeightGoalGuard.noTargets) {
      advice = [
        ListTile(
          title: Text('Die Anpassung ergibt sich aus deinem gemessenen Verbrauch (siehe unten).', style: secondary),
        ),
      ];
    } else if (planKnown) {
      final value = WeightTrend.advice(
        result: result,
        plannedPercent: plannedPercent,
        currentAdjustment: settings.nutrition.energyAdjustmentKilocalories,
        safety: safety,
      );
      advice = [
        ListTile(
          leading: Icon(
            value.kind == WeightAdviceKind.onTrack ? Icons.check_circle : Icons.sync,
            color: switch (value.kind) {
              WeightAdviceKind.tooFast => AppColors.of(context).caution,
              WeightAdviceKind.onTrack => AppColors.of(context).good,
              _ => AppColors.of(context).info,
            },
          ),
          title: Text(value.message),
        ),
        if (value.kilocalories != 0)
          ListTile(
            leading: const Icon(Icons.check),
            title: Text(
              'Übernehmen (${value.kilocalories > 0 ? '+' : '−'}${value.kilocalories.abs().toInt()} kcal pro Tag)',
            ),
            onTap: () => _change(settings, (nutrition) => nutrition.energyAdjustmentKilocalories += value.kilocalories),
          ),
        EvidenceDisclosure(ruleIDs: value.evidenceIDs),
      ];
    } else {
      advice = [
        ListTile(
          title: Text(
            'Lege im Profil ein Zieltempo fest, dann vergleicht die App deinen Verlauf damit und schlägt Anpassungen vor.',
            style: secondary,
          ),
        ),
      ];
    }
    final values = [for (final entry in recent) entry.kilograms];
    final minY = values.isEmpty ? 0.0 : (values.reduce((a, b) => a < b ? a : b) - 1).floorToDouble();
    final maxY = values.isEmpty ? 1.0 : (values.reduce((a, b) => a > b ? a : b) + 1).ceilToDouble();
    return FormSection(
      header: 'Trend (${result.entries} Wägungen, ${result.spanDays} Tage)',
      children: [
        Semantics(
          label: 'Wägungen der letzten vier Wochen',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: SizedBox(
              height: 160,
              child: ScatterChart(
                ScatterChartData(
                  minX: 0,
                  maxX: (WeightTrend.windowDays - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  scatterSpots: [
                    for (final entry in recent)
                      ScatterSpot(
                        start.daysUntil(entry.day).toDouble(),
                        entry.kilograms,
                        dotPainter: FlDotCirclePainter(
                          radius: 4,
                          color: entry.source == WeightSource.manual
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 7,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(_shortDate(start.adding(value.round())), style: AppText.caption(context)),
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ),
        ),
        LabeledRow(label: 'Trendgewicht heute', value: '${GermanFormat.number(result.trendKilograms)} kg'),
        LabeledRow(label: 'Änderung pro Woche', value: '${_signed(result.weeklyPercent)} %'),
        ...advice,
      ],
    );
  }

  /// Prognose beim Abnehmen aus dem geplanten Tempo (gesund: 0,5–1 % pro Woche, höchstens 25 % Defizit).
  Widget _forecastSection(WeightForecastResult forecast) => FormSection(
    header: 'Prognose',
    footer:
        'Gesund und nachhaltig: etwa 0,5 % des Körpergewichts pro Woche, höchstens 1 %, das Defizit höchstens ein '
        'Viertel des Bedarfs und nie unter BMI 18,5 (${GermanFormat.number(forecast.floorKilograms)} kg). 7.700 kcal '
        'je kg sind eine Näherung – Wasser und Anpassung des Stoffwechsels verschieben den Verlauf, deshalb steuert die '
        'App anhand deiner Wägungen nach.'
        '${forecast.deficitCapped ? ' Dein Wunschtempo wurde auf ein Viertel des Bedarfs begrenzt.' : ''}',
    children: [
      LabeledRow(label: 'Tempo', value: '${GermanFormat.number(forecast.weeklyKilograms)} kg pro Woche'),
      LabeledRow(label: 'Geschätztes Defizit', value: 'etwa ${forecast.dailyDeficit.toInt()} kcal pro Tag'),
      for (final point in forecast.points)
        LabeledRow(
          label: 'In ${point.weeks} Wochen (${_shortDate(point.day)})',
          value: '${GermanFormat.number(point.kilograms)} kg',
        ),
      if ((forecast.target, forecast.weeksToTarget, forecast.targetDay) case (final target?, final weeks?, final day?))
        LabeledRow(
          label: 'Ziel ${GermanFormat.number(target)} kg',
          value: 'in etwa $weeks Wochen (${DateFormat('EEE, d. MMM', 'de_DE').format(day.referenceDate)})',
        ),
      const EvidenceDisclosure(ruleIDs: ['weightloss.rate', 'weightloss.protein', 'weightloss.exercise']),
    ],
  );

  Widget _expenditureSection(ExpenditureResult result, double formula, CoachSettings settings, WeightGoalGuard safety) {
    final current = settings.nutrition.energyAdjustmentKilocalories;
    final proposal = result.plausible
        ? Expenditure.adjustment(result, formulaMaintenance: formula, current: current, safety: safety)
        : null;
    return FormSection(
      header: 'Gemessener Verbrauch',
      footer:
          'Aus ${result.loggedDays} Tagen mit erfassten Mahlzeiten'
          '${result.excludedDays > 0 ? ' (${result.excludedDays} unvollständige Tage nicht gezählt)' : ''}'
          ' und dem Gewichtstrend. Nur so genau wie deine Erfassung.',
      children: [
        LabeledRow(label: 'Verbrauch laut Verlauf', value: '${GermanFormat.number(result.kilocalories)} kcal'),
        LabeledRow(label: 'Laut Formel', value: '${GermanFormat.number((formula / 10).roundToDouble() * 10)} kcal'),
        LabeledRow(label: 'Im Schnitt gegessen', value: '${GermanFormat.number(result.averageIntake)} kcal'),
        if (!result.plausible)
          ListTile(
            leading: Icon(Icons.warning, color: AppColors.of(context).caution),
            title: Text(
              'Das Ergebnis ist unplausibel – vermutlich fehlen Mahlzeiten. Erfasse alles, was du isst, auch Getränke '
              'und Snacks.',
              style: TextStyle(color: AppColors.of(context).caution),
            ),
          )
        else if (proposal != null)
          ListTile(
            leading: const Icon(Icons.check),
            title: Text(
              proposal == 0
                  ? 'Anpassung zurücksetzen (Formel passt)'
                  : 'Tagesziele um ${proposal > 0 ? '+' : '−'}${proposal.abs().toInt()} kcal anpassen',
            ),
            onTap: () => _change(settings, (nutrition) => nutrition.energyAdjustmentKilocalories = proposal),
          )
        else
          ListTile(
            leading: Icon(Icons.check_circle, color: AppColors.of(context).good),
            title: Text(
              'Deine Tagesziele passen zu deinem Verbrauch.',
              style: TextStyle(color: AppColors.of(context).good),
            ),
          ),
        const EvidenceDisclosure(ruleIDs: ['energy.measured']),
      ],
    );
  }
}

IconData weightSourceIcon(WeightSource source) => switch (source) {
  WeightSource.manual => Icons.edit,
  WeightSource.garmin => Icons.watch,
  WeightSource.health => Icons.favorite,
};

String weightSourceLabel(WeightSource source) => switch (source) {
  WeightSource.manual => 'eigene Eingabe',
  WeightSource.garmin => 'Garmin',
  WeightSource.health => healthStoreName,
};

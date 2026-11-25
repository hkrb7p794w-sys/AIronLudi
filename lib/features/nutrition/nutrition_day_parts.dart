part of 'nutrition_screen.dart';

/// Wochenstreifen: Tag antippen zum Ansehen und Nachtragen.
class _DayStrip extends StatefulWidget {
  const _DayStrip({required this.selected, required this.today, required this.onSelect});

  final CalendarDay selected;
  final CalendarDay today;
  final ValueChanged<CalendarDay> onSelect;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = widget.today;
    final monday = today.adding(-today.weekdayIndex + _weekOffset * 7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Vorige Woche',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _weekOffset -= 1),
          ),
          for (var offset = 0; offset < 7; offset++)
            Expanded(
              child: () {
                final day = monday.adding(offset);
                final future = today < day;
                return Semantics(
                  label: DateFormat('EEEE, d. MMMM', 'de_DE').format(day.referenceDate),
                  selected: day == widget.selected,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: future ? null : () => widget.onSelect(day),
                    child: Container(
                      // Mindesthöhe statt fester Höhe: wächst mit großer Schrift mit.
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: day == widget.selected ? scheme.primary.withValues(alpha: 0.2) : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(Weekday.of(day).short, style: AppText.caption(context)),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: future ? scheme.onSurfaceVariant.withValues(alpha: 0.5) : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
            ),
          IconButton(
            tooltip: 'Nächste Woche',
            icon: const Icon(Icons.chevron_right),
            onPressed: _weekOffset >= 0 ? null : () => setState(() => _weekOffset += 1),
          ),
        ],
      ),
    );
  }
}

/// Auf einen Blick: übrige kcal im Ring, Protein/KH/Fett als „noch … g“.
class _BudgetSection extends StatelessWidget {
  const _BudgetSection({
    required this.targets,
    required this.totals,
    required this.intake,
    required this.adjustment,
    required this.onAdjust,
  });

  final NutritionTargets targets;
  final NutrientValues totals;
  final FoodIntake intake;

  /// Anpassung für den angezeigten Tag (Refeed, Ruhetag, eigene kcal).
  final DayAdjustment? adjustment;
  final ValueChanged<DayAdjustment?> onAdjust;

  String get _adjustmentText => switch (adjustment) {
    null => 'Normal',
    DayAdjustment(kind: DayAdjustmentKind.custom, :final kilocalories) =>
      '${kilocalories >= 0 ? '+' : '−'}${kilocalories.abs().round()} kcal',
    final value => value.kind.label,
  };

  @override
  Widget build(BuildContext context) {
    final kcal = NutritionBudget.line(Nutrient.kcal, targets: targets.values, totals: totals, intake: intake);
    return FormSection(
      header: '${targets.dayType.label} · ${targets.source.rawValue}',
      footer: targets.customMacros
          ? ['Eigene Makroziele (Einstellungen › Ernährung).', ...targets.macroNotes].join(' ')
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (kcal != null) _CalorieRing(line: kcal),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    for (final nutrient in NutritionBudget.main)
                      if (NutritionBudget.line(nutrient, targets: targets.values, totals: totals, intake: intake)
                          case final line?)
                        _MacroBar(line: line),
                  ],
                ),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Tagesziel anpassen'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_adjustmentText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const DisclosureChevron(),
            ],
          ),
          onTap: () async {
            final result = await showModalBottomSheet<(DayAdjustment?,)>(
              context: context,
              showDragHandle: true,
              builder: (_) => DayAdjustmentSheet(initial: adjustment),
            );
            if (result != null) onAdjust(result.$1);
          },
        ),
        // Makroziele dauerhaft in Gramm oder Prozent, auch getrennt für Ruhetage.
        ListTile(
          leading: const Icon(Icons.pie_chart_outline),
          title: const Text('Makroziele'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                targets.customMacros ? 'Eigene' : 'Automatisch',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const DisclosureChevron(),
            ],
          ),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NutritionSettingsScreen())),
        ),
      ],
    );
  }
}

/// Tagesziel für einen Tag anpassen: normal, Refeed, Ruhetag oder eigene ±kcal. Schutzgrenzen gelten weiter.
class DayAdjustmentSheet extends StatefulWidget {
  const DayAdjustmentSheet({super.key, required this.initial});

  final DayAdjustment? initial;

  @override
  State<DayAdjustmentSheet> createState() => _DayAdjustmentSheetState();
}

class _DayAdjustmentSheetState extends State<DayAdjustmentSheet> {
  late DayAdjustmentKind? _kind = widget.initial?.kind;
  late double _kcal = widget.initial?.kind == DayAdjustmentKind.custom ? widget.initial!.kilocalories : 200;

  static String _detail(DayAdjustmentKind? kind) => switch (kind) {
    null => 'Ziele nach Training, Plan und deinem Ziel.',
    DayAdjustmentKind.refeed => 'Heute ohne Defizit, das Plus als Kohlenhydrate – z. B. vor einem langen Training.',
    DayAdjustmentKind.rest => 'Wie ein Tag ohne Training, auch wenn eine Einheit geplant ist.',
    DayAdjustmentKind.custom => 'Eigene Änderung um bis zu ±500 kcal.',
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final kind in <DayAdjustmentKind?>[null, ...DayAdjustmentKind.values])
            ListTile(
              leading: Icon(
                _kind == kind ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: _kind == kind ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(kind?.label ?? 'Normal'),
              subtitle: Text(_detail(kind)),
              onTap: () => setState(() => _kind = kind),
            ),
          if (_kind == DayAdjustmentKind.custom)
            ListTile(
              title: Text('${_kcal >= 0 ? '+' : '−'}${_kcal.abs().round()} kcal'),
              subtitle: Slider(
                value: _kcal,
                min: -DayAdjustment.maxKilocalories,
                max: DayAdjustment.maxKilocalories,
                divisions: 20,
                onChanged: (value) => setState(() => _kcal = value),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Gilt nur für diesen Tag. Höchstens ein Viertel Defizit und die Mindest-Energieverfügbarkeit bleiben '
              'immer bestehen.',
              style: AppText.caption(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop((
                switch (_kind) {
                  null => null,
                  DayAdjustmentKind.custom => DayAdjustment(kind: DayAdjustmentKind.custom, kilocalories: _kcal),
                  final kind => DayAdjustment(kind: kind),
                },
              )),
              child: const Text('Übernehmen'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CalorieRing extends StatelessWidget {
  const _CalorieRing({required this.line});

  final BudgetLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = line.remaining.abs().round();
    return Semantics(
      label: '$amount Kilokalorien ${line.remaining >= 0 ? 'übrig' : 'über dem Ziel'}',
      excludeSemantics: true,
      child: SizedBox(
        width: 112,
        height: 112,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: line.progress,
                strokeWidth: 12,
                strokeCap: StrokeCap.round,
                backgroundColor: scheme.surfaceContainerHighest,
                color: line.isOver ? AppColors.of(context).alert : scheme.primary,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$amount', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  line.remaining >= 0 ? 'kcal übrig' : 'kcal drüber',
                  style: AppText.caption(context).copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.line});

  final BudgetLine line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bei wenig Breite (kleines Gerät, große Schrift) rutscht der Rest in die nächste Zeile statt überzulaufen.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          children: [
            Text(line.nutrient.label),
            Text(
              NutritionBudget.remainingText(line),
              style: TextStyle(fontWeight: FontWeight.bold, color: line.isOver ? AppColors.of(context).alert : null),
            ),
          ],
        ),
        const SizedBox(height: 3),
        LiquidProgressBar(value: line.progress, color: line.isOver ? AppColors.of(context).alert : null),
      ],
    ),
  );
}

/// Wasser mit Glas-Knopf: Antippen +250 ml, gedrückt halten für andere Mengen.
class _WaterSection extends StatelessWidget {
  const _WaterSection({required this.water, required this.target, required this.onAdd});

  final HydrationTotal water;
  final double target;
  final ValueChanged<double> onAdd;

  @override
  Widget build(BuildContext context) => FormSection(
    children: [
      ListTile(
        leading: const Icon(Icons.water_drop, color: AppPalette.cyan),
        title: Text('Wasser ${GermanFormat.number(water.total / 1000)} / ${GermanFormat.decimal(target / 1000)} l'),
        subtitle: water.food >= 50 ? Text('davon ${GermanFormat.decimal(water.food / 1000)} l aus Essen') : null,
        trailing: GestureDetector(
          onLongPress: () async {
            final box = context.findRenderObject()! as RenderBox;
            final position = box.localToGlobal(Offset(box.size.width, 0));
            final amount = await showMenu<double>(
              context: context,
              position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
              items: [
                for (final amount in const [150.0, 330.0, 500.0, 750.0])
                  PopupMenuItem(value: amount, child: Text('${amount.round()} ml')),
              ],
            );
            if (amount != null) onAdd(amount);
          },
          child: Semantics(
            hint: 'Gedrückt halten für andere Mengen',
            child: FilledButton.tonalIcon(
              onPressed: () => onAdd(250),
              icon: const Icon(Icons.add),
              label: const Text('+250 ml'),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Tagesübersicht als Kacheln: gegessen, Ziel, übrig, Fortschritt, Mahlzeiten und Makros.
class _DaySummarySection extends StatelessWidget {
  const _DaySummarySection({required this.summary, required this.totals, required this.targets});

  final NutritionDaySummary summary;
  final NutrientValues totals;
  final NutrientValues? targets;

  @override
  Widget build(BuildContext context) {
    final remaining = summary.remaining;
    final tiles = [
      ('Gegessen', '${summary.eaten.round()}', 'kcal'),
      ('Ziel', summary.goal == null ? '–' : '${summary.goal!.round()}', 'kcal'),
      ((remaining ?? 0) >= 0 ? 'Übrig' : 'Drüber', remaining == null ? '–' : '${remaining.abs().round()}', 'kcal'),
      ('Fortschritt', summary.percent?.toString() ?? '–', '%'),
      ('Mahlzeiten', '${summary.meals}', 'erfasst'),
      for (final nutrient in const [Nutrient.protein, Nutrient.carbs, Nutrient.fat])
        (
          nutrient.label,
          '${(totals[nutrient] ?? 0).round()}',
          targets?[nutrient] == null ? 'g' : 'von ${targets![nutrient]!.round()} g',
        ),
    ];
    final scheme = Theme.of(context).colorScheme;
    return FormSection(
      header: 'Tagesübersicht',
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (title, value, unit) in tiles)
                Container(
                  width: 96,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.caption(context).copyWith(color: scheme.onSurfaceVariant)),
                      Text(value, style: LiquidText.kpi(context, size: 20), maxLines: 1),
                      Text(unit, style: AppText.caption(context).copyWith(color: scheme.onSurfaceVariant), maxLines: 1),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Alle Nährstoffe mit Ziel – aufklappbar, damit oben nur das Wichtige steht.
class _TargetsSection extends StatelessWidget {
  const _TargetsSection({required this.targets, required this.intake});

  static const primary = [
    Nutrient.kcal,
    Nutrient.protein,
    Nutrient.carbs,
    Nutrient.fat,
    Nutrient.fiber,
    Nutrient.water,
  ];

  final NutritionTargets targets;
  final FoodIntake intake;

  static String format(double value) => value >= 10 ? '${value.round()}' : GermanFormat.decimal(value);

  @override
  Widget build(BuildContext context) {
    final order = [...primary, ...Nutrient.values.where((nutrient) => !primary.contains(nutrient))];
    final reference = targets.referenceWeightKilograms < targets.profile.weightKilograms
        ? ' (bezogen auf ${GermanFormat.number(targets.referenceWeightKilograms.roundToDouble())} kg).'
        : '.';
    return FormSection(
      footer:
          'Grundumsatz ${targets.basalMetabolicRate.toInt()} kcal, Training ${targets.exerciseKilocalories.toInt()} kcal, '
          'Protein ${GermanFormat.decimal(targets.proteinPerKilogram)} g/kg$reference'
          '${targets.energyAvailabilityFloorApplied ? ' Energie auf Mindestverfügbarkeit angehoben.' : ''}',
      children: [
        ExpansionTile(
          title: const Text('Alle Nährstoffe'),
          children: [
            for (final nutrient in order)
              () {
                // Ohne Wert in allen Positionen: unbekannt statt 0 (kein vorgetäuschter Mangel); mit Lücken: Untergrenze.
                final unknown = intake.isUnknown(nutrient);
                final missing = intake.missingCount(nutrient);
                final actual = unknown ? null : intake.totals[nutrient];
                final target = targets.values[nutrient];
                final percent = unknown ? null : NutritionSummary.percent(actual, target);
                final actualText = unknown
                    ? '–'
                    : '${intake.isPartial(nutrient) ? '≥ ' : ''}'
                          '${(target ?? 0) >= 10 ? '${(actual ?? 0).round()}' : format(actual ?? 0)}';
                final gap = unknown
                    ? 'Keine Angabe in den Einträgen'
                    : intake.isPartial(nutrient)
                    ? '$missing von ${intake.itemCount} ${intake.itemCount == 1 ? 'Eintrag' : 'Einträgen'} ohne Angabe'
                    : null;
                return ListTile(
                  title: Text(nutrient.label),
                  trailing: Text('$actualText / ${target == null ? '–' : format(target)} ${nutrient.unit}'),
                  subtitle: percent == null && gap == null
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (percent != null)
                              LiquidProgressBar(
                                value: (percent > 100 ? 100 : percent) / 100,
                                color: nutrient.isReference
                                    ? null
                                    : nutrient.isUpperLimit
                                    ? (percent > 100 ? AppColors.of(context).alert : AppColors.of(context).caution)
                                    : (percent >= 100 ? AppColors.of(context).good : null),
                              ),
                            if (gap != null) Text(gap, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                );
              }(),
          ],
        ),
      ],
    );
  }
}

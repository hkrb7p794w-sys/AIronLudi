part of 'fuel_plan_screen.dart';

/// Konkreter Vorschlag mit herkömmlichen Lebensmitteln; „Andere Idee“ wechselt durch die Vorschläge.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestions, required this.chosen, required this.onChoose});

  final List<FuelMealSuggestion> suggestions;
  final String? chosen;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final index = suggestions.indexWhere((x) => x.template.id == chosen);
    final current = suggestions[index < 0 ? 0 : index];
    final coverage = current.carbCoverage;
    final scheme = Theme.of(context).colorScheme;
    // Auf schmalen Geräten (iPhone SE) weniger einrücken, damit der Vorschlag lesbar bleibt.
    final narrow = MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: EdgeInsets.only(left: narrow ? 28 : 120, bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(LiquidRadii.inner),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(current.template.name, style: LiquidText.label(context).copyWith(fontWeight: FontWeight.w600)),
            Text(current.text),
            Text(
              [
                '≈ ${current.amounts.carbs.round()} g KH',
                if (current.amounts.protein >= 5) '${current.amounts.protein.round()} g Protein',
                if (coverage != null && !current.covers) 'deckt ${(coverage * 100).round()} %',
                if (current.missing.isNotEmpty) 'fehlt: ${current.missing.map((f) => f.name).join(', ')}',
              ].join(' · '),
              style: LiquidText.label(context).copyWith(color: current.covers ? null : kpiColor(KpiStatus.moderate)),
            ),
            if (suggestions.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      onChoose(suggestions[(suggestions.indexOf(current) + 1) % suggestions.length].template.id),
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Andere Idee'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final FuelNote note;

  @override
  Widget build(BuildContext context) => LiquidCard(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    tint: kpiColor(KpiStatus.moderate),
    child: Row(
      spacing: 10,
      children: [
        Icon(Icons.warning_amber_rounded, color: kpiColor(KpiStatus.moderate), size: 20),
        Expanded(child: Text(note.text)),
      ],
    ),
  );
}

/// Auswahl der Phasen für das Tagebuch. Phasen, die schon eine eingetragene Mahlzeit abdeckt, sind abgewählt.
class _LogSheet extends StatefulWidget {
  const _LogSheet({required this.plan, required this.conflicts, required this.relog});

  final FuelPlan plan;
  final Map<FuelPhase, StoredMeal> conflicts;

  /// Schon einmal übernommen: die bisherigen Einträge werden ersetzt.
  final bool relog;

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  late final Set<FuelPhase> _phases = {
    for (final phase in FuelPhase.values)
      if (FuelDiary.entry(widget.plan, phase) != null && !widget.conflicts.containsKey(phase)) phase,
  };

  String _subtitle(FuelDiaryEntry entry) {
    final values =
        '${(entry.totals[Nutrient.kcal] ?? 0).round()} kcal · ${(entry.totals[Nutrient.carbs] ?? 0).round()} g KH · '
        '${Hydration.total(entry.items).total.round()} ml';
    final conflict = widget.conflicts[entry.phase];
    if (conflict != null) {
      final at = conflict.createdAt;
      return '$values\nSchon eingetragen: „${conflict.title}“ um ${at.hour}:${at.minute.toString().padLeft(2, '0')} – '
          'nicht doppelt zählen';
    }
    if (entry.phase != FuelPhase.intra) return '$values\nPlatzhalter – wird durch deine echte Mahlzeit ersetzt';
    return values;
  }

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
              [
                day == null || day == CalendarDay.today() ? 'Für heute.' : 'Für den ${GermanFormat.date(day)}.',
                'Die Trainings-Kohlenhydrate zählen dann in der Tagesbilanz.',
                if (widget.relog) 'Bisherige Einträge dieses Plans werden ersetzt.',
              ].join(' '),
              style: LiquidText.label(context),
            ),
            const SizedBox(height: 8),
            for (final phase in FuelPhase.values)
              if (FuelDiary.entry(widget.plan, phase) case final entry?)
                CheckboxListTile(
                  value: _phases.contains(phase),
                  onChanged: (value) => setState(() => value == true ? _phases.add(phase) : _phases.remove(phase)),
                  title: Text(entry.title),
                  subtitle: Text(_subtitle(entry)),
                  isThreeLine: true,
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

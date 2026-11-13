import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../evidence/evidence_views.dart';

/// Wochenplan bearbeiten: je Tag Einheiten hinzufügen, Intensität ändern oder entfernen.
class ScheduleEditor extends StatelessWidget {
  const ScheduleEditor({
    super.key,
    required this.schedule,
    required this.sports,
    required this.onChanged,
    this.highlight,
  });

  final WeekSchedule schedule;
  final List<TrainingSport> sports;
  final ValueChanged<WeekSchedule> onChanged;
  final Weekday? highlight;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final weekday in Weekday.values)
        _DayEditorRow(
          weekday: weekday,
          isHighlighted: weekday == highlight,
          sports: sports,
          slots: schedule.slots(weekday),
          onChanged: (slots) => onChanged(schedule.withSlots(slots, weekday)),
        ),
    ],
  );
}

class _DayEditorRow extends StatelessWidget {
  const _DayEditorRow({
    required this.weekday,
    required this.isHighlighted,
    required this.sports,
    required this.slots,
    required this.onChanged,
  });

  final Weekday weekday;
  final bool isHighlighted;
  final List<TrainingSport> sports;
  final List<SessionSlot> slots;
  final ValueChanged<List<SessionSlot>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                weekday.long,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: isHighlighted ? FontWeight.bold : null),
              ),
              if (isHighlighted) ...[
                const SizedBox(width: 8),
                AppChip(text: 'Heute', color: theme.colorScheme.primary),
              ],
              const Spacer(),
              PopupMenuButton<TrainingSport>(
                tooltip: 'Einheit am ${weekday.long} hinzufügen',
                icon: Icon(Icons.add_circle, color: theme.colorScheme.primary),
                onSelected: (sport) => onChanged([
                  ...slots,
                  SessionSlot(sport, sport == TrainingSport.strength ? SessionIntensity.hard : SessionIntensity.easy),
                ]),
                itemBuilder: (_) => [
                  for (final sport in sports)
                    PopupMenuItem(
                      value: sport,
                      child: ListTile(leading: Icon(AppSymbols.of(sport.symbol)), title: Text(sport.label)),
                    ),
                ],
              ),
            ],
          ),
          if (slots.isEmpty)
            Text('Frei', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, slot) in slots.indexed)
                  _SlotChip(
                    slot: slot,
                    onChanged: (updated) {
                      final next = [...slots];
                      if (updated == null) {
                        next.removeAt(index);
                      } else {
                        next[index] = updated;
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.onChanged});

  final SessionSlot slot;

  /// `null` = entfernen.
  final ValueChanged<SessionSlot?> onChanged;

  List<SessionIntensity> get _intensities => switch (slot.sport) {
    TrainingSport.strength => const [SessionIntensity.easy, SessionIntensity.hard],
    TrainingSport.other => const [],
    _ => SessionIntensity.values,
  };

  @override
  Widget build(BuildContext context) {
    final color = slot.sport.color;
    return PopupMenuButton<SessionIntensity?>(
      tooltip: slot.chipLabel,
      onSelected: (intensity) => onChanged(intensity == null ? null : SessionSlot(slot.sport, intensity)),
      itemBuilder: (_) => [
        for (final intensity in _intensities)
          CheckedPopupMenuItem(value: intensity, checked: intensity == slot.intensity, child: Text(intensity.label)),
        const PopupMenuItem(
          value: null,
          child: Text('Entfernen', style: TextStyle(color: Colors.red)),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppSymbols.of(slot.sport.symbol), size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              slot.chipLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hinweise zum Wochenplan mit Quellen (Praxisregeln sind gekennzeichnet).
class ScheduleHintsSection extends StatelessWidget {
  const ScheduleHintsSection({super.key, required this.hints});

  final List<ScheduleHint> hints;

  @override
  Widget build(BuildContext context) {
    if (hints.isEmpty) return const SizedBox.shrink();
    final ids = [for (final hint in hints) ...hint.evidenceIDs];
    return FormSection(
      header: 'Dein Plan im Check',
      children: [
        for (final hint in hints)
          ListTile(
            leading: Icon(
              switch (hint.severity) {
                HintSeverity.warning => Icons.warning_amber_rounded,
                HintSeverity.tip => Icons.lightbulb,
                HintSeverity.info => Icons.info,
              },
              color: switch (hint.severity) {
                HintSeverity.warning => Colors.orange,
                HintSeverity.tip => Colors.blue,
                HintSeverity.info => Theme.of(context).colorScheme.onSurfaceVariant,
              },
            ),
            title: Text(hint.message),
            subtitle: hint.isPracticeRule && hint.severity != HintSeverity.info ? const Text('Praxisregel') : null,
          ),
        if (ids.isNotEmpty) EvidenceDisclosure(ruleIDs: ids),
      ],
    );
  }
}

/// Hinweise zu den Eingaben: unplausible Werte, widersprüchliche Ziele und Zielzeiten im Vergleich zur Prognose.
class InputIssuesSection extends StatelessWidget {
  const InputIssuesSection({super.key, required this.issues, this.title = 'Deine Angaben im Check'});

  final List<InputIssue> issues;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final ids = [for (final issue in issues) ...issue.evidenceIDs];
    return FormSection(
      header: title,
      children: [
        for (final issue in issues)
          ListTile(
            leading: Icon(
              switch (issue.severity) {
                InputSeverity.warning => Icons.warning_amber_rounded,
                InputSeverity.tip => Icons.lightbulb,
                InputSeverity.info => Icons.check_circle,
              },
              color: switch (issue.severity) {
                InputSeverity.warning => Colors.orange,
                InputSeverity.tip => Colors.amber,
                InputSeverity.info => Colors.green,
              },
            ),
            title: Text(issue.message),
          ),
        if (ids.isNotEmpty) EvidenceDisclosure(ruleIDs: ids),
      ],
    );
  }
}

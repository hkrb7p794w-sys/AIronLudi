import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../../ui/tokens.dart';

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

/// Auswahl im Menü einer Einheit.
sealed class _SlotAction {
  const _SlotAction();
}

final class _SetIntensity extends _SlotAction {
  const _SetIntensity(this.intensity);

  final SessionIntensity intensity;
}

final class _SetActivity extends _SlotAction {
  const _SetActivity(this.activity);

  /// `null` = allgemein „Anderes“.
  final ActivityKind? activity;
}

final class _RemoveSlot extends _SlotAction {
  const _RemoveSlot();
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
    // Kein `null` als Menüwert: Flutter wertet `null` als Abbruch und ruft `onSelected` dann nicht auf.
    return PopupMenuButton<_SlotAction>(
      tooltip: slot.chipLabel,
      onSelected: (action) => onChanged(switch (action) {
        _SetIntensity(:final intensity) => SessionSlot(slot.sport, intensity, slot.activity),
        _SetActivity(:final activity) => slot.withActivity(activity),
        _RemoveSlot() => null,
      }),
      itemBuilder: (_) => [
        for (final intensity in _intensities)
          CheckedPopupMenuItem<_SlotAction>(
            value: _SetIntensity(intensity),
            checked: intensity == slot.intensity,
            child: Text(intensity.label),
          ),
        // „Anderes“: welche Sportart genau (Bouldern, Yoga …) – dann zählt nur die passende Aktivität als erledigt.
        if (slot.sport == TrainingSport.other) ...[
          CheckedPopupMenuItem<_SlotAction>(
            value: const _SetActivity(null),
            checked: slot.activity == null,
            child: const Text('Beliebig (Yoga, Wandern …)'),
          ),
          for (final kind in SessionSlot.otherActivities)
            CheckedPopupMenuItem<_SlotAction>(
              value: _SetActivity(kind),
              checked: slot.activity == kind,
              child: Text(kind.label),
            ),
        ],
        PopupMenuItem<_SlotAction>(
          value: _RemoveSlot(),
          child: Text('Entfernen', style: TextStyle(color: AppColors.of(context).alert)),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppSymbols.of(slot.symbol), size: 16, color: color),
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
                HintSeverity.warning => AppColors.of(context).caution,
                HintSeverity.tip => AppColors.of(context).info,
                HintSeverity.info => Theme.of(context).colorScheme.onSurfaceVariant,
              },
            ),
            title: Text(hint.message),
            subtitle: hint.isPracticeRule && hint.severity != HintSeverity.info ? const Text('Praxisregel') : null,
          ),
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
                InputSeverity.warning => AppColors.of(context).caution,
                InputSeverity.tip => AppPalette.amber,
                InputSeverity.info => AppColors.of(context).good,
              },
            ),
            title: Text(issue.message),
          ),
      ],
    );
  }
}

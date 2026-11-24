import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/body_map.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../evidence/evidence_views.dart';

export '../../ui/body_map.dart' show BodyMap, BodySide;

/// Heatmap mit Liste: welche Muskeln wie viele effektive Sätze bekommen haben.
class MuscleHeatmapSection extends StatelessWidget {
  const MuscleHeatmapSection({super.key, required this.title, required this.values, this.full = 6, this.footer});

  final String title;
  final Map<Muscle, double> values;

  /// Ab so vielen Sätzen volle Farbe.
  final double full;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final shown = values.entries.where((entry) => entry.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return FormSection(
      header: title,
      footer:
          footer ??
          'Effektive Arbeitssätze: Hauptmuskel 1, mitarbeitende Muskeln 0,5; Sätze mit RIR 4+ und Drop-Sätze halb, '
              'Aufwärmen nicht. Eine Schätzung, keine Messung.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: BodyMap(values: values, full: full),
        ),
        for (final entry in shown)
          LabeledRow(label: entry.key.label, value: '${GermanFormat.decimal(entry.value)} Sätze'),
        const EvidenceDisclosure(ruleIDs: ['gym.muscle-load', 'gym.volume']),
      ],
    );
  }
}

enum _OverviewMode {
  week('7 Tage'),
  month('Ø 4 Wochen'),
  recovery('Erholung');

  const _OverviewMode(this.label);

  final String label;
}

/// Langzeitübersicht: Wochensätze je Muskel, Mittel über 4 Wochen, wenig Trainiertes und Regeneration.
class MuscleOverviewSection extends ConsumerStatefulWidget {
  const MuscleOverviewSection({super.key, required this.sessions, this.now});

  final List<GymSession> sessions;
  final DateTime? now;

  @override
  ConsumerState<MuscleOverviewSection> createState() => _MuscleOverviewSectionState();
}

class _MuscleOverviewSectionState extends ConsumerState<MuscleOverviewSection> {
  _OverviewMode _mode = _OverviewMode.week;

  double _value(MuscleStatus status) => _mode == _OverviewMode.month ? status.averageWeeklySets : status.weeklySets;

  static Color recoveryColor(MuscleRecovery recovery, BuildContext context) => switch (recovery) {
    MuscleRecovery.recovering => AppColors.of(context).caution,
    MuscleRecovery.ready => AppColors.of(context).good,
    MuscleRecovery.neglected => Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
  };

  /// „zuletzt vor 3 Tagen“ (wie `.relative(presentation: .named)`).
  static String relative(DateTime date, DateTime now) {
    final days = CalendarDay.fromDate(date.toLocal()).daysUntil(CalendarDay.fromDate(now.toLocal()));
    return switch (days) {
      <= 0 => 'heute',
      1 => 'gestern',
      2 => 'vorgestern',
      < 14 => 'vor $days Tagen',
      < 60 => 'vor ${days ~/ 7} Wochen',
      _ => 'vor ${days ~/ 30} Monaten',
    };
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final custom = ref.watch(coachSettingsProvider).gym.customExercises;
    final statuses = MuscleLoad.status(sessions: widget.sessions, now: now, custom: custom);
    (int, double) order(MuscleStatus status) => (
      switch (status.recovery) {
        MuscleRecovery.recovering => 0,
        MuscleRecovery.neglected => 1,
        MuscleRecovery.ready => 2,
      },
      -_value(status),
    );
    final sorted = [...statuses]
      ..sort((a, b) {
        final (left, right) = (order(a), order(b));
        return left.$1 != right.$1 ? left.$1.compareTo(right.$1) : left.$2.compareTo(right.$2);
      });
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Muskeln',
      footer:
          'Effektive Sätze je Muskel (Hauptmuskel 1, mitarbeitend 0,5). Volle Farbe ab ${MuscleLoad.weeklyFull.toInt()} '
          'Sätzen pro Woche, orange unter ${MuscleLoad.weeklyEnough.toInt()}. „Vermutlich noch in der Erholung“ heißt: in '
          'den letzten ${MuscleLoad.recoveryHours.toInt()} Stunden nennenswert belastet – eine Schätzung, keine Messung '
          'von Ermüdung.',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_OverviewMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in _OverviewMode.values)
                ButtonSegment(
                  value: mode,
                  label: FittedBox(child: Text(mode.label)),
                ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => setState(() => _mode = selection.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: BodyMap(
            values: {for (final status in statuses) status.muscle: _value(status)},
            full: MuscleLoad.weeklyFull,
            colors: _mode == _OverviewMode.recovery
                ? {for (final status in statuses) status.muscle: recoveryColor(status.recovery, context)}
                : const {},
          ),
        ),
        for (final status in sorted)
          ListTile(
            dense: true,
            leading: ExcludeSemantics(
              child: CircleAvatar(radius: 4, backgroundColor: recoveryColor(status.recovery, context)),
            ),
            minLeadingWidth: 8,
            title: Text(status.muscle.label),
            subtitle: Text(
              '${status.recovery.label} · '
              '${status.lastLoaded == null ? 'noch nie' : 'zuletzt ${relative(status.lastLoaded!, now)}'}',
            ),
            trailing: Text(
              '${GermanFormat.decimal(_value(status))} Sätze',
              style: TextStyle(
                color: status.isLow && _mode != _OverviewMode.recovery ? AppColors.of(context).caution : secondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        const EvidenceDisclosure(ruleIDs: ['gym.muscle-load', 'gym.volume']),
      ],
    );
  }
}

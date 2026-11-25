import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/body_map.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';

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

/// Langzeitübersicht: Wochensätze je Muskel, Mittel über 4 Wochen, wenig Trainiertes und Regeneration – umschaltbar
/// auf Ausdauerminuten (Kardio) und Minuten Dehnen/Mobility je Muskel.
class MuscleOverviewSection extends ConsumerStatefulWidget {
  const MuscleOverviewSection({super.key, required this.sessions, this.now, this.activities});

  final List<GymSession> sessions;
  final DateTime? now;

  /// Ausdauereinheiten; null = aus dem Speicher laden.
  final List<GarminActivity>? activities;

  @override
  ConsumerState<MuscleOverviewSection> createState() => _MuscleOverviewSectionState();
}

class _MuscleOverviewSectionState extends ConsumerState<MuscleOverviewSection> {
  _OverviewMode _mode = _OverviewMode.week;
  BodyLoadKind _kind = BodyLoadKind.strength;
  List<GarminActivity> _loaded = const [];

  @override
  void initState() {
    super.initState();
    if (widget.activities == null) unawaited(_load());
  }

  Future<void> _load() async {
    final activities = await ref.read(activityRepositoryProvider).all();
    if (mounted) setState(() => _loaded = activities);
  }

  List<GarminActivity> get _activities => widget.activities ?? _loaded;

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

  /// Zeitraum der Minuten: 7 Tage bis heute oder 28 Tage (dann geteilt durch 4).
  (CalendarDay, CalendarDay, double) _range(DateTime now) {
    final today = CalendarDay.fromDate(now);
    return _mode == _OverviewMode.month ? (today.adding(-27), today, 4.0) : (today.adding(-6), today, 1.0);
  }

  Map<Muscle, double> _divided(Map<Muscle, double> values, double weeks) => {
    for (final entry in values.entries) entry.key: entry.value / weeks,
  };

  void _select(BodyLoadKind kind) => setState(() {
    _kind = kind;
    // Erholung gibt es nur für das Krafttraining.
    if (kind != BodyLoadKind.strength && _mode == _OverviewMode.recovery) _mode = _OverviewMode.week;
  });

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final custom = ref.watch(coachSettingsProvider).gym.customExercises;
    final mobilityLog = ref.watch(coachSettingsProvider).mobility.log;
    final statuses = MuscleLoad.status(sessions: widget.sessions, now: now, custom: custom);
    final (from, to, weeks) = _range(now);
    final period = _mode == _OverviewMode.month ? 'pro Woche (Ø 4 Wochen)' : 'in den letzten 7 Tagen';

    final (values, full, rows, footer) = switch (_kind) {
      BodyLoadKind.strength => (
        {for (final status in statuses) status.muscle: _value(status)},
        MuscleLoad.weeklyFull,
        _strengthRows(context, statuses, now),
        'Effektive Sätze je Muskel (Hauptmuskel 1, mitarbeitend 0,5). Volle Farbe ab ${MuscleLoad.weeklyFull.toInt()} '
            'Sätzen pro Woche, orange unter ${MuscleLoad.weeklyEnough.toInt()}. „Vermutlich noch in der Erholung“ heißt: '
            'in den letzten ${MuscleLoad.recoveryHours.toInt()} Stunden nennenswert belastet – eine Schätzung, keine '
            'Messung von Ermüdung.',
      ),
      BodyLoadKind.cardio => (
        _divided(CardioLoad.minutes(_activities, from: from, to: to), weeks),
        CardioLoad.weeklyFull,
        [
          for (final (sport, minutes) in CardioLoad.bySport(_activities, from: from, to: to))
            LabeledRow(label: MobilityPlanner.sportLabel(sport), value: '${(minutes / weeks).round()} min'),
        ],
        'Minuten Laufen, Radfahren und Schwimmen je Muskel: Hauptmuskeln voll, mitarbeitende halb (Laufen: Beine und '
            'Gesäß; Rad: vor allem Oberschenkel vorn und Gesäß; Schwimmen: Latissimus und Schultern). Volle Farbe ab '
            '${CardioLoad.weeklyFull.toInt()} Minuten pro Woche. Eine Zuordnung zur Orientierung, keine Messung.',
      ),
      BodyLoadKind.stretch => (
        _divided(StretchLoad.minutes(mobilityLog, from: from, to: to), weeks),
        StretchLoad.weeklyFull,
        [
          for (final entry in StretchLoad.areaMinutes(
            mobilityLog,
            from: from,
            to: to,
          ).entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            LabeledRow(label: entry.key.label, value: '${GermanFormat.decimal(entry.value / weeks)} min'),
        ],
        'Minuten aus abgeschlossenen Mobility-Einheiten, verteilt auf ihre Schwerpunkte. Volle Farbe ab '
            '${StretchLoad.weeklyFull.toInt()} Minuten pro Woche und Muskel.',
      ),
    };
    final empty = switch (_kind) {
      BodyLoadKind.strength => null,
      BodyLoadKind.cardio => 'Keine Lauf-, Rad- oder Schwimmeinheiten $period.',
      BodyLoadKind.stretch => 'Keine Mobility-Einheiten $period. Starten kannst du sie unter Gesundheit › Mobility.',
    };
    final modes = [
      for (final mode in _OverviewMode.values)
        if (_kind == BodyLoadKind.strength || mode != _OverviewMode.recovery) mode,
    ];
    return FormSection(
      header: 'Muskeln',
      footer: footer,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_OverviewMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in modes)
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            children: [
              BodyMap(
                values: values,
                full: full,
                unit: _kind.unit,
                colors: _kind == BodyLoadKind.strength && _mode == _OverviewMode.recovery
                    ? {for (final status in statuses) status.muscle: recoveryColor(status.recovery, context)}
                    : const {},
              ),
              const SizedBox(height: 8),
              SegmentedButton<BodyLoadKind>(
                showSelectedIcon: false,
                segments: [
                  for (final kind in BodyLoadKind.values)
                    ButtonSegment(
                      value: kind,
                      label: FittedBox(child: Text(kind.label)),
                    ),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) => _select(selection.first),
              ),
            ],
          ),
        ),
        if (rows.isEmpty && empty != null)
          ListTile(
            title: Text(empty, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ...rows,
      ],
    );
  }

  List<Widget> _strengthRows(BuildContext context, List<MuscleStatus> statuses, DateTime now) {
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
    return [
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
    ];
  }
}

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';

/// Ein Muskel mit seinen Flächen auf der Zeichenfläche 100 × 200.
final class _Region {
  const _Region(this.muscle, this.frames);

  final Muscle muscle;
  final List<Rect> frames;
}

/// Links und rechts gespiegelt.
_Region _pair(Muscle muscle, double x, double y, double width, double height) =>
    _Region(muscle, [Rect.fromLTWH(x, y, width, height), Rect.fromLTWH(100 - x - width, y, width, height)]);

/// Schematische Körperkarte (vorn und hinten) mit Farbe je Muskel: grau = nicht beansprucht, gelb bis rot = mehr.
/// Eine Übersicht, keine anatomisch genaue Darstellung (Port von `BodyMapView`).
class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.values, required this.full, this.colors = const {}});

  /// Wert je Muskel; ab [full] volle Farbe.
  final Map<Muscle, double> values;
  final double full;

  /// Eigene Farbe je Muskel (z. B. Regeneration); überschreibt die Heatmap-Farbe.
  final Map<Muscle, Color> colors;

  static const silhouette = [
    Rect.fromLTWH(30, 28, 40, 66),
    Rect.fromLTWH(14, 32, 14, 72),
    Rect.fromLTWH(72, 32, 14, 72),
    Rect.fromLTWH(31, 90, 18, 104),
    Rect.fromLTWH(51, 90, 18, 104),
  ];

  static final front = [
    _pair(Muscle.frontDelts, 26, 32, 10, 10),
    _pair(Muscle.sideDelts, 15, 34, 9, 12),
    _pair(Muscle.chest, 36, 34, 13, 16),
    _pair(Muscle.biceps, 16, 48, 10, 22),
    _pair(Muscle.forearms, 15, 73, 10, 28),
    const _Region(Muscle.abs, [Rect.fromLTWH(42, 53, 16, 34)]),
    _pair(Muscle.obliques, 33, 55, 8, 28),
    _pair(Muscle.quads, 32, 96, 13, 46),
    _pair(Muscle.adductors, 45.5, 98, 4, 30),
    _pair(Muscle.calves, 34, 150, 10, 30),
  ];

  static final back = [
    const _Region(Muscle.traps, [Rect.fromLTWH(38, 29, 24, 15)]),
    _pair(Muscle.rearDelts, 23, 33, 11, 10),
    _pair(Muscle.sideDelts, 15, 34, 8, 12),
    _pair(Muscle.lats, 32, 45, 15, 30),
    const _Region(Muscle.lowerBack, [Rect.fromLTWH(41, 76, 18, 14)]),
    _pair(Muscle.triceps, 16, 48, 10, 22),
    _pair(Muscle.forearms, 15, 73, 10, 28),
    _pair(Muscle.glutes, 32, 91, 17, 17),
    _pair(Muscle.hamstrings, 32, 110, 15, 34),
    _pair(Muscle.calves, 33, 148, 13, 32),
  ];

  /// Gelb → Orange → Rot je nach Anteil an [full]; ohne Last grau.
  static Color heat(double value, {required double full, required Color empty}) {
    final level = MuscleLoad.intensity(value, full: full);
    if (level <= 0) return empty;
    return HSVColor.fromAHSV(0.45 + 0.55 * level, 360 * (0.15 - 0.15 * level), 0.85, 0.95).toColor();
  }

  String get _semantics {
    final shown = values.entries.where((entry) => entry.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (shown.isEmpty) return 'Keine Muskeln beansprucht';
    return 'Muskelkarte: ${[for (final entry in shown) '${entry.key.label} ${GermanFormat.decimal(entry.value)} Sätze'].join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget figure(List<_Region> regions, String title) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 220,
          child: AspectRatio(
            aspectRatio: 0.5,
            child: CustomPaint(
              painter: _BodyPainter(
                regions: regions,
                base: secondary.withValues(alpha: 0.12),
                color: (muscle) =>
                    colors[muscle] ?? heat(values[muscle] ?? 0, full: full, empty: secondary.withValues(alpha: 0.22)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 11, color: secondary)),
      ],
    );
    return Semantics(
      label: _semantics,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [figure(front, 'Vorn'), const SizedBox(width: 16), figure(back, 'Hinten')],
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.regions, required this.base, required this.color});

  final List<_Region> regions;
  final Color base;
  final Color Function(Muscle muscle) color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100 < size.height / 200 ? size.width / 100 : size.height / 200;
    final offsetX = (size.width - 100 * scale) / 2;
    Rect place(Rect rect) =>
        Rect.fromLTWH(offsetX + rect.left * scale, rect.top * scale, rect.width * scale, rect.height * scale);
    final paint = Paint()..color = base;
    // Umriss: Kopf, Rumpf, Arme, Beine.
    canvas.drawOval(place(const Rect.fromLTWH(40, 2, 20, 22)), paint);
    for (final part in BodyMap.silhouette) {
      canvas.drawRRect(RRect.fromRectAndRadius(place(part), Radius.circular(6 * scale)), paint);
    }
    for (final region in regions) {
      final fill = Paint()..color = color(region.muscle);
      for (final frame in region.frames) {
        canvas.drawRRect(RRect.fromRectAndRadius(place(frame), Radius.circular(3 * scale)), fill);
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => true;
}

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
    MuscleRecovery.recovering => Colors.orange,
    MuscleRecovery.ready => Colors.green,
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
                color: status.isLow && _mode != _OverviewMode.recovery ? Colors.orange : secondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        const EvidenceDisclosure(ruleIDs: ['gym.muscle-load', 'gym.volume']),
      ],
    );
  }
}

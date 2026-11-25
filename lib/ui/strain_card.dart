import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'components.dart';
import 'liquid.dart';

Color strainColor(StrainLevel level) => switch (level) {
  StrainLevel.rest => Colors.grey,
  StrainLevel.light => Colors.teal,
  StrainLevel.moderate => Colors.blue,
  StrainLevel.high => Colors.orange,
  StrainLevel.veryHigh => Colors.red,
};

(String, Color) recoveryChip(RecoveryLevel? level) => switch (level) {
  RecoveryLevel.normal => ('Erholt', Colors.green),
  RecoveryLevel.locker => ('Eingeschränkt', Colors.orange),
  RecoveryLevel.pause => ('Erholung nötig', Colors.red),
  null => ('Erholung unbekannt', Colors.grey),
};

/// „Meine Belastung heute“: Balken aus Erledigtem und Geplantem gegen den üblichen Tag, Erholungsampel, die letzten
/// sieben Tage. Antippen zeigt die Zahlen dahinter.
class DailyStrainCard extends StatelessWidget {
  const DailyStrainCard({super.key, required this.strain});

  final DailyStrain strain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = strainColor(strain.level);
    final (recoveryText, recoveryColor) = recoveryChip(strain.recovery);
    return FormSection(
      header: 'Meine Belastung heute',
      children: [
        InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => DailyStrainDetails(strain: strain),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strain.headline,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                    AppChip(text: recoveryText, color: recoveryColor),
                  ],
                ),
                StrainBar(strain: strain),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        strain.advice,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(width: 84, height: 34, child: StrainWeekBars(strain: strain)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Erledigt (voll), geplant (hell) und Strich beim üblichen Tag.
class StrainBar extends StatelessWidget {
  const StrainBar({super.key, required this.strain});

  final DailyStrain strain;

  @override
  Widget build(BuildContext context) {
    final color = strainColor(strain.level);
    final scale = math.max(strain.total, strain.typical * 1.6);
    final track = LiquidTheme.of(context).track;
    return Semantics(
      label:
          'Erledigt ${strain.done.round()} Punkte, geplant ${strain.planned.round()}, üblicher Tag '
          '${strain.typical.round()}',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double part(double value) => scale <= 0 ? 0 : value / scale * width;
          final glow = [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: -2)];
          // Füllung läuft mit einer Feder auf ihren Wert (Erscheinen und jede Änderung).
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: LiquidMotion.of(context, LiquidMotion.slow),
            curve: LiquidMotion.settle,
            builder: (context, progress, _) => SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(7)),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: part(strain.total) * progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: part(strain.done) * progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LiquidGradients.linear(color),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: strain.done > 0 ? glow : null,
                      ),
                    ),
                  ),
                  Positioned(
                    left: math.min(part(strain.typical), width - 2),
                    top: -2,
                    bottom: -2,
                    width: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Belastung der letzten sieben Tage, heute farbig.
class StrainWeekBars extends StatelessWidget {
  const StrainWeekBars({super.key, required this.strain});

  final DailyStrain strain;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
    final maxY = math.max(strain.week.fold<double>(0, math.max), strain.typical) * 1.1;
    return ExcludeSemantics(
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY,
          barTouchData: const BarTouchData(enabled: false),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (final (index, value) in strain.week.indexed)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: value,
                    width: 7,
                    color: index == strain.week.length - 1 ? strainColor(strain.level) : muted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Zahlen hinter der Karte.
class DailyStrainDetails extends StatelessWidget {
  const DailyStrainDetails({super.key, required this.strain});

  final DailyStrain strain;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (strain.measured case final measured?)
            FormSection(
              header: 'Belastung (Skala wie WHOOP-Strain)',
              footer: switch (strain.source) {
                StrainSource.whoop => 'Wert von WHOOP (Tageszyklus).',
                _ =>
                  'Aus deinem Puls über den ganzen Tag: Jede Minute zählt nach ihrem Anteil an der '
                      'Herzfrequenzreserve (Zonen 50–60 … 90–100 %, Gewicht 1–5; Alltagsbewegung ab 30 % leicht). '
                      'Skala 0–21 wie bei WHOOP – nach oben immer schwerer zu steigern. Näherung, die genaue '
                      'WHOOP-Formel ist nicht öffentlich.',
              },
              children: [
                LabeledRow(label: 'Belastung', value: '${GermanFormat.decimal(measured)} von 21'),
                LabeledRow(label: 'Quelle', value: strain.source.label),
                if (strain.heartRate case final result?) ...[
                  LabeledRow(
                    label: 'Ruhepuls · HFmax',
                    value: '${result.restingHeartRate.round()} · ${result.maxHeartRate.round()} bpm',
                  ),
                  for (final (zone, minutes) in result.zoneMinutes.indexed.skip(1))
                    if (minutes > 0)
                      LabeledRow(
                        label: 'Zone $zone (${40 + zone * 10}–${50 + zone * 10} %)',
                        value: '${minutes.round()} min',
                      ),
                ],
              ],
            ),
          FormSection(
            header: strain.measured == null ? 'Heute' : 'Trainings heute (Belastungspunkte)',
            children: [
              LabeledRow(label: 'Erledigt', value: '${strain.done.round()} Punkte'),
              LabeledRow(label: 'Noch geplant', value: '${strain.planned.round()} Punkte'),
              LabeledRow(label: 'Üblicher Tag', value: '${strain.typical.round()} Punkte'),
              LabeledRow(label: 'Erholung', value: recoveryChip(strain.recovery).$1),
            ],
          ),
          FormSection(
            header: 'Letzte Wochen',
            footer:
                'Punkte wie Training Stress Score: 100 = eine Stunde an der Schwelle. Aus Leistung, Tempo bzw. Puls '
                'deiner Aufzeichnungen, sonst geschätzt aus Dauer und Sportart; geplante Einheiten nach Sportart und '
                'Intensität. Üblicher Tag = Fitness (Schnitt der letzten 6 Wochen), Ermüdung = letzte Woche.',
            children: [
              LabeledRow(label: 'Fitness', value: strain.typical.round().toString()),
              LabeledRow(label: 'Ermüdung', value: strain.fatigue.round().toString()),
              LabeledRow(label: 'Form', value: strain.form.round().toString()),
            ],
          ),
        ],
      ),
    ),
  );
}

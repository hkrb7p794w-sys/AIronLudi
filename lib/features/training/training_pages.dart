import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ui/chart_axes.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/tokens.dart';
import '../../ui/zoomable_chart.dart';
import '../evidence/evidence_views.dart';
import 'training_controller.dart';

part 'training_trend_pages.dart';

/// „62 ms“, „7,5 h“ oder „–“ (wie `Formatters.number`).
String formatNumber(double? value, {String unit = '', int digits = 0}) {
  if (value == null) return '–';
  final text = NumberFormat.decimalPatternDigits(locale: 'de_DE', decimalDigits: digits).format(value);
  return unit.isEmpty ? text : '$text $unit';
}

String formatDuration(double seconds) {
  final minutes = (seconds / 60).round();
  return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
}

double _x(CalendarDay day) => day.referenceDate.millisecondsSinceEpoch / Duration.millisecondsPerDay;

String _dayLabel(double value) => DateFormat(
  'd.M.',
  'de_DE',
).format(DateTime.fromMillisecondsSinceEpoch((value * Duration.millisecondsPerDay).round()));

FlTitlesData _titles({double? interval}) => FlTitlesData(
  topTitles: const AxisTitles(),
  rightTitles: const AxisTitles(),
  leftTitles: valueAxis(reservedSize: 40),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: interval,
      getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, child: AxisLabel(_dayLabel(value))),
    ),
  ),
);

// Erholung

/// Erholungsverläufe, Werte von heute und Schlafphasen (Port von `RecoverySections`).
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key, required this.controller});

  final TrainingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Erholung')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (controller.recovery.isEmpty && controller.tiles.isEmpty)
            FormSection(
              children: [
                ListTile(
                  title: Text(
                    'Noch keine Werte deiner Datenquellen. Ziehe nach unten, um abzurufen.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          for (final card in controller.recovery) FormSection(children: [TrendCardView(card: card)]),
          if (controller.tiles.isNotEmpty)
            FormSection(
              header: 'Werte von heute',
              footer:
                  'Trainingsbereitschaft, Trainingsstatus und Endurance Score liefern nur Uhren mit diesen Werten '
                  '(Garmin-Konto in den Einstellungen).',
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = math.max(1, (constraints.maxWidth / 108).floor());
                      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tile in controller.tiles)
                            Container(
                              width: width,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 2,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      tile.value,
                                      style: AppText.headline(context).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    tile.title,
                                    style: AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          if (controller.sleepStages case final night?)
            FormSection(
              header: 'Schlafphasen (${DateFormat('EEE, d. MMM', 'de_DE').format(night.day.referenceDate)})',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SleepStages(metrics: night),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Verlauf einer Kennzahl über 28 Tage mit Schnitt und Veränderung zum Vormonat.
class TrendCardView extends StatelessWidget {
  const TrendCardView({super.key, required this.card});

  final TrendCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = card.trend;
    final change = trend.change;
    final higher = card.higherIsBetter;
    final changeColor = change == null || higher == null || change.abs() < 0.05
        ? theme.colorScheme.onSurfaceVariant
        : ((change > 0) == higher ? AppColors.of(context).good : AppColors.of(context).caution);
    final values = [for (final point in trend.points) point.value];
    final low = values.isEmpty ? 0.0 : values.reduce(math.min);
    final high = values.isEmpty ? 1.0 : values.reduce(math.max);
    final padding = math.max((high - low) * 0.15, 1.0);
    final secondary = AppText.caption(context).copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(card.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text(
                formatNumber(trend.latest?.value, unit: card.unit, digits: card.digits),
                style: AppText.headline(context).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Semantics(
            label: 'Verlauf ${card.title}',
            child: SizedBox(
              height: 110,
              child: LineChart(
                LineChartData(
                  minY: low - padding,
                  maxY: high + padding,
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (final point in trend.points) FlSpot(_x(point.day), point.value)],
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: theme.colorScheme.primary,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (trend.average case final average?)
                        HorizontalLine(
                          y: average,
                          color: theme.colorScheme.onSurfaceVariant,
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                        ),
                    ],
                  ),
                  titlesData: _titles(interval: 7),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ø 28 Tage ${formatNumber(trend.average, unit: card.unit, digits: card.digits)}',
                  style: secondary,
                ),
              ),
              if (change != null)
                Text(
                  '${change >= 0 ? '+' : ''}${formatNumber(change, unit: card.unit, digits: card.digits)} zum Vormonat',
                  style: secondary.copyWith(color: changeColor),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Schlafphasen als Balken mit Dauer je Phase.
class SleepStages extends StatelessWidget {
  const SleepStages({super.key, required this.metrics});

  final DailyMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('Tief', metrics.deepSleepSeconds ?? 0, AppPalette.indigo),
      ('Leicht', metrics.lightSleepSeconds ?? 0, AppColors.of(context).info),
      ('REM', metrics.remSleepSeconds ?? 0, AppPalette.cyan),
      ('Wach', metrics.awakeSleepSeconds ?? 0, AppColors.of(context).caution),
    ];
    final total = math.max(stages.fold<double>(0, (sum, stage) => sum + stage.$2), 1.0);
    return Column(
      spacing: 8,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              spacing: 2,
              children: [
                for (final (_, seconds, color) in stages)
                  if (seconds > 0)
                    Expanded(
                      flex: math.max(1, (seconds / total * 1000).round()),
                      child: ColoredBox(color: color),
                    ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            for (final (name, seconds, color) in stages)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.caption(context).copyWith(color: color)),
                    Text(formatDuration(seconds), style: AppText.caption(context)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// Herzfrequenz

const _zoneColors = [AppPalette.grey, AppPalette.blue, AppPalette.green, AppPalette.orange, AppPalette.red];

/// Pulszonen: HFmax, Coach-Zonen je Sportart, Intensität, Uhr-Zonen und Hinweise (Port von `HeartRateSections`).
class HeartRateScreen extends StatelessWidget {
  const HeartRateScreen({super.key, required this.report});

  final HeartRateZoneReport? report;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    final secondary = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Herzfrequenz')),
      body: report == null
          ? const Center(child: Text('Noch keine Werte.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                FormSection(
                  header: 'Herzfrequenz-Zonen',
                  footer:
                      'Coach-Zonen nach Friel in % der Schwellen-HF – sie hängen an der Schwelle, nicht an der HFmax.',
                  children: [
                    LabeledRow(label: 'HFmax', value: report.maxHeartRate == null ? '–' : '${report.maxHeartRate} bpm'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(report.maxHeartRateSource, style: secondary),
                    ),
                  ],
                ),
                _CoachZoneSection(title: 'Laufen', zones: report.run),
                _CoachZoneSection(title: 'Rad', zones: report.bike),
                _IntensitySection(distribution: report.distribution),
                for (final watch in report.watch)
                  FormSection(
                    header:
                        'Uhr-Zonen ${watch.sport[0].toUpperCase()}${watch.sport.substring(1).toLowerCase()} (${watch.methodText})',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _ZoneBand(zones: watch.zones),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Danach zählt die Uhr „Zeit in Zone“. Ändern: Garmin Connect › Benutzereinstellungen › '
                          'Herzfrequenzzonen.',
                          style: secondary,
                        ),
                      ),
                    ],
                  ),
                FormSection(
                  header: 'Hinweise',
                  children: [
                    for (final hint in report.hints) ListTile(dense: true, title: Text(hint)),
                    const EvidenceDisclosure(
                      ruleIDs: ['hr.threshold-zones', 'hr.max-formula', 'intensity.distribution', 'hr.optical'],
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _CoachZoneSection extends StatelessWidget {
  const _CoachZoneSection({required this.title, required this.zones});

  final String title;
  final CoachZones zones;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Coach-Zonen $title',
      children: [
        if (zones.zones.isEmpty)
          ListTile(
            title: Text(
              'Noch keine Schwelle bekannt – HFmax oder Schwelle unter Einstellungen eintragen.',
              style: TextStyle(color: secondary),
            ),
          )
        else ...[
          ListTile(
            title: Text(
              zones.source,
              style: AppText.caption(context)
                  .copyWith(color: zones.isApproximate ? AppColors.of(context).caution : secondary),
            ),
            trailing: Text(
              '${zones.lactateThreshold ?? 0} bpm Schwelle',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ZoneBand(zones: zones.fiveZones),
          ),
          if (zones.easyLimit case final easy?) ListTile(dense: true, title: Text('Locker (Z1–2): bis $easy bpm')),
          ExpansionTile(
            title: const Text('Alle Zonen'),
            children: [
              for (final zone in zones.zones) LabeledRow(label: '${zone.name} · ${zone.use}', value: zone.rangeText),
            ],
          ),
        ],
      ],
    );
  }
}

class _ZoneBand extends StatelessWidget {
  const _ZoneBand({required this.zones});

  final List<HeartRateZone> zones;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 4,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 10,
          child: Row(
            spacing: 2,
            children: [
              for (var index = 0; index < zones.length; index++)
                Expanded(child: ColoredBox(color: _zoneColors[math.min(index, _zoneColors.length - 1)])),
            ],
          ),
        ),
      ),
      Row(
        spacing: 2,
        children: [
          for (final zone in zones)
            Expanded(
              child: Column(
                children: [
                  Text(zone.name, style: AppText.caption(context).copyWith(fontWeight: FontWeight.bold)),
                  FittedBox(
                    child: Text(
                      zone.rangeText,
                      style: AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

class _IntensitySection extends StatelessWidget {
  const _IntensitySection({required this.distribution});

  final ZoneDistribution distribution;

  @override
  Widget build(BuildContext context) => FormSection(
    header: 'Intensität (letzte ${distribution.weeks} Wochen)',
    footer: 'Zeit in den Zonen der Uhr. Richtwert: ca. 80 % locker (Z1–2).',
    children: [
      if (distribution.run == null && distribution.bike == null)
        ListTile(
          title: Text(
            'Keine Zonendaten der Uhr in den letzten ${distribution.weeks} Wochen.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      if (distribution.run case final share?) _ShareRow(title: 'Laufen', share: share),
      if (distribution.bike case final share?) _ShareRow(title: 'Rad', share: share),
      if (distribution.perWeek.isNotEmpty)
        ExpansionTile(
          title: const Text('Je Woche'),
          children: [
            for (final week in distribution.perWeek) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Woche ab ${GermanFormat.date(week.monday)}',
                    style: AppText.caption(context).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (week.run case final share?) _ShareRow(title: 'Laufen', share: share),
              if (week.bike case final share?) _ShareRow(title: 'Rad', share: share),
            ],
          ],
        ),
    ],
  );
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.title, required this.share});

  final String title;
  final IntensityShare share;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text(
              formatDuration(share.minutes * 60.0),
              style: AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(
              spacing: 2,
              children: [
                for (final (index, percent) in share.zonePercent.indexed)
                  if (percent > 0)
                    Expanded(
                      flex: percent,
                      child: ColoredBox(color: _zoneColors[math.min(index, _zoneColors.length - 1)]),
                    ),
              ],
            ),
          ),
        ),
        Text(
          'locker ${share.easyPercent} % · mittel ${share.moderatePercent} % · hart ${share.hardPercent} %',
          style: AppText.caption(context)
              .copyWith(color: share.easyPercent >= 75 ? AppColors.of(context).good : AppColors.of(context).caution),
        ),
      ],
    ),
  );
}

// Trends

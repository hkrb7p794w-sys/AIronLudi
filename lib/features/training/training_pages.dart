import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/zoomable_chart.dart';
import '../evidence/evidence_views.dart';
import 'training_controller.dart';

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
  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: interval,
      getTitlesWidget: (value, meta) => SideTitleWidget(
        meta: meta,
        child: Text(_dayLabel(value), style: const TextStyle(fontSize: 10)),
      ),
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
                    'Noch keine Garmin-Werte. Ziehe nach unten, um abzurufen.',
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
                  'Training Readiness, Trainingsstatus und Endurance Score gibt es nur mit dem Garmin-Konto '
                  '(Einstellungen); die Personal API liefert sie nicht.',
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
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    tile.title,
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
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
        : ((change > 0) == higher ? Colors.green : Colors.orange);
    final values = [for (final point in trend.points) point.value];
    final low = values.isEmpty ? 0.0 : values.reduce(math.min);
    final high = values.isEmpty ? 1.0 : values.reduce(math.max);
    final padding = math.max((high - low) * 0.15, 1.0);
    final secondary = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
      ('Tief', metrics.deepSleepSeconds ?? 0, Colors.indigo),
      ('Leicht', metrics.lightSleepSeconds ?? 0, Colors.blue),
      ('REM', metrics.remSleepSeconds ?? 0, Colors.cyan),
      ('Wach', metrics.awakeSleepSeconds ?? 0, Colors.orange),
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
                    Text(name, style: TextStyle(fontSize: 12, color: color)),
                    Text(formatDuration(seconds), style: const TextStyle(fontSize: 12)),
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

const _zoneColors = [Colors.grey, Colors.blue, Colors.green, Colors.orange, Colors.red];

/// Pulszonen: HFmax, Coach-Zonen je Sportart, Intensität, Uhr-Zonen und Hinweise (Port von `HeartRateSections`).
class HeartRateScreen extends StatelessWidget {
  const HeartRateScreen({super.key, required this.report});

  final HeartRateZoneReport? report;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
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
              style: TextStyle(fontSize: 12, color: zones.isApproximate ? Colors.orange : secondary),
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
                  Text(zone.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  FittedBox(
                    child: Text(
                      zone.rangeText,
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
          style: TextStyle(fontSize: 12, color: share.easyPercent >= 75 ? Colors.green : Colors.orange),
        ),
      ],
    ),
  );
}

// Trends

/// Minuten je Sportart und Woche (gestapelt), Form-Kurve mit „heute“ und aerobe Effizienz lockerer Läufe
/// (Port von `TrendsPage`).
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key, required this.activities, required this.gym});

  final List<GarminActivity> activities;
  final List<GymItem> gym;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.today();
    final minutes = TrainingTrends.weeklyMinutes(
      activities: widget.activities,
      gym: widget.gym,
      today: today,
      weeks: _weeks,
    );
    final form = FitnessForm.seriesUntil(widget.activities, today: today);
    final efficiency = TrainingTrends.aerobicEfficiency(widget.activities);
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final sports = [
      for (final sport in TrainingSport.values)
        if (minutes.any((entry) => entry.sport == sport)) sport,
    ];
    final mondays = {for (final entry in minutes) entry.monday}.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Minuten je Woche',
            footer: 'Alle Quellen, Gym-Einheiten der App eingerechnet; doppelte Aufzeichnungen zählen einmal.',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 12, label: Text('12 Wochen')),
                    ButtonSegment(value: 26, label: Text('26 Wochen')),
                    ButtonSegment(value: 52, label: Text('1 Jahr')),
                  ],
                  selected: {_weeks},
                  onSelectionChanged: (value) => setState(() => _weeks = value.first),
                ),
              ),
              if (minutes.isEmpty)
                ListTile(title: Text('Noch keine Aktivitäten in diesem Zeitraum.', style: secondary))
              else ...[
                Semantics(
                  label: 'Trainingsminuten je Woche und Sportart, letzte $_weeks Wochen',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          barGroups: [
                            for (final (index, monday) in mondays.indexed)
                              () {
                                var from = 0.0;
                                final stack = <BarChartRodStackItem>[];
                                for (final sport in sports) {
                                  final value = minutes
                                      .where((entry) => entry.monday == monday && entry.sport == sport)
                                      .fold<int>(0, (sum, entry) => sum + entry.minutes)
                                      .toDouble();
                                  if (value <= 0) continue;
                                  stack.add(BarChartRodStackItem(from, from + value, sport.color));
                                  from += value;
                                }
                                return BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: from,
                                      rodStackItems: stack,
                                      width: math.max(4, 200 / mondays.length),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ],
                                );
                              }(),
                          ],
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: math.max(1, (mondays.length / 4).ceilToDouble()),
                                getTitlesWidget: (value, meta) => SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    DateFormat('d.M.', 'de_DE').format(mondays[value.toInt()].referenceDate),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      for (final sport in sports)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 4,
                          children: [
                            CircleAvatar(radius: 5, backgroundColor: sport.color),
                            Text(sport.label, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          FormSection(
            header: 'Form',
            footer:
                'Fitness minus Ermüdung (Belastung über 42 bzw. 7 Tage). Unter −30 % der Fitness rät die Tagesampel '
                'zu lockerem Training.',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FitnessForm.isReliable(form)
                    ? ZoomableTrendChart(
                        points: [for (final point in form) (date: point.day.referenceDate, value: point.form)],
                        unit: 'Form',
                        includesZero: true,
                        bars: true,
                        marksToday: true,
                      )
                    : Text(
                        'Die Form-Kurve braucht Trainingsbelastung der Uhr aus mindestens ${FitnessForm.warmUpDays} Tagen.',
                        style: secondary,
                      ),
              ),
            ],
          ),
          FormSection(
            header: 'Aerobe Effizienz (lockere Läufe)',
            footer:
                'Meter je Herzschlag: Tempo geteilt durch die mittlere Herzfrequenz. Steigt der Wert bei lockeren '
                'Läufen, wird die Grundlage besser. Hitze, Hügel und Müdigkeit drücken ihn – auf den Trend achten, '
                'nicht auf einzelne Läufe.',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: efficiency.length >= 2
                    ? ZoomableTrendChart(
                        points: [for (final value in efficiency) (date: value.day.referenceDate, value: value.value)],
                        unit: 'm je Schlag',
                        minimumPadding: 0.02,
                      )
                    : Text(
                        'Dafür braucht es mindestens zwei lockere Läufe ab 20 Minuten mit Herzfrequenz und Strecke.',
                        style: secondary,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Fitness & Form

/// Fitness, Ermüdung und Form aus der Trainingsbelastung der Uhr mit Einordnung (Port von `FitnessFormPage`).
class FitnessFormScreen extends StatelessWidget {
  const FitnessFormScreen({super.key, required this.points});

  final List<FormPoint> points;

  @override
  Widget build(BuildContext context) {
    final recent = points.length > 90 ? points.sublist(points.length - 90) : points;
    final last = points.lastOrNull;
    final percent = last?.formPercent;
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Fitness & Form')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (last != null && percent != null && FitnessForm.isReliable(points))
            FormSection(
              header: 'Heute',
              footer: 'Die Grenzen der Einordnung sind Praxiswerte aus Trainingssoftware, keine Studienergebnisse.',
              children: [
                ListTile(
                  title: Text(
                    FormZone.of(percent).label,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(FormZone.of(percent).explanation),
                ),
                LabeledRow(label: 'Fitness', value: GermanFormat.number(last.fitness)),
                LabeledRow(label: 'Ermüdung', value: GermanFormat.number(last.fatigue)),
                LabeledRow(label: 'Form', value: '${GermanFormat.number(last.form)} (${percent.round()} %)'),
              ],
            )
          else
            FormSection(
              children: [
                ListTile(
                  title: Text(
                    'Für eine aussagekräftige Kurve braucht die App Trainingsbelastung aus mindestens '
                    '${FitnessForm.warmUpDays} Tagen. Die Uhr liefert sie zu jeder aufgezeichneten Aktivität.',
                    style: secondary,
                  ),
                ),
              ],
            ),
          if (recent.isNotEmpty)
            FormSection(
              header: 'Letzte 90 Tage',
              children: [
                Semantics(
                  label: 'Fitness, Ermüdung und Form der letzten 90 Tage',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: SizedBox(
                      height: 220,
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [
                            for (final point in recent)
                              LineChartBarData(
                                spots: [FlSpot(_x(point.day), 0), FlSpot(_x(point.day), point.form)],
                                color: (point.form >= 0 ? Colors.green : Colors.orange).withValues(alpha: 0.5),
                                barWidth: 2,
                                dotData: const FlDotData(show: false),
                              ),
                            LineChartBarData(
                              spots: [for (final point in recent) FlSpot(_x(point.day), point.fitness)],
                              color: Colors.blue,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: [for (final point in recent) FlSpot(_x(point.day), point.fatigue)],
                              color: Colors.pink,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                          titlesData: _titles(interval: 30),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    spacing: 12,
                    children: [
                      _Legend(color: Colors.blue, label: 'Fitness'),
                      _Legend(color: Colors.pink, label: 'Ermüdung'),
                      _Legend(color: Colors.green, label: 'Form'),
                    ],
                  ),
                ),
              ],
            ),
          FormSection(
            children: [
              ListTile(
                title: Text(
                  'Fitness ist der Schnitt deiner Belastung über 42 Tage, Ermüdung über 7 Tage. Form ist die Differenz: '
                  'positiv, wenn du erholter bist, als dein Training gewohnt ist. Nur Aktivitäten mit Belastungswert der '
                  'Uhr zählen.',
                  style: secondary.copyWith(fontSize: 13),
                ),
              ),
              const EvidenceDisclosure(ruleIDs: ['load.fitness-form']),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      CircleAvatar(radius: 5, backgroundColor: color),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

// Wochenbericht

/// Wochenbericht der letzten Kalenderwoche im Vergleich zur Vorwoche (Port von `WeeklyReportPage`).
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key, required this.report});

  final WeeklyReport report;

  static String minutes(double value) {
    final total = value.toInt();
    return total >= 60 ? '${total ~/ 60} h ${total % 60} min' : '$total min';
  }

  static String sportLabel(ActivitySport sport) => switch (sport) {
    ActivitySport.run => 'Laufen',
    ActivitySport.bike => 'Rad',
    ActivitySport.swim => 'Schwimmen',
    ActivitySport.strength => 'Kraft',
    _ => 'Sonstiges',
  };

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget row(String title, String value, String previous) => ListTile(
      title: Text(title),
      trailing: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value),
            TextSpan(text: '  ($previous)', style: secondary),
          ],
        ),
      ),
    );
    String unit(double? value, String unit) => value == null ? '–' : '${GermanFormat.number(value)} $unit';
    final week = report.week;
    final previous = report.previous;
    return Scaffold(
      appBar: AppBar(title: const Text('Wochenbericht')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Woche ab ${GermanFormat.date(report.monday)}',
            children: [
              if (report.highlights.isEmpty)
                const ListTile(title: Text('Eine ruhige, gleichmäßige Woche – nichts Auffälliges.')),
              for (final line in report.highlights)
                ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(line)),
            ],
          ),
          FormSection(
            header: 'Zahlen (Vorwoche)',
            children: [
              row('Einheiten', '${week.sessions}', '${previous.sessions}'),
              row('Trainingszeit', minutes(week.minutes), minutes(previous.minutes)),
              row('Belastung', GermanFormat.number(week.load), GermanFormat.number(previous.load)),
              for (final sport in const [ActivitySport.run, ActivitySport.bike, ActivitySport.swim])
                if (week.kilometers[sport] case final kilometers?)
                  row(sportLabel(sport), unit(kilometers, 'km'), unit(previous.kilometers[sport], 'km')),
              if (report.fitnessChange case final change?)
                LabeledRow(label: 'Fitness', value: '${change > 0 ? '+' : ''}${GermanFormat.number(change)}'),
            ],
          ),
          FormSection(
            header: 'Erholung (Vorwoche)',
            children: [
              row('Schlaf', unit(week.averageSleepHours, 'h'), unit(previous.averageSleepHours, 'h')),
              row('HRV', unit(week.averageHRV, 'ms'), unit(previous.averageHRV, 'ms')),
              row('Ruhepuls', unit(week.averageRestingHeartRate, 'bpm'), unit(previous.averageRestingHeartRate, 'bpm')),
            ],
          ),
        ],
      ),
    );
  }
}

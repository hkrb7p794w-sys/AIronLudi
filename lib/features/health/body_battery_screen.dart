import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../ui/components.dart';

/// Body Battery: aktueller Stand, Tagesverlauf, 30 Tage und Zusammenhang mit Schlaf und Stress (Port von
/// `BodyBatteryView`).
class BodyBatteryScreen extends ConsumerStatefulWidget {
  const BodyBatteryScreen({super.key});

  @override
  ConsumerState<BodyBatteryScreen> createState() => _BodyBatteryScreenState();
}

class _BodyBatteryScreenState extends ConsumerState<BodyBatteryScreen> {
  List<DailyMetrics> _days = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final today = CalendarDay.today();
    final days = await ref.read(metricsRepositoryProvider).range(from: today.adding(-60), to: today);
    if (mounted) setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final today = CalendarDay.today();
    final summary = BodyBatteryAnalysis.summary(days: _days, today: today);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Body Battery')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (!summary.hasData)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                spacing: 8,
                children: [
                  Icon(Icons.battery_0_bar, size: 44, color: secondary),
                  Text(
                    'Keine Body Battery',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Body Battery gibt es nur von Garmin-Uhren. Melde dich in den Einstellungen mit dem Garmin-Konto an '
                    'und ziehe nach unten zum Abrufen. Apple Health hat keinen vergleichbaren Wert.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary),
                  ),
                ],
              ),
            )
          else ...[
            FormSection(
              children: [_Header(summary: summary, today: today)],
            ),
            if (summary.curve.length >= 2)
              FormSection(
                header: summary.currentDay == today ? 'Heute' : 'Gestern',
                footer: 'Lädt im Schlaf und in Ruhe, sinkt bei Belastung und Stress.',
                children: [_CurveChart(curve: summary.curve)],
              ),
            if (summary.history.length >= 2)
              FormSection(
                header: 'Letzte 30 Tage',
                footer:
                    'Balken: Tiefst- bis Höchstwert des Tages. Punkt: Stand beim Aufwachen. '
                    '${summary.wakeNorm == null ? 'Dein üblicher Bereich erscheint ab 7 Tagen mit Aufwachwert.' : 'Grau hinterlegt: dein üblicher Aufwachwert.'}',
                children: [_HistoryChart(history: summary.history, norm: summary.wakeNorm)],
              ),
            FormSection(
              header: 'Schlaf und Stress',
              footer: 'Vergleich deiner eigenen Tage, keine Ursache. Werte der Uhr (Garmin).',
              children: [
                if (summary.relations.isEmpty)
                  ListTile(
                    title: Text(
                      'Für einen Vergleich braucht es je mindestens 3 Tage mit langen und kurzen Nächten bzw. viel und '
                      'wenig Stress.',
                      style: TextStyle(color: secondary),
                    ),
                  ),
                for (final relation in summary.relations)
                  ListTile(
                    leading: Icon(relation.id == 'sleep' ? Icons.bed_outlined : Icons.monitor_heart_outlined),
                    title: Text(relation.text),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Kopf: aktueller Stand mit Einordnung, Aufwachwert gegenüber dem eigenen Bereich, Laden und Verbrauch.
class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.today});

  final BodyBatterySummary summary;
  final CalendarDay today;

  String _normText(double wake) {
    final norm = summary.wakeNorm;
    if (norm == null) return '';
    return switch (norm.position(wake)) {
      NormPosition.below => ' – unter deinem üblichen Bereich (${norm.low.toInt()}–${norm.high.toInt()})',
      NormPosition.within => ' – in deinem üblichen Bereich',
      NormPosition.above => ' – über deinem üblichen Bereich',
    };
  }

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final current = summary.current;
    final wake = summary.wake;
    final latest = summary.history.lastOrNull;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          BatteryGauge(value: current),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                if (current != null) ...[
                  Text(
                    '${current.toInt()} · ${BodyBatteryAnalysis.band(current)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (summary.currentMinute case final minute?)
                    Text(
                      'Stand ${summary.currentDay == today ? 'heute' : 'gestern'} ${SleepCoach.clock(minute)} Uhr',
                      style: secondary,
                    ),
                ] else
                  const Text('Aktueller Stand fehlt', style: TextStyle(fontWeight: FontWeight.w600)),
                if (wake != null)
                  Text('Beim Aufwachen ${wake.toInt()}${_normText(wake)}')
                else
                  Text('Aufwachwert heute fehlt', style: secondary.copyWith(fontSize: 14)),
                if (latest != null && (latest.charged != null || latest.drained != null))
                  Text(
                    'Geladen +${latest.charged?.toInt() ?? '–'} · verbraucht −${latest.drained?.toInt() ?? '–'}',
                    style: secondary,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ring mit Füllstand (statt `Gauge`), Farbe von rot bis blau.
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({super.key, required this.value});

  final double? value;

  static Color color(double value) => switch (value) {
    < 26 => Colors.red,
    < 51 => Colors.orange,
    < 76 => Colors.green,
    _ => Colors.blue,
  };

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final fraction = ((value ?? 0).clamp(0, 100)) / 100;
    return Semantics(
      label: 'Body Battery ${value == null ? 'unbekannt' : value.toInt()}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: fraction.toDouble(),
                strokeWidth: 6,
                color: color(value ?? 0),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, size: 14),
                Text(value == null ? '–' : '${value.toInt()}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tagesverlauf (Viertelstunden).
class _CurveChart extends StatelessWidget {
  const _CurveChart({required this.curve});

  final List<BodyBatterySample> curve;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Body-Battery-Verlauf von heute',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: SizedBox(
        height: 160,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 24,
            minY: 0,
            maxY: 100,
            lineBarsData: [
              LineChartBarData(
                spots: [for (final sample in curve) FlSpot(sample.minute / 60, sample.value.toDouble())],
                color: Colors.blue,
                barWidth: 2,
                isCurved: true,
                preventCurveOverShooting: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.blue.withValues(alpha: 0.35), Colors.blue.withValues(alpha: 0.05)],
                  ),
                ),
              ),
            ],
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 6,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text('${value.toInt()} Uhr', style: const TextStyle(fontSize: 10)),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    ),
  );
}

/// 30 Tage: Spanne je Tag und Aufwachwert, dazu der eigene übliche Bereich.
class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.history, required this.norm});

  final List<BodyBatteryDay> history;
  final PersonalNorm? norm;

  @override
  Widget build(BuildContext context) {
    final norm = this.norm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: SizedBox(
        height: 170,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: 100,
            barGroups: [
              for (final (index, day) in history.indexed)
                BarChartGroupData(
                  x: index,
                  groupVertically: true,
                  barRods: [
                    if (day.low != null && day.high != null)
                      BarChartRodData(
                        fromY: day.low!,
                        toY: day.high!,
                        width: 6,
                        color: Colors.blue.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    // Stand beim Aufwachen als kurze Marke (Punkt in Swift).
                    if (day.wake case final wake?)
                      BarChartRodData(
                        fromY: (wake - 1.5).clamp(0, 100),
                        toY: (wake + 1.5).clamp(0, 100),
                        width: 6,
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                  ],
                ),
            ],
            extraLinesData: ExtraLinesData(extraLinesOnTop: true, horizontalLines: const []),
            rangeAnnotations: RangeAnnotations(
              horizontalRangeAnnotations: [
                if (norm != null)
                  HorizontalRangeAnnotation(y1: norm.low, y2: norm.high, color: Colors.grey.withValues(alpha: 0.15)),
              ],
            ),
            barTouchData: BarTouchData(enabled: false),
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(),
              rightTitles: AxisTitles(),
              bottomTitles: AxisTitles(),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25)),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

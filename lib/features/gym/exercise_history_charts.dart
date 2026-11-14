import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ui/components.dart';

/// Verlauf einer Übung: 1RM bzw. Höchstgewicht und die bewegte Last je Einheit. Zeitraum per Knopf, mit zwei
/// Fingern zoomen, seitlich wischen zum Verschieben; die Y-Achse passt sich dem sichtbaren Ausschnitt an. Beide
/// Diagramme zeigen denselben Ausschnitt (Port von `ExerciseHistoryCharts`).
class ExerciseHistoryCharts extends StatefulWidget {
  const ExerciseHistoryCharts({super.key, required this.history});

  final List<GymStatsPoint> history;

  @override
  State<ExerciseHistoryCharts> createState() => _ExerciseHistoryChartsState();
}

class _ExerciseHistoryChartsState extends State<ExerciseHistoryCharts> {
  static const _dayMs = Duration.millisecondsPerDay;
  bool _oneRepMax = true;
  late double _days;
  late DateTime _start;
  double? _zoomBase;

  List<DateTime> get _dates => [for (final point in widget.history) point.day.referenceDate];
  double get _span => ChartZoom.spanDays(_dates);

  @override
  void initState() {
    super.initState();
    _days = ChartZoom.initialDays(_span);
    _start = ChartZoom.initialStart(_dates, days: _days);
  }

  String? get _presetLabel {
    for (final preset in ChartZoom.presets) {
      if (((preset.days == null ? _span : ChartZoom.clamp(preset.days!, span: _span)) - _days).abs() < 0.5) {
        return preset.label;
      }
    }
    return null;
  }

  double _x(DateTime date) => date.millisecondsSinceEpoch / _dayMs;

  Widget _chart(List<({DateTime date, double value})> points, {required bool includesZero, required bool bars}) {
    final color = Theme.of(context).colorScheme.primary;
    final domain = ChartZoom.yDomain(points, from: _start, days: _days, includesZero: includesZero);
    final minX = _x(_start);
    final maxX = minX + _days;
    final showsPoints = ChartZoom.showsPoints(days: _days, count: points.length, span: _span);
    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: math.max(1, _days / 4),
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              DateFormat('d.M.', 'de_DE').format(DateTime.fromMillisecondsSinceEpoch((value * _dayMs).round())),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      ),
    );
    final visible = [
      for (final point in points)
        if (_x(point.date) >= minX - 1 && _x(point.date) <= maxX + 1) point,
    ];
    if (bars) {
      return BarChart(
        BarChartData(
          minY: domain.low,
          maxY: domain.high,
          alignment: BarChartAlignment.center,
          barGroups: [
            for (final point in visible)
              BarChartGroupData(
                x: _x(point.date).round(),
                barRods: [BarChartRodData(toY: point.value, width: 6, color: color.withValues(alpha: 0.7))],
              ),
          ],
          titlesData: titles,
          borderData: FlBorderData(show: false),
        ),
      );
    }
    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: domain.low,
        maxY: domain.high,
        clipData: const FlClipData.all(),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final point in points) FlSpot(_x(point.date), point.value)],
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: showsPoints),
          ),
        ],
        titlesData: titles,
        borderData: FlBorderData(show: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strength = [
      for (final point in widget.history)
        (
          date: point.day.referenceDate,
          value: _oneRepMax ? (point.oneRepMaxKg ?? point.topWeightKg) : point.topWeightKg,
        ),
    ];
    final volume = [for (final point in widget.history) (date: point.day.referenceDate, value: point.volumeKg)];
    final end = _start.add(Duration(milliseconds: (_days * _dayMs).round()));
    final format = DateFormat('dd.MM.yy', 'de_DE');
    // Seitlich wischen verschiebt, zwei Finger zoomen um die Mitte.
    Widget gestures(Widget child) => LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onScaleStart: (_) => _zoomBase = _days,
        onScaleUpdate: (details) => setState(() {
          final width = math.max(constraints.maxWidth, 1);
          if (details.pointerCount > 1) {
            final center = _start.add(Duration(milliseconds: (_days * _dayMs / 2).round()));
            _days = ChartZoom.clamp((_zoomBase ?? _days) / math.max(details.scale, 0.1), span: _span);
            _start = center.subtract(Duration(milliseconds: (_days * _dayMs / 2).round()));
          } else {
            _start = _start.subtract(
              Duration(milliseconds: (details.focalPointDelta.dx / width * _days * _dayMs).round()),
            );
          }
        }),
        onScaleEnd: (_) => _zoomBase = null,
        child: child,
      ),
    );
    return FormSection(
      header: 'Verlauf',
      footer:
          '${format.format(_start)} – ${format.format(end)} · Mit zwei Fingern zoomen, seitlich wischen zum Verschieben. '
          '1RM geschätzt nach Epley aus Sätzen mit bis zu 12 Wiederholungen; bewegte Last = Gewicht × Wiederholungen aller '
          'Sätze.',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final preset in ChartZoom.presets) ButtonSegment(value: preset.label, label: Text(preset.label)),
            ],
            selected: {?_presetLabel},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              final preset = ChartZoom.presets.firstWhere((preset) => preset.label == selection.first);
              setState(() {
                _days = ChartZoom.clamp(preset.days ?? _span, span: _span);
                _start = ChartZoom.initialStart(_dates, days: _days);
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Geschätztes 1RM')),
              ButtonSegment(value: false, label: Text('Höchstgewicht')),
            ],
            selected: {_oneRepMax},
            onSelectionChanged: (value) => setState(() => _oneRepMax = value.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: SizedBox(height: 180, child: gestures(_chart(strength, includesZero: false, bars: false))),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Bewegte Last je Einheit', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: SizedBox(height: 140, child: gestures(_chart(volume, includesZero: true, bars: true))),
        ),
      ],
    );
  }
}

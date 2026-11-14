import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Verlauf mit Zeitraum-Knöpfen, Zoom mit zwei Fingern und seitlichem Verschieben (Port von `ZoomableTrendChart`).
class ZoomableTrendChart extends StatefulWidget {
  const ZoomableTrendChart({
    super.key,
    required this.points,
    required this.unit,
    this.includesZero = false,
    this.minimumPadding = 1,
    this.bars = false,
    this.marksToday = false,
  });

  final List<({DateTime date, double value})> points;
  final String unit;
  final bool includesZero;
  final double minimumPadding;
  final bool bars;

  /// Linie bei heute.
  final bool marksToday;

  @override
  State<ZoomableTrendChart> createState() => _ZoomableTrendChartState();
}

class _ZoomableTrendChartState extends State<ZoomableTrendChart> {
  static const _dayMs = Duration.millisecondsPerDay;
  late double _days;
  late DateTime _start;
  double? _zoomBase;

  List<DateTime> get _dates => [for (final point in widget.points) point.date, if (widget.marksToday) DateTime.now()];
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

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final domain = ChartZoom.yDomain(
      widget.points,
      from: _start,
      days: _days,
      includesZero: widget.includesZero,
      minimumPadding: widget.minimumPadding,
    );
    final minX = _x(_start);
    final maxX = minX + _days;
    final showsPoints = ChartZoom.showsPoints(days: _days, count: widget.points.length, span: _span);
    final today = _x(DateTime.now());
    final chart = LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: domain.low,
        maxY: domain.high,
        clipData: const FlClipData.all(),
        lineBarsData: [
          if (widget.bars)
            // Balken als senkrechte Linien je Tag: grün über null, orange darunter.
            for (final point in widget.points)
              LineChartBarData(
                spots: [FlSpot(_x(point.date), 0), FlSpot(_x(point.date), point.value)],
                color: (point.value >= 0 ? Colors.green : Colors.orange).withValues(alpha: 0.6),
                barWidth: math.max(1, 240 / _days),
                dotData: const FlDotData(show: false),
              )
          else
            LineChartBarData(
              spots: [for (final point in widget.points) FlSpot(_x(point.date), point.value)],
              color: color,
              barWidth: 2,
              dotData: FlDotData(show: showsPoints),
            ),
        ],
        extraLinesData: ExtraLinesData(
          verticalLines: [
            if (widget.marksToday)
              VerticalLine(
                x: today,
                color: color,
                strokeWidth: 1,
                label: VerticalLineLabel(show: true, labelResolver: (_) => 'heute', alignment: Alignment.topRight),
              ),
          ],
        ),
        titlesData: FlTitlesData(
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
        ),
        borderData: FlBorderData(show: false),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        SegmentedButton<String>(
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
        Semantics(
          label: 'Verlauf ${widget.unit}',
          child: SizedBox(
            height: 180,
            child: LayoutBuilder(
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
                child: chart,
              ),
            ),
          ),
        ),
        Text(
          'Mit zwei Fingern zoomen, seitlich wischen zum Verschieben.',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

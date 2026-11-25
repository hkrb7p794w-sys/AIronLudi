import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'chart_axes.dart';
import 'components.dart';
import 'sport_style.dart';

/// Trainingszeit je Woche, gestapelt nach Sportart (älteste Woche links, diese Woche rechts).
class WeekMinutesChart extends StatelessWidget {
  const WeekMinutesChart({super.key, required this.minutes, required this.today, this.weeks = 8, this.onTap});

  final List<SportMinutes> minutes;
  final CalendarDay today;
  final int weeks;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thisMonday = PlanAdjustments.monday(today);
    final mondays = [for (var index = weeks - 1; index >= 0; index--) thisMonday.adding(-7 * index)];
    final sports = [
      for (final sport in TrainingSport.values)
        if (minutes.any((entry) => entry.sport == sport)) sport,
    ];
    int total(CalendarDay monday) =>
        minutes.where((entry) => entry.monday == monday).fold(0, (sum, entry) => sum + entry.minutes);
    final maxY = math.max(60, mondays.map(total).fold(0, math.max)) * 1.15;
    final current = total(thisMonday);
    final previous = total(thisMonday.adding(-7));
    String hours(int minutes) => '${GermanFormat.decimal((minutes / 6).round() / 10)} h';
    return FormSection(
      header: 'Trainingszeit je Woche',
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(hours(current), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'diese Woche · Vorwoche ${hours(previous)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (sports.isEmpty)
                  Text(
                    'Noch keine Trainings in den letzten $weeks Wochen.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else
                  SizedBox(
                    height: 120,
                    child: Semantics(
                      label: 'Trainingszeit der letzten $weeks Wochen, diese Woche ${hours(current)}',
                      excludeSemantics: true,
                      child: BarChart(
                        BarChartData(
                          maxY: maxY,
                          barTouchData: const BarTouchData(enabled: false),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            topTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 18,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= mondays.length) return const SizedBox.shrink();
                                  final day = mondays[index];
                                  return SideTitleWidget(
                                    meta: meta,
                                    child: AxisLabel(
                                      index == mondays.length - 1 ? 'jetzt' : '${day.day}.${day.month}.',
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (final (index, monday) in mondays.indexed)
                              () {
                                var from = 0.0;
                                final stack = <BarChartRodStackItem>[];
                                for (final sport in sports) {
                                  final value = minutes
                                      .where((entry) => entry.monday == monday && entry.sport == sport)
                                      .fold(0, (sum, entry) => sum + entry.minutes)
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
                                      width: 14,
                                      rodStackItems: stack,
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ],
                                );
                              }(),
                          ],
                        ),
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final sport in sports) AppChip(text: sport.shortLabel, color: sport.color)],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../today/now_views.dart';
import '../training/sleep_coach_screen.dart';
import '../training/training_pages.dart';
import 'body_battery_screen.dart';
import 'mobility_screen.dart';
import 'morning_report_views.dart';

/// Daten für die Widgets: Tageswerte plus Ersatzquellen (Wägungen, Belastung aus den eigenen Aktivitäten).
final class HealthData {
  HealthData({
    required this.days,
    required List<WeightEntry> weights,
    required List<GarminActivity> activities,
    required this.today,
  }) : extra = {
         HealthWidget.weight: [
           for (final entry in WeightTrend.merged(weights)) DayValue(day: entry.day, value: entry.kilograms),
         ],
         // Ohne Garmin-Konto: Tagesbelastung aus den eigenen Aktivitäten (gleiche Grundlage wie „Fitness & Form“).
         HealthWidget.trainingLoad: [
           for (final point in FitnessForm.seriesUntil(activities, today: today))
             if (point.load > 0) DayValue(day: point.day, value: point.load.roundToDouble()),
         ],
       };

  final List<DailyMetrics> days;
  final Map<HealthWidget, List<DayValue>> extra;
  final CalendarDay today;

  Set<HealthWidget> get available => HealthDashboard.available(days: days, extra: extra, today: today);

  List<DayValue> series(HealthWidget kind, {required int window}) =>
      HealthDashboard.series(kind, days: days, extra: extra, today: today, window: window);

  /// Persönlicher Bereich der letzten 30 Tage ohne heute.
  PersonalNorm? norm(HealthWidget kind) => PersonalNorm.of([
    for (final point in series(kind, window: PersonalNorm.windowDays + 1))
      if (point.day < today) point.value,
  ]);

  DailyMetrics? metrics(CalendarDay day) => days.where((metrics) => metrics.day == day).firstOrNull;
}

extension HealthWidgetStyleExt on HealthWidget {
  IconData get icon => switch (this) {
    HealthWidget.bodyBattery => Icons.battery_charging_full,
    HealthWidget.hrv => Icons.monitor_heart_outlined,
    HealthWidget.restingHeartRate => Icons.favorite,
    HealthWidget.sleep => Icons.bed,
    HealthWidget.stress => Icons.psychology_outlined,
    HealthWidget.vo2Max => Icons.air,
    HealthWidget.trainingLoad => Icons.bar_chart,
    HealthWidget.recoveryTime => Icons.hourglass_bottom,
    HealthWidget.readiness => Icons.speed,
    HealthWidget.steps => Icons.directions_walk,
    HealthWidget.activeCalories => Icons.local_fire_department,
    HealthWidget.restingCalories => Icons.local_fire_department_outlined,
    HealthWidget.weight => Icons.monitor_weight_outlined,
    HealthWidget.heartRateRange => Icons.favorite_border,
    HealthWidget.respiration => Icons.waves,
    HealthWidget.spo2 => Icons.water_drop,
  };

  Color get color => switch (category) {
    HealthCategory.health => Colors.red,
    HealthCategory.sleep => Colors.indigo,
    HealthCategory.recovery => Colors.teal,
    HealthCategory.load => Colors.orange,
    HealthCategory.performance => Colors.purple,
  };
}

/// Gesundheitsbereich: Morning Report oben, darunter die konfigurierbaren Widgets (Port von `HealthDashboardView`).
class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  List<DailyMetrics> _days = const [];
  List<GarminActivity> _activities = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final today = CalendarDay.today();
    final results = await (
      ref.read(metricsRepositoryProvider).range(from: today.adding(-400), to: today),
      ref.read(activityRepositoryProvider).all(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _days = [...results.$1]..sort((a, b) => a.day.compareTo(b.day));
      _activities = results.$2;
    });
  }

  void _push(Widget screen) => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));

  @override
  Widget build(BuildContext context) {
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final model = ref.watch(appModelProvider);
    final today = CalendarDay.today();
    final data = HealthData(days: _days, weights: model.allWeights, activities: _activities, today: today);
    final available = data.available;
    final visible = settings.healthDashboard.visible(available);
    final report = MorningReportBuilder.make(settings: settings, days: _days, activities: _activities, focus: null);
    final missing = [
      for (final entry in settings.healthDashboard.entries)
        if (!entry.hidden && !available.contains(entry.kind)) entry,
    ];
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gesundheit'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => HealthDashboardEditor(available: available),
              ),
            ),
            child: const Text('Anpassen'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await model.syncNow();
          await _reload();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Card(
              onTap: () => _push(const MorningReportScreen()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      Expanded(child: MorningReportHeader(report: report)),
                      Icon(Icons.chevron_right, color: secondary),
                    ],
                  ),
                  if (report.findings.isNotEmpty)
                    Text(report.findings.take(2).join(' '), style: TextStyle(fontSize: 13, color: secondary)),
                  Text(report.recommendation, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Card(onTap: () => _push(const MobilityScreen()), child: const MobilitySummary()),
            const SizedBox(height: 16),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  spacing: 8,
                  children: [
                    Icon(Icons.monitor_heart_outlined, size: 44, color: secondary),
                    Text(
                      available.isEmpty ? 'Noch keine Werte' : 'Alle Widgets ausgeblendet',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      available.isEmpty
                          ? 'Melde dich mit dem Garmin-Konto an oder schalte Apple Health ein und ziehe nach unten zum '
                                'Abrufen.'
                          : 'Tippe auf „Anpassen“, um Widgets einzublenden oder hinzuzufügen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in visible)
                        SizedBox(
                          width: width,
                          child: _Card(
                            onTap: () => _push(switch (entry.kind) {
                              HealthWidget.bodyBattery => const BodyBatteryScreen(),
                              HealthWidget.sleep => const SleepCoachScreen(),
                              final kind => HealthMetricDetail(kind: kind, data: data),
                            }),
                            child: HealthWidgetCard(entry: entry, data: data),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Ohne Daten in den letzten 30 Tagen (ausgeblendet): '
                  '${missing.map((entry) => '${entry.kind.title} (${entry.kind.sources})').join(', ')}',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  );
}

String _value(HealthWidget kind, double value) => formatNumber(value, unit: kind.unit, digits: kind.digits);

/// Graues Band für den eigenen Bereich im Diagramm.
HorizontalRangeAnnotation _band(PersonalNorm norm, {double alpha = 0.12}) => HorizontalRangeAnnotation(
  y1: norm.low,
  y2: norm.high,
  color: Colors.grey.withValues(alpha: alpha),
);

/// Ein Widget: aktueller Wert, Einordnung gegen den eigenen Bereich und je nach Darstellung ein kleiner Verlauf.
class HealthWidgetCard extends StatelessWidget {
  const HealthWidgetCard({super.key, required this.entry, required this.data});

  final HealthDashboardEntry entry;
  final HealthData data;

  String _valueText(DayValue? latest) {
    if (latest == null) return '–';
    if (entry.kind == HealthWidget.heartRateRange) {
      if (data.metrics(latest.day)?.minHeartRate case final low?) return '${low.toInt()}–${latest.value.toInt()} bpm';
    }
    if (entry.kind == HealthWidget.recoveryTime && latest.value == 0) return 'erholt';
    return _value(entry.kind, latest.value);
  }

  String _caption(DayValue latest, PersonalNorm? norm) {
    final when = latest.day == data.today ? '' : '${shortDate(latest.day)} · ';
    if (norm == null) return '${when}Eigener Bereich ab 7 Tagen';
    return when +
        switch (norm.position(latest.value)) {
          NormPosition.below => 'unter deinem Bereich',
          NormPosition.within => 'im üblichen Bereich',
          NormPosition.above => 'über deinem Bereich',
        };
  }

  Color _color(BuildContext context, DayValue latest, PersonalNorm? norm) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final higher = entry.kind.higherIsBetter;
    if (norm == null || higher == null) return secondary;
    return switch (norm.position(latest.value)) {
      NormPosition.within => secondary,
      NormPosition.above => higher ? Colors.green : Colors.orange,
      NormPosition.below => higher ? Colors.orange : Colors.green,
    };
  }

  @override
  Widget build(BuildContext context) {
    final kind = entry.kind;
    final series = data.series(kind, window: entry.style.days);
    final latest = data.series(kind, window: 7).lastOrNull;
    final norm = data.norm(kind);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(
              spacing: 6,
              children: [
                Icon(kind.icon, size: 16, color: kind.color),
                Expanded(
                  child: Text(
                    kind.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
                  ),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_valueText(latest), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
            if (latest != null)
              Text(
                _caption(latest, norm),
                maxLines: 2,
                style: TextStyle(fontSize: 11, color: _color(context, latest, norm)),
              )
            else
              Text('Keine Werte in den letzten 7 Tagen', style: TextStyle(fontSize: 11, color: secondary)),
            if (entry.style != HealthWidgetStyle.value && series.length >= 2)
              SizedBox(
                height: entry.style == HealthWidgetStyle.month ? 70 : 44,
                child: _MiniChart(series: series, norm: norm, color: kind.color),
              ),
          ],
        ),
      ),
    );
  }
}

double _x(CalendarDay day) => day.referenceDate.millisecondsSinceEpoch / Duration.millisecondsPerDay;

class _MiniChart extends StatelessWidget {
  const _MiniChart({required this.series, required this.norm, required this.color});

  final List<DayValue> series;
  final PersonalNorm? norm;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final norm = this.norm;
    return ExcludeSemantics(
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: [for (final point in series) FlSpot(_x(point.day), point.value)],
              color: color,
              barWidth: 2,
              isCurved: true,
              preventCurveOverShooting: true,
              dotData: const FlDotData(show: false),
            ),
          ],
          rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [if (norm != null) _band(norm)]),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }
}

/// Verlauf eines Werts über 30 oder 90 Tage mit eigenem Bereich (Port von `HealthMetricDetail`).
class HealthMetricDetail extends StatefulWidget {
  const HealthMetricDetail({super.key, required this.kind, required this.data});

  final HealthWidget kind;
  final HealthData data;

  @override
  State<HealthMetricDetail> createState() => _HealthMetricDetailState();
}

class _HealthMetricDetailState extends State<HealthMetricDetail> {
  int _window = 30;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final series = widget.data.series(kind, window: _window);
    final norm = widget.data.norm(kind);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final latest = series.lastOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(kind.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: norm == null
                ? 'Dein üblicher Bereich erscheint ab 7 Tagen mit Werten.'
                : 'Grau: dein üblicher Bereich (Ø ${_value(kind, norm.mean)}, ${norm.count} Tage).',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 30, label: Text('30 Tage')),
                      ButtonSegment(value: 90, label: Text('90 Tage')),
                    ],
                    selected: {_window},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => setState(() => _window = selection.first),
                  ),
                ),
              ),
              if (series.length >= 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
                  child: SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: [for (final point in series) FlSpot(_x(point.day), point.value)],
                            color: kind.color,
                            barWidth: 2,
                            isCurved: true,
                            preventCurveOverShooting: true,
                            dotData: FlDotData(
                              getDotPainter: (spot, percent, bar, index) =>
                                  FlDotCirclePainter(radius: 2, color: kind.color, strokeWidth: 0),
                            ),
                          ),
                        ],
                        rangeAnnotations: RangeAnnotations(
                          horizontalRangeAnnotations: [if (norm != null) _band(norm, alpha: 0.15)],
                        ),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(),
                          rightTitles: AxisTitles(),
                          bottomTitles: AxisTitles(),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                )
              else
                ListTile(
                  title: Text('Zu wenige Werte für einen Verlauf.', style: TextStyle(color: secondary)),
                ),
            ],
          ),
          FormSection(
            header: 'Werte',
            children: [
              LabeledRow(label: 'Tage mit Werten', value: '${series.length} von $_window'),
              if (latest != null)
                LabeledRow(label: 'Zuletzt (${shortDate(latest.day)})', value: _value(kind, latest.value)),
              if (series.isNotEmpty)
                LabeledRow(
                  label: 'Schnitt',
                  value: _value(kind, series.fold(0.0, (sum, point) => sum + point.value) / series.length),
                ),
              LabeledRow(label: 'Quelle', value: kind.sources),
            ],
          ),
        ],
      ),
    );
  }
}

/// Widgets hinzufügen, entfernen, ein-/ausblenden, sortieren und die Darstellung wählen (Port von
/// `HealthDashboardEditor`).
class HealthDashboardEditor extends ConsumerWidget {
  const HealthDashboardEditor({super.key, required this.available});

  final Set<HealthWidget> available;

  void _change(WidgetRef ref, void Function(HealthDashboard dashboard) change) {
    final settings = ref.read(coachSettingsProvider);
    final dashboard = HealthDashboard.fromJson(settings.healthDashboard.toJson()) ?? HealthDashboard();
    change(dashboard);
    settings.healthDashboard = dashboard;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(coachSettingsProvider).healthDashboard;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final addable = [
      for (final kind in HealthWidget.values)
        if (!dashboard.contains(kind)) kind,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Übersicht anpassen'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Im Gesundheitsbereich',
            footer: 'Ziehen zum Sortieren, Auge zum Ein- und Ausblenden, Papierkorb zum Entfernen.',
            children: [
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) =>
                    _change(ref, (dashboard) => dashboard.move(fromOffsets: {from}, toOffset: to > from ? to + 1 : to)),
                children: [
                  for (final (index, entry) in dashboard.entries.indexed)
                    ListTile(
                      key: ValueKey(entry.kind),
                      leading: IconButton(
                        tooltip: entry.hidden ? 'Einblenden' : 'Ausblenden',
                        icon: Icon(
                          entry.hidden ? Icons.visibility_off : Icons.visibility,
                          color: entry.hidden ? secondary : Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () => _change(ref, (dashboard) => dashboard.setHidden(entry.kind, !entry.hidden)),
                      ),
                      title: Row(
                        spacing: 6,
                        children: [
                          Icon(entry.kind.icon, size: 18, color: entry.kind.color),
                          Flexible(
                            child: Text(entry.kind.title, style: TextStyle(color: entry.hidden ? secondary : null)),
                          ),
                        ],
                      ),
                      subtitle: available.contains(entry.kind)
                          ? null
                          : Text('keine Daten (${entry.kind.sources})', style: const TextStyle(fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<HealthWidgetStyle>(
                            tooltip: 'Darstellung',
                            initialValue: entry.style,
                            onSelected: (style) => _change(ref, (dashboard) => dashboard.setStyle(entry.kind, style)),
                            itemBuilder: (_) => [
                              for (final style in HealthWidgetStyle.values)
                                PopupMenuItem(value: style, child: Text(style.label)),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(entry.style.label, style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Entfernen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _change(ref, (dashboard) => dashboard.remove(entry.kind)),
                          ),
                          ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          for (final category in HealthCategory.values)
            if (addable.where((kind) => kind.category == category).toList() case final kinds when kinds.isNotEmpty)
              FormSection(
                header: 'Hinzufügen · ${category.label}',
                children: [
                  for (final kind in kinds)
                    ListTile(
                      enabled: available.contains(kind),
                      leading: Icon(kind.icon, color: kind.color),
                      title: Text(kind.title),
                      trailing: available.contains(kind)
                          ? const Icon(Icons.add_circle, color: Colors.green)
                          : Text('keine Daten', style: TextStyle(fontSize: 12, color: secondary)),
                      onTap: () => _change(ref, (dashboard) => dashboard.add(kind)),
                    ),
                ],
              ),
          FormSection(
            children: [
              ListTile(
                title: const Text('Standard wiederherstellen'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () => ref.read(coachSettingsProvider).healthDashboard = HealthDashboard(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

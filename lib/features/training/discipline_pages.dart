import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/providers.dart';
import '../../ui/chart_axes.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/tokens.dart';
import '../evidence/evidence_views.dart';
import 'training_controller.dart';
import 'training_pages.dart';

part 'discipline_screens.dart';

String _day(CalendarDay day) => DateFormat('EEE, d. MMM', 'de_DE').format(day.referenceDate);

String _short(CalendarDay day) => '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.';

// Bausteine

/// Tabelle aus Tempo- oder Zonenzeilen.
class PaceTableSection extends StatelessWidget {
  const PaceTableSection({super.key, required this.title, required this.rows, this.footer});

  final String title;
  final List<PaceRow> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) => FormSection(
    header: title,
    footer: footer,
    children: [
      for (final row in rows)
        ListTile(
          dense: true,
          title: Text(row.label, style: TextStyle(fontWeight: row.isKey ? FontWeight.w600 : null)),
          subtitle: Text(row.use),
          trailing: Text(
            row.value,
            style: AppText.callout(context).copyWith(fontWeight: row.isKey ? FontWeight.bold : null),
          ),
        ),
    ],
  );
}

/// Verlauf eingetragener Testwerte.
class TestTrendSection extends ConsumerWidget {
  const TestTrendSection({
    super.key,
    required this.title,
    required this.kind,
    required this.format,
    this.lowerIsBetter = false,
  });

  final String title;
  final TestKind kind;
  final String Function(double value) format;

  /// Kleiner ist besser (Paces): Achse umdrehen, damit „besser“ oben liegt.
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = TestHistory.values(kind, ref.watch(coachSettingsProvider).tests);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    double y(double value) => lowerIsBetter ? -value : value;
    return FormSection(
      header: title,
      children: [
        if (values.isEmpty)
          ListTile(
            title: Text('Noch kein Test eingetragen.', style: TextStyle(color: secondary)),
          )
        else ...[
          ListTile(
            title: Text('Zuletzt ${_day(values.last.day)}'),
            trailing: Text(
              format(values.last.value),
              style: AppText.headline(context).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (values.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
              child: SizedBox(
                height: 120,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (final value in values)
                            FlSpot(
                              value.day.referenceDate.millisecondsSinceEpoch / Duration.millisecondsPerDay,
                              y(value.value),
                            ),
                        ],
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 2,
                      ),
                    ],
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      bottomTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 56,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(format(lowerIsBetter ? -value : value), style: AppText.caption(context)),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Eingabe eines Testwerts als Text („8:40“) mit Übernehmen-Knopf. [evaluate]: Werte der Felder → Ergebnistext und
/// Übernahme, oder `null` bei ungültiger Eingabe.
class TestEntrySection extends StatefulWidget {
  const TestEntrySection({
    super.key,
    required this.title,
    required this.fields,
    required this.footer,
    required this.evaluate,
  });

  final String title;
  final List<({String label, String placeholder})> fields;
  final String footer;
  final ({String preview, VoidCallback apply})? Function(List<String> values) evaluate;

  @override
  State<TestEntrySection> createState() => _TestEntrySectionState();
}

class _TestEntrySectionState extends State<TestEntrySection> {
  late final List<TextEditingController> _inputs = [
    for (final _ in widget.fields) TextEditingController()..addListener(_changed),
  ];
  bool _applied = false;

  void _changed() => setState(() {
    if (_inputs.any((input) => input.text.isNotEmpty)) _applied = false;
  });

  @override
  void dispose() {
    for (final input in _inputs) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.evaluate([for (final input in _inputs) input.text]);
    return FormSection(
      header: widget.title,
      footer: widget.footer,
      children: [
        for (final (index, field) in widget.fields.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _inputs[index],
              keyboardType: TextInputType.text,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:,.]'))],
              decoration: InputDecoration(labelText: field.label, hintText: field.placeholder),
            ),
          ),
        if (result != null) LabeledRow(label: 'Ergebnis', value: result.preview),
        ListTile(
          leading: Icon(_applied ? Icons.check : Icons.save_alt),
          title: Text(_applied ? 'Übernommen' : 'Übernehmen'),
          enabled: result != null,
          onTap: () {
            result?.apply();
            for (final input in _inputs) {
              input.clear();
            }
            setState(() => _applied = true);
          },
        ),
      ],
    );
  }
}

/// Kilometer pro Woche einer Sportart (12 Wochen).
class KilometersSection extends StatelessWidget {
  const KilometersSection({super.key, required this.controller, required this.sport, required this.color});

  final TrainingController controller;
  final ActivitySport sport;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final weeks = controller.weeks;
    final thisWeek = weeks.lastOrNull?.volume.kilometers[sport] ?? 0;
    final previous = [
      for (final week
          in weeks.length > 1 ? weeks.sublist(math.max(0, weeks.length - 5), weeks.length - 1) : const <WeekVolume>[])
        week.volume.kilometers[sport] ?? 0,
    ];
    final average = previous.isEmpty ? 0.0 : previous.reduce((a, b) => a + b) / previous.length;
    final secondary = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'Kilometer pro Woche',
      children: [
        ListTile(
          title: const Text('Diese Woche'),
          trailing: Text(
            formatNumber(thisWeek, unit: 'km', digits: sport == ActivitySport.bike ? 0 : 1),
            style: AppText.headline(context).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
          child: SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                barGroups: [
                  for (final (index, week) in weeks.indexed)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: week.volume.kilometers[sport] ?? 0,
                          width: 14,
                          color: index == weeks.length - 1 ? color : color.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: valueAxis(reservedSize: 32),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 3,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(_short(weeks[value.toInt()].monday), style: AppText.caption(context)),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Ø der 4 Wochen davor: ${formatNumber(average, unit: 'km', digits: 1)} · '
            '${weeks.lastOrNull?.volume.sessions[sport] ?? 0} Einheiten diese Woche',
            style: secondary,
          ),
        ),
      ],
    );
  }
}

/// VO2max-Verlauf der Uhr.
class VO2Section extends StatelessWidget {
  const VO2Section({super.key, required this.title, required this.trend});

  final String title;
  final MetricTrend? trend;

  @override
  Widget build(BuildContext context) {
    final trend = this.trend;
    if (trend == null || trend.points.isEmpty) return const SizedBox.shrink();
    final values = [for (final point in trend.points) point.value];
    return FormSection(
      header: title,
      children: [
        LabeledRow(
          label: 'Aktuell',
          value: formatNumber(trend.latest?.value, unit: 'ml/kg/min', digits: 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
          child: SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minY: values.reduce(math.min) - 1,
                maxY: values.reduce(math.max) + 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (final point in trend.points)
                        FlSpot(
                          point.day.referenceDate.millisecondsSinceEpoch / Duration.millisecondsPerDay,
                          point.value,
                        ),
                    ],
                    color: Theme.of(context).colorScheme.primary,
                    barWidth: 2,
                  ),
                ],
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(),
                  rightTitles: AxisTitles(),
                  bottomTitles: AxisTitles(),
                  leftTitles: valueAxis(reservedSize: 32),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Color _decouplingColor(double percent) => percent < AerobicDecoupling.goodBelowPercent
    ? AppPalette.green
    : (percent < 10 ? AppPalette.orange : AppPalette.red);

String _decouplingLabel(double percent) =>
    percent < AerobicDecoupling.goodBelowPercent ? 'stabil' : (percent < 10 ? 'erhöhte Drift' : 'starke Drift');

/// Aerobe Kopplung (HF-Pace- bzw. HF-Watt-Drift) gleichmäßiger Einheiten aus den FIT-Dateien.
class DecouplingSection extends StatelessWidget {
  const DecouplingSection({
    super.key,
    required this.title,
    required this.sport,
    required this.controller,
    this.showsSkipped = false,
  });

  final String title;
  final DecouplingSport sport;
  final TrainingController controller;
  final bool showsSkipped;

  @override
  Widget build(BuildContext context) {
    final sessions = controller.decoupled(sport);
    final average = ActivityAnalysisPlanner.recentAverage(sessions);
    final secondary = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final recent = sessions.length > 12 ? sessions.sublist(sessions.length - 12) : sessions;
    final skipped = showsSkipped ? controller.skippedDecoupling : const <ActivityAnalysis>[];
    return FormSection(
      header: title,
      footer:
          'Steigt die Herzfrequenz in der zweiten Hälfte bei gleichem Tempo bzw. gleicher Leistung, ist die Kopplung '
          'positiv. Unter 5 % gilt als stabile Grundlage für diese Dauer. Die ersten 10 Minuten zählen nicht.',
      children: [
        if (sessions.isEmpty)
          ListTile(
            title: Text(
              sport == DecouplingSport.run
                  ? 'Noch keine gewertete Einheit. Gewertet werden gleichmäßige Läufe ab 35 min mit höchstens 10 % der '
                        'Zeit in Zone 4–5.'
                  : 'Noch keine gewertete Fahrt. Gewertet werden Fahrten ab 45 min mit Leistungsmessung und höchstens '
                        '10 % der Zeit in Zone 4–5.',
              style: AppText.footnote(context).copyWith(color: secondary.color),
            ),
          )
        else ...[
          if (average != null)
            ListTile(
              title: Text('Ø letzte ${math.min(sessions.length, 5)} Einheiten', style: secondary),
              subtitle: Text(
                '${GermanFormat.decimal(average)} %',
                style: AppText.title(context).copyWith(fontWeight: FontWeight.w600, color: _decouplingColor(average)),
              ),
              trailing: Text(_decouplingLabel(average)),
            ),
          Semantics(
            label: 'Kopplung der letzten Einheiten',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: SizedBox(
                height: 140,
                child: BarChart(
                  BarChartData(
                    barGroups: [
                      for (final (index, analysis) in recent.indexed)
                        BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: analysis.decoupling?.percent ?? 0,
                              width: 12,
                              color: _decouplingColor(analysis.decoupling?.percent ?? 0),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                    ],
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: AerobicDecoupling.goodBelowPercent,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          strokeWidth: 1,
                          dashArray: const [4, 3],
                        ),
                      ],
                    ),
                    titlesData: FlTitlesData(
                      topTitles: AxisTitles(),
                      rightTitles: AxisTitles(),
                      bottomTitles: AxisTitles(),
                      leftTitles: valueAxis(reservedSize: 32),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),
          ),
          for (final analysis in sessions.reversed.take(6)) _DecouplingRow(analysis: analysis),
        ],
        if (skipped.isNotEmpty)
          ExpansionTile(
            title: Text('Nicht gewertet (${skipped.length})'),
            children: [
              for (final analysis in skipped.reversed)
                ListTile(
                  dense: true,
                  title: Text(analysis.name ?? 'Aktivität'),
                  subtitle: Text('${GermanFormat.date(analysis.day)} · ${analysis.skipReason ?? ''}'),
                ),
            ],
          ),
        const EvidenceDisclosure(ruleIDs: ['run.decoupling']),
      ],
    );
  }
}

class _DecouplingRow extends StatelessWidget {
  const _DecouplingRow({required this.analysis});

  final ActivityAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final result = analysis.decoupling;
    final detail = result == null
        ? GermanFormat.date(analysis.day)
        : [
            GermanFormat.date(analysis.day),
            'HF ${result.firstHalfHeartRate.round()} → ${result.secondHalfHeartRate.round()}',
            if (result.firstHalfPace != null && result.secondHalfPace != null)
              '${PlanTokens.mmss(result.firstHalfPace!)} → ${PlanTokens.mmss(result.secondHalfPace!)} /km',
            if (result.firstHalfPower != null && result.secondHalfPower != null)
              '${result.firstHalfPower} → ${result.secondHalfPower} W',
          ].join(' · ');
    return ListTile(
      dense: true,
      title: Text(analysis.name ?? 'Einheit', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail),
      trailing: result == null
          ? null
          : Text(
              '${GermanFormat.decimal(result.percent)} %',
              style: TextStyle(fontWeight: FontWeight.w600, color: _decouplingColor(result.percent)),
            ),
    );
  }
}

/// Pace-Check: Passt die eingestellte Schwellenpace zu den letzten harten Läufen?
class PaceCheckSection extends ConsumerWidget {
  const PaceCheckSection({super.key, required this.controller});

  final TrainingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final result = controller.paceCheck(thresholdPace: settings.season.thresholdPaceSecondsPerKm);
    final (headline, icon, color) = switch (result.status) {
      PaceStatus.fits => ('Schwellenpace passt', Icons.verified, AppColors.of(context).good),
      PaceStatus.faster => ('Schwelle eher schneller', Icons.fast_forward, AppColors.of(context).info),
      PaceStatus.slower => ('Schwelle eher langsamer', Icons.slow_motion_video, AppColors.of(context).caution),
      PaceStatus.tooFewData => (
        'Noch zu wenig harte Läufe',
        Icons.hourglass_empty,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    final suggestion = PaceCheck.suggestionText(result);
    final suggested = result.suggested;
    return FormSection(
      header: 'Pace-Check',
      footer:
          'Ausgewertet werden Schwellen- und 4×4-Läufe der letzten 6 Wochen. Ein Vorschlag kommt erst, wenn mindestens '
          'zwei Einheiten in dieselbe Richtung zeigen, und ändert höchstens 10 s/km. Der 30-min-Test bleibt maßgeblich.',
      children: [
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(headline, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Schwelle ${PlanTokens.mmss(result.current)} /km · Intervalle ${result.intervalBand} /km'),
        ),
        if (suggestion != null && suggested != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(suggestion.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  suggestion.text,
                  style: AppText.footnote(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                FilledButton.icon(
                  onPressed: () {
                    settings.season = settings.season..thresholdPaceSecondsPerKm = suggested;
                    HapticFeedback.mediumImpact();
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('${PlanTokens.mmss(suggested)} /km übernehmen'),
                ),
              ],
            ),
          ),
        if (result.rows.isNotEmpty)
          ExpansionTile(
            title: Text('Ausgewertete Läufe (${result.rows.length})'),
            children: [for (final row in result.rows.reversed) _PaceCheckRowView(row: row)],
          ),
        const EvidenceDisclosure(ruleIDs: ['run.pace-check', 'run.4x4']),
      ],
    );
  }
}

class _PaceCheckRowView extends StatelessWidget {
  const _PaceCheckRowView({required this.row});

  final PaceCheckRow row;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (row.workMinutes case final minutes?) 'Arbeit $minutes min',
      if (row.workPace case final pace?) '${PlanTokens.mmss(pace)} /km',
      if (row.workHeartRate case final heart?) '$heart bpm',
      if (row.heartRatePercentOfThreshold case final percent?) '$percent % Schwellen-HF',
      if (row.estimatedThreshold case final estimate?) 'geschätzt ${PlanTokens.mmss(estimate)} /km',
      if (row.repetitionPeakPercentOfMax case final peak?) 'Spitze $peak % HFmax',
    ].join(' · ');
    return ListTile(
      dense: true,
      title: Text(row.name ?? (row.kind == PaceKind.vo2 ? '4×4' : 'Schwellenlauf')),
      subtitle: Text(details.isEmpty ? row.verdict : '${row.verdict}\n$details'),
      trailing: Text(GermanFormat.date(row.day), style: AppText.caption(context)),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(text),
  );
}

// Seiten

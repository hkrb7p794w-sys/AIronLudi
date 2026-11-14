import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../evidence/evidence_views.dart';
import 'training_controller.dart';
import 'training_pages.dart';

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
          trailing: Text(row.value, style: TextStyle(fontSize: 15, fontWeight: row.isKey ? FontWeight.bold : null)),
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                            child: Text(format(lowerIsBetter ? -value : value), style: const TextStyle(fontSize: 10)),
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
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'Kilometer pro Woche',
      children: [
        ListTile(
          title: const Text('Diese Woche'),
          trailing: Text(
            formatNumber(thisWeek, unit: 'km', digits: sport == ActivitySport.bike ? 0 : 1),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 3,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(_short(weeks[value.toInt()].monday), style: const TextStyle(fontSize: 10)),
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
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(),
                  rightTitles: AxisTitles(),
                  bottomTitles: AxisTitles(),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
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

Color _decouplingColor(double percent) =>
    percent < AerobicDecoupling.goodBelowPercent ? Colors.green : (percent < 10 ? Colors.orange : Colors.red);

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
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
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
              style: secondary.copyWith(fontSize: 13),
            ),
          )
        else ...[
          if (average != null)
            ListTile(
              title: Text('Ø letzte ${math.min(sessions.length, 5)} Einheiten', style: secondary),
              subtitle: Text(
                '${GermanFormat.decimal(average)} %',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _decouplingColor(average)),
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
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(),
                      rightTitles: AxisTitles(),
                      bottomTitles: AxisTitles(),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
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
      PaceStatus.fits => ('Schwellenpace passt', Icons.verified, Colors.green),
      PaceStatus.faster => ('Schwelle eher schneller', Icons.fast_forward, Colors.blue),
      PaceStatus.slower => ('Schwelle eher langsamer', Icons.slow_motion_video, Colors.orange),
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
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      trailing: Text(GermanFormat.date(row.day), style: const TextStyle(fontSize: 12)),
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

/// Schwimmen: Kilometer, CSS-Verlauf, Paces, Technik, CSS-Test (Port von `SwimPage`).
class SwimScreen extends ConsumerWidget {
  const SwimScreen({super.key, required this.controller});

  final TrainingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Schwimmen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          KilometersSection(controller: controller, sport: ActivitySport.swim, color: Colors.blue),
          TestTrendSection(
            title: 'CSS · Schwellentempo /100 m',
            kind: TestKind.css,
            format: (value) => PlanTokens.mmss(value.toInt()),
            lowerIsBetter: true,
          ),
          PaceTableSection(title: 'Paces aus der CSS', rows: SwimPaces.rows(settings.season.cssSecondsPer100m)),
          const FormSection(
            header: 'Technik-Fokus bei 2:00–2:15 /100 m',
            children: [
              ListTile(
                leading: Icon(Icons.air),
                title: Text('Ausatmen unter Wasser – ruhig und kontinuierlich, dann reicht das kurze Einatmen.'),
              ),
              ListTile(
                leading: Icon(Icons.back_hand_outlined),
                title: Text(
                  'Hoher Ellbogen beim Fassen – Unterarm früh senkrecht stellen, nicht mit gestrecktem Arm drücken.',
                ),
              ),
              ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('Ruhiger Kopf, Blick nach unten – hebt die Beine. Ab Frühjahr: Sighting alle 6–8 Züge.'),
              ),
            ],
          ),
          TestEntrySection(
            title: 'CSS-Test eintragen',
            fields: const [
              (label: '400 m maximal', placeholder: 'z. B. 8:40'),
              (label: '200 m maximal', placeholder: 'z. B. 4:20'),
            ],
            footer:
                'Einschwimmen 400 m, 400 m maximal, 5–10 min locker, 200 m maximal. CSS = (Zeit 400 − Zeit 200) ÷ 2.',
            evaluate: (values) {
              final (t400, t200) = (TimeText.seconds(values[0]), TimeText.seconds(values[1]));
              if (t400 == null || t200 == null) return null;
              final css = SwimPaces.css(time400: t400, time200: t200);
              if (css == null) return null;
              return (
                preview: 'CSS ${PlanTokens.mmss(css)} /100 m',
                apply: () => settings.record(TestKind.css, css.toDouble()),
              );
            },
          ),
          const FormSection(
            children: [
              EvidenceDisclosure(ruleIDs: ['swim.css', 'intensity.distribution']),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rad: Kilometer, FTP-Verlauf, VO2max, Zonen, Kopplung, Zwift-Workouts, FTP und Rad-Schnitt (Port von `BikePage`).
class BikeScreen extends ConsumerWidget {
  const BikeScreen({super.key, required this.controller});

  final TrainingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final season = settings.season;
    final schedule = ref.watch(seasonScheduleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rad')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          KilometersSection(controller: controller, sport: ActivitySport.bike, color: Colors.orange),
          TestTrendSection(title: 'FTP · Zwift-Test', kind: TestKind.ftp, format: (value) => '${value.toInt()} W'),
          VO2Section(title: 'VO2max Rad (Garmin)', trend: controller.vo2Bike),
          PaceTableSection(
            title: 'Zonen aus FTP ${season.ftpWatts} W',
            rows: BikeZones.rows(season.ftpWatts),
            footer: 'FTP nur als Referenz für Watt-Angaben – keine Umrechnung in km/h.',
          ),
          DecouplingSection(title: 'Aerobe Kopplung (Pw:HR)', sport: DecouplingSport.ride, controller: controller),
          if (schedule != null)
            FormSection(
              children: [
                ExpansionTile(
                  title: Text('Zwift-Workouts (${schedule.zw.length})'),
                  children: [
                    for (final workout in schedule.zw)
                      ListTile(
                        dense: true,
                        title: Text('${workout.c} · ${workout.n}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(PlanTokens(season).fill(workout.t)),
                      ),
                  ],
                ),
              ],
            ),
          TestEntrySection(
            title: 'FTP eintragen',
            fields: const [(label: 'FTP in Watt', placeholder: 'z. B. 185')],
            footer: 'Zwift ›FTP Ramp Test Lite‹ – gleicher Test wie bisher, damit die Werte vergleichbar bleiben.',
            evaluate: (values) {
              final watts = int.tryParse(values.first);
              if (watts == null || watts < 80 || watts > 500) return null;
              return (preview: '$watts W', apply: () => settings.record(TestKind.ftp, watts.toDouble()));
            },
          ),
          TestEntrySection(
            title: 'Rad-Schnitt für Almere',
            fields: [(label: 'km/h auf 94 km', placeholder: GermanFormat.decimal(season.raceBikeSpeedKmh))],
            footer: 'Benchmark aus einer langen Ausfahrt im Renntempo; fließt in die Zielzeit ein.',
            evaluate: (values) {
              final speed = double.tryParse(values.first.replaceAll(',', '.'));
              if (speed == null || speed < 15 || speed > 50) return null;
              return (
                preview: '${GermanFormat.decimal(speed)} km/h',
                apply: () => settings.record(TestKind.bikeSpeed, speed),
              );
            },
          ),
          const FormSection(
            children: [
              EvidenceDisclosure(ruleIDs: ['intensity.distribution']),
            ],
          ),
        ],
      ),
    );
  }
}

/// Laufen: Kilometer, Schwellenpace, VO2max, Prognose der Uhr, Paces, Tests, Pace-Check, Kopplung (Port von
/// `RunPage`).
class RunScreen extends ConsumerWidget {
  const RunScreen({super.key, required this.controller});

  final TrainingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final predictions = ref.read(garminSyncServiceProvider).racePredictions;
    return Scaffold(
      appBar: AppBar(title: const Text('Laufen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          KilometersSection(controller: controller, sport: ActivitySport.run, color: Colors.green),
          TestTrendSection(
            title: 'Schwellenpace',
            kind: TestKind.threshold,
            format: (value) => '${PlanTokens.mmss(value.toInt())} /km',
            lowerIsBetter: true,
          ),
          VO2Section(title: 'VO2max Laufen (Garmin)', trend: controller.vo2Run),
          if (predictions != null) _RacePredictionSection(predictions: predictions),
          PaceTableSection(
            title: 'Paces',
            rows: RunPaces.rows(settings.season),
            footer: 'Läufe nur als Zone 2, Schwelle oder 4×4 min – keine anderen Intervallformen.',
          ),
          TestEntrySection(
            title: '30-min-Test eintragen',
            fields: const [(label: 'Ø-Pace letzte 20 min', placeholder: 'z. B. 4:50')],
            footer:
                '15 min einlaufen, 30 min so schnell wie gleichmäßig möglich; die Ø-Pace der letzten 20 min ist die neue '
                'Schwelle. Die Ø-Herzfrequenz derselben 20 min ist die Schwellen-HF (unter Herzfrequenz eintragen).',
            evaluate: (values) {
              final pace = TimeText.seconds(values.first);
              if (pace == null || pace < 150 || pace > 480) return null;
              return (
                preview: '${PlanTokens.mmss(pace)} /km',
                apply: () => settings.record(TestKind.threshold, pace.toDouble()),
              );
            },
          ),
          TestEntrySection(
            title: 'Renn-Laufpace (nach dem Rad)',
            fields: const [(label: 'Pace /km', placeholder: 'z. B. 5:42')],
            footer: 'Benchmark aus einem Koppellauf im Renntempo; fließt in die Zielzeit Almere ein.',
            evaluate: (values) {
              final pace = TimeText.seconds(values.first);
              if (pace == null || pace < 150 || pace > 600) return null;
              return (
                preview: '${PlanTokens.mmss(pace)} /km',
                apply: () => settings.record(TestKind.racePace, pace.toDouble()),
              );
            },
          ),
          PaceCheckSection(controller: controller),
          DecouplingSection(
            title: 'Aerobe Kopplung (Pa:HR)',
            sport: DecouplingSport.run,
            controller: controller,
            showsSkipped: true,
          ),
          const FormSection(
            children: [
              EvidenceDisclosure(ruleIDs: ['run.4x4', 'intensity.distribution', 'hr.threshold-zones']),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wettkampfprognosen der Uhr (nur mit dem Garmin-Konto).
class _RacePredictionSection extends StatelessWidget {
  const _RacePredictionSection({required this.predictions});

  final RacePredictions predictions;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (label, seconds, kilometers) in [
        ('5 km', predictions.fiveK, 5.0),
        ('10 km', predictions.tenK, 10.0),
        ('Halbmarathon', predictions.halfMarathon, 21.0975),
        ('Marathon', predictions.marathon, 42.195),
      ])
        if (seconds != null) (label, seconds, (seconds / kilometers).round()),
    ];
    return FormSection(
      header: 'Prognose der Uhr',
      footer: 'Garmins Schätzung aus VO2max und Trainingsverlauf – eine Orientierung, kein Testergebnis.',
      children: [
        for (final (label, seconds, pace) in rows)
          ListTile(
            title: Text(label),
            trailing: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: TimeText.hms(seconds.toInt()),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '   ${PlanTokens.mmss(pace)} /km',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Zielzeit Almere: Schätzung aus den Benchmarks, Abschnitte, Aktualität, Hebel (Port von `AlmerePage`).
class AlmereScreen extends ConsumerWidget {
  const AlmereScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final estimate = RaceEstimate(config: settings.season, tests: settings.tests, today: CalendarDay.today());
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    String minutes(double value) => '${GermanFormat.decimal(value)} min';
    return Scaffold(
      appBar: AppBar(title: const Text('Almere')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(settings.season.mainRaceDescription, style: secondary.copyWith(fontSize: 13)),
                    Text(
                      '${RaceEstimate.hoursMinutes(estimate.totalMinutes)} h',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (estimate.allFresh)
                      Text(estimate.corridorText)
                    else
                      const Text(
                        'Keine Aussage zum Zielkorridor – mindestens ein Wert ist ungetestet oder älter als 8 Wochen.',
                        style: TextStyle(color: Colors.orange),
                      ),
                  ],
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Abschnitte',
            children: [
              for (final leg in estimate.legs)
                ListTile(
                  title: Text(leg.label),
                  subtitle: Text(leg.assumption),
                  trailing: Text(RaceEstimate.hoursMinutes(leg.minutes)),
                ),
            ],
          ),
          FormSection(
            header: 'Aktualität der Benchmarks',
            children: [
              for (final item in estimate.freshness)
                ListTile(
                  title: Text(item.label),
                  trailing: Text(
                    item.age == null
                        ? 'kein Test'
                        : (item.isFresh ? 'vor ${item.age} Tagen ✓' : '${item.age} Tage alt – fällig'),
                    style: TextStyle(color: item.isFresh ? secondary.color : Colors.orange),
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Was bringt eine Verbesserung?',
            footer:
                'Wechselzeiten sind Annahmen. Die Tabelle zeigt nur die Wirkung, nicht den Aufwand. Beim 70.3 ist das '
                'Rad der größte Hebel; mehr Zeit braucht es dafür nicht, nur Umschichten.',
            children: [
              LabeledRow(label: 'Schwimmen 5 s/100 m schneller', value: minutes(estimate.savings.swim)),
              LabeledRow(label: 'Rad 1 km/h schneller', value: minutes(estimate.savings.bike)),
              LabeledRow(label: 'Lauf 10 s/km schneller', value: minutes(estimate.savings.run)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Marathon: Countdown, Zielpace, Halbmarathon-Test, Longrun-Leiter, Rennen & Verpflegung (Port von `MarathonPage`).
class MarathonScreen extends ConsumerWidget {
  const MarathonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final season = settings.season;
    final outlook = MarathonOutlook(
      config: season,
      halfMarathonSeconds: settings.halfMarathonSeconds,
      schedule: ref.watch(seasonScheduleProvider),
      today: CalendarDay.today(),
    );
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final predicted = outlook.predicted;
    String pace(int seconds) => MarathonOutlook.pace(seconds / MarathonOutlook.marathonKilometers);
    return Scaffold(
      appBar: AppBar(title: const Text('Marathon')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(
                      outlook.daysToRace >= 0 ? 'Noch ${outlook.daysToRace} Tage' : 'Marathon geschafft 🏅',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(GermanFormat.date(season.marathonDate), style: secondary),
                    Text(
                      'Zielpace ${PlanTokens.mmss(season.marathonPaceSecondsPerKm)} /km → ca. '
                      '${MarathonOutlook.hoursMinutesFromSeconds(outlook.targetSeconds)} h',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    if (predicted != null) ...[
                      Text(
                        'Halbmarathon-Test → realistisch ${MarathonOutlook.hoursMinutesFromSeconds(predicted.low)}–'
                        '${MarathonOutlook.hoursMinutesFromSeconds(predicted.high)} h (Pace ${pace(predicted.low)}–'
                        '${pace(predicted.high)} /km).',
                      ),
                      if (outlook.targetTooFast)
                        const Text(
                          'Die Zielpace ist schneller als der Test hergibt.',
                          style: TextStyle(color: Colors.orange),
                        ),
                    ] else
                      Text(
                        'Die Zielpace ist vorläufig. Der Halbmarathon-Test bestätigt oder korrigiert sie (Praxiswert: '
                        'Marathon ≈ HM × 2,15–2,2; die Riegel-Formel mit × 2,09 ist für Debütanten meist zu optimistisch).',
                        style: secondary.copyWith(fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
          TestEntrySection(
            title: 'Halbmarathon-Test eintragen',
            fields: const [(label: 'Zeit (h:mm:ss)', placeholder: 'z. B. 1:45:00')],
            footer: 'Geplant am 14.03.2027 im Marathonblock.',
            evaluate: (values) {
              final seconds = TimeText.seconds(values.first);
              if (seconds == null || seconds < 3600 || seconds > 14400) return null;
              return (
                preview: TimeText.hms(seconds),
                apply: () => settings.record(TestKind.halfMarathon, seconds.toDouble()),
              );
            },
          ),
          FormSection(
            header: 'Longrun-Leiter',
            footer:
                'Longrun höchstens 2–3 km pro Woche steigern, jede 4. Woche Entlastung. Spitze 32 km drei Wochen vor dem '
                'Rennen, dann 3 Wochen Taper mit weniger Umfang bei gleichem Tempo.',
            children: [
              for (final week in outlook.ladder)
                ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 64,
                    child: Text(
                      week.isCurrent ? '▶ ${_short(week.sunday)}' : _short(week.sunday),
                      style: TextStyle(color: week.isPast ? secondary.color : null),
                    ),
                  ),
                  title: Text(
                    week.longRun,
                    style: TextStyle(fontWeight: week.longRun.contains('Marathon') ? FontWeight.bold : null),
                  ),
                  trailing: SizedBox(
                    width: 110,
                    child: Text(
                      week.quality,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: secondary.copyWith(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Rennen & Verpflegung',
            children: [
              _InfoTile(
                'Pacing',
                'Erste 5 km 5–10 s/km langsamer als ${PlanTokens.mmss(season.marathonPaceSecondsPerKm)} /km, bis km 30 '
                    'gleichmäßig, erst danach zulegen.',
              ),
              const _InfoTile(
                'Verpflegung',
                '60–90 g Kohlenhydrate pro Stunde aus Gel und Getränk, alle 15–20 min. Jeder Longrun ab 25 km ist '
                    'Generalprobe – am Renntag nichts Neues.',
              ),
              const _InfoTile('Taper', '3 Wochen, Umfang −25 / −40 / −60 %, das Tempo bleibt.'),
              const _InfoTile(
                'Kraft',
                'Beine schwer und kurz (2–3 Sätze à 4–6 Wdh.), mindestens 48 h Abstand zu Longrun und Qualitätslauf.',
              ),
              const _InfoTile(
                'Stoppsignal',
                'Schmerz, der beim Laufen zunimmt oder humpeln lässt → abbrechen, 2–3 Tage Pause.',
              ),
              const EvidenceDisclosure(ruleIDs: ['taper', 'nutrition.carbs', 'strength.economy']),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sportseite für Profile ohne Saisonplan: Umfang pro Woche und Auswertungen aus den Garmin-Daten. Plan-, Test- und
/// Zonenwerte des Saisonplans tauchen hier nicht auf (Port von `PersonalSportPage`).
class PersonalSportScreen extends StatelessWidget {
  const PersonalSportScreen({super.key, required this.sport, required this.controller});

  final TrainingSport sport;
  final TrainingController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(sport.label)),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        KilometersSection(controller: controller, sport: sport.garminSport, color: sport.color),
        if (sport == TrainingSport.run) ...[
          VO2Section(title: 'VO2max Laufen (Garmin)', trend: controller.vo2Run),
          DecouplingSection(
            title: 'Aerobe Kopplung (Pa:HR)',
            sport: DecouplingSport.run,
            controller: controller,
            showsSkipped: true,
          ),
          const FormSection(
            children: [
              EvidenceDisclosure(ruleIDs: ['run.progression', 'run.minimum', 'rhr.endurance']),
            ],
          ),
        ],
        if (sport == TrainingSport.bike) ...[
          VO2Section(title: 'VO2max Rad (Garmin)', trend: controller.vo2Bike),
          DecouplingSection(title: 'Aerobe Kopplung (Pw:HR)', sport: DecouplingSport.ride, controller: controller),
        ],
      ],
    ),
  );
}

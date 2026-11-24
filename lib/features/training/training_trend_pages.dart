part of 'training_pages.dart';

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
                            leftTitles: valueAxis(reservedSize: 40),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: math.max(1, (mondays.length / 4).ceilToDouble()),
                                getTitlesWidget: (value, meta) => SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    DateFormat('d.M.', 'de_DE').format(mondays[value.toInt()].referenceDate),
                                    style: AppText.caption(context),
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
                            Text(sport.label, style: AppText.caption(context)),
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
                    style: AppText.title(context).copyWith(fontWeight: FontWeight.bold),
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
                                color: (point.form >= 0 ? AppColors.of(context).good : AppColors.of(context).caution)
                                    .withValues(alpha: 0.5),
                                barWidth: 2,
                                dotData: const FlDotData(show: false),
                              ),
                            LineChartBarData(
                              spots: [for (final point in recent) FlSpot(_x(point.day), point.fitness)],
                              color: AppColors.of(context).info,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: [for (final point in recent) FlSpot(_x(point.day), point.fatigue)],
                              color: AppPalette.pink,
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
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    spacing: 12,
                    children: [
                      _Legend(color: AppColors.of(context).info, label: 'Fitness'),
                      _Legend(color: AppPalette.pink, label: 'Ermüdung'),
                      _Legend(color: AppColors.of(context).good, label: 'Form'),
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
                  style: AppText.footnote(context).copyWith(color: secondary.color),
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
      Text(label, style: AppText.caption(context)),
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

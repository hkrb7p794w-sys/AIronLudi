part of 'discipline_pages.dart';

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
          KilometersSection(controller: controller, sport: ActivitySport.swim, color: AppColors.of(context).info),
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
          KilometersSection(controller: controller, sport: ActivitySport.bike, color: AppColors.of(context).caution),
          TestTrendSection(title: 'FTP · Zwift-Test', kind: TestKind.ftp, format: (value) => '${value.toInt()} W'),
          VO2Section(title: 'VO2max Rad (Uhr)', trend: controller.vo2Bike),
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
          KilometersSection(controller: controller, sport: ActivitySport.run, color: AppColors.of(context).good),
          TestTrendSection(
            title: 'Schwellenpace',
            kind: TestKind.threshold,
            format: (value) => '${PlanTokens.mmss(value.toInt())} /km',
            lowerIsBetter: true,
          ),
          VO2Section(title: 'VO2max Laufen (Uhr)', trend: controller.vo2Run),
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
      footer: 'Schätzung deiner Uhr aus VO2max und Trainingsverlauf – eine Orientierung, kein Testergebnis.',
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
                    style: AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Zielzeit Almere: Schätzung aus den Benchmarks, Abschnitte, Aktualität, Zeitrechner mit Reglern (Port von
/// `AlmerePage`).
class AlmereScreen extends ConsumerWidget {
  const AlmereScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final estimate = RaceEstimate(config: settings.season, tests: settings.tests, today: CalendarDay.today());
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
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
                    Text(
                      settings.season.mainRaceDescription,
                      style: AppText.footnote(context).copyWith(color: secondary.color),
                    ),
                    Text(
                      '${RaceEstimate.hoursMinutes(estimate.totalMinutes)} h',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (estimate.allFresh)
                      Text(estimate.corridorText)
                    else
                      Text(
                        'Keine Aussage zum Zielkorridor – mindestens ein Wert ist ungetestet oder älter als 8 Wochen.',
                        style: TextStyle(color: AppColors.of(context).caution),
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
                    style: TextStyle(color: item.isFresh ? secondary.color : AppColors.of(context).caution),
                  ),
                ),
            ],
          ),
          // Regler statt fester Tabelle (Wunsch vom 25.11.2026): Zeiten selbst durchrechnen.
          TriathlonCalculatorSection(start: TriathlonTimes.season(settings.season)),
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
                      style: AppText.headline(context),
                    ),
                    if (predicted != null) ...[
                      Text(
                        'Halbmarathon-Test → realistisch ${MarathonOutlook.hoursMinutesFromSeconds(predicted.low)}–'
                        '${MarathonOutlook.hoursMinutesFromSeconds(predicted.high)} h (Pace ${pace(predicted.low)}–'
                        '${pace(predicted.high)} /km).',
                      ),
                      if (outlook.targetTooFast)
                        Text(
                          'Die Zielpace ist schneller als der Test hergibt.',
                          style: TextStyle(color: AppColors.of(context).caution),
                        ),
                    ] else
                      Text(
                        'Die Zielpace ist vorläufig. Der Halbmarathon-Test bestätigt oder korrigiert sie (Praxiswert: '
                        'Marathon ≈ HM × 2,15–2,2; die Riegel-Formel mit × 2,09 ist für Debütanten meist zu optimistisch).',
                        style: AppText.footnote(context).copyWith(color: secondary.color),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Regler zum Durchspielen von Pace und Halbmarathon (Wunsch vom 25.11.2026).
          MarathonCalculatorSection(
            pace: season.marathonPaceSecondsPerKm,
            half:
                settings.halfMarathonSeconds ??
                (outlook.targetSeconds /
                        ((MarathonOutlook.halfMarathonFactorLower + MarathonOutlook.halfMarathonFactorUpper) / 2))
                    .round(),
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
                      style: AppText.caption(context).copyWith(color: secondary.color),
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
                'Lower schwer und kurz (2–3 Sätze à 4–6 Wdh.), mindestens 48 h Abstand zu Longrun und Qualitätslauf.',
              ),
              const _InfoTile(
                'Stoppsignal',
                'Schmerz, der beim Laufen zunimmt oder humpeln lässt → abbrechen, 2–3 Tage Pause.',
              ),
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
          VO2Section(title: 'VO2max Laufen (Uhr)', trend: controller.vo2Run),
          DecouplingSection(
            title: 'Aerobe Kopplung (Pa:HR)',
            sport: DecouplingSport.run,
            controller: controller,
            showsSkipped: true,
          ),
        ],
        if (sport == TrainingSport.bike) ...[
          VO2Section(title: 'VO2max Rad (Uhr)', trend: controller.vo2Bike),
          DecouplingSection(title: 'Aerobe Kopplung (Pw:HR)', sport: DecouplingSport.ride, controller: controller),
        ],
      ],
    ),
  );
}

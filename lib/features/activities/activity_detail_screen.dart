import 'dart:async';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/garmin/garmin_sync_service.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/route_map.dart';
import '../gym/gym_screen.dart';
import 'activity_parts.dart';

/// Alle Details einer Aktivität wie in Garmin Connect: Übersicht, Karte, Verlauf, Runden, Abschnitte und alle
/// Kennzahlen. Fehlendes holt die Seite beim Öffnen von Garmin (Details und FIT-Datei); die Datei bleibt im Cache
/// (Port von `ActivityDetailView`).
class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({super.key, required this.activity});

  final GarminActivity activity;

  @override
  ConsumerState<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  GarminActivity? _detailed;
  FitActivity? _fit;
  ActivityReport? _report;
  bool _loading = false;
  String? _problem;

  GarminActivity get _current => _detailed ?? widget.activity;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final base = widget.activity;
    final sync = ref.read(garminSyncServiceProvider);
    final model = ref.read(appModelProvider);
    setState(() => _loading = true);
    try {
      // Bericht vom letzten Abruf und Datei aus dem Cache sofort anzeigen.
      _report = sync.reportStore.report(base.id);
      if (sync.reportStore.cachedFile(base.id) case final data?) {
        _fit = await _decode(data);
        _storeReport(base);
      }
      if (mounted) setState(() {});
      // Workouts aus Apple Health / Health Connect (negative ID): Verlauf und Strecke vom Gerät.
      if (base.id < 0) {
        if (!model.isDemo) {
          final recording = await ref.read(healthImportServiceProvider).recording(base.id, around: base.day);
          if (recording != null) {
            _fit = recording;
            _storeReport(base);
          }
        }
        return;
      }
      final client = ref.read(garminClientProvider);
      if (!client.isConfigured || model.isDemo) return;
      try {
        final json = await client.json(GarminEndpoint.activity(base.id));
        final detailed = GarminActivityParser.detail(json, base);
        _detailed = detailed;
        await ref.read(activityRepositoryProvider).upsert(detailed);
      } on Object {
        // Details bleiben aus der Liste.
      }
      if (_fit != null) return;
      try {
        final data = await client.data(GarminEndpoint.activityFile(base.id));
        _fit = await _decode(data);
        sync.reportStore.cacheFile(data, id: base.id);
        _storeReport(_detailed ?? base);
      } on Object {
        _problem =
            'Der Verlauf (FIT-Datei) konnte gerade nicht geladen werden. Die Übersicht stammt aus der Aktivitätsliste.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<FitActivity?> _decode(List<int> data) async {
    try {
      return await GarminSyncService.decodeFit(data is Uint8List ? data : Uint8List.fromList(data));
    } on Object {
      return null;
    }
  }

  /// Bericht aus der geladenen Datei erzeugen und speichern (auch für ältere Aktivitäten außerhalb des Abrufs).
  void _storeReport(GarminActivity activity) {
    final fit = _fit;
    if (fit == null || _report?.version == ActivityReport.currentVersion) return;
    final built = ActivityReportBuilder.build(activity, fit);
    _report = built;
    ref.read(garminSyncServiceProvider).reportStore.store(built, today: CalendarDay.today());
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final fit = _fit;
    final report = _report;
    final sport = current.sport;
    final sections = ActivityDetails.sections(current);
    final route = fit == null ? const <({double latitude, double longitude})>[] : ActivityDetails.route(fit);
    return Scaffold(
      appBar: AppBar(title: Text(current.name ?? 'Aktivität')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(activity: current, overview: sections.firstOrNull?.rows ?? const []),
          if (sport == ActivitySport.strength) _LinkedGymSection(activity: current),
          if (report != null) _FindingsSection(report: report),
          if (fit != null) ...[
            if (route.length > 1) FormSection(children: [RouteMap(route: route)]),
            _ChartsSection(
              samples: ActivityDetails.samples(fit, sport),
              sport: sport,
              byDistance: fit.records.any((record) => (record.distance ?? 0) > 0),
            ),
            if (fit.laps.length > 1) _LapsSection(laps: fit.laps, sport: sport),
          ] else if (report != null) ...[
            // Datei der Uhr nicht (mehr) da: Verlauf und Runden aus dem gespeicherten Bericht.
            _ChartsSection(samples: report.samples, sport: sport, byDistance: report.byDistance),
            if (report.laps.length > 1) _LapsSection(laps: report.laps, sport: sport),
          ] else if (_loading)
            const FormSection(
              children: [
                ListTile(
                  leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('Verlauf wird geladen …'),
                ),
              ],
            ),
          if (report != null && report.splits.length > 1) _SplitsSection(report: report, sport: sport),
          for (final section in sections.skip(1))
            FormSection(
              header: section.title,
              children: [for (final row in section.rows) LabeledRow(label: row.label, value: row.value)],
            ),
          MissingDataSection(notes: ActivityFeed.missing(current)),
          if (_problem case final problem?)
            FormSection(
              children: [
                ListTile(
                  title: Text(
                    problem,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.activity, required this.overview});

  final GarminActivity activity;
  final List<DetailRow> overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final effort = ref.watch(coachSettingsProvider).efforts['${activity.id}'];
    final start = activity.startLocal;
    final shares = ActivityFeed.zoneShares(activity);
    return FormSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              if (activity.day case final day?)
                Text(
                  [
                    formatDay(day),
                    if (start != null && start.length >= 16) '${start.substring(11, 16)} Uhr',
                    ?activity.locationName,
                  ].join(' · '),
                  style: TextStyle(color: secondary),
                ),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FeedBadges(sources: [ActivitySource.of(activity.id)], intensity: SessionKind.of(activity)),
                  if (effort != null)
                    Text(
                      'Anstrengung $effort/10',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondary),
                    ),
                ],
              ),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  for (final row in overview)
                    SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(row.value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                          ),
                          Text(row.label, style: TextStyle(fontSize: 12, color: secondary)),
                        ],
                      ),
                    ),
                ],
              ),
              if (shares != null) ZoneShareBar(shares: shares),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aussagen der Regeln zu dieser Einheit (Tempo-Einteilung, Puls-Drift, Intervalle, Standzeit).
class _FindingsSection extends StatelessWidget {
  const _FindingsSection({required this.report});

  final ActivityReport report;

  @override
  Widget build(BuildContext context) {
    final findings = ActivityFindings.findings(report);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Auswertung',
      footer: 'Aus der Aufzeichnung der Uhr berechnet – feste Regeln, keine KI.',
      children: [
        if (findings.isEmpty)
          ListTile(
            title: Text(
              'Für diese Einheit gibt es keine besonderen Auffälligkeiten.',
              style: TextStyle(color: secondary),
            ),
          ),
        for (final finding in findings)
          ListTile(
            leading: switch (finding.tone) {
              FindingTone.good => const Icon(Icons.check_circle, color: Colors.green),
              FindingTone.attention => const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              FindingTone.neutral => Icon(Icons.info_outline, color: secondary),
            },
            title: Text(finding.text),
          ),
      ],
    );
  }
}

String _clock(double seconds) {
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Diagrammreihen aus dem Verlauf; nur Reihen mit mindestens zwei Punkten.
class _ChartsSection extends StatelessWidget {
  const _ChartsSection({required this.samples, required this.sport, required this.byDistance});

  final List<DetailSample> samples;
  final ActivitySport sport;
  final bool byDistance;

  @override
  Widget build(BuildContext context) {
    final paceTitle = switch (sport) {
      ActivitySport.run => 'Pace (min/km)',
      ActivitySport.swim => 'Pace (min/100 m)',
      _ => 'Geschwindigkeit (km/h)',
    };
    List<FlSpot> points(double? Function(DetailSample sample) value) => [
      for (final sample in samples)
        if (value(sample) case final y?) FlSpot(sample.x, y),
    ];
    final paceReversed = sport == ActivitySport.run || sport == ActivitySport.swim;
    final series = [
      ('Herzfrequenz (bpm)', Colors.red, points((sample) => sample.heartRate), false),
      (paceTitle, Colors.blue, points((sample) => sample.pace), paceReversed),
      ('Höhe (m)', Colors.green, points((sample) => sample.altitude), false),
      (
        sport == ActivitySport.bike ? 'Trittfrequenz (U/min)' : 'Kadenz (spm)',
        Colors.purple,
        points((sample) => sample.cadence),
        false,
      ),
      ('Leistung (W)', Colors.orange, points((sample) => sample.power), false),
    ].where((item) => item.$3.length > 1).toList();
    if (series.isEmpty) return const SizedBox.shrink();
    final unit = byDistance ? 'km' : 'min';
    return FormSection(
      header: 'Verlauf',
      children: [
        for (final (title, color, spots, reversed) in series)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  height: 140,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          // Pace: kleiner ist schneller, daher umgekehrte Achse (negierte Werte).
                          spots: reversed ? [for (final spot in spots) FlSpot(spot.x, -spot.y)] : spots,
                          color: color,
                          barWidth: 1.5,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                      lineTouchData: const LineTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                reversed ? _clock(-value) : GermanFormat.decimal(value),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          axisNameWidget: Text(unit, style: const TextStyle(fontSize: 10)),
                          sideTitles: const SideTitles(showTitles: true, reservedSize: 22),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Abschnitte fester Länge (Laufen 1 km, Rad 5 km, Schwimmen 100 m) mit Balken für das Tempo.
class _SplitsSection extends StatelessWidget {
  const _SplitsSection({required this.report, required this.sport});

  final ActivityReport report;
  final ActivitySport sport;

  @override
  Widget build(BuildContext context) {
    final speeds = [for (final split in report.splits) split.speed];
    final fastest = speeds.isEmpty ? 1.0 : speeds.reduce((a, b) => a > b ? a : b);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final tint = Theme.of(context).colorScheme.primary.withValues(alpha: 0.7);
    return FormSection(
      header: report.splitMeters == 1000 ? 'Kilometer' : ActivityFindings.splitTitle(report.splitMeters),
      children: [
        for (final split in report.splits)
          Semantics(
            label:
                'Abschnitt ${split.index}: ${ActivityDetails.speed(split.speed, sport)}'
                '${split.averageHeartRate == null ? '' : ', Puls ${split.averageHeartRate!.round()}'}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                spacing: 8,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${split.index}',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(ActivityDetails.speed(split.speed, sport), style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 8,
                          width: (constraints.maxWidth * (fastest > 0 ? split.speed / fastest : 0)).clamp(
                            4,
                            constraints.maxWidth,
                          ),
                          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      split.averageHeartRate == null ? '' : '${split.averageHeartRate!.round()} ♥',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LapsSection extends StatelessWidget {
  const _LapsSection({required this.laps, required this.sport});

  final List<FitLap> laps;
  final ActivitySport sport;

  static double? lapSpeed(FitLap lap) {
    if (lap.averageSpeed case final speed? when speed > 0) return speed;
    final distance = lap.distanceMeters;
    final seconds = lap.timerSeconds;
    if (distance == null || seconds == null || seconds <= 0) return null;
    return distance / seconds;
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    String whole(double? value, [String suffix = '']) => value == null ? '–' : '${value.toInt()}$suffix';
    final headers = [
      '#',
      'Distanz',
      'Zeit',
      if (sport == ActivitySport.run || sport == ActivitySport.swim) 'Pace' else 'km/h',
      'Ø HF',
      'Max HF',
      'Anstieg',
      'Kadenz',
      'Leistung',
    ];
    return FormSection(
      header: 'Runden',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: DataTable(
            columnSpacing: 14,
            headingRowHeight: 28,
            dataRowMinHeight: 24,
            dataRowMaxHeight: 28,
            headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
            dataTextStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
            columns: [for (final header in headers) DataColumn(label: Text(header), numeric: true)],
            rows: [
              for (final (index, lap) in laps.indexed)
                DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(
                      Text(lap.distanceMeters == null ? '–' : ActivityDetails.distance(lap.distanceMeters!, sport)),
                    ),
                    DataCell(Text(lap.timerSeconds == null ? '–' : ActivityDetails.duration(lap.timerSeconds!))),
                    DataCell(Text(lapSpeed(lap) == null ? '–' : ActivityDetails.speed(lapSpeed(lap)!, sport))),
                    DataCell(Text(whole(lap.averageHeartRate))),
                    DataCell(Text(whole(lap.maxHeartRate))),
                    DataCell(Text(whole(lap.ascentMeters, ' m'))),
                    DataCell(
                      Text(
                        whole(
                          lap.averageCadence == null
                              ? null
                              : (sport == ActivitySport.run ? lap.averageCadence! * 2 : lap.averageCadence!),
                        ),
                      ),
                    ),
                    DataCell(Text(whole(lap.averagePower, ' W'))),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Krafttraining der Uhr plus Einheit der App: dieselbe Einheit, also beides an einem Ort. Zuordnung über die
/// gespeicherte Verbindung, sonst über die Startzeit.
class _LinkedGymSection extends ConsumerStatefulWidget {
  const _LinkedGymSection({required this.activity});

  final GarminActivity activity;

  @override
  ConsumerState<_LinkedGymSection> createState() => _LinkedGymSectionState();
}

class _LinkedGymSectionState extends ConsumerState<_LinkedGymSection> {
  StoredGymSession? _record;

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  Future<void> _find() async {
    final records = (await ref.read(gymRepositoryProvider).all()).take(60).toList();
    final activity = widget.activity;
    final linked = records.where((record) => record.session.garmin?.activityID == activity.id).firstOrNull;
    final start = activityStart(activity);
    final byTime = start == null
        ? null
        : records.where((record) {
            final session = record.session;
            return session.garmin?.activityID == null &&
                session.start.difference(start).abs() <= GarminStrengthSync.matchWindow &&
                session.day == activity.day;
          }).firstOrNull;
    if (mounted) setState(() => _record = linked ?? byTime);
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record == null) return const SizedBox.shrink();
    final session = record.session;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Sätze aus der App · ${session.title}',
      footer: session.garmin?.status == GarminLinkStatus.enriched
          ? 'Die Sätze stehen auch in Garmin Connect in dieser Aktivität.'
          : 'Dieselbe Einheit – Kalorien und Puls kommen von der Uhr, die Sätze aus der App. Es zählt nur einmal.',
      children: [
        for (final exercise in session.exercises)
          if (exercise.loggedSets.isNotEmpty)
            ListTile(
              dense: true,
              title: Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                [
                  for (final set in exercise.loggedSets)
                    set.weightKg > 0 ? '${GermanFormat.number(set.weightKg)}×${set.reps}' : '${set.reps}',
                ].join(' · '),
                style: TextStyle(color: secondary),
              ),
            ),
        ListTile(
          title: const Text('Einheit in der App öffnen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(record: record))),
        ),
      ],
    );
  }
}

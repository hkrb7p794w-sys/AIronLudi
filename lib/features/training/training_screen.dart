import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/large_title.dart';
import '../../ui/sport_style.dart';
import '../../ui/strain_card.dart';
import '../../ui/week_minutes_chart.dart';
import '../endurance/endurance_controller.dart';
import '../endurance/endurance_screens.dart';
import '../gym/gym_providers.dart';
import '../gym/gym_screen.dart';
import '../health/health_screen.dart';
import '../plan/my_week_screen.dart';
import '../plan/plan_screen.dart';
import 'discipline_pages.dart';
import 'sleep_coach_screen.dart';
import 'training_controller.dart';
import 'training_pages.dart';

/// Übersicht der Leistungsbereiche: Gym, Erholung, Herzfrequenz, Trends, Schlaf-Coach, Fitness & Form und
/// Wochenbericht – jeweils eine eigene Seite (Port von `TrainingView.swift`).
class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key});

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  final _controller = TrainingController();
  List<DailyMetrics> _days = const [];
  List<GarminActivity> _activities = const [];
  List<StoredGymSession> _gym = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final today = CalendarDay.today();
    final sync = ref.read(garminSyncServiceProvider);
    final results = await (
      ref.read(metricsRepositoryProvider).range(from: today.adding(-400), to: today),
      ref.read(activityRepositoryProvider).all(),
      ref.read(gymRepositoryProvider).all(),
      sync.raw(GarminEndpoint.heartRateZones),
    ).wait;
    if (!mounted) return;
    _days = results.$1;
    _activities = results.$2;
    _gym = results.$3;
    _controller.update(
      days: _days,
      activities: _activities,
      profile: sync.profile,
      watchZones: results.$4,
      overrides: ref.read(coachSettingsProvider).heartRate,
      analyses: sync.analysisStore.load().values.toList(),
    );
  }

  /// „Meine Belastung heute“ wie unter „Heute“ (Ampel aus den Tageswerten und der Form).
  DailyStrain _strain(CalendarDay today, {required List<FormPoint> formPoints}) {
    final settings = ref.read(coachSettingsProvider);
    final endurance = ref.read(enduranceControllerProvider).plan;
    final days = [..._days]..sort((a, b) => b.day.compareTo(a.day));
    final state = RecoveryEvaluator.today(days: days, form: formPoints, today: today);
    final strengthRecorded = _activities.any(
      (activity) => activity.day == today && activity.sport == ActivitySport.strength,
    );
    final gymMinutes = strengthRecorded
        ? 0.0
        : _gym
              .where((record) => record.session.day == today && record.session.end != null)
              .fold<double>(0, (sum, record) => sum + record.session.end!.difference(record.session.start).inMinutes);
    return DailyStrainRules.compute(
      activities: _activities,
      plannedToday: settings.profile.mode == ProfileMode.personal
          ? settings.schedule(today).slots(Weekday.values[today.weekdayIndex])
          : const [],
      enduranceToday: endurance?.slotsOn(today) ?? const [],
      recovery: state.isKnown ? state.recommendation : null,
      today: today,
      gymMinutesToday: gymMinutes,
      thresholds: endurance?.request.thresholds ?? const AthleteThresholds(),
    );
  }

  void _open(Widget Function(BuildContext context) builder) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));

  @override
  Widget build(BuildContext context) {
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final running = ref.watch(gymControllerProvider).active?.title;
    final endurancePlan = ref.watch(enduranceControllerProvider).plan;
    final enduranceSummary = switch (endurancePlan?.slotsOn(CalendarDay.today()).firstOrNull) {
      final slot? => slot.current.isRest ? 'Ruhetag' : slot.current.type.label,
      null => endurancePlan == null ? null : 'heute frei',
    };
    final today = CalendarDay.today();
    final controller = _controller;
    final gym = [for (final record in _gym) GymItem.fromSession(record.session)];
    final weekMinutes = TrainingTrends.weeklyMinutes(
      activities: _activities,
      gym: gym,
      today: today,
      weeks: 1,
    ).fold<int>(0, (sum, entry) => sum + entry.minutes);
    final sleep = SleepCoach.report(days: _days, settings: settings.sleep, goal: settings.profile.goal, today: today);
    final form = FitnessForm.seriesUntil(_activities, today: today);
    final formPercent = form.lastOrNull?.formPercent;
    final report = WeeklyReport.lastWeek(
      activities: _activities,
      days: _days,
      gymDays: [for (final record in _gym) record.session.day],
      today: today,
    );
    final recovery = controller.recovery.firstOrNull;
    final season = settings.season;
    final estimate = RaceEstimate(config: season, tests: settings.tests, today: today);
    return Scaffold(
      appBar: AppBar(title: const CollapsingTitle(child: Text('Training'))),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(appModelProvider).syncNow();
          await _reload();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const LargeTitleHeader('Training'),
            DailyStrainCard(strain: _strain(today, formPoints: form)),
            WeekMinutesChart(
              minutes: TrainingTrends.weeklyMinutes(activities: _activities, gym: gym, today: today, weeks: 8),
              today: today,
              onTap: () => _open((_) => TrendsScreen(activities: _activities, gym: gym)),
            ),
            _HubGrid(
              children: [
                _HubRow(
                  title: 'Plan',
                  symbol: 'calendar',
                  color: Colors.orange,
                  value: '',
                  caption: settings.profile.mode == ProfileMode.season ? 'Saisonplan und Woche' : 'Deine Woche',
                  onTap: () => _open(
                    (_) => settings.profile.mode == ProfileMode.season ? const PlanScreen() : const MyWeekScreen(),
                  ),
                ),
                _HubRow(
                  title: 'Ausdauerplan',
                  symbol: 'figure.run',
                  color: Colors.deepOrange,
                  value: enduranceSummary ?? 'Erstellen',
                  caption: 'Laufen, Rad/Zwift, Schwimmen – passt sich an',
                  onTap: () => _open((_) => const EnduranceScreen()),
                ),
                // Früher eigener Reiter; „Training starten“ (App-Icon, Kurzbefehl, Widget) öffnet diesen Bereich direkt.
                if (settings.profile.trains(TrainingSport.strength))
                  _HubRow(
                    title: 'Gym',
                    symbol: 'dumbbell.fill',
                    color: Colors.green,
                    value: running == null ? 'Einheit starten' : 'läuft',
                    valueColor: running == null ? null : Colors.green,
                    caption: running ?? 'Pläne, Übungen, Auswertung',
                    onTap: () => _open((_) => const GymScreen()),
                  ),
                _HubRow(
                  title: 'Gesundheit',
                  symbol: 'heart.text.square.fill',
                  color: Colors.pink,
                  value: switch (BodyBatteryAnalysis.summary(days: _days, today: today).current) {
                    final current? => 'BB ${current.toInt()}',
                    null => '',
                  },
                  caption: 'Morning Report, Widgets, Body Battery',
                  onTap: () => _open((_) => const HealthScreen()),
                ),
                _HubRow(
                  title: 'Erholung',
                  symbol: 'bed.double.fill',
                  color: Colors.indigo,
                  value: recovery == null
                      ? '–'
                      : formatNumber(recovery.trend.latest?.value, unit: recovery.unit, digits: recovery.digits),
                  caption: 'HRV, Ruhepuls, Schlaf',
                  onTap: () => _open((_) => RecoveryScreen(controller: controller)),
                ),
                _HubRow(
                  title: 'Herzfrequenz',
                  symbol: 'heart.fill',
                  color: Colors.red,
                  value: controller.zones?.run.lactateThreshold == null
                      ? '–'
                      : '${controller.zones!.run.lactateThreshold} bpm',
                  caption: 'Schwelle Laufen',
                  onTap: () => _open((_) => HeartRateScreen(report: controller.zones)),
                ),
                _HubRow(
                  title: 'Trends',
                  symbol: 'chart.bar.xaxis',
                  color: Colors.purple,
                  value: '$weekMinutes min',
                  caption: 'diese Woche',
                  onTap: () => _open((_) => TrendsScreen(activities: _activities, gym: gym)),
                ),
                _HubRow(
                  title: 'Schlaf-Coach',
                  symbol: 'moon.stars.fill',
                  color: Colors.indigo,
                  value: sleep == null ? '–' : '${SleepCoach.clock(sleep.bedtimeMinutes)} Uhr',
                  caption: 'Schlafenszeit heute',
                  onTap: () => _open((_) => const SleepCoachScreen()),
                ),
                _HubRow(
                  title: 'Fitness & Form',
                  symbol: 'chart.line.uptrend.xyaxis',
                  color: Colors.blue,
                  value: formPercent == null ? '–' : FormZone.of(formPercent).label,
                  caption: 'Belastung der Uhr',
                  onTap: () => _open((_) => FitnessFormScreen(points: form)),
                ),
                _HubRow(
                  title: 'Wochenbericht',
                  symbol: 'doc.text.magnifyingglass',
                  color: Colors.teal,
                  value: '${report.week.sessions} Einheiten',
                  caption: 'letzte Woche',
                  onTap: () => _open((_) => WeeklyReportScreen(report: report)),
                ),
              ],
            ),
            if (settings.profile.mode == ProfileMode.season) ...[
              _HubGrid(
                header: 'Disziplinen',
                children: [
                  _HubRow(
                    title: 'Schwimmen',
                    symbol: 'figure.pool.swim',
                    color: Colors.blue,
                    value: '${PlanTokens.mmss(season.cssSecondsPer100m)} /100 m',
                    caption: 'CSS',
                    onTap: () => _open((_) => SwimScreen(controller: controller)),
                  ),
                  _HubRow(
                    title: 'Rad',
                    symbol: 'figure.outdoor.cycle',
                    color: Colors.orange,
                    value: '${season.ftpWatts} W',
                    caption: 'FTP',
                    onTap: () => _open((_) => BikeScreen(controller: controller)),
                  ),
                  _HubRow(
                    title: 'Laufen',
                    symbol: 'figure.run',
                    color: Colors.green,
                    value: '${PlanTokens.mmss(season.thresholdPaceSecondsPerKm)} /km',
                    caption: 'Schwelle',
                    onTap: () => _open((_) => RunScreen(controller: controller)),
                  ),
                ],
              ),
              _HubGrid(
                header: 'Ziele',
                children: [
                  _HubRow(
                    title: 'Almere',
                    symbol: 'flag.checkered',
                    color: Colors.teal,
                    value: '${RaceEstimate.hoursMinutes(estimate.totalMinutes)} h',
                    caption: 'geschätzte Zielzeit',
                    onTap: () => _open((_) => const AlmereScreen()),
                  ),
                  _HubRow(
                    title: 'Marathon',
                    symbol: 'medal.fill',
                    color: Colors.pink,
                    value: '${math.max(today.daysUntil(season.marathonDate), 0)} Tage',
                    caption: GermanFormat.date(season.marathonDate),
                    onTap: () => _open((_) => const MarathonScreen()),
                  ),
                ],
              ),
            ] else
              _HubGrid(
                header: 'Meine Sportarten',
                children: [
                  for (final sport in settings.profile.sports)
                    if (sport == TrainingSport.run || sport == TrainingSport.bike || sport == TrainingSport.swim)
                      _HubRow(
                        title: sport.shortLabel,
                        symbol: switch (sport) {
                          TrainingSport.run => 'figure.run',
                          TrainingSport.bike => 'figure.outdoor.cycle',
                          _ => 'figure.pool.swim',
                        },
                        color: sport.color,
                        value: formatNumber(
                          controller.weeks.lastOrNull?.volume.kilometers[sport.garminSport] ?? 0,
                          unit: 'km',
                          digits: 1,
                        ),
                        caption: 'diese Woche',
                        onTap: () => _open((_) => PersonalSportScreen(sport: sport, controller: controller)),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Kachel der Übersicht: Symbol, Kernwert groß, Bereich klein; Details erst beim Antippen.
class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.title,
    required this.symbol,
    required this.color,
    required this.value,
    required this.caption,
    required this.onTap,
    this.valueColor,
  });

  final String title;
  final String symbol;
  final Color color;
  final String value;
  final Color? valueColor;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: '$title: $value, $caption',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Row(
                children: [
                  SportIcon(symbol: symbol, color: color, size: 26),
                  const Spacer(),
                  const DisclosureChevron(),
                ],
              ),
              // Ohne Kernwert steht der Bereich groß und die Erklärung klein darunter – kein einsamer Strich.
              Text(
                value.isEmpty || value == '–' ? title : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
              ),
              Text(
                value.isEmpty || value == '–' ? caption : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kacheln in zwei Spalten (drei ab Tablet-Breite) statt einer Liste mit Erklärtexten.
class _HubGrid extends StatelessWidget {
  const _HubGrid({this.header, required this.children});

  final String? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header case final header?)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 7),
              child: Text(header.toUpperCase(), style: muted),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 600 ? 3 : 2;
              const gap = 10.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final child in children)
                    SizedBox(
                      width: width,
                      child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: child),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

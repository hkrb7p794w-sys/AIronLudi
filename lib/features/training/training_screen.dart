import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/deep_links.dart';
import '../../app/training_data_reload.dart';
import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/large_title.dart';
import '../../ui/sport_style.dart';
import '../../ui/strain_card.dart';
import '../../ui/tokens.dart';
import '../../ui/week_minutes_chart.dart';
import '../endurance/endurance_controller.dart';
import '../endurance/endurance_screens.dart';
import '../fuel/fuel_planner_screen.dart';
import '../gym/gym_providers.dart';
import '../gym/gym_screen.dart';
import '../health/health_screen.dart';
import '../plan/my_week_screen.dart';
import '../plan/plan_screen.dart';
import '../routes/routes_screen.dart';
import 'discipline_pages.dart';
import 'sleep_coach_screen.dart';
import 'training_controller.dart';
import 'training_pages.dart';

/// Übersicht der Leistungsbereiche: Gym, Erholung, Herzfrequenz, Trends, Schlaf-Coach, Fitness & Form und
/// Wochenbericht – jeweils eine eigene Seite (Port von `TrainingView.swift`).
///
/// Seit Stufe 4 des Roasts (docs/roast/design-konzept.md) in zwei Teilen: [TrainingSection.plan] ist der Reiter
/// „Plan“ (was kommt), [TrainingSection.history] die „Auswertungen“ im Reiter „Verlauf“ (was war).
class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key, this.section = TrainingSection.plan});

  final TrainingSection section;

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

enum TrainingSection {
  plan('Plan'),
  history('Auswertungen');

  const TrainingSection(this.title);

  final String title;
}

class _TrainingScreenState extends ConsumerState<TrainingScreen>
    with TrainingDataReload<TrainingScreen>, PendingRouteHandler<TrainingScreen> {
  bool get _isPlan => widget.section == TrainingSection.plan;

  @override
  Set<AppRoute> get handledRoutes => _isPlan ? const {AppRoute.gym, AppRoute.startWorkout} : const {AppRoute.health};

  @override
  void handlePendingRoute(PendingRoute pending) => switch (pending.route) {
    AppRoute.health => _open((_) => const HealthScreen()),
    AppRoute.startWorkout => _open((_) => const GymScreen(startWorkout: true)),
    _ => _open((_) => const GymScreen()),
  };

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

  /// Neue Aktivität, Tageswerte oder Gym-Einheit in der Datenbank (gleich aus welcher Quelle): Belastung neu rechnen.
  @override
  Future<void> reloadTrainingData() => _reload();

  Future<void> _explore(List<GarminActivity> activities) async {
    try {
      await ref.read(explorationImportProvider).importCached(activities);
    } on Object {
      // Nur eine Ergänzung.
    }
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
    // Vorab geplante Routen mit passender Aktivität ins Archiv.
    unawaited(ref.read(routeStoreProvider).completeFromActivities(_activities));
    // Gebiete (falls eingeschaltet): schon geladene Strecken still übernehmen – ohne die Aktivität zu öffnen.
    unawaited(_explore(_activities));
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
      // Strain wie bei WHOOP: WHOOP-Wert bzw. Puls über den ganzen Tag (heutige Tageswerte).
      todayMetrics: _days.where((metrics) => metrics.day == today).firstOrNull,
      maxHeartRate: HeartRateStrain.maxHeartRate(
        overrides: settings.heartRate,
        activities: _activities,
        today: today,
        age: ref.read(appModelProvider).sync.profile?.ageOn(today),
      ),
    );
  }

  void _open(Widget Function(BuildContext context) builder) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));

  @override
  Widget build(BuildContext context) {
    listenPendingRoutes();
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final running = ref.watch(gymControllerProvider).active?.title;
    final endurancePlan = ref.watch(enduranceControllerProvider).plan;
    final enduranceSummary = switch (endurancePlan?.slotsOn(CalendarDay.today()).firstOrNull) {
      final slot? => slot.current.isRest ? 'Ruhetag' : slot.current.type.label,
      null => endurancePlan == null ? null : 'heute frei',
    };
    final today = CalendarDay.today();
    final routeStore = ref.watch(routeStoreProvider);
    final routeToday = routeStore.plannedOn(today).firstOrNull;
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
      appBar: AppBar(title: CollapsingTitle(child: Text(widget.section.title))),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(appModelProvider).syncNow();
          await _reload();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            LargeTitleHeader(widget.section.title),
            if (_isPlan) DailyStrainCard(strain: _strain(today, formPoints: form)),
            if (!_isPlan)
              WeekMinutesChart(
                minutes: TrainingTrends.weeklyMinutes(activities: _activities, gym: gym, today: today, weeks: 8),
                today: today,
                onTap: () => _open((_) => TrendsScreen(activities: _activities, gym: gym)),
              ),
            _HubGrid(
              children: [
                if (_isPlan)
                  _HubRow(
                    title: 'Woche',
                    symbol: 'calendar',
                    color: AppColors.of(context).caution,
                    value: '',
                    caption: settings.profile.mode == ProfileMode.season ? 'Saisonplan und Woche' : 'Deine Woche',
                    onTap: () => _open(
                      (_) => settings.profile.mode == ProfileMode.season ? const PlanScreen() : const MyWeekScreen(),
                    ),
                  ),
                if (_isPlan)
                  _HubRow(
                    title: 'Ausdauerplan',
                    symbol: 'figure.run',
                    color: Colors.deepOrange,
                    value: enduranceSummary ?? 'Erstellen',
                    caption: 'Laufen, Rad/Zwift, Schwimmen – passt sich an',
                    onTap: () => _open((_) => const EnduranceScreen()),
                  ),
                // Früher eigener Reiter; „Training starten“ (App-Icon, Kurzbefehl, Widget) öffnet diesen Bereich direkt.
                if (_isPlan && settings.profile.trains(TrainingSport.strength))
                  _HubRow(
                    title: 'Gym',
                    symbol: 'dumbbell.fill',
                    color: AppColors.of(context).good,
                    value: running == null ? 'Einheit starten' : 'läuft',
                    valueColor: running == null ? null : AppColors.of(context).good,
                    caption: running ?? 'Pläne, Übungen, Auswertung',
                    onTap: () => _open((_) => const GymScreen()),
                  ),
                if (!_isPlan)
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
                if (!_isPlan)
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
                if (!_isPlan)
                  _HubRow(
                    title: 'Herzfrequenz',
                    symbol: 'heart.fill',
                    color: AppColors.of(context).alert,
                    value: controller.zones?.run.lactateThreshold == null
                        ? '–'
                        : '${controller.zones!.run.lactateThreshold} bpm',
                    caption: 'Schwelle Laufen',
                    onTap: () => _open((_) => HeartRateScreen(report: controller.zones)),
                  ),
                if (!_isPlan)
                  _HubRow(
                    title: 'Trends',
                    symbol: 'chart.bar.xaxis',
                    color: Colors.purple,
                    value: '$weekMinutes min',
                    caption: 'diese Woche',
                    onTap: () => _open((_) => TrendsScreen(activities: _activities, gym: gym)),
                  ),
                if (!_isPlan)
                  _HubRow(
                    title: 'Schlaf-Coach',
                    symbol: 'moon.stars.fill',
                    color: Colors.indigo,
                    value: sleep == null ? '–' : '${SleepCoach.clock(sleep.bedtimeMinutes)} Uhr',
                    caption: 'Schlafenszeit heute',
                    onTap: () => _open((_) => const SleepCoachScreen()),
                  ),
                if (!_isPlan)
                  _HubRow(
                    title: 'Fitness & Form',
                    symbol: 'chart.line.uptrend.xyaxis',
                    color: AppColors.of(context).info,
                    value: formPercent == null ? '–' : FormZone.of(formPercent).label,
                    caption: 'Belastung der Uhr',
                    onTap: () => _open((_) => FitnessFormScreen(points: form)),
                  ),
                if (!_isPlan)
                  _HubRow(
                    title: 'Wochenbericht',
                    symbol: 'doc.text.magnifyingglass',
                    color: Colors.teal,
                    value: '${report.week.sessions} Einheiten',
                    caption: 'letzte Woche',
                    onTap: () => _open((_) => WeeklyReportScreen(report: report)),
                  ),
                if (_isPlan)
                  _HubRow(
                    title: 'Routen',
                    symbol: 'point.topleft.down.to.point.bottomright.curvepath',
                    color: Colors.teal,
                    value: routeToday == null ? '' : RouteFormat.distance(routeToday.stats.distanceMeters),
                    caption: routeToday == null
                        ? (routeStore.settings.explorationEnabled
                              ? '${routeStore.exploration.territories.length} Gebiete · Routen planen'
                              : 'Laufen & Rad auf OpenStreetMap')
                        : 'Route heute',
                    onTap: () => _open((_) => const RoutesScreen()),
                  ),
                if (_isPlan)
                  _HubRow(
                    title: 'Verpflegung',
                    symbol: 'fork.knife',
                    color: AppColors.of(context).caution,
                    value: '',
                    caption: 'Fuel Planner: vor, während, nach dem Training',
                    onTap: () => _open((_) => const FuelPlannerScreen()),
                  ),
              ],
            ),
            if (settings.profile.mode == ProfileMode.season) ...[
              if (!_isPlan)
                _HubGrid(
                  header: 'Disziplinen',
                  children: [
                    _HubRow(
                      title: 'Schwimmen',
                      symbol: 'figure.pool.swim',
                      color: AppColors.of(context).info,
                      value: '${PlanTokens.mmss(season.cssSecondsPer100m)} /100 m',
                      caption: 'CSS',
                      onTap: () => _open((_) => SwimScreen(controller: controller)),
                    ),
                    _HubRow(
                      title: 'Rad',
                      symbol: 'figure.outdoor.cycle',
                      color: AppColors.of(context).caution,
                      value: '${season.ftpWatts} W',
                      caption: 'FTP',
                      onTap: () => _open((_) => BikeScreen(controller: controller)),
                    ),
                    _HubRow(
                      title: 'Laufen',
                      symbol: 'figure.run',
                      color: AppColors.of(context).good,
                      value: '${PlanTokens.mmss(season.thresholdPaceSecondsPerKm)} /km',
                      caption: 'Schwelle',
                      onTap: () => _open((_) => RunScreen(controller: controller)),
                    ),
                  ],
                ),
              // Saisonziele gehören zum Plan (Roast F-4: unter „Saison“ zusammengefasst).
              if (_isPlan)
                _HubGrid(
                  header: 'Saison',
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
            ] else if (!_isPlan)
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
                style: AppText.caption(context).copyWith(color: secondary),
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

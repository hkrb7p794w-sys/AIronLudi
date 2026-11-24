import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/day_change.dart';
import '../../app/training_data_reload.dart';
import '../../data/repositories/gym_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/kpi_ring.dart';
import '../../ui/large_title.dart';
import '../../ui/liquid.dart';
import '../../ui/platform_names.dart';
import '../../ui/strain_card.dart';
import '../../ui/tokens.dart';
import '../activities/activity_detail_screen.dart';
import '../activities/activity_parts.dart';
import '../activities/post_workout_section.dart';
import '../ai/ai_screen.dart';
import '../ai/chat_screen.dart';
import '../endurance/endurance_controller.dart';
import '../evidence/evidence_views.dart';
import '../game/game_views.dart';
import '../gym/gym_providers.dart';
import '../gym/gym_screen.dart';
import '../health/health_screen.dart';
import '../health/morning_report_views.dart';
import '../plan/my_week_screen.dart';
import '../routes/routes_screen.dart';
import '../settings/data_sources_screen.dart';
import '../settings/settings_screen.dart';
import 'now_views.dart';
import 'today_controller.dart';
import 'today_dashboard_editor.dart';
import 'week_overview.dart';

/// Tagesempfehlung, Wochen-Soll/Ist und Rennvorbereitung (Port von `TodayView.swift`).
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> with TrainingDataReload<TodayScreen> {
  late final TodayController _controller = TodayController(
    store: ref.read(settingsStoreProvider),
    schedule: ref.read(seasonScheduleProvider),
  );
  List<DailyMetrics> _days = const [];
  List<GarminActivity> _activities = const [];
  List<StoredGymSession> _gym = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    unawaited(_reload(loadNote: true));
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

  List<GymItem> get _gymItems => [for (final record in _gym) GymItem.fromSession(record.session)];

  /// Neue Aktivität, Tageswerte oder Gym-Einheit in der Datenbank (gleich aus welcher Quelle): Belastung neu rechnen.
  @override
  Future<void> reloadTrainingData() => _reload();

  Future<void> _reload({bool loadNote = false}) async {
    final today = CalendarDay.today();
    final results = await (
      ref.read(metricsRepositoryProvider).range(from: today.adding(-400), to: today),
      ref.read(activityRepositoryProvider).all(),
      ref.read(gymRepositoryProvider).all(),
    ).wait;
    if (!mounted) return;
    _days = [...results.$1]..sort((a, b) => b.day.compareTo(a.day));
    _activities = results.$2;
    _gym = results.$3;
    _loaded = true;
    _update();
    if (loadNote) {
      unawaited(_controller.loadNote(ref.read(aiClientProvider), settings: ref.read(coachSettingsProvider)));
    }
  }

  /// Neu rechnen mit den geladenen Daten (Einstellungen, laufende Einheit).
  void _update() {
    if (!_loaded) return;
    final gym = ref.read(gymControllerProvider);
    // Laufende Einheit mit mindestens einem Satz zählt in der Wochenübersicht schon mit.
    final running = gym.active != null && gym.sessionState().countsAsTrained
        ? [gym.active!.day]
        : const <CalendarDay>[];
    _controller.update(
      days: _days,
      activities: _activities,
      settings: ref.read(coachSettingsProvider),
      gymDays: [for (final record in _gym) record.session.day, ...running],
      gym: _gymItems,
      enduranceToday: ref.read(enduranceControllerProvider).plan?.slotsOn(CalendarDay.today()) ?? const [],
    );
  }

  /// Erledigte Einheit unter „Jetzt dran“: dieselbe Ansicht wie unter „Aktivitäten“ (Aufzeichnung bzw. Krafteinheit).
  Widget? _doneScreen(TodayFocusItem item, CalendarDay today) {
    final sport = item.sport;
    if (sport == null) return null;
    if (sport == TrainingSport.strength) {
      final record = _gym.where((record) => record.session.day == today).firstOrNull;
      if (record != null) return SessionDetailScreen(record: record);
    }
    final candidates = [
      for (final activity in _activities)
        if (activity.day == today && activity.sport == sport.garminSport) activity,
    ]..sort((a, b) => (b.durationSeconds ?? 0).compareTo(a.durationSeconds ?? 0));
    return switch (candidates.firstOrNull) {
      final activity? => ActivityDetailScreen(activity: activity),
      null => null,
    };
  }

  /// „Meine Belastung heute“ aus Aktivitäten, Krafteinheiten der App, Plan und derselben Ampel wie „Jetzt dran“.
  DailyStrain _strain(TodaySnapshot snapshot) {
    final settings = ref.read(coachSettingsProvider);
    final today = snapshot.plan.today;
    final endurance = ref.read(enduranceControllerProvider).plan;
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
      recovery: snapshot.metrics == null ? null : snapshot.recommendation,
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

  /// Vorschläge für diese Woche (nur eigener Wochenplan): Tagesform und Wochenbelastung.
  List<PlanSuggestion> _suggestions(TodaySnapshot snapshot) {
    final settings = ref.read(coachSettingsProvider);
    if (settings.profile.mode != ProfileMode.personal) return const [];
    final today = snapshot.plan.today;
    return [
      if (snapshot.advice case final advice?)
        ?PlanSuggestion.recovery(
          advice: advice,
          profile: settings.profile,
          adjustments: settings.planAdjustments,
          today: today,
        ),
      if (snapshot.load case final load?)
        ?PlanSuggestion.load(load, profile: settings.profile, adjustments: settings.planAdjustments, today: today),
    ];
  }

  List<PlanSuggestion> _nextWeek(TodaySnapshot snapshot) {
    final settings = ref.read(coachSettingsProvider);
    final load = snapshot.load;
    if (settings.profile.mode != ProfileMode.personal || load == null) return const [];
    return [
      ?PlanSuggestion.nextWeek(
        load: load,
        profile: settings.profile,
        adjustments: settings.planAdjustments,
        today: snapshot.plan.today,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Neuer Kalendertag (Mitternacht, Rückkehr in die App): neu laden wie `onDayChange`.
    ref.listen(currentDayProvider, (_, _) => unawaited(_reload()));
    // Einstellungen, Abruf und laufende Einheit ändern die Einordnung.
    ref.listen(coachSettingsProvider, (_, _) => _update());
    ref.listen(gymControllerProvider, (_, _) => _update());
    // Ausdauerplan angepasst oder neu: „Jetzt dran“ zeigt dessen Einheiten.
    ref.listen(enduranceControllerProvider, (_, _) => _update());
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final model = ref.watch(appModelProvider);
    final settings = ref.watch(coachSettingsProvider);
    final snapshot = _controller.snapshot;
    final theme = Theme.of(context);
    final secondary = AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant);
    final today = snapshot?.plan.today ?? CalendarDay.today();
    final lastSync = model.lastSync ?? model.health.lastImport;
    return Scaffold(
      appBar: AppBar(
        title: const CollapsingTitle(child: Text('Heute')),
        actions: [
          IconButton(
            tooltip: 'Coach fragen',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ChatScreen(snapshot: snapshot))),
          ),
          IconButton(
            tooltip: 'Heute anpassen',
            icon: const Icon(Icons.tune),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TodayDashboardEditor())),
          ),
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await model.syncNow();
          await _reload(loadNote: true);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const LargeTitleHeader('Heute'),
            // Abrufstatus.
            if (model.isSyncing || model.lastError != null || (model.lastReport?.errors.isNotEmpty ?? false))
              FormSection(
                children: [
                  if (model.isSyncing)
                    const ListTile(
                      leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      title: Text('Daten werden abgerufen …'),
                    ),
                  if (model.lastError case final error?)
                    ListTile(
                      leading: Icon(Icons.warning_amber, color: AppColors.of(context).caution),
                      title: Text(
                        error,
                        style: AppText.footnote(context).copyWith(color: AppColors.of(context).caution),
                      ),
                    ),
                  if (model.lastReport case final report? when report.errors.isNotEmpty)
                    ListTile(
                      title: Text(
                        '${report.errors.length} Endpunkte ohne Daten – Details unter Einstellungen › Garmin-Diagnose.',
                        style: secondary,
                      ),
                    ),
                ],
              ),
            // Nur ohne Quelle und ohne Tageswerte der letzten sieben Tage (z. B. aus einer Sicherung oder Hand-Eingabe);
            // mit direktem Weg zu den Datenquellen statt nur einem Text.
            if (showsConnectSourceHint(
              hasSource: model.garmin.isConfigured || model.health.isEnabled || model.isWhoopConnected,
              metricDays: _days.map((metrics) => metrics.day),
              today: today,
            ))
              FormSection(
                children: [
                  ListTile(
                    title: Text(
                      'Verbinde in den Einstellungen eine Datenquelle – deine Uhr, WHOOP oder $healthStoreName –, '
                      'damit die App deine Erholung einordnen kann.',
                      style: secondary,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Quelle verbinden'),
                    textColor: theme.colorScheme.primary,
                    iconColor: theme.colorScheme.primary,
                    onTap: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const DataSourcesScreen())),
                  ),
                ],
              ),
            // Module erscheinen nacheinander mit einer weichen Feder.
            if (snapshot != null)
              for (final (index, section) in _sections(context, snapshot, settings, today, lastSync).indexed)
                LiquidAppear(
                  delay: Duration(milliseconds: 40 * index.clamp(0, 8)),
                  child: section,
                ),
            // Ohne geladene Tageswerte bleiben die Empfehlungen erreichbar.
            if (snapshot == null && settings.todayDashboard.shows(TodayModule.ai)) _aiSection(context, settings),
          ],
        ),
      ),
    );
  }

  /// Empfehlungen aus Regeln und KI (früher eigener Reiter „AI“), ganz ausblendbar.
  Widget _aiSection(BuildContext context, CoachSettings settings) {
    final theme = Theme.of(context);
    void open(Widget screen) => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
    return FormSection(
      children: [
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('AI-Empfehlungen'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (InsightInbox.unreadCount(settings.insights, now: DateTime.now()) case final unread when unread > 0)
                CoachChip(text: '$unread neu', color: theme.colorScheme.primary),
              const DisclosureChevron(),
            ],
          ),
          subtitle: switch (_controller.notePoints.firstOrNull) {
            final point? => Text(point, maxLines: 2, overflow: TextOverflow.ellipsis),
            null => null,
          },
          onTap: () => open(
            AIScreen(
              coachNote: ListenableBuilder(
                listenable: _controller,
                builder: (_, _) => _CoachNoteSection(controller: _controller),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Bereiche in fester Reihenfolge, je nach Auswahl unter „Heute anpassen“: oben Schlaf, Erholung und Strain,
  /// darunter das Training des Tages; alles Weitere lässt sich zuschalten.
  List<Widget> _sections(
    BuildContext context,
    TodaySnapshot snapshot,
    CoachSettings settings,
    CalendarDay today,
    DateTime? lastSync,
  ) {
    final dashboard = settings.todayDashboard;
    bool shows(TodayModule module) => dashboard.shows(module);
    final theme = Theme.of(context);
    final strain = _strain(snapshot);
    final todaysActivities = [
      for (final activity in _activities)
        if (activity.day == today) activity,
    ];
    void open(Widget screen) => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
    return [
      if (shows(TodayModule.kpis))
        FormSection(
          footer: snapshot.isFromYesterday ? 'Schlaf und Erholung von gestern – heute noch keine Werte.' : null,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: KpiRing(
                      kpi: TodayKpis.sleep(snapshot.metrics, targetHours: settings.sleep.targetHours),
                      onTap: () => open(const HealthScreen()),
                    ),
                  ),
                  Expanded(
                    child: KpiRing(
                      kpi: TodayKpis.recovery(
                        snapshot.metrics,
                        snapshot.metrics == null ? null : snapshot.recommendation.level,
                      ),
                      onTap: () => open(const HealthScreen()),
                    ),
                  ),
                  Expanded(
                    child: KpiRing(
                      kpi: TodayKpis.strain(strain),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => DailyStrainDetails(strain: strain),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      if (shows(TodayModule.training)) ...[
        if (snapshot.focus case final focus?)
          NowSection(snapshot: snapshot, focus: focus, openDone: (item) => _doneScreen(item, snapshot.plan.today)),
        const PlannedRoutesTodaySection(),
        MissedSessionSection(week: snapshot.sessions, onSaved: _reload),
        if (settings.profile.mode == ProfileMode.season)
          if (snapshot.today case final plan?) SeasonOpenSections(today: plan),
        _DoneTodaySection(
          activities: todaysActivities,
          gym: [
            for (final record in _gym)
              if (record.session.day == today) record,
          ],
          thresholds: ref.read(enduranceControllerProvider).plan?.request.thresholds ?? const AthleteThresholds(),
        ),
      ],
      if (shows(TodayModule.ai)) _aiSection(context, settings),
      if (shows(TodayModule.suggestions)) SuggestionsSection(suggestions: _suggestions(snapshot)),
      // Morning Report bis 12 Uhr; danach über „Gesundheit“ im Reiter Training.
      if (shows(TodayModule.morningReport) && DateTime.now().hour < 12)
        MorningReportCard(
          report: MorningReportBuilder.make(
            settings: settings,
            days: _days,
            activities: _activities,
            focus: snapshot.focus,
          ),
          focus: snapshot.focus,
        ),
      if (shows(TodayModule.strainDetails)) DailyStrainCard(strain: strain),
      if (shows(TodayModule.postWorkout)) PostWorkoutSection(activities: todaysActivities, sessions: snapshot.sessions),
      if (shows(TodayModule.weeklyReview) && WeeklyReview.isDue(today))
        if (snapshot.focus case final focus?) ...[
          WeeklyReviewSection(
            review: WeeklyReview.make(
              progress: focus.progress,
              week: snapshot.sessions,
              activities: _activities,
              gym: _gymItems,
              today: today,
            ),
          ),
          SuggestionsSection(suggestions: _nextWeek(snapshot), title: 'Vorschlag für nächste Woche'),
        ],
      if (shows(TodayModule.motivation))
        MotivationSections(snapshot: snapshot, activities: _activities, gym: _gym, showsLeague: false),
      if (shows(TodayModule.hints)) TodayHintsSection(snapshot: snapshot, activities: _activities, days: _days),
      if (shows(TodayModule.week))
        FormSection(
          header: 'Woche',
          footer: lastSync == null ? null : 'Letzter Abruf ${_relative(lastSync)}',
          children: [
            InkWell(
              onTap: () => open(
                WeekOverviewScreen(
                  snapshot: snapshot,
                  activities: _activities,
                  gymDays: {for (final record in _gym) record.session.day},
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  spacing: 14,
                  children: [
                    if (snapshot.focus?.progress case final progress?)
                      ProgressRing(
                        fraction: progress.fraction,
                        color: progress.fraction >= 1
                            ? AppColors.of(context).good
                            : progress.fraction >= 0.5
                            ? AppColors.of(context).caution
                            : theme.colorScheme.primary,
                        size: 52,
                        stroke: 6,
                        child: Text(
                          '${(progress.fraction.clamp(0, 9.99) * 100).round()} %',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          if (snapshot.focus?.progress case final progress?)
                            Text(progress.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Text('Diese Woche, Ziele und Verlauf'),
                        ],
                      ),
                    ),
                    const DisclosureChevron(),
                  ],
                ),
              ),
            ),
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Center(
          child: TextButton.icon(
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Heute anpassen'),
            onPressed: () => open(const TodayDashboardEditor()),
          ),
        ),
      ),
    ];
  }

  static String _relative(DateTime date) {
    final minutes = DateTime.now().difference(date).inMinutes;
    if (minutes < 1) return 'gerade eben';
    if (minutes < 60) return 'vor $minutes min';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'vor $hours h';
    final days = hours ~/ 24;
    return days == 1 ? 'gestern' : 'vor $days Tagen';
  }
}

/// Coach-Notiz der KI (oder regelbasiert) mit Grundlage.
class _CoachNoteSection extends ConsumerWidget {
  const _CoachNoteSection({required this.controller});

  final TodayController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final ai = ref.watch(aiClientProvider);
    final secondary = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: settings.profile.mode == ProfileMode.season ? 'Coach-Notiz' : 'Warum?',
      children: [
        for (final point in controller.notePoints)
          ListTile(
            dense: true,
            minLeadingWidth: 12,
            leading: const Icon(Icons.chevron_right, size: 16),
            title: Text(point, style: AppText.callout(context)),
          ),
        ListTile(
          dense: true,
          title: Text(controller.noteSource, style: secondary),
          trailing: controller.isLoadingNote
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : (ai.allows('daily_note')
                    ? TextButton(
                        onPressed: () => controller.loadNote(ai, settings: settings, force: true),
                        child: const Text('Neu formulieren'),
                      )
                    : null),
        ),
        if (controller.noteError case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(error, style: AppText.caption(context).copyWith(color: AppColors.of(context).caution)),
          ),
        EvidenceDisclosure(ruleIDs: controller.noteEvidence),
      ],
    );
  }
}

/// Heute erledigt, aus dem gemeinsamen Verlauf: Garmin, WHOOP, Health, Nachgetragenes und Gym (Doppelte einmal),
/// je mit Dauer, Puls und Strain.
class _DoneTodaySection extends StatelessWidget {
  const _DoneTodaySection({required this.activities, required this.gym, required this.thresholds});

  final List<GarminActivity> activities;
  final List<StoredGymSession> gym;
  final AthleteThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final entries = ActivityFeed.entries(
      activities: activities,
      gym: [for (final record in gym) GymItem.fromSession(record.session)],
    );
    if (entries.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: 'Heute erledigt',
      children: [
        for (final entry in entries)
          FeedRow(
            entry: entry,
            // Strain der Einheit auf derselben Skala wie oben (0–21).
            extra: switch (entry.activity) {
              final activity? =>
                'Strain ${GermanFormat.decimal(TodayKpis.strainOf(TrainingLoad.actual(activity, thresholds)))}',
              null => null,
            },
            onTap: () {
              final Widget? screen = switch ((entry.activity, entry.gym)) {
                (final activity?, _) => ActivityDetailScreen(activity: activity),
                (_, final item?) => switch (gym.where((record) => record.session.id == item.id).firstOrNull) {
                  final record? => SessionDetailScreen(record: record),
                  null => null,
                },
                _ => null,
              };
              if (screen != null) {
                unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
              }
            },
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../evidence/evidence_views.dart';
import '../gym/gym_providers.dart';
import '../settings/settings_screen.dart';
import 'now_views.dart';
import 'today_controller.dart';
import 'week_overview.dart';

/// Tagesempfehlung, Wochen-Soll/Ist und Rennvorbereitung (Port von `TodayView.swift`).
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
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
    // Einstellungen, Abruf und laufende Einheit ändern die Einordnung.
    ref.listen(coachSettingsProvider, (_, _) => _update());
    ref.listen(gymControllerProvider, (_, _) => _update());
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final model = ref.watch(appModelProvider);
    final settings = ref.watch(coachSettingsProvider);
    final snapshot = _controller.snapshot;
    final theme = Theme.of(context);
    final secondary = TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant);
    final today = snapshot?.plan.today ?? CalendarDay.today();
    final lastSync = model.lastSync ?? model.health.lastImport;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heute'),
        actions: [
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
                      leading: const Icon(Icons.warning_amber, color: Colors.orange),
                      title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.orange)),
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
            if (!model.garmin.isConfigured && !model.health.isEnabled)
              FormSection(
                children: [
                  ListTile(
                    title: Text(
                      'Melde dich in den Einstellungen mit deinem Garmin-Konto an oder schalte den Import aus Apple '
                      'Health (Apple Watch) ein.',
                      style: secondary,
                    ),
                  ),
                ],
              ),
            if (snapshot != null) ...[
              if (snapshot.focus case final focus?) NowSection(snapshot: snapshot, focus: focus),
              _CoachNoteSection(controller: _controller),
              SuggestionsSection(suggestions: _suggestions(snapshot)),
              if (settings.profile.mode == ProfileMode.season)
                if (snapshot.today case final plan?) SeasonOpenSections(today: plan),
              if (WeeklyReview.isDue(today))
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
              _DoneTodaySection(
                activities: [
                  for (final activity in _activities)
                    if (activity.day == today) activity,
                ],
                gym: [
                  for (final item in _gymItems)
                    if (CalendarDay.fromDate(item.start.toLocal()) == today) item,
                ],
              ),
              TodayHintsSection(snapshot: snapshot, activities: _activities, days: _days),
              FormSection(
                header: 'Woche',
                footer: lastSync == null ? null : 'Letzter Abruf ${_relative(lastSync)}',
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WeekOverviewScreen(
                          snapshot: snapshot,
                          activities: _activities,
                          gymDays: {for (final record in _gym) record.session.day},
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 6,
                              children: [
                                if (snapshot.focus?.progress case final progress?) ...[
                                  Text(progress.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  LinearProgressIndicator(
                                    value: progress.fraction.clamp(0, 1),
                                    color: progress.fraction >= 1 ? Colors.green : null,
                                  ),
                                ],
                                const Row(
                                  spacing: 6,
                                  children: [
                                    Icon(Icons.calendar_month_outlined, size: 18),
                                    Flexible(child: Text('Diese Woche, Ziele und Verlauf')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
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
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: settings.profile.mode == ProfileMode.season ? 'Coach-Notiz' : 'Warum?',
      children: [
        for (final point in controller.notePoints)
          ListTile(
            dense: true,
            minLeadingWidth: 12,
            leading: const Icon(Icons.chevron_right, size: 16),
            title: Text(point, style: const TextStyle(fontSize: 15)),
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
            child: Text(error, style: const TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        EvidenceDisclosure(ruleIDs: controller.noteEvidence),
      ],
    );
  }
}

/// Heute erledigt, aus dem gemeinsamen Verlauf: Garmin, Health, Nachgetragenes und Gym (Doppelte einmal).
class _DoneTodaySection extends StatelessWidget {
  const _DoneTodaySection({required this.activities, required this.gym});

  final List<GarminActivity> activities;
  final List<GymItem> gym;

  @override
  Widget build(BuildContext context) {
    final entries = ActivityFeed.entries(activities: activities, gym: gym);
    if (entries.isEmpty) return const SizedBox.shrink();
    return FormSection(
      header: 'Heute erledigt',
      children: [
        for (final entry in entries)
          ListTile(
            title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: entry.values.isEmpty ? null : Text(entry.values.join(' · ')),
          ),
      ],
    );
  }
}

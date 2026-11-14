import 'dart:async';

import 'package:coach_core/coach_core.dart' hide Badge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../services/social/social_service.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../gym/gym_screen.dart';
import '../today/today_controller.dart';
import 'activity_detail_screen.dart';
import 'activity_parts.dart';

enum ActivitiesScope {
  all('Alle'),
  mine('Meine'),
  friends('Freunde');

  const ActivitiesScope(this.label);

  final String label;
}

/// Reiter „Aktivitäten“: eigene Trainings und die Beiträge der Freunde in einer Liste, neueste oben. „Meine“ ist der
/// vollständige eigene Verlauf mit Suche und Filter, „Freunde“ nur deren Beiträge (Port von `ActivitiesView`).
class ActivitiesScreen extends ConsumerStatefulWidget {
  const ActivitiesScreen({super.key, this.initialScope = ActivitiesScope.all});

  /// „Alle Aktivitäten“ aus der Wochenübersicht öffnet direkt „Meine“.
  final ActivitiesScope initialScope;

  /// So viele eigene Trainings stehen höchstens unter „Alle“; der ganze Verlauf steht unter „Meine“.
  static const ownLimit = 300;

  /// So viele Wochen bekommen den Bezug zum Plan (ältere ohne, damit die Liste schnell bleibt).
  static const plannedWeeks = 6;

  @override
  ConsumerState<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends ConsumerState<ActivitiesScreen> {
  late ActivitiesScope _scope = widget.initialScope;
  List<GarminActivity> _activities = const [];
  List<StoredGymSession> _gym = const [];
  FeedFilter _filter = const FeedFilter();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    unawaited(ref.read(socialServiceProvider).refresh());
  }

  Future<void> _reload() async {
    final results = await (ref.read(activityRepositoryProvider).all(), ref.read(gymRepositoryProvider).all()).wait;
    if (!mounted) return;
    setState(() {
      _activities = [...results.$1]..sort((a, b) => (b.startLocal ?? '').compareTo(a.startLocal ?? ''));
      _gym = [...results.$2]..sort((a, b) => b.session.start.compareTo(a.session.start));
    });
  }

  Future<void> _refresh() async {
    await ref.read(appModelProvider).syncNow();
    await ref.read(socialServiceProvider).refresh();
    await _reload();
  }

  Future<void> _open(FeedEntry entry) async {
    final activity = entry.activity;
    final gym = entry.gym;
    Widget? screen;
    if (activity != null) {
      screen = ActivityDetailScreen(activity: activity);
    } else if (gym != null) {
      final record = _gym.where((record) => record.session.id == gym.id).firstOrNull;
      if (record != null) screen = SessionDetailScreen(record: record);
    }
    if (screen == null) return;
    final page = screen;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    await _reload();
  }

  List<FeedEntry> _feed(CoachSettings settings) {
    final sessions = [for (final record in _gym) record.session];
    final results = <SessionResult>[];
    if (settings.profile.mode == ProfileMode.personal) {
      final today = CalendarDay.today();
      final gymDays = [for (final session in sessions) session.day];
      for (var week = 0; week < ActivitiesScreen.plannedWeeks; week++) {
        results.addAll(
          TodayController.sessionWeek(
            settings: settings,
            activities: _activities,
            gymDays: gymDays,
            today: today,
            weekOf: today.adding(-7 * week),
          ).results,
        );
      }
    }
    return ActivityFeed.entries(
      activities: _activities,
      gym: [for (final session in sessions) GymItem.fromSession(session)],
      results: results,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appModelProvider.select((model) => model.lastSync), (_, _) => unawaited(_reload()));
    final settings = ref.watch(coachSettingsProvider);
    final social = ref.watch(socialServiceProvider);
    final incoming = social.incomingCount;
    return Scaffold(
      appBar: AppBar(
        title: _searching && _scope == ActivitiesScope.mine
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Name, Sportart, Wert', border: InputBorder.none),
                onChanged: (text) => setState(() => _filter = _copy(_filter, search: text)),
              )
            : const Text('Aktivitäten'),
        actions: [
          if (_scope == ActivitiesScope.mine) ...[
            IconButton(
              tooltip: _searching ? 'Suche schließen' : 'Suchen',
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _filter = _copy(_filter, search: '');
              }),
            ),
            _FilterMenu(filter: _filter, onChanged: (filter) => setState(() => _filter = filter)),
          ] else
            Badge(
              isLabelVisible: incoming > 0,
              label: Text('$incoming'),
              child: Icon(incoming > 0 ? Icons.people : Icons.people_outline, semanticLabel: 'Freunde'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ActivitiesScope>(
                segments: [
                  for (final scope in ActivitiesScope.values) ButtonSegment(value: scope, label: Text(scope.label)),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() => _scope = selection.first),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: switch (_scope) {
                ActivitiesScope.mine => _mine(settings),
                ActivitiesScope.all => _timeline(social, friendsOnly: false),
                ActivitiesScope.friends => _timeline(social, friendsOnly: true),
              },
            ),
          ),
        ],
      ),
    );
  }

  static FeedFilter _copy(
    FeedFilter filter, {
    TrainingSport? sport,
    bool clearSport = false,
    bool? onlyPlanned,
    bool? onlyHard,
    FeedPeriod? period,
    String? search,
  }) => FeedFilter(
    sport: clearSport ? null : (sport ?? filter.sport),
    onlyPlanned: onlyPlanned ?? filter.onlyPlanned,
    onlyHard: onlyHard ?? filter.onlyHard,
    period: period ?? filter.period,
    search: search ?? filter.search,
  );

  static String _monthTitle(String key) {
    final day = CalendarDay.tryParse('$key-01');
    return day == null ? key : DateFormat('MMMM y', 'de_DE').format(day.referenceDate);
  }

  Widget _mine(CoachSettings settings) {
    final all = _feed(settings);
    final entries = _filter.apply(all, today: CalendarDay.today());
    final months = <String, List<FeedEntry>>{};
    for (final entry in entries) {
      (months[entry.day.iso.substring(0, 7)] ??= []).add(entry);
    }
    final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        FormSection(
          footer: _filter.narrows || _filter.search.isNotEmpty
              ? '${entries.length} von ${all.length} Einheiten · Filter oben rechts'
                    '${_filter.onlyPlanned ? ' · Plan-Bezug der letzten ${ActivitiesScreen.plannedWeeks} Wochen' : ''}'
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<FeedPeriod>(
                  segments: [
                    for (final period in FeedPeriod.values)
                      ButtonSegment(
                        value: period,
                        label: FittedBox(child: Text(period.label)),
                      ),
                  ],
                  selected: {_filter.period},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => setState(() => _filter = _copy(_filter, period: selection.first)),
                ),
              ),
            ),
          ],
        ),
        if (all.isEmpty)
          _Empty(
            title: 'Noch keine Aktivitäten',
            text: 'Ziehe unter „Heute“ nach unten, um Garmin abzurufen, oder trage ein Training nach.',
            color: secondary,
          )
        else if (entries.isEmpty)
          _Empty(
            title: 'Keine Treffer',
            text: _filter.search.isEmpty
                ? 'Kein Training passt zum Filter.'
                : 'Nichts gefunden für „${_filter.search}“.',
            color: secondary,
          ),
        for (final month in keys)
          FormSection(
            header: _monthTitle(month),
            children: [
              for (final entry in months[month]!)
                FeedRow(entry: entry, onTap: entry.activity != null || entry.gym != null ? () => _open(entry) : null),
            ],
          ),
      ],
    );
  }

  Widget _timeline(SocialService social, {required bool friendsOnly}) {
    final List<TimelineItem> items;
    if (friendsOnly) {
      items = SocialTimeline.merge(
        entries: const [],
        posts: [
          for (final post in social.feed)
            if (!post.mine) post,
        ],
        shared: const {},
      );
    } else {
      final entries = ActivityFeed.entries(
        activities: _activities.take(ActivitiesScreen.ownLimit).toList(),
        gym: [for (final record in _gym.take(ActivitiesScreen.ownLimit)) GymItem.fromSession(record.session)],
      );
      final oldest = social.isAvailable && social.hasMore ? social.feed.lastOrNull?.date : null;
      items = SocialTimeline.merge(
        entries: entries,
        posts: social.isAvailable ? social.feed : const [],
        shared: SharedPostStore(ref.read(settingsStoreProvider)).load(),
        oldest: oldest,
      );
    }
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) unawaited(social.loadMore());
        return false;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (!social.isAvailable)
            FormSection(
              children: [
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Mit Freunden wird daraus ein Feed', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Mit einem Konto siehst du hier auch die Trainings deiner Freunde und kannst reagieren.',
                  ),
                ),
              ],
            )
          else if (social.lastError case final error?)
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.orange)),
            ),
          if (items.isEmpty && !social.isLoading)
            _Empty(
              title: friendsOnly ? 'Noch nichts von Freunden' : 'Noch keine Aktivitäten',
              text: friendsOnly
                  ? 'Hier erscheint, was deine Freunde teilen. Freunde findest du über den Benutzernamen.'
                  : 'Deine Trainings von Uhr und Gym erscheinen hier, dazu alles, was deine Freunde teilen.',
              color: secondary,
            ),
          for (final item in items)
            if (item.entry case final entry?) ...[
              FeedRow(entry: entry, onTap: entry.activity != null || entry.gym != null ? () => _open(entry) : null),
              if (item.post case final post?) _ReactionSummary(post: post),
              const Divider(height: 1, indent: 60),
            ] else if (item.post case final post?) ...[
              _PostTile(post: post),
              const Divider(height: 1),
            ],
          if (social.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.text, required this.color});

  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
    child: Column(
      spacing: 8,
      children: [
        Icon(Icons.directions_run, size: 44, color: color),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color),
        ),
      ],
    ),
  );
}

/// Filter: Sportart, nur Plan-Einheiten, nur harte Einheiten, zurücksetzen.
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({required this.filter, required this.onChanged});

  final FeedFilter filter;
  final ValueChanged<FeedFilter> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: 'Filter',
    icon: Icon(filter.narrows ? Icons.filter_alt : Icons.filter_alt_outlined),
    onSelected: (action) => action(),
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        checked: filter.sport == null,
        value: () => onChanged(_ActivitiesScreenState._copy(filter, clearSport: true)),
        child: const Text('Alle Sportarten'),
      ),
      for (final sport in TrainingSport.values)
        CheckedPopupMenuItem(
          checked: filter.sport == sport,
          value: () => onChanged(_ActivitiesScreenState._copy(filter, sport: sport)),
          child: Row(
            spacing: 8,
            children: [
              Icon(AppSymbols.of(sport.symbol), size: 18, color: sport.color),
              Text(sport.label),
            ],
          ),
        ),
      const PopupMenuDivider(),
      CheckedPopupMenuItem(
        checked: filter.onlyPlanned,
        value: () => onChanged(_ActivitiesScreenState._copy(filter, onlyPlanned: !filter.onlyPlanned)),
        child: const Text('Nur Plan-Einheiten'),
      ),
      CheckedPopupMenuItem(
        checked: filter.onlyHard,
        value: () => onChanged(_ActivitiesScreenState._copy(filter, onlyHard: !filter.onlyHard)),
        child: const Text('Nur harte Einheiten'),
      ),
      if (filter.narrows)
        PopupMenuItem(
          value: () => onChanged(FeedFilter(period: filter.period, search: filter.search)),
          child: const Text('Filter zurücksetzen'),
        ),
    ],
  );
}

/// Beitrag eines Freundes: Name, Zeit, Überschrift und Kennzahlen. Reaktionen, Kommentare und Mahlzeit-Übernahme
/// folgen mit dem Bereich „Freunde“.
class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final SocialPost post;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final date = post.date;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            spacing: 10,
            children: [
              CircleAvatar(
                radius: 16,
                child: Text((post.mine ? 'D' : post.author.displayName.characters.firstOrNull ?? '?').toUpperCase()),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.mine ? 'Du' : post.author.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (date != null)
                      Text(SocialFormat.relative(date), style: TextStyle(fontSize: 12, color: secondary)),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Icon(AppSymbols.of(post.symbol), size: 20),
              Expanded(
                child: Text(post.headline, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
            ],
          ),
          if (post.facts.isNotEmpty) Text(post.facts, style: TextStyle(color: secondary)),
          _ReactionSummary(post: post, padded: false),
        ],
      ),
    );
  }
}

class _ReactionSummary extends StatelessWidget {
  const _ReactionSummary({required this.post, this.padded = true});

  final SocialPost post;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    if (post.reactions == 0 && post.comments == 0) return const SizedBox.shrink();
    final text = [
      if (post.reactions > 0) '${post.topReactions} ${post.reactions}'.trim(),
      if (post.comments > 0) '${post.comments} ${post.comments == 1 ? 'Kommentar' : 'Kommentare'}',
    ].join(' · ');
    return Padding(
      padding: padded ? const EdgeInsets.fromLTRB(72, 0, 16, 8) : EdgeInsets.zero,
      child: Text(text, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

import 'dart:async';

import 'package:coach_core/coach_core.dart' hide Badge;
import 'package:coach_core/coach_core.dart' as core show Badge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/storage.dart';
import '../../services/ai/ai_client.dart';
import '../../services/providers.dart';
import '../../services/social/game_service.dart';
import '../../ui/components.dart';
import '../../ui/symbols.dart';
import '../social/social_views.dart';
import '../today/now_views.dart';
import '../today/today_controller.dart';

IconData badgeIcon(String symbol) => switch (symbol) {
  '5.circle.fill' || '10.circle.fill' || 'star.circle.fill' => Icons.stars,
  'calendar' => Icons.calendar_month,
  'calendar.badge.checkmark' => Icons.event_available,
  'checkmark.seal' || 'checkmark.seal.fill' => Icons.verified,
  'flame' || 'flame.fill' => Icons.local_fire_department,
  'fork.knife' || 'fork.knife.circle.fill' => Icons.restaurant,
  'medal.fill' => Icons.military_tech,
  'person.2' || 'person.3.fill' => Icons.groups,
  'rosette' => Icons.workspace_premium,
  'trophy' || 'trophy.fill' => Icons.emoji_events,
  final other => AppSymbols.of(other),
};

/// Trainingstage für Serie und Begleiter: zählende Aktivitäten (Port von `MotivationSections.trainingDays`).
Set<CalendarDay> trainingDays(WidgetRef ref, List<GarminActivity> activities, Set<CalendarDay> gymDays) {
  final settings = ref.read(coachSettingsProvider);
  return {
    for (final activity in activities)
      if (activity.day case final day?
          when ScoreRules.countsAsTraining(
            activity,
            otherIsPlanned: settings
                .schedule(day)
                .slots(Weekday.of(day))
                .any((slot) => slot.sport == TrainingSport.other),
          ))
        day,
    ...gymDays,
  };
}

/// Begleiter und Rangliste unter „Heute“ (Port von `MotivationSections`). Begleiter und Liga folgen in Phase 3j-4;
/// hier Serie, Stufe und Abzeichen.
class MotivationSections extends ConsumerWidget {
  const MotivationSections({super.key, required this.snapshot, required this.activities, required this.gym});

  final TodaySnapshot snapshot;
  final List<GarminActivity> activities;
  final List<StoredGymSession> gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(coachSettingsProvider);
    final today = snapshot.plan.today;
    final days = trainingDays(ref, activities, {for (final record in gym) record.session.day});
    final summary = ref.read(appModelProvider).motivation(days, today: today);
    // Serie, Stufe und Abzeichen; meldet den Stand an die Freundes-Rangliste.
    return GameSection(summary: summary, activities: activities, gym: gym, trainingDays: days, today: today);
  }
}

/// „Heute“: Tages-Serie, Stufe und nächstes Abzeichen; meldet den Stand an die Freundes-Rangliste (Port von
/// `GameSection`).
class GameSection extends ConsumerStatefulWidget {
  const GameSection({
    super.key,
    required this.summary,
    required this.activities,
    required this.gym,
    required this.trainingDays,
    required this.today,
  });

  final MotivationSummary summary;
  final List<GarminActivity> activities;
  final List<StoredGymSession> gym;
  final Set<CalendarDay> trainingDays;
  final CalendarDay today;

  @override
  ConsumerState<GameSection> createState() => _GameSectionState();
}

class _GameSectionState extends ConsumerState<GameSection> {
  Set<CalendarDay> _mealDays = const {};
  String? _reported;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeals());
  }

  Future<void> _loadMeals() async {
    final meals = await ref.read(mealRepositoryProvider).all();
    if (!mounted) return;
    setState(() => _mealDays = {for (final meal in meals.take(2000)) meal.day});
  }

  /// Trainingsminuten je Tag aus Aktivitäten und Krafteinheiten (für Challenges).
  Map<CalendarDay, int> get _minutesByDay {
    final result = <CalendarDay, int>{};
    final since = widget.today.adding(-14);
    for (final activity in widget.activities) {
      final day = activity.day;
      final seconds = activity.movingSeconds ?? activity.durationSeconds;
      if (day == null || day < since || seconds == null) continue;
      result[day] = (result[day] ?? 0) + (seconds / 60).round();
    }
    for (final record in widget.gym.take(60)) {
      final session = record.session;
      final end = session.end;
      if (session.day < since || end == null) continue;
      result[session.day] = (result[session.day] ?? 0) + (end.difference(session.start).inSeconds / 60).round();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameServiceProvider);
    final social = ref.watch(socialServiceProvider);
    final meals = _mealDays;
    final streak = DailyStreak.compute(activeDays: {...widget.trainingDays, ...meals}, today: widget.today);
    final summary = widget.summary;
    final level = GameLevel.progress(summary.totalPoints);
    final stats = GameStats()
      ..workouts = widget.activities.length + widget.gym.length
      ..bestDayStreak = streak.best
      ..planWeekStreak = summary.streak
      ..mealDays = meals.length
      ..friends = social.friends.friends.length
      ..challengesWon = game.challengesWon
      ..level = level.level;
    final next = BadgeRules.next(stats);
    final key =
        '${summary.weekPoints}-${summary.totalPoints}-${streak.current}-${meals.length}-${widget.trainingDays.length}';
    if (_reported != key) {
      _reported = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        game.snapshot = GameSnapshot(streak: streak, summary: summary, stats: stats);
        unawaited(
          game.report(
            summary: summary,
            streak: streak,
            inputs: GameInputs(
              today: widget.today,
              minutesByDay: _minutesByDay,
              mealDays: meals,
              adherence: summary.week,
            ),
          ),
        );
      });
    }
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Fortschritt',
      footer: streak.jokerDays.isEmpty
          ? null
          : 'Joker eingesetzt: Ein freier Tag pro Woche unterbricht die Serie nicht – Pausen gehören dazu.',
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => const FriendsScreen(initialPage: FriendsPage.game),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.local_fire_department, color: streak.activeToday ? Colors.orange : secondary),
                    Expanded(
                      child: Text(
                        streak.current == 1 ? '1 Tag in Folge' : '${streak.current} Tage in Folge',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ),
                    Text('Stufe ${level.level}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Semantics(
                  label: 'Fortschritt zur nächsten Stufe: ${level.inLevel} von ${level.perLevel} Punkten',
                  child: LinearProgressIndicator(value: level.perLevel == 0 ? 0 : level.inLevel / level.perLevel),
                ),
                if (!streak.activeToday && streak.current > 0)
                  Text(
                    'Erfasse heute ein Training oder eine Mahlzeit, damit die Serie weiterläuft.',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                if (next != null)
                  Row(
                    spacing: 6,
                    children: [
                      Icon(badgeIcon(next.symbol), size: 16, color: secondary),
                      Expanded(
                        child: Text(
                          'Nächstes Abzeichen: ${next.title} (${next.progress(stats)}/${next.target})',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// „Wettkampf“ in Freunde: Stufe und Serie, Rangliste der Woche, Challenges, Abzeichen (Port von `GameView`).
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(gameServiceProvider).refresh());
  }

  Widget _tile(String value, String label, IconData icon, Color color) => Expanded(
    child: Semantics(
      container: true,
      child: Column(
        spacing: 4,
        children: [
          Icon(icon, color: color),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameServiceProvider);
    final social = ref.watch(socialServiceProvider);
    final snapshot = game.snapshot;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final noFriends = social.friends.friends.isEmpty;
    return RefreshIndicator(
      onRefresh: game.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (snapshot != null)
            FormSection(
              footer:
                  'Punkte gibt es für dein eigenes Plan-Ziel, nicht für mehr Training: Wer wenig plant, kann genauso '
                  'gewinnen. Beste Serie: ${snapshot.streak.best} Tage.',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    spacing: 8,
                    children: [
                      _tile('${snapshot.streak.current}', 'Tage in Folge', Icons.local_fire_department, Colors.orange),
                      _tile(
                        '${GameLevel.progress(snapshot.summary.totalPoints).level}',
                        'Stufe',
                        Icons.star,
                        Colors.amber,
                      ),
                      _tile('${snapshot.summary.weekPoints}', 'Punkte diese Woche', Icons.bar_chart, Colors.blue),
                    ],
                  ),
                ),
              ],
            ),
          if (game.invitations.isNotEmpty)
            FormSection(
              header: 'Einladungen',
              children: [
                for (final challenge in game.invitations)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Text(challenge.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(
                          '${challenge.metricTitle} · Woche ab ${challenge.monday == null ? challenge.week : shortDate(challenge.monday!)}',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(onPressed: () => game.join(challenge), child: const Text('Mitmachen')),
                            OutlinedButton(onPressed: () => game.leave(challenge), child: const Text('Ablehnen')),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          FormSection(
            header: 'Rangliste diese Woche',
            footer: 'Wochenpunkte: 100 = alles Geplante erledigt.',
            children: [
              if (game.leaderboard.length <= 1)
                ListTile(
                  title: Text(
                    'Füge Freunde hinzu, um euch in der Rangliste zu vergleichen.',
                    style: TextStyle(color: secondary),
                  ),
                ),
              for (final entry in game.leaderboard)
                ListTile(
                  tileColor: entry.me ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : null,
                  leading: SizedBox(
                    width: 72,
                    child: Row(
                      spacing: 8,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(entry.rank <= 3 ? const ['🥇', '🥈', '🥉'][entry.rank - 1] : '${entry.rank}.'),
                        ),
                        Avatar(
                          person: SocialPerson(username: entry.username, displayName: entry.displayName),
                          size: 30,
                        ),
                      ],
                    ),
                  ),
                  title: Text(entry.me ? 'Du' : entry.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Stufe ${entry.level < 1 ? 1 : entry.level} · 🔥 ${entry.dayStreak}'),
                  trailing: Text(
                    entry.reported ? '${entry.weekPoints}' : '–',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          FormSection(
            header: 'Challenges',
            footer: noFriends
                ? 'Challenges gibt es mit Freunden – füge zuerst jemanden hinzu.'
                : 'Eine Challenge läuft immer eine Kalenderwoche. Der Stand aktualisiert sich beim Öffnen von „Heute“.',
            children: [
              ListTile(
                enabled: !noFriends,
                leading: const Icon(Icons.sports_score),
                title: const Text('Neue Challenge'),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const NewChallengeScreen())),
              ),
              for (final challenge in game.challenges)
                if (challenge.status == 'joined') _ChallengeRow(challenge: challenge),
            ],
          ),
          if (snapshot != null) BadgeGrid(stats: snapshot.stats),
          if (game.lastError case final error?)
            ListTile(
              title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.orange)),
            ),
        ],
      ),
    );
  }
}

class _ChallengeRow extends ConsumerWidget {
  const _ChallengeRow({required this.challenge});

  final Challenge challenge;

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final label = challenge.mineCreated ? 'Löschen' : 'Verlassen';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(challenge.mineCreated ? 'Challenge für alle löschen?' : 'Challenge verlassen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(label, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok ?? false) await ref.read(gameServiceProvider).leave(challenge);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final top = (challenge.max < 1 ? 1 : challenge.max).toDouble();
    final pending = challenge.members.where((member) => member.status == 'invited').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(challenge.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
              if (challenge.finished)
                Text(
                  challenge.iWon ? '🏆 Gewonnen' : 'Beendet',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: challenge.iWon ? Colors.orange : secondary,
                  ),
                ),
              IconButton(
                tooltip: challenge.mineCreated ? 'Löschen' : 'Verlassen',
                icon: const Icon(Icons.logout),
                onPressed: () => _confirmLeave(context, ref),
              ),
            ],
          ),
          Text(challenge.kind?.rule ?? challenge.metricTitle, style: TextStyle(fontSize: 12, color: secondary)),
          for (final member in challenge.joined)
            Semantics(
              container: true,
              child: Row(
                spacing: 8,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${member.winner ? '🏆 ' : ''}${member.me ? 'Du' : member.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (member.progress.clamp(0, top)) / top,
                      color: member.me ? Theme.of(context).colorScheme.primary : secondary,
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${member.progress.toInt()} ${challenge.kind?.unit ?? ''}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (pending > 0)
            Text('$pending eingeladen, noch nicht dabei', style: TextStyle(fontSize: 11, color: secondary)),
        ],
      ),
    );
  }
}

/// Abzeichen mit Fortschritt (Port von `BadgeGrid`).
class BadgeGrid extends StatelessWidget {
  const BadgeGrid({super.key, required this.stats});

  final GameStats stats;

  @override
  Widget build(BuildContext context) {
    final earned = BadgeRules.earned(stats).length;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget badge(core.Badge badge) {
      final done = badge.isEarned(stats);
      return SizedBox(
        width: 96,
        child: Semantics(
          label: '${badge.title}, ${done ? 'erreicht' : '${badge.progress(stats)} von ${badge.target}'}',
          excludeSemantics: true,
          child: Column(
            spacing: 4,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: done ? Colors.orange.withValues(alpha: 0.15) : secondary.withValues(alpha: 0.08),
                child: Icon(badgeIcon(badge.symbol), color: done ? Colors.orange : secondary.withValues(alpha: 0.5)),
              ),
              Text(
                badge.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                done ? badge.detail : '${badge.progress(stats)}/${badge.target}',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 11, color: secondary),
              ),
            ],
          ),
        ),
      );
    }

    return FormSection(
      header: 'Abzeichen ($earned/${BadgeRules.all.length})',
      footer: 'Abzeichen gibt es für Beständigkeit – nie für mehr Training als geplant oder für weniger Essen.',
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [for (final item in BadgeRules.all) badge(item)],
          ),
        ),
      ],
    );
  }
}

/// Neue Challenge mit Freunden (Port von `NewChallengeSheet`).
class NewChallengeScreen extends ConsumerStatefulWidget {
  const NewChallengeScreen({super.key});

  @override
  ConsumerState<NewChallengeScreen> createState() => _NewChallengeScreenState();
}

class _NewChallengeScreenState extends ConsumerState<NewChallengeScreen> {
  ChallengeMetric _metric = ChallengeMetric.values.first;
  bool _nextWeek = false;
  final _title = TextEditingController();
  final _invited = <String>{};
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final monday = PlanAdjustments.monday(CalendarDay.today());
    setState(() => _sending = true);
    try {
      await ref
          .read(gameServiceProvider)
          .create(
            metric: _metric,
            week: _nextWeek ? monday.adding(7) : monday,
            title: _title.text.trim(),
            invite: _invited.toList(),
          );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      setState(() => _error = error is AIClientError ? error.message : '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(socialServiceProvider).friends.friends;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neue Challenge'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: _metric.rule,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<ChallengeMetric>(
                  initialValue: _metric,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Worum geht’s?'),
                  items: [
                    for (final metric in ChallengeMetric.values)
                      DropdownMenuItem(value: metric, child: Text(metric.title)),
                  ],
                  onChanged: (metric) => setState(() => _metric = metric ?? _metric),
                ),
              ),
            ],
          ),
          FormSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Diese Woche')),
                      ButtonSegment(value: true, label: Text('Nächste Woche')),
                    ],
                    selected: {_nextWeek},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => setState(() => _nextWeek = selection.first),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Name (optional), z. B. Novemberduell'),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Freunde einladen',
            children: [
              for (final friend in friends)
                CheckboxListTile(
                  title: Text(friend.displayName),
                  value: _invited.contains(friend.username),
                  onChanged: (on) =>
                      setState(() => on ?? false ? _invited.add(friend.username) : _invited.remove(friend.username)),
                ),
            ],
          ),
          FormSection(
            footer: _error,
            children: [
              ListTile(
                enabled: _invited.isNotEmpty && !_sending,
                title: const Text('Challenge starten'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: _start,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

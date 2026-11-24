import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ai/ai_client.dart';
import '../../services/providers.dart';
import '../../services/social/social_service.dart';
import '../../ui/components.dart';
import '../../ui/symbols.dart';
import '../../ui/tokens.dart';
import '../account/account_views.dart';
import '../game/game_views.dart';
import '../nutrition/meal_share_views.dart';

part 'social_comments_friends.dart';

String _errorText(Object error) => error is AIClientError ? error.message : '$error';

IconData postIcon(SocialPost post) => switch (post.symbol) {
  'fork.knife' => Icons.restaurant,
  'trophy.fill' => Icons.emoji_events,
  'star.fill' => Icons.star,
  final symbol => AppSymbols.of(symbol),
};

enum FriendsPage {
  feed('Feed'),
  friends('Freunde'),
  game('Wettkampf');

  const FriendsPage(this.label);

  final String label;
}

/// Freunde: Feed mit Trainings, Mahlzeiten und Meilensteinen der Freunde sowie Freundesliste mit Suche (Port von
/// `FriendsView`).
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.initialPage = FriendsPage.feed});

  final FriendsPage initialPage;

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  late FriendsPage _page = widget.initialPage;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(socialServiceProvider).refresh());
    unawaited(ref.read(gameServiceProvider).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialServiceProvider);
    final invitations = ref.watch(gameServiceProvider).invitations.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Freunde'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: social.isAvailable
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<FriendsPage>(
                      segments: [
                        for (final page in FriendsPage.values)
                          ButtonSegment(
                            value: page,
                            label: Text(switch (page) {
                              FriendsPage.friends when social.incomingCount > 0 => 'Freunde (${social.incomingCount})',
                              FriendsPage.game when invitations > 0 => 'Wettkampf ($invitations)',
                              _ => page.label,
                            }),
                          ),
                      ],
                      selected: {_page},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) => setState(() => _page = selection.first),
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_page) {
                    FriendsPage.feed => const FeedList(),
                    FriendsPage.friends => const FriendList(),
                    FriendsPage.game => const GameScreen(),
                  },
                ),
              ],
            )
          : const SignInPrompt(
              title: 'Freunde brauchen ein Konto',
              text:
                  'Mit einem eigenen Konto findest du Freunde über den Benutzernamen, siehst ihre Trainings und teilst '
                  'Mahlzeiten. Nur du kennst dein Passwort.',
            ),
    );
  }
}

/// Hinweis mit „Anmelden“ und „Konto erstellen“.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 12,
      children: [
        Icon(Icons.people_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(text, textAlign: TextAlign.center),
        FilledButton(
          onPressed: () => presentAccountAuth(context, AccountAuthMode.login),
          child: const Text('Anmelden'),
        ),
        TextButton(
          onPressed: () => presentAccountAuth(context, AccountAuthMode.register),
          child: const Text('Konto erstellen'),
        ),
      ],
    ),
  );
}

/// Beiträge der Freunde (und eigene) mit Nachladen.
class FeedList extends ConsumerWidget {
  const FeedList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(socialServiceProvider);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return RefreshIndicator(
      onRefresh: social.refresh,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 300) unawaited(social.loadMore());
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (social.lastError case final error?)
              ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: AppColors.of(context).caution),
                title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).caution)),
              ),
            if (social.feed.isEmpty && !social.isLoading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Noch nichts geteilt\nTeile ein Training (Abschluss im Gym oder Aktivität › Teilen) oder eine Mahlzeit '
                  '(Ernährung › Teilen). Hier erscheint, was deine Freunde teilen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondary),
                ),
              ),
            for (final post in social.feed) ...[
              InkWell(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostDetailScreen(post: post))),
                child: PostCard(post: post, compact: true),
              ),
              const Divider(height: 1),
            ],
            if (social.isLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein Beitrag: Person, Zeit, Inhalt, Reaktionen und Kommentare (Port von `PostCard`).
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post, this.compact = false});

  final SocialPost post;

  /// In Listen: nur eine dezente Zusammenfassung der Reaktionen; Antippen öffnet den Beitrag mit allen Reaktionen.
  final bool compact;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beitrag löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Löschen', style: TextStyle(color: AppColors.of(context).alert)),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      try {
        await ref.read(socialServiceProvider).delete(post);
      } on Object {
        // Bleibt stehen; der nächste Abruf zeigt den Stand.
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final payload = post.payload;
    final date = post.date;
    final exercises = payload.exercises ?? const <String>[];
    final meal = payload.meal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 10,
            children: [
              Avatar(person: post.author),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.mine ? 'Du' : post.author.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (date != null)
                      Text(SocialFormat.relative(date), style: AppText.caption(context).copyWith(color: secondary)),
                  ],
                ),
              ),
              if (post.mine)
                PopupMenuButton<void>(
                  tooltip: 'Optionen',
                  icon: const Icon(Icons.more_horiz),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => _confirmDelete(context, ref),
                      child: Text('Beitrag löschen', style: TextStyle(color: AppColors.of(context).alert)),
                    ),
                  ],
                ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Icon(postIcon(post), size: 20),
              Expanded(child: Text(post.headline, style: AppText.headline(context))),
            ],
          ),
          if (post.facts.isNotEmpty) Text(post.facts, style: TextStyle(color: secondary)),
          if (exercises.isNotEmpty)
            Text(
              exercises.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.footnote(context).copyWith(color: secondary),
            ),
          for (final record in payload.records ?? const <String>[])
            Row(
              spacing: 6,
              children: [
                Icon(Icons.emoji_events, size: 16, color: AppColors.of(context).caution),
                Expanded(
                  child: Text(record, style: AppText.footnote(context).copyWith(color: AppColors.of(context).caution)),
                ),
              ],
            ),
          if (payload.note case final note? when note.isNotEmpty) Text(note),
          if (post.kind == SocialPostKind.meal && meal != null && !post.mine)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ReceivedMealScreen(preloaded: meal)),
              ),
              icon: const Icon(Icons.download),
              label: const Text('In mein Tagebuch übernehmen'),
            ),
          if (compact) ReactionSummary(post: post) else ReactionBar(post: post),
        ],
      ),
    );
  }
}

/// Dezente Zeile für Listen: vorhandene Reaktionen und Kommentare, sonst nichts. Antippen öffnet den Beitrag.
class ReactionSummary extends StatelessWidget {
  const ReactionSummary({super.key, required this.post});

  final SocialPost post;

  @override
  Widget build(BuildContext context) {
    if (post.reactions == 0 && post.comments == 0) return const SizedBox.shrink();
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostDetailScreen(post: post))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          spacing: 10,
          children: [
            if (post.reactions > 0)
              Text(
                '${post.topReactions} ${post.reactions}',
                style: AppText.caption(context).copyWith(color: secondary),
              ),
            if (post.comments > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 13, color: secondary),
                  Text(
                    '${post.comments}',
                    semanticsLabel: '${post.comments} Kommentare',
                    style: AppText.caption(context).copyWith(color: secondary),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein Beitrag mit allen Reaktionen und dem Weg zu den Kommentaren.
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.post});

  final SocialPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nach einer Reaktion aktualisiert der Dienst den Beitrag im Feed: den aktuellen Stand anzeigen.
    final current = ref.watch(socialServiceProvider).feed.where((item) => item.id == post.id).firstOrNull ?? post;
    return Scaffold(
      appBar: AppBar(title: Text(current.mine ? 'Dein Beitrag' : current.author.displayName)),
      body: ListView(children: [PostCard(post: current)]),
    );
  }
}

/// Reaktionen und Kommentare unter einem Beitrag (Port von `ReactionBar`).
class ReactionBar extends ConsumerWidget {
  const ReactionBar({super.key, required this.post});

  final SocialPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (final reaction in SocialReaction.values)
          Semantics(
            label: '${reaction.label}${post.myReaction == reaction.rawValue ? ', gewählt' : ''}',
            button: true,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                unawaited(ref.read(socialServiceProvider).react(post, reaction));
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: post.myReaction == reaction.rawValue ? primary.withValues(alpha: 0.2) : null,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(reaction.rawValue, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ),
        const Spacer(),
        if (post.reactions > 0)
          Text('${post.topReactions} ${post.reactions}', style: AppText.caption(context).copyWith(color: secondary)),
        TextButton.icon(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => CommentsScreen(post: post))),
          icon: const Icon(Icons.chat_bubble_outline, size: 16),
          label: Text('${post.comments}', semanticsLabel: '${post.comments} Kommentare'),
        ),
      ],
    );
  }
}

/// Anfangsbuchstabe im Kreis, gleiche Farbe je Benutzername.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.person, this.size = 36});

  final SocialPerson person;
  final double size;

  static const _palette = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.pink,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    final sum = person.username.runes.fold(0, (total, rune) => total + rune);
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: _palette[sum % _palette.length],
        child: Text(
          person.initial,
          style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }
}

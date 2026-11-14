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
import '../account/account_views.dart';
import '../nutrition/meal_share_views.dart';

String _errorText(Object error) => error is AIClientError ? error.message : '$error';

IconData postIcon(SocialPost post) => switch (post.symbol) {
  'fork.knife' => Icons.restaurant,
  'trophy.fill' => Icons.emoji_events,
  'star.fill' => Icons.star,
  final symbol => AppSymbols.of(symbol),
};

enum FriendsPage {
  feed('Feed'),
  friends('Freunde');

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
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialServiceProvider);
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
                            label: Text(
                              page == FriendsPage.friends && social.incomingCount > 0
                                  ? 'Freunde (${social.incomingCount})'
                                  : page.label,
                            ),
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
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.orange)),
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
            for (final post in social.feed) ...[PostCard(post: post), const Divider(height: 1)],
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
  const PostCard({super.key, required this.post});

  final SocialPost post;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beitrag löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
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
                      Text(SocialFormat.relative(date), style: TextStyle(fontSize: 12, color: secondary)),
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
                      child: const Text('Beitrag löschen', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Icon(postIcon(post), size: 20),
              Expanded(
                child: Text(post.headline, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
            ],
          ),
          if (post.facts.isNotEmpty) Text(post.facts, style: TextStyle(color: secondary)),
          if (exercises.isNotEmpty)
            Text(
              exercises.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          for (final record in payload.records ?? const <String>[])
            Row(
              spacing: 6,
              children: [
                const Icon(Icons.emoji_events, size: 16, color: Colors.orange),
                Expanded(
                  child: Text(record, style: const TextStyle(fontSize: 13, color: Colors.orange)),
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
          ReactionBar(post: post),
        ],
      ),
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
          Text('${post.topReactions} ${post.reactions}', style: TextStyle(fontSize: 12, color: secondary)),
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

/// Kommentare eines Beitrags (Port von `CommentsView`).
class CommentsScreen extends ConsumerStatefulWidget {
  const CommentsScreen({super.key, required this.post});

  final SocialPost post;

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  List<SocialComment> _comments = const [];
  final _text = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await ref.read(socialServiceProvider).comments(widget.post);
      if (mounted) setState(() => _comments = comments);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _send() async {
    final trimmed = _text.text.trim();
    final value = trimmed.runes.length > 280 ? String.fromCharCodes(trimmed.runes.take(280)) : trimmed;
    try {
      await ref.read(socialServiceProvider).comment(widget.post, value);
      _text.clear();
      await _load();
    } on Object catch (error) {
      setState(() => _error = _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post.headline),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                for (final comment in _comments)
                  ListTile(
                    title: Row(
                      spacing: 8,
                      children: [
                        Flexible(
                          child: Text(comment.author.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (SocialFormat.date(comment.createdAt) case final date?)
                          Text(SocialFormat.relative(date), style: TextStyle(fontSize: 12, color: secondary)),
                      ],
                    ),
                    subtitle: Text(comment.text),
                    trailing: comment.canDelete
                        ? IconButton(
                            tooltip: 'Löschen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              try {
                                await ref.read(socialServiceProvider).deleteComment(comment, on: widget.post);
                              } on Object {
                                // Der nächste Abruf zeigt den Stand.
                              }
                              await _load();
                            },
                          )
                        : null,
                  ),
                if (_comments.isEmpty)
                  ListTile(
                    title: Text('Noch keine Kommentare.', style: TextStyle(color: secondary)),
                  ),
                if (_error case final error?)
                  ListTile(
                    title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.red)),
                  ),
              ],
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'Kommentar …', border: OutlineInputBorder()),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Senden',
                      icon: const Icon(Icons.send),
                      onPressed: _text.text.trim().isEmpty ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonLabel extends StatelessWidget {
  const _PersonLabel({required this.person});

  final SocialPerson person;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 10,
    children: [
      Avatar(person: person, size: 32),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(person.displayName, overflow: TextOverflow.ellipsis),
            Text(
              '@${person.username}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Freundesliste mit Suche, Anfragen und Einladung (Port von `FriendList`).
class FriendList extends ConsumerStatefulWidget {
  const FriendList({super.key});

  @override
  ConsumerState<FriendList> createState() => _FriendListState();
}

class _FriendListState extends ConsumerState<FriendList> {
  final _query = TextEditingController();
  List<SocialPerson> _results = const [];
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      setState(() {});
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), _search);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final results = await ref.read(socialServiceProvider).search(_query.text);
      if (mounted) {
        setState(() {
          _results = results;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _act(Future<void> Function() action, {bool researchAfter = false}) async {
    try {
      await action();
      if (researchAfter) await _search();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Widget _searchAction(SocialPerson person) {
    final social = ref.read(socialServiceProvider);
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return switch (person.relation ?? SocialRelation.none) {
      SocialRelation.friends => Text('Befreundet', style: secondary),
      SocialRelation.outgoing => Text('Angefragt', style: secondary),
      SocialRelation.incoming => TextButton(
        onPressed: () => _act(() => social.addFriend(person.username), researchAfter: true),
        child: const Text('Annehmen'),
      ),
      SocialRelation.blocked => TextButton(
        onPressed: () => _act(() => social.unblock(person.username), researchAfter: true),
        child: const Text('Entsperren'),
      ),
      SocialRelation.none || SocialRelation.me => FilledButton.icon(
        onPressed: () => _act(() => social.addFriend(person.username), researchAfter: true),
        icon: const Icon(Icons.person_add_alt, size: 18),
        label: const Text('Hinzufügen'),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialServiceProvider);
    final friends = social.friends;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return RefreshIndicator(
      onRefresh: social.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _query,
              autocorrect: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Benutzername suchen',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_query.text.isNotEmpty)
            FormSection(
              header: 'Suche',
              children: [
                if (_results.isEmpty)
                  ListTile(
                    title: Text(
                      'Niemand gefunden. Benutzernamen beginnen mit dem, was du tippst.',
                      style: TextStyle(color: secondary),
                    ),
                  ),
                for (final person in _results)
                  ListTile(
                    title: _PersonLabel(person: person),
                    trailing: _searchAction(person),
                  ),
              ],
            ),
          if (friends.incoming.isNotEmpty)
            FormSection(
              header: 'Anfragen an dich',
              children: [
                for (final person in friends.incoming)
                  ListTile(
                    title: _PersonLabel(person: person),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: () => _act(() => social.addFriend(person.username)),
                          child: const Text('Annehmen'),
                        ),
                        IconButton(
                          tooltip: 'Ablehnen',
                          icon: const Icon(Icons.close),
                          onPressed: () => _act(() => social.removeFriend(person.username)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          FormSection(
            header: 'Freunde (${friends.friends.length})',
            children: [
              if (friends.friends.isEmpty)
                ListTile(
                  title: Text(
                    'Noch keine Freunde. Suche oben nach einem Benutzernamen oder lade jemanden ein.',
                    style: TextStyle(color: secondary),
                  ),
                ),
              for (final person in friends.friends)
                ListTile(
                  title: _PersonLabel(person: person),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PersonScreen(username: person.username, displayName: person.displayName),
                    ),
                  ),
                ),
            ],
          ),
          if (friends.outgoing.isNotEmpty)
            FormSection(
              header: 'Gesendete Anfragen',
              children: [
                for (final person in friends.outgoing)
                  ListTile(
                    title: _PersonLabel(person: person),
                    trailing: TextButton(
                      onPressed: () => _act(() => social.removeFriend(person.username)),
                      child: const Text('Zurückziehen'),
                    ),
                  ),
              ],
            ),
          FormSection(
            footer:
                'Freunde sehen nur, was du ausdrücklich teilst – nie Gewicht, Puls, Schlaf oder andere Körperwerte.',
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Jemanden ohne Konto einladen'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountDetailScreen())),
              ),
            ],
          ),
          if (_error case final error?)
            ListTile(
              title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.red)),
            ),
        ],
      ),
    );
  }
}

/// Profil einer befreundeten Person mit ihren letzten Beiträgen (Port von `PersonView`).
class PersonScreen extends ConsumerStatefulWidget {
  const PersonScreen({super.key, required this.username, required this.displayName});

  final String username;
  final String displayName;

  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  SocialProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(socialServiceProvider)
        .profile(widget.username)
        .then(
          (profile) {
            if (mounted) setState(() => _profile = profile);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = _errorText(error));
          },
        );
  }

  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.displayName} sperren?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sperren', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await ref.read(socialServiceProvider).block(widget.username);
    } on Object {
      // Der nächste Abruf zeigt den Stand.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(widget.displayName)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            children: [
              ListTile(
                leading: Avatar(
                  person: SocialPerson(username: widget.username, displayName: widget.displayName),
                  size: 56,
                ),
                title: Text(
                  widget.displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('@${widget.username}'),
              ),
            ],
          ),
          if (profile != null)
            FormSection(
              header: 'Letzte Beiträge',
              children: [
                if (profile.posts.isEmpty)
                  ListTile(
                    title: Text('Noch nichts geteilt.', style: TextStyle(color: secondary)),
                  ),
                for (final post in profile.posts)
                  ListTile(
                    leading: Icon(postIcon(post)),
                    title: Text(post.headline, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        if (post.facts.isNotEmpty) post.facts,
                        if (post.date case final date?) SocialFormat.relative(date),
                      ].join('\n'),
                    ),
                  ),
              ],
            ),
          FormSection(
            footer:
                'Wer gesperrt ist, sieht deine Beiträge nicht und kann dir keine Anfragen schicken. Es gibt keine '
                'Mitteilung.',
            children: [
              ListTile(
                title: const Text('Freundschaft beenden', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  try {
                    await ref.read(socialServiceProvider).removeFriend(widget.username);
                  } on Object {
                    // Der nächste Abruf zeigt den Stand.
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              ListTile(
                title: const Text('Sperren', style: TextStyle(color: Colors.red)),
                onTap: _block,
              ),
            ],
          ),
          if (_error case final error?)
            ListTile(
              title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.red)),
            ),
        ],
      ),
    );
  }
}

/// Was geteilt wird.
sealed class ShareContent {
  const ShareContent();
}

final class ShareWorkout extends ShareContent {
  const ShareWorkout(this.workout);

  final WorkoutShare workout;
}

final class ShareMeal extends ShareContent {
  const ShareMeal(this.meal);

  final SharedMeal meal;
}

/// „Mit Freunden teilen“: kurze Notiz, Vorschau dessen, was geteilt wird, dann senden (Port von
/// `ShareWithFriendsSheet`).
class ShareWithFriendsScreen extends ConsumerStatefulWidget {
  const ShareWithFriendsScreen({super.key, required this.content, this.localKeys = const []});

  final ShareContent content;

  /// Schlüssel des eigenen Trainings (`SocialTimeline.keys`).
  final List<String> localKeys;

  @override
  ConsumerState<ShareWithFriendsScreen> createState() => _ShareWithFriendsScreenState();
}

class _ShareWithFriendsScreenState extends ConsumerState<ShareWithFriendsScreen> {
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final trimmed = _note.text.trim();
    final note = trimmed.isEmpty
        ? null
        : (trimmed.runes.length > 280 ? String.fromCharCodes(trimmed.runes.take(280)) : trimmed);
    final social = ref.read(socialServiceProvider);
    try {
      switch (widget.content) {
        case ShareWorkout(:final workout):
          workout.note = note;
          await social.shareWorkout(workout, localKeys: widget.localKeys);
        case ShareMeal(:final meal):
          await social.shareMeal(MealPostShare(meal: meal, note: note));
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  List<Widget> _preview() => switch (widget.content) {
    ShareWorkout(:final workout) => [
      LabeledRow(label: 'Training', value: workout.title),
      if (workout.durationMin case final minutes?) LabeledRow(label: 'Dauer', value: '$minutes min'),
      if (workout.distanceKm case final km?) LabeledRow(label: 'Strecke', value: '${GermanFormat.decimal(km)} km'),
      if (workout.elevationM case final up?) LabeledRow(label: 'Höhenmeter', value: '$up m'),
      if (workout.sets case final sets?) LabeledRow(label: 'Sätze', value: '$sets'),
      if (workout.exercises case final exercises?) ListTile(dense: true, title: Text(exercises.join(' · '))),
      for (final record in workout.records ?? const <String>[])
        ListTile(dense: true, leading: const Icon(Icons.emoji_events), title: Text(record)),
    ],
    ShareMeal(:final meal) => [
      LabeledRow(label: meal.title, value: '${meal.kilocalories.round()} kcal'),
      ListTile(
        dense: true,
        title: Text('${meal.items.length} Positionen mit Mengen und Nährwerten – deine Freunde können sie übernehmen.'),
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mit Freunden teilen'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
      ),
      body: social.isAvailable
          ? ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                FormSection(
                  header: 'Das sehen deine Freunde',
                  footer: 'Keine Körperwerte: Puls, Kalorienverbrauch, Gewicht und Schlaf bleiben auf deinem Gerät.',
                  children: _preview(),
                ),
                FormSection(
                  header: 'Notiz (optional)',
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _note,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'z. B. Endlich wieder unter 5 min/km!'),
                      ),
                    ),
                  ],
                ),
                FormSection(
                  footer: _error,
                  children: [
                    ListTile(
                      enabled: !_sending,
                      title: const Text('Teilen'),
                      textColor: Theme.of(context).colorScheme.primary,
                      trailing: _sending
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : null,
                      onTap: _send,
                    ),
                  ],
                ),
              ],
            )
          : const SignInPrompt(title: 'Konto nötig', text: 'Zum Teilen mit Freunden brauchst du ein Konto.'),
    );
  }
}

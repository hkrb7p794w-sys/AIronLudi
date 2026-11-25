part of 'social_views.dart';

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
                          Text(SocialFormat.relative(date), style: AppText.caption(context).copyWith(color: secondary)),
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
                    title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).alert)),
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
              style: AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    final secondary = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
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
                  trailing: const DisclosureChevron(),
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
                trailing: const DisclosureChevron(),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountDetailScreen())),
              ),
            ],
          ),
          if (_error case final error?)
            ListTile(
              title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).alert)),
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
            child: Text('Sperren', style: TextStyle(color: AppColors.of(context).alert)),
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
                title: Text('Freundschaft beenden', style: TextStyle(color: AppColors.of(context).alert)),
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
                title: Text('Sperren', style: TextStyle(color: AppColors.of(context).alert)),
                onTap: _block,
              ),
            ],
          ),
          if (_error case final error?)
            ListTile(
              title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).alert)),
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
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
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

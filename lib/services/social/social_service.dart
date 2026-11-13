import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/settings_store.dart';
import '../account/account_service.dart';
import '../ai/ai_client.dart';

/// Merkt, welches eigene Training zu welchem Beitrag gehört (nur auf diesem Gerät).
final class SharedPostStore {
  SharedPostStore(this._settings);

  static const key = SettingsKeys.socialSharedPosts;

  /// Ältere Zuordnungen fallen weg, damit die Liste nicht wächst.
  static const limit = 400;

  final SettingsStore _settings;

  Map<String, String> load() => _settings.read(
    key,
    (json) => json is Map && json.values.every((value) => value is String)
        ? {for (final MapEntry(:key, :value) in json.entries) '$key': value as String}
        : null,
    const <String, String>{},
  );

  Future<void> remember(List<String> localKeys, {required String post}) async {
    if (localKeys.isEmpty) return;
    var map = {...load()};
    if (map.length > limit) map = {};
    for (final localKey in localKeys) {
      map[localKey] = post;
    }
    await _settings.setJson(key, map);
  }
}

/// Profil einer anderen Person mit ihren Beiträgen.
final class SocialProfile {
  const SocialProfile({required this.username, required this.displayName, required this.relation, required this.posts});

  final String username;
  final String displayName;
  final SocialRelation relation;
  final List<SocialPost> posts;

  static SocialProfile? fromJson(Object? json) {
    if (json case {
      'username': final String username,
      'displayName': final String displayName,
      'relation': final String rawRelation,
      'posts': final List<Object?> rawPosts,
    }) {
      final relation = enumFromRaw(SocialRelation.values, rawRelation);
      final posts = rawPosts.map(SocialPost.fromJson).toList();
      if (relation == null || posts.contains(null)) return null;
      return SocialProfile(
        username: username,
        displayName: displayName,
        relation: relation,
        posts: posts.nonNulls.toList(),
      );
    }
    return null;
  }
}

/// Freunde und Feed über den Worker (`worker/src/social.ts`). Nur mit eigenem Konto; geteilt wird nur, was die Person
/// ausdrücklich teilt (Training ohne Körperwerte, Mahlzeit, Meilenstein).
final class SocialService extends ChangeNotifier {
  SocialService({required this._ai, required this._account, required this._sharedPosts});

  final AIClient _ai;
  final AccountService _account;
  final SharedPostStore _sharedPosts;

  SocialFriends friends = SocialFriends();
  List<SocialPost> feed = [];
  bool hasMore = true;
  bool isLoading = false;
  String? lastError;

  static const pageSize = 30;

  bool get isAvailable => _account.isSignedIn;
  int get incomingCount => friends.incoming.length;

  Future<T> _get<T>(String path, T? Function(Object? json) read, {Map<String, String> query = const {}}) async {
    final data = await _ai.send('v1/social/$path', method: 'GET', query: query, auth: AIAuth.session);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } on FormatException {
      throw AIClientError.network('Unerwartete Antwort des Workers.');
    }
    return read(json) ?? (throw AIClientError.network('Unerwartete Antwort des Workers.'));
  }

  Future<List<int>> _send(String path, {required String method, Object? body}) => _ai.send(
    'v1/social/$path',
    method: method,
    body: method == 'GET' ? null : utf8.encode(body == null ? '{}' : jsonEncode(body)),
    auth: AIAuth.session,
  );

  /// Wie `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`.
  static String escape(String username) => Uri.encodeComponent(username).replaceAll('%40', '@');

  static List<SocialPost>? _posts(Object? json, String key) {
    if (json is! Map || json[key] is! List) return null;
    final posts = (json[key] as List).map(SocialPost.fromJson).toList();
    return posts.contains(null) ? null : posts.nonNulls.toList();
  }

  static String _message(Object error) => error is AIClientError ? error.message : '$error';

  // Laden

  /// Freunde und erste Seite des Feeds.
  Future<void> refresh() async {
    if (!isAvailable || isLoading) return;
    isLoading = true;
    notifyListeners();
    try {
      friends = await _get('friends', SocialFriends.fromJson);
      final page = await _get('feed', (json) => _posts(json, 'posts'));
      feed = page;
      hasMore = page.length >= pageSize;
      lastError = null;
    } on Object catch (error) {
      lastError = _message(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final last = feed.isEmpty ? null : feed.last.date;
    if (!isAvailable || !hasMore || isLoading || last == null) return;
    isLoading = true;
    notifyListeners();
    try {
      final before = '${last.millisecondsSinceEpoch}';
      final page = await _get('feed', (json) => _posts(json, 'posts'), query: {'before': before});
      final known = {for (final post in feed) post.id};
      feed = [...feed, ...page.where((post) => !known.contains(post.id))];
      hasMore = page.length >= pageSize;
    } on Object catch (error) {
      lastError = _message(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<SocialPerson>> search(String text) async {
    final query = text.trim();
    if (query.runes.length < 2) return [];
    return _get('search', (json) {
      if (json is! Map || json['people'] is! List) return null;
      final people = (json['people'] as List).map(SocialPerson.fromJson).toList();
      return people.contains(null) ? null : people.nonNulls.toList();
    }, query: {'q': query});
  }

  Future<SocialProfile> profile(String username) => _get('people/${escape(username)}', SocialProfile.fromJson);

  // Freunde

  /// Anfragen oder eingehende Anfrage annehmen.
  Future<void> addFriend(String username) async {
    await _send('friends/${escape(username)}', method: 'POST');
    await refresh();
  }

  /// Entfernen, ablehnen oder eigene Anfrage zurückziehen.
  Future<void> removeFriend(String username) async {
    await _send('friends/${escape(username)}', method: 'DELETE');
    await refresh();
  }

  Future<void> block(String username) async {
    await _send('blocks/${escape(username)}', method: 'POST');
    await refresh();
  }

  Future<void> unblock(String username) => _send('blocks/${escape(username)}', method: 'DELETE');

  // Beiträge

  SocialPost _created(List<int> data) {
    final post = switch (_decode(data)) {
      {'post': final Object? raw} => SocialPost.fromJson(raw),
      _ => null,
    };
    return post ?? (throw AIClientError.network('Unerwartete Antwort des Workers.'));
  }

  static Object? _decode(List<int> data) {
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
  }

  /// [localKeys]: Schlüssel des eigenen Trainings (`SocialTimeline.keys`), damit es im Reiter „Aktivitäten“ nur einmal
  /// erscheint und nicht erneut automatisch geteilt wird.
  Future<SocialPost> shareWorkout(WorkoutShare workout, {List<String> localKeys = const []}) async {
    final post = _created(await _send('posts', method: 'POST', body: workout.toJson()));
    _insert(post);
    await _sharedPosts.remember(localKeys, post: post.id);
    return post;
  }

  Future<void> shareMeal(MealPostShare meal) async {
    _insert(_created(await _send('posts', method: 'POST', body: meal.toJson())));
  }

  void _insert(SocialPost post) {
    feed = [post, ...feed.where((other) => other.id != post.id)];
    notifyListeners();
  }

  Future<void> delete(SocialPost post) async {
    await _send('posts/${post.id}', method: 'DELETE');
    feed = feed.where((other) => other.id != post.id).toList();
    // Die Zuordnung bleibt: Ein gelöschter Beitrag soll nicht automatisch erneut geteilt werden.
    notifyListeners();
  }

  void _replace(String id, SocialPost Function(SocialPost post) change) {
    final index = feed.indexWhere((post) => post.id == id);
    if (index < 0) return;
    feed = [...feed]..[index] = change(feed[index]);
    notifyListeners();
  }

  /// Gleiche Reaktion nochmals: zurücknehmen. Der Feed zeigt die Änderung sofort.
  Future<void> react(SocialPost post, SocialReaction reaction) async {
    final index = feed.indexWhere((other) => other.id == post.id);
    if (index < 0) return;
    final previous = feed[index];
    final removing = previous.myReaction == reaction.rawValue;
    _replace(
      post.id,
      (current) => current.copyWith(
        myReaction: () => removing ? null : reaction.rawValue,
        reactions:
            current.reactions +
            (previous.myReaction == null
                ? 1
                : removing
                ? -1
                : 0),
      ),
    );
    try {
      if (removing) {
        await _send('posts/${post.id}/reaction', method: 'DELETE');
      } else {
        await _send('posts/${post.id}/reaction', method: 'PUT', body: {'emoji': reaction.rawValue});
      }
    } on Object catch (error) {
      _replace(post.id, (_) => previous);
      lastError = _message(error);
      notifyListeners();
    }
  }

  Future<List<SocialComment>> comments(SocialPost post) => _get('posts/${post.id}/comments', (json) {
    if (json is! Map || json['comments'] is! List) return null;
    final list = (json['comments'] as List).map(SocialComment.fromJson).toList();
    return list.contains(null) ? null : list.nonNulls.toList();
  });

  Future<void> comment(SocialPost post, String text) async {
    await _send('posts/${post.id}/comments', method: 'POST', body: {'text': text});
    _replace(post.id, (current) => current.copyWith(comments: current.comments + 1));
  }

  Future<void> deleteComment(SocialComment comment, {required SocialPost on}) async {
    await _send('comments/${comment.id}', method: 'DELETE');
    _replace(on.id, (current) => current.copyWith(comments: current.comments > 0 ? current.comments - 1 : 0));
  }
}

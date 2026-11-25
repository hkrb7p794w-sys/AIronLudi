// Nachgebauter Worker für Durchläufe: Konto, Freunde, Feed und Spiel im Speicher, mit den Antwortformaten, die die App
// erwartet (`AccountService`, `SocialService`, `GameService`). Andere Personen: Mia (schickt eine Freundschaftsanfrage)
// und Tom (findbar über die Suche).
import 'dart:convert';

import 'package:aironludi/services/http/http_transport.dart';

const fakeWorkerURL = 'https://worker.test';

final class FakeWorker {
  FakeWorker() {
    _users['mia'] = (id: 'u-mia', displayName: 'Mia', password: 'geheim-mia');
    _users['tom'] = (id: 'u-tom', displayName: 'Tom', password: 'geheim-tom');
    _requests.add(('mia', null)); // Mia fragt jede neu angelegte Person an (Empfänger beim Anlegen gesetzt).
    _posts.add({
      'id': 'p-mia-1',
      'kind': 'workout',
      'createdAt': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(),
      'author': 'mia',
      'payload': {'sport': 'running', 'title': 'Morgenlauf am See', 'note': 'Lief super!'},
    });
  }

  final _users = <String, ({String id, String displayName, String password})>{};
  final _sessions = <String, String>{};
  final _friends = <(String, String)>{};

  /// Offene Anfragen (von, an); `null` als Empfänger: wird beim ersten neuen Konto gesetzt.
  final _requests = <(String, String?)>[];
  final _posts = <Map<String, Object?>>[];
  final _reactions = <String, Map<String, String>>{};
  final _comments = <String, List<Map<String, Object?>>>{};
  final _challenges = <Map<String, Object?>>[];
  final requests = <String>[];

  /// Inhalte der geteilten Beiträge (Prüfung: keine Körperwerte).
  final postedBodies = <Map<String, Object?>>[];
  var _next = 0;

  late final transport = FakeHttpTransport(_handle);

  HttpResponse _json(Object body, {int status = 200}) => HttpResponse(status, utf8.encode(jsonEncode(body)));
  HttpResponse _error(int status, String message) => _json({'error': message}, status: status);

  Map<String, Object?> _account(String username) {
    final user = _users[username]!;
    return {'id': user.id, 'username': username, 'displayName': user.displayName, 'isAdmin': false};
  }

  Map<String, Object?> _person(String username, String me) {
    final relation = username == me
        ? 'self'
        : _friends.contains(_pair(me, username))
        ? 'friends'
        : _requests.contains((username, me))
        ? 'incoming'
        : _requests.contains((me, username))
        ? 'outgoing'
        : 'none';
    return {'username': username, 'displayName': _users[username]!.displayName, 'relation': relation};
  }

  (String, String) _pair(String a, String b) => a.compareTo(b) < 0 ? (a, b) : (b, a);

  Map<String, Object?> _post(Map<String, Object?> post, String me) {
    final reactions = _reactions[post['id']] ?? const {};
    return {
      'id': post['id'],
      'kind': post['kind'],
      'createdAt': post['createdAt'],
      'author': _person(post['author']! as String, me),
      'mine': post['author'] == me,
      'payload': post['payload'],
      'reactions': reactions.length,
      'myReaction': ?reactions[me],
      'topReactions': reactions.values.toSet().join(),
      'comments': (_comments[post['id']] ?? const []).length,
    };
  }

  HttpResponse _handle(HttpRequest request) {
    final path = request.url.path.replaceFirst(RegExp('^/'), '');
    requests.add('${request.method} $path');
    final body = request.body == null || request.body!.isEmpty
        ? const <String, Object?>{}
        : (jsonDecode(utf8.decode(request.body!)) as Map).cast<String, Object?>();
    final token = request.headers['Authorization']?.replaceFirst('Bearer ', '');
    final me = token == null ? null : _sessions[token];
    final now = DateTime.now().toUtc().toIso8601String();

    if (path == 'v1/health') return _json({'ok': true});

    // Konto
    if (path == 'v1/account/register' && request.method == 'POST') {
      final username = body['username']! as String;
      if (_users.containsKey(username)) return _error(409, 'Dieser Benutzername ist schon vergeben.');
      _users[username] = (
        id: 'u-$username',
        displayName: (body['displayName'] as String?)?.isNotEmpty ?? false ? body['displayName']! as String : username,
        password: body['password']! as String,
      );
      for (var i = 0; i < _requests.length; i++) {
        if (_requests[i].$2 == null) _requests[i] = (_requests[i].$1, username);
      }
      return _session(username, recovery: 'ABCD-EFGH-IJKL');
    }
    if (path == 'v1/account/login' && request.method == 'POST') {
      final username = body['username']! as String;
      if (_users[username]?.password != body['password']) {
        return _error(401, 'Benutzername oder Passwort stimmt nicht.');
      }
      return _session(username);
    }
    if (me == null) return _error(401, 'Bitte neu anmelden.');
    switch ((request.method, path)) {
      case ('GET', 'v1/account/me'):
        return _json({
          'account': _account(me),
          'sessions': [
            {'device': 'Test', 'createdAt': now, 'lastUsed': now, 'current': true},
          ],
        });
      case ('GET', 'v1/account/invites'):
        return _json({'invites': const <Object>[]});
      case ('POST', 'v1/account/invites'):
        return _json({'code': 'EINLADUNG1', 'expiresAt': now});
      case ('POST', 'v1/account/logout'):
        _sessions.remove(token);
        return _json(const {});
      case ('PUT' || 'POST', 'v1/account/profile'):
        final user = _users[me]!;
        _users[me] = (id: user.id, displayName: body['displayName']! as String, password: user.password);
        return _json({'account': _account(me)});
    }

    // Freunde und Feed
    if (path.startsWith('v1/social/')) return _social(request.method, path.substring(10), request.url, body, me, now);

    // Spiel
    switch ((request.method, path)) {
      case ('PUT', 'v1/game/score'):
        return _json(const {});
      case ('GET', 'v1/game/leaderboard'):
        final people = [me, ..._users.keys.where((name) => _friends.contains(_pair(me, name)))];
        return _json({
          'entries': [
            for (final (index, name) in people.indexed)
              {
                'rank': index + 1,
                'username': name,
                'displayName': _users[name]!.displayName,
                'me': name == me,
                'weekPoints': 40 - index * 5,
                'totalPoints': 300 - index * 20,
                'streak': 2,
                'dayStreak': 3,
                'level': 4,
                'reported': true,
              },
          ],
        });
      case ('GET', 'v1/game/challenges'):
        return _json({
          'challenges': [for (final challenge in _challenges) _challenge(challenge, me)],
        });
      case ('POST', 'v1/game/challenges'):
        final challenge = {
          'id': 'c${_next++}',
          'title': body['title'],
          'metric': body['metric'],
          'week': body['week'],
          'creator': me,
          'members': [me, ...(body['invite'] as List? ?? const []).cast<String>()],
        };
        _challenges.add(challenge);
        return _json({'challenge': _challenge(challenge, me)});
    }
    final challengeID = RegExp(r'^v1/game/challenges/([^/]+)(/.*)?$').firstMatch(path);
    if (challengeID != null) {
      final id = challengeID.group(1);
      if (request.method == 'DELETE') _challenges.removeWhere((challenge) => challenge['id'] == id);
      return _json(const {});
    }
    return _error(404, 'Nicht gefunden: ${request.method} $path');
  }

  HttpResponse _session(String username, {String? recovery}) {
    final token = 'token-${_next++}';
    _sessions[token] = username;
    return _json({'token': token, 'account': _account(username), 'recoveryCode': ?recovery});
  }

  Map<String, Object?> _challenge(Map<String, Object?> challenge, String me) => {
    'id': challenge['id'],
    'title': challenge['title'],
    'metric': challenge['metric'],
    'metricTitle': 'Trainingstage',
    'max': 7,
    'week': challenge['week'],
    'finished': false,
    // Stand der anfragenden Person: angelegt bzw. angenommen = joined, eingeladen = invited.
    'status': challenge['creator'] == me ? 'joined' : 'invited',
    'mineCreated': challenge['creator'] == me,
    'members': [
      for (final name in (challenge['members']! as List).cast<String>())
        {
          'username': name,
          'displayName': _users[name]?.displayName ?? name,
          'status': name == challenge['creator'] ? 'joined' : 'invited',
          'progress': 0.0,
          'me': name == me,
          'winner': false,
        },
    ],
  };

  HttpResponse _social(String method, String path, Uri url, Map<String, Object?> body, String me, String now) {
    final segments = path.split('/').map(Uri.decodeComponent).toList();
    switch ((method, segments)) {
      case ('GET', ['friends']):
        return _json({
          'friends': [
            for (final (a, b) in _friends)
              if (a == me || b == me) _person(a == me ? b : a, me),
          ],
          'incoming': [
            for (final (from, to) in _requests)
              if (to == me) _person(from, me),
          ],
          'outgoing': [
            for (final (from, to) in _requests)
              if (from == me && to != null) _person(to, me),
          ],
        });
      case ('GET', ['feed']):
        final visible = _posts.where(
          (post) => post['author'] == me || _friends.contains(_pair(me, post['author']! as String)),
        );
        return _json({
          'posts': [for (final post in visible.toList().reversed) _post(post, me)],
        });
      case ('GET', ['search']):
        final query = (url.queryParameters['q'] ?? '').toLowerCase();
        return _json({
          'people': [
            for (final name in _users.keys)
              if (name != me && (name.contains(query) || _users[name]!.displayName.toLowerCase().contains(query)))
                _person(name, me),
          ],
        });
      case ('POST', ['friends', final other]):
        if (_requests.remove((other, me))) {
          _friends.add(_pair(me, other));
        } else {
          _requests.add((me, other));
        }
        return _json(const {});
      case ('DELETE', ['friends', final other]):
        _friends.remove(_pair(me, other));
        _requests
          ..remove((me, other))
          ..remove((other, me));
        return _json(const {});
      case ('POST', ['posts']):
        postedBodies.add(body);
        final post = {
          'id': 'p${_next++}',
          'kind': body['kind'] ?? (body.containsKey('meal') ? 'meal' : 'workout'),
          'createdAt': now,
          'author': me,
          'payload': body,
        };
        _posts.add(post);
        return _json({'post': _post(post, me)});
      case ('DELETE', ['posts', final id]):
        _posts.removeWhere((post) => post['id'] == id);
        return _json(const {});
      case ('PUT', ['posts', final id, 'reaction']):
        (_reactions[id] ??= {})[me] = body['emoji']! as String;
        return _json(const {});
      case ('DELETE', ['posts', final id, 'reaction']):
        _reactions[id]?.remove(me);
        return _json(const {});
      case ('GET', ['posts', final id, 'comments']):
        return _json({
          'comments': [
            for (final comment in _comments[id] ?? const <Map<String, Object?>>[])
              {
                'id': comment['id'],
                'text': comment['text'],
                'createdAt': comment['createdAt'],
                'author': _person(comment['author']! as String, me),
                'canDelete': comment['author'] == me,
              },
          ],
        });
      case ('POST', ['posts', final id, 'comments']):
        (_comments[id] ??= []).add({'id': 'k${_next++}', 'text': body['text'], 'createdAt': now, 'author': me});
        return _json(const {});
      case ('DELETE', ['comments', final id]):
        for (final list in _comments.values) {
          list.removeWhere((comment) => comment['id'] == id);
        }
        return _json(const {});
    }
    return _error(404, 'Nicht gefunden: $method social/$path');
  }
}

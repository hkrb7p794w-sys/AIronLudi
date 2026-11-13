// Social- und Spiel-Dienst gegen einen nachgebildeten Worker.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/account/account_service.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/social/game_service.dart';
import 'package:aironludi/services/social/social_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> post(String id, {String? myReaction, int reactions = 0}) => {
  'id': id,
  'kind': 'workout',
  'createdAt': '2026-11-1${id.length}T08:00:00.000Z',
  'author': {'username': 'lena', 'displayName': 'Lena'},
  'mine': false,
  'payload': {'sport': 'run', 'title': 'Lauf'},
  'reactions': reactions,
  'myReaction': myReaction,
  'topReactions': '',
  'comments': 0,
};

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late (int, Object?) Function(HttpRequest request) handler;
  late FakeHttpTransport transport;
  late AccountService account;
  late AIClient ai;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    handler = (_) => (200, <String, Object?>{});
    transport = FakeHttpTransport((request) {
      final (status, body) = handler(request);
      return HttpResponse(status, utf8.encode(jsonEncode(body)));
    });
    ai = AIClient(
      secrets: Secrets.memory({SecretKey.accountSession: 's1.x'}),
      settings: settings,
      transport: transport,
    );
    await settings.setString(SettingsKeys.workerURL, 'https://w.example');
    await settings.setJson(SettingsKeys.accountProfile, {
      'id': 'a',
      'username': 'ich',
      'displayName': 'Ich',
      'isAdmin': false,
    });
    account = AccountService(ai: ai, settings: settings, device: 'Test');
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  test('Reaktion sofort sichtbar, bei Fehler zurückgenommen', () async {
    final social = SocialService(ai: ai, account: account, sharedPosts: SharedPostStore(settings));
    handler = (request) => switch (request.url.path) {
      '/v1/social/friends' => (200, {'friends': <Object?>[], 'incoming': <Object?>[], 'outgoing': <Object?>[]}),
      '/v1/social/feed' => (
        200,
        {
          'posts': [post('p1')],
        },
      ),
      _ => (500, {'error': 'kaputt'}),
    };
    await social.refresh();
    expect(social.feed.single.id, 'p1');
    expect(social.hasMore, isFalse);
    await social.react(social.feed.single, SocialReaction.values.first);
    expect(social.feed.single.reactions, 0);
    expect(social.feed.single.myReaction, isNull);
    expect(social.lastError, isNotNull);

    handler = (_) => (200, <String, Object?>{});
    await social.react(social.feed.single, SocialReaction.values.first);
    expect(social.feed.single.reactions, 1);
    expect(social.feed.single.myReaction, SocialReaction.values.first.rawValue);
    expect(transport.requests.last.method, 'PUT');
  });

  test('Beitrag teilen merkt das eigene Training', () async {
    final store = SharedPostStore(settings);
    final social = SocialService(ai: ai, account: account, sharedPosts: store);
    handler = (_) => (200, {'post': post('neu')});
    final created = await social.shareWorkout(
      WorkoutShare(sport: 'run', title: 'Lauf'),
      localKeys: ['activity:7'],
    );
    expect(created.id, 'neu');
    expect(social.feed.first.id, 'neu');
    expect(store.load(), {'activity:7': 'neu'});
  });

  test('Spielstand wird nur bei Änderung gemeldet', () async {
    final game = GameService(ai: ai, account: account);
    handler = (request) => switch (request.url.path) {
      '/v1/game/leaderboard' => (200, {'entries': <Object?>[]}),
      '/v1/game/challenges' => (200, {'challenges': <Object?>[]}),
      _ => (200, <String, Object?>{}),
    };
    const today = CalendarDay(2026, 11, 13);
    final week = WeekAdherence(monday: PlanAdjustments.monday(today), days: const []);
    final summary = MotivationSummary(week: week, weekPoints: 10, totalPoints: 40, streak: 1, level: 2);
    const streak = DailyStreak(current: 3, best: 5, jokerDays: [], activeToday: true);
    final inputs = GameInputs(today: today, minutesByDay: const {}, mealDays: const {}, adherence: week);
    await game.report(summary: summary, streak: streak, inputs: inputs);
    final score = transport.requests.firstWhere((request) => request.url.path == '/v1/game/score');
    expect(jsonDecode(utf8.decode(score.body!)), containsPair('dayStreak', 3));
    final count = transport.requests.length;
    await game.report(summary: summary, streak: streak, inputs: inputs);
    expect(transport.requests, hasLength(count));
    expect(game.lastError, isNull);
  });
}

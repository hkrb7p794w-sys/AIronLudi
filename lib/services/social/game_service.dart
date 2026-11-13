import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../account/account_service.dart';
import '../ai/ai_client.dart';

/// Zuletzt auf „Heute“ berechneter Stand (Serie, Stufe, Abzeichen), damit „Wettkampf“ ihn ohne Neuberechnung zeigt.
final class GameSnapshot {
  const GameSnapshot({required this.streak, required this.summary, required this.stats});

  final DailyStreak streak;
  final MotivationSummary summary;
  final GameStats stats;
}

/// Eingaben für Challenges der laufenden Woche.
final class GameInputs {
  const GameInputs({required this.today, required this.minutesByDay, required this.mealDays, required this.adherence});

  final CalendarDay today;
  final Map<CalendarDay, int> minutesByDay;
  final Set<CalendarDay> mealDays;
  final WeekAdherence adherence;
}

/// Rangliste und Challenges unter Freunden (`worker/src/game.ts`). Die Werte rechnet die App mit denselben Regeln wie
/// Begleiter und Plan; der Worker begrenzt sie (Übertraining bringt keine Punkte).
final class GameService extends ChangeNotifier {
  GameService({required this._ai, required this._account});

  final AIClient _ai;
  final AccountService _account;

  List<LeaderboardEntry> leaderboard = [];
  List<Challenge> challenges = [];
  String? lastError;
  GameSnapshot? snapshot;
  String? _lastReported;

  bool get isAvailable => _account.isSignedIn;
  int get challengesWon => challenges.where((challenge) => challenge.iWon).length;
  List<Challenge> get invitations =>
      challenges.where((challenge) => challenge.status == 'invited' && !challenge.finished).toList();

  static List<T>? _list<T extends Object>(List<int> data, String key, T? Function(Object? json) read) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
    if (json is! Map || json[key] is! List) return null;
    final items = <T?>[for (final item in json[key] as List) read(item)];
    return items.contains(null) ? null : items.nonNulls.toList();
  }

  static Never _unexpected() => throw AIClientError.network('Unerwartete Antwort des Workers.');

  static String _message(Object error) => error is AIClientError ? error.message : '$error';

  Future<void> refresh() async {
    if (!isAvailable) return;
    try {
      final board = await _ai.send('v1/game/leaderboard', method: 'GET', auth: AIAuth.session);
      leaderboard = _list(board, 'entries', LeaderboardEntry.fromJson) ?? _unexpected();
      final list = await _ai.send('v1/game/challenges', method: 'GET', auth: AIAuth.session);
      challenges = _list(list, 'challenges', Challenge.fromJson) ?? _unexpected();
      lastError = null;
    } on Object catch (error) {
      lastError = _message(error);
    }
    notifyListeners();
  }

  /// Eigenen Stand melden (nur bei Änderung) und laufende Challenges aktualisieren.
  Future<void> report({
    required MotivationSummary summary,
    required DailyStreak streak,
    required GameInputs inputs,
  }) async {
    if (!isAvailable) return;
    final monday = PlanAdjustments.monday(inputs.today);
    final values = <(String, int)>[
      for (final challenge in challenges)
        if (challenge.status == 'joined' && !challenge.finished)
          if ((challenge.kind, challenge.monday) case (final metric?, final week?) when week == monday)
            (
              challenge.id,
              metric.value(
                monday: week,
                today: inputs.today,
                minutesByDay: inputs.minutesByDay,
                mealDays: inputs.mealDays,
                adherence: inputs.adherence,
              ),
            ),
    ];
    final key = '${monday.iso}-${summary.weekPoints}-${summary.totalPoints}-${streak.current}-$values';
    if (key == _lastReported) return;
    try {
      final score = {
        'week': monday.iso,
        'weekPoints': summary.weekPoints,
        'totalPoints': summary.totalPoints,
        'streak': summary.streak,
        'dayStreak': streak.current,
        'level': summary.level,
      };
      await _ai.send('v1/game/score', method: 'PUT', body: utf8.encode(jsonEncode(score)), auth: AIAuth.session);
      for (final (id, value) in values) {
        await _ai.send(
          'v1/game/challenges/$id/progress',
          method: 'PUT',
          body: utf8.encode(jsonEncode({'value': value})),
          auth: AIAuth.session,
        );
      }
      _lastReported = key;
      await refresh();
    } on Object catch (error) {
      lastError = _message(error);
      notifyListeners();
    }
  }

  Future<void> create({
    required ChallengeMetric metric,
    required CalendarDay week,
    required String title,
    required List<String> invite,
  }) async {
    final body = {'metric': metric.rawValue, 'week': week.iso, 'title': title, 'invite': invite};
    final data = await _ai.send(
      'v1/game/challenges',
      method: 'POST',
      body: utf8.encode(jsonEncode(body)),
      auth: AIAuth.session,
    );
    final created = switch (_decode(data)) {
      {'challenge': final Object? raw} => Challenge.fromJson(raw),
      _ => null,
    };
    if (created == null) _unexpected();
    challenges = [created, ...challenges];
    _lastReported = null;
    notifyListeners();
  }

  static Object? _decode(List<int> data) {
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
  }

  Future<void> join(Challenge challenge) async {
    try {
      await _ai.send(
        'v1/game/challenges/${challenge.id}/join',
        method: 'POST',
        body: utf8.encode('{}'),
        auth: AIAuth.session,
      );
      _lastReported = null;
      await refresh();
    } on Object catch (error) {
      lastError = _message(error);
      notifyListeners();
    }
  }

  Future<void> leave(Challenge challenge) async {
    try {
      await _ai.send('v1/game/challenges/${challenge.id}', method: 'DELETE', auth: AIAuth.session);
      challenges = challenges.where((other) => other.id != challenge.id).toList();
    } on Object catch (error) {
      lastError = _message(error);
    }
    notifyListeners();
  }
}

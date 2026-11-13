import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../motivation/adherence.dart';
import '../profile/plan_adjustments.dart';
import '../util/enum_codec.dart';

/// Tages-Serie: Tage in Folge mit etwas Erfasstem (Training oder Mahlzeit). Ein Joker je Woche überbrückt einen
/// fehlenden Tag, damit ein Ruhetag oder ein voller Tag die Serie nicht gleich beendet – Pausen sollen sich nicht wie
/// Versagen anfühlen. Heute zählt erst, wenn etwas erfasst ist; bis dahin läuft die Serie von gestern weiter.
final class DailyStreak {
  const DailyStreak({required this.current, required this.best, required this.jokerDays, required this.activeToday});

  final int current;
  final int best;

  /// Mit Joker überbrückte Tage der laufenden Serie.
  final List<CalendarDay> jokerDays;

  /// Ist heute schon etwas erfasst?
  final bool activeToday;

  static const jokersPerWeek = 1;

  /// [jokers]: fehlende Tage, die je Woche überbrückt werden; 0 zählt nur lückenlose Tage.
  static DailyStreak compute({
    required Set<CalendarDay> activeDays,
    required CalendarDay today,
    int lookback = 400,
    int jokers = jokersPerWeek,
  }) {
    final activeToday = activeDays.contains(today);
    final current = _run(
      activeToday ? today : today.adding(-1),
      activeDays: activeDays,
      limit: lookback,
      allowed: jokers,
    );
    // Beste Serie: jede Serie, die an einem aktiven Tag endet (vorwärts betrachtet).
    var best = current.length;
    final earliest = today.adding(-lookback);
    final sorted = activeDays.where((day) => day <= today && day >= earliest).toList()..sort();
    for (final day in sorted) {
      if (activeDays.contains(day.adding(1))) continue;
      best = math.max(best, _run(day, activeDays: activeDays, limit: lookback, allowed: jokers).length);
    }
    return DailyStreak(current: current.length, best: best, jokerDays: current.jokers, activeToday: activeToday);
  }

  /// Rückwärts ab [start]: aktive Tage zählen, je Woche (Montag bis Sonntag) ein fehlender Tag per Joker.
  /// Ein Joker gilt nur zwischen zwei aktiven Tagen; die Serie beginnt und endet mit einem aktiven Tag.
  static ({int length, List<CalendarDay> jokers}) _run(
    CalendarDay start, {
    required Set<CalendarDay> activeDays,
    required int limit,
    required int allowed,
  }) {
    var day = start;
    var length = 0;
    final jokers = <CalendarDay>[];
    final usedInWeek = <CalendarDay, int>{};
    var steps = 0;
    while (steps < limit) {
      steps += 1;
      if (activeDays.contains(day)) {
        length += 1;
      } else {
        final monday = PlanAdjustments.monday(day);
        final used = usedInWeek[monday] ?? 0;
        if (length <= 0 || used >= allowed || !activeDays.contains(day.adding(-1))) break;
        usedInWeek[monday] = used + 1;
        jokers.add(day);
        length += 1;
      }
      day = day.adding(-1);
    }
    return (length: length, jokers: jokers);
  }
}

/// Was für Abzeichen zählt (alles auf dem Gerät berechnet).
final class GameStats {
  GameStats();

  int workouts = 0;
  int bestDayStreak = 0;

  /// Abgeschlossene Wochen in Folge mit mindestens 80 % des Plans (`ScoreRules.streak`).
  int planWeekStreak = 0;
  int mealDays = 0;
  int friends = 0;
  int challengesWon = 0;
  int level = 0;
}

enum BadgeMetric { workouts, dayStreak, planWeeks, mealDays, friends, challengesWon, level }

/// Abzeichen für Beständigkeit, nicht für Menge: kein Abzeichen für mehr Training als geplant, für Kaloriendefizit
/// oder Gewichtsverlust (Schutzgrenzen aus `GoalRules` bleiben unberührt).
final class Badge {
  const Badge({
    required this.id,
    required this.title,
    required this.detail,
    required this.symbol,
    required this.target,
    required this.metric,
  });

  final String id;
  final String title;
  final String detail;
  final String symbol;
  final int target;
  final BadgeMetric metric;

  int value(GameStats stats) => switch (metric) {
    BadgeMetric.workouts => stats.workouts,
    BadgeMetric.dayStreak => stats.bestDayStreak,
    BadgeMetric.planWeeks => stats.planWeekStreak,
    BadgeMetric.mealDays => stats.mealDays,
    BadgeMetric.friends => stats.friends,
    BadgeMetric.challengesWon => stats.challengesWon,
    BadgeMetric.level => stats.level,
  };

  int progress(GameStats stats) => math.min(value(stats), target);
  bool isEarned(GameStats stats) => value(stats) >= target;

  @override
  String toString() => 'Badge($id)';
}

abstract final class BadgeRules {
  static const all = [
    Badge(
      id: 'workout.1',
      title: 'Los geht’s',
      detail: 'Erstes Training erfasst',
      symbol: 'figure.run',
      target: 1,
      metric: BadgeMetric.workouts,
    ),
    Badge(
      id: 'workout.10',
      title: 'Dranbleiber',
      detail: '10 Trainings',
      symbol: 'flame',
      target: 10,
      metric: BadgeMetric.workouts,
    ),
    Badge(
      id: 'workout.50',
      title: 'Gewohnheit',
      detail: '50 Trainings',
      symbol: 'flame.fill',
      target: 50,
      metric: BadgeMetric.workouts,
    ),
    Badge(
      id: 'workout.100',
      title: 'Hundert',
      detail: '100 Trainings',
      symbol: 'medal.fill',
      target: 100,
      metric: BadgeMetric.workouts,
    ),
    Badge(
      id: 'streak.7',
      title: 'Eine Woche',
      detail: '7 Tage in Folge etwas erfasst',
      symbol: 'calendar',
      target: 7,
      metric: BadgeMetric.dayStreak,
    ),
    Badge(
      id: 'streak.30',
      title: 'Ein Monat',
      detail: '30 Tage in Folge',
      symbol: 'calendar.badge.checkmark',
      target: 30,
      metric: BadgeMetric.dayStreak,
    ),
    Badge(
      id: 'streak.100',
      title: 'Hundert Tage',
      detail: '100 Tage in Folge',
      symbol: 'star.circle.fill',
      target: 100,
      metric: BadgeMetric.dayStreak,
    ),
    Badge(
      id: 'plan.1',
      title: 'Plan erfüllt',
      detail: 'Eine Woche mit mindestens 80 % des Plans',
      symbol: 'checkmark.seal',
      target: 1,
      metric: BadgeMetric.planWeeks,
    ),
    Badge(
      id: 'plan.4',
      title: 'Vier Wochen stark',
      detail: '4 Wochen in Folge nach Plan',
      symbol: 'checkmark.seal.fill',
      target: 4,
      metric: BadgeMetric.planWeeks,
    ),
    Badge(
      id: 'plan.12',
      title: 'Ein Block',
      detail: '12 Wochen in Folge nach Plan',
      symbol: 'rosette',
      target: 12,
      metric: BadgeMetric.planWeeks,
    ),
    Badge(
      id: 'meals.7',
      title: 'Tagebuch',
      detail: 'An 7 Tagen Essen erfasst',
      symbol: 'fork.knife',
      target: 7,
      metric: BadgeMetric.mealDays,
    ),
    Badge(
      id: 'meals.30',
      title: 'Ernährungsprofi',
      detail: 'An 30 Tagen Essen erfasst',
      symbol: 'fork.knife.circle.fill',
      target: 30,
      metric: BadgeMetric.mealDays,
    ),
    Badge(
      id: 'friends.1',
      title: 'Gemeinsam',
      detail: 'Erste Freundschaft',
      symbol: 'person.2',
      target: 1,
      metric: BadgeMetric.friends,
    ),
    Badge(
      id: 'friends.5',
      title: 'Team',
      detail: '5 Freunde',
      symbol: 'person.3.fill',
      target: 5,
      metric: BadgeMetric.friends,
    ),
    Badge(
      id: 'challenge.1',
      title: 'Gewonnen!',
      detail: 'Erste Challenge gewonnen',
      symbol: 'trophy',
      target: 1,
      metric: BadgeMetric.challengesWon,
    ),
    Badge(
      id: 'challenge.5',
      title: 'Seriensieger',
      detail: '5 Challenges gewonnen',
      symbol: 'trophy.fill',
      target: 5,
      metric: BadgeMetric.challengesWon,
    ),
    Badge(
      id: 'level.5',
      title: 'Stufe 5',
      detail: 'Stufe 5 erreicht',
      symbol: '5.circle.fill',
      target: 5,
      metric: BadgeMetric.level,
    ),
    Badge(
      id: 'level.10',
      title: 'Stufe 10',
      detail: 'Stufe 10 erreicht',
      symbol: '10.circle.fill',
      target: 10,
      metric: BadgeMetric.level,
    ),
  ];

  static List<Badge> earned(GameStats stats) => all.where((badge) => badge.isEarned(stats)).toList();

  /// Das nächste erreichbare Abzeichen: das mit dem größten Anteil am Ziel, das noch fehlt.
  static Badge? next(GameStats stats) {
    Badge? best;
    double share(Badge badge) => badge.progress(stats) / badge.target;
    for (final badge in all.where((badge) => !badge.isEarned(stats))) {
      // Wie `max(by:)` in Swift: bei Gleichstand das erste.
      if (best == null || share(best) < share(badge)) best = badge;
    }
    return best;
  }
}

/// Stufe aus den Punkten der Planerfüllung (`ScoreRules.level`, alle 100 Punkte eine Stufe).
abstract final class GameLevel {
  static ({int level, int inLevel, int perLevel}) progress(int totalPoints) =>
      (level: ScoreRules.level(totalPoints), inLevel: math.max(totalPoints, 0) % 100, perLevel: 100);
}

/// Messgrößen der Challenges, gleich wie im Worker (`METRICS` in game.ts). Immer eine Kalenderwoche.
enum ChallengeMetric implements RawEnum {
  plan('Plan erfüllt', '%', 'Anteil deines eigenen Plans – wer wenig plant, kann genauso gewinnen.', 100),
  sessions('Trainingstage', 'Tage', 'Höchstens ein Trainingstag pro Tag zählt.', 7),
  minutes('Trainingsminuten', 'min', 'Höchstens 90 Minuten am Tag zählen – Übertraining bringt nichts.', 7 * 90),
  meals('Tage mit Ernährungstagebuch', 'Tage', 'Ein Tag zählt, sobald eine Mahlzeit erfasst ist.', 7);

  const ChallengeMetric(this.title, this.unit, this.rule, this.max);

  final String title;
  final String unit;

  /// Warum diese Grenze: Mehr als geplant bringt keine Punkte.
  final String rule;
  final int max;

  @override
  String get rawValue => name;

  String get id => rawValue;

  /// Wert für die Woche ab [monday] (bis einschließlich [today]).
  int value({
    required CalendarDay monday,
    required CalendarDay today,
    required Map<CalendarDay, int> minutesByDay,
    required Set<CalendarDay> mealDays,
    required WeekAdherence? adherence,
  }) {
    final days = [for (var offset = 0; offset < 7; offset++) monday.adding(offset)].where((day) => day <= today);
    return switch (this) {
      plan =>
        adherence == null || adherence.planned <= 0
            ? 0
            : math.min(100, (adherence.done / adherence.planned * 100).round()),
      sessions => days.where((day) => (minutesByDay[day] ?? 0) > 0).length,
      minutes => days.fold(0, (sum, day) => sum + math.min(minutesByDay[day] ?? 0, 90)),
      meals => days.where(mealDays.contains).length,
    };
  }
}

bool? _bool(Object? value) => value is bool ? value : null;

/// Eintrag der Freundes-Rangliste (`GET /v1/game/leaderboard`).
final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.username,
    required this.displayName,
    required this.me,
    required this.weekPoints,
    required this.totalPoints,
    required this.streak,
    required this.dayStreak,
    required this.level,
    required this.reported,
  });

  final int rank;
  final String username;
  final String displayName;
  final bool me;
  final int weekPoints;
  final int totalPoints;
  final int streak;
  final int dayStreak;
  final int level;
  final bool reported;

  String get id => username;

  Map<String, Object?> toJson() => {
    'rank': rank,
    'username': username,
    'displayName': displayName,
    'me': me,
    'weekPoints': weekPoints,
    'totalPoints': totalPoints,
    'streak': streak,
    'dayStreak': dayStreak,
    'level': level,
    'reported': reported,
  };

  static LeaderboardEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final ints = [
      for (final key in const ['rank', 'weekPoints', 'totalPoints', 'streak', 'dayStreak', 'level']) json[key],
    ];
    final (username, displayName, me, reported) = (
      json['username'],
      json['displayName'],
      _bool(json['me']),
      _bool(json['reported']),
    );
    if (ints.any((value) => value is! int) ||
        username is! String ||
        displayName is! String ||
        me == null ||
        reported == null) {
      return null;
    }
    return LeaderboardEntry(
      rank: ints[0]! as int,
      username: username,
      displayName: displayName,
      me: me,
      weekPoints: ints[1]! as int,
      totalPoints: ints[2]! as int,
      streak: ints[3]! as int,
      dayStreak: ints[4]! as int,
      level: ints[5]! as int,
      reported: reported,
    );
  }
}

/// Teilnehmer einer Challenge.
final class ChallengeMember {
  const ChallengeMember({
    required this.username,
    required this.displayName,
    required this.status,
    required this.progress,
    required this.me,
    required this.winner,
  });

  final String username;
  final String displayName;
  final String status;
  final double progress;
  final bool me;
  final bool winner;

  String get id => username;

  Map<String, Object?> toJson() => {
    'username': username,
    'displayName': displayName,
    'status': status,
    'progress': progress,
    'me': me,
    'winner': winner,
  };

  static ChallengeMember? fromJson(Object? json) {
    if (json is! Map) return null;
    final (username, displayName, status, progress) = (
      json['username'],
      json['displayName'],
      json['status'],
      json['progress'],
    );
    final (me, winner) = (_bool(json['me']), _bool(json['winner']));
    if (username is! String ||
        displayName is! String ||
        status is! String ||
        progress is! num ||
        me == null ||
        winner == null) {
      return null;
    }
    return ChallengeMember(
      username: username,
      displayName: displayName,
      status: status,
      progress: progress.toDouble(),
      me: me,
      winner: winner,
    );
  }
}

final class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.metric,
    required this.metricTitle,
    required this.max,
    required this.week,
    required this.finished,
    required this.status,
    required this.mineCreated,
    required this.members,
  });

  final String id;
  final String title;
  final String metric;
  final String metricTitle;
  final int max;
  final String week;
  final bool finished;

  /// `joined`, `invited` oder `none`.
  final String status;
  final bool mineCreated;
  final List<ChallengeMember> members;

  ChallengeMetric? get kind => enumFromRaw(ChallengeMetric.values, metric);
  CalendarDay? get monday => CalendarDay.tryParse(week);
  List<ChallengeMember> get joined => members.where((member) => member.status == 'joined').toList();
  bool get iWon => finished && members.any((member) => member.me && member.winner);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'metric': metric,
    'metricTitle': metricTitle,
    'max': max,
    'week': week,
    'finished': finished,
    'status': status,
    'mineCreated': mineCreated,
    'members': [for (final member in members) member.toJson()],
  };

  static Challenge? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, title, metric, metricTitle, max, week, status) = (
      json['id'],
      json['title'],
      json['metric'],
      json['metricTitle'],
      json['max'],
      json['week'],
      json['status'],
    );
    final (finished, mineCreated) = (_bool(json['finished']), _bool(json['mineCreated']));
    final members = listStrict(json['members'], ChallengeMember.fromJson);
    if (id is! String ||
        title is! String ||
        metric is! String ||
        metricTitle is! String ||
        max is! int ||
        week is! String ||
        status is! String ||
        finished == null ||
        mineCreated == null ||
        members == null) {
      return null;
    }
    return Challenge(
      id: id,
      title: title,
      metric: metric,
      metricTitle: metricTitle,
      max: max,
      week: week,
      finished: finished,
      status: status,
      mineCreated: mineCreated,
      members: members,
    );
  }
}

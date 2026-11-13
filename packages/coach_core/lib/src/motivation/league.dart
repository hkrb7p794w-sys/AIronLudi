import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../profile/plan_adjustments.dart';
import '../profile/week_schedule.dart';
import '../util/url_query.dart';
import 'adherence.dart';

final _leagueCode = RegExp(r'^[a-z0-9-]{6,40}$');

/// Stand der Planerfüllung: aktuelle Woche, Punkte und Serie. Grundlage für Begleiter und Rangliste.
final class MotivationSummary {
  const MotivationSummary({
    required this.week,
    required this.weekPoints,
    required this.totalPoints,
    required this.streak,
    required this.level,
  });

  final WeekAdherence week;
  final int weekPoints;

  /// Punkte der letzten `weeks` Wochen inklusive der aktuellen.
  final int totalPoints;

  /// Abgeschlossene Wochen in Folge mit mindestens 80 % des Plans.
  final int streak;
  final int level;

  /// [schedule]: Plan der Woche, die den Tag enthält (mit Ausnahmen). [trainingDays]: Tage mit Training
  /// (Garmin-Aktivität oder Krafteinheit).
  static MotivationSummary compute({
    required WeekSchedule Function(CalendarDay) schedule,
    required Set<CalendarDay> trainingDays,
    required CalendarDay today,
    int weeks = 12,
  }) {
    final monday = PlanAdjustments.monday(today);
    final current = WeekAdherence.compute(
      schedule: schedule(monday),
      trainingDays: trainingDays,
      weekOf: monday,
      today: today,
    );
    final past = [
      for (var offset = 1; offset < math.max(weeks, 1); offset++)
        WeekAdherence.compute(
          schedule: schedule(monday.adding(-7 * offset)),
          trainingDays: trainingDays,
          weekOf: monday.adding(-7 * offset),
          today: today,
        ),
    ];
    final weekPoints = ScoreRules.points(current);
    final total = past.fold(weekPoints, (sum, week) => sum + ScoreRules.points(week));
    return MotivationSummary(
      week: current,
      weekPoints: weekPoints,
      totalPoints: total,
      streak: ScoreRules.streak(past),
      level: ScoreRules.level(total),
    );
  }

  /// Gestern war etwas geplant und wurde nicht gemacht (nur innerhalb der Woche).
  bool missedYesterday(CalendarDay today) {
    final index = today.weekdayIndex;
    return index > 0 && week.days[index - 1] == AdherenceDay.missed;
  }
}

/// Eintrag der Rangliste, wie ihn der Worker speichert (`worker/src/league.ts`).
final class LeagueEntry {
  const LeagueEntry({
    required this.id,
    required this.name,
    required this.avatar,
    required this.week,
    required this.weekPoints,
    required this.totalPoints,
    required this.streak,
    required this.done,
    required this.planned,
    this.updatedAt,
  });

  factory LeagueEntry.fromSummary({
    required String id,
    required String name,
    required String avatar,
    required MotivationSummary summary,
  }) => LeagueEntry(
    id: id,
    name: name,
    avatar: avatar,
    week: summary.week.monday.iso,
    weekPoints: summary.weekPoints,
    totalPoints: summary.totalPoints,
    streak: summary.streak,
    done: summary.week.done,
    planned: summary.week.planned,
  );

  final String id;
  final String name;
  final String avatar;
  final String week;
  final int weekPoints;
  final int totalPoints;
  final int streak;
  final int done;
  final int planned;
  final String? updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'week': week,
    'weekPoints': weekPoints,
    'totalPoints': totalPoints,
    'streak': streak,
    'done': done,
    'planned': planned,
    'updatedAt': ?updatedAt,
  };

  static LeagueEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, name, avatar, week) = (json['id'], json['name'], json['avatar'], json['week']);
    final (weekPoints, totalPoints, streak, done, planned) = (
      json['weekPoints'],
      json['totalPoints'],
      json['streak'],
      json['done'],
      json['planned'],
    );
    final updatedAt = json['updatedAt'];
    if (id is! String ||
        name is! String ||
        avatar is! String ||
        week is! String ||
        weekPoints is! int ||
        totalPoints is! int ||
        streak is! int ||
        done is! int ||
        planned is! int ||
        (updatedAt != null && updatedAt is! String)) {
      return null;
    }
    return LeagueEntry(
      id: id,
      name: name,
      avatar: avatar,
      week: week,
      weekPoints: weekPoints,
      totalPoints: totalPoints,
      streak: streak,
      done: done,
      planned: planned,
      updatedAt: updatedAt as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LeagueEntry &&
      other.id == id &&
      other.name == name &&
      other.avatar == avatar &&
      other.week == week &&
      other.weekPoints == weekPoints &&
      other.totalPoints == totalPoints &&
      other.streak == streak &&
      other.done == done &&
      other.planned == planned &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, avatar, week, weekPoints, totalPoints, streak, done, planned, updatedAt);
}

/// Was eine Einladung mit dem gespeicherten Zugang machen darf.
enum InviteDecision {
  /// Gleicher Server: Das vorhandene Token bleibt.
  keepCurrentToken,
  useInviteToken,

  /// Anderer Server, aber das Haupt-Token ist hinterlegt: Es darf weder gesendet noch überschrieben werden.
  rejectOtherServer,
}

/// Einladung in die Rangliste: Worker-Adresse, Gast-Token und Ranglisten-Code als Link `coach://join?…`.
/// Das Gast-Token stellt der Worker eigens für die Einladung aus (`POST /v1/invite`); das Haupt-Token verlässt das
/// iPhone nicht.
/// Wer den Link öffnet, nutzt denselben Worker – Profil, Garmin-Konto und Daten bleiben auf dem eigenen iPhone.
final class LeagueInvite {
  const LeagueInvite({required this.workerURL, required this.token, required this.code});

  static const scheme = 'coach';

  final String workerURL;
  final String token;
  final String code;

  static LeagueInvite? fromUri(Uri url) {
    if (url.scheme != scheme || url.host != 'join') return null;
    final items = queryItems(url);
    final worker = items['worker'] ?? '';
    final code = items['league'] ?? '';
    final token = (items['token'] ?? '').trim();
    // Ohne Gast-Token würde das gespeicherte Token an die Adresse aus dem Link gehen.
    if (!worker.startsWith('https://') || token.isEmpty || !LeagueCode.isValid(code)) return null;
    return LeagueInvite(workerURL: worker, token: token, code: code);
  }

  /// Server aus der Einladung; wird vor dem Beitreten angezeigt.
  String? get host => urlHost(workerURL);

  /// Was eine Einladung mit dem gespeicherten Zugang machen darf.
  InviteDecision decision({required String currentURL, required String? currentToken}) {
    if (currentToken == null || currentToken.isEmpty) return InviteDecision.useInviteToken;
    if (urlHost(currentURL) == host) return InviteDecision.keepCurrentToken;
    return GuestToken.isGuest(currentToken) ? InviteDecision.useInviteToken : InviteDecision.rejectOtherServer;
  }

  /// Selbst kodiert: Nur unreservierte Zeichen bleiben stehen, damit „+“, „&“ und „=“ im Token sicher ankommen.
  Uri? get url => Uri.tryParse(
    '$scheme://join?worker=${percentEncodeUnreserved(workerURL)}&token=${percentEncodeUnreserved(token)}'
    '&league=${percentEncodeUnreserved(code)}',
  );

  @override
  bool operator ==(Object other) =>
      other is LeagueInvite && other.workerURL == workerURL && other.token == token && other.code == code;

  @override
  int get hashCode => Object.hash(workerURL, token, code);
}

/// Gast-Token des Workers (`worker/src/auth.ts`): `g1.<id>.<signatur>`. Gäste nutzen KI, Rangliste und geteilte
/// Mahlzeiten, laden aber niemanden ein und sehen die private SideStore-Quelle nicht.
abstract final class GuestToken {
  static const prefix = 'g1.';

  static bool isGuest(String token) => token.startsWith(prefix);
}

/// Link zur Android-Download-Seite mit Gastzugang im Anker: Der Browser schickt den Anker nicht an den Server, die
/// Seite macht daraus `ironludi://connect?worker=…&token=…` für die Android-App.
abstract final class AndroidLink {
  static Uri? url({required Uri base, required String guestToken}) =>
      Uri.tryParse('$base#zugang=${percentEncodeUnreserved(guestToken)}');
}

abstract final class LeagueCode {
  /// Gleiche Regel wie im Worker: 6–40 Zeichen, Kleinbuchstaben, Ziffern, Bindestrich.
  static bool isValid(String code) => _leagueCode.hasMatch(code);

  static const _alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

  static String generate([math.Random? random]) {
    final generator = random ?? math.Random.secure();
    return 'team-${List.generate(10, (_) => _alphabet[generator.nextInt(_alphabet.length)]).join()}';
  }
}

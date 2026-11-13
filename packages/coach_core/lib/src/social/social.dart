import 'dart:math' as math;

import '../garmin/garmin_activity.dart';
import '../gym/gym_session.dart';
import '../nutrition/meal.dart';
import '../nutrition/meal_share.dart';
import '../nutrition/nutrient.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import '../util/text_prefix.dart';

/// Beziehung zu einer anderen Person (wie `worker/src/social.ts`).
enum SocialRelation implements RawEnum {
  me('self'),
  friends('friends'),
  incoming('incoming'),
  outgoing('outgoing'),
  none('none'),
  blocked('blocked');

  const SocialRelation(this.rawValue);

  @override
  final String rawValue;
}

/// Ein Wert, der fehlen darf, aber wenn vorhanden vom richtigen Typ sein muss (wie `decodeIfPresent`).
/// Gibt `(ok, value)` zurück.
(bool, T?) _optional<T>(Object? value) =>
    value == null ? (true, null) : (value is T ? (true, value as T) : (false, null));

(bool, double?) _optionalNumber(Object? value) =>
    value == null ? (true, null) : (value is num ? (true, value.toDouble()) : (false, null));

(bool, List<String>?) _optionalStrings(Object? value) {
  if (value == null) return (true, null);
  if (value is! List || !value.every((item) => item is String)) return (false, null);
  return (true, value.cast<String>());
}

final class SocialPerson {
  const SocialPerson({required this.username, required this.displayName, this.relation, this.since});

  final String username;
  final String displayName;
  final SocialRelation? relation;
  final String? since;

  String get id => username;

  /// Initial für den Avatar.
  String get initial {
    final source = displayName.isNotEmpty ? displayName : username;
    return source.isEmpty ? '?' : String.fromCharCode(source.runes.first).toUpperCase();
  }

  Map<String, Object?> toJson() => {
    'username': username,
    'displayName': displayName,
    'relation': ?relation?.rawValue,
    'since': ?since,
  };

  static SocialPerson? fromJson(Object? json) {
    if (json is! Map) return null;
    final (username, displayName) = (json['username'], json['displayName']);
    final rawRelation = json['relation'];
    final relation = rawRelation == null ? null : enumFromRaw(SocialRelation.values, rawRelation);
    final (sinceOk, since) = _optional<String>(json['since']);
    if (username is! String || displayName is! String || (rawRelation != null && relation == null) || !sinceOk) {
      return null;
    }
    return SocialPerson(username: username, displayName: displayName, relation: relation, since: since);
  }

  @override
  bool operator ==(Object other) =>
      other is SocialPerson &&
      other.username == username &&
      other.displayName == displayName &&
      other.relation == relation &&
      other.since == since;

  @override
  int get hashCode => Object.hash(username, displayName, relation, since);
}

final class SocialFriends {
  const SocialFriends({this.friends = const [], this.incoming = const [], this.outgoing = const []});

  final List<SocialPerson> friends;
  final List<SocialPerson> incoming;
  final List<SocialPerson> outgoing;

  Map<String, Object?> toJson() => {
    'friends': [for (final person in friends) person.toJson()],
    'incoming': [for (final person in incoming) person.toJson()],
    'outgoing': [for (final person in outgoing) person.toJson()],
  };

  static SocialFriends? fromJson(Object? json) {
    if (json is! Map) return null;
    final friends = listStrict(json['friends'], SocialPerson.fromJson);
    final incoming = listStrict(json['incoming'], SocialPerson.fromJson);
    final outgoing = listStrict(json['outgoing'], SocialPerson.fromJson);
    if (friends == null || incoming == null || outgoing == null) return null;
    return SocialFriends(friends: friends, incoming: incoming, outgoing: outgoing);
  }
}

/// Reaktionen wie im Worker (`REACTIONS`).
enum SocialReaction implements RawEnum {
  clap('👏', 'Applaus'),
  fire('🔥', 'Stark'),
  strong('💪', 'Kraft'),
  yummy('😋', 'Lecker'),
  heart('❤️', 'Herz');

  const SocialReaction(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;
}

enum SocialPostKind implements RawEnum {
  workout,
  meal,
  milestone,
  unknown;

  @override
  String get rawValue => name;

  /// Unbekannte Arten (neuere Worker-Version) werden zu [unknown].
  static SocialPostKind? fromJson(Object? json) => json is String ? enumFromRaw(values, json) ?? unknown : null;
}

/// Inhalt eines Beitrags; welche Felder belegt sind, hängt von der Art ab.
final class SocialPayload {
  SocialPayload();

  String? sport;
  String? title;
  double? durationMin;
  double? distanceKm;
  double? elevationM;
  double? sets;
  double? volumeKg;
  List<String>? exercises;
  List<String>? records;
  String? note;
  SharedMeal? meal;
  String? text;
  String? badge;

  Map<String, Object?> toJson() => {
    'sport': ?sport,
    'title': ?title,
    'durationMin': ?durationMin,
    'distanceKm': ?distanceKm,
    'elevationM': ?elevationM,
    'sets': ?sets,
    'volumeKg': ?volumeKg,
    'exercises': ?exercises,
    'records': ?records,
    'note': ?note,
    'meal': ?meal?.toJson(),
    'text': ?text,
    'badge': ?badge,
  };

  static SocialPayload? fromJson(Object? json) {
    if (json is! Map) return null;
    final strings = [
      for (final key in const ['sport', 'title', 'note', 'text', 'badge']) _optional<String>(json[key]),
    ];
    final numbers = [
      for (final key in const ['durationMin', 'distanceKm', 'elevationM', 'sets', 'volumeKg'])
        _optionalNumber(json[key]),
    ];
    final (exercisesOk, exercises) = _optionalStrings(json['exercises']);
    final (recordsOk, records) = _optionalStrings(json['records']);
    final rawMeal = json['meal'];
    final meal = rawMeal == null ? null : SharedMeal.fromJson(rawMeal);
    if (strings.any((entry) => !entry.$1) ||
        numbers.any((entry) => !entry.$1) ||
        !exercisesOk ||
        !recordsOk ||
        (rawMeal != null && meal == null)) {
      return null;
    }
    return SocialPayload()
      ..sport = strings[0].$2
      ..title = strings[1].$2
      ..note = strings[2].$2
      ..text = strings[3].$2
      ..badge = strings[4].$2
      ..durationMin = numbers[0].$2
      ..distanceKm = numbers[1].$2
      ..elevationM = numbers[2].$2
      ..sets = numbers[3].$2
      ..volumeKg = numbers[4].$2
      ..exercises = exercises
      ..records = records
      ..meal = meal;
  }
}

/// Beitrag im Feed. Der Inhalt hängt von der Art ab; unbekannte Arten zeigt die App als Hinweis.
final class SocialPost {
  const SocialPost({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.author,
    required this.mine,
    required this.payload,
    required this.reactions,
    this.myReaction,
    required this.topReactions,
    required this.comments,
  });

  final String id;
  final SocialPostKind kind;
  final String createdAt;
  final SocialPerson author;
  final bool mine;
  final SocialPayload payload;
  final int reactions;
  final String? myReaction;
  final String topReactions;
  final int comments;

  DateTime? get date => SocialFormat.date(createdAt);

  /// Überschrift im Feed, z. B. „Lockerer Lauf“ oder „Overnight Oats“.
  String get headline => switch (kind) {
    SocialPostKind.meal => payload.meal?.title ?? 'Mahlzeit',
    SocialPostKind.workout || SocialPostKind.milestone => payload.title ?? 'Beitrag',
    SocialPostKind.unknown => 'Beitrag (neuere App-Version nötig)',
  };

  /// Kennzahlen in einer Zeile, z. B. „45 min · 8,2 km“ oder „620 kcal · 42 g Protein“.
  String get facts {
    final parts = <String>[];
    switch (kind) {
      case SocialPostKind.workout:
        if (payload.durationMin case final minutes?) parts.add('${minutes.round()} min');
        if (payload.distanceKm case final km? when km > 0) parts.add('${GermanFormat.decimal(km)} km');
        if (payload.elevationM case final up? when up >= 10) parts.add('${up.round()} hm');
        if (payload.sets case final sets? when sets > 0) parts.add('${sets.truncate()} Sätze');
        if (payload.volumeKg case final volume? when volume > 0) {
          parts.add('${GermanFormat.number((volume / 100).roundToDouble() * 100)} kg bewegt');
        }
      case SocialPostKind.meal:
        if (payload.meal case final meal?) {
          parts.add('${meal.kilocalories.round()} kcal');
          final protein = NutritionSummary.totals(meal.mealItems)[Nutrient.protein] ?? 0;
          if (protein > 0) parts.add('${protein.round()} g Protein');
        }
      case SocialPostKind.milestone:
        if (payload.text case final text?) parts.add(text);
      case SocialPostKind.unknown:
        break;
    }
    return parts.join(' · ');
  }

  String get symbol => switch (kind) {
    SocialPostKind.meal => 'fork.knife',
    SocialPostKind.milestone => 'trophy.fill',
    SocialPostKind.unknown => 'questionmark.circle',
    SocialPostKind.workout => switch (payload.sport) {
      'run' => 'figure.run',
      'bike' => 'figure.outdoor.cycle',
      'swim' => 'figure.pool.swim',
      'strength' => 'dumbbell.fill',
      'walk' => 'figure.walk',
      'hike' => 'figure.hiking',
      'yoga' || 'mobility' => 'figure.yoga',
      _ => 'figure.mixed.cardio',
    },
  };

  static SocialPost? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, createdAt, mine, reactions, topReactions, comments) = (
      json['id'],
      json['createdAt'],
      json['mine'],
      json['reactions'],
      json['topReactions'],
      json['comments'],
    );
    final kind = SocialPostKind.fromJson(json['kind']);
    final author = SocialPerson.fromJson(json['author']);
    final payload = SocialPayload.fromJson(json['payload']);
    final (reactionOk, myReaction) = _optional<String>(json['myReaction']);
    if (id is! String ||
        kind == null ||
        createdAt is! String ||
        author == null ||
        mine is! bool ||
        payload == null ||
        reactions is! int ||
        !reactionOk ||
        topReactions is! String ||
        comments is! int) {
      return null;
    }
    return SocialPost(
      id: id,
      kind: kind,
      createdAt: createdAt,
      author: author,
      mine: mine,
      payload: payload,
      reactions: reactions,
      myReaction: myReaction,
      topReactions: topReactions,
      comments: comments,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.rawValue,
    'createdAt': createdAt,
    'author': author.toJson(),
    'mine': mine,
    'payload': payload.toJson(),
    'reactions': reactions,
    'myReaction': ?myReaction,
    'topReactions': topReactions,
    'comments': comments,
  };
}

final class SocialComment {
  const SocialComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
    required this.canDelete,
  });

  final String id;
  final String text;
  final String createdAt;
  final SocialPerson author;
  final bool canDelete;

  static SocialComment? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, text, createdAt, canDelete) = (json['id'], json['text'], json['createdAt'], json['canDelete']);
    final author = SocialPerson.fromJson(json['author']);
    if (id is! String || text is! String || createdAt is! String || author == null || canDelete is! bool) return null;
    return SocialComment(id: id, text: text, createdAt: createdAt, author: author, canDelete: canDelete);
  }
}

/// Was beim Teilen eines Trainings an Freunde geht – bewusst ohne Körperwerte (Puls, Gewicht, HRV, Schlaf, Kalorien).
final class WorkoutShare {
  WorkoutShare({required this.sport, required this.title});

  final String kind = 'workout';
  final String sport;
  final String title;
  int? durationMin;
  double? distanceKm;
  int? elevationM;
  int? sets;
  int? volumeKg;
  List<String>? exercises;
  List<String>? records;
  String? note;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'sport': sport,
    'title': title,
    'durationMin': ?durationMin,
    'distanceKm': ?distanceKm,
    'elevationM': ?elevationM,
    'sets': ?sets,
    'volumeKg': ?volumeKg,
    'exercises': ?exercises,
    'records': ?records,
    'note': ?note,
  };

  /// Krafteinheit: Dauer, Sätze, bewegtes Gewicht, Übungen (höchstens 12) und neue Bestleistungen.
  static WorkoutShare gym(GymSession session, {List<String> records = const [], DateTime? now}) {
    final share = WorkoutShare(sport: 'strength', title: session.title.isEmpty ? 'Krafttraining' : session.title);
    final end = session.end ?? now ?? DateTime.now();
    share
      ..durationMin = math.max(1, (end.difference(session.start).inMicroseconds / 1e6 / 60).round())
      ..sets = session.doneSetCount;
    if (session.volumeKg > 0) share.volumeKg = session.volumeKg.round();
    final names = [
      for (final exercise in session.exercises)
        if (exercise.doneSets.isNotEmpty) exercise.name,
    ];
    if (names.isNotEmpty) share.exercises = names.take(12).toList();
    if (records.isNotEmpty) share.records = records.take(10).toList();
    return share;
  }

  /// Ausdaueraktivität: Sportart, Dauer, Strecke, Höhenmeter – Puls und Kalorien bleiben auf dem Gerät.
  static WorkoutShare activity(GarminActivity activity) {
    final key = activity.typeKey?.toLowerCase() ?? '';
    final sport = switch (activity.sport) {
      ActivitySport.run => 'run',
      ActivitySport.bike => 'bike',
      ActivitySport.swim => 'swim',
      ActivitySport.strength => 'strength',
      ActivitySport.other =>
        key.contains('hik')
            ? 'hike'
            : key.contains('walk')
            ? 'walk'
            : key.contains('yoga')
            ? 'yoga'
            : 'other',
    };
    final fallback = switch (sport) {
      'run' => 'Lauf',
      'bike' => 'Radfahrt',
      'swim' => 'Schwimmen',
      'strength' => 'Krafttraining',
      'walk' => 'Spaziergang',
      'hike' => 'Wanderung',
      'yoga' => 'Yoga',
      _ => 'Training',
    };
    final name = activity.name?.trim() ?? '';
    final share = WorkoutShare(sport: sport, title: textPrefix(name.isEmpty ? fallback : name, 80));
    if (activity.movingSeconds ?? activity.durationSeconds case final seconds? when seconds > 0) {
      share.durationMin = math.max(1, (seconds / 60).round());
    }
    if (activity.distanceMeters case final meters? when meters >= 100) {
      share.distanceKm = (meters / 100).roundToDouble() / 10;
    }
    if (activity.elevationGain case final up? when up >= 10) share.elevationM = up.round();
    return share;
  }
}

/// Mahlzeit für den Feed: dieselben Felder wie beim Teilen per Code (`SharedMeal`).
final class MealPostShare {
  const MealPostShare({required this.meal, this.note});

  final String kind = 'meal';
  final SharedMeal meal;
  final String? note;

  Map<String, Object?> toJson() => {'kind': kind, 'meal': meal.toJson(), 'note': ?note};
}

abstract final class SocialFormat {
  static const _months = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sept.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];

  /// ISO 8601 mit oder ohne Sekundenbruchteile; ohne Zeitzonenangabe ungültig (wie `ISO8601DateFormatter`).
  static DateTime? date(String iso) {
    if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(iso) || !iso.contains('T')) return null;
    return DateTime.tryParse(iso);
  }

  /// „gerade eben“, „vor 5 Min.“, „vor 3 Std.“, „gestern“, sonst Datum („5. Nov.“) – in Ortszeit.
  static String relative(DateTime date, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final local = date.toLocal();
    final seconds = current.difference(local).inMicroseconds / 1e6;
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    if (seconds < 60) return 'gerade eben';
    if (seconds < 3600) return 'vor ${(seconds / 60).truncate()} Min.';
    if (sameDay(local, current)) return 'vor ${(seconds / 3600).truncate()} Std.';
    if (sameDay(local, DateTime(current.year, current.month, current.day - 1))) return 'gestern';
    return '${local.day}. ${_months[local.month - 1]}';
  }
}

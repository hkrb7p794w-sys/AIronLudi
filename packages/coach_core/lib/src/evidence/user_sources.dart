import 'dart:math' as math;

import '../nutrition/meal.dart' show newUuid;
import '../util/enum_codec.dart';

/// Themen einer eigenen Quelle.
enum UserSourceTopic implements RawEnum {
  endurance,
  strength,
  nutrition,
  recovery,
  general;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    endurance => 'Ausdauer',
    strength => 'Krafttraining',
    nutrition => 'Ernährung',
    recovery => 'Schlaf und Erholung',
    general => 'Allgemein',
  };
}

/// Eigene wissenschaftliche Quellen der Person (Einstellungen › Coach › Eigene Quellen). Sie gehen als zusätzliche
/// „belegte Regeln“ an die KI (Gemini Flash im Worker) und dürfen dort zitiert werden. Die Entscheidungen der App
/// (Tagesampel, Ziele, Progression, Schutzgrenzen) ändern sie nicht – „Regeln entscheiden, KI formuliert“.
final class UserSource {
  UserSource({
    String? id,
    required this.citation,
    this.reference = '',
    required this.statement,
    Set<UserSourceTopic>? topics,
  }) : id = id ?? newUuid(),
       topics = topics ?? {UserSourceTopic.general};

  String id;

  /// Kurzbeleg, z. B. „Schoenfeld et al. 2017“.
  String citation;

  /// DOI, PMID oder Link.
  String reference;

  /// Kernaussage in eigenen Worten, so wie die KI sie verwenden soll.
  String statement;
  Set<UserSourceTopic> topics;

  /// Kennung für die KI und die Quellenangabe in ihrer Antwort.
  String get evidenceID => 'eigen.${id.substring(0, math.min(8, id.length)).toLowerCase()}';

  bool get isValid => citation.trim().isNotEmpty && statement.trim().runes.length >= 10;

  /// Link aus DOI, PMID oder URL.
  Uri? get url {
    final text = reference.trim();
    if (text.toLowerCase().startsWith('http')) return Uri.tryParse(text);
    if (text.startsWith('10.')) return Uri.tryParse('https://doi.org/$text');
    final digits = text.toLowerCase().replaceAll('pmid', '').replaceAll(RegExp(r'^[: ]+|[: ]+$'), '');
    if (digits.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(digits)) return null;
    return Uri.parse('https://pubmed.ncbi.nlm.nih.gov/$digits/');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'citation': citation,
    'reference': reference,
    'statement': statement,
    'topics': [
      for (final topic in UserSourceTopic.values)
        if (topics.contains(topic)) topic.rawValue,
    ],
  };

  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static UserSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, citation, reference, statement) = (json['id'], json['citation'], json['reference'], json['statement']);
    final topics = enumListStrict(UserSourceTopic.values, json['topics']);
    if (id is! String || !_uuid.hasMatch(id) || citation is! String || reference is! String || statement is! String) {
      return null;
    }
    if (topics == null) return null;
    return UserSource(
      id: id.toUpperCase(),
      citation: citation,
      reference: reference,
      statement: statement,
      topics: topics.toSet(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserSource &&
      other.id == id &&
      other.citation == citation &&
      other.reference == reference &&
      other.statement == statement &&
      other.topics.length == topics.length &&
      other.topics.containsAll(topics);

  @override
  int get hashCode => Object.hash(id, citation, reference, statement, Object.hashAllUnordered(topics));
}

abstract final class UserSources {
  static const maxPerRequest = 8;
  static const maxStatementLength = 300;

  /// Themen, die zu einer Worker-Aufgabe passen; `null` = alle (Chat).
  static Set<UserSourceTopic>? topics(String task) => switch (task) {
    'daily_note' => {UserSourceTopic.endurance, UserSourceTopic.recovery, UserSourceTopic.general},
    'gym_hints' || 'gym_plan' => {UserSourceTopic.strength, UserSourceTopic.recovery, UserSourceTopic.general},
    'nutrition_review' || 'weekly_recipes' => {UserSourceTopic.nutrition, UserSourceTopic.general},
    'coach_chat' => null,
    _ => {},
  };

  /// Hängt passende eigene Quellen an `evidence` der Eingabe an (nach den Regeln der App, damit diese Vorrang haben).
  static Map<String, Object?> inject(List<UserSource> sources, Map<String, Object?> input, {required String task}) {
    final wanted = topics(task);
    if (wanted != null && wanted.isEmpty) return input;
    final relevant = sources
        .where((source) => source.isValid && (wanted == null || source.topics.any(wanted.contains)))
        .take(maxPerRequest)
        .toList();
    if (relevant.isEmpty) return input;
    final existing = input['evidence'] is List ? input['evidence']! as List : const <Object?>[];
    final extra = [
      for (final source in relevant)
        {
          'id': source.evidenceID,
          'statement':
              '${String.fromCharCodes(source.statement.trim().runes.take(maxStatementLength))} '
              '(eigene Quelle: ${source.citation})',
        },
    ];
    return {
      ...input,
      'evidence': [...existing.take(math.max(0, 20 - extra.length)), ...extra],
    };
  }

  static bool isUserID(String id) => id.startsWith('eigen.');
}

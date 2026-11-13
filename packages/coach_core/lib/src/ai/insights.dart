import 'package:collection/collection.dart';

import '../coach/recommendation.dart';
import '../coach/recovery_level.dart';
import '../coach/sleep_coach.dart';
import '../json/json_value.dart';
import '../nutrition/food_search.dart';
import '../profile/plan_suggestion.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import '../util/swift_date.dart';
import '../util/text_prefix.dart';

final _digit = RegExp(r'\p{N}', unicode: true);
final _wordSeparator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Thema einer Empfehlung im Reiter „AI“.
enum InsightTopic implements RawEnum {
  training('training'),
  planning('plan'),
  performance('leistung'),
  recovery('erholung'),
  nutrition('ernaehrung'),
  progress('fortschritt'),
  stagnation('stagnation'),
  action('handlung');

  const InsightTopic(this.rawValue);

  @override
  final String rawValue;

  String get label => switch (this) {
    training => 'Training',
    planning => 'Trainingsplan',
    performance => 'Leistung',
    recovery => 'Erholung',
    nutrition => 'Ernährung',
    progress => 'Fortschritt',
    stagnation => 'Stagnation',
    action => 'Nächste Schritte',
  };

  /// SF-Symbol-Name der Swift-App; die Flutter-Oberfläche ordnet ihm ein Icon zu.
  String get symbol => switch (this) {
    training => 'figure.run',
    planning => 'calendar',
    performance => 'chart.line.uptrend.xyaxis',
    recovery => 'bed.double',
    nutrition => 'fork.knife',
    progress => 'arrow.up.right',
    stagnation => 'pause.circle',
    action => 'checklist',
  };
}

/// Bereich einer Empfehlung für die Filter. Wird aus Thema und Inhalt abgeleitet, gespeicherte Empfehlungen bleiben
/// damit unverändert gültig; ein neuer Bereich braucht nur einen Fall und seine Stichwörter.
enum InsightCategory implements RawEnum {
  strength,
  endurance,
  nutrition,
  recovery,
  health,
  bodyComposition,
  general;

  @override
  String get rawValue => name;

  String get label => switch (this) {
    strength => 'Training und Kraftaufbau',
    endurance => 'Ausdauer und Leistung',
    nutrition => 'Ernährung',
    recovery => 'Schlaf und Regeneration',
    health => 'Gesundheit und Belastung',
    bodyComposition => 'Körperzusammensetzung',
    general => 'Allgemeine Fitness',
  };

  String get symbol => switch (this) {
    strength => 'dumbbell',
    endurance => 'figure.run',
    nutrition => 'fork.knife',
    recovery => 'bed.double',
    health => 'heart.text.square',
    bodyComposition => 'scalemass',
    general => 'figure.mixed.cardio',
  };

  /// Das Thema, das die KI-Analyse für diesen Bereich bekommt.
  InsightTopic? get analysisTopic => switch (this) {
    strength => InsightTopic.training,
    endurance => InsightTopic.performance,
    nutrition || bodyComposition => InsightTopic.nutrition,
    recovery || health => InsightTopic.recovery,
    general => null,
  };

  List<String> get _keywords => switch (this) {
    strength => const [
      'bankdr',
      'kniebeug',
      'kreuzheb',
      'schulterdr',
      'klimmz',
      'rudern',
      'kraft',
      'gym',
      'satz',
      'saetze',
      'sätze',
      'volumen',
      'progression',
      'deload',
      'muskel',
    ],
    endurance => const [
      'lauf',
      'rennrad',
      'radfahr',
      'rad-',
      'schwimm',
      'pace',
      'ausdauer',
      'tempo',
      'intervall',
      'zone',
    ],
    nutrition => const ['protein', 'kalorien', 'kcal', 'ernaehr', 'ernähr', 'mahlzeit', 'kohlenhydr', 'fett', 'essen'],
    recovery => const ['schlaf', 'erhol', 'regener', 'hrv', 'muedigkeit', 'müdigkeit', 'ruhetag'],
    health => const ['schmerz', 'krank', 'verletz', 'ruhepuls', 'ueberlast', 'überlast', 'belastung', 'beschwerd'],
    bodyComposition => const ['koerper', 'körper', 'gewicht', 'abnehm', 'zunehm', 'taille'],
    general => const [],
  };

  /// Das Thema entscheidet zuerst, innerhalb davon der Inhalt. So bleibt „Schlaf für mehr Kraft“ bei der Regeneration.
  static InsightCategory of({required InsightTopic topic, required String content}) {
    final lower = content.toLowerCase();
    bool has(InsightCategory category) => category._keywords.any(lower.contains);
    switch (topic) {
      case InsightTopic.recovery:
        return has(health) ? health : recovery;
      case InsightTopic.nutrition:
        return has(bodyComposition) ? bodyComposition : nutrition;
      default:
        const order = [health, bodyComposition, recovery, nutrition, strength, endurance];
        return order.firstWhereOrNull(has) ?? general;
    }
  }
}

/// Bearbeitungsstand aus Sicht der Person.
enum InsightStatus implements RawEnum {
  newInsight('neu'),
  read('gelesen'),
  done('umgesetzt'),
  dismissed('verworfen');

  const InsightStatus(this.rawValue);

  @override
  final String rawValue;
}

/// Woher eine Empfehlung kommt. Regeln haben Vorrang vor der KI.
enum InsightOrigin implements RawEnum {
  rules('regeln'),
  ai('ki');

  const InsightOrigin(this.rawValue);

  @override
  final String rawValue;
}

/// Wohin eine Empfehlung zielt – zwei Empfehlungen zum selben Betreff mit anderer Richtung widersprechen sich.
enum InsightDirection implements RawEnum {
  more('mehr'),
  less('weniger'),
  keep('halten'),
  change('aendern'),
  check('pruefen');

  const InsightDirection(this.rawValue);

  @override
  final String rawValue;
}

/// Eine Empfehlung im Reiter „AI“. `basis`, `origin` und `model` sind intern (Nachvollziehbarkeit), die Ansicht zeigt
/// nur Titel und Text.
final class Insight {
  Insight({
    required this.topic,
    required String subject,
    required this.title,
    required this.text,
    required this.direction,
    int priority = 2,
    required this.origin,
    required this.created,
    required this.validUntil,
    this.basis = const [],
    this.model,
    this.uncertain = false,
  }) : subject = normalizedSubject(subject),
       priority = priority.clamp(1, 3),
       status = InsightStatus.newInsight,
       statusChanged = null;

  const Insight._raw({
    required this.topic,
    required this.subject,
    required this.title,
    required this.text,
    required this.direction,
    required this.priority,
    required this.origin,
    required this.created,
    required this.validUntil,
    required this.basis,
    required this.model,
    required this.uncertain,
    required this.status,
    required this.statusChanged,
  });

  final InsightTopic topic;

  /// Worum es geht, z. B. „bankdruecken“, „schlaf“, „protein“ (klein, ohne Leerzeichen).
  final String subject;
  final String title;
  final String text;
  final InsightDirection direction;

  /// 1 = wichtig, 3 = nebenbei.
  final int priority;
  final InsightOrigin origin;
  final DateTime created;
  final DateTime validUntil;

  /// Belegende Fakten in Klartext (intern, nicht in der normalen Ansicht).
  final List<String> basis;

  /// Modell bei KI-Empfehlungen (intern).
  final String? model;

  /// `niedrig`, wenn Daten fehlen oder knapp sind – wird in der Ansicht genannt, nicht verschleiert.
  final bool uncertain;
  final InsightStatus status;
  final DateTime? statusChanged;

  /// Thema + Betreff: dieselbe Frage hat immer dieselbe ID.
  String get id => '${topic.rawValue}.$subject';

  /// Kopie mit geändertem Stand bzw. Zeiten (Swift ändert die `var`-Felder direkt).
  Insight copyWith({
    InsightStatus? status,
    DateTime? Function()? statusChanged,
    DateTime? created,
    DateTime? validUntil,
  }) => Insight._raw(
    topic: topic,
    subject: subject,
    title: title,
    text: text,
    direction: direction,
    priority: priority,
    origin: origin,
    created: created ?? this.created,
    validUntil: validUntil ?? this.validUntil,
    basis: basis,
    model: model,
    uncertain: uncertain,
    status: status ?? this.status,
    statusChanged: statusChanged == null ? this.statusChanged : statusChanged(),
  );

  bool isCurrent(DateTime date) => validUntil.isAfter(date);

  InsightCategory get category => InsightCategory.of(topic: topic, content: '$subject $title $text');

  /// Titel zu Schlaf und Gesundheit können Rohwerte enthalten; sie gehen nur bei vollem Datenschutzmodus an die KI.
  bool get hasRawHealthValue =>
      (category == InsightCategory.recovery || category == InsightCategory.health) && _digit.hasMatch(title);

  /// Widerspruch: gleicher Betreff mit anderer Richtung, oder „mehr“ gegen „weniger“ zum selben Hauptwort im Bereich.
  bool contradicts(Insight other) {
    if (subject == other.subject) return direction != other.direction;
    final opposite =
        {direction, other.direction}.length == 2 &&
        {direction, other.direction}.containsAll([InsightDirection.more, InsightDirection.less]);
    return opposite && category == other.category && _head(subject) == _head(other.subject);
  }

  /// Erstes Wort vor einem Bindestrich (wie `split(separator: "-").first`: leere Teile zählen nicht).
  static String? _head(String subject) => subject.split('-').firstWhereOrNull((part) => part.isNotEmpty);

  static String normalizedSubject(String text) =>
      FoodSearch.normalized(text).split(_wordSeparator).where((word) => word.isNotEmpty).take(4).join('-');

  Map<String, Object?> toJson() => {
    'topic': topic.rawValue,
    'subject': subject,
    'title': title,
    'text': text,
    'direction': direction.rawValue,
    'priority': priority,
    'origin': origin.rawValue,
    'created': swiftDateToJson(created),
    'validUntil': swiftDateToJson(validUntil),
    'basis': basis,
    'model': ?model,
    'uncertain': uncertain,
    'status': status.rawValue,
    'statusChanged': ?switch (statusChanged) {
      final date? => swiftDateToJson(date),
      null => null,
    },
  };

  /// Wie das synthetisierte `Decodable`: Werte werden unverändert übernommen (kein Normalisieren beim Lesen).
  static Insight? fromJson(Object? json) {
    if (json is! Map) return null;
    final topic = enumFromRaw(InsightTopic.values, json['topic']);
    final direction = enumFromRaw(InsightDirection.values, json['direction']);
    final origin = enumFromRaw(InsightOrigin.values, json['origin']);
    final status = enumFromRaw(InsightStatus.values, json['status']);
    final created = swiftDateFromJson(json['created']);
    final validUntil = swiftDateFromJson(json['validUntil']);
    final (subject, title, text) = (json['subject'], json['title'], json['text']);
    final priority = json['priority'];
    final uncertain = json['uncertain'];
    final basis = listStrict(json['basis'], (value) => value is String ? value : null);
    final model = json['model'];
    final rawChanged = json['statusChanged'];
    final statusChanged = rawChanged == null ? null : swiftDateFromJson(rawChanged);
    if (topic == null ||
        direction == null ||
        origin == null ||
        status == null ||
        created == null ||
        validUntil == null ||
        subject is! String ||
        title is! String ||
        text is! String ||
        priority is! int ||
        uncertain is! bool ||
        basis == null ||
        (model != null && model is! String) ||
        (rawChanged != null && statusChanged == null)) {
      return null;
    }
    return Insight._raw(
      topic: topic,
      subject: subject,
      title: title,
      text: text,
      direction: direction,
      priority: priority,
      origin: origin,
      created: created,
      validUntil: validUntil,
      basis: basis,
      model: model as String?,
      uncertain: uncertain,
      status: status,
      statusChanged: statusChanged,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Insight &&
      other.topic == topic &&
      other.subject == subject &&
      other.title == title &&
      other.text == text &&
      other.direction == direction &&
      other.priority == priority &&
      other.origin == origin &&
      other.created.isAtSameMomentAs(created) &&
      other.validUntil.isAtSameMomentAs(validUntil) &&
      const ListEquality<String>().equals(other.basis, basis) &&
      other.model == model &&
      other.uncertain == uncertain &&
      other.status == status &&
      other.statusChanged?.microsecondsSinceEpoch == statusChanged?.microsecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(topic, subject, title, text, direction, status);

  @override
  String toString() => 'Insight($id, ${status.rawValue}, $title)';
}

/// Gruppen für die Ansicht.
final class InsightGroups {
  InsightGroups();

  final List<Insight> newItems = [];
  final List<Insight> open = [];
  final List<Insight> closed = [];
  final List<Insight> expired = [];
}

/// Sammelt Empfehlungen aus Regeln und KI: keine Doppelten, keine Widersprüche, Bearbeitungsstand bleibt erhalten.
abstract final class InsightInbox {
  /// Erledigte und verworfene Empfehlungen bleiben so lange sichtbar (Verlauf), danach fallen sie weg.
  static const keepClosedDays = 30;

  /// Abgelaufene Empfehlungen bleiben so lange als „nicht mehr aktuell“.
  static const keepExpiredDays = 14;

  /// Neue Empfehlungen einsortieren.
  /// - Gleiche ID: Text wird aktualisiert; der Stand bleibt, außer der Inhalt hat sich geändert (dann wieder „neu“).
  ///   Verworfenes bleibt verworfen, solange es noch gilt und die Richtung gleich ist.
  /// - Gleicher Betreff, andere Richtung (Widerspruch): Regeln schlagen KI; sonst ersetzt die neuere die ältere.
  /// - Gleicher Titel unter anderem Betreff: doppelt, die ältere bleibt.
  static List<Insight> merge(List<Insight> existing, List<Insight> incoming, {required DateTime now}) {
    final result = [...existing];
    for (final candidate in incoming) {
      if (!candidate.isCurrent(now)) continue;
      final index = result.indexWhere((insight) => insight.id == candidate.id);
      if (index >= 0) {
        final current = result[index];
        if (current.origin == InsightOrigin.rules && candidate.origin == InsightOrigin.ai && current.isCurrent(now)) {
          continue;
        }
        var updated = candidate;
        final sameContent = current.text == candidate.text && current.direction == candidate.direction;
        if (sameContent || (current.status == InsightStatus.dismissed && current.direction == candidate.direction)) {
          updated = candidate.copyWith(
            status: current.status,
            statusChanged: () => current.statusChanged,
            created: current.created,
          );
        }
        result[index] = updated;
        continue;
      }
      final conflicts = [
        for (final insight in result)
          if (insight.contradicts(candidate) && insight.isCurrent(now) && insight.status != InsightStatus.dismissed)
            insight,
      ];
      if (conflicts.any((insight) => insight.origin == InsightOrigin.rules) && candidate.origin == InsightOrigin.ai) {
        continue;
      }
      final replaced = {for (final insight in conflicts) insight.id};
      result.removeWhere((insight) => replaced.contains(insight.id));
      final title = FoodSearch.normalized(candidate.title);
      if (result.any((insight) => FoodSearch.normalized(insight.title) == title && insight.isCurrent(now))) continue;
      result.add(candidate);
    }
    return prune(result, now: now);
  }

  /// Regel-Empfehlungen, die nicht mehr zutreffen, gelten ab jetzt als abgelaufen (die Regel hat sie zurückgezogen).
  static List<Insight> retireRules(List<Insight> insights, {required Set<String> keeping, required DateTime now}) => [
    for (final insight in insights)
      if (insight.origin != InsightOrigin.rules || keeping.contains(insight.id) || !insight.isCurrent(now))
        insight
      else
        insight.copyWith(validUntil: now),
  ];

  static List<Insight> setStatus(
    InsightStatus status, {
    required String id,
    required List<Insight> insights,
    required DateTime now,
  }) => [
    for (final insight in insights)
      insight.id == id ? insight.copyWith(status: status, statusChanged: () => now) : insight,
  ];

  static List<Insight> prune(List<Insight> insights, {required DateTime now}) => insights.where((insight) {
    if (insight.status == InsightStatus.done || insight.status == InsightStatus.dismissed) {
      return (insight.statusChanged ?? insight.created).isAfter(now.subtract(const Duration(days: keepClosedDays)));
    }
    return insight.validUntil.isAfter(now.subtract(const Duration(days: keepExpiredDays)));
  }).toList();

  /// [focus]: Themen in der Reihenfolge der Prioritäten der Person; bei gleicher Dringlichkeit zuerst.
  static InsightGroups groups(
    List<Insight> insights, {
    InsightTopic? topic,
    InsightCategory? category,
    List<InsightTopic> focus = const [],
    required DateTime now,
  }) {
    final groups = InsightGroups();
    int rank(InsightTopic topic) {
      final index = focus.indexOf(topic);
      return index < 0 ? focus.length : index;
    }

    final sorted = insights
        .where(
          (insight) => (topic == null || insight.topic == topic) && (category == null || insight.category == category),
        )
        .toList();
    mergeSort(
      sorted,
      compare: (a, b) {
        final byPriority = a.priority.compareTo(b.priority);
        if (byPriority != 0) return byPriority;
        final byRank = rank(a.topic).compareTo(rank(b.topic));
        if (byRank != 0) return byRank;
        return b.created.compareTo(a.created);
      },
    );
    for (final insight in sorted) {
      switch (insight.status) {
        case InsightStatus.done || InsightStatus.dismissed:
          groups.closed.add(insight);
        case InsightStatus.newInsight when insight.isCurrent(now):
          groups.newItems.add(insight);
        case InsightStatus.read when insight.isCurrent(now):
          groups.open.add(insight);
        default:
          groups.expired.add(insight);
      }
    }
    return groups;
  }

  static int unreadCount(List<Insight> insights, {required DateTime now}) =>
      insights.where((insight) => insight.status == InsightStatus.newInsight && insight.isCurrent(now)).length;
}

/// Eingaben für [InsightRules.build].
final class InsightRulesInput {
  const InsightRulesInput({
    required this.now,
    this.recommendation,
    this.sleep,
    this.gymObservations = const [],
    this.nutritionGaps = const [],
    this.planSuggestions = const [],
  });

  final DateTime now;
  final Recommendation? recommendation;
  final SleepReport? sleep;
  final List<String> gymObservations;
  final List<String> nutritionGaps;
  final List<PlanSuggestion> planSuggestions;
}

/// Empfehlungen aus den Regeln der App (ohne KI): Erholung, Schlaf, Stillstand und Volumen im Krafttraining,
/// Ernährungslücken und Planvorschläge. Jede Regel ist dieselbe wie an ihrem Ort in der App.
abstract final class InsightRules {
  static List<Insight> build(InsightRulesInput input) {
    final now = input.now;
    final local = now.toLocal();
    final endOfDay = DateTime(local.year, local.month, local.day).add(const Duration(days: 1));
    final inAWeek = now.add(const Duration(days: 7));
    final result = <Insight>[];

    final recommendation = input.recommendation;
    if (recommendation != null && recommendation.level != RecoveryLevel.normal) {
      result.add(
        Insight(
          topic: InsightTopic.recovery,
          subject: 'tagesform',
          title: recommendation.label,
          text: recommendation.advice,
          direction: InsightDirection.less,
          priority: 1,
          origin: InsightOrigin.rules,
          created: now,
          validUntil: endOfDay,
          basis: recommendation.reasons,
        ),
      );
    }

    final sleep = input.sleep;
    if (sleep != null && sleep.nights >= 3 && sleep.debtHours >= 3) {
      result.add(
        Insight(
          topic: InsightTopic.recovery,
          subject: 'schlaf',
          title: 'Schlaf nachholen',
          text:
              'In den letzten Nächten fehlen dir rund ${GermanFormat.decimal(sleep.debtHours)} Stunden Schlaf. '
              'Plane heute etwas mehr Zeit im Bett ein.',
          direction: InsightDirection.more,
          priority: 2,
          origin: InsightOrigin.rules,
          created: now,
          validUntil: endOfDay,
          basis: ['${sleep.nights} Nächte, Ø ${GermanFormat.decimal(sleep.averageHours)} h'],
        ),
      );
    }

    for (final observation in input.gymObservations) {
      // Wie `split(separator: ":", maxSplits: 1)`: leere Teile fallen weg.
      final separator = observation.indexOf(':');
      final parts =
          (separator < 0 ? [observation] : [observation.substring(0, separator), observation.substring(separator + 1)])
              .where((part) => part.isNotEmpty)
              .map((part) => part.trim())
              .toList();
      if (parts.length != 2) continue;
      final stalled = observation.contains('Stillstand');
      final tooMuch = observation.contains('mehr als');
      result.add(
        Insight(
          topic: stalled ? InsightTopic.stagnation : InsightTopic.training,
          subject: parts[0],
          title: stalled ? '${parts[0]}: Stillstand' : parts[0],
          text: parts[1],
          direction: stalled ? InsightDirection.change : (tooMuch ? InsightDirection.less : InsightDirection.more),
          priority: stalled ? 1 : 2,
          origin: InsightOrigin.rules,
          created: now,
          validUntil: inAWeek,
          basis: [observation],
        ),
      );
    }

    for (final gap in input.nutritionGaps) {
      final name = gap.split(':').firstWhereOrNull((part) => part.isNotEmpty) ?? gap;
      result.add(
        Insight(
          topic: InsightTopic.nutrition,
          subject: name,
          title: 'Mehr $name',
          text: '${gap.replaceAll('$name: ', 'Du kommst ')} – in den letzten zwei Wochen unter 80 % deines Ziels.',
          direction: InsightDirection.more,
          priority: 2,
          origin: InsightOrigin.rules,
          created: now,
          validUntil: inAWeek,
          basis: [gap],
        ),
      );
    }

    for (final suggestion in input.planSuggestions) {
      result.add(
        Insight(
          topic: InsightTopic.planning,
          subject: 'plan-${suggestion.id}',
          title: suggestion.title,
          text: '${suggestion.reason} Übernehmen kannst du den Vorschlag im Reiter Training.',
          direction: InsightDirection.change,
          priority: 2,
          origin: InsightOrigin.rules,
          created: now,
          validUntil: suggestion.week.adding(7).referenceDate,
          basis: [for (final change in suggestion.changes) change.text],
        ),
      );
    }
    return result;
  }
}

/// Ein nummerierter Fakt für die KI-Analyse.
final class InsightFact {
  const InsightFact({required this.id, required this.text});

  final String id;
  final String text;

  @override
  bool operator ==(Object other) => other is InsightFact && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'InsightFact($id, $text)';
}

/// KI-Analyse im Reiter „AI“ (Worker-Aufgabe `ai_insights`): Die App schickt nummerierte Fakten, fehlende Daten und
/// die Empfehlungen der Regeln; die KI darf nur daraus folgern und muss je Empfehlung Fakten nennen.
abstract final class InsightAnalysis {
  /// Fakten mit IDs (`f1`, `f2` …) aus Klartextzeilen.
  static List<InsightFact> facts(List<String> lines) {
    final texts = lines.where((line) => line.isNotEmpty).take(60).toList();
    return [for (var index = 0; index < texts.length; index++) InsightFact(id: 'f${index + 1}', text: texts[index])];
  }

  static Map<String, Object?> input({
    required InsightTopic? topic,
    required List<InsightFact> facts,
    required List<String> missing,
    required List<Insight> ruleInsights,
    List<Insight> closed = const [],
  }) => {
    // Umgesetztes und Verworfenes: nicht erneut vorschlagen, bei Umgesetztem die Wirkung bewerten.
    'bearbeitet': [
      for (final insight
          in closed
              .where(
                (insight) =>
                    (insight.status == InsightStatus.done || insight.status == InsightStatus.dismissed) &&
                    !insight.hasRawHealthValue,
              )
              .take(20))
        {'titel': insight.title, 'betreff': insight.subject, 'stand': insight.status.rawValue},
    ],
    'thema': topic?.rawValue ?? 'alle',
    'fakten': [
      for (final fact in facts) {'id': fact.id, 'text': fact.text},
    ],
    'fehlend': missing,
    'regeln': [
      for (final insight in ruleInsights)
        {'betreff': insight.subject, 'titel': insight.title, 'richtung': insight.direction.rawValue},
    ],
    'themen': [for (final topic in InsightTopic.values) topic.rawValue],
  };

  /// Liest die geprüfte Antwort des Workers. Fakten-IDs werden zu Klartext (intern), unbekannte Themen verworfen.
  static List<Insight> insights(
    JsonValue output, {
    required List<InsightFact> facts,
    required String model,
    required DateTime now,
  }) {
    final byID = <String, String>{};
    for (final fact in facts) {
      byID.putIfAbsent(fact.id, () => fact.text);
    }
    final result = <Insight>[];
    for (final item in output['empfehlungen']?.arrayValue ?? const <JsonValue>[]) {
      final topic = enumFromRaw(InsightTopic.values, item['thema']?.stringValue);
      final title = item['titel']?.stringValue;
      final text = item['text']?.stringValue;
      if (topic == null || title == null || title.isEmpty || text == null || text.isEmpty) continue;
      final basis = [
        for (final entry in item['belege']?.arrayValue ?? const <JsonValue>[])
          if (entry.stringValue case final id? when byID.containsKey(id)) byID[id]!,
      ];
      if (basis.isEmpty) continue;
      final days = item['gueltig_tage']?.clampedInt(1, 14) ?? 7;
      result.add(
        Insight(
          topic: topic,
          subject: item['betreff']?.stringValue ?? title,
          title: textPrefix(title, 80),
          text: textPrefix(text, 400),
          direction: enumFromRaw(InsightDirection.values, item['richtung']?.stringValue) ?? InsightDirection.check,
          priority: item['prioritaet']?.clampedInt(1, 3) ?? 2,
          origin: InsightOrigin.ai,
          created: now,
          validUntil: now.add(Duration(days: days)),
          basis: basis,
          model: model,
          uncertain: item['sicherheit']?.stringValue == 'niedrig',
        ),
      );
    }
    return result;
  }
}

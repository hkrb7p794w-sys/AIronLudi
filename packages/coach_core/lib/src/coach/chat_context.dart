import 'package:collection/collection.dart';

import '../ai/insights.dart';
import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_session.dart';
import '../json/json_value.dart';
import '../nutrition/nutrient.dart';
import '../nutrition/nutrition_planner.dart';
import '../nutrition/weight_trend.dart';
import '../profile/input_check.dart';
import '../profile/personalization.dart';
import '../profile/run_plan.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import '../util/german_format.dart';
import '../util/text_prefix.dart';
import 'coaching_note.dart';
import 'fitness_form.dart';
import 'sleep_coach.dart';

final _digit = RegExp(r'\p{N}', unicode: true);

/// Eine Nachricht im Chatverlauf (`role` ist „user“ oder „coach“).
typedef ChatMessage = ({String role, String text});

/// Worum es in einer Frage geht. Danach richtet sich, welche Daten die KI bekommt.
enum ChatTopic { strength, endurance, nutrition, recovery, longTerm, app }

/// Ordnet Fragen Themen zu, ohne KI: Das kostet nichts und ist prüfbar.
abstract final class ChatRouter {
  static const Map<ChatTopic, List<String>> _keywords = {
    ChatTopic.strength: [
      'bankdr',
      'kniebeug',
      'kreuzheb',
      'schulterdr',
      'klimmz',
      'rudern',
      'satz',
      'sätze',
      'wiederholung',
      'kraft',
      'gym',
      'übung',
      'progression',
      'deload',
      'gewicht steiger',
      'muskel',
    ],
    ChatTopic.endurance: [
      'lauf',
      'läuf',
      'jogg',
      'rennrad',
      'radfahr',
      'schwimm',
      'pace',
      'ausdauer',
      'intervall',
      'marathon',
      'triathlon',
      'kilometer',
      'zone 2',
    ],
    ChatTopic.nutrition: [
      'protein',
      'eiweiß',
      'eiweiss',
      'kalorien',
      'kcal',
      'essen',
      'mahlzeit',
      'ernähr',
      'kohlenhydr',
      'makro',
      'hunger',
      'abnehm',
      'zunehm',
      'trinken',
      'frühstück',
      'abendessen',
    ],
    ChatTopic.recovery: [
      'schlaf',
      'müde',
      'erhol',
      'regener',
      'hrv',
      'ruhepuls',
      'schwer trainieren',
      'heute trainieren',
      'belastung',
      'body battery',
      'krank',
      'ruhetag',
      'soll ich heute',
      'sollte ich heute',
    ],
    ChatTopic.longTerm: [
      'verlauf',
      'gewicht',
      'abnehm',
      'zunehm',
      'körperfett',
      'entwickel',
      'entwickl',
      'letzten wochen',
      'monat',
      'fortschritt',
      'langfrist',
      'trend',
      'seit',
    ],
    ChatTopic.app: ['in der app', 'einstellung', 'wo finde', 'wie stelle ich', 'widget', 'funktion'],
  };

  static Set<ChatTopic> topics({required String question, required List<ChatMessage> history}) {
    final result = match(question);
    if (isFollowUp(question)) {
      final recent = history.length > 4 ? history.sublist(history.length - 4) : history;
      for (final entry in recent) {
        if (entry.role == 'user') result.addAll(match(entry.text));
      }
      // Kommt nach einer Antwort „… und morgen?“, gehört der Plan dazu.
      if (question.toLowerCase().contains('training')) result.add(ChatTopic.recovery);
    }
    return result;
  }

  static Set<ChatTopic> match(String text) {
    final lower = text.toLowerCase();
    return {
      for (final MapEntry(:key, value: words) in _keywords.entries)
        if (words.any(lower.contains)) key,
    };
  }

  /// Kurze Nachfragen und Sätze, die sich auf das Vorherige beziehen.
  static bool isFollowUp(String question) {
    final lower = question.toLowerCase().trim();
    const starts = ['und ', 'aber ', 'was bedeutet', 'was heißt', 'warum', 'wieso', 'dann ', 'also ', 'dafür', 'das '];
    return starts.any(lower.startsWith) || lower.split(' ').where((word) => word.isNotEmpty).length <= 5;
  }
}

/// Eine erfasste Mahlzeit von heute.
final class ChatMealLine {
  const ChatMealLine({required this.title, required this.nutrients});

  final String title;
  final NutrientValues nutrients;
}

/// Fakten für den Chat (Port von `ChatContext.Facts`).
final class ChatFacts {
  ChatFacts({required this.profile, required this.privacy});

  UserProfile profile;
  PrivacyMode privacy;

  /// Gewichts- und Kalorienziele sind gesperrt (`GoalRules`).
  bool withholdsWeightTargets = false;
  String? recommendation;

  /// Nur für den Chat: Daten, aus denen die Antwort zur konkreten Frage entsteht.
  List<GymSession> gymSessions = [];
  List<GarminActivity> activities = [];
  NutrientValues? eaten;
  List<ChatMealLine> todayMeals = [];
  NutrientValues? weekAverage;
  List<String> tomorrowSessions = [];
  DailyMetrics? todayMetrics;
  List<Insight> insights = [];
  List<String> reasons = [];
  List<String> todaySessions = [];
  SleepReport? sleep;
  NutritionTargets? targets;
  double? eatenKilocalories;
  FormZone? formZone;
  List<String> weekHighlights = [];
  WeightTrendResult? weightTrend;
  RunWeek? runWeek;
  String? mobilityLine;

  /// Auswertung der letzten aufgezeichneten Einheiten (`ActivityFindings.contextLine`, schon passend zum
  /// Datenschutzmodus).
  List<String> activityFindings = [];
}

List<T> _suffix<T>(List<T> list, int count) => list.length > count ? list.sublist(list.length - count) : list;

/// Fakten für den Chat mit dem Coach: alles, was die Regeln der App berechnet haben, als kurze Sätze. Die KI darf
/// nur daraus antworten (Worker-Aufgabe `coach_chat`). Im Datenschutzmodus „reduziert“ gehen keine
/// Roh-Gesundheitswerte hinaus, nur Einordnungen.
abstract final class ChatContext {
  static const evidence = [
    'recovery.hrv',
    'recovery.rhr',
    'recovery.sleep',
    'sleep.regularity',
    'sleep.extension',
    'run.progression',
    'plan.deload',
    'taper',
    'nutrition.energy',
    'nutrition.protein',
    'weight.trend',
    'load.fitness-form',
    'gym.progression',
  ];

  static List<String> lines(ChatFacts facts, {CalendarDay? today}) {
    final full = facts.privacy == PrivacyMode.full;
    final lines = <String>[];
    final profile = facts.profile;
    lines.add('Sportarten: ${profile.sports.map((sport) => sport.label).join(', ')}.');
    // Haupt-/Nebenziele und Prioritäten: Die KI richtet Analyse und Empfehlungen danach aus (Paket 6).
    lines.addAll(Personalization.contextLines(profile.effectiveGoals(today ?? CalendarDay.today())));
    if (facts.withholdsWeightTargets) {
      lines.add('Keine Gewichts- oder Kalorienziele nennen und nicht zum Abnehmen raten.');
    }
    final event = profile.event;
    if (event != null) {
      final target = event.targetSeconds;
      lines.add(
        'Wettkampf: ${event.name} (${event.kind.label}) am ${GermanFormat.date(event.date)}'
        '${target == null ? '' : ', Zielzeit ${InputCheck.time(target.toDouble())}'}.',
      );
    }
    final recommendation = facts.recommendation;
    if (recommendation != null) {
      // Gründe enthalten Messwerte; im reduzierten Modus nur die Einordnung.
      final reasons = full && facts.reasons.isNotEmpty ? ' (${facts.reasons.join('; ')})' : '';
      lines.add('Tagesampel heute: $recommendation$reasons.');
    }
    lines.add(
      facts.todaySessions.isEmpty
          ? 'Heute ist keine Einheit geplant.'
          : 'Heute geplant: ${facts.todaySessions.join('; ')}.',
    );
    final week = facts.runWeek;
    if (week != null) {
      lines.add(
        'Laufwoche: ${week.phase.label}, ${week.totalMinutes} Minuten geplant, Schnitt der letzten vier Wochen '
        '${week.baselineMinutes} Minuten.',
      );
    }
    final sleep = facts.sleep;
    if (sleep != null) {
      if (full) {
        lines.add(
          'Schlaf der letzten ${sleep.nights} Nächte: im Schnitt ${GermanFormat.decimal(sleep.averageHours)} Stunden; '
          'empfohlene Schlafenszeit heute ${SleepCoach.clock(sleep.bedtimeMinutes)}.',
        );
      } else {
        final category = sleep.averageHours < 7 ? 'im Schnitt unter 7 Stunden' : 'im Schnitt mindestens 7 Stunden';
        lines.add(
          'Schlaf der letzten Nächte: $category; empfohlene Schlafenszeit heute ${SleepCoach.clock(sleep.bedtimeMinutes)}.',
        );
      }
      final spread = sleep.bedtimeSpreadMinutes;
      if (spread != null && spread > SleepCoach.irregularMinutes) {
        lines.add('Die Einschlafzeit schwankt stark.');
      }
    }
    final targets = facts.targets;
    if (targets != null) {
      final kcal = (targets.values[Nutrient.kcal] ?? 0).truncate();
      final protein = (targets.values[Nutrient.protein] ?? 0).truncate();
      var line = 'Tagesziel Ernährung (${targets.dayType.label}): $kcal kcal, $protein g Protein';
      final eaten = facts.eatenKilocalories;
      if (eaten != null) line += '; bisher erfasst ${eaten.round()} kcal';
      lines.add('$line.');
    }
    final trend = facts.weightTrend;
    if (trend != null) {
      if (full) {
        lines.add(
          'Gewichtstrend: ${GermanFormat.number(trend.trendKilograms)} kg, '
          '${GermanFormat.number(trend.weeklyPercent)} % pro Woche.',
        );
      } else {
        final direction = trend.weeklyPercent.abs() < 0.1
            ? 'stabil'
            : trend.weeklyPercent < 0
            ? 'leicht fallend'
            : 'leicht steigend';
        lines.add('Gewichtstrend: $direction.');
      }
    }
    final zone = facts.formZone;
    if (zone != null) lines.add('Form (Fitness gegen Ermüdung): ${zone.label}.');
    final mobility = facts.mobilityLine;
    if (mobility != null) lines.add(mobility);
    for (final finding in facts.activityFindings.take(3)) {
      lines.add('Auswertung der Aufzeichnung – $finding');
    }
    // Die Sätze des Wochenberichts enthalten Rohwerte (Schlafstunden, Ruhepuls).
    if (full) {
      for (final highlight in facts.weekHighlights.take(3)) {
        lines.add('Wochenbericht: $highlight');
      }
    }
    return lines;
  }

  static Map<String, Object?> input(
    ChatFacts facts, {
    required String question,
    required List<ChatMessage> history,
    CalendarDay? today,
  }) => {
    'question': textPrefix(question, 600),
    'history': [
      for (final entry in _suffix(history, 6)) {'role': entry.role, 'text': textPrefix(entry.text, 600)},
    ],
    'facts': lines(facts, today: today),
    'evidence': CoachingNote.evidenceInput(evidence),
  };

  /// Antwort aus `{"antwort": "...", "quellen": [...]}`.
  static ({String text, List<String> sources})? answer(JsonValue output) {
    final text = output['antwort']?.stringValue?.trim();
    if (text == null || text.isEmpty) return null;
    final sources = [for (final value in output['quellen']?.arrayValue ?? const <JsonValue>[]) ?value.stringValue];
    return (text: text, sources: sources);
  }

  static String _short(CalendarDay day) => GermanFormat.date(day);

  static int _grams(double? value) => (value ?? 0).round();

  /// Nur die Daten, die zur Frage gehören, mit Herkunft: gemessen, selbst erfasst oder von der App berechnet.
  static List<String> focusedLines(
    ChatFacts facts, {
    required Set<ChatTopic> topics,
    required String question,
    required CalendarDay today,
  }) {
    final lines = ['Heute ist ${Weekday.of(today).long}, ${_short(today)}.'];
    if (topics.isEmpty || (topics.length == 1 && topics.contains(ChatTopic.app))) return lines;
    lines.addAll(Personalization.contextLines(facts.profile.effectiveGoals(today)));
    if (facts.withholdsWeightTargets) {
      lines.add('Keine Gewichts- oder Kalorienziele nennen und nicht zum Abnehmen raten.');
    }
    if (topics.contains(ChatTopic.strength) ||
        topics.contains(ChatTopic.endurance) ||
        topics.contains(ChatTopic.recovery)) {
      lines.addAll(_planLines(facts));
    }
    if (topics.contains(ChatTopic.strength)) lines.addAll(_strengthLines(facts, question: question, today: today));
    if (topics.contains(ChatTopic.endurance)) lines.addAll(_enduranceLines(facts, today: today));
    if (topics.contains(ChatTopic.nutrition)) lines.addAll(_nutritionLines(facts));
    if (topics.contains(ChatTopic.recovery)) lines.addAll(_recoveryLines(facts, today: today));
    if (topics.contains(ChatTopic.longTerm)) lines.addAll(_longTermLines(facts, today: today));
    lines.addAll(_recommendationLines(facts, topics: topics));
    return lines;
  }

  static List<String> _planLines(ChatFacts facts) {
    final lines = [
      facts.todaySessions.isEmpty
          ? 'Heute ist keine Einheit geplant.'
          : 'Heute geplant: ${facts.todaySessions.join('; ')}.',
      facts.tomorrowSessions.isEmpty
          ? 'Morgen ist keine Einheit geplant.'
          : 'Morgen geplant: ${facts.tomorrowSessions.join('; ')}.',
    ];
    final recommendation = facts.recommendation;
    if (recommendation != null) lines.add('Tagesampel heute (Regel der App): $recommendation.');
    return lines;
  }

  static List<String> _strengthLines(ChatFacts facts, {required String question, required CalendarDay today}) {
    final lower = question.toLowerCase();
    final start = today.adding(-56);
    final sessions = facts.gymSessions.where((session) => session.day >= start).toList();
    mergeSort(sessions, compare: (a, b) => a.start.compareTo(b.start));
    final lines = <String>[];
    final seen = <String>{};
    final known = [for (final exercise in ExerciseLibrary.all) (id: exercise.id, name: exercise.name)];
    final logged = [
      for (final session in sessions)
        for (final exercise in session.exercises) (id: exercise.exerciseID, name: exercise.name),
    ];
    String set(LoggedSet value) => '${GermanFormat.number(value.weightKg)} kg für ${value.reps} Wiederholungen';
    for (final exercise in [...known, ...logged]) {
      if (!lower.contains(exercise.name.toLowerCase())) continue;
      if (!seen.add(exercise.id)) continue;
      final history = <({CalendarDay day, LoggedSet best, int count})>[];
      for (final session in sessions) {
        final entry = session.exercises.firstWhereOrNull((item) => item.exerciseID == exercise.id);
        if (entry == null) continue;
        final done = entry.doneSets;
        if (done.isEmpty) continue;
        // Wie `max(by:)` in Swift: bei Gleichstand der erste Satz.
        var best = done.first;
        for (final candidate in done.skip(1)) {
          if (best.weightKg < candidate.weightKg ||
              (best.weightKg == candidate.weightKg && best.reps < candidate.reps)) {
            best = candidate;
          }
        }
        history.add((day: session.day, best: best, count: done.length));
      }
      if (history.isEmpty) {
        lines.add('${exercise.name}: keine erfassten Sätze in den letzten 8 Wochen.');
        continue;
      }
      for (final item in _suffix(history, 8)) {
        lines.add(
          '${exercise.name} am ${_short(item.day)}: bester Satz ${set(item.best)}, ${item.count} Arbeitssätze (erfasst).',
        );
      }
      final recent = history.where((item) => item.day >= today.adding(-28)).toList();
      if (recent.length >= 2) {
        final (first, last) = (recent.first, recent.last);
        final change = last.best.weightKg - first.best.weightKg;
        lines.add(
          '${exercise.name} in den letzten 4 Wochen: von ${set(first.best)} auf ${set(last.best)}, '
          'Differenz ${GermanFormat.number(change)} kg (berechnet aus ${recent.length} Einheiten).',
        );
      } else {
        lines.add('${exercise.name}: zu wenige Einheiten in den letzten 4 Wochen für eine Entwicklung.');
      }
    }
    if (lines.isEmpty) {
      for (final session in _suffix(sessions, 5)) {
        final volume = session.exercises
            .expand((exercise) => exercise.doneSets)
            .fold(0.0, (sum, set) => sum + set.loadKg * set.reps);
        final sets = session.exercises.fold(0, (sum, exercise) => sum + exercise.doneSets.length);
        lines.add(
          'Krafteinheit ${_short(session.day)} (${session.title}): $sets Arbeitssätze, '
          '${GermanFormat.number(volume.roundToDouble())} kg Volumen (erfasst).',
        );
      }
      if (sessions.isEmpty) lines.add('Keine Krafteinheiten in den letzten 8 Wochen erfasst.');
    }
    return lines;
  }

  static String _activityDay(GarminActivity activity) => switch (activity.day) {
    final day? => _short(day),
    null => '?',
  };

  static List<String> _enduranceLines(ChatFacts facts, {required CalendarDay today}) {
    final lines = <String>[];
    final week = facts.runWeek;
    if (week != null) {
      lines.add(
        'Laufwoche: ${week.phase.label}, ${week.totalMinutes} Minuten geplant, Schnitt der letzten vier Wochen '
        '${week.baselineMinutes} Minuten.',
      );
    }
    final recent = _suffix(
      facts.activities.where((activity) => (activity.day ?? today) >= today.adding(-28)).toList(),
      8,
    );
    for (final activity in recent) {
      final minutes = ((activity.durationSeconds ?? 0) / 60).truncate();
      final distance = switch (activity.distanceMeters) {
        final meters? => ', ${GermanFormat.decimal(meters / 1000)} km',
        null => '',
      };
      lines.add('${activity.name ?? 'Aktivität'} am ${_activityDay(activity)}: $minutes Minuten$distance (gemessen).');
    }
    if (recent.isEmpty) lines.add('Keine Ausdaueraktivitäten in den letzten 4 Wochen vorhanden.');
    return lines;
  }

  /// Titel können von anderen Personen stammen (geteilte Mahlzeit). Zahlen darin dürfen nicht als belegt gelten.
  static String _mealTitle(ChatMealLine meal) => meal.title.replaceAll(_digit, '').trim();

  static List<String> _nutritionLines(ChatFacts facts) {
    // Schutzgrenze aktiv (z. B. Essstörung): keine Kalorien und Mengen, auch nicht als erfasste Werte.
    if (facts.withholdsWeightTargets) {
      return [for (final meal in facts.todayMeals.take(8)) 'Mahlzeit heute: ${_mealTitle(meal)}.'];
    }
    final lines = <String>[];
    final eaten = facts.eaten;
    if (eaten != null) {
      lines.add(
        'Heute bisher erfasst: ${_grams(eaten[Nutrient.kcal])} kcal, ${_grams(eaten[Nutrient.protein])} g Protein, '
        '${_grams(eaten[Nutrient.carbs])} g Kohlenhydrate, ${_grams(eaten[Nutrient.fat])} g Fett '
        '(erfasst, teils KI-Schätzung).',
      );
      for (final meal in facts.todayMeals.take(8)) {
        lines.add(
          'Mahlzeit heute: ${_mealTitle(meal)}, ${_grams(meal.nutrients[Nutrient.kcal])} kcal, '
          '${_grams(meal.nutrients[Nutrient.protein])} g Protein.',
        );
      }
    } else {
      lines.add('Heute ist noch keine Mahlzeit erfasst.');
    }
    final targets = facts.targets;
    if (targets != null) {
      final goalKcal = _grams(targets.values[Nutrient.kcal]);
      final goalProtein = _grams(targets.values[Nutrient.protein]);
      lines.add('Tagesziel (Regel der App, ${targets.dayType.label}): $goalKcal kcal, $goalProtein g Protein.');
      final openKcal = goalKcal - _grams(eaten?[Nutrient.kcal]);
      final openProtein = goalProtein - _grams(eaten?[Nutrient.protein]);
      lines.add(
        'Noch offen heute (berechnet): ${openKcal < 0 ? 0 : openKcal} kcal, '
        '${openProtein < 0 ? 0 : openProtein} g Protein.',
      );
    }
    final average = facts.weekAverage;
    if (average != null) {
      lines.add(
        'Schnitt der letzten 7 erfassten Tage: ${_grams(average[Nutrient.kcal])} kcal, '
        '${_grams(average[Nutrient.protein])} g Protein.',
      );
    }
    return lines;
  }

  static List<String> _recoveryLines(ChatFacts facts, {required CalendarDay today}) {
    final full = facts.privacy == PrivacyMode.full;
    final lines = <String>[];
    if (full && facts.reasons.isNotEmpty) lines.add('Begründung der Ampel: ${facts.reasons.join('; ')}.');
    final sleep = facts.sleep;
    if (sleep != null) {
      lines.add(
        full
            ? 'Schlaf der letzten ${sleep.nights} Nächte: im Schnitt ${GermanFormat.decimal(sleep.averageHours)} '
                  'Stunden (gemessen).'
            : 'Schlaf der letzten Nächte: '
                  '${sleep.averageHours < 7 ? 'im Schnitt unter 7 Stunden' : 'im Schnitt mindestens 7 Stunden'}.',
      );
      lines.add('Empfohlene Schlafenszeit heute: ${SleepCoach.clock(sleep.bedtimeMinutes)}.');
    } else {
      lines.add('Zu wenige Schlafdaten für eine Einschätzung.');
    }
    final metrics = facts.todayMetrics;
    if (full && metrics != null) {
      if (metrics.restingHeartRate case final value?) lines.add('Ruhepuls heute: ${value.truncate()} (gemessen).');
      if (metrics.hrvLastNightAverage case final value?) {
        lines.add('HRV letzte Nacht: ${value.truncate()} ms (gemessen).');
      }
    }
    final zone = facts.formZone;
    if (zone != null) lines.add('Form (Fitness gegen Ermüdung): ${zone.label}.');
    final lastDays = facts.gymSessions.where((session) => session.day >= today.adding(-3)).toList();
    for (final session in _suffix(lastDays, 3)) {
      lines.add('Krafteinheit am ${_short(session.day)}: ${session.title} (erfasst).');
    }
    final activities = facts.activities.where((activity) => (activity.day ?? today) >= today.adding(-3)).toList();
    for (final activity in _suffix(activities, 3)) {
      lines.add(
        '${activity.name ?? 'Aktivität'} am ${_activityDay(activity)}: '
        '${((activity.durationSeconds ?? 0) / 60).truncate()} Minuten (gemessen).',
      );
    }
    return lines;
  }

  static List<String> _longTermLines(ChatFacts facts, {required CalendarDay today}) {
    final lines = <String>[];
    final gym = facts.gymSessions.where((session) => session.day >= today.adding(-28)).length;
    final activities = facts.activities.where((activity) => (activity.day ?? today) >= today.adding(-28)).length;
    lines.add('In den letzten 4 Wochen: $gym Krafteinheiten, $activities Ausdaueraktivitäten.');
    final trend = facts.weightTrend;
    if (trend != null && !facts.withholdsWeightTargets) {
      if (facts.privacy == PrivacyMode.full) {
        lines.add(
          'Gewichtstrend: ${GermanFormat.number(trend.trendKilograms)} kg, '
          '${GermanFormat.number(trend.weeklyPercent)} % pro Woche (berechnet).',
        );
      } else {
        final direction = trend.weeklyPercent.abs() < 0.1
            ? 'stabil'
            : trend.weeklyPercent < 0
            ? 'fallend'
            : 'steigend';
        lines.add('Gewichtstrend: $direction.');
      }
    }
    if (facts.privacy == PrivacyMode.full) {
      for (final highlight in facts.weekHighlights.take(3)) {
        lines.add('Wochenbericht: $highlight');
      }
    }
    return lines;
  }

  /// Frühere Empfehlungen aus dem passenden Bereich und ob sie umgesetzt wurden.
  static List<String> _recommendationLines(ChatFacts facts, {required Set<ChatTopic> topics}) {
    final wanted = <InsightCategory>{};
    if (topics.contains(ChatTopic.strength)) wanted.add(InsightCategory.strength);
    if (topics.contains(ChatTopic.endurance)) wanted.add(InsightCategory.endurance);
    if (topics.contains(ChatTopic.nutrition)) {
      wanted.addAll([InsightCategory.nutrition, InsightCategory.bodyComposition]);
    }
    if (topics.contains(ChatTopic.recovery)) wanted.addAll([InsightCategory.recovery, InsightCategory.health]);
    if (topics.contains(ChatTopic.longTerm)) wanted.addAll(InsightCategory.values);
    final visible = facts.insights
        .where((insight) => facts.privacy == PrivacyMode.full || !insight.hasRawHealthValue)
        .where((insight) => wanted.contains(insight.category))
        .toList();
    mergeSort(visible, compare: (a, b) => b.created.compareTo(a.created));
    return [
      for (final insight in visible.take(5))
        'Frühere Empfehlung (${switch (insight.status) {
          InsightStatus.done => 'umgesetzt',
          InsightStatus.dismissed => 'von der Person verworfen',
          _ => 'offen',
        }}): ${insight.title}.',
    ];
  }

  /// Eingabe des Chats: Daten passend zur Frage, die letzten Nachrichten und ältere Fragen in Kurzform.
  static Map<String, Object?> focusedInput(
    ChatFacts facts, {
    required String question,
    required List<ChatMessage> history,
    required CalendarDay today,
  }) {
    final topics = ChatRouter.topics(question: question, history: history);
    final recent = _suffix(history, 10);
    final older = [
      for (final entry in history.take(history.length - recent.length))
        if (entry.role == 'user') textPrefix(entry.text, 80),
    ];
    return {
      'question': textPrefix(question, 600),
      'history': [
        for (final entry in recent) {'role': entry.role, 'text': textPrefix(entry.text, 800)},
      ],
      'olderQuestions': _suffix(older, 6),
      'facts': focusedLines(facts, topics: topics, question: question, today: today),
      'evidence': CoachingNote.evidenceInput(evidence),
    };
  }
}

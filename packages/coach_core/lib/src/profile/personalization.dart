import 'package:collection/collection.dart';

import '../ai/insights.dart';
import '../calendar/calendar_day.dart';
import '../health/health_dashboard.dart';
import '../integration/data_provider.dart';
import '../util/enum_codec.dart';
import 'schedule_check.dart';
import 'user_profile.dart';
import 'week_load.dart';

/// Trainingsziele für Haupt- und Nebenziele.
enum TrainingGoal implements RawEnum {
  muscleGain('Muskelaufbau', 'Mehr Krafteinheiten, Fortschritt nach Volumen, leichter Kalorienüberschuss.'),
  fatLoss('Fettabbau', 'Moderates Defizit mit viel Protein, Kraft zum Muskelerhalt.'),
  strength('Kraftsteigerung', 'Schwere Grundübungen, Fortschritt nach Gewicht, genug Pausen.'),
  endurance('Ausdauer verbessern', 'Mehr Ausdauereinheiten, überwiegend locker, Fortschritt nach Pace und Puls.'),
  generalFitness('Allgemeine Fitness', 'Ausgewogener Mix aus Kraft und Ausdauer.'),
  recovery('Bessere Regeneration', 'Vorsichtigere Steigerung, Schlaf und Erholung stehen vorne.'),
  health('Gesundheit', 'Regelmäßigkeit vor Leistung, Ruhepuls und Schlaf im Blick.'),
  competition('Wettkampfvorbereitung', 'Plan auf das Rennen ausgerichtet, Steigerung und Tapering.');

  const TrainingGoal(this.label, this.effect);

  final String label;

  /// Was die App daraus macht (im Onboarding unter dem Ziel).
  final String effect;

  @override
  String get rawValue => name;
}

/// Bereiche, die der Person besonders wichtig sind. Sie steuern Reihenfolge und Gewichtung, nicht die Regeln selbst.
enum FocusArea implements RawEnum {
  muscle('Muskelaufbau'),
  endurance('Ausdauer'),
  bodyComposition('Körperkomposition'),
  sleep('Schlaf'),
  recovery('Recovery'),
  nutrition('Ernährung'),
  performance('Leistungssteigerung'),
  health('Gesundheit');

  const FocusArea(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Fitness-Tracker der Person (aus dem Onboarding; ändert sich in Einstellungen › Datenquellen).
final class TrackerSetup {
  const TrackerSetup({this.usesTracker, this.providers = const []});

  /// `null` = nicht beantwortet (übersprungen).
  final bool? usesTracker;
  final List<DataProvider> providers;

  Map<String, Object?> toJson() => {
    'usesTracker': ?usesTracker,
    'providers': [for (final provider in providers) provider.rawValue],
  };

  static TrackerSetup fromJson(Object? json) {
    if (json is! Map) return const TrackerSetup();
    // Synthetisiertes Codable in Swift: unbekannter Anbieter → ganzes Objekt auf Standard.
    final providers = json['providers'] == null
        ? const <DataProvider>[]
        : enumListStrict(DataProvider.values, json['providers']);
    if (providers == null) return const TrackerSetup();
    return TrackerSetup(
      usesTracker: json['usesTracker'] is bool ? json['usesTracker'] as bool : null,
      providers: providers,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrackerSetup &&
      other.usesTracker == usesTracker &&
      const ListEquality<DataProvider>().equals(other.providers, providers);

  @override
  int get hashCode => Object.hash(usesTracker, const ListEquality<DataProvider>().hash(providers));
}

/// Ziele und Prioritäten zu einem Zeitpunkt. Änderungen gelten ab [since]; ältere Stände bleiben im Verlauf, damit
/// Auswertungen früherer Zeiträume nicht nachträglich anders aussehen.
final class PersonalGoals {
  PersonalGoals({
    required this.primary,
    List<TrainingGoal> secondary = const [],
    List<FocusArea> priorities = const [],
    required this.since,
  }) : secondary = List.unmodifiable(_unique(secondary, exclude: primary).take(maxSecondary)),
       priorities = List.unmodifiable(_unique(priorities).take(maxPriorities));

  static const maxSecondary = 2;
  static const maxPriorities = 3;

  final TrainingGoal primary;

  /// Höchstens [maxSecondary], ohne das Hauptziel.
  final List<TrainingGoal> secondary;

  /// Wichtigste zuerst, höchstens [maxPriorities].
  final List<FocusArea> priorities;
  final CalendarDay since;

  static List<T> _unique<T>(List<T> values, {T? exclude}) {
    final seen = <T>{?exclude};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }

  List<TrainingGoal> get all => [primary, ...secondary];

  bool has(TrainingGoal goal) => all.contains(goal);

  /// Prioritäten, ohne Angabe aus den Zielen abgeleitet (sinnvoller Standard).
  List<FocusArea> get effectivePriorities => priorities.isEmpty ? Personalization.defaultPriorities(all) : priorities;

  PersonalGoals copyWith({
    TrainingGoal? primary,
    List<TrainingGoal>? secondary,
    List<FocusArea>? priorities,
    CalendarDay? since,
  }) => PersonalGoals(
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    priorities: priorities ?? this.priorities,
    since: since ?? this.since,
  );

  Map<String, Object?> toJson() => {
    'primary': primary.rawValue,
    'secondary': [for (final goal in secondary) goal.rawValue],
    'priorities': [for (final area in priorities) area.rawValue],
    'since': since.toJson(),
  };

  /// Tolerant: unbekannte Ziele oder Prioritäten (neuere Version) werden übersprungen. Ohne gültiges Hauptziel `null`.
  static PersonalGoals? fromJson(Object? json) {
    if (json is! Map) return null;
    final primary = enumFromRaw(TrainingGoal.values, json['primary']);
    if (primary == null) return null;
    final since = json['since'];
    return PersonalGoals(
      primary: primary,
      secondary: enumListFromRaw(TrainingGoal.values, json['secondary']),
      priorities: enumListFromRaw(FocusArea.values, json['priorities']),
      since: since is Map ? CalendarDay.fromJson(since.cast<String, Object?>()) : const CalendarDay(2000, 1, 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PersonalGoals &&
      other.primary == primary &&
      const ListEquality<TrainingGoal>().equals(other.secondary, secondary) &&
      const ListEquality<FocusArea>().equals(other.priorities, priorities) &&
      other.since == since;

  @override
  int get hashCode => Object.hash(primary, Object.hashAll(secondary), Object.hashAll(priorities), since);

  @override
  String toString() => 'PersonalGoals(${primary.name}, $secondary, $priorities, $since)';
}

/// Eine Stelle für alles, was aus Zielen und Prioritäten folgt. Regeln entscheiden, die KI formuliert.
///
abstract final class Personalization {
  /// Ziele aus dem bisherigen Einzelziel (`FitnessGoal`) und einem Wettkampf – für Profile von vor Paket 6.
  static PersonalGoals derived(UserProfile profile, {required CalendarDay since}) {
    if (profile.mode == ProfileMode.season) {
      return PersonalGoals(
        primary: TrainingGoal.competition,
        secondary: const [TrainingGoal.endurance, TrainingGoal.strength],
        priorities: const [FocusArea.performance, FocusArea.endurance, FocusArea.recovery],
        since: since,
      );
    }
    var secondary = <TrainingGoal>[];
    final TrainingGoal primary;
    switch (profile.goal) {
      case FitnessGoal.loseWeight:
        primary = TrainingGoal.fatLoss;
      case FitnessGoal.loseAndBuild:
        primary = TrainingGoal.fatLoss;
        secondary = [TrainingGoal.muscleGain];
      case FitnessGoal.buildMuscle || FitnessGoal.gainWeight:
        primary = TrainingGoal.muscleGain;
      case FitnessGoal.improveFitness:
        primary = TrainingGoal.endurance;
      case FitnessGoal.maintain:
        primary = TrainingGoal.generalFitness;
    }
    if (profile.event != null) {
      return PersonalGoals(primary: TrainingGoal.competition, secondary: [primary, ...secondary], since: since);
    }
    return PersonalGoals(primary: primary, secondary: secondary, since: since);
  }

  /// Richtung für Ernährung und Gewicht (`FitnessGoal`, steuert Kalorienziel und Schutzgrenzen) aus den Zielen.
  static FitnessGoal fitnessGoal(PersonalGoals goals) {
    final builds = goals.has(TrainingGoal.muscleGain) || goals.has(TrainingGoal.strength);
    final fatLoss = goals.has(TrainingGoal.fatLoss);
    return switch (goals.primary) {
      TrainingGoal.fatLoss => builds ? FitnessGoal.loseAndBuild : FitnessGoal.loseWeight,
      TrainingGoal.muscleGain => FitnessGoal.buildMuscle,
      TrainingGoal.strength => fatLoss ? FitnessGoal.loseAndBuild : FitnessGoal.buildMuscle,
      TrainingGoal.endurance ||
      TrainingGoal.competition => fatLoss ? FitnessGoal.loseWeight : FitnessGoal.improveFitness,
      TrainingGoal.generalFitness ||
      TrainingGoal.recovery ||
      TrainingGoal.health => fatLoss ? FitnessGoal.loseWeight : FitnessGoal.maintain,
    };
  }

  /// Standard-Prioritäten zu den Zielen (wenn die Person keine wählt).
  static List<FocusArea> defaultPriorities(List<TrainingGoal> goals) {
    final result = <FocusArea>[];
    void add(List<FocusArea> areas) {
      for (final area in areas) {
        if (!result.contains(area)) result.add(area);
      }
    }

    for (final goal in goals) {
      add(switch (goal) {
        TrainingGoal.muscleGain => [FocusArea.muscle, FocusArea.nutrition],
        TrainingGoal.fatLoss => [FocusArea.bodyComposition, FocusArea.nutrition],
        TrainingGoal.strength => [FocusArea.muscle, FocusArea.performance],
        TrainingGoal.endurance => [FocusArea.endurance, FocusArea.recovery],
        TrainingGoal.generalFitness => [FocusArea.health, FocusArea.endurance],
        TrainingGoal.recovery => [FocusArea.recovery, FocusArea.sleep],
        TrainingGoal.health => [FocusArea.health, FocusArea.sleep],
        TrainingGoal.competition => [FocusArea.performance, FocusArea.recovery],
      });
    }
    return result.take(PersonalGoals.maxPriorities).toList();
  }

  /// Höchste Steigerung der Wochenbelastung, ab der gewarnt wird: vorsichtiger bei Regeneration oder Gesundheit als
  /// Haupt- oder Prioritätsziel (20 statt 30 %).
  static double maxLoadIncrease(PersonalGoals goals) {
    final careful =
        goals.primary == TrainingGoal.recovery ||
        goals.primary == TrainingGoal.health ||
        goals.effectivePriorities.take(2).any((area) => area == FocusArea.recovery || area == FocusArea.health);
    return careful ? 0.20 : WeekLoad.maxIncrease;
  }

  /// Gewünschte Einheiten je Sportart, angepasst an Haupt- und Nebenziele (nach `SchedulePlanner.wantedCounts`).
  static Map<TrainingSport, int> adjustCounts(
    Map<TrainingSport, int> counts, {
    required PersonalGoals goals,
    required UserProfile profile,
  }) {
    final result = Map.of(counts);
    final beginner = ScheduleCheck.overallLevel(profile) == ExperienceLevel.beginner;
    void atLeast(TrainingSport sport, int count) {
      if (!profile.trains(sport)) return;
      final current = result[sport] ?? 0;
      result[sport] = current > count ? current : count;
    }

    switch (goals.primary) {
      case TrainingGoal.muscleGain || TrainingGoal.strength:
        atLeast(TrainingSport.strength, beginner ? 3 : 4);
      case TrainingGoal.endurance:
        for (final sport in profile.sports.where((sport) => sport.isEndurance)) {
          atLeast(sport, beginner ? 2 : 3);
        }
      default:
        break;
    }
    if (goals.secondary.contains(TrainingGoal.muscleGain) || goals.secondary.contains(TrainingGoal.strength)) {
      atLeast(TrainingSport.strength, 2);
    }
    if (goals.secondary.contains(TrainingGoal.endurance)) {
      final main = profile.sports.where((sport) => sport.isEndurance).firstOrNull;
      if (main != null) atLeast(main, 2);
    }
    if (goals.primary == TrainingGoal.recovery || goals.primary == TrainingGoal.health) {
      // Regelmäßig, aber nicht viel: höchstens 2 je Sportart.
      for (final sport in result.keys.toList()) {
        if (result[sport]! > 2) result[sport] = 2;
      }
    }
    return result;
  }

  /// Reihenfolge der Health-Widgets für ein neues bzw. nicht angepasstes Dashboard.
  static List<HealthWidget> healthWidgets(PersonalGoals goals) {
    final order = <HealthWidget>[];
    void add(List<HealthWidget> widgets) {
      for (final widget in widgets) {
        if (!order.contains(widget)) order.add(widget);
      }
    }

    for (final area in goals.effectivePriorities) {
      add(switch (area) {
        FocusArea.sleep => const [HealthWidget.sleep, HealthWidget.hrv],
        FocusArea.recovery => const [HealthWidget.bodyBattery, HealthWidget.hrv, HealthWidget.recoveryTime],
        FocusArea.health => const [HealthWidget.restingHeartRate, HealthWidget.steps],
        FocusArea.endurance => const [HealthWidget.vo2Max, HealthWidget.trainingLoad],
        FocusArea.performance => const [HealthWidget.trainingLoad, HealthWidget.vo2Max],
        FocusArea.bodyComposition => const [HealthWidget.weight, HealthWidget.activeCalories],
        FocusArea.muscle => const [HealthWidget.weight, HealthWidget.trainingLoad],
        FocusArea.nutrition => const [HealthWidget.weight, HealthWidget.restingCalories],
      });
    }
    add(HealthDashboard.standard);
    return order;
  }

  /// Empfehlungs-Themen in der Reihenfolge der Prioritäten (für den Reiter „AI“).
  static List<InsightTopic> insightTopics(PersonalGoals goals) {
    final order = <InsightTopic>[];
    void add(List<InsightTopic> topics) {
      for (final topic in topics) {
        if (!order.contains(topic)) order.add(topic);
      }
    }

    for (final area in goals.effectivePriorities) {
      add(switch (area) {
        FocusArea.muscle => const [InsightTopic.training, InsightTopic.progress, InsightTopic.stagnation],
        FocusArea.endurance => const [InsightTopic.training, InsightTopic.performance],
        FocusArea.bodyComposition => const [InsightTopic.nutrition, InsightTopic.progress],
        FocusArea.sleep || FocusArea.recovery || FocusArea.health => const [InsightTopic.recovery],
        FocusArea.nutrition => const [InsightTopic.nutrition],
        FocusArea.performance => const [InsightTopic.performance, InsightTopic.progress],
      });
    }
    return order;
  }

  /// Zeilen für den KI-Kontext (Chat, Analyse, Tagesnotiz): Ziele, Prioritäten und worauf Empfehlungen achten sollen.
  static List<String> contextLines(PersonalGoals goals) => [
    'Hauptziel: ${goals.primary.label}'
        '${goals.secondary.isEmpty ? '' : '; Nebenziele: ${goals.secondary.map((goal) => goal.label).join(', ')}'}.',
    'Prioritäten der Person: ${goals.effectivePriorities.map((area) => area.label).join(', ')}.',
    'Empfehlungen daran ausrichten: ${guidance(goals.primary)}',
  ];

  static String guidance(TrainingGoal goal) => switch (goal) {
    TrainingGoal.muscleGain =>
      'Kraftvolumen und Progression bewerten, Protein und leichter Überschuss; Ausdauer nur ergänzend.',
    TrainingGoal.fatLoss => 'Muskelerhalt durch Kraft und Protein, moderates Defizit; kein Crash-Defizit.',
    TrainingGoal.strength =>
      'Fortschritt der Grundübungen nach Gewicht, ausreichend Pausen zwischen schweren Einheiten.',
    TrainingGoal.endurance => 'Umfang überwiegend locker (Zone 2), wenige harte Einheiten; Pace und Puls im Verlauf.',
    TrainingGoal.generalFitness => 'Ausgewogenheit und Regelmäßigkeit vor Höchstleistung.',
    TrainingGoal.recovery => 'Schlaf, HRV und Ruhepuls zuerst; Belastung nur vorsichtig steigern.',
    TrainingGoal.health => 'Regelmäßige moderate Bewegung, Schlaf und Ruhepuls; keine Leistungsziele erzwingen.',
    TrainingGoal.competition =>
      'Auf das Rennen hin periodisieren (Aufbau, Spitze, Tapering); Schlüsseleinheiten schützen.',
  };
}

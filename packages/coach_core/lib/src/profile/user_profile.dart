import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/season_plan.dart';
import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';
import 'personalization.dart';
import 'week_schedule.dart';

/// Sportarten, aus denen Nutzer:innen wählen.
enum TrainingSport implements RawEnum {
  run('Laufen'),
  strength('Krafttraining'),
  bike('Radfahren'),
  swim('Schwimmen'),
  other('Anderes (Yoga, Wandern …)');

  const TrainingSport(this.label);

  final String label;

  @override
  String get rawValue => name;

  ActivitySport get garminSport => switch (this) {
    run => ActivitySport.run,
    strength => ActivitySport.strength,
    bike => ActivitySport.bike,
    swim => ActivitySport.swim,
    other => ActivitySport.other,
  };

  /// Ausdauersportart (für Intensitätsverteilung und Ruhepuls-Ziel).
  bool get isEndurance => this == run || this == bike || this == swim;

  /// Symbolname (SF Symbols wie in Swift; die App bildet ihn auf ihre Icons ab).
  String get symbol => switch (this) {
    run => 'figure.run',
    strength => 'dumbbell.fill',
    bike => 'figure.outdoor.cycle',
    swim => 'figure.pool.swim',
    other => 'figure.yoga',
  };
}

/// Hauptziel. Aus ihm folgen Ernährungsziel, Trainingsverteilung und Hinweise.
enum FitnessGoal implements RawEnum {
  loseWeight('Abnehmen', 'Langsam und gesund Gewicht verlieren, Muskeln erhalten.'),
  loseAndBuild('Abnehmen und Muskeln aufbauen', 'Körperfett senken und gleichzeitig Kraft aufbauen.'),
  buildMuscle('Muskeln aufbauen', 'Mehr Muskelmasse und Kraft mit leichtem Überschuss.'),
  gainWeight('Zunehmen', 'Gesund zunehmen, vor allem als Muskelmasse.'),
  improveFitness('Fitter werden', 'Ausdauer, Tempo oder Ruhepuls verbessern.'),
  maintain('Fit bleiben, Gewicht halten', 'Das aktuelle Niveau halten und regelmäßig trainieren.');

  const FitnessGoal(this.label, this.detail);

  final String label;
  final String detail;

  @override
  String get rawValue => name;

  /// Ziele, die das Körpergewicht senken sollen.
  bool get losesWeight => this == loseWeight || this == loseAndBuild;

  bool get gainsWeight => this == gainWeight || this == buildMuscle;
}

enum ExperienceLevel implements RawEnum {
  beginner('Einsteiger:in', 'Neu dabei oder nach langer Pause wieder eingestiegen.'),
  intermediate('Fortgeschritten', 'Seit über 6 Monaten regelmäßig dabei.'),
  advanced('Erfahren', 'Seit Jahren strukturiert unterwegs.');

  const ExperienceLevel(this.label, this.detail);

  final String label;
  final String detail;

  @override
  String get rawValue => name;
}

enum EventKind implements RawEnum {
  run5k('5-km-Lauf', 5),
  run10k('10-km-Lauf', 10),
  halfMarathon('Halbmarathon', 21.0975),
  marathon('Marathon', 42.195),
  triathlon('Triathlon', null),
  other('Anderer Wettkampf', null);

  const EventKind(this.label, this.distanceKilometers);

  final String label;
  final double? distanceKilometers;

  @override
  String get rawValue => name;

  bool get isRunning => distanceKilometers != null;
}

/// Ein Wettkampf oder Lauf, auf den sich jemand vorbereitet.
final class EventGoal {
  const EventGoal({required this.name, required this.date, required this.kind, this.targetSeconds});

  final String name;
  final CalendarDay date;
  final EventKind kind;

  /// Zielzeit in Sekunden (optional).
  final int? targetSeconds;

  Map<String, Object?> toJson() => {
    'name': name,
    'date': date.toJson(),
    'kind': kind.rawValue,
    'targetSeconds': ?targetSeconds,
  };

  static EventGoal? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final date = json['date'];
    final kind = enumFromRaw(EventKind.values, json['kind']);
    if (name is! String || date is! Map || kind == null) return null;
    return EventGoal(
      name: name,
      date: CalendarDay.fromJson(date.cast<String, Object?>()),
      kind: kind,
      targetSeconds: jsonInt(json['targetSeconds']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EventGoal &&
      other.name == name &&
      other.date == date &&
      other.kind == kind &&
      other.targetSeconds == targetSeconds;

  @override
  int get hashCode => Object.hash(name, date, kind, targetSeconds);
}

/// Persönliche Verbesserungsziele ohne Wettkampf.
final class ImprovementTargets {
  const ImprovementTargets({
    this.runDistanceKilometers,
    this.runPaceSecondsPerKilometer,
    this.restingHeartRate,
    this.targetWeightKilograms,
    this.weeksToTargetWeight,
  });

  /// Strecke, die am Stück gelaufen werden soll (km).
  final double? runDistanceKilometers;

  /// Ziel-Pace über diese Strecke (s/km).
  final int? runPaceSecondsPerKilometer;
  final int? restingHeartRate;
  final double? targetWeightKilograms;

  /// In wie vielen Wochen das Zielgewicht erreicht sein soll.
  final int? weeksToTargetWeight;

  bool get isEmpty =>
      runDistanceKilometers == null &&
      runPaceSecondsPerKilometer == null &&
      restingHeartRate == null &&
      targetWeightKilograms == null;

  ImprovementTargets copyWith({double? targetWeightKilograms, int? weeksToTargetWeight}) => ImprovementTargets(
    runDistanceKilometers: runDistanceKilometers,
    runPaceSecondsPerKilometer: runPaceSecondsPerKilometer,
    restingHeartRate: restingHeartRate,
    targetWeightKilograms: targetWeightKilograms ?? this.targetWeightKilograms,
    weeksToTargetWeight: weeksToTargetWeight ?? this.weeksToTargetWeight,
  );

  Map<String, Object?> toJson() => {
    'runDistanceKilometers': ?runDistanceKilometers,
    'runPaceSecondsPerKilometer': ?runPaceSecondsPerKilometer,
    'restingHeartRate': ?restingHeartRate,
    'targetWeightKilograms': ?targetWeightKilograms,
    'weeksToTargetWeight': ?weeksToTargetWeight,
  };

  static ImprovementTargets fromJson(Object? json) {
    if (json is! Map) return const ImprovementTargets();
    // Wie Swift: ein Feld mit falschem Typ macht das ganze Objekt ungültig.
    const keys = [
      'runDistanceKilometers',
      'runPaceSecondsPerKilometer',
      'restingHeartRate',
      'targetWeightKilograms',
      'weeksToTargetWeight',
    ];
    if (keys.any((key) => json[key] != null && json[key] is! num)) return const ImprovementTargets();
    return ImprovementTargets(
      runDistanceKilometers: jsonDouble(json['runDistanceKilometers']),
      runPaceSecondsPerKilometer: jsonInt(json['runPaceSecondsPerKilometer']),
      restingHeartRate: jsonInt(json['restingHeartRate']),
      targetWeightKilograms: jsonDouble(json['targetWeightKilograms']),
      weeksToTargetWeight: jsonInt(json['weeksToTargetWeight']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ImprovementTargets && const MapEquality<String, Object?>().equals(other.toJson(), toJson());

  @override
  int get hashCode => const MapEquality<String, Object?>().hash(toJson());
}

/// Angaben, bei denen die App vorsichtiger ist oder zum Arztbesuch rät.
enum HealthFlag implements RawEnum {
  pregnantOrPostpartum('Schwanger oder nach der Geburt'),
  eatingDisorder('Essstörung (aktuell oder früher)'),
  medicalCondition('Herz-Kreislauf- oder andere ärztlich behandelte Erkrankung'),
  injury('Akute Verletzung oder Beschwerden');

  const HealthFlag(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// `season`: der bisherige Saisonplan (Triathlon Almere). `personal`: Plan aus Profil und Wochenplan.
enum ProfileMode implements RawEnum {
  season,
  personal;

  @override
  String get rawValue => name;
}

/// Alles, was die App über die Person wissen muss, um sich anzupassen (Schlüssel `coach.profile`).
final class UserProfile {
  UserProfile({
    this.mode = ProfileMode.personal,
    this.onboardingDone = false,
    this.sports = const [TrainingSport.run, TrainingSport.strength],
    this.goal = FitnessGoal.improveFitness,
    this.event,
    this.targets = const ImprovementTargets(),
    Map<String, ExperienceLevel>? levels,
    WeekSchedule? schedule,
    this.health = const [],
    this.currentRunKilometersPerWeek,
    this.goals,
    this.goalHistory = const [],
    this.tracker = const TrackerSetup(),
  }) : levels = levels ?? {},
       schedule = schedule ?? WeekSchedule();

  ProfileMode mode;
  bool onboardingDone;
  List<TrainingSport> sports;
  FitnessGoal goal;

  /// `null` = kein Wettkampf, sondern allgemeine Verbesserung.
  EventGoal? event;
  ImprovementTargets targets;

  /// Erfahrung je Sportart (Schlüssel: `TrainingSport.rawValue`).
  Map<String, ExperienceLevel> levels;
  WeekSchedule schedule;
  List<HealthFlag> health;

  /// Selbstauskunft, wie viel aktuell gelaufen wird; ohne Angabe zählt Garmin.
  double? currentRunKilometersPerWeek;

  /// Haupt- und Nebenziele, Prioritäten (`null` = noch nicht festgelegt, dann aus [goal] abgeleitet).
  PersonalGoals? goals;

  /// Frühere Ziele mit Gültigkeitsbeginn ([goalsOn]).
  List<PersonalGoals> goalHistory;

  /// Fitness-Tracker laut Onboarding.
  TrackerSetup tracker;

  ExperienceLevel level(TrainingSport sport) => levels[sport.rawValue] ?? ExperienceLevel.beginner;

  void setLevel(ExperienceLevel level, TrainingSport sport) => levels[sport.rawValue] = level;

  bool trains(TrainingSport sport) => sports.contains(sport);

  /// Höchste Erfahrung unter den gewählten Ausdauersportarten (Beginner, wenn keine gewählt).
  ExperienceLevel get enduranceLevel =>
      maxBy(sports.where((sport) => sport.isEndurance).map(level), (ExperienceLevel level) => level.index) ??
      ExperienceLevel.beginner;

  /// Der bisherige Saisonplan als Profil (Triathlon Almere, alle vier Disziplinen).
  static UserProfile get seasonPlan => UserProfile(
    mode: ProfileMode.season,
    onboardingDone: true,
    sports: const [TrainingSport.swim, TrainingSport.bike, TrainingSport.run, TrainingSport.strength],
    goal: FitnessGoal.improveFitness,
    levels: {
      TrainingSport.swim.rawValue: ExperienceLevel.intermediate,
      TrainingSport.bike.rawValue: ExperienceLevel.intermediate,
      TrainingSport.run.rawValue: ExperienceLevel.advanced,
      TrainingSport.strength.rawValue: ExperienceLevel.advanced,
    },
  );

  /// Entwurf für den Wechsel vom Saisonplan zu einem persönlichen Profil: Sportarten und Hauptrennen bleiben.
  static UserProfile personalDraft(SeasonConfig config) => seasonPlan
    ..mode = ProfileMode.personal
    ..onboardingDone = false
    ..event = EventGoal(name: config.mainRaceName, date: config.mainRaceDate, kind: EventKind.triathlon);

  // Ziele aus der Personalisierung (in Swift eine Extension in Personalization.swift).

  /// Aktuelle Ziele; ältere Profile ohne Angabe bekommen abgeleitete Ziele.
  PersonalGoals effectiveGoals(CalendarDay today) => goals ?? Personalization.derived(this, since: today);

  /// Ziele, die an einem Tag galten (für Auswertungen früherer Zeiträume).
  PersonalGoals goalsOn(CalendarDay day) {
    final history = [...goalHistory, ?goals]..sort((a, b) => a.since.compareTo(b.since));
    return history.lastWhereOrNull((entry) => entry.since <= day) ??
        history.firstOrNull ??
        Personalization.derived(this, since: day);
  }

  /// Neue Ziele ab [day]: Der bisherige Stand wandert in den Verlauf (gleicher Tag wird ersetzt).
  void updateGoals(PersonalGoals newGoals, {required CalendarDay on}) {
    final updated = newGoals.copyWith(since: on);
    // Ohne gespeicherte Ziele galt bisher das Abgeleitete – seit jeher (sonst sähen alte Zeiträume die neuen Ziele).
    final current = goals ?? Personalization.derived(this, since: const CalendarDay(2000, 1, 1));
    if (current != updated) {
      goalHistory = [...goalHistory.where((entry) => entry.since < on), if (current.since < on) current];
    }
    goals = updated;
    goal = Personalization.fitnessGoal(updated);
  }

  UserProfile copy() => UserProfile.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'mode': mode.rawValue,
    'onboardingDone': onboardingDone,
    'sports': [for (final sport in sports) sport.rawValue],
    'goal': goal.rawValue,
    'event': ?event?.toJson(),
    'targets': targets.toJson(),
    'levels': {for (final entry in levels.entries) entry.key: entry.value.rawValue},
    'schedule': schedule.toJson(),
    'health': [for (final flag in health) flag.rawValue],
    'currentRunKilometersPerWeek': ?currentRunKilometersPerWeek,
    'goals': ?goals?.toJson(),
    'goalHistory': [for (final entry in goalHistory) entry.toJson()],
    'tracker': tracker.toJson(),
  };

  /// Tolerantes Dekodieren wie in Swift: Jedes Feld fällt für sich auf den Standard zurück, wenn es fehlt oder nicht
  /// lesbar ist. Innerhalb eines Felds gilt das strenge Swift-Verhalten (ein unbekannter Wert verwirft die Liste).
  static UserProfile fromJson(Object? json) {
    if (json is! Map) return UserProfile();
    return UserProfile(
      mode: enumFromRaw(ProfileMode.values, json['mode']) ?? ProfileMode.personal,
      onboardingDone: json['onboardingDone'] == true,
      sports: enumListStrict(TrainingSport.values, json['sports']) ?? const [TrainingSport.run, TrainingSport.strength],
      goal: enumFromRaw(FitnessGoal.values, json['goal']) ?? FitnessGoal.improveFitness,
      event: EventGoal.fromJson(json['event']),
      targets: ImprovementTargets.fromJson(json['targets']),
      levels: _levels(json['levels']) ?? {},
      schedule: WeekSchedule.fromJson(json['schedule']),
      health: enumListStrict(HealthFlag.values, json['health']) ?? const [],
      currentRunKilometersPerWeek: jsonDouble(json['currentRunKilometersPerWeek']),
      goals: PersonalGoals.fromJson(json['goals']),
      goalHistory: listStrict(json['goalHistory'], PersonalGoals.fromJson) ?? const [],
      tracker: TrackerSetup.fromJson(json['tracker']),
    );
  }

  static Map<String, ExperienceLevel>? _levels(Object? raw) {
    if (raw is! Map) return null;
    final result = <String, ExperienceLevel>{};
    for (final entry in raw.entries) {
      final level = enumFromRaw(ExperienceLevel.values, entry.value);
      if (level == null) return null;
      result[entry.key as String] = level;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile && const DeepCollectionEquality().equals(other.toJson(), toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());
}

/// Startzustand beim ersten Start nach einem Update.
abstract final class ProfileMigration {
  /// Wer die App schon mit Garmin-Daten oder Saison nutzt, behält den Saisonplan; alle anderen starten mit dem
  /// Einrichtungsassistenten.
  static UserProfile initialProfile({required bool hasExistingData}) =>
      hasExistingData ? UserProfile.seasonPlan : UserProfile();
}

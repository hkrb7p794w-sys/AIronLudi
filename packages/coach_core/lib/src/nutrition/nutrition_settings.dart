import '../calendar/calendar_day.dart';
import '../garmin/garmin_profile.dart';
import '../util/enum_codec.dart';

/// Tagestyp für die Ernährungsziele.
enum DayType implements RawEnum {
  restDay('ruhetag', 'Ruhetag'),
  light('leicht', 'Leichter Tag'),
  moderate('moderat', 'Moderater Trainingstag'),
  hard('hart', 'Harter Trainingstag'),
  veryHard('sehr_hart', 'Sehr harter Trainingstag');

  const DayType(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;

  static DayType? fromRaw(Object? raw) => enumFromRaw(values, raw);

  /// Kohlenhydrate g/kg (Thomas, Erdman & Burke 2016, ACSM/AND/DC).
  double get carbsPerKilogram => switch (this) {
    restDay => 3,
    light => 4,
    moderate => 6,
    hard => 8,
    veryHard => 10,
  };

  /// Untergrenze der Spanne aus Thomas et al. 2016 (leicht 3–5, moderat 5–7, hoch 6–10, sehr hoch 8–12 g/kg).
  /// Reicht die Energie nicht für den Zielwert, sinken die Kohlenhydrate höchstens bis hierhin.
  double get minimumCarbsPerKilogram => switch (this) {
    restDay || light => 3,
    moderate => 5,
    hard => 6,
    veryHard => 8,
  };

  /// Angenommene Dauer einer geplanten Einheit (Minuten), solange Garmin noch nichts aufgezeichnet hat.
  double get plannedMinutes => switch (this) {
    restDay => 0,
    light => 45,
    moderate => 60,
    hard => 90,
    veryHard => 180,
  };

  /// MET der geplanten Einheit (Compendium of Physical Activities, Ainsworth et al. 2011): Kraft etwa 5, Ausdauer
  /// etwa 7 (zwischen moderatem Radfahren und lockerem Laufen).
  double get plannedMET => this == light ? 5 : 7;

  /// Anteil des Energie-Defizits/-Überschusses, der angewendet wird („fuel for the work“).
  double get goalScale => switch (this) {
    restDay || light => 1,
    moderate => 0.5,
    hard || veryHard => 0,
  };

  bool operator <(DayType other) => index < other.index;
  bool operator >(DayType other) => index > other.index;
}

enum NutritionGoal implements RawEnum {
  maintain('halten', 'Gewicht halten'),
  lose('abnehmen', 'Abnehmen'),
  gain('aufbauen', 'Aufbauen'),
  recomposition('umformen', 'Umformen (Fett ab, Muskeln auf)');

  const NutritionGoal(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;

  static NutritionGoal? fromRaw(Object? raw) => enumFromRaw(values, raw);

  double get adjustPercent => switch (this) {
    maintain => 0,
    lose => -15,
    gain => 10,
    recomposition => -5,
  };

  /// Protein g/kg: Ausdauer ~1,8 (Williamson 2023), Aufbau bis 2,0 (Morton 2018), Defizit 2,2 (ISSN).
  double get proteinPerKilogram => switch (this) {
    maintain => 1.8,
    gain => 2.0,
    lose => 2.2,
    recomposition => 2.0,
  };
}

enum Diet implements RawEnum {
  omnivore('alles', 'Alles'),
  pescetarian('pescetarisch', 'Pescetarisch'),
  vegetarian('vegetarisch', 'Vegetarisch'),
  vegan('vegan', 'Vegan');

  const Diet(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;

  static Diet? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

final class BodyProfile {
  const BodyProfile({
    required this.weightKilograms,
    required this.heightCentimeters,
    required this.age,
    required this.isFemale,
  });

  final double weightKilograms;
  final double heightCentimeters;
  final int age;
  final bool isFemale;

  static const fallback = BodyProfile(weightKilograms: 75, heightCentimeters: 180, age: 35, isFemale: false);

  Map<String, Object?> toJson() => {
    'weightKilograms': weightKilograms,
    'heightCentimeters': heightCentimeters,
    'age': age,
    'isFemale': isFemale,
  };

  @override
  bool operator ==(Object other) =>
      other is BodyProfile &&
      other.weightKilograms == weightKilograms &&
      other.heightCentimeters == heightCentimeters &&
      other.age == age &&
      other.isFemale == isFemale;

  @override
  int get hashCode => Object.hash(weightKilograms, heightCentimeters, age, isFemale);
}

/// Einstellungen der Ernährung (Schlüssel `coach.nutrition`). Körperwerte sind optional: ohne Eintrag gelten die
/// Garmin-Werte.
final class NutritionSettings {
  NutritionSettings();

  NutritionGoal goal = NutritionGoal.maintain;
  Diet diet = Diet.pescetarian;

  /// Aktivitätsfaktor ohne Sport (PAL).
  double activityFactor = 1.4;
  double? bodyFatPercent;
  double? weightKilograms;
  double? heightCentimeters;
  int? age;
  bool? isFemale;

  /// Gewünschte Gewichtsänderung in % des Körpergewichts pro Woche (negativ = abnehmen). Kommt aus dem Profil und hat
  /// Vorrang vor dem festen Prozentsatz des Ziels.
  double? weeklyWeightChangePercent;

  /// Vom Nutzer übernommene Anpassung aus dem Gewichtsverlauf (kcal pro Tag, ±500).
  double energyAdjustmentKilocalories = 0;

  /// Schwangerschaft/Stillzeit oder Essstörung: keine Gewichts- oder Kalorienziele (`GoalRules`).
  bool weightTargetsWithheld = false;

  /// Tag der zuletzt als Körpergewicht übernommenen Wägung.
  CalendarDay? lastAppliedWeighInDay;

  /// Letzter Wochen-Check-in (Gewichtsverlauf angesehen bzw. übersprungen), siehe `NutritionCheckIn`.
  CalendarDay? lastCheckInDay;

  /// Einstellungen haben Vorrang, dann Garmin-Profil, dann Standardwerte.
  BodyProfile profile(GarminProfile? garmin, {required CalendarDay on}) {
    const fallback = BodyProfile.fallback;
    return BodyProfile(
      weightKilograms: weightKilograms ?? garmin?.weightKilograms ?? fallback.weightKilograms,
      heightCentimeters: heightCentimeters ?? garmin?.heightCentimeters ?? fallback.heightCentimeters,
      age: age ?? garmin?.ageOn(on) ?? fallback.age,
      isFemale: isFemale ?? (garmin == null ? null : garmin.gender == 'FEMALE') ?? fallback.isFemale,
    );
  }

  NutritionSettings copy() => NutritionSettings.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'goal': goal.rawValue,
    'diet': diet.rawValue,
    'activityFactor': activityFactor,
    'bodyFatPercent': ?bodyFatPercent,
    'weightKilograms': ?weightKilograms,
    'heightCentimeters': ?heightCentimeters,
    'age': ?age,
    'isFemale': ?isFemale,
    'weeklyWeightChangePercent': ?weeklyWeightChangePercent,
    'energyAdjustmentKilocalories': energyAdjustmentKilocalories,
    'weightTargetsWithheld': weightTargetsWithheld,
    'lastAppliedWeighInDay': ?lastAppliedWeighInDay?.toJson(),
    'lastCheckInDay': ?lastCheckInDay?.toJson(),
  };

  /// Tolerant wie in Swift: fehlende oder ungültige Felder bekommen den Standard.
  static NutritionSettings fromJson(Object? json) {
    final settings = NutritionSettings();
    if (json is! Map) return settings;
    settings
      ..goal = NutritionGoal.fromRaw(json['goal']) ?? NutritionGoal.maintain
      ..diet = Diet.fromRaw(json['diet']) ?? Diet.pescetarian
      ..activityFactor = jsonDouble(json['activityFactor']) ?? 1.4
      ..bodyFatPercent = jsonDouble(json['bodyFatPercent'])
      ..weightKilograms = jsonDouble(json['weightKilograms'])
      ..heightCentimeters = jsonDouble(json['heightCentimeters'])
      ..age = jsonInt(json['age'])
      ..isFemale = json['isFemale'] is bool ? json['isFemale'] as bool : null
      ..weeklyWeightChangePercent = jsonDouble(json['weeklyWeightChangePercent'])
      ..energyAdjustmentKilocalories = (jsonDouble(json['energyAdjustmentKilocalories']) ?? 0).clamp(-500, 500)
      ..weightTargetsWithheld = json['weightTargetsWithheld'] == true
      ..lastAppliedWeighInDay = _day(json['lastAppliedWeighInDay'])
      ..lastCheckInDay = _day(json['lastCheckInDay']);
    return settings;
  }

  static CalendarDay? _day(Object? json) {
    if (json is! Map) return null;
    final year = jsonInt(json['year']);
    final month = jsonInt(json['month']);
    final day = jsonInt(json['day']);
    return year == null || month == null || day == null ? null : CalendarDay(year, month, day);
  }

  @override
  bool operator ==(Object other) => other is NutritionSettings && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

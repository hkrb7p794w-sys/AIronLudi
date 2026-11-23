// Fuel Planner (neu in AIronLudi): Eingaben eines Verpflegungsplans – Sportart, Dauer, Intensität, Bedingungen und
// das persönliche Profil (Verträglichkeit, Schweiß). Grundlage: docs/FUEL_PLANNER_SCIENCE.md, Abschnitt 1.
import '../calendar/calendar_day.dart';
import '../endurance/endurance_plan.dart';
import '../profile/session_match.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';

/// Sportart aus Sicht der Verpflegung (Magen-Darm-Belastung, Schweiß, Gelegenheit zum Essen).
enum FuelSport implements RawEnum {
  run('Laufen', 'figure.run', 90, 1.0),
  bike('Rad', 'figure.outdoor.cycle', 120, 0.9),
  swim('Schwimmen', 'figure.pool.swim', 60, 0.4),
  triathlon('Triathlon', 'figure.mixed.cardio', 100, 0.95),
  strength('Kraft', 'dumbbell.fill', 60, 0.6),
  hybrid('Hybrid', 'figure.strengthtraining.functional', 90, 1.0);

  const FuelSport(this.label, this.symbol, this.maxCarbsPerHour, this.sweatFactor);

  final String label;
  final String symbol;

  /// Obergrenze der Disziplin in g/h (Spezifikation 2.2).
  final int maxCarbsPerHour;

  /// Faktor auf die geschätzte Schweißrate (Spezifikation 4.1).
  final double sweatFactor;

  /// Kurzer Hinweis unter der Auswahl.
  String get detail => switch (this) {
    run => 'Erschütterung: lieber kleine Portionen, öfter',
    bike => 'Ruhiger Oberkörper, höhere Mengen möglich',
    swim => 'Aufnahme nur am Beckenrand oder Boot',
    triathlon => 'Großteil auf dem Rad aufnehmen',
    strength => 'Meist reichen Mahlzeiten davor und danach',
    hybrid => 'Hyrox, CrossFit, Koppeltraining',
  };

  bool get isEndurance => this != strength;

  @override
  String get rawValue => name;

  static FuelSport of(EnduranceSport sport) => switch (sport) {
    EnduranceSport.run => run,
    EnduranceSport.bike => bike,
    EnduranceSport.swim => swim,
  };

  /// Sportart des Wochenplans; „Anderes“ (Yoga, Wandern) hat keinen Verpflegungsplan.
  static FuelSport? ofTraining(TrainingSport sport) => switch (sport) {
    TrainingSport.run => run,
    TrainingSport.bike => bike,
    TrainingSport.swim => swim,
    TrainingSport.strength => strength,
    TrainingSport.other => null,
  };
}

/// Intensität ohne Wettkampf (der ist ein eigener Schalter, siehe [FuelScenario.isRace]).
enum FuelIntensity implements RawEnum {
  easy('Locker', 'Zone 1–2', 0.6),
  tempo('Tempo', 'Zone 3', 0.9),
  threshold('Schwelle', 'Zone 4–5, Intervalle', 1.1);

  const FuelIntensity(this.label, this.detail, this.sweatLitersPerHour);

  final String label;
  final String detail;

  /// Geschätzte Schweißrate bei 70 kg und 20 °C (Spezifikation 4.1).
  final double sweatLitersPerHour;

  @override
  String get rawValue => name;

  /// Art der Einheit des Ausdauerplans → Intensität (Spezifikation 1).
  static FuelIntensity of(EnduranceWorkoutType type) => switch (type) {
    EnduranceWorkoutType.rest ||
    EnduranceWorkoutType.recovery ||
    EnduranceWorkoutType.endurance ||
    EnduranceWorkoutType.long => easy,
    EnduranceWorkoutType.tempo => tempo,
    EnduranceWorkoutType.threshold || EnduranceWorkoutType.vo2max || EnduranceWorkoutType.race => threshold,
  };

  /// Intensität einer Einheit des Wochenplans (lang zählt als locker, die Dauer macht den Unterschied).
  static FuelIntensity ofSession(SessionIntensity intensity) => switch (intensity) {
    SessionIntensity.easy || SessionIntensity.long => easy,
    SessionIntensity.hard => threshold,
  };
}

/// Wie viel Verpflegung der Magen-Darm-Trakt gewohnt ist (trainierbar, Jeukendrup 2017).
enum GutTolerance implements RawEnum {
  beginner('Einsteiger', 'Selten mit Verpflegung trainiert', 60, 750),
  habituated('Gewohnt', 'Gels oder Iso-Drinks regelmäßig im Training', 90, 900),
  trained('Gut-Trained', 'Hohe Mengen gezielt geübt', 120, 1000);

  const GutTolerance(this.label, this.detail, this.maxCarbsPerHour, this.maxFluidPerHour);

  final String label;
  final String detail;

  /// Obergrenze Kohlenhydrate in g/h (Spezifikation 2.2).
  final int maxCarbsPerHour;

  /// Obergrenze Flüssigkeit in ml/h (Spezifikation 4.2).
  final int maxFluidPerHour;

  @override
  String get rawValue => name;
}

enum FuelHumidity implements RawEnum {
  dry('Trocken'),
  normal('Normal'),
  humid('Schwül');

  const FuelHumidity(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Natrium im Schweiß (Barnes 2019: Ausdauer im Mittel ≈ 930 mg/l).
enum SweatSaltiness implements RawEnum {
  low('Niedrig', 500),
  medium('Mittel', 900),
  high('Hoch (weiße Ränder auf der Kleidung)', 1300);

  const SweatSaltiness(this.label, this.sodiumPerLiter);

  final String label;

  /// mg Natrium je Liter Schweiß.
  final int sodiumPerLiter;

  @override
  String get rawValue => name;
}

/// Erlaubte Takte des Zeitstrahls in Minuten.
const fuelIntervals = [15, 20, 30];

/// Persönliches Profil: gilt für jeden neuen Plan, je Plan änderbar.
final class FuelProfile {
  const FuelProfile({
    this.gut = GutTolerance.habituated,
    this.sweatRateLitersPerHour,
    this.saltiness = SweatSaltiness.medium,
    this.sodiumPerLiter,
    this.caffeineMgPerKg = 3,
    this.intervalMinutes = 20,
    this.setup = const [],
    this.useStockFirst = true,
    this.home = const [],
    this.onlyHome = false,
  });

  final GutTolerance gut;

  /// Gemessene Schweißrate; `null` = schätzen.
  final double? sweatRateLitersPerHour;
  final SweatSaltiness saltiness;

  /// Gemessenes Natrium im Schweiß (mg/l); `null` = aus [saltiness].
  final double? sodiumPerLiter;

  /// Koffeindosis, wenn eingeschaltet (1–6 mg/kg).
  final double caffeineMgPerKg;
  final int intervalMinutes;

  /// Produkte, die standardmäßig unterwegs genutzt werden (IDs).
  final List<String> setup;

  /// Vorrätige Produkte automatisch einplanen und zuerst aufbrauchen.
  final bool useStockFirst;

  /// Lebensmittel, die zu Hause meist da sind (IDs aus `FuelFoods`).
  final List<String> home;

  /// Vorschläge nur aus [home] (im Zweifel deckt der Plan den Bedarf dann nur annähernd).
  final bool onlyHome;

  /// Einschränkung für Vorschläge; `null` = alle Lebensmittel.
  Set<String>? get homeFilter => onlyHome ? home.toSet() : null;

  FuelProfile copyWith({
    GutTolerance? gut,
    double? Function()? sweatRateLitersPerHour,
    SweatSaltiness? saltiness,
    double? Function()? sodiumPerLiter,
    double? caffeineMgPerKg,
    int? intervalMinutes,
    List<String>? setup,
    bool? useStockFirst,
    List<String>? home,
    bool? onlyHome,
  }) => FuelProfile(
    gut: gut ?? this.gut,
    sweatRateLitersPerHour: sweatRateLitersPerHour == null ? this.sweatRateLitersPerHour : sweatRateLitersPerHour(),
    saltiness: saltiness ?? this.saltiness,
    sodiumPerLiter: sodiumPerLiter == null ? this.sodiumPerLiter : sodiumPerLiter(),
    caffeineMgPerKg: caffeineMgPerKg ?? this.caffeineMgPerKg,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    setup: setup ?? this.setup,
    useStockFirst: useStockFirst ?? this.useStockFirst,
    home: home ?? this.home,
    onlyHome: onlyHome ?? this.onlyHome,
  );

  /// Schweißrate aus Wiegen: (vorher − nachher) kg + getrunken l − Urin l, geteilt durch die Stunden.
  static double? measuredSweatRate({
    required double weightBefore,
    required double weightAfter,
    required double drankLiters,
    double urineLiters = 0,
    required int minutes,
  }) {
    if (minutes <= 0) return null;
    final loss = weightBefore - weightAfter + drankLiters - urineLiters;
    if (loss <= 0) return null;
    return (loss / (minutes / 60) * 100).roundToDouble() / 100;
  }

  Map<String, Object?> toJson() => {
    'gut': gut.rawValue,
    'sweatRate': ?sweatRateLitersPerHour,
    'saltiness': saltiness.rawValue,
    'sodiumPerLiter': ?sodiumPerLiter,
    'caffeineMgPerKg': caffeineMgPerKg,
    'interval': intervalMinutes,
    'setup': setup,
    if (!useStockFirst) 'stockFirst': false,
    if (home.isNotEmpty) 'home': home,
    if (onlyHome) 'onlyHome': true,
  };

  static FuelProfile fromJson(Object? json) {
    if (json is! Map) return const FuelProfile();
    final interval = jsonInt(json['interval']);
    final setup = json['setup'];
    return FuelProfile(
      gut: enumFromRaw(GutTolerance.values, json['gut']) ?? GutTolerance.habituated,
      sweatRateLitersPerHour: _positive(jsonDouble(json['sweatRate'])),
      saltiness: enumFromRaw(SweatSaltiness.values, json['saltiness']) ?? SweatSaltiness.medium,
      sodiumPerLiter: _positive(jsonDouble(json['sodiumPerLiter'])),
      caffeineMgPerKg: (jsonDouble(json['caffeineMgPerKg']) ?? 3).clamp(1, 6).toDouble(),
      intervalMinutes: fuelIntervals.contains(interval) ? interval! : 20,
      setup: [
        if (setup is List)
          for (final id in setup)
            if (id is String) id,
      ],
      useStockFirst: json['stockFirst'] != false,
      home: [
        if (json['home'] case final List<Object?> home)
          for (final id in home)
            if (id is String) id,
      ],
      onlyHome: json['onlyHome'] == true,
    );
  }
}

double? _positive(double? value) => value != null && value > 0 ? value : null;

/// Ein Szenario: eine geplante Einheit oder frei eingestellt.
final class FuelScenario {
  const FuelScenario({
    required this.sport,
    required this.minutes,
    required this.weightKilograms,
    this.title = '',
    this.intensity = FuelIntensity.easy,
    this.isRace = false,
    this.distanceMeters,
    this.temperatureCelsius = 18,
    this.humidity = FuelHumidity.normal,
    this.indoor = false,
    this.gut = GutTolerance.habituated,
    this.sweatRateLitersPerHour,
    this.saltiness = SweatSaltiness.medium,
    this.sodiumPerLiter,
    this.caffeine = false,
    this.caffeineMgPerKg = 3,
    this.fasted = false,
    this.hoursUntilNext,
    this.intervalMinutes = 20,
    this.age,
    this.day,
    this.startMinuteOfDay,
    this.slotID,
    this.swimMinutes,
    this.bikeMinutes,
  });

  /// Aus einer Einheit des Ausdauerplans: Sportart, Dauer, Strecke und Intensität übernommen, der Rest vom Profil.
  factory FuelScenario.fromWorkout(
    EnduranceWorkout workout, {
    required double weightKilograms,
    FuelProfile profile = const FuelProfile(),
    CalendarDay? day,
    String? slotID,
    int? age,
  }) => FuelScenario.withProfile(
    profile,
    sport: FuelSport.of(workout.sport),
    minutes: workout.minutes,
    weightKilograms: weightKilograms,
    title: workout.title,
    intensity: FuelIntensity.of(workout.type),
    isRace: workout.type == EnduranceWorkoutType.race,
    distanceMeters: workout.meters,
    day: day,
    slotID: slotID,
    age: age,
  );

  /// Aus einer Einheit des Wochenplans (auch Krafttraining); `null` für „Anderes“.
  static FuelScenario? fromSession(
    SessionSlot slot, {
    required double weightKilograms,
    int? minutes,
    FuelProfile profile = const FuelProfile(),
    CalendarDay? day,
    String? slotID,
    int? age,
  }) {
    final sport = FuelSport.ofTraining(slot.sport);
    if (sport == null) return null;
    return FuelScenario.withProfile(
      profile,
      sport: sport,
      minutes: minutes ?? SessionMatcher.defaultMinutes(slot),
      weightKilograms: weightKilograms,
      title: slot.title,
      intensity: FuelIntensity.ofSession(slot.intensity),
      day: day,
      slotID: slotID,
      age: age,
    );
  }

  /// Neues Szenario mit den Werten des Profils.
  factory FuelScenario.withProfile(
    FuelProfile profile, {
    required FuelSport sport,
    required int minutes,
    required double weightKilograms,
    String title = '',
    FuelIntensity intensity = FuelIntensity.easy,
    bool isRace = false,
    int? distanceMeters,
    CalendarDay? day,
    String? slotID,
    int? age,
  }) => FuelScenario(
    sport: sport,
    minutes: minutes,
    weightKilograms: weightKilograms,
    title: title,
    intensity: intensity,
    isRace: isRace,
    distanceMeters: distanceMeters,
    gut: profile.gut,
    sweatRateLitersPerHour: profile.sweatRateLitersPerHour,
    saltiness: profile.saltiness,
    sodiumPerLiter: profile.sodiumPerLiter,
    caffeineMgPerKg: profile.caffeineMgPerKg,
    intervalMinutes: profile.intervalMinutes,
    day: day,
    slotID: slotID,
    age: age,
  );

  final FuelSport sport;
  final int minutes;
  final double weightKilograms;
  final String title;
  final FuelIntensity intensity;

  /// Wettkampf: höchste Stufe beim Essen unterwegs, Carboloading, mehr Kohlenhydrate vorher.
  final bool isRace;
  final int? distanceMeters;
  final double temperatureCelsius;
  final FuelHumidity humidity;

  /// Drinnen (Rolle, Laufband, Halle): kein Fahrtwind, mehr Schweiß.
  final bool indoor;
  final GutTolerance gut;
  final double? sweatRateLitersPerHour;
  final SweatSaltiness saltiness;
  final double? sodiumPerLiter;
  final bool caffeine;
  final double caffeineMgPerKg;

  /// Nüchtern (≥ 8 h ohne Essen).
  final bool fasted;

  /// Stunden bis zur nächsten Einheit; `null` = mehr als 24 h.
  final int? hoursUntilNext;
  final int intervalMinutes;
  final int? age;
  final CalendarDay? day;

  /// Startzeit (Minuten nach Mitternacht), für den Koffein-Hinweis und Uhrzeiten im Zeitstrahl.
  final int? startMinuteOfDay;

  /// Zugehörige Einheit des Ausdauer- bzw. Wochenplans.
  final String? slotID;

  /// Triathlon: Minuten im Wasser bzw. auf dem Rad; `null` = übliche Anteile (Spezifikation 2.6).
  final int? swimMinutes;
  final int? bikeMinutes;

  /// Stimmen Sportart, Dauer, Strecke, Intensität, Wettkampf und Tag noch mit der Einheit überein?
  bool matchesWorkout(EnduranceWorkout workout, {CalendarDay? day}) {
    final fresh = FuelScenario.fromWorkout(workout, weightKilograms: weightKilograms, day: day);
    return fresh.sport == sport &&
        fresh.minutes == minutes &&
        fresh.distanceMeters == distanceMeters &&
        fresh.intensity == intensity &&
        fresh.isRace == isRace &&
        (day == null || this.day == day);
  }

  /// Werte der (geänderten) Einheit übernehmen; eigene Einstellungen (Wetter, Magen, Produkte …) bleiben.
  FuelScenario updatedFromWorkout(EnduranceWorkout workout, {CalendarDay? day}) {
    final fresh = FuelScenario.fromWorkout(workout, weightKilograms: weightKilograms, day: day);
    return copyWith(
      sport: fresh.sport,
      minutes: fresh.minutes,
      distanceMeters: () => fresh.distanceMeters,
      intensity: fresh.intensity,
      isRace: fresh.isRace,
      day: () => day ?? this.day,
    );
  }

  double get hours => minutes / 60;

  /// Natrium je Liter Schweiß (gemessen oder aus dem Typ).
  double get sweatSodiumPerLiter => sodiumPerLiter ?? saltiness.sodiumPerLiter.toDouble();

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    return '${sport.label} · $minutes min${isRace ? ' · Wettkampf' : ''}';
  }

  FuelScenario copyWith({
    FuelSport? sport,
    int? minutes,
    double? weightKilograms,
    String? title,
    FuelIntensity? intensity,
    bool? isRace,
    int? Function()? distanceMeters,
    double? temperatureCelsius,
    FuelHumidity? humidity,
    bool? indoor,
    GutTolerance? gut,
    double? Function()? sweatRateLitersPerHour,
    SweatSaltiness? saltiness,
    double? Function()? sodiumPerLiter,
    bool? caffeine,
    double? caffeineMgPerKg,
    bool? fasted,
    int? Function()? hoursUntilNext,
    int? intervalMinutes,
    int? Function()? age,
    CalendarDay? Function()? day,
    int? Function()? startMinuteOfDay,
    String? Function()? slotID,
    int? Function()? swimMinutes,
    int? Function()? bikeMinutes,
  }) => FuelScenario(
    sport: sport ?? this.sport,
    minutes: minutes ?? this.minutes,
    weightKilograms: weightKilograms ?? this.weightKilograms,
    title: title ?? this.title,
    intensity: intensity ?? this.intensity,
    isRace: isRace ?? this.isRace,
    distanceMeters: distanceMeters == null ? this.distanceMeters : distanceMeters(),
    temperatureCelsius: temperatureCelsius ?? this.temperatureCelsius,
    humidity: humidity ?? this.humidity,
    indoor: indoor ?? this.indoor,
    gut: gut ?? this.gut,
    sweatRateLitersPerHour: sweatRateLitersPerHour == null ? this.sweatRateLitersPerHour : sweatRateLitersPerHour(),
    saltiness: saltiness ?? this.saltiness,
    sodiumPerLiter: sodiumPerLiter == null ? this.sodiumPerLiter : sodiumPerLiter(),
    caffeine: caffeine ?? this.caffeine,
    caffeineMgPerKg: caffeineMgPerKg ?? this.caffeineMgPerKg,
    fasted: fasted ?? this.fasted,
    hoursUntilNext: hoursUntilNext == null ? this.hoursUntilNext : hoursUntilNext(),
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    age: age == null ? this.age : age(),
    day: day == null ? this.day : day(),
    startMinuteOfDay: startMinuteOfDay == null ? this.startMinuteOfDay : startMinuteOfDay(),
    slotID: slotID == null ? this.slotID : slotID(),
    swimMinutes: swimMinutes == null ? this.swimMinutes : swimMinutes(),
    bikeMinutes: bikeMinutes == null ? this.bikeMinutes : bikeMinutes(),
  );

  Map<String, Object?> toJson() => {
    'sport': sport.rawValue,
    'minutes': minutes,
    'weight': weightKilograms,
    if (title.isNotEmpty) 'title': title,
    'intensity': intensity.rawValue,
    'race': isRace,
    'distance': ?distanceMeters,
    'temperature': temperatureCelsius,
    'humidity': humidity.rawValue,
    'indoor': indoor,
    'gut': gut.rawValue,
    'sweatRate': ?sweatRateLitersPerHour,
    'saltiness': saltiness.rawValue,
    'sodiumPerLiter': ?sodiumPerLiter,
    'caffeine': caffeine,
    'caffeineMgPerKg': caffeineMgPerKg,
    'fasted': fasted,
    'hoursUntilNext': ?hoursUntilNext,
    'interval': intervalMinutes,
    'age': ?age,
    'day': ?day?.iso,
    'start': ?startMinuteOfDay,
    'slotID': ?slotID,
    'swim': ?swimMinutes,
    'bike': ?bikeMinutes,
  };

  static FuelScenario? fromJson(Object? json) {
    if (json is! Map) return null;
    final sport = enumFromRaw(FuelSport.values, json['sport']);
    final minutes = jsonInt(json['minutes']);
    final weight = jsonDouble(json['weight']);
    if (sport == null || minutes == null || minutes <= 0 || weight == null || weight <= 0) return null;
    final interval = jsonInt(json['interval']);
    final day = json['day'];
    final title = json['title'];
    final slot = json['slotID'];
    return FuelScenario(
      sport: sport,
      minutes: minutes,
      weightKilograms: weight,
      title: title is String ? title : '',
      intensity: enumFromRaw(FuelIntensity.values, json['intensity']) ?? FuelIntensity.easy,
      isRace: json['race'] == true,
      distanceMeters: jsonInt(json['distance']),
      temperatureCelsius: jsonDouble(json['temperature']) ?? 18,
      humidity: enumFromRaw(FuelHumidity.values, json['humidity']) ?? FuelHumidity.normal,
      indoor: json['indoor'] == true,
      gut: enumFromRaw(GutTolerance.values, json['gut']) ?? GutTolerance.habituated,
      sweatRateLitersPerHour: _positive(jsonDouble(json['sweatRate'])),
      saltiness: enumFromRaw(SweatSaltiness.values, json['saltiness']) ?? SweatSaltiness.medium,
      sodiumPerLiter: _positive(jsonDouble(json['sodiumPerLiter'])),
      caffeine: json['caffeine'] == true,
      caffeineMgPerKg: (jsonDouble(json['caffeineMgPerKg']) ?? 3).clamp(1, 6).toDouble(),
      fasted: json['fasted'] == true,
      hoursUntilNext: jsonInt(json['hoursUntilNext']),
      intervalMinutes: fuelIntervals.contains(interval) ? interval! : 20,
      age: jsonInt(json['age']),
      day: day is String ? CalendarDay.tryParse(day) : null,
      startMinuteOfDay: jsonInt(json['start']),
      slotID: slot is String ? slot : null,
      swimMinutes: jsonInt(json['swim']),
      bikeMinutes: jsonInt(json['bike']),
    );
  }
}

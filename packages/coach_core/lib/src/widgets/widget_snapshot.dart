import 'dart:convert';

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import '../health/morning_report.dart';
import '../nutrition/hydration.dart';
import '../nutrition/meal.dart';
import '../nutrition/meal_category.dart';
import '../nutrition/nutrient.dart';
import '../util/enum_codec.dart';
import '../util/swift_date.dart';

// Lesen wie das synthetisierte `Decodable`: Pflichtfelder müssen passen, Optionale dürfen fehlen.
(bool, T?) _opt<T>(Object? value, T? Function(Object?) read) {
  if (value == null) return (true, null);
  final result = read(value);
  return (result != null, result);
}

double? _num(Object? value) => value is num ? value.toDouble() : null;
String? _str(Object? value) => value is String ? value : null;
bool? _bool(Object? value) => value is bool ? value : null;
int? _int(Object? value) => value is int ? value : null;
CalendarDay? _day(Object? value) {
  if (value is! Map) return null;
  try {
    return CalendarDay.fromJson(value.cast<String, Object?>());
  } on Object {
    return null;
  }
}

double? _fraction(double value, double? target) {
  if (target == null || target <= 0) return null;
  return (value / target).clamp(0.0, 1.0);
}

/// Tage in Folge mit Training oder Mahlzeit, für die Kopfzeile der Widgets.
final class WidgetStreak {
  const WidgetStreak({required this.days, required this.activeToday});

  final int days;

  /// Heute ist schon etwas erfasst.
  final bool activeToday;

  /// Kurzer Satz zur Serie. Kein Druck: Ohne Eintrag heute steht nur, was die Serie fortsetzt.
  String get headline {
    if (days <= 0) return 'Heute starten – erster Tag!';
    if (!activeToday) return 'Heute noch etwas erfassen';
    if (isRunning) return 'Serie läuft – weiter so!';
    return 'Guter Start – dranbleiben!';
  }

  /// Erst ab drei Tagen in Folge und mit Eintrag heute ist es eine laufende Serie.
  bool get isRunning => days >= 3 && activeToday;

  Map<String, Object?> toJson() => {'days': days, 'activeToday': activeToday};

  static WidgetStreak? fromJson(Object? json) {
    if (json is! Map) return null;
    final (days, active) = (_int(json['days']), _bool(json['activeToday']));
    return days == null || active == null ? null : WidgetStreak(days: days, activeToday: active);
  }

  @override
  bool operator ==(Object other) => other is WidgetStreak && other.days == days && other.activeToday == activeToday;

  @override
  int get hashCode => Object.hash(days, activeToday);

  @override
  String toString() => 'WidgetStreak($days, $activeToday)';
}

final class WidgetSession {
  const WidgetSession({required this.title, required this.target, required this.done, required this.symbol});

  final String title;
  final String target;
  final bool done;

  /// SF-Symbol der Sportart.
  final String symbol;

  Map<String, Object?> toJson() => {'title': title, 'target': target, 'done': done, 'symbol': symbol};

  static WidgetSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final (title, target, done, symbol) = (
      _str(json['title']),
      _str(json['target']),
      _bool(json['done']),
      _str(json['symbol']),
    );
    if (title == null || target == null || done == null || symbol == null) return null;
    return WidgetSession(title: title, target: target, done: done, symbol: symbol);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetSession &&
      other.title == title &&
      other.target == target &&
      other.done == done &&
      other.symbol == symbol;

  @override
  int get hashCode => Object.hash(title, target, done, symbol);
}

final class WidgetToday {
  const WidgetToday({
    required this.level,
    required this.headline,
    this.sessions = const [],
    this.week,
    this.weekFraction,
  });

  /// Tagesampel; `null` ohne Erholungswerte.
  final RecoveryLevel? level;
  final String headline;
  final List<WidgetSession> sessions;

  /// „3/5 Einheiten · 140/210 min“
  final String? week;
  final double? weekFraction;

  /// Erste noch offene Einheit des Tages.
  WidgetSession? get nextSession => sessions.firstWhereOrNull((session) => !session.done);

  Map<String, Object?> toJson() => {
    'level': ?level?.rawValue,
    'headline': headline,
    'sessions': [for (final session in sessions) session.toJson()],
    'week': ?week,
    'weekFraction': ?weekFraction,
  };

  static WidgetToday? fromJson(Object? json) {
    if (json is! Map) return null;
    final (levelOk, level) = _opt(json['level'], (value) => enumFromRaw(RecoveryLevel.values, value));
    final headline = _str(json['headline']);
    final sessions = listStrict(json['sessions'], WidgetSession.fromJson);
    final (weekOk, week) = _opt(json['week'], _str);
    final (fractionOk, fraction) = _opt(json['weekFraction'], _num);
    if (!levelOk || headline == null || sessions == null || !weekOk || !fractionOk) return null;
    return WidgetToday(level: level, headline: headline, sessions: sessions, week: week, weekFraction: fraction);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetToday &&
      other.level == level &&
      other.headline == headline &&
      const ListEquality<WidgetSession>().equals(other.sessions, sessions) &&
      other.week == week &&
      other.weekFraction == weekFraction;

  @override
  int get hashCode => Object.hash(level, headline, week, weekFraction);
}

/// Eine Mahlzeit im Mahlzeiten-Widget: gegessen und Richtwert (Anteil am Tagesziel, `MealSplit`).
final class WidgetMealPart {
  const WidgetMealPart({required this.category, required this.kcal, required this.target});

  final MealCategory category;
  final double kcal;
  final double? target;

  MealCategory get id => category;

  double? get fraction => _fraction(kcal, target);

  Map<String, Object?> toJson() => {'category': category.rawValue, 'kcal': kcal, 'target': ?target};

  static WidgetMealPart? fromJson(Object? json) {
    if (json is! Map) return null;
    final category = MealCategory.fromRaw(_str(json['category']));
    final kcal = _num(json['kcal']);
    final (targetOk, target) = _opt(json['target'], _num);
    if (category == null || kcal == null || !targetOk) return null;
    return WidgetMealPart(category: category, kcal: kcal, target: target);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetMealPart && other.category == category && other.kcal == kcal && other.target == target;

  @override
  int get hashCode => Object.hash(category, kcal, target);
}

final class WidgetLastMeal {
  const WidgetLastMeal({required this.title, required this.at, required this.kcal});

  final String title;
  final DateTime at;
  final double kcal;

  Map<String, Object?> toJson() => {'title': title, 'at': swiftReferenceDateToJson(at), 'kcal': kcal};

  static WidgetLastMeal? fromJson(Object? json) {
    if (json is! Map) return null;
    final (title, at, kcal) = (_str(json['title']), swiftDateFromJson(json['at']), _num(json['kcal']));
    if (title == null || at == null || kcal == null) return null;
    return WidgetLastMeal(title: title, at: at, kcal: kcal);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetLastMeal && other.title == title && other.at.isAtSameMomentAs(at) && other.kcal == kcal;

  @override
  int get hashCode => Object.hash(title, at.microsecondsSinceEpoch, kcal);
}

final class WidgetNutrition {
  WidgetNutrition({
    required this.kcal,
    required this.kcalTarget,
    required this.protein,
    required this.proteinTarget,
    required this.waterMilliliters,
    required this.waterTarget,
    required this.lastMeal,
    this.meals,
  });

  final double kcal;

  /// `null`, wenn kein Ziel berechnet werden konnte (fehlendes Profil).
  final double? kcalTarget;
  final double protein;
  final double? proteinTarget;
  double waterMilliliters;
  final double? waterTarget;
  final WidgetLastMeal? lastMeal;

  /// kcal je Mahlzeit (Frühstück, Mittag, Abend, Snacks); `null` bei Ständen von vor dem Mahlzeiten-Widget.
  final List<WidgetMealPart>? meals;

  /// Übrig (negativ = darüber); `null` ohne Ziel.
  double? get kcalRemaining => kcalTarget == null ? null : kcalTarget! - kcal;

  double? get kcalFraction => _fraction(kcal, kcalTarget);
  double? get proteinFraction => _fraction(protein, proteinTarget);
  double? get waterFraction => _fraction(waterMilliliters, waterTarget);

  WidgetNutrition copy() => WidgetNutrition(
    kcal: kcal,
    kcalTarget: kcalTarget,
    protein: protein,
    proteinTarget: proteinTarget,
    waterMilliliters: waterMilliliters,
    waterTarget: waterTarget,
    lastMeal: lastMeal,
    meals: meals,
  );

  Map<String, Object?> toJson() => {
    'kcal': kcal,
    'kcalTarget': ?kcalTarget,
    'protein': protein,
    'proteinTarget': ?proteinTarget,
    'waterMilliliters': waterMilliliters,
    'waterTarget': ?waterTarget,
    'lastMeal': ?lastMeal?.toJson(),
    'meals': ?meals?.map((meal) => meal.toJson()).toList(),
  };

  static WidgetNutrition? fromJson(Object? json) {
    if (json is! Map) return null;
    final (kcal, protein, water) = (_num(json['kcal']), _num(json['protein']), _num(json['waterMilliliters']));
    final (kcalTargetOk, kcalTarget) = _opt(json['kcalTarget'], _num);
    final (proteinTargetOk, proteinTarget) = _opt(json['proteinTarget'], _num);
    final (waterTargetOk, waterTarget) = _opt(json['waterTarget'], _num);
    final (lastOk, last) = _opt(json['lastMeal'], WidgetLastMeal.fromJson);
    final (mealsOk, meals) = _opt(json['meals'], (value) => listStrict(value, WidgetMealPart.fromJson));
    if (kcal == null ||
        protein == null ||
        water == null ||
        !kcalTargetOk ||
        !proteinTargetOk ||
        !waterTargetOk ||
        !lastOk ||
        !mealsOk) {
      return null;
    }
    return WidgetNutrition(
      kcal: kcal,
      kcalTarget: kcalTarget,
      protein: protein,
      proteinTarget: proteinTarget,
      waterMilliliters: water,
      waterTarget: waterTarget,
      lastMeal: last,
      meals: meals,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetNutrition &&
      other.kcal == kcal &&
      other.kcalTarget == kcalTarget &&
      other.protein == protein &&
      other.proteinTarget == proteinTarget &&
      other.waterMilliliters == waterMilliliters &&
      other.waterTarget == waterTarget &&
      other.lastMeal == lastMeal &&
      const ListEquality<WidgetMealPart>().equals(other.meals, meals);

  @override
  int get hashCode => Object.hash(kcal, kcalTarget, protein, waterMilliliters);
}

final class WidgetLastSession {
  const WidgetLastSession({required this.title, required this.day, required this.sets, required this.volumeKg});

  final String title;
  final CalendarDay day;
  final int sets;
  final double volumeKg;

  Map<String, Object?> toJson() => {'title': title, 'day': day.toJson(), 'sets': sets, 'volumeKg': volumeKg};

  static WidgetLastSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final (title, day, sets, volume) = (
      _str(json['title']),
      _day(json['day']),
      _int(json['sets']),
      _num(json['volumeKg']),
    );
    if (title == null || day == null || sets == null || volume == null) return null;
    return WidgetLastSession(title: title, day: day, sets: sets, volumeKg: volume);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetLastSession &&
      other.title == title &&
      other.day == day &&
      other.sets == sets &&
      other.volumeKg == volumeKg;

  @override
  int get hashCode => Object.hash(title, day, sets, volumeKg);
}

final class WidgetGym {
  WidgetGym({
    required this.next,
    required this.nextDetail,
    required this.running,
    required this.runningTitle,
    required this.last,
    required this.weekDone,
    required this.weekPlanned,
    this.nextIsForDay,
  });

  /// Nächste geplante Einheit (Routine bzw. Einheit laut Plan).
  String? next;
  String? nextDetail;

  /// Eine Einheit läuft (mindestens ein Satz).
  bool running;
  String? runningTitle;
  WidgetLastSession? last;
  int weekDone;

  /// Geplante Krafteinheiten dieser Woche; `null`, wenn der Plan keine Zahl hergibt.
  int? weekPlanned;

  /// `next` gehört zu genau diesem Tag (Plan-Einheit statt Routine) und gilt am Folgetag nicht mehr.
  bool? nextIsForDay;

  /// „2/3 diese Woche“ bzw. „2 diese Woche“.
  String get weekText => weekPlanned == null ? '$weekDone diese Woche' : '$weekDone/$weekPlanned diese Woche';

  WidgetGym copy() => WidgetGym(
    next: next,
    nextDetail: nextDetail,
    running: running,
    runningTitle: runningTitle,
    last: last,
    weekDone: weekDone,
    weekPlanned: weekPlanned,
    nextIsForDay: nextIsForDay,
  );

  Map<String, Object?> toJson() => {
    'next': ?next,
    'nextDetail': ?nextDetail,
    'running': running,
    'runningTitle': ?runningTitle,
    'last': ?last?.toJson(),
    'weekDone': weekDone,
    'weekPlanned': ?weekPlanned,
    'nextIsForDay': ?nextIsForDay,
  };

  static WidgetGym? fromJson(Object? json) {
    if (json is! Map) return null;
    final (nextOk, next) = _opt(json['next'], _str);
    final (detailOk, detail) = _opt(json['nextDetail'], _str);
    final running = _bool(json['running']);
    final (titleOk, title) = _opt(json['runningTitle'], _str);
    final (lastOk, last) = _opt(json['last'], WidgetLastSession.fromJson);
    final weekDone = _int(json['weekDone']);
    final (plannedOk, planned) = _opt(json['weekPlanned'], _int);
    final (forDayOk, forDay) = _opt(json['nextIsForDay'], _bool);
    if (!nextOk || !detailOk || running == null || !titleOk || !lastOk || weekDone == null || !plannedOk || !forDayOk) {
      return null;
    }
    return WidgetGym(
      next: next,
      nextDetail: detail,
      running: running,
      runningTitle: title,
      last: last,
      weekDone: weekDone,
      weekPlanned: planned,
      nextIsForDay: forDay,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetGym &&
      other.next == next &&
      other.nextDetail == nextDetail &&
      other.running == running &&
      other.runningTitle == runningTitle &&
      other.last == last &&
      other.weekDone == weekDone &&
      other.weekPlanned == weekPlanned &&
      other.nextIsForDay == nextIsForDay;

  @override
  int get hashCode => Object.hash(next, nextDetail, running, runningTitle, last, weekDone, weekPlanned, nextIsForDay);
}

/// Gesundheitswerte, die ein Widget zeigen kann – die Kernwerte des Morning Reports.
enum HealthMetric implements RawEnum {
  bodyBattery('Body Battery', 'battery.75percent', MorningMetric.bodyBattery),
  sleep('Schlaf', 'bed.double.fill', MorningMetric.sleepDuration),
  hrv('HRV', 'waveform.path.ecg', MorningMetric.hrv),
  recovery('Recovery', 'arrow.clockwise.heart', MorningMetric.recovery),
  restingHeartRate('Ruhepuls', 'heart.fill', MorningMetric.restingHeartRate),
  stress('Stress', 'brain.head.profile', MorningMetric.stress);

  const HealthMetric(this.title, this.symbol, this.reportMetric);

  final String title;
  final String symbol;

  /// Entsprechender Wert im Morning Report.
  final MorningMetric reportMetric;

  @override
  String get rawValue => name;
}

final class WidgetHealth {
  const WidgetHealth({
    required this.metric,
    required this.value,
    required this.gauge,
    required this.status,
    required this.note,
  });

  final HealthMetric metric;

  /// Formatiert („7,4 h“, „62 ms“); `null` = kein Wert.
  final String? value;

  /// Zahl für Ringe (Body Battery 0–100); sonst `null`.
  final double? gauge;
  final MorningStatus status;
  final String note;

  Map<String, Object?> toJson() => {
    'metric': metric.rawValue,
    'value': ?value,
    'gauge': ?gauge,
    'status': status.rawValue,
    'note': note,
  };

  static WidgetHealth? fromJson(Object? json) {
    if (json is! Map) return null;
    final metric = enumFromRaw(HealthMetric.values, json['metric']);
    final (valueOk, value) = _opt(json['value'], _str);
    final (gaugeOk, gauge) = _opt(json['gauge'], _num);
    final status = enumFromRaw(MorningStatus.values, json['status']);
    final note = _str(json['note']);
    if (metric == null || !valueOk || !gaugeOk || status == null || note == null) return null;
    return WidgetHealth(metric: metric, value: value, gauge: gauge, status: status, note: note);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetHealth &&
      other.metric == metric &&
      other.value == value &&
      other.gauge == gauge &&
      other.status == status &&
      other.note == note;

  @override
  int get hashCode => Object.hash(metric, value, gauge, status, note);
}

/// Stand für die Anzeige.
final class WidgetDisplay {
  const WidgetDisplay({required this.snapshot, required this.isCurrent, required this.healthIsOld});

  final WidgetSnapshot snapshot;

  /// Stand ist von heute.
  final bool isCurrent;

  /// Gesundheitswerte stammen nicht von der letzten Nacht: Der Stand ist von einem früheren Tag.
  final bool healthIsOld;
}

/// Was die Homescreen-Widgets zeigen. Die App schreibt den Stand in die App Group (nach Abruf, beim Verlassen,
/// im Hintergrund), die Widgets lesen nur diese Datei – kein Zugriff auf die Datenbank der App. Werte sind schon
/// formatiert bzw. fertig berechnet; die Widgets rechnen nur Tageswechsel und wartende Wasser-Einträge ein.
/// Das JSON muss zu den nativen Widgets der Swift-Erweiterung passen: Zeitpunkte wie beim Standard-`JSONEncoder` als
/// Sekunden seit dem 1.1.2001 (`WidgetStore` in Swift nutzt keine Datumsstrategie).
final class WidgetSnapshot {
  WidgetSnapshot({
    required this.createdAt,
    required this.day,
    required this.today,
    required this.nutrition,
    required this.gym,
    required this.health,
    this.streak,
    this.mealStreak,
    this.version = currentVersion,
  });

  static const fileName = 'widget-snapshot.json';
  static const currentVersion = 1;

  int version;
  DateTime createdAt;

  /// Tag, für den die Werte gelten.
  CalendarDay day;
  WidgetToday today;
  WidgetNutrition? nutrition;

  /// `null` ohne Krafttraining im Profil.
  WidgetGym? gym;

  /// Gesundheitswerte der letzten Nacht in fester Reihenfolge (nur Metriken des Morning Reports).
  List<WidgetHealth> health;

  /// Tages-Serie (`DailyStreak`); fehlt in älteren Ständen.
  WidgetStreak? streak;

  /// Serie der Mahlzeiten: nur Tage mit eingetragener Mahlzeit, lückenlos (ohne Joker, ohne Training von der Uhr).
  /// Für die Mahlzeiten- und Ernährungs-Anzeigen; fehlt in älteren Ständen.
  WidgetStreak? mealStreak;

  WidgetHealth? healthFor(HealthMetric metric) => health.firstWhereOrNull((item) => item.metric == metric);

  WidgetSnapshot copy() => WidgetSnapshot(
    createdAt: createdAt,
    day: day,
    today: today,
    nutrition: nutrition?.copy(),
    gym: gym?.copy(),
    health: [...health],
    streak: streak,
    mealStreak: mealStreak,
    version: version,
  );

  /// Stand für die Anzeige an [day]: Am neuen Tag ist nichts gegessen und nichts geplant bekannt (keine Schätzung –
  /// das Widget bittet ums Öffnen der App); Gesundheitswerte gelten ab dem Folgetag als alt. Wartende
  /// Wasser-Einträge aus dem Widget zählen sofort mit.
  WidgetDisplay display(CalendarDay on, {WidgetActionQueue? queue}) {
    final snapshot = copy();
    final isCurrent = on == day;
    if (!isCurrent) {
      // Am Folgetag läuft die Serie weiter, heute ist aber noch nichts erfasst; älter ist sie unbekannt.
      if (on == day.adding(1)) {
        snapshot
          ..streak = switch (snapshot.streak) {
            final value? => WidgetStreak(days: value.days, activeToday: false),
            null => null,
          }
          ..mealStreak = switch (snapshot.mealStreak) {
            final value? => WidgetStreak(days: value.days, activeToday: false),
            null => null,
          };
      } else {
        snapshot
          ..streak = null
          ..mealStreak = null;
      }
      snapshot.today = const WidgetToday(level: null, headline: 'Neuer Tag – App öffnen');
      if (nutrition != null) {
        snapshot.nutrition = WidgetNutrition(
          kcal: 0,
          kcalTarget: null,
          protein: 0,
          proteinTarget: null,
          waterMilliliters: 0,
          waterTarget: null,
          lastMeal: null,
          meals: [for (final category in MealSplit.order) WidgetMealPart(category: category, kcal: 0, target: null)],
        );
      }
      if (snapshot.gym case final gym?) {
        gym
          ..running = false
          ..runningTitle = null;
        if (gym.nextIsForDay == true) {
          gym
            ..next = 'App öffnen'
            ..nextDetail = null;
        }
        // Neue Woche: Zählung beginnt von vorn.
        if (on.adding(-on.weekdayIndex) != day.adding(-day.weekdayIndex)) gym.weekDone = 0;
      }
    }
    final pendingWater = (queue ?? WidgetActionQueue()).water(on);
    if (pendingWater > 0 && snapshot.nutrition != null) snapshot.nutrition!.waterMilliliters += pendingWater;
    return WidgetDisplay(snapshot: snapshot, isCurrent: isCurrent, healthIsOld: on > day);
  }

  /// Gesundheitswerte aus dem Morning Report; Body Battery zusätzlich als Zahl für den Ring.
  static List<WidgetHealth> healthFrom(MorningReport report, {required double? bodyBattery}) => [
    for (final metric in HealthMetric.values)
      if (report.items.firstWhereOrNull((item) => item.metric == metric.reportMetric) case final item?)
        WidgetHealth(
          metric: metric,
          value: item.value,
          gauge: metric == HealthMetric.bodyBattery && item.status != MorningStatus.missing ? bodyBattery : null,
          status: item.status,
          note: item.note,
        ),
  ];

  /// Ernährung des Tages aus Zielen und Summen; Wasser zählt mit, die letzte Mahlzeit ohne reines Wasser.
  static WidgetNutrition nutritionFrom({
    required NutrientValues? targets,
    required NutrientValues totals,
    required double water,
    required WidgetLastMeal? lastMeal,
    Map<MealCategory, double> mealKilocalories = const {},
  }) => WidgetNutrition(
    kcal: totals[Nutrient.kcal] ?? 0,
    kcalTarget: targets?[Nutrient.kcal],
    protein: totals[Nutrient.protein] ?? 0,
    proteinTarget: targets?[Nutrient.protein],
    waterMilliliters: water,
    waterTarget: targets?[Nutrient.water],
    lastMeal: lastMeal,
    meals: [
      for (final category in MealSplit.order)
        WidgetMealPart(
          category: category,
          kcal: (mealKilocalories[category] ?? 0).roundToDouble(),
          target: MealSplit.target(category, dayKilocalories: targets?[Nutrient.kcal]),
        ),
    ],
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'createdAt': swiftReferenceDateToJson(createdAt),
    'day': day.toJson(),
    'today': today.toJson(),
    'nutrition': ?nutrition?.toJson(),
    'gym': ?gym?.toJson(),
    'health': [for (final item in health) item.toJson()],
    'streak': ?streak?.toJson(),
    'mealStreak': ?mealStreak?.toJson(),
  };

  static WidgetSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = _int(json['version']);
    final createdAt = swiftDateFromJson(json['createdAt']);
    final day = _day(json['day']);
    final today = WidgetToday.fromJson(json['today']);
    final (nutritionOk, nutrition) = _opt(json['nutrition'], WidgetNutrition.fromJson);
    final (gymOk, gym) = _opt(json['gym'], WidgetGym.fromJson);
    final health = listStrict(json['health'], WidgetHealth.fromJson);
    final (streakOk, streak) = _opt(json['streak'], WidgetStreak.fromJson);
    final (mealStreakOk, mealStreak) = _opt(json['mealStreak'], WidgetStreak.fromJson);
    if (version == null ||
        createdAt == null ||
        day == null ||
        today == null ||
        !nutritionOk ||
        !gymOk ||
        health == null ||
        !streakOk ||
        !mealStreakOk) {
      return null;
    }
    return WidgetSnapshot(
      version: version,
      createdAt: createdAt,
      day: day,
      today: today,
      nutrition: nutrition,
      gym: gym,
      health: health,
      streak: streak,
      mealStreak: mealStreak,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.version == version &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      other.day == day &&
      other.today == today &&
      other.nutrition == nutrition &&
      other.gym == gym &&
      const ListEquality<WidgetHealth>().equals(other.health, health) &&
      other.streak == streak &&
      other.mealStreak == mealStreak;

  @override
  int get hashCode => Object.hash(version, day, today, nutrition, gym, streak, mealStreak);
}

/// Ein Wasser-Eintrag aus dem Widget.
final class WidgetActionEntry {
  WidgetActionEntry({String? id, required this.day, required this.at, required this.waterMilliliters})
    : id = id ?? newUuid();

  final String id;
  final CalendarDay day;
  final DateTime at;
  final double waterMilliliters;

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day.toJson(),
    'at': swiftReferenceDateToJson(at),
    'waterMilliliters': waterMilliliters,
  };

  static WidgetActionEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, day, at, water) = (
      _str(json['id']),
      _day(json['day']),
      swiftDateFromJson(json['at']),
      _num(json['waterMilliliters']),
    );
    if (id == null || day == null || at == null || water == null) return null;
    return WidgetActionEntry(id: id, day: day, at: at, waterMilliliters: water);
  }
}

/// Aktionen aus interaktiven Widgets, die die App beim nächsten Öffnen übernimmt (das Widget kann die Datenbank
/// der App nicht schreiben). Heute nur Wasser.
final class WidgetActionQueue {
  WidgetActionQueue({List<WidgetActionEntry>? entries}) : entries = entries ?? [];

  static const fileName = 'widget-actions.json';

  /// Ältere Einträge verfallen (App lange nicht geöffnet) statt Tage später aufzutauchen.
  static const maxAgeDays = 7;

  List<WidgetActionEntry> entries;

  void addWater(double milliliters, {required DateTime at}) {
    if (milliliters <= 0 || !milliliters.isFinite) return;
    entries.add(WidgetActionEntry(day: CalendarDay.fromDate(at.toLocal()), at: at, waterMilliliters: milliliters));
  }

  double water(CalendarDay on) =>
      entries.where((entry) => entry.day == on).fold(0.0, (sum, entry) => sum + entry.waterMilliliters);

  /// Einträge, die die App übernehmen soll (nicht älter als [maxAgeDays]).
  List<WidgetActionEntry> pending(CalendarDay today) {
    final oldest = today.adding(-maxAgeDays);
    return entries.where((entry) => entry.day >= oldest && entry.day <= today).toList();
  }

  /// Nach dem Übernehmen: genau diese Einträge entfernen (später hinzugekommene bleiben).
  void remove(Set<String> ids) => entries.removeWhere((entry) => ids.contains(entry.id));

  Map<String, Object?> toJson() => {
    'entries': [for (final entry in entries) entry.toJson()],
  };

  static WidgetActionQueue? fromJson(Object? json) {
    if (json is! Map) return null;
    final entries = listStrict(json['entries'], WidgetActionEntry.fromJson);
    return entries == null ? null : WidgetActionQueue(entries: entries);
  }
}

final _groupsArray = RegExp(
  r'<key>\s*com\.apple\.security\.application-groups\s*</key>\s*<array>(.*?)</array>',
  dotAll: true,
);
final _string = RegExp(r'<string>(.*?)</string>', dotAll: true);

/// Liest die App Groups aus dem eingebetteten Provisioning-Profil (`embedded.mobileprovision`). SideStore hängt bei
/// kostenlosen Konten die Team-ID an (`group.<id>.<TEAMID>`), die App kennt sie also nicht im Voraus.
abstract final class AppGroupProfile {
  /// Gruppe, die App und Widgets teilen (wie in `project.yml`).
  static const baseIdentifier = 'group.io.github.hkrb7p794w.coach';
  static const entitlementKey = 'com.apple.security.application-groups';

  /// Gruppen aus dem Profil (eine CMS-Signatur um eine XML-Plist). Statt eines Plist-Parsers sucht Dart den Eintrag
  /// im XML-Text; Swift liest die Plist mit `PropertyListSerialization`.
  static List<String> groups(List<int> profile) {
    final text = latin1.decode(profile, allowInvalid: true);
    final start = text.indexOf('<?xml');
    if (start < 0) return [];
    final end = text.indexOf('</plist>', start);
    if (end < 0) return [];
    final plist = utf8.decode(latin1.encode(text.substring(start, end + 8)), allowMalformed: true);
    final entitlements = plist.indexOf('<key>Entitlements</key>');
    if (entitlements < 0) return [];
    final match = _groupsArray.firstMatch(plist.substring(entitlements));
    if (match == null) return [];
    return [for (final item in _string.allMatches(match.group(1)!)) _unescape(item.group(1)!.trim())];
  }

  static String _unescape(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// Kandidaten in der Reihenfolge der Prüfung: passende Gruppen aus dem Profil (kürzeste zuerst), dann die
  /// unveränderte ID (normale Signatur, Simulator).
  static List<String> candidates(List<String> profileGroups, {String base = baseIdentifier}) {
    final matching = profileGroups.where((group) => group == base || group.startsWith('$base.')).toList()
      ..sort((a, b) {
        final byLength = a.length.compareTo(b.length);
        return byLength != 0 ? byLength : a.compareTo(b);
      });
    return [...matching, if (!matching.contains(base)) base];
  }
}

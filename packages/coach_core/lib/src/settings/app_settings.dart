import '../calendar/calendar_day.dart';
import '../motivation/league.dart';
import '../nutrition/meal.dart' show newUuid;
import '../nutrition/meal_reminders.dart';

/// Rangliste: Code (leer = nicht dabei), eigene ID und Anzeigename. Nur Name und Punkte verlassen das iPhone.
final class LeagueSettings {
  LeagueSettings({this.code = '', String? memberID, this.name = ''}) : memberID = memberID ?? newUuid().toLowerCase();

  String code;
  String memberID;
  String name;

  bool get isJoined => LeagueCode.isValid(code);

  Map<String, Object?> toJson() => {'code': code, 'memberID': memberID, 'name': name};

  /// Wie die synthetisierte `Codable`-Umsetzung: alle drei Felder Pflicht, sonst `null`.
  static LeagueSettings? fromJson(Object? json) => switch (json) {
    {'code': final String code, 'memberID': final String memberID, 'name': final String name} => LeagueSettings(
      code: code,
      memberID: memberID,
      name: name,
    ),
    _ => null,
  };

  LeagueSettings copy() => LeagueSettings(code: code, memberID: memberID, name: name);

  @override
  bool operator ==(Object other) =>
      other is LeagueSettings && other.code == code && other.memberID == memberID && other.name == name;

  @override
  int get hashCode => Object.hash(code, memberID, name);
}

/// Erinnerung an geplante Einheiten: an oder aus und Uhrzeit.
final class ReminderSettings {
  ReminderSettings();

  bool enabled = true;
  int hour = 7;
  int minute = 30;

  /// Am Vorabend um 18 Uhr an Schwimm-Ausrüstung erinnern.
  bool equipment = true;

  /// Sonntags „Nächste Woche planen“.
  bool weekPlanning = true;
  int planningHour = 18;
  int planningMinute = 0;

  /// Abends um 20 Uhr „Tag auswerten“ (Ernährung und Training).
  bool nutritionReview = false;

  /// Erinnerungen an Mahlzeiten (je Mahlzeit Uhrzeit und Schalter).
  MealReminderSettings meals = MealReminderSettings();

  /// Morgens um 8 Uhr eine Mitteilung zum Morning Report.
  bool morningReport = true;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'equipment': equipment,
    'weekPlanning': weekPlanning,
    'planningHour': planningHour,
    'planningMinute': planningMinute,
    'nutritionReview': nutritionReview,
    'meals': meals.toJson(),
    'morningReport': morningReport,
  };

  /// Tolerant wie `init(from:)`: fehlende oder falsche Werte fallen auf die Standards, Uhrzeiten werden begrenzt.
  static ReminderSettings fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    bool flag(String key, bool fallback) => map[key] is bool ? map[key]! as bool : fallback;
    int number(String key, int fallback, int max) {
      final value = map[key];
      final raw = value is int ? value : fallback;
      return raw.clamp(0, max);
    }

    return ReminderSettings()
      ..enabled = flag('enabled', true)
      ..hour = number('hour', 7, 23)
      ..minute = number('minute', 30, 59)
      ..equipment = flag('equipment', true)
      ..weekPlanning = flag('weekPlanning', true)
      ..planningHour = number('planningHour', 18, 23)
      ..planningMinute = number('planningMinute', 0, 59)
      ..nutritionReview = flag('nutritionReview', false)
      ..meals = map['meals'] is Map ? MealReminderSettings.fromJson(map['meals']) : MealReminderSettings()
      ..morningReport = flag('morningReport', true);
  }

  ReminderSettings copy() => fromJson(toJson());

  @override
  bool operator ==(Object other) => other is ReminderSettings && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

/// Hinweise einer externen KI mit Datum des Imports.
final class ImportedNotes {
  const ImportedNotes({required this.day, required this.texts});

  final CalendarDay day;
  final List<String> texts;

  Map<String, Object?> toJson() => {'day': day.toJson(), 'texts': texts};

  static ImportedNotes? fromJson(Object? json) {
    if (json case {'day': final Map<Object?, Object?> day, 'texts': final List<Object?> texts}
        when texts.every((text) => text is String)) {
      try {
        return ImportedNotes(day: CalendarDay.fromJson(day.cast<String, Object?>()), texts: texts.cast<String>());
      } on Object {
        return null;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ImportedNotes &&
      other.day == day &&
      other.texts.length == texts.length &&
      Iterable<int>.generate(texts.length).every((index) => other.texts[index] == texts[index]);

  @override
  int get hashCode => Object.hash(day, Object.hashAll(texts));
}

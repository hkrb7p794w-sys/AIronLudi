import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../profile/plan_adjustments.dart';
import 'meal_category.dart';

/// Gewohnte Essenszeit einer Mahlzeit mit eigenem Schalter.
final class MealReminderSlot {
  MealReminderSlot({this.enabled = false, required int hour, required int minute})
    : hour = hour.clamp(0, 23),
      minute = minute.clamp(0, 59);

  final bool enabled;
  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  MealReminderSlot copyWith({bool? enabled, int? hour, int? minute}) =>
      MealReminderSlot(enabled: enabled ?? this.enabled, hour: hour ?? this.hour, minute: minute ?? this.minute);

  Map<String, Object?> toJson() => {'enabled': enabled, 'hour': hour, 'minute': minute};

  /// Wie das synthetisierte `Decodable` (ohne Begrenzen, das geschieht nur beim Anlegen).
  static MealReminderSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final (enabled, hour, minute) = (json['enabled'], json['hour'], json['minute']);
    if (enabled is! bool || hour is! int || minute is! int) return null;
    return MealReminderSlot._raw(enabled, hour, minute);
  }

  const MealReminderSlot._raw(this.enabled, this.hour, this.minute);

  @override
  bool operator ==(Object other) =>
      other is MealReminderSlot && other.enabled == enabled && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);
}

/// Gewohnte Essenszeiten und je Mahlzeit ein eigener Schalter (Standard: aus).
final class MealReminderSettings {
  MealReminderSettings();

  MealReminderSlot breakfast = MealReminderSlot(hour: 8, minute: 0);
  MealReminderSlot lunch = MealReminderSlot(hour: 12, minute: 30);
  MealReminderSlot dinner = MealReminderSlot(hour: 19, minute: 0);
  MealReminderSlot snack = MealReminderSlot(hour: 16, minute: 0);

  static const categories = [MealCategory.breakfast, MealCategory.lunch, MealCategory.snack, MealCategory.dinner];

  MealReminderSlot? operator [](MealCategory category) => switch (category) {
    MealCategory.breakfast => breakfast,
    MealCategory.lunch => lunch,
    MealCategory.dinner => dinner,
    MealCategory.snack => snack,
    MealCategory.other => null,
  };

  void operator []=(MealCategory category, MealReminderSlot? value) {
    if (value == null) return;
    switch (category) {
      case MealCategory.breakfast:
        breakfast = value;
      case MealCategory.lunch:
        lunch = value;
      case MealCategory.dinner:
        dinner = value;
      case MealCategory.snack:
        snack = value;
      case MealCategory.other:
        break;
    }
  }

  bool get anyEnabled => categories.any((category) => this[category]?.enabled == true);

  Map<String, Object?> toJson() => {
    'breakfast': breakfast.toJson(),
    'lunch': lunch.toJson(),
    'dinner': dinner.toJson(),
    'snack': snack.toJson(),
  };

  /// Tolerant: unlesbare Mahlzeiten behalten ihre Standardzeit.
  static MealReminderSettings fromJson(Object? json) {
    final settings = MealReminderSettings();
    if (json is! Map) return settings;
    settings
      ..breakfast = MealReminderSlot.fromJson(json['breakfast']) ?? settings.breakfast
      ..lunch = MealReminderSlot.fromJson(json['lunch']) ?? settings.lunch
      ..dinner = MealReminderSlot.fromJson(json['dinner']) ?? settings.dinner
      ..snack = MealReminderSlot.fromJson(json['snack']) ?? settings.snack;
    return settings;
  }

  @override
  bool operator ==(Object other) =>
      other is MealReminderSettings &&
      other.breakfast == breakfast &&
      other.lunch == lunch &&
      other.dinner == dinner &&
      other.snack == snack;

  @override
  int get hashCode => Object.hash(breakfast, lunch, dinner, snack);
}

/// Erinnerungen an Mahlzeiten (Erweiterung von `ReminderPlanner` in Swift).
abstract final class MealReminderPlanner {
  /// Erinnerungen an Mahlzeiten für heute und die nächsten Tage. Keine Mitteilung, wenn die Mahlzeit an dem Tag schon
  /// erfasst ist oder die Zeit heute vorbei ist. Uhrzeiten gelten in der jeweils aktuellen Zeitzone (die App plant
  /// bei jeder Änderung von Zeiten, Mahlzeiten oder Zeitzone neu).
  static List<ScheduledNote> meals(
    MealReminderSettings settings, {
    required CalendarDay today,
    required int minutesNow,
    required Set<String> logged,
    int days = 2,
  }) => [
    for (var offset = 0; offset < math.max(days, 1); offset++)
      for (final category in MealReminderSettings.categories)
        if (settings[category] case final slot?
            when slot.enabled &&
                !(offset == 0 && minutesNow >= slot.minutes) &&
                !logged.contains(loggedKey(today.adding(offset), category)))
          ScheduledNote(
            kind: ScheduledNoteKind.meal,
            day: today.adding(offset),
            hour: slot.hour,
            minute: slot.minute,
            title: '${category.label} eintragen',
            body: mealBody(category),
            tag: category.rawValue,
          ),
  ];

  /// Schlüssel für „an diesem Tag schon erfasst“.
  static String loggedKey(CalendarDay day, MealCategory category) => '${day.iso}|${category.rawValue}';

  static String mealBody(MealCategory category) => switch (category) {
    MealCategory.breakfast => 'Was gab es zum Frühstück? Ein Tipp auf „Zuletzt“ reicht oft.',
    MealCategory.lunch => 'Mittagessen eintragen – Foto, Text oder aus deinen Favoriten.',
    MealCategory.dinner => 'Abendessen eintragen, dann stimmt die Tagesbilanz.',
    MealCategory.snack || MealCategory.other => 'Snack eintragen?',
  };
}

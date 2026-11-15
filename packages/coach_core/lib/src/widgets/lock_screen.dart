import '../nutrition/meal_category.dart';
import '../nutrition/meal_reminders.dart';
import 'meal_headline.dart';
import 'widget_snapshot.dart';

/// Welche Live-Aktivitäten auf dem Sperrbildschirm stehen. Feste Regel: Während einer laufenden Gym-Einheit hat die
/// Einheit Vorrang – „Mahlzeiten heute“ wird so lange beendet und danach wieder gestartet. Zwei Karten gleichzeitig
/// drängen sich sonst auf dem Sperrbildschirm, und iOS ordnet sie nicht nach Wichtigkeit.
abstract final class LockScreenActivities {
  /// [workoutShown]: Die Live-Aktivität der Einheit läuft (eingeschaltet und mindestens ein Satz gemacht).
  static bool showsMeals({required bool mealsEnabled, required bool workoutShown}) => mealsEnabled && !workoutShown;
}

/// Nächste Mahlzeit für die Live-Aktivität „Mahlzeiten heute“ – die Erinnerung steht auf dem Sperrbildschirm statt als
/// Mitteilung. Feste Regeln, keine KI.
final class MealLiveNext {
  const MealLiveNext({required this.category, required this.at, required this.due});

  final MealCategory category;

  /// Gewohnte Essenszeit heute.
  final DateTime at;

  /// Die Zeit ist erreicht und die Mahlzeit noch nicht eingetragen.
  final bool due;

  /// „Mittagessen · 12:30“ bzw. „Zeit fürs Mittagessen“.
  String get text {
    final name = MealHeadline.name(category);
    if (due) {
      final isSnack = category == MealCategory.snack || category == MealCategory.other;
      return isSnack ? 'Zeit für einen Snack – eintragen?' : 'Zeit fürs $name – jetzt eintragen?';
    }
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return 'Als Nächstes: $name um $hour:$minute';
  }

  @override
  bool operator ==(Object other) =>
      other is MealLiveNext && other.category == category && other.at == at && other.due == due;

  @override
  int get hashCode => Object.hash(category, at, due);
}

abstract final class MealLiveReminder {
  /// So lange nach der gewohnten Zeit gilt eine offene Mahlzeit noch als „fällig“; danach rückt die nächste nach.
  static const graceMinutes = 180;

  /// Nächste offene Mahlzeit des Tages. Es zählen die eingeschalteten Essenszeiten; ist keine eingeschaltet, die
  /// gewohnten Zeiten der Hauptmahlzeiten (Snack nur, wenn eingeschaltet). [meals]: Kalorien je Mahlzeit heute
  /// (`WidgetMealPart`); eingetragen heißt mehr als 0 kcal. `null`, wenn heute nichts mehr ansteht.
  static MealLiveNext? next({
    required MealReminderSettings settings,
    required List<WidgetMealPart> meals,
    required DateTime now,
  }) {
    final enabled = [
      for (final category in MealReminderSettings.categories)
        if (settings[category] case final slot? when slot.enabled) (category, slot),
    ];
    final slots = enabled.isNotEmpty
        ? enabled
        : [
            for (final category in MealReminderSettings.categories)
              if (category != MealCategory.snack) (category, settings[category]!),
          ];
    slots.sort((a, b) => a.$2.minutes.compareTo(b.$2.minutes));
    final logged = {
      for (final meal in meals)
        if (meal.kcal > 0) meal.category,
    };
    final minutesNow = now.hour * 60 + now.minute;
    for (final (category, slot) in slots) {
      if (logged.contains(category)) continue;
      if (minutesNow >= slot.minutes + graceMinutes) continue;
      return MealLiveNext(
        category: category,
        at: DateTime(now.year, now.month, now.day, slot.hour, slot.minute),
        due: minutesNow >= slot.minutes,
      );
    }
    return null;
  }
}

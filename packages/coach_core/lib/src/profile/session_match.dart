import '../garmin/garmin_activity.dart';
import 'user_profile.dart';
import 'week_schedule.dart';

/// Zuordnung von Aktivitäten zu geplanten Einheiten (Port von `SessionMatcher`). Hier zunächst die Werte, die
/// Wochenplan und Ernährung brauchen; die Zuordnung selbst folgt mit dem Plan-Modul.
abstract final class SessionMatcher {
  /// Ab diesem Anteil der geplanten Dauer gilt die Einheit als erledigt, darunter als „teilweise“.
  static const doneShare = 0.6;

  /// Kürzere Aktivitäten (Weg zur Arbeit, Einrollen) zählen für keine Einheit.
  static const minimumSeconds = 900.0;

  /// Dauer, wenn der Plan keine nennt (der Laufplan liefert eigene Minuten).
  static int defaultMinutes(SessionSlot slot) => switch ((slot.sport, slot.intensity)) {
    (TrainingSport.strength, _) => 45,
    (TrainingSport.other, _) => 30,
    (_, SessionIntensity.easy) => 45,
    (_, SessionIntensity.hard) => 50,
    (_, SessionIntensity.long) => 90,
  };

  static TrainingSport sport(ActivitySport sport) => switch (sport) {
    ActivitySport.run => TrainingSport.run,
    ActivitySport.bike => TrainingSport.bike,
    ActivitySport.swim => TrainingSport.swim,
    ActivitySport.strength => TrainingSport.strength,
    ActivitySport.other => TrainingSport.other,
  };
}

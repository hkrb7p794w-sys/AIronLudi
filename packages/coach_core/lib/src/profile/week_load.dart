import '../analysis/session_kind.dart';
import '../garmin/garmin_activity.dart';

/// Wochenbelastung über alle Sportarten: letzte 7 Tage gegen den Wochenschnitt der drei Wochen davor, wie die
/// Laufumfang-Regel (`LoadCheck`), aber mit der Belastung statt Kilometern. Grundlage ist die Belastung der Uhr; ohne
/// sie schätzt die App aus Dauer × Intensität (nachgetragene Einheiten: Dauer × Anstrengung, Foster et al. 2001). Ab
/// 30 % mehr gibt es einen Hinweis zum Dosieren – als Verletzungsvorhersage ist so ein Verhältnis nicht belegt
/// (Impellizzeri et al. 2020).
///
/// Die Prüfung selbst (`check`) braucht den gemeinsamen Aktivitätsverlauf (`ActivityFeed`) und folgt mit dem
/// Analyse-Modul.
abstract final class WeekLoad {
  static const maxIncrease = 0.30;

  /// Unter dieser Differenz wird nicht gewarnt (etwa eine Stunde lockeres Training).
  static const minimumDifference = 60.0;

  /// Geschätzte Belastung je Minute ohne Wert der Uhr, in der Größenordnung von Garmin und session RPE (locker ≈
  /// Anstrengung 4, hart ≈ 8, Kraft ≈ 4).
  static const easyPerMinute = 1.0;
  static const hardPerMinute = 2.0;
  static const strengthPerMinute = 1.0;

  /// Gym-Einheit der App ohne Endzeit.
  static const defaultGymMinutes = 45;

  static const evidenceIDs = ['load.weekly', 'load.rpe'];

  /// Belastung einer Aktivität: Wert der Uhr, sonst aus Dauer und Intensität geschätzt.
  static ({double value, bool estimated}) load(GarminActivity activity) {
    final load = activity.trainingLoad;
    if (load != null && load > 0) return (value: load, estimated: false);
    final minutes = (activity.durationSeconds ?? 0) / 60;
    if (minutes <= 0) return (value: 0, estimated: true);
    if (activity.sport == ActivitySport.strength) return (value: minutes * strengthPerMinute, estimated: true);
    return (value: minutes * (SessionKind.isHard(activity) ? hardPerMinute : easyPerMinute), estimated: true);
  }
}

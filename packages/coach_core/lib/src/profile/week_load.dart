import '../analysis/activity_feed.dart';
import '../analysis/session_kind.dart';
import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import 'session_match.dart';
import 'user_profile.dart';

/// Wochenbelastung über alle Sportarten: letzte 7 Tage gegen den Wochenschnitt der drei Wochen davor, wie die
/// Laufumfang-Regel (`LoadCheck`), aber mit der Belastung statt Kilometern. Grundlage ist die Belastung der Uhr; ohne
/// sie schätzt die App aus Dauer × Intensität (nachgetragene Einheiten: Dauer × Anstrengung, Foster et al. 2001). Ab
/// 30 % mehr gibt es einen Hinweis zum Dosieren – als Verletzungsvorhersage ist so ein Verhältnis nicht belegt
/// (Impellizzeri et al. 2020).
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

  /// Gym-Einheiten der App, die schon als Garmin-Krafttraining vorliegen, zählen nur einmal ([ActivityFeed]).
  /// [maxIncrease]: Warnschwelle; aus den Zielen (`Personalization.maxLoadIncrease`), sonst 30 %.
  static WeekLoadResult check({
    required List<GarminActivity> activities,
    List<GymItem> gym = const [],
    required CalendarDay today,
    double maxIncrease = WeekLoad.maxIncrease,
  }) {
    final start = today.adding(-27);
    final recent = activities.where((activity) {
      final day = activity.day;
      return day != null && day >= start && day <= today;
    }).toList();
    final recentGym = gym.where((item) {
      final day = CalendarDay.fromDate(item.start.toLocal());
      return day >= start && day <= today;
    }).toList();
    var last = 0.0;
    var estimated = 0.0;
    var earlier = 0.0;
    final bySport = <TrainingSport, double>{};
    final lastStart = today.adding(-6);
    for (final entry in ActivityFeed.entries(activities: recent, gym: recentGym)) {
      final activity = entry.activity;
      final (value, isEstimate) = activity != null
          ? (load(activity).value, load(activity).estimated)
          : ((entry.gym?.minutes ?? defaultGymMinutes) * strengthPerMinute, true);
      if (entry.day >= lastStart) {
        last += value;
        if (isEstimate) estimated += value;
        final sport = SessionMatcher.sport(entry.sport);
        bySport[sport] = (bySport[sport] ?? 0) + value;
      } else {
        earlier += value;
      }
    }
    final baseline = earlier / 3;
    final result = WeekLoadResult(
      last: last.roundToDouble(),
      baseline: baseline.roundToDouble(),
      bySport: bySport.map((sport, value) => MapEntry(sport, value.roundToDouble())),
      estimatedShare: last > 0 ? estimated / last : 0,
    );
    if (baseline <= 0) return result;
    final increase = last / baseline - 1;
    result.increase = (increase * 100).roundToDouble() / 100;
    if (increase > maxIncrease && last - baseline >= minimumDifference) {
      result.warning =
          'Belastung der letzten 7 Tage über alle Sportarten: ${result.last.toInt()}, '
          '${(increase * 100).round()} % mehr als im Schnitt der drei Wochen davor (${result.baseline.toInt()}). '
          'Plane die nächsten Tage eher locker.'
          '${result.estimatedShare > 0.5 ? ' Ein Großteil ist aus Dauer und Intensität geschätzt.' : ''}';
    }
    return result;
  }

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

final class WeekLoadResult {
  WeekLoadResult({required this.last, required this.baseline, required this.bySport, required this.estimatedShare});

  final double last;
  final double baseline;

  /// Belastung der letzten 7 Tage je Sportart.
  final Map<TrainingSport, double> bySport;

  /// Anteil der letzten 7 Tage, der geschätzt ist (0…1).
  final double estimatedShare;
  double? increase;
  String? warning;

  List<String> get evidenceIDs => WeekLoad.evidenceIDs;
}

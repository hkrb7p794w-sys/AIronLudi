import '../analysis/activity_feed.dart';
import '../analysis/session_kind.dart';
import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../plan/today_focus.dart';
import '../profile/plan_adjustments.dart';
import '../profile/session_match.dart';
import '../profile/user_profile.dart';
import '../profile/week_load.dart';
import '../profile/week_schedule.dart';
import '../util/german_format.dart';
import 'trends.dart';

CalendarDay _localDay(DateTime date) => CalendarDay.fromDate(date.toLocal());

/// Wochenrückblick am Sonntag (zusammen mit „Nächste Woche planen“): Soll/Ist, Belastung gegen die Wochen davor,
/// Höhepunkte der Woche und – über `PlanSuggestion.nextWeek` – der Vorschlag für die nächste Woche.
///
/// Swift nimmt eine `TimeZone`; hier gilt wie in `WeekLoad` und `ActivityFeed` die Zeitzone des Geräts.
final class WeeklyReview {
  const WeeklyReview({
    required this.monday,
    required this.progress,
    required this.missed,
    required this.load,
    required this.highlights,
  });

  final CalendarDay monday;
  final TodayFocusProgress progress;

  /// Verpasste Einheiten („Di: Lockerer Lauf“).
  final List<String> missed;
  final WeekLoadResult load;
  final List<String> highlights;

  /// Sonntags auf „Heute“.
  static bool isDue(CalendarDay today) => Weekday.of(today) == Weekday.sunday;

  static WeeklyReview make({
    required TodayFocusProgress progress,
    required SessionWeek? week,
    required List<GarminActivity> activities,
    List<GymItem> gym = const [],
    required CalendarDay today,
  }) {
    final monday = PlanAdjustments.monday(today);
    final missed = [
      for (final result in week?.results ?? const <SessionResult>[])
        if (result.status == SessionStatus.missed)
          '${Weekday.of(result.planned.day).short}: ${result.planned.slot.title}',
    ];
    final load = WeekLoad.check(activities: activities, gym: gym, today: today);
    final inWeek = activities.where((activity) {
      final day = activity.day;
      return day != null && day >= monday && day <= today;
    }).toList();
    return WeeklyReview(
      monday: monday,
      progress: progress,
      missed: missed,
      load: load,
      highlights: highlightsFor(activities: inWeek, gym: gym, progress: progress, monday: monday, today: today),
    );
  }

  static List<String> highlightsFor({
    required List<GarminActivity> activities,
    required List<GymItem> gym,
    required TodayFocusProgress progress,
    required CalendarDay monday,
    required CalendarDay today,
  }) {
    final lines = <String>[];
    if (progress.sessionsPlanned > 0 && progress.sessionsDone >= progress.sessionsPlanned) {
      lines.add('Alle ${progress.sessionsPlanned} geplanten Einheiten geschafft.');
    }
    for (final (sport, label) in [(ActivitySport.run, 'Längster Lauf'), (ActivitySport.bike, 'Längste Radfahrt')]) {
      var longest = 0.0;
      for (final activity in activities) {
        final meters = activity.distanceMeters;
        if (activity.sport == sport && meters != null && meters > longest) longest = meters;
      }
      if (longest >= 1000) lines.add('$label: ${GermanFormat.decimal(longest / 1000)} km');
    }
    final swims = [
      for (final activity in activities)
        if (activity.sport == ActivitySport.swim) ?activity.distanceMeters,
    ];
    if (swims.isNotEmpty) {
      final swim = swims.reduce((a, b) => b > a ? b : a);
      if (swim > 0) lines.add('Weitestes Schwimmen: ${GermanFormat.number(swim)} m');
    }
    final hard = activities
        .where((activity) => SessionKind.isHard(activity) && activity.sport != ActivitySport.strength)
        .length;
    final endurance = activities
        .where(
          (activity) =>
              activity.sport == ActivitySport.run ||
              activity.sport == ActivitySport.bike ||
              activity.sport == ActivitySport.swim,
        )
        .length;
    if (endurance >= 3) lines.add('${endurance - hard} von $endurance Ausdauereinheiten locker.');
    final gymWeek = gym.where((item) {
      final day = _localDay(item.start);
      return day >= monday && day <= today;
    }).toList();
    if (gymWeek.isNotEmpty) {
      final volume = gymWeek.fold(0.0, (sum, item) => sum + item.volumeKg);
      lines.add(
        '${gymWeek.length} Krafteinheiten'
        '${volume > 0 ? ', ${GermanFormat.number((volume / 10).roundToDouble() * 10)} kg bewegt' : ''}',
      );
    }
    return lines;
  }
}

/// Minuten einer Sportart in einer Woche.
final class SportMinutes {
  const SportMinutes({required this.monday, required this.sport, required this.minutes});

  final CalendarDay monday;
  final TrainingSport sport;
  final int minutes;

  String get id => '${monday.iso}-${sport.rawValue}';

  @override
  bool operator ==(Object other) =>
      other is SportMinutes && other.monday == monday && other.sport == sport && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(monday, sport, minutes);

  @override
  String toString() => 'SportMinutes($id, $minutes)';
}

/// Trends auf einen Blick: Minuten je Sportart und Woche, aerobe Effizienz lockerer Läufe.
abstract final class TrainingTrends {
  /// Minuten je Sportart für die letzten [weeks] Wochen bis einschließlich dieser (älteste zuerst). App-Krafteinheiten
  /// zählen, Doppelte mit Garmin nur einmal.
  static List<SportMinutes> weeklyMinutes({
    required List<GarminActivity> activities,
    List<GymItem> gym = const [],
    required CalendarDay today,
    required int weeks,
  }) {
    final thisMonday = PlanAdjustments.monday(today);
    final first = thisMonday.adding(-7 * (weeks - 1));
    final minutes = <CalendarDay, Map<TrainingSport, double>>{};
    final entries = ActivityFeed.entries(
      activities: activities.where((activity) => activity.day != null && activity.day! >= first).toList(),
      gym: gym.where((item) => _localDay(item.start) >= first).toList(),
    );
    for (final entry in entries) {
      if (entry.day > today) continue;
      final value = switch (entry.activity?.durationSeconds) {
        final seconds? => seconds / 60,
        null => (entry.gym?.minutes ?? WeekLoad.defaultGymMinutes).toDouble(),
      };
      final week = minutes.putIfAbsent(PlanAdjustments.monday(entry.day), () => {});
      final sport = SessionMatcher.sport(entry.sport);
      week[sport] = (week[sport] ?? 0) + value;
    }
    return [
      for (var index = 0; index < weeks; index++)
        for (final sport in TrainingSport.values)
          if ((minutes[first.adding(7 * index)]?[sport] ?? 0).round() case final value when value > 0)
            SportMinutes(monday: first.adding(7 * index), sport: sport, minutes: value),
    ];
  }

  /// Ab dieser Dauer zählt ein lockerer Lauf für die Effizienz.
  static const minimumEfficiencySeconds = 20.0 * 60;

  /// Aerobe Effizienz lockerer Läufe: Meter je Herzschlag (Tempo in m/min geteilt durch die mittlere Herzfrequenz).
  /// Steigt sie bei gleicher Lockerheit, wird die Grundlage besser. Hitze, Hügel und Müdigkeit verschieben sie.
  static List<DayValue> aerobicEfficiency(List<GarminActivity> activities) {
    final result = <DayValue>[];
    for (final activity in activities) {
      final day = activity.day;
      final meters = activity.distanceMeters;
      final heartRate = activity.averageHeartRate;
      final seconds = activity.movingSeconds ?? activity.durationSeconds;
      if (activity.sport != ActivitySport.run ||
          SessionKind.of(activity) != SessionKind.easy ||
          day == null ||
          meters == null ||
          meters <= 0 ||
          heartRate == null ||
          heartRate <= 0 ||
          seconds == null ||
          seconds < minimumEfficiencySeconds) {
        continue;
      }
      result.add(DayValue(day: day, value: ((meters / (seconds / 60)) / heartRate * 100).roundToDouble() / 100));
    }
    return result..sort((a, b) => a.day.compareTo(b.day));
  }
}

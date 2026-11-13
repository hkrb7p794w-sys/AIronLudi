import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../profile/plan_adjustments.dart';
import '../util/german_format.dart';
import 'fitness_form.dart';

/// Summen einer Kalenderwoche.
final class WeeklyTotals {
  WeeklyTotals();

  int sessions = 0;
  double minutes = 0;
  double load = 0;
  Map<ActivitySport, double> kilometers = {};
  double? averageSleepHours;
  double? averageHRV;
  double? averageRestingHeartRate;
}

/// Wochenbericht: was in der letzten Kalenderwoche passiert ist, im Vergleich zur Woche davor. Nur Zahlen aus
/// Garmin und der App; die Hinweise sind feste Regeln.
final class WeeklyReport {
  const WeeklyReport({
    required this.monday,
    required this.week,
    required this.previous,
    required this.fitnessChange,
    required this.highlights,
  });

  /// Montag der berichteten Woche.
  final CalendarDay monday;
  final WeeklyTotals week;
  final WeeklyTotals previous;
  final double? fitnessChange;
  final List<String> highlights;

  /// Bericht für die Woche vor der Woche, die [today] enthält.
  static WeeklyReport lastWeek({
    required List<GarminActivity> activities,
    required List<DailyMetrics> days,
    required List<CalendarDay> gymDays,
    required CalendarDay today,
  }) {
    final thisMonday = PlanAdjustments.monday(today);
    final monday = thisMonday.adding(-7);
    final week = totals(activities: activities, days: days, gymDays: gymDays, from: monday);
    final previous = totals(activities: activities, days: days, gymDays: gymDays, from: monday.adding(-7));
    final form = FitnessForm.seriesUntil(activities, today: thisMonday.adding(-1));
    double? fitnessChange;
    if (FitnessForm.isReliable(form) && form.length > 7) {
      fitnessChange = ((form[form.length - 1].fitness - form[form.length - 8].fitness) * 10).roundToDouble() / 10;
    }
    return WeeklyReport(
      monday: monday,
      week: week,
      previous: previous,
      fitnessChange: fitnessChange,
      highlights: highlightsFor(week: week, previous: previous, fitnessChange: fitnessChange),
    );
  }

  static WeeklyTotals totals({
    required List<GarminActivity> activities,
    required List<DailyMetrics> days,
    required List<CalendarDay> gymDays,
    required CalendarDay from,
  }) {
    final monday = from;
    final end = monday.adding(6);
    final inWeek = activities.where((activity) {
      final day = activity.day;
      return day != null && monday <= day && day <= end;
    }).toList();
    final totals = WeeklyTotals();
    final activityDays = {for (final activity in inWeek) ?activity.day};
    // Gym-Einheiten, die nicht schon als Garmin-Aktivität zählen.
    final extraGym = {
      for (final day in gymDays)
        if (monday <= day && day <= end && !activityDays.contains(day)) day,
    };
    totals.sessions = inWeek.length + extraGym.length;
    totals.minutes = (inWeek.fold(0.0, (sum, activity) => sum + (activity.durationSeconds ?? 0)) / 60).roundToDouble();
    totals.load = inWeek.fold(0.0, (sum, activity) => sum + (activity.trainingLoad ?? 0)).roundToDouble();
    for (final activity in inWeek) {
      if (activity.sport == ActivitySport.other || activity.sport == ActivitySport.strength) continue;
      totals.kilometers[activity.sport] =
          (totals.kilometers[activity.sport] ?? 0) + (activity.distanceMeters ?? 0) / 1000;
    }
    totals.kilometers = {
      for (final MapEntry(:key, :value) in totals.kilometers.entries) key: (value * 10).roundToDouble() / 10,
    };
    final metrics = days.where((metric) => monday <= metric.day && metric.day <= end).toList();
    double? average(List<double> values) => values.isEmpty
        ? null
        : (values.fold(0.0, (sum, value) => sum + value) / values.length * 10).roundToDouble() / 10;
    totals.averageSleepHours = average([
      for (final metric in metrics)
        if (metric.sleepSeconds case final seconds?) seconds / 3600,
    ]);
    totals.averageHRV = average([for (final metric in metrics) ?metric.hrvLastNightAverage]);
    totals.averageRestingHeartRate = average([for (final metric in metrics) ?metric.restingHeartRate]);
    return totals;
  }

  static List<String> highlightsFor({
    required WeeklyTotals week,
    required WeeklyTotals previous,
    required double? fitnessChange,
  }) {
    final lines = <String>[];
    if (week.sessions == 0) {
      lines.add('Keine Einheit aufgezeichnet. Eine kurze lockere Einheit hilft, wieder reinzukommen.');
    } else if (previous.minutes > 0) {
      final change = (week.minutes / previous.minutes - 1) * 100;
      if (change > 30) {
        lines.add(
          'Deutlich mehr Trainingszeit als in der Vorwoche (+${change.round()} %). Achte diese Woche auf Erholung.',
        );
      } else if (change < -30) {
        lines.add('Deutlich weniger Trainingszeit als in der Vorwoche (${change.round()} %).');
      }
    }
    if (fitnessChange != null) {
      if (fitnessChange > 0.5) {
        lines.add('Deine Fitness ist gestiegen (+${GermanFormat.number(fitnessChange)}).');
      } else if (fitnessChange < -0.5) {
        lines.add('Deine Fitness ist leicht gesunken (${GermanFormat.number(fitnessChange)}).');
      }
    }
    final sleep = week.averageSleepHours;
    if (sleep != null && sleep < 7) {
      lines.add(
        'Im Schnitt ${GermanFormat.number(sleep)} Stunden Schlaf – Erwachsene brauchen regelmäßig mindestens 7.',
      );
    }
    final pulse = week.averageRestingHeartRate;
    final before = previous.averageRestingHeartRate;
    if (pulse != null && before != null && pulse - before >= 3) {
      lines.add(
        'Der Ruhepuls lag im Schnitt ${GermanFormat.number(pulse - before)} Schläge höher als in der Vorwoche – ein '
        'Hinweis auf Belastung, Stress oder einen Infekt.',
      );
    }
    return lines;
  }
}

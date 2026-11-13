import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../util/german_format.dart';

final class LoadCheckResult {
  LoadCheckResult({required this.lastWeekKilometers, required this.baselineKilometers});

  final double lastWeekKilometers;
  final double baselineKilometers;
  double? increase;
  String? warning;
}

/// Prüft, ob der Laufumfang zu schnell steigt: letzte 7 Tage gegenüber dem Wochenschnitt der drei Wochen davor. Über
/// 30 % Steigerung sah eine Kohortenstudie tendenziell mehr Überlastungsverletzungen (Nielsen et al. 2014); die feste
/// 10-%-Regel schützte dagegen nicht (Buist et al. 2007).
abstract final class LoadCheck {
  static const maxIncrease = 0.30;

  /// Einzellauf gegen den längsten Lauf der letzten 30 Tage (Frandsen et al. 2025).
  static const singleRunLimit = 1.10;

  /// Unter diesem bisher längsten Lauf (km) wird nicht gewarnt: Aus 2 km werden schnell 4 km, ohne dass es etwas heißt.
  static const minimumLongestKilometers = 3.0;

  /// Unter dieser Differenz (km) wird nicht gewarnt: kleine Umfänge schwanken stark.
  static const minimumDifferenceKilometers = 5.0;

  static LoadCheckResult running(List<GarminActivity> activities, {required CalendarDay today}) {
    double kilometers(CalendarDay start, int days) {
      final end = start.adding(days - 1);
      return activities
          .where((activity) {
            final day = activity.day;
            return activity.sport == ActivitySport.run && day != null && start <= day && day <= end;
          })
          .fold(0.0, (sum, activity) => sum + (activity.distanceMeters ?? 0) / 1000);
    }

    final last = kilometers(today.adding(-6), 7);
    final baseline = kilometers(today.adding(-27), 21) / 3;
    final result = LoadCheckResult(
      lastWeekKilometers: (last * 10).roundToDouble() / 10,
      baselineKilometers: (baseline * 10).roundToDouble() / 10,
    )..warning = singleRunWarning(activities, today: today);
    if (baseline <= 0) return result;
    final increase = last / baseline - 1;
    result.increase = (increase * 100).roundToDouble() / 100;
    // Die Warnung zum Einzellauf ist besser belegt und hat Vorrang.
    if (result.warning == null && increase > maxIncrease && last - baseline >= minimumDifferenceKilometers) {
      result.warning =
          'In den letzten 7 Tagen bist du ${GermanFormat.number(result.lastWeekKilometers)} km gelaufen, '
          '${(increase * 100).round()} % mehr als im Schnitt der drei Wochen davor '
          '(${GermanFormat.number(result.baselineKilometers)} km). Halte den Umfang diese Woche eher gleich.';
    }
    return result;
  }

  /// Der längste Lauf der letzten drei Tage gegen den längsten der 30 Tage davor.
  static String? singleRunWarning(List<GarminActivity> activities, {required CalendarDay today}) {
    final runs = [
      for (final activity in activities)
        if (activity.sport == ActivitySport.run && activity.day != null && (activity.distanceMeters ?? 0) > 0)
          (day: activity.day!, meters: activity.distanceMeters!),
    ];
    final recent = runs.where((run) => run.day >= today.adding(-2) && run.day <= today);
    final latest = maxBy(recent, (({CalendarDay day, double meters}) run) => run.meters);
    if (latest == null) return null;
    final start = latest.day.adding(-30);
    final earlier = runs.where((run) => run.day >= start && run.day < latest.day).map((run) => run.meters);
    if (earlier.isEmpty) return null;
    final longest = earlier.max;
    if (longest < minimumLongestKilometers * 1000 || latest.meters <= longest * singleRunLimit) return null;
    return 'Dein letzter Lauf war mit ${GermanFormat.number(latest.meters / 1000)} km deutlich länger als dein längster '
        'der letzten 30 Tage (${GermanFormat.number(longest / 1000)} km). Lass die nächsten Läufe locker und kürzer.';
  }
}

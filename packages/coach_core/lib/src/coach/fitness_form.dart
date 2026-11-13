import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';

/// Ein Tageswert der Fitness-Kurve.
final class FormPoint {
  const FormPoint({
    required this.day,
    required this.load,
    required this.fitness,
    required this.fatigue,
    required this.form,
  });

  final CalendarDay day;
  final double load;
  final double fitness;
  final double fatigue;

  /// Fitness minus Ermüdung am Morgen des Tages (vor der Belastung des Tages).
  final double form;

  String get id => day.iso;

  /// Form in % der Fitness; unabhängig davon, wie groß die Belastungswerte der Uhr sind.
  double? get formPercent => fitness > 1 ? form / fitness * 100 : null;
}

/// Einordnung der Form in % der Fitness. Die Grenzen sind Praxiswerte aus Trainingssoftware (intervals.icu), keine
/// Studienergebnisse.
enum FormZone {
  fresh('Erholt', 'Die Ermüdung ist deutlich unter deiner Fitness – gut für einen Wettkampf oder einen Test.'),
  neutral('Ausgeglichen', 'Belastung und Fitness halten sich die Waage.'),
  productive('Im Aufbau', 'Du trainierst mehr, als du gewohnt bist. So steigt die Fitness; plane Erholung ein.'),
  high(
    'Sehr hohe Belastung',
    'Die Ermüdung liegt weit über deiner Fitness. Achte besonders auf Schlaf, Erholungswerte und Ruhetage.',
  );

  const FormZone(this.label, this.explanation);

  final String label;
  final String explanation;

  static FormZone of(double percent) {
    if (percent > 5) return fresh;
    if (percent >= -10) return neutral;
    if (percent >= -30) return productive;
    return high;
  }
}

/// Fitness, Ermüdung und Form aus der Trainingsbelastung der Uhr (Garmin „Training Load“ je Aktivität), nach dem
/// Impulse-Response-Modell von Banister (Übersicht: Clarke & Skiba 2013): Fitness ist der gleitende Mittelwert über 42
/// Tage, Ermüdung über 7 Tage, Form die Differenz. Die Kurven beschreiben den Verlauf; als Vorhersage von Verletzungen
/// taugen solche Verhältnisse nicht (Impellizzeri et al. 2020), daher warnt die App damit nicht; nur bei sehr negativer
/// Form rät die Tagesampel zu lockerem Training (`Recommendation.limitedByForm`).
abstract final class FitnessForm {
  static const fitnessDays = 42.0;
  static const fatigueDays = 7.0;

  /// Erst nach so vielen Tagen mit Daten ist die Fitness-Kurve eingeschwungen.
  static const warmUpDays = 42;

  /// Unter dieser Form (in % der Fitness, Zone „sehr hohe Belastung“) rät die Ampel zu lockerem Training. Praxiswert;
  /// nie zu einer Pause, denn als Vorhersage taugt die Kurve nicht.
  static const lockerBelowPercent = -30.0;
  static const reasonPrefix = 'Form ';

  /// Tageswerte von [start] bis [end]; Tage ohne Aktivität zählen mit Belastung 0.
  static List<FormPoint> series(List<GarminActivity> activities, {required CalendarDay from, required CalendarDay to}) {
    final loads = <CalendarDay, double>{};
    for (final activity in activities) {
      final day = activity.day;
      final load = activity.trainingLoad;
      if (day == null || load == null || load <= 0) continue;
      loads[day] = (loads[day] ?? 0) + load;
    }
    var fitness = 0.0;
    var fatigue = 0.0;
    final points = <FormPoint>[];
    double round(double value) => (value * 10).roundToDouble() / 10;
    for (var day = from; day <= to; day = day.adding(1)) {
      final load = loads[day] ?? 0;
      final form = fitness - fatigue;
      fitness += (load - fitness) / fitnessDays;
      fatigue += (load - fatigue) / fatigueDays;
      points.add(FormPoint(day: day, load: load, fitness: round(fitness), fatigue: round(fatigue), form: round(form)));
    }
    return points;
  }

  /// Verlauf ab der ersten Aktivität mit Belastung (höchstens 180 Tage zurück) bis heute.
  static List<FormPoint> seriesUntil(List<GarminActivity> activities, {required CalendarDay today}) {
    final earliest = today.adding(-180);
    final days = activities
        .where((activity) => (activity.trainingLoad ?? 0) > 0)
        .map((activity) => activity.day)
        .nonNulls
        .where((day) => day >= earliest);
    if (days.isEmpty) return const [];
    final first = days.reduce((a, b) => a <= b ? a : b);
    return series(activities, from: first, to: today);
  }

  /// Ob die Kurve schon aussagekräftig ist.
  static bool isReliable(List<FormPoint> points) => points.length >= warmUpDays;

  /// Grund für die Ampel, wenn die Ermüdung weit über der Fitness liegt (nur bei eingeschwungener Kurve).
  static String? recoveryReason(List<FormPoint> points) {
    if (!isReliable(points)) return null;
    final percent = points.last.formPercent;
    if (percent == null || percent >= lockerBelowPercent) return null;
    return '$reasonPrefix${percent.round()} % der Fitness – Ermüdung weit über dem Gewohnten';
  }

  static double clampPercent(double value) => math.max(-100, math.min(100, value));
}

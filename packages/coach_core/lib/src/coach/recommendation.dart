import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../util/german_format.dart';
import 'fitness_form.dart';
import 'recovery_level.dart';

/// Regelbasierte Tagesempfehlung – deterministisch, ohne Netzwerk. Die KI formuliert nur den Text dazu und darf die
/// Entscheidung nicht ändern.
final class Recommendation {
  const Recommendation({required this.level, required this.reasons});

  final RecoveryLevel level;
  final List<String> reasons;

  String get label => level.label;
  String get advice => level.advice;

  /// Tagesampel mit der Form: sehr negative Form ergibt höchstens „locker“ (eine Pause bleibt eine Pause).
  Recommendation limitedByForm(List<FormPoint> points) {
    final reason = FitnessForm.recoveryReason(points);
    if (reason == null) return this;
    return Recommendation(
      level: level > RecoveryLevel.locker ? level : RecoveryLevel.locker,
      reasons: [...reasons, reason],
    );
  }

  /// Die Form hat die Ampel mitbestimmt.
  bool get isLimitedByForm => reasons.any((reason) => reason.startsWith(FitnessForm.reasonPrefix));

  Map<String, Object?> toJson() => {'level': level.rawValue, 'reasons': reasons};

  @override
  bool operator ==(Object other) =>
      other is Recommendation && other.level == level && const ListEquality<String>().equals(other.reasons, reasons);

  @override
  int get hashCode => Object.hash(level, Object.hashAll(reasons));
}

/// Die eine Tagesampel für alle Ansichten.
final class TodayState {
  const TodayState({required this.metrics, required this.recommendation, required this.isKnown});

  final DailyMetrics? metrics;
  final Recommendation recommendation;

  /// `false`: keine bewertbaren Werte, die Ampel darf nicht als Messung erscheinen.
  final bool isKnown;

  RecoveryLevel? get level => isKnown ? recommendation.level : null;
}

/// Portierung von `garmin_ai_coach/recommendation.py` (Altbestand).
///
/// Grundlagen der Regeln:
/// - HRV: maßgeblich ist der 7-Tage-Schnitt relativ zur persönlichen Baseline (Garmin „HRV-Status“), nicht die
///   Einzelnacht (Plews et al. 2012/2013; Garmin-Handbuch „Heart Rate Variability Status“).
/// - Readiness: Garmins Stufen (1–24 Poor, 25–49 Low, …), nur nach unten genutzt, weil die akute Belastung selbst in
///   den Score einfließt. Nur über den Garmin-Connect-Zugang; ohne Wert entfällt die Regel.
/// - Ruhepuls: mindestens 5 bpm über dem eigenen 7-Tage-Schnitt als Warnsignal.
/// - Schlaf: unter 5 h rot, unter 6 h gelb.
abstract final class RecoveryEvaluator {
  static const hrvStatusGerman = {
    'BALANCED': 'ausgeglichen',
    'UNBALANCED': 'unausgeglichen',
    'LOW': 'niedrig',
    'POOR': 'schlecht',
    'NONE': 'noch kein Status',
  };

  static Recommendation evaluate(
    DailyMetrics metrics, {
    required double? restingHeartRate7DayAverage,
    double? readinessScore,
  }) {
    var level = RecoveryLevel.normal;
    final reasons = <String>[];
    void worsen(RecoveryLevel candidate) {
      if (candidate > level) level = candidate;
    }

    final status = metrics.hrvStatus?.toUpperCase();
    if (status == 'LOW' || status == 'POOR') {
      worsen(RecoveryLevel.pause);
      reasons.add('HRV-Status ${hrvStatusGerman[status] ?? status} (7-Tage-Schnitt deutlich unter deiner Baseline)');
    } else if (status == 'UNBALANCED') {
      final weekly = metrics.hrvWeeklyAverage;
      final low = metrics.hrvBaselineLow;
      if (weekly != null && low != null && weekly < low) {
        worsen(RecoveryLevel.locker);
        reasons.add('HRV-Status unausgeglichen, 7-Tage-Schnitt unter deiner Baseline');
      } else {
        // Über der Baseline ist nicht automatisch gut (kann bei viel lockerem Umfang auf Überlastung hindeuten) – nur
        // benennen, nicht herabstufen.
        reasons.add('HRV-Status unausgeglichen (über der Baseline) – im Blick behalten');
      }
    } else if (status == 'BALANCED') {
      reasons.add('HRV-Status ausgeglichen');
    }

    final score = readinessScore ?? metrics.trainingReadiness;
    if (score != null) {
      if (score < 25) {
        worsen(RecoveryLevel.pause);
        reasons.add('Readiness ${score.round()} (Garmin-Stufe „Poor“)');
      } else if (score < 50) {
        worsen(RecoveryLevel.locker);
        reasons.add('Readiness ${score.round()} (Garmin-Stufe „Low“)');
      }
    }

    final restingHR = metrics.restingHeartRate;
    final average = restingHeartRate7DayAverage;
    if (restingHR != null && average != null && restingHR >= average + 5) {
      worsen(RecoveryLevel.locker);
      reasons.add('Ruhepuls ${restingHR.round()} bpm, ${(restingHR - average).round()} über deinem 7-Tage-Schnitt');
    }

    // Die Schwellen prüfen die ungerundeten Sekunden. Die Anzeige rundet ab, sonst stünden 4:57 h als „5 h“ da.
    final seconds = metrics.sleepSeconds;
    if (seconds != null) {
      final hours = GermanFormat.decimal((seconds / 360).floorToDouble() / 10);
      if (seconds < 5 * 3600) {
        worsen(RecoveryLevel.pause);
        reasons.add('nur $hours h Schlaf');
      } else if (seconds < 6 * 3600) {
        worsen(RecoveryLevel.locker);
        reasons.add('kurzer Schlaf ($hours h)');
      }
    }

    if (reasons.isEmpty) reasons.add('keine Erholungswerte auffällig');
    return Recommendation(level: level, reasons: reasons);
  }

  /// Liegt mindestens ein Wert vor, aus dem die Ampel überhaupt etwas ableiten kann? Schritte allein reichen nicht.
  static bool hasInputs(DailyMetrics metrics, {required double? restingHeartRate7DayAverage}) {
    final status = metrics.hrvStatus?.toUpperCase();
    return (status != null && status != 'NONE') ||
        metrics.trainingReadiness != null ||
        metrics.sleepSeconds != null ||
        (metrics.restingHeartRate != null && restingHeartRate7DayAverage != null);
  }

  /// Werte von heute, sonst die der letzten Nacht; sehr negative Form ergibt höchstens „locker“.
  static TodayState today({
    required List<DailyMetrics> days,
    required List<FormPoint> form,
    required CalendarDay today,
  }) {
    final byDay = <CalendarDay, DailyMetrics>{};
    for (final metrics in days) {
      byDay.putIfAbsent(metrics.day, () => metrics);
    }
    double? averageFor(CalendarDay day) =>
        average((metrics) => metrics.restingHeartRate, days, from: 1, to: 7, today: day);
    final candidates = [byDay[today], byDay[today.adding(-1)]].nonNulls.toList();
    final usable = candidates.firstWhereOrNull(
      (metrics) => hasInputs(metrics, restingHeartRate7DayAverage: averageFor(metrics.day)),
    );
    final metrics = usable ?? candidates.firstOrNull;
    final recommendation = evaluate(
      metrics ?? DailyMetrics(today),
      restingHeartRate7DayAverage: averageFor(metrics?.day ?? today),
    ).limitedByForm(form);
    return TodayState(
      metrics: metrics,
      recommendation: recommendation,
      isKnown: usable != null || recommendation.isLimitedByForm,
    );
  }

  static TodayState todayFromActivities({
    required List<DailyMetrics> days,
    required List<GarminActivity> activities,
    required CalendarDay today,
  }) => RecoveryEvaluator.today(
    days: days,
    form: FitnessForm.seriesUntil(activities, today: today),
    today: today,
  );

  /// Mittelwert eines Werts über die Tage [from]…[to] vor [today] (wie `_history_avg` im Altbestand).
  static double? average(
    double? Function(DailyMetrics metrics) value,
    List<DailyMetrics> history, {
    required int from,
    required int to,
    required CalendarDay today,
  }) {
    final values = history
        .where((metrics) {
          final offset = metrics.day.daysUntil(today);
          return offset >= from && offset <= to;
        })
        .map(value)
        .nonNulls
        .toList();
    if (values.isEmpty) return null;
    return (values.sum / values.length * 10).roundToDouble() / 10;
  }
}

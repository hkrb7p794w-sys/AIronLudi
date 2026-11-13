import '../calendar/calendar_day.dart';
import '../fit/fit_decoder.dart';
import '../garmin/garmin_activity.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';
import '../util/rounding.dart';
import 'aerobic_decoupling.dart';
import 'pace_check.dart';
import 'session_kind.dart';

/// Ergebnis der FIT-Auswertung einer Aktivität (aerobe Kopplung und Runden für den Pace-Check).
final class ActivityAnalysis {
  ActivityAnalysis({required this.id, required this.day, this.name}) : method = AerobicDecoupling.methodVersion;

  final int id;
  CalendarDay day;
  String? name;

  /// Version der Kopplungs-Methode; ältere Einträge werden neu bewertet.
  int method;
  DecouplingSport? decouplingSport;
  DecouplingResult? decoupling;

  /// Warum keine Kopplung berechnet wurde (für die Anzeige „nicht gewertet“).
  String? skipReason;

  /// Anteil der Zeit in Zone 4–5 in Prozent.
  double? highZonePercent;
  PaceKind? paceKind;
  List<PaceLap>? laps;

  /// Selbsteinschätzung auf der Uhr (1–10).
  double? rpe;

  ActivityAnalysis copy() => fromJson(toJson())!;

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day.toJson(),
    'name': ?name,
    'method': method,
    'decouplingSport': ?decouplingSport?.rawValue,
    'decoupling': ?decoupling?.toJson(),
    'skipReason': ?skipReason,
    'highZonePercent': ?highZonePercent,
    'paceKind': ?paceKind?.rawValue,
    'laps': ?laps?.map((lap) => lap.toJson()).toList(),
    'rpe': ?rpe,
  };

  static ActivityAnalysis? fromJson(Object? json) {
    if (json is! Map || json['day'] is! Map) return null;
    final id = jsonInt(json['id']);
    if (id == null) return null;
    final analysis =
        ActivityAnalysis(
            id: id,
            day: CalendarDay.fromJson((json['day'] as Map).cast<String, Object?>()),
            name: json['name'] as String?,
          )
          ..method = jsonInt(json['method']) ?? 0
          ..decouplingSport = enumFromRaw(DecouplingSport.values, json['decouplingSport'])
          ..decoupling = DecouplingResult.fromJson(json['decoupling'])
          ..skipReason = json['skipReason'] as String?
          ..highZonePercent = jsonDouble(json['highZonePercent'])
          ..paceKind = enumFromRaw(PaceKind.values, json['paceKind'])
          ..laps = json['laps'] is List ? (json['laps'] as List).map(PaceLap.fromJson).nonNulls.toList() : null
          ..rpe = jsonDouble(json['rpe']);
    return analysis;
  }
}

/// Welche Aktivitäten ausgewertet werden und wie die Ergebnisse in Kopplung und Pace-Check einfließen (Altbestand:
/// `app._update_decoupling_cache`, `app._run_pace_check`).
abstract final class ActivityAnalysisPlanner {
  /// FIT-Abrufe je Synchronisierung (Garmin-Rate-Limit schonen; der Rest folgt beim nächsten Abruf).
  static const maxFetchesPerSync = 6;
  static const decouplingDays = 60;

  /// Kürzere Einheiten zählen im Altbestand nicht als Trainingseinheit (`tagesform.MIN_DURATION_MIN`).
  static const minSessionMinutes = 15.0;

  /// Lauf mit Schwellen- oder Intervall-Charakter für den Pace-Check.
  static PaceKind? paceKind(GarminActivity activity) {
    if (activity.sport != ActivitySport.run || (activity.durationSeconds ?? 0) / 60 < minSessionMinutes) return null;
    return switch (SessionKind.of(activity)) {
      SessionKind.threshold => PaceKind.threshold,
      SessionKind.vo2 => PaceKind.vo2,
      _ => null,
    };
  }

  /// Ob für die Aktivität die FIT-Datei nötig ist.
  static bool needsFile(GarminActivity activity) =>
      AerobicDecoupling.classify(activity) != null || paceKind(activity) != null;

  /// Noch nicht (oder mit alter Methode) ausgewertete Aktivitäten der letzten 60 Tage, jüngste zuerst. Läufe und
  /// Fahrten ohne Aussage (z. B. HF-Zweitaufzeichnung der Uhr) fallen weg.
  static List<GarminActivity> pending(
    List<GarminActivity> activities, {
    required Map<int, ActivityAnalysis> analyzed,
    required CalendarDay today,
  }) {
    final start = today.adding(-decouplingDays);
    final result = activities.where((activity) {
      final day = activity.day;
      if (day == null || day < start || day > today) return false;
      if (analyzed[activity.id]?.method == AerobicDecoupling.methodVersion) return false;
      return needsFile(activity) || AerobicDecoupling.skipReason(activity) != null;
    }).toList()..sort((a, b) => (b.startLocal ?? '').compareTo(a.startLocal ?? ''));
    return result;
  }

  /// Auswertung einer Aktivität; [fit] ist `null`, wenn keine Datei nötig war oder sie nicht lesbar war.
  static ActivityAnalysis analyze(GarminActivity activity, {FitActivity? fit, double? rpe}) {
    final share = AerobicDecoupling.highZoneShare(activity);
    final analysis =
        ActivityAnalysis(id: activity.id, day: activity.day ?? const CalendarDay(2000, 1, 1), name: activity.name)
          ..highZonePercent = share == null ? null : round1HalfEven(share * 100)
          ..rpe = rpe;
    final sport = AerobicDecoupling.classify(activity);
    if (sport != null) {
      analysis.decouplingSport = sport;
      final result = fit == null ? null : AerobicDecoupling.compute(fit, sport);
      if (result != null) {
        analysis.decoupling = result;
      } else {
        analysis.skipReason = fit == null ? 'FIT-Datei nicht lesbar' : 'keine verwertbare Zeitreihe/Runden';
      }
    } else {
      analysis.skipReason = AerobicDecoupling.skipReason(activity);
    }
    final kind = paceKind(activity);
    if (kind != null) {
      analysis
        ..paceKind = kind
        ..laps = fit == null ? [] : PaceLap.from(fit.laps);
    }
    return analysis;
  }

  /// RPE aus `/activity-service/activity/{id}` (`summaryDTO.directWorkoutRpe`, 10–100).
  static double? rpeFromActivityDetail(JsonValue json) {
    final raw = json['summaryDTO']?['directWorkoutRpe']?.doubleValue;
    if (raw == null || raw <= 0) return null;
    return roundHalfEven(raw / 10 * 10) / 10;
  }

  /// Harte Läufe der letzten zwei Tage ohne RPE: Die Selbsteinschätzung wird oft erst später eingetragen, also erneut
  /// fragen (`tagesform.RPE_REFRESH_DAYS`).
  static List<int> needsRPE(List<ActivityAnalysis> analyses, {required CalendarDay today}) => [
    for (final analysis in analyses)
      if (analysis.paceKind != null && analysis.rpe == null && analysis.day >= today.adding(-2)) analysis.id,
  ];

  static int _byDayAndId(ActivityAnalysis a, ActivityAnalysis b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.id.compareTo(b.id);
  }

  /// Sitzungen für den Pace-Check (letzte 6 Wochen, älteste zuerst).
  static List<PaceSession> paceSessions(List<ActivityAnalysis> analyses, {required CalendarDay today}) {
    final start = today.adding(-PaceCheck.lookbackDays);
    final result = [
      for (final analysis in analyses)
        if (analysis.paceKind case final kind? when analysis.day >= start)
          PaceSession(
            id: analysis.id,
            day: analysis.day,
            name: analysis.name,
            kind: kind,
            rpe: analysis.rpe,
            laps: analysis.laps ?? const [],
          ),
    ]..sort((a, b) => a.day != b.day ? a.day.compareTo(b.day) : a.id.compareTo(b.id));
    return result;
  }

  /// Gewertete Einheiten einer Sportart, älteste zuerst.
  static List<ActivityAnalysis> decoupled(Iterable<ActivityAnalysis> analyses, {required DecouplingSport sport}) =>
      analyses.where((analysis) => analysis.decouplingSport == sport && analysis.decoupling != null).toList()
        ..sort(_byDayAndId);

  /// Nicht gewertete Läufe/Fahrten mit Grund, die letzten zehn.
  static List<ActivityAnalysis> skipped(List<ActivityAnalysis> analyses) {
    final result = analyses.where((analysis) => analysis.decoupling == null && analysis.skipReason != null).toList()
      ..sort(_byDayAndId);
    return result.length > 10 ? result.sublist(result.length - 10) : result;
  }

  /// Schnitt der letzten fünf Werte (`avg_recent_pct`).
  static double? recentAverage(List<ActivityAnalysis> sessions) {
    final values = sessions.map((session) => session.decoupling?.percent).nonNulls.toList();
    final last = values.length > 5 ? values.sublist(values.length - 5) : values;
    if (last.isEmpty) return null;
    return round1HalfEven(last.fold<double>(0, (sum, value) => sum + value) / last.length);
  }
}

import '../evidence/evidence.dart';
import '../evidence/user_sources.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import 'recommendation.dart';
import 'recovery_level.dart';
import 'season_plan.dart';

/// Datenschutzmodus für KI-Aufrufe. Im kostenlosen Gemini-Kontingent darf Google Eingaben zur
/// Produktverbesserung nutzen (Gemini API Additional Terms, „Unpaid Services“). „Reduziert“ schickt daher
/// keine Rohwerte (Ruhepuls, HRV in ms, Schlafstunden), nur Einordnungen.
enum PrivacyMode implements RawEnum {
  reduced('reduziert'),
  full('voll');

  const PrivacyMode(this.rawValue);

  @override
  final String rawValue;

  static PrivacyMode? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Baut die Eingabe der Worker-Aufgabe `daily_note` und die Notiz ohne KI. KI-Eingaben sind JSON-Objekte
/// (`Map<String, Object?>`), wie `[String: JSONValue]` in Swift.
abstract final class CoachingNote {
  static Map<String, Object?> input({
    required Recommendation recommendation,
    required DailyMetrics? metrics,
    required PlanState plan,
    required SeasonConfig config,
    required WeeklyVolume week,
    required PrivacyMode privacy,
  }) {
    final decisionReasons = privacy == PrivacyMode.full
        ? recommendation.reasons
        : neutralReasons(recommendation, metrics);
    return {
      'weekday': plan.weekday,
      'phase': plan.phase.rawValue,
      'phaseFocus': plan.phase.focus,
      'phaseDetail': plan.plan.promptText,
      'raceName': config.mainRaceDescription,
      'raceDate': GermanFormat.date(config.mainRaceDate),
      'raceGoal': config.raceGoal,
      'daysToRace': plan.daysToRace.toDouble(),
      'testValues': SeasonPlan.testValuesText(config),
      'todayItems': [for (final item in plan.todayFixed) item.text],
      'openItems': [...plan.weekOpen],
      'daysLeftInWeek': plan.daysLeftInWeek.toDouble(),
      'volumes': {
        'swimKm': _rounded(week.kilometers[ActivitySport.swim] ?? 0),
        'bikeKm': _rounded(week.kilometers[ActivitySport.bike] ?? 0),
        'runKm': _rounded(week.kilometers[ActivitySport.run] ?? 0),
      },
      'vitals': vitals(metrics, privacy: privacy),
      'decision': {'label': recommendation.label, 'advice': recommendation.advice, 'reasons': decisionReasons},
      'evidence': evidenceInput(dailyNoteEvidence),
    };
  }

  /// „Titel (Zusatz) – schon erledigt“ bzw. „→ Hinweis“ für den Prompt.
  static String line(String title, String caption, {required bool done, required String chip}) {
    var text = caption.isEmpty ? title : '$title ($caption)';
    if (done) text += ' – schon erledigt';
    if (chip.isNotEmpty) text += ' → $chip';
    return text;
  }

  /// Regeln, auf die sich die Tagesnotiz stützen darf.
  static const dailyNoteEvidence = [
    'recovery.hrv',
    'recovery.rhr',
    'recovery.sleep',
    'recovery.subjective',
    'intensity.distribution',
    'run.4x4',
    'strength.economy',
    'strength.interference',
    'taper',
  ];

  /// `[{id, statement}]` für den Worker: Nur diese Aussagen darf die KI als Begründung nutzen.
  static List<Map<String, Object?>> evidenceInput(List<String> ids) => [
    for (final rule in Evidence.rulesFor(ids)) {'id': rule.id, 'statement': rule.statement},
  ];

  /// Liest `"quellen": ["id", …]` aus der KI-Antwort; nur bekannte Regeln und eigene Quellen (`UserSources`).
  static List<String> sources(JsonValue output) => [
    for (final value in output['quellen']?.arrayValue ?? const <JsonValue>[])
      if (value.stringValue case final id? when Evidence.rulesByID[id] != null || UserSources.isUserID(id)) id,
  ];

  /// Erholungsblock: im Modus „reduziert“ ohne Rohwerte (wie `vitals_block` im Altbestand).
  static List<String> vitals(DailyMetrics? metrics, {required PrivacyMode privacy}) {
    if (metrics == null) return ['keine Erholungsdaten für heute'];
    final status = switch (metrics.hrvStatus) {
      final status? => RecoveryEvaluator.hrvStatusGerman[status] ?? status,
      null => 'keine Daten',
    };
    switch (privacy) {
      case PrivacyMode.full:
        final sleep = metrics.sleepHours;
        return [
          'Ruhepuls: ${_number(metrics.restingHeartRate, ' bpm')}',
          'HRV letzte Nacht: ${_number(metrics.hrvLastNightAverage, ' ms')}, 7-Tage-Schnitt '
              '${_number(metrics.hrvWeeklyAverage, ' ms')} (Status $status)',
          'Body Battery: ${_number(metrics.bodyBatteryHigh, '')}',
          'Schlaf: ${sleep == null ? 'keine Daten' : '${GermanFormat.decimal(sleep)} h'}, Score '
              '${_number(metrics.sleepScore, '')}',
        ];
      case PrivacyMode.reduced:
        final sleepSeconds = metrics.sleepSeconds;
        return [
          'HRV-Status (7-Tage-Schnitt vs. Baseline): $status',
          'Schlaf: ${_band(sleepSeconds == null ? null : sleepSeconds / 3600, const [(6, 'kurz'), (7.5, 'normal')], otherwise: 'gut')}',
          'Body Battery: ${_band(metrics.bodyBatteryHigh, const [(30, 'niedrig'), (60, 'mittel')], otherwise: 'hoch')}',
        ];
    }
  }

  /// Begründungen ohne Zahlen für den Modus „reduziert“.
  static List<String> neutralReasons(Recommendation recommendation, DailyMetrics? metrics) => [
    for (final reason in recommendation.reasons)
      if (reason.startsWith('Ruhepuls'))
        'Ruhepuls deutlich über deinem 7-Tage-Schnitt'
      else if (reason.startsWith('nur') && reason.endsWith('Schlaf'))
        'sehr kurzer Schlaf'
      else if (reason.startsWith('kurzer Schlaf'))
        'kurzer Schlaf'
      else if (reason.startsWith('Readiness'))
        'Garmin-Readiness niedrig'
      else
        reason,
  ];

  /// Notiz ohne KI – wird angezeigt, solange die KI nicht erreichbar oder nicht eingerichtet ist.
  static List<String> fallback(Recommendation recommendation, {required PlanState plan}) {
    final lines = ['${recommendation.label}: ${recommendation.advice}', 'Grund: ${recommendation.reasons.join('; ')}.'];
    final today = [for (final item in plan.todayFixed) item.text];
    if (today.isNotEmpty) lines.add('Heute laut Wochenrahmen: ${today.join(', ')}.');
    if (plan.weekOpen.isNotEmpty) {
      if (plan.daysLeftInWeek == 0) {
        final rest = recommendation.level == RecoveryLevel.normal
            ? 'nur noch heute möglich'
            : 'entfällt bei dieser Tagesampel diese Woche';
        lines.add('Offen, heute letzter Tag der Woche ($rest): ${plan.weekOpen.join(', ')}.');
      } else {
        lines.add('Diese Woche noch offen: ${plan.weekOpen.join(', ')}.');
      }
    }
    return lines;
  }

  /// Liest `{"punkte": ["…", …]}` aus der KI-Antwort.
  static List<String> points(JsonValue output) {
    final values = output['punkte']?.arrayValue ?? output.arrayValue ?? const <JsonValue>[];
    return [
      for (final value in values)
        if (value.stringValue?.trim() case final text? when text.isNotEmpty) text,
    ];
  }

  static String _number(double? value, String unit) =>
      value == null ? 'keine Daten' : GermanFormat.decimal(value) + unit;

  static String _band(double? value, List<(double, String)> limits, {required String otherwise}) {
    if (value == null) return 'keine Daten';
    for (final (limit, label) in limits) {
      if (value < limit) return label;
    }
    return otherwise;
  }

  static double _rounded(double value) => (value * 10).roundToDouble() / 10;
}

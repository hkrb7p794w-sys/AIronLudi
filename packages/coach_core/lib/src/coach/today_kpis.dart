import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';
import 'daily_strain.dart';
import 'heart_rate_strain.dart';
import 'recovery_level.dart';

/// Ampel einer Kennzahl: Grün = im Zielbereich, Gelb = Aufmerksamkeit, Rot = kritisch bzw. hohe Belastung.
enum KpiStatus {
  good,
  moderate,
  critical,
  unknown;

  /// Die ungünstigere von beiden (unbekannt zählt nicht).
  KpiStatus worse(KpiStatus other) {
    if (this == unknown) return other;
    if (other == unknown) return this;
    return index >= other.index ? this : other;
  }
}

/// Eine Kennzahl für den Ring: Anteil 0–1, Wert in der Mitte, kurze Zeile darunter.
final class Kpi {
  const Kpi({
    required this.title,
    required this.value,
    required this.fraction,
    required this.status,
    required this.caption,
    this.secondaryFraction,
    this.valueStatus,
  });

  final String title;

  /// Text in der Ringmitte („82“, „7,4 h“, „11,3“, „–“).
  final String value;

  /// Gefüllter Anteil des Rings (0–1).
  final double fraction;

  /// Heller zweiter Abschnitt hinter [fraction] (beim Strain: noch geplant), ebenfalls 0–1 vom ganzen Ring.
  final double? secondaryFraction;
  final KpiStatus status;
  final String caption;

  /// Eigene Farbe für den Wert in der Mitte, wenn er etwas anderes aussagt als der Ring (beim Strain: noch nichts
  /// trainiert, aber viel geplant – die „0,0“ ist neutral, die Warnung gilt dem Geplanten). `null` = [status].
  final KpiStatus? valueStatus;
}

/// Die drei Kennzahlen oben auf „Heute“: Schlaf, Erholung, Strain (0–21). Regeln, keine KI; die Farbe der Erholung
/// folgt nie einer besseren Stufe als die Tagesampel der App.
abstract final class TodayKpis {
  /// Strain-Skala 0–21 aus Trainings-Stress-Punkten (TSS-artig): logarithmisch wie bei WHOOP, damit der Wert am
  /// oberen Ende immer schwerer steigt. 50 Punkte ≈ 8,9, 100 ≈ 14, 150 ≈ 17, 250 ≈ 19,7.
  static const strainMaximum = 21.0;
  static const strainScale = 91.0;

  static double strainOf(double points) =>
      points <= 0 ? 0 : (strainMaximum * (1 - math.exp(-points / strainScale)) * 10).roundToDouble() / 10;

  static String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

  /// Schlaf: Schlafwert (0–100, Uhr oder WHOOP), sonst Schlafdauer gegen das Schlafziel.
  static Kpi sleep(DailyMetrics? metrics, {double targetHours = 8}) {
    final score = metrics?.sleepScore;
    final hours = metrics?.sleepHours;
    if (score != null) {
      return Kpi(
        title: 'Schlaf',
        value: '${score.round()}',
        fraction: (score / 100).clamp(0, 1),
        status: score >= 80
            ? KpiStatus.good
            : score >= 60
            ? KpiStatus.moderate
            : KpiStatus.critical,
        caption: hours == null ? 'Schlafwert' : '${_decimal(hours)} h',
      );
    }
    if (hours != null) {
      final share = hours / targetHours;
      return Kpi(
        title: 'Schlaf',
        value: '${_decimal(hours)} h',
        fraction: share.clamp(0, 1),
        status: share >= 0.95
            ? KpiStatus.good
            : hours >= targetHours - 1
            ? KpiStatus.moderate
            : KpiStatus.critical,
        caption: 'Ziel ${_decimal(targetHours)} h',
      );
    }
    return const Kpi(title: 'Schlaf', value: '–', fraction: 0, status: KpiStatus.unknown, caption: 'keine Daten');
  }

  static KpiStatus _levelStatus(RecoveryLevel? level) => switch (level) {
    RecoveryLevel.normal => KpiStatus.good,
    RecoveryLevel.locker => KpiStatus.moderate,
    RecoveryLevel.pause => KpiStatus.critical,
    null => KpiStatus.unknown,
  };

  /// Erholung: Erholungswert 0–100 (WHOOP-Recovery bzw. Training Readiness), sonst Body Battery beim Aufwachen,
  /// sonst nur die Tagesampel. Schwellen wie bei WHOOP: ab 67 grün, ab 34 gelb.
  static Kpi recovery(DailyMetrics? metrics, RecoveryLevel? level) {
    final ruled = _levelStatus(level);
    final (score, caption) = switch ((metrics?.trainingReadiness, metrics?.bodyBatteryAtWake)) {
      // Unter dem Ring die Herkunft, nicht die Empfehlung – die steht schon in „Jetzt dran“.
      (final readiness?, _) => (readiness, 'Messwert'),
      (_, final battery?) => (battery, 'Body Battery'),
      _ => (null, level == null ? 'keine Daten' : 'Tagesampel'),
    };
    if (score != null) {
      final measured = score >= 67
          ? KpiStatus.good
          : score >= 34
          ? KpiStatus.moderate
          : KpiStatus.critical;
      return Kpi(
        title: 'Erholung',
        value: '${score.round()} %',
        fraction: (score / 100).clamp(0, 1),
        status: measured.worse(ruled),
        caption: caption,
      );
    }
    return Kpi(
      title: 'Erholung',
      value: switch (level) {
        RecoveryLevel.normal => 'Gut',
        RecoveryLevel.locker => 'Mäßig',
        RecoveryLevel.pause => 'Pause',
        null => '–',
      },
      fraction: switch (level) {
        RecoveryLevel.normal => 1,
        RecoveryLevel.locker => 0.6,
        RecoveryLevel.pause => 0.3,
        null => 0,
      },
      status: ruled,
      caption: caption,
    );
  }

  /// Strain 0–21: erledigt (voll) und noch geplant (hell). Farbe aus der Einordnung gegen den üblichen Tag; bei
  /// eingeschränkter Erholung ist „hoch“ schon rot.
  /// Belastungspunkte → gewichtete Pulsminuten, um Geplantes auf einen gemessenen Strain aufzuschlagen
  /// (100 Punkte ≈ 1 h an der Schwelle ≈ 250 gewichtete Minuten).
  static const pulseMinutesPerPoint = 2.5;

  /// Strain-Ring: gemessen (WHOOP bzw. Puls über den ganzen Tag) oder – ohne Pulsverlauf – aus den Trainings
  /// geschätzt; noch Geplantes hell obendrauf.
  static Kpi strain(DailyStrain strain) {
    final measured = strain.measured;
    final done = measured ?? strainOf(strain.done);
    final total = measured == null
        ? strainOf(strain.total)
        : HeartRateStrain.strainOf(HeartRateStrain.loadOf(measured) + strain.planned * pulseMinutesPerPoint);
    final status = switch (strain.level) {
      StrainLevel.rest || StrainLevel.light || StrainLevel.moderate => KpiStatus.good,
      StrainLevel.high => strain.recovery == RecoveryLevel.normal ? KpiStatus.moderate : KpiStatus.critical,
      StrainLevel.veryHigh => KpiStatus.critical,
    };
    return Kpi(
      title: 'Belastung',
      value: _decimal(done),
      fraction: done / strainMaximum,
      secondaryFraction: total > done ? total / strainMaximum : null,
      status: status,
      caption: total > done
          ? '+${_decimal(total - done)} geplant'
          : (measured == null ? 'von 21' : strain.source.label),
      // Noch (fast) nichts trainiert: der Wert ist neutral, die Einordnung betrifft nur das Geplante.
      valueStatus: done < 1 && total > done ? KpiStatus.unknown : null,
    );
  }
}

/// Bereiche der Seite „Heute“ zum Ein- und Ausblenden (Schlüssel `coach.todayDashboard`).
enum TodayModule implements RawEnum {
  kpis('kpis', 'Schlaf, Erholung, Belastung'),
  training('training', 'Training heute'),
  nutrition('nutrition', 'Ernährung heute'),
  ai('ai', 'KI-Empfehlungen'),
  suggestions('suggestions', 'Vorschläge zum Plan'),
  morningReport('morningReport', 'Morgenbericht (bis 12 Uhr)'),
  strainDetails('strainDetails', 'Belastung im Detail'),
  postWorkout('postWorkout', 'Nach dem Training'),
  weeklyReview('weeklyReview', 'Wochenrückblick'),
  motivation('motivation', 'Motivation und Begleiter'),
  hints('hints', 'Hinweise'),
  week('week', 'Woche und Ziele');

  const TodayModule(this.rawValue, this.label);

  @override
  final String rawValue;
  final String label;
}

/// Was auf „Heute“ zu sehen ist. Standard: das Wesentliche – Kennzahlen, Training, Empfehlungen, Vorschläge, Woche.
/// Gespeichert werden die ausgeblendeten Bereiche; neue Bereiche aus späteren Versionen erscheinen nach [standardHidden].
final class TodayDashboard {
  TodayDashboard({Set<TodayModule>? hidden}) : hidden = hidden ?? {...standardHidden};

  Set<TodayModule> hidden;

  static const standardHidden = {
    TodayModule.morningReport,
    TodayModule.strainDetails,
    TodayModule.postWorkout,
    TodayModule.motivation,
    TodayModule.hints,
  };

  bool shows(TodayModule module) => !hidden.contains(module);

  void set(TodayModule module, {required bool visible}) {
    hidden = visible ? ({...hidden}..remove(module)) : {...hidden, module};
  }

  Map<String, Object?> toJson() => {
    'hidden': [
      for (final module in TodayModule.values)
        if (hidden.contains(module)) module.rawValue,
    ],
  };

  static TodayDashboard? fromJson(Object? json) {
    final list = JsonValue(json)['hidden']?.arrayValue;
    if (list == null) return null;
    return TodayDashboard(hidden: {for (final item in list) ?enumFromRaw(TodayModule.values, item.raw)});
  }

  @override
  bool operator ==(Object other) =>
      other is TodayDashboard && other.hidden.length == hidden.length && other.hidden.containsAll(hidden);

  @override
  int get hashCode => Object.hashAllUnordered(hidden);
}

/// Hinweis „Verbinde eine Datenquelle“ auf „Heute“: nur ohne verbundene Quelle **und** ohne Tageswerte der letzten
/// sieben Tage (Werte können auch aus einer Sicherung oder von Hand stammen).
bool showsConnectSourceHint({
  required bool hasSource,
  required Iterable<CalendarDay> metricDays,
  required CalendarDay today,
}) => !hasSource && !metricDays.any((day) => !(day < today.adding(-7)));

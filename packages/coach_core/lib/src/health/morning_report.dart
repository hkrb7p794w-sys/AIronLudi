import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/fitness_form.dart';
import '../coach/recommendation.dart';
import '../coach/recovery_level.dart';
import '../coach/sleep_coach.dart';
import '../garmin/daily_metrics.dart';
import '../profile/plan_adjustments.dart';
import '../profile/user_profile.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import 'body_battery.dart';
import 'personal_norm.dart';

/// Einordnung eines Werts im Morgenbericht.
enum MorningStatus implements RawEnum {
  good,
  normal,
  attention,
  missing;

  @override
  String get rawValue => name;
}

/// Werte des Morgenberichts.
enum MorningMetric {
  sleepDuration('Schlafdauer'),
  sleepQuality('Schlafqualität'),
  sleepStages('Schlafphasen'),
  restingHeartRate('Ruhepuls'),
  hrv('HRV'),
  stress('Stress'),
  bodyBattery('Body Battery'),
  recovery('Erholung'),
  load('Trainingsbelastung');

  const MorningMetric(this.title);

  final String title;
}

/// Eine Zeile des Morgenberichts.
final class MorningItem {
  const MorningItem({required this.metric, required this.value, required this.status, required this.note});

  final MorningMetric metric;
  final String? value;
  final MorningStatus status;

  /// Einordnung in einem Satz („2 bpm über deinem üblichen Bereich“).
  final String note;

  String get id => metric.name;
  String get title => metric.title;

  @override
  String toString() => 'MorningItem($metric, $value, $status, $note)';
}

/// Geplante Einheit des Tages (aus „Jetzt dran“).
final class MorningSession {
  const MorningSession({required this.id, required this.title, required this.target, required this.demanding});

  final String id;
  final String title;
  final String target;
  final bool demanding;
}

/// Morning Report: die wichtigsten Werte der Nacht, eingeordnet gegen den eigenen Normalbereich, mit einer Empfehlung
/// nach festen Regeln (`RecoveryEvaluator` plus persönliche Abweichungen). Fehlende Werte werden genannt, nie
/// geschätzt; mit wenigen Daten bleibt der Bericht kurz und sagt das.
final class MorningReport {
  const MorningReport({
    required this.day,
    required this.dataDay,
    required this.items,
    required this.level,
    required this.headline,
    required this.findings,
    required this.recommendation,
    required this.sleepAdvice,
    required this.sessions,
    required this.missing,
  });

  final CalendarDay day;

  /// Tag der Werte; `day − 1`, wenn heute noch nichts synchronisiert ist.
  final CalendarDay? dataDay;
  final List<MorningItem> items;

  /// `null` = zu wenig Daten für eine Empfehlung.
  final RecoveryLevel? level;
  final String headline;

  /// Auffälligkeiten als kurze Sätze.
  final List<String> findings;
  final String recommendation;
  final String? sleepAdvice;
  final List<MorningSession> sessions;

  /// Werte, die heute fehlen.
  final List<String> missing;

  bool get isFromYesterday => dataDay != null && dataDay! < day;

  static MorningReport make({
    required List<DailyMetrics> days,
    required CalendarDay today,
    required SleepSettings sleep,
    FitnessGoal? goal,
    List<MorningSession> sessions = const [],
    FormPoint? form,
    List<FormPoint> formSeries = const [],
  }) {
    final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
    DailyMetrics? lastWhere(bool Function(DailyMetrics metrics) test) => sorted.reversed.where(test).firstOrNull;
    final metrics =
        lastWhere((metrics) => metrics.day == today && _hasNight(metrics)) ??
        lastWhere((metrics) => metrics.day == today.adding(-1) && _hasNight(metrics));
    final reference = metrics?.day ?? today;
    final previous = sorted.where((metrics) => metrics.day < reference).toList();
    PersonalNorm? norm(double? Function(DailyMetrics metrics) field) =>
        PersonalNorm.fromDays(previous, today: reference, field: field);

    final items = <MorningItem>[
      sleepDuration(metrics, need: sleep.targetHours, norm: norm((metrics) => metrics.sleepHours)),
      sleepQuality(metrics),
      sleepStages(metrics, deepNorm: norm((metrics) => metrics.deepSleepSeconds)),
      restingHeartRate(metrics, norm: norm((metrics) => metrics.restingHeartRate)),
      hrv(
        metrics,
        norm: norm((metrics) => metrics.hrvLastNightAverage),
        trend: hrvTrend(sorted, reference: reference),
      ),
    ];
    // Stress des Vortags: der heutige Tagesschnitt ist am Morgen noch nicht aussagekräftig.
    final yesterday = reference.adding(-1);
    final stressDay = lastWhere((metrics) => metrics.day == yesterday);
    items
      ..add(
        stress(
          stressDay?.stressAverage,
          sleepStress: metrics?.sleepStress,
          norm: PersonalNorm.fromDays(
            sorted.where((metrics) => metrics.day < yesterday).toList(),
            today: yesterday,
            field: (metrics) => metrics.stressAverage,
          ),
        ),
      )
      ..add(
        bodyBattery(
          metrics == null ? null : BodyBatteryAnalysis.wakeValue(metrics),
          norm: norm(BodyBatteryAnalysis.wakeValue),
        ),
      );
    final restingAverage = RecoveryEvaluator.average(
      (metrics) => metrics.restingHeartRate,
      sorted,
      from: 1,
      to: 7,
      today: reference,
    );
    final evaluated = metrics == null
        ? null
        : RecoveryEvaluator.evaluate(metrics, restingHeartRate7DayAverage: restingAverage);
    items
      ..add(recovery(metrics, evaluated: evaluated))
      ..add(load(metrics, form: form));

    // Dieselbe Ampel wie überall. Auffälligkeiten stehen als Hinweise da und ändern die Stufe nicht.
    final level = RecoveryEvaluator.today(days: sorted, form: formSeries, today: today).level;
    final report = SleepCoach.report(days: sorted, settings: sleep, goal: goal, today: today);
    final sleepAdvice = report == null
        ? null
        : 'Heute Abend gegen ${SleepCoach.clock(report.bedtimeMinutes)} Uhr ins Bett – '
              '${GermanFormat.decimal(report.tonightMinutes / 60)} h Schlafbedarf bis '
              '${SleepCoach.clock(sleep.wakeMinutes)} Uhr.';
    return MorningReport(
      day: today,
      dataDay: metrics?.day,
      items: items,
      level: level,
      headline: headlineText(level),
      findings: [
        for (final item in items)
          if (item.status == MorningStatus.attention) item.note,
      ],
      recommendation: recommendationText(level, sessions: sessions),
      sleepAdvice: sleepAdvice,
      sessions: sessions,
      missing: [
        for (final item in items)
          if (item.status == MorningStatus.missing) item.title,
      ],
    );
  }

  static bool _hasNight(DailyMetrics metrics) =>
      metrics.sleepSeconds != null ||
      metrics.restingHeartRate != null ||
      metrics.hrvLastNightAverage != null ||
      metrics.hrvStatus != null ||
      metrics.bodyBatteryAtWake != null ||
      metrics.bodyBatteryCurve != null;

  // Einordnung

  static MorningItem _item(MorningMetric metric, String? value, MorningStatus status, String note) =>
      MorningItem(metric: metric, value: value, status: status, note: note);

  static MorningItem sleepDuration(DailyMetrics? metrics, {required double need, required PersonalNorm? norm}) {
    final seconds = metrics?.sleepSeconds;
    final shown = metrics?.sleepHours;
    if (seconds == null || shown == null) {
      return _item(MorningMetric.sleepDuration, null, MorningStatus.missing, 'Keine Schlafdaten');
    }
    // Vergleiche mit dem genauen Wert, gerundet wird nur die Anzeige.
    final hours = seconds / 3600;
    final value = hoursText(shown);
    final needText = GermanFormat.decimal(need);
    if (hours < need - 0.5) {
      final short = ((need - hours) * 60).round();
      return _item(
        MorningMetric.sleepDuration,
        value,
        MorningStatus.attention,
        'Schlaf war $short min kürzer als dein Bedarf ($needText h).',
      );
    }
    if (hours >= need) {
      return _item(MorningMetric.sleepDuration, value, MorningStatus.good, 'Bedarf von $needText h erreicht.');
    }
    final usual = norm != null && norm.position(hours) == NormPosition.below ? ' und kürzer als sonst' : '';
    return _item(MorningMetric.sleepDuration, value, MorningStatus.normal, 'Knapp unter deinem Bedarf$usual.');
  }

  /// Garmin-Schlaf-Score: 90+ ausgezeichnet, 80–89 gut, 60–79 ordentlich, unter 60 schwach.
  static MorningItem sleepQuality(DailyMetrics? metrics) {
    final score = metrics?.sleepScore;
    if (score == null) return _item(MorningMetric.sleepQuality, null, MorningStatus.missing, 'Kein Schlaf-Score');
    final value = '${score.toInt()}';
    if (score >= 80) return _item(MorningMetric.sleepQuality, value, MorningStatus.good, 'Gute Schlafqualität.');
    if (score >= 60) {
      return _item(MorningMetric.sleepQuality, value, MorningStatus.normal, 'Ordentliche Schlafqualität.');
    }
    return _item(MorningMetric.sleepQuality, value, MorningStatus.attention, 'Schlafqualität war schwach.');
  }

  static MorningItem sleepStages(DailyMetrics? metrics, {required PersonalNorm? deepNorm}) {
    final deep = metrics?.deepSleepSeconds;
    final rem = metrics?.remSleepSeconds;
    if (deep == null || rem == null) {
      return _item(MorningMetric.sleepStages, null, MorningStatus.missing, 'Keine Schlafphasen');
    }
    final value = 'Tief ${durationText(deep)} · REM ${durationText(rem)}';
    if (deepNorm != null && deepNorm.position(deep) == NormPosition.below) {
      return _item(MorningMetric.sleepStages, value, MorningStatus.attention, 'Weniger Tiefschlaf als sonst.');
    }
    return _item(MorningMetric.sleepStages, value, MorningStatus.normal, 'Phasen im üblichen Rahmen.');
  }

  static MorningItem restingHeartRate(DailyMetrics? metrics, {required PersonalNorm? norm}) {
    final value = metrics?.restingHeartRate;
    if (value == null) return _item(MorningMetric.restingHeartRate, null, MorningStatus.missing, 'Kein Ruhepuls');
    final text = '${value.toInt()} bpm';
    if (norm == null) {
      return _item(
        MorningMetric.restingHeartRate,
        text,
        MorningStatus.normal,
        'Eigener Bereich ab ${PersonalNorm.minimumDays} Tagen mit Werten.',
      );
    }
    return switch (norm.position(value)) {
      NormPosition.above => _item(
        MorningMetric.restingHeartRate,
        text,
        MorningStatus.attention,
        'Ruhepuls ${(value - norm.high).ceil()} bpm über deinem üblichen Bereich.',
      ),
      NormPosition.below => _item(
        MorningMetric.restingHeartRate,
        text,
        MorningStatus.good,
        'Ruhepuls niedriger als sonst.',
      ),
      NormPosition.within => _item(MorningMetric.restingHeartRate, text, MorningStatus.normal, 'Im üblichen Bereich.'),
    };
  }

  /// 7-Tage-Schnitt des logarithmierten HRV-Werts gegen die Basis der Tage 7 bis 60, Grenze ± 0,5 SD (Plews 2013,
  /// Javaloyes 2019). `null`, solange die Basis fehlt. Apple liefert SDNN statt rMSSD; die Methode bleibt dieselbe.
  static NormPosition? hrvTrend(List<DailyMetrics> days, {required CalendarDay reference}) {
    List<double> values(int from, int to) => [
      for (final metrics in days)
        if (metrics.day.daysUntil(reference) case final offset when offset >= from && offset <= to)
          if (metrics.hrvLastNightAverage case final value? when value > 0) math.log(value),
    ];
    final recent = values(0, 6);
    final baseline = values(7, 60);
    if (recent.length < 4 || baseline.length < 14) return null;
    final mean = baseline.fold(0.0, (sum, value) => sum + value) / baseline.length;
    final deviation = math.sqrt(
      baseline.fold(0.0, (sum, value) => sum + (value - mean) * (value - mean)) / baseline.length,
    );
    final week = recent.fold(0.0, (sum, value) => sum + value) / recent.length;
    if (week < mean - 0.5 * deviation) return NormPosition.below;
    return week > mean + 0.5 * deviation ? NormPosition.above : NormPosition.within;
  }

  /// Garmins HRV-Status (7-Tage-Schnitt gegen Baseline) zuerst, sonst der eigene Wochenschnitt, sonst die
  /// Einzelnacht.
  static MorningItem hrv(DailyMetrics? metrics, {required PersonalNorm? norm, NormPosition? trend}) {
    final night = metrics?.hrvLastNightAverage;
    final value = night == null ? null : '${night.toInt()} ms';
    const below = 'HRV liegt unter deinem Normalbereich.';
    switch (metrics?.hrvStatus?.toUpperCase()) {
      case 'LOW' || 'POOR':
        return _item(MorningMetric.hrv, value, MorningStatus.attention, below);
      case 'UNBALANCED':
        final (weekly, low) = (metrics?.hrvWeeklyAverage, metrics?.hrvBaselineLow);
        if (weekly != null && low != null && weekly < low) {
          return _item(MorningMetric.hrv, value, MorningStatus.attention, below);
        }
        return _item(MorningMetric.hrv, value, MorningStatus.normal, 'HRV unausgeglichen, aber nicht zu niedrig.');
      case 'BALANCED':
        final low = metrics?.hrvBaselineLow;
        if (night != null && low != null && night < low) {
          return _item(
            MorningMetric.hrv,
            value,
            MorningStatus.normal,
            'Letzte Nacht niedrig, Wochenschnitt ausgeglichen.',
          );
        }
        return _item(MorningMetric.hrv, value, MorningStatus.good, 'HRV ausgeglichen.');
    }
    if (night == null) return _item(MorningMetric.hrv, null, MorningStatus.missing, 'Keine HRV');
    if (trend != null) {
      return switch (trend) {
        NormPosition.below => _item(
          MorningMetric.hrv,
          value,
          MorningStatus.attention,
          'HRV-Wochenschnitt unter deinem Normalbereich.',
        ),
        NormPosition.within => _item(
          MorningMetric.hrv,
          value,
          MorningStatus.normal,
          'HRV-Wochenschnitt im üblichen Bereich.',
        ),
        NormPosition.above => _item(MorningMetric.hrv, value, MorningStatus.good, 'HRV-Wochenschnitt höher als sonst.'),
      };
    }
    if (norm == null) {
      return _item(
        MorningMetric.hrv,
        value,
        MorningStatus.normal,
        'Eigener Bereich ab ${PersonalNorm.minimumDays} Nächten.',
      );
    }
    return switch (norm.position(night)) {
      NormPosition.below => _item(MorningMetric.hrv, value, MorningStatus.attention, below),
      NormPosition.within => _item(MorningMetric.hrv, value, MorningStatus.normal, 'HRV im üblichen Bereich.'),
      NormPosition.above => _item(MorningMetric.hrv, value, MorningStatus.good, 'HRV höher als sonst.'),
    };
  }

  static MorningItem stress(double? average, {required double? sleepStress, required PersonalNorm? norm}) {
    if (average == null) {
      if (sleepStress != null) {
        return _item(MorningMetric.stress, 'Nacht ${sleepStress.toInt()}', MorningStatus.normal, 'Stress im Schlaf.');
      }
      return _item(MorningMetric.stress, null, MorningStatus.missing, 'Kein Stresswert');
    }
    final value = 'Ø ${average.toInt()}';
    if (norm != null && norm.position(average) == NormPosition.above) {
      return _item(MorningMetric.stress, value, MorningStatus.attention, 'Stress gestern höher als sonst.');
    }
    // Garmin: 0–25 Ruhe, 26–50 niedrig, 51–75 mittel, 76–100 hoch.
    if (average > 50) {
      return _item(
        MorningMetric.stress,
        value,
        MorningStatus.attention,
        'Stress gestern im mittleren Bereich oder höher.',
      );
    }
    return _item(MorningMetric.stress, value, MorningStatus.normal, 'Stress gestern im üblichen Rahmen.');
  }

  static MorningItem bodyBattery(double? wake, {required PersonalNorm? norm}) {
    if (wake == null) {
      return _item(MorningMetric.bodyBattery, null, MorningStatus.missing, 'Keine Body Battery (nur Garmin)');
    }
    final value = '${wake.toInt()}';
    if (norm != null) {
      return switch (norm.position(wake)) {
        NormPosition.below => _item(
          MorningMetric.bodyBattery,
          value,
          MorningStatus.attention,
          'Body Battery ist vergleichsweise niedrig.',
        ),
        NormPosition.above => _item(
          MorningMetric.bodyBattery,
          value,
          MorningStatus.good,
          'Body Battery höher als sonst.',
        ),
        NormPosition.within => _item(
          MorningMetric.bodyBattery,
          value,
          MorningStatus.normal,
          'Body Battery im üblichen Bereich.',
        ),
      };
    }
    if (wake < 26) return _item(MorningMetric.bodyBattery, value, MorningStatus.attention, 'Body Battery ist niedrig.');
    return _item(
      MorningMetric.bodyBattery,
      value,
      wake >= 76 ? MorningStatus.good : MorningStatus.normal,
      'Body Battery ${BodyBatteryAnalysis.band(wake)}.',
    );
  }

  static MorningItem recovery(DailyMetrics? metrics, {required Recommendation? evaluated}) {
    final parts = <String>[
      if (metrics?.trainingReadiness case final readiness?) 'Readiness ${readiness.toInt()}',
      if (metrics?.recoveryHours case final hours?) hours == 0 ? 'erholt' : 'noch ${hours.round()} h',
    ];
    if (evaluated == null) {
      return _item(MorningMetric.recovery, parts.firstOrNull, MorningStatus.missing, 'Keine Erholungswerte');
    }
    final status = evaluated.level == RecoveryLevel.normal ? MorningStatus.good : MorningStatus.attention;
    return _item(
      MorningMetric.recovery,
      parts.isEmpty ? evaluated.label : parts.join(' · '),
      status,
      evaluated.level == RecoveryLevel.normal
          ? 'Erholungswerte unauffällig.'
          : 'Erholung: ${evaluated.label.toLowerCase()}.',
    );
  }

  /// Akute zu chronischer Last der Uhr (0,8–1,3 üblich, über 1,5 deutlich mehr als gewohnt; Gabbett 2016), sonst die
  /// Form aus den eigenen Aktivitäten.
  static MorningItem load(DailyMetrics? metrics, {required FormPoint? form}) {
    final (acute, chronic) = (metrics?.acuteLoad, metrics?.chronicLoad);
    if (acute != null && chronic != null && chronic > 0) {
      final ratio = acute / chronic;
      final value = '${acute.toInt()} / ${chronic.toInt()}';
      if (ratio > 1.5) {
        return _item(MorningMetric.load, value, MorningStatus.attention, 'Belastung deutlich über deinem Gewohnten.');
      }
      if (ratio < 0.8) return _item(MorningMetric.load, value, MorningStatus.normal, 'Weniger Belastung als gewohnt.');
      return _item(MorningMetric.load, value, MorningStatus.normal, 'Belastung im gewohnten Rahmen.');
    }
    if (form?.formPercent case final percent?) {
      final zone = FormZone.of(percent);
      return _item(
        MorningMetric.load,
        zone.label,
        zone == FormZone.high ? MorningStatus.attention : MorningStatus.normal,
        zone == FormZone.high ? 'Sehr hohe Belastung in den letzten Tagen.' : zone.explanation,
      );
    }
    return _item(MorningMetric.load, null, MorningStatus.missing, 'Keine Belastungswerte');
  }

  // Texte

  static String headlineText(RecoveryLevel? level) => switch (level) {
    RecoveryLevel.normal => 'Bereit für dein Training',
    RecoveryLevel.locker => 'Heute eher locker',
    RecoveryLevel.pause => 'Heute Erholung',
    null => 'Zu wenig Daten für eine Einschätzung',
  };

  static String recommendationText(RecoveryLevel? level, {required List<MorningSession> sessions}) {
    if (level == null) return 'Es fehlen zu viele Werte. Richte dich heute nach deinem Gefühl.';
    var text = switch (level) {
      RecoveryLevel.normal => 'Empfehlung: Training wie geplant.',
      RecoveryLevel.locker => 'Empfehlung: Heute eher eine lockere Trainingseinheit.',
      RecoveryLevel.pause => 'Empfehlung: Ruhetag oder höchstens 20–30 min sehr locker.',
    };
    final hard = sessions.where((session) => session.demanding).firstOrNull;
    if (level != RecoveryLevel.normal && hard != null) {
      text += ' „${hard.title}“ lieber kürzer oder locker.';
    } else if (level == RecoveryLevel.normal && sessions.isEmpty) {
      text = 'Kein Training geplant – die Werte erlauben aber Belastung.';
    }
    return text;
  }

  static String hoursText(double hours) => durationText(hours * 3600);

  static String durationText(double seconds) {
    final minutes = (seconds / 60).round();
    return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
  }
}

/// Mitteilung zum Morgenbericht (Erweiterung von `ReminderPlanner` in Swift).
abstract final class MorningReportReminder {
  static const morningReportHour = 8;
  static const morningReportFallback = 'Schlaf, Erholung und was heute ansteht – tippen zum Öffnen.';

  /// Mitteilung um 8 Uhr zum Morning Report (Standard an, abwählbar). Lokale Mitteilungen brauchen ihren Text beim
  /// Planen: Liegen die Werte der Nacht schon vor ([summary]), steht heute die Einordnung darin, sonst – und für die
  /// folgenden Tage – ein allgemeiner Satz. Öffnet die App vorher oder läuft die Hintergrundaktualisierung, wird der
  /// Text ersetzt.
  static List<ScheduledNote> morningReport({
    required CalendarDay today,
    required int minutesNow,
    String? summary,
    int hour = morningReportHour,
    int days = 5,
  }) => [
    for (var offset = 0; offset < math.max(days, 1); offset++)
      if (!(offset == 0 && minutesNow >= hour * 60))
        ScheduledNote(
          kind: ScheduledNoteKind.morningReport,
          day: today.adding(offset),
          hour: hour,
          minute: 0,
          title: 'Morning Report',
          body: switch (offset == 0 ? summary?.trim() : null) {
            final text? when text.isNotEmpty => text,
            _ => morningReportFallback,
          },
        ),
  ];

  /// Text für heute: nur mit Werten der letzten Nacht, nicht mit denen von gestern.
  static String? morningSummary(MorningReport report) =>
      report.dataDay == report.day && report.level != null ? report.headline : null;
}

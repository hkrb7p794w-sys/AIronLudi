import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../fit/fit_decoder.dart';
import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import '../util/rounding.dart';
import 'activity_details.dart';
import 'aerobic_decoupling.dart';

/// Abschnitt fester Länge (Laufen/Gehen 1 km, Rad 5 km, Schwimmen 100 m).
final class ReportSplit {
  const ReportSplit({
    required this.index,
    required this.meters,
    required this.seconds,
    this.averageHeartRate,
    this.ascentMeters,
  });

  final int index;
  final double meters;
  final double seconds;
  final double? averageHeartRate;
  final double? ascentMeters;

  int get id => index;

  /// m/s
  double get speed => seconds > 0 ? meters / seconds : 0;

  Map<String, Object?> toJson() => {
    'index': index,
    'meters': meters,
    'seconds': seconds,
    'averageHeartRate': ?averageHeartRate,
    'ascentMeters': ?ascentMeters,
  };

  static ReportSplit? fromJson(Object? json) {
    if (json is! Map || json['index'] is! int) return null;
    final (meters, seconds) = (jsonDouble(json['meters']), jsonDouble(json['seconds']));
    if (meters == null || seconds == null) return null;
    return ReportSplit(
      index: json['index'] as int,
      meters: meters,
      seconds: seconds,
      averageHeartRate: jsonDouble(json['averageHeartRate']),
      ascentMeters: jsonDouble(json['ascentMeters']),
    );
  }

  @override
  String toString() => 'ReportSplit($index, $meters m, $seconds s)';
}

/// Vergleich erste gegen zweite Hälfte (nach Bewegungszeit).
final class ReportHalves {
  const ReportHalves({this.speedChangePercent, this.heartRateChangePercent});

  /// Tempoänderung der zweiten Hälfte in Prozent (+ = schneller).
  final double? speedChangePercent;

  /// Pulsänderung der zweiten Hälfte in Prozent (+ = höher).
  final double? heartRateChangePercent;

  Map<String, Object?> toJson() => {
    'speedChangePercent': ?speedChangePercent,
    'heartRateChangePercent': ?heartRateChangePercent,
  };

  static ReportHalves? fromJson(Object? json) => json is Map
      ? ReportHalves(
          speedChangePercent: jsonDouble(json['speedChangePercent']),
          heartRateChangePercent: jsonDouble(json['heartRateChangePercent']),
        )
      : null;
}

/// JSON einer Runde wie das synthetisierte `Codable` von `FitLap` in Swift (Intensität als Zahl).
Map<String, Object?> fitLapToJson(FitLap lap) => {
  'startTime': ?lap.startTime,
  'elapsedSeconds': ?lap.elapsedSeconds,
  'timerSeconds': ?lap.timerSeconds,
  'distanceMeters': ?lap.distanceMeters,
  'averageHeartRate': ?lap.averageHeartRate,
  'maxHeartRate': ?lap.maxHeartRate,
  'intensity': ?lap.intensity?.index,
  'averageSpeed': ?lap.averageSpeed,
  'maxSpeed': ?lap.maxSpeed,
  'ascentMeters': ?lap.ascentMeters,
  'descentMeters': ?lap.descentMeters,
  'averageCadence': ?lap.averageCadence,
  'averagePower': ?lap.averagePower,
  'maxPower': ?lap.maxPower,
  'calories': ?lap.calories,
};

FitLap? fitLapFromJson(Object? json) {
  if (json is! Map) return null;
  final rawIntensity = json['intensity'];
  FitLapIntensity? intensity;
  if (rawIntensity is int && rawIntensity >= 0 && rawIntensity < FitLapIntensity.values.length) {
    intensity = FitLapIntensity.values[rawIntensity];
  } else if (rawIntensity != null) {
    return null;
  }
  return FitLap(
      timerSeconds: jsonDouble(json['timerSeconds']),
      distanceMeters: jsonDouble(json['distanceMeters']),
      averageHeartRate: jsonDouble(json['averageHeartRate']),
      maxHeartRate: jsonDouble(json['maxHeartRate']),
      intensity: intensity,
    )
    ..startTime = jsonDouble(json['startTime'])
    ..elapsedSeconds = jsonDouble(json['elapsedSeconds'])
    ..averageSpeed = jsonDouble(json['averageSpeed'])
    ..maxSpeed = jsonDouble(json['maxSpeed'])
    ..ascentMeters = jsonDouble(json['ascentMeters'])
    ..descentMeters = jsonDouble(json['descentMeters'])
    ..averageCadence = jsonDouble(json['averageCadence'])
    ..averagePower = jsonDouble(json['averagePower'])
    ..maxPower = jsonDouble(json['maxPower'])
    ..calories = jsonDouble(json['calories']);
}

DetailSample? _sampleFromJson(Object? json) {
  if (json is! Map) return null;
  final x = jsonDouble(json['x']);
  if (x == null) return null;
  return DetailSample(
    x: x,
    heartRate: jsonDouble(json['heartRate']),
    pace: jsonDouble(json['pace']),
    altitude: jsonDouble(json['altitude']),
    cadence: jsonDouble(json['cadence']),
    power: jsonDouble(json['power']),
  );
}

/// Vollständige Auswertung einer aufgezeichneten Aktivität aus der Datei der Uhr (FIT): Runden, Splits, Verlauf für
/// die Diagramme und Kennzahlen zu Tempo-Einteilung, Puls-Drift, Intervallen und Standzeit. Wird beim Abruf für jede
/// Aktivität erzeugt und gespeichert, damit Detailansicht, Coach und KI-Export sie ohne erneuten Abruf nutzen.
final class ActivityReport {
  const ActivityReport({
    required this.id,
    required this.day,
    required this.name,
    required this.sport,
    required this.version,
    required this.laps,
    required this.splits,
    required this.splitMeters,
    required this.samples,
    required this.byDistance,
    required this.halves,
    required this.pausedSeconds,
    required this.movingSeconds,
    required this.highZonePercent,
    required this.averageCadence,
  });

  static const currentVersion = 1;
  static const maxLaps = 80;

  final int id;
  final CalendarDay day;
  final String? name;
  final ActivitySport sport;
  final int version;
  final List<FitLap> laps;
  final List<ReportSplit> splits;
  final double splitMeters;
  final List<DetailSample> samples;
  final bool byDistance;
  final ReportHalves halves;

  /// Zeit mit angehaltener Uhr bzw. im Stand (s).
  final double pausedSeconds;
  final double movingSeconds;

  /// Anteil der Zeit in Zone 4–5 in Prozent (aus der Aktivität).
  final double? highZonePercent;

  /// Schritte pro Minute (Laufen) bzw. Umdrehungen pro Minute.
  final double? averageCadence;

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day.toJson(),
    'name': ?name,
    'sport': sport.rawValue,
    'version': version,
    'laps': [for (final lap in laps) fitLapToJson(lap)],
    'splits': [for (final split in splits) split.toJson()],
    'splitMeters': splitMeters,
    'samples': [for (final sample in samples) sample.toJson()],
    'byDistance': byDistance,
    'halves': halves.toJson(),
    'pausedSeconds': pausedSeconds,
    'movingSeconds': movingSeconds,
    'highZonePercent': ?highZonePercent,
    'averageCadence': ?averageCadence,
  };

  /// Wie das synthetisierte `Decodable`: Pflichtfelder müssen lesbar sein.
  static ActivityReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final rawDay = json['day'];
    final sport = enumFromRaw(ActivitySport.values, json['sport']);
    final version = json['version'];
    final laps = listStrict(json['laps'], fitLapFromJson);
    final splits = listStrict(json['splits'], ReportSplit.fromJson);
    final samples = listStrict(json['samples'], _sampleFromJson);
    final halves = ReportHalves.fromJson(json['halves']);
    final (splitMeters, paused, moving) = (
      jsonDouble(json['splitMeters']),
      jsonDouble(json['pausedSeconds']),
      jsonDouble(json['movingSeconds']),
    );
    final byDistance = json['byDistance'];
    if (id is! int ||
        rawDay is! Map<String, Object?> ||
        sport == null ||
        version is! int ||
        laps == null ||
        splits == null ||
        samples == null ||
        halves == null ||
        splitMeters == null ||
        paused == null ||
        moving == null ||
        byDistance is! bool) {
      return null;
    }
    final CalendarDay day;
    try {
      day = CalendarDay.fromJson(rawDay);
    } on Object {
      return null;
    }
    final name = json['name'];
    return ActivityReport(
      id: id,
      day: day,
      name: name is String ? name : null,
      sport: sport,
      version: version,
      laps: laps,
      splits: splits,
      splitMeters: splitMeters,
      samples: samples,
      byDistance: byDistance,
      halves: halves,
      pausedSeconds: paused,
      movingSeconds: moving,
      highZonePercent: jsonDouble(json['highZonePercent']),
      averageCadence: jsonDouble(json['averageCadence']),
    );
  }
}

typedef _Step = ({FitRecord record, double seconds, bool moving});

abstract final class ActivityReportBuilder {
  /// Unter dieser Geschwindigkeit gilt ein Messpunkt als Stand (m/s).
  static const movingSpeed = 0.5;

  static double splitLength(ActivitySport sport) => switch (sport) {
    ActivitySport.bike => 5000,
    ActivitySport.swim => 100,
    _ => 1000,
  };

  static ActivityReport build(GarminActivity activity, FitActivity fit) {
    final sport = activity.sport;
    final records = fit.records;
    final length = splitLength(sport);
    final moving = movingSeconds(records);
    final elapsed = records.isEmpty ? 0.0 : records.last.timestamp - records.first.timestamp;
    final total = activity.elapsedSeconds ?? activity.durationSeconds ?? elapsed;
    final cadenceMean = mean([
      for (final record in records)
        if (record.cadence case final cadence? when cadence > 0) cadence,
    ]);
    final cadence = cadenceMean == null ? null : (sport == ActivitySport.run ? cadenceMean * 2 : cadenceMean);
    final share = AerobicDecoupling.highZoneShare(activity);
    return ActivityReport(
      id: activity.id,
      day: activity.day ?? const CalendarDay(2000, 1, 1),
      name: activity.name,
      sport: sport,
      version: ActivityReport.currentVersion,
      laps: fit.laps.take(ActivityReport.maxLaps).toList(),
      splits: splits(records, length),
      splitMeters: length,
      samples: ActivityDetails.samples(fit, sport, maxPoints: 150),
      byDistance: records.any((record) => (record.distance ?? 0) > 0),
      halves: halves(records),
      pausedSeconds: math.max(0, math.max(total, elapsed) - moving),
      movingSeconds: moving,
      highZonePercent: share == null ? null : round1HalfEven(share * 100),
      averageCadence: cadence == null ? null : (cadence * 10).roundToDouble() / 10,
    );
  }

  static double? mean(List<double> values) =>
      values.isEmpty ? null : values.fold(0.0, (sum, value) => sum + value) / values.length;

  /// Zeitabstand zum Vorgänger; Lücken über 10 s (angehaltene Uhr) zählen nicht als Bewegung.
  static List<_Step> _steps(List<FitRecord> records) {
    final result = <_Step>[];
    for (var index = 1; index < records.length; index++) {
      final delta = records[index].timestamp - records[index - 1].timestamp;
      if (delta <= 0) continue;
      final speed = records[index].speed;
      final moving = delta <= 10 && (speed == null || speed >= movingSpeed);
      result.add((record: records[index], seconds: math.min(delta, 10), moving: moving));
    }
    return result;
  }

  static double movingSeconds(List<FitRecord> records) =>
      _steps(records).where((step) => step.moving).fold(0.0, (sum, step) => sum + step.seconds);

  /// Abschnitte fester Länge aus der Distanzspur; ein Rest unter 40 % der Länge entfällt.
  static List<ReportSplit> splits(List<FitRecord> records, double length) {
    final result = <ReportSplit>[];
    var startDistance = 0.0;
    var seconds = 0.0;
    var heartRates = <double>[];
    var ascent = 0.0;
    var hasAltitude = false;
    double? lastAltitude;
    void close(double meters) => result.add(
      ReportSplit(
        index: result.length + 1,
        meters: meters,
        seconds: seconds,
        averageHeartRate: mean(heartRates),
        ascentMeters: hasAltitude ? ascent.roundToDouble() : null,
      ),
    );
    for (final step in _steps(records)) {
      final distance = step.record.distance;
      if (distance == null) continue;
      if (step.moving) seconds += step.seconds;
      if (step.record.heartRate case final heartRate?) heartRates.add(heartRate);
      if (step.record.altitude case final altitude?) {
        hasAltitude = true;
        if (lastAltitude != null && altitude > lastAltitude) ascent += altitude - lastAltitude;
        lastAltitude = altitude;
      }
      if (distance - startDistance >= length) {
        close(length);
        startDistance += length;
        seconds = 0;
        heartRates = [];
        ascent = 0;
      }
    }
    final rest = (records.isEmpty ? 0.0 : (records.last.distance ?? 0)) - startDistance;
    if (rest >= length * 0.4 && seconds > 0) close(rest);
    return result;
  }

  /// Erste gegen zweite Hälfte der Bewegungszeit: mittleres Tempo und mittlerer Puls.
  static ReportHalves halves(List<FitRecord> records) {
    final moving = _steps(records).where((step) => step.moving).toList();
    final total = moving.fold(0.0, (sum, step) => sum + step.seconds);
    if (total < 600) return const ReportHalves();
    final (firstSpeed, firstHeart, secondSpeed, secondHeart) = (<double>[], <double>[], <double>[], <double>[]);
    var passed = 0.0;
    for (final step in moving) {
      passed += step.seconds;
      final first = passed <= total / 2;
      if (step.record.speed case final speed? when speed > 0) (first ? firstSpeed : secondSpeed).add(speed);
      if (step.record.heartRate case final heartRate?) (first ? firstHeart : secondHeart).add(heartRate);
    }
    double? change(List<double> a, List<double> b) {
      final (early, late) = (mean(a), mean(b));
      if (a.length < 60 || b.length < 60 || early == null || late == null || early <= 0) return null;
      return round1HalfEven((late / early - 1) * 100);
    }

    return ReportHalves(
      speedChangePercent: change(firstSpeed, secondSpeed),
      heartRateChangePercent: change(firstHeart, secondHeart),
    );
  }
}

/// Ton einer Aussage.
enum FindingTone { good, neutral, attention }

/// Eine Aussage zu einer Aktivität.
final class ActivityFinding {
  const ActivityFinding({required this.id, required this.text, required this.tone, this.hasRawHeartRate = false});

  final String id;
  final String text;
  final FindingTone tone;

  /// Enthält Pulswerte in Schlägen (im Datenschutzmodus „reduziert“ nicht an die KI).
  final bool hasRawHeartRate;

  @override
  String toString() => 'ActivityFinding($id, $tone, $text)';
}

/// Aussagen zu einer Aktivität in klaren Sätzen. Regeln entscheiden; die KI bekommt nur diese Sätze.
abstract final class ActivityFindings {
  /// Schwellen: Tempo ab ±2 % nennenswert, ab −5 % deutlich; Puls-Drift ab 5 % bei gleichmäßigem Tempo (übliche
  /// Grenze der aeroben Entkopplung, vgl. `AerobicDecoupling`).
  static List<ActivityFinding> findings(ActivityReport report) {
    final result = <ActivityFinding>[];
    final sport = report.sport;
    final intervals = report.laps.where((lap) => lap.isWork).toList();
    final structured = intervals.length >= 3 && report.laps.any((lap) => !lap.isWork && lap.intensity != null);

    final change = report.halves.speedChangePercent;
    if (structured) {
      result.addAll(intervalFindings(intervals, sport));
    } else if (change != null && sport != ActivitySport.strength && sport != ActivitySport.other) {
      if (change >= 2) {
        result.add(
          ActivityFinding(
            id: 'pacing',
            text: 'Zweite Hälfte ${percent(change)} schneller als die erste – gut eingeteilt.',
            tone: FindingTone.good,
          ),
        );
      } else if (change <= -5) {
        result.add(
          ActivityFinding(
            id: 'pacing',
            text: 'Zweite Hälfte ${percent(-change)} langsamer als die erste – vermutlich zu schnell begonnen.',
            tone: FindingTone.attention,
          ),
        );
      } else {
        result.add(
          const ActivityFinding(
            id: 'pacing',
            text: 'Tempo über die ganze Einheit gleichmäßig.',
            tone: FindingTone.good,
          ),
        );
      }
      final drift = report.halves.heartRateChangePercent;
      if (change.abs() < 3 && drift != null) {
        if (drift >= 5) {
          result.add(
            ActivityFinding(
              id: 'drift',
              text:
                  'Puls stieg bei gleichem Tempo um ${percent(drift)} – Zeichen für Ermüdung, Wärme oder zu wenig '
                  'Trinken.',
              tone: FindingTone.attention,
            ),
          );
        } else if (drift > -5) {
          result.add(
            const ActivityFinding(id: 'drift', text: 'Puls blieb bei gleichem Tempo stabil.', tone: FindingTone.good),
          );
        }
      }
    }

    final full = report.splits
        .where((split) => split.meters >= report.splitMeters * 0.99 && split.seconds > 0)
        .toList();
    if (!structured && full.length >= 3) {
      // Wie `max(by:)`/`min(by:)` in Swift: bei Gleichstand der erste Treffer.
      var fastest = full.first;
      var slowest = full.first;
      for (final split in full.skip(1)) {
        if (fastest.speed < split.speed) fastest = split;
        if (split.speed < slowest.speed) slowest = split;
      }
      final unit = splitName(report.splitMeters);
      result.add(
        ActivityFinding(
          id: 'splits',
          text:
              'Schnellster $unit: Nr. ${fastest.index} (${ActivityDetails.speed(fastest.speed, sport)}), '
              'langsamster: Nr. ${slowest.index} (${ActivityDetails.speed(slowest.speed, sport)}).',
          tone: FindingTone.neutral,
        ),
      );
    }

    final total = report.movingSeconds + report.pausedSeconds;
    if (total > 0 && report.pausedSeconds >= 120 && report.pausedSeconds / total >= 0.1) {
      result.add(
        ActivityFinding(
          id: 'pause',
          text:
              '${(report.pausedSeconds / 60).round()} min Standzeit '
              '(${(report.pausedSeconds / total * 100).round()} % der Gesamtzeit).',
          tone: FindingTone.neutral,
        ),
      );
    }
    if (report.highZonePercent case final high? when high >= 1) {
      result.add(
        ActivityFinding(
          id: 'zones',
          text: '${GermanFormat.decimal(high)} % der Zeit in Zone 4–5.',
          tone: high >= 40 ? FindingTone.attention : FindingTone.neutral,
        ),
      );
    }
    return result;
  }

  static List<ActivityFinding> intervalFindings(List<FitLap> intervals, ActivitySport sport) {
    final speeds = <double>[
      for (final lap in intervals)
        if (lap.averageSpeed case final speed? when speed > 0)
          speed
        else if ((lap.distanceMeters, lap.timerSeconds) case (final meters?, final seconds?)
            when seconds > 0 && meters > 0)
          meters / seconds,
    ];
    final average = ActivityReportBuilder.mean(speeds);
    if (speeds.length < 3 || average == null) return [];
    final result = [
      ActivityFinding(
        id: 'intervals',
        text: '${speeds.length} Intervalle, im Schnitt ${ActivityDetails.speed(average, sport)}.',
        tone: FindingTone.neutral,
      ),
    ];
    final change = (speeds.last / speeds.first - 1) * 100;
    if (change <= -4) {
      result.add(
        ActivityFinding(
          id: 'fade',
          text: 'Letztes Intervall ${percent(-change)} langsamer als das erste – das Tempo war am Anfang zu hoch.',
          tone: FindingTone.attention,
        ),
      );
    } else {
      result.add(
        const ActivityFinding(id: 'fade', text: 'Tempo bis zum letzten Intervall gehalten.', tone: FindingTone.good),
      );
    }
    final heartRates = intervals.map((lap) => lap.averageHeartRate).nonNulls.toList();
    if (heartRates.length >= 3) {
      result.add(
        ActivityFinding(
          id: 'intervalHeartRate',
          text: 'Höchster Intervall-Schnitt: ${heartRates.reduce(math.max).round()} Schläge pro Minute.',
          tone: FindingTone.neutral,
          hasRawHeartRate: true,
        ),
      );
    }
    return result;
  }

  static String percent(double value) => '${GermanFormat.decimal(value)} %';

  /// Überschrift der Split-Liste.
  static String splitTitle(double meters) => switch (meters) {
    100 => '100-m-Abschnitte',
    5000 => '5-km-Abschnitte',
    _ => 'Kilometer',
  };

  static String splitName(double meters) => switch (meters) {
    100 => '100-m-Abschnitt',
    5000 => '5-km-Abschnitt',
    _ => 'Kilometer',
  };

  /// Zeile für den Coach, z. B. „Morgenlauf (10.11.): Tempo gleichmäßig. Puls stabil.“ – im Modus „reduziert“ ohne
  /// Pulswerte in Schlägen.
  static String? contextLine(ActivityReport report, {required bool full}) {
    final texts = [
      for (final finding in findings(report))
        if (full || !finding.hasRawHeartRate) finding.text,
    ];
    if (texts.isEmpty) return null;
    final name = report.name?.trim() ?? '';
    return '${name.isEmpty ? 'Aktivität' : name} (${GermanFormat.date(report.day)}): ${texts.join(' ')}';
  }
}

/// Welche Aktivitäten vollständig übertragen werden.
abstract final class ActivityReportPlanner {
  /// So weit zurück werden Aktivitäten vollständig nachgeladen.
  static const days = 42;
  static const minSeconds = 300.0;

  /// Aktivitäten ohne (aktuellen) Bericht, jüngste zuerst. Garmin-Aktivitäten (positive IDs) haben eine Datei der
  /// Uhr; mit [health] stattdessen die Workouts aus Apple Health (negative IDs), deren Verlauf die Health-Schnittstelle
  /// liefert.
  static List<GarminActivity> pending(
    List<GarminActivity> activities, {
    required Map<int, ActivityReport> known,
    Set<int> failed = const {},
    required CalendarDay today,
    bool health = false,
  }) {
    final start = today.adding(-days);
    return activities.where((activity) {
      final day = activity.day;
      if ((activity.id < 0) != health || day == null || day < start || day > today) return false;
      if ((activity.durationSeconds ?? 0) < minSeconds || failed.contains(activity.id)) return false;
      return known[activity.id]?.version != ActivityReport.currentVersion;
    }).toList()..sort((a, b) => (b.startLocal ?? '').compareTo(a.startLocal ?? ''));
  }
}

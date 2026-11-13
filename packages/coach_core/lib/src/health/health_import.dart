import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../nutrition/weight_trend.dart';
import '../util/enum_codec.dart';

/// Tageswerte, wie die App sie aus den Statistiken der Health-Schnittstelle je Kalendertag berechnet.
final class HealthDayValues {
  HealthDayValues(this.day);

  final CalendarDay day;
  double? restingHeartRate;

  /// SDNN in ms (Apple), nicht RMSSD (Garmin).
  double? hrvSDNN;
  double? steps;
  double? activeKilocalories;
  double? basalKilocalories;

  /// Atemzüge pro Minute
  double? respiratoryRate;

  /// Sauerstoffsättigung als Anteil (0,97) oder Prozent (97).
  double? oxygenSaturation;
  double? oxygenSaturationLowest;
  double? vo2Max;
}

/// Schlafphase.
enum SleepStage implements RawEnum {
  inBed,
  asleep,
  awake,
  core,
  deep,
  rem;

  @override
  String get rawValue => name;

  bool get isAsleep => this == asleep || this == core || this == deep || this == rem;

  static SleepStage? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Eine Schlafprobe.
final class SleepSample {
  const SleepSample({required this.start, required this.end, required this.stage, required this.source});

  final DateTime start;
  final DateTime end;
  final SleepStage stage;

  /// Quelle (Bundle-ID), damit Uhr und iPhone nicht doppelt zählen.
  final String source;
}

/// Ein Workout aus der Health-Schnittstelle.
final class HealthWorkout {
  const HealthWorkout({
    required this.uuid,
    required this.typeKey,
    required this.start,
    required this.end,
    this.distanceMeters,
    this.kilocalories,
    this.averageHeartRate,
    this.maxHeartRate,
    this.elevationGain,
    required this.sourceName,
    required this.sourceBundle,
  });

  final String uuid;

  /// Schlüssel im Stil von Garmin (`running`, `cycling`, `lap_swimming`, `strength_training`, …).
  final String typeKey;
  final DateTime start;
  final DateTime end;
  final double? distanceMeters;
  final double? kilocalories;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? elevationGain;
  final String sourceName;
  final String sourceBundle;
}

/// Apple Health bzw. Health Connect als zweite Datenquelle neben Garmin. Die App liest die Rohwerte und reicht sie
/// hier in einfachen Strukturen herein; die Zuordnung zu Tageswerten, Nächten und Aktivitäten ist ohne
/// Plattform-Abhängigkeit formuliert und getestet.
///
/// Grundsätze:
/// - Garmin hat Vorrang. Health füllt nur Lücken (`fill`), damit sich die Werte einer Uhr nicht mit denen einer
///   anderen mischen.
/// - Die Herzfrequenzvariabilität misst Apple als SDNN, Garmin als RMSSD in der Nacht. Die Werte sind nicht
///   vergleichbar; Health-HRV wird deshalb nur übernommen, wenn Garmin nicht verbunden ist.
/// - Workouts, die Garmin schon kennt (gleiche Zeit, gleiche Sportart) oder die die App selbst geschrieben hat,
///   werden nicht doppelt übernommen.
///
/// Uhrzeiten gelten in der Zeitzone des Geräts; für Tests lässt sich ein fester Abstand zu UTC angeben.
abstract final class HealthImport {
  static DateTime _wall(DateTime date, Duration? utcOffset) =>
      utcOffset == null ? date.toLocal() : date.toUtc().add(utcOffset);

  // Tageswerte

  static DailyMetrics metrics(HealthDayValues values, {required bool includeHRV}) {
    final metrics = DailyMetrics(values.day)
      ..restingHeartRate = within(values.restingHeartRate, 25, 120)
      ..steps = within(values.steps, 0, 150000)
      ..activeKilocalories = within(values.activeKilocalories, 0, 10000)
      ..restingKilocalories = within(values.basalKilocalories, 500, 5000)
      ..respirationWaking = within(values.respiratoryRate, 4, 40)
      ..spo2Average = within(percent(values.oxygenSaturation), 70, 100)
      ..spo2Lowest = within(percent(values.oxygenSaturationLowest), 50, 100)
      ..vo2Max = within(values.vo2Max, 15, 95);
    if (includeHRV) metrics.hrvLastNightAverage = within(values.hrvSDNN, 5, 300);
    final (active, basal) = (metrics.activeKilocalories, metrics.restingKilocalories);
    if (active != null && basal != null) metrics.totalKilocalories = active + basal;
    return metrics;
  }

  /// Ergänzt fehlende Werte von [base] (Garmin) aus [health]; vorhandene Werte bleiben unverändert.
  static DailyMetrics fill(DailyMetrics? base, DailyMetrics health) => base == null ? health : health.merging(base);

  static double? percent(double? value) => value == null ? null : (value <= 1 ? value * 100 : value);

  static double? within(double? value, double lower, double upper) {
    if (value == null || !value.isFinite || value < lower || value > upper) return null;
    return (value * 10).roundToDouble() / 10;
  }

  // Schlaf

  /// Ab so viel Schlaf ist eine Episode kein Nickerchen mehr, egal wann sie beginnt.
  static const _napLimit = 3.0 * 3600;

  /// Größere Lücken trennen zwei Schlafepisoden.
  static const _episodeGap = 3600.0;

  static double _seconds(DateTime start, DateTime end) => end.difference(start).inMicroseconds / 1e6;

  /// Nächte je Aufwachtag. Eine kurze Schlafepisode, die zwischen 10 und 18 Uhr beginnt, gilt als Nickerchen und
  /// zählt nicht. Bewertet wird die ganze Episode, denn die Uhr schreibt viele kurze Phasen (Schichtarbeit,
  /// Ausschlafen). Je Nacht zählt eine Quelle: die mit Schlafphasen (Apple Watch), sonst die mit dem meisten Schlaf.
  static Map<CalendarDay, DailyMetrics> sleep(List<SleepSample> samples, {Duration? utcOffset}) {
    final byNight = <CalendarDay, List<SleepSample>>{};
    final bySource = <String, List<SleepSample>>{};
    for (final sample in samples.where((sample) => sample.end.isAfter(sample.start))) {
      bySource.putIfAbsent(sample.source, () => []).add(sample);
    }
    for (final episode in bySource.values.expand(_episodes)) {
      final asleep = episode.where((sample) => sample.stage.isAsleep).toList();
      if (asleep.isEmpty) continue;
      final start = asleep.map((sample) => sample.start).reduce((a, b) => a.isBefore(b) ? a : b);
      final end = episode.map((sample) => sample.end).reduce((a, b) => a.isAfter(b) ? a : b);
      final hour = _wall(start, utcOffset).hour;
      if (hour >= 10 && hour < 18 && asleepSeconds(episode) < _napLimit) continue;
      // Aufwachtag: Ende plus sechs Stunden, damit Schlaf nach Mitternacht und bis in den Vormittag passt.
      final night = CalendarDay.fromDate(_wall(end.add(const Duration(hours: 6)), utcOffset));
      byNight.putIfAbsent(night, () => []).addAll(episode);
    }
    final result = <CalendarDay, DailyMetrics>{};
    for (final MapEntry(key: day, value: nightSamples) in byNight.entries) {
      final sources = <String, List<SleepSample>>{};
      for (final sample in nightSamples) {
        sources.putIfAbsent(sample.source, () => []).add(sample);
      }
      bool hasStages(List<SleepSample> list) => list.any(
        (sample) =>
            sample.stage == SleepStage.core || sample.stage == SleepStage.deep || sample.stage == SleepStage.rem,
      );
      List<SleepSample>? chosen;
      for (final candidate in sources.values) {
        if (chosen == null) {
          chosen = candidate;
          continue;
        }
        // Wie `max(by:)`: ersetzen, wenn der bisherige „kleiner“ ist.
        final (chosenStages, candidateStages) = (hasStages(chosen), hasStages(candidate));
        final chosenIsSmaller = chosenStages != candidateStages
            ? !chosenStages
            : asleepSeconds(chosen) < asleepSeconds(candidate);
        if (chosenIsSmaller) chosen = candidate;
      }
      if (chosen == null) continue;
      final asleep = chosen.where((sample) => sample.stage.isAsleep).toList();
      final total = asleepSeconds(chosen);
      if (total < 1800 || asleep.isEmpty) continue;
      final first = asleep.map((sample) => sample.start).reduce((a, b) => a.isBefore(b) ? a : b);
      final last = asleep.map((sample) => sample.end).reduce((a, b) => a.isAfter(b) ? a : b);
      double? stageSeconds(SleepStage stage) {
        final sum = chosen!
            .where((sample) => sample.stage == stage)
            .fold(0.0, (value, sample) => value + _seconds(sample.start, sample.end));
        return sum > 0 ? sum : null;
      }

      result[day] = DailyMetrics(day)
        ..sleepSeconds = total
        ..deepSleepSeconds = stageSeconds(SleepStage.deep)
        ..remSleepSeconds = stageSeconds(SleepStage.rem)
        ..lightSleepSeconds = stageSeconds(SleepStage.core)
        ..awakeSleepSeconds = stageSeconds(SleepStage.awake)
        ..sleepStartMinutes = _minutes(_wall(first, utcOffset))
        ..sleepEndMinutes = _minutes(_wall(last, utcOffset));
    }
    return result;
  }

  /// Proben einer Quelle, zu Episoden zusammengefasst.
  static List<List<SleepSample>> _episodes(List<SleepSample> samples) {
    final result = <List<SleepSample>>[];
    DateTime? latestEnd;
    for (final sample in [...samples]..sort((a, b) => a.start.compareTo(b.start))) {
      if (latestEnd != null && _seconds(latestEnd, sample.start) < _episodeGap) {
        result.last.add(sample);
        latestEnd = latestEnd.isAfter(sample.end) ? latestEnd : sample.end;
      } else {
        result.add([sample]);
        latestEnd = sample.end;
      }
    }
    return result;
  }

  /// Geschlafene Sekunden ohne Überlappungen (mehrere Einträge derselben Quelle können sich überschneiden).
  static double asleepSeconds(List<SleepSample> samples) {
    final intervals = [
      for (final sample in samples)
        if (sample.stage.isAsleep) (sample.start, sample.end),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0.0;
    (DateTime, DateTime)? current;
    for (final interval in intervals) {
      if (current != null && !interval.$1.isAfter(current.$2)) {
        current = (current.$1, current.$2.isAfter(interval.$2) ? current.$2 : interval.$2);
      } else {
        if (current != null) total += _seconds(current.$1, current.$2);
        current = interval;
      }
    }
    if (current != null) total += _seconds(current.$1, current.$2);
    return total;
  }

  static double _minutes(DateTime wall) => (wall.hour * 60 + wall.minute).toDouble();

  // Workouts

  /// Stabile, negative ID aus der Workout-UUID; Garmin-IDs sind positiv, so gibt es keine Kollision.
  static int activityID(String uuid) {
    final hex = uuid.replaceAll('-', '');
    var value = 0;
    for (var index = 0; index < 16 && index < hex.length; index += 2) {
      value = (value << 8) | int.parse(hex.substring(index, index + 2), radix: 16);
    }
    value &= 0x3FFFFFFFFFFFFFFF;
    return -value - 1;
  }

  static GarminActivity activity(HealthWorkout workout, {Duration? utcOffset}) {
    final duration = _seconds(workout.start, workout.end);
    final activity = GarminActivity(activityID(workout.uuid))
      ..typeKey = workout.typeKey
      ..name = '${label(workout.typeKey)} · ${workout.sourceName}'
      ..startLocal = _timestamp(_wall(workout.start, utcOffset))
      ..durationSeconds = duration > 0 ? duration : null;
    activity
      ..elapsedSeconds = activity.durationSeconds
      ..distanceMeters = within(workout.distanceMeters, 1, 500000)
      ..calories = within(workout.kilocalories, 1, 10000)
      ..averageHeartRate = within(workout.averageHeartRate, 30, 230)
      ..maxHeartRate = within(workout.maxHeartRate, 30, 240)
      ..elevationGain = within(workout.elevationGain, 0, 10000);
    activity.activeKilocalories = activity.calories;
    if (activity.distanceMeters case final distance? when duration > 0) activity.averageSpeed = distance / duration;
    return activity;
  }

  /// Workouts, die übernommen werden: nicht von der App selbst geschrieben und nicht schon als Garmin-Aktivität
  /// vorhanden (Start höchstens 10 Minuten auseinander oder mehr als die Hälfte überlappend).
  static List<GarminActivity> newActivities(
    List<HealthWorkout> workouts, {
    required List<GarminActivity> existing,
    required String ownBundle,
    Duration? utcOffset,
  }) {
    final others = <(ActivitySport, DateTime, DateTime)>[];
    for (final activity in existing.where((activity) => activity.id >= 0)) {
      final text = activity.startLocal;
      final start = text == null ? null : date(text, utcOffset: utcOffset);
      if (start == null) continue;
      final seconds = activity.durationSeconds ?? 0;
      others.add((activity.sport, start, start.add(Duration(microseconds: (seconds * 1e6).round()))));
    }
    return [
      for (final workout in workouts)
        if (workout.sourceBundle != ownBundle &&
            !workout.sourceBundle.startsWith('$ownBundle.') &&
            !others.any((other) {
              final sport = ActivitySport.fromTypeKey(workout.typeKey);
              if (other.$1 != sport && other.$1 != ActivitySport.other && sport != ActivitySport.other) return false;
              if (_seconds(other.$2, workout.start).abs() <= 600) return true;
              final overlapEnd = other.$3.isBefore(workout.end) ? other.$3 : workout.end;
              final overlapStart = other.$2.isAfter(workout.start) ? other.$2 : workout.start;
              final overlap = _seconds(overlapStart, overlapEnd);
              final shorter = math.min(_seconds(other.$2, other.$3), _seconds(workout.start, workout.end));
              return shorter > 0 && overlap > shorter / 2;
            }))
          activity(workout, utcOffset: utcOffset),
    ];
  }

  static String label(String typeKey) => switch (typeKey) {
    'running' => 'Laufen',
    'cycling' => 'Radfahren',
    'lap_swimming' => 'Schwimmen (Becken)',
    'open_water_swimming' => 'Freiwasserschwimmen',
    'strength_training' => 'Krafttraining',
    'walking' => 'Gehen',
    'hiking' => 'Wandern',
    'hiit' => 'HIIT',
    'yoga' => 'Yoga',
    'indoor_rowing' => 'Rudern',
    'elliptical' => 'Crosstrainer',
    _ => 'Training',
  };

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _timestamp(DateTime wall) =>
      '${wall.year.toString().padLeft(4, '0')}-${_two(wall.month)}-${_two(wall.day)} ${_two(wall.hour)}:'
      '${_two(wall.minute)}:${_two(wall.second)}';

  /// Zeitpunkt aus „yyyy-MM-dd HH:mm:ss“ in Ortszeit (bzw. mit festem Abstand zu UTC).
  static DateTime? date(String text, {Duration? utcOffset}) {
    final parts = text.replaceAll('T', ' ').split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final day = CalendarDay.tryParse(parts[0]);
    if (day == null) return null;
    final time = [
      for (final part in parts[1].split(':').where((part) => part.isNotEmpty)) (double.tryParse(part) ?? -1).toInt(),
    ];
    if (time.length < 2) return null;
    final second = time.length > 2 ? time[2] : 0;
    if (utcOffset == null) return DateTime(day.year, day.month, day.day, time[0], time[1], second);
    return DateTime.utc(day.year, day.month, day.day, time[0], time[1], second).subtract(utcOffset);
  }

  // Gewicht

  /// Letzte Wägung je Tag.
  static List<WeightEntry> weights(List<({DateTime date, double kilograms})> samples, {Duration? utcOffset}) {
    final byDay = <CalendarDay, (DateTime, double)>{};
    for (final sample in samples) {
      if (sample.kilograms < 25 || sample.kilograms > 300) continue;
      final day = CalendarDay.fromDate(_wall(sample.date, utcOffset));
      final existing = byDay[day];
      if (existing != null && existing.$1.isAfter(sample.date)) continue;
      byDay[day] = (sample.date, sample.kilograms);
    }
    return [
      for (final MapEntry(:key, :value) in byDay.entries)
        WeightEntry(day: key, kilograms: (value.$2 * 10).roundToDouble() / 10, source: WeightSource.health),
    ]..sort((a, b) => a.day.compareTo(b.day));
  }
}

import 'dart:math' as math;

import '../fit/fit_decoder.dart';

/// Einzelwert zu einem Zeitpunkt (Sekunden seit Bezugsdatum).
final class HealthSample {
  const HealthSample({required this.time, required this.value});

  final double time;
  final double value;
}

/// Menge über einen Zeitraum (z. B. 12 m Distanz in 3 s).
final class HealthAmount {
  const HealthAmount({required this.start, required this.end, required this.value});

  final double start;
  final double end;
  final double value;
}

final class HealthLocation {
  const HealthLocation({required this.time, required this.latitude, required this.longitude, this.altitude});

  final double time;
  final double latitude;
  final double longitude;
  final double? altitude;
}

final class HealthInterval {
  const HealthInterval({required this.start, required this.end});

  final double start;
  final double end;
}

/// Rohdaten eines Workouts.
final class HealthRecordingInput {
  HealthRecordingInput({required this.start, required this.end});

  final double start;
  final double end;

  /// Schläge pro Minute.
  List<HealthSample> heartRate = [];

  /// Meter je Zeitraum.
  List<HealthAmount> distance = [];

  /// Watt.
  List<HealthSample> power = [];
  List<HealthLocation> locations = [];

  /// Runden laut Uhr (Taste oder Bahn), nicht die automatischen Kilometer.
  List<HealthInterval> laps = [];
  List<HealthInterval> pauses = [];
}

/// Verlauf eines Workouts aus Apple Health bzw. Health Connect als Aufzeichnung im selben Format wie die Datei einer
/// Garmin-Uhr (`FitActivity`). So gelten Auswertung, Splits und Diagramme unverändert (`ActivityReportBuilder`).
abstract final class HealthRecording {
  /// Raster der Aufzeichnung in Sekunden.
  static const step = 5.0;

  /// Ein Messwert gilt höchstens so lange (s); danach ist die Stelle leer.
  static const validSeconds = 30.0;

  /// Messpunkte alle 5 Sekunden; pausierte Zeit bleibt als Lücke (zählt in der Auswertung als Standzeit).
  static FitActivity fit(HealthRecordingInput input) {
    if (input.end <= input.start) return FitActivity();
    final heartRate = [...input.heartRate]..sort((a, b) => a.time.compareTo(b.time));
    final power = [...input.power]..sort((a, b) => a.time.compareTo(b.time));
    final distance = input.distance.where((amount) => amount.end >= amount.start && amount.value >= 0).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final locations = [...input.locations]..sort((a, b) => a.time.compareTo(b.time));
    final heartCursor = [0];
    final powerCursor = [0];
    var locationCursor = 0;
    var distanceCursor = 0;
    var completed = 0.0;
    ({double time, double distance})? previous;
    final records = <FitRecord>[];

    for (var time = input.start; time <= input.end + 0.001; time += step) {
      if (input.pauses.any((pause) => pause.start <= time && time < pause.end)) {
        previous = null;
        continue;
      }
      double? recordDistance;
      double? speed;
      if (distance.isNotEmpty) {
        // Abgeschlossene Zeiträume ganz, der laufende anteilig.
        while (distanceCursor < distance.length && distance[distanceCursor].end <= time) {
          completed += distance[distanceCursor].value;
          distanceCursor += 1;
        }
        var total = completed;
        if (distanceCursor < distance.length) {
          final current = distance[distanceCursor];
          if (current.start < time && current.end > current.start) {
            total += current.value * (time - current.start) / (current.end - current.start);
          }
        }
        recordDistance = total;
        if (previous != null && time > previous.time) {
          speed = math.max(0, (total - previous.distance) / (time - previous.time));
        }
        previous = (time: time, distance: total);
      }
      final record = FitRecord(
        timestamp: time,
        heartRate: _latest(heartRate, time, heartCursor),
        power: _latest(power, time, powerCursor),
        distance: recordDistance,
        speed: speed,
      );
      while (locationCursor + 1 < locations.length && locations[locationCursor + 1].time <= time) {
        locationCursor += 1;
      }
      if (locationCursor < locations.length) {
        final location = locations[locationCursor];
        if ((location.time - time).abs() <= validSeconds) {
          record
            ..latitude = location.latitude
            ..longitude = location.longitude
            ..altitude = location.altitude;
        }
      }
      records.add(record);
    }
    return FitActivity(records: records, laps: laps(input, records));
  }

  /// Jüngster Wert bis [time], höchstens 30 s alt.
  static double? _latest(List<HealthSample> samples, double time, List<int> cursor) {
    while (cursor[0] + 1 < samples.length && samples[cursor[0] + 1].time <= time) {
      cursor[0] += 1;
    }
    if (cursor[0] >= samples.length) return null;
    final sample = samples[cursor[0]];
    return sample.time <= time && time - sample.time <= validSeconds ? sample.value : null;
  }

  /// Runden mit Zeit ohne Pausen, Distanz und Puls aus den Messpunkten.
  static List<FitLap> laps(HealthRecordingInput input, List<FitRecord> records) {
    final sorted = input.laps.where((lap) => lap.end > lap.start).toList()..sort((a, b) => a.start.compareTo(b.start));
    return [
      for (final lap in sorted)
        () {
          final inside = records
              .where((record) => record.timestamp >= lap.start && record.timestamp <= lap.end)
              .toList();
          final paused = input.pauses.fold(
            0.0,
            (sum, pause) => sum + math.max(0.0, math.min(pause.end, lap.end) - math.max(pause.start, lap.start)),
          );
          final heartRates = inside.map((record) => record.heartRate).nonNulls.toList();
          double? meters;
          final first = inside.isEmpty ? null : inside.first.distance;
          final last = inside.isEmpty ? null : inside.last.distance;
          if (first != null && last != null) meters = math.max(0, last - first);
          final result =
              FitLap(
                  timerSeconds: lap.end - lap.start - paused,
                  distanceMeters: meters,
                  averageHeartRate: heartRates.isEmpty
                      ? null
                      : heartRates.fold(0.0, (sum, value) => sum + value) / heartRates.length,
                  maxHeartRate: heartRates.isEmpty ? null : heartRates.reduce(math.max),
                )
                ..elapsedSeconds = lap.end - lap.start
                ..startTime = lap.start;
          final seconds = result.timerSeconds;
          if (meters != null && seconds != null && seconds > 0 && meters > 0) result.averageSpeed = meters / seconds;
          final powers = inside.map((record) => record.power).nonNulls.toList();
          if (powers.isNotEmpty) result.averagePower = powers.fold(0.0, (sum, value) => sum + value) / powers.length;
          return result;
        }(),
    ];
  }
}

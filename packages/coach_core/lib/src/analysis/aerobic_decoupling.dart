import '../fit/fit_decoder.dart';
import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';
import '../util/rounding.dart';

enum DecouplingSport implements RawEnum {
  run,
  ride;

  @override
  String get rawValue => name;
}

enum DecouplingSource implements RawEnum {
  series,
  laps;

  @override
  String get rawValue => name;
}

final class DecouplingResult {
  DecouplingResult({
    required this.percent,
    required this.firstHalfHeartRate,
    required this.secondHalfHeartRate,
    this.firstHalfPace,
    this.secondHalfPace,
    this.firstHalfPower,
    this.secondHalfPower,
    required this.source,
  });

  final double percent;
  final double firstHalfHeartRate;
  final double secondHalfHeartRate;

  /// Laufen: Tempo je Hälfte in s/km.
  int? firstHalfPace;
  int? secondHalfPace;

  /// Rad: Leistung je Hälfte in Watt.
  int? firstHalfPower;
  int? secondHalfPower;
  final DecouplingSource source;

  Map<String, Object?> toJson() => {
    'percent': percent,
    'firstHalfHeartRate': firstHalfHeartRate,
    'secondHalfHeartRate': secondHalfHeartRate,
    'firstHalfPace': ?firstHalfPace,
    'secondHalfPace': ?secondHalfPace,
    'firstHalfPower': ?firstHalfPower,
    'secondHalfPower': ?secondHalfPower,
    'source': source.rawValue,
  };

  static DecouplingResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final percent = jsonDouble(json['percent']);
    final first = jsonDouble(json['firstHalfHeartRate']);
    final second = jsonDouble(json['secondHalfHeartRate']);
    final source = enumFromRaw(DecouplingSource.values, json['source']);
    if (percent == null || first == null || second == null || source == null) return null;
    return DecouplingResult(
      percent: percent,
      firstHalfHeartRate: first,
      secondHalfHeartRate: second,
      firstHalfPace: jsonInt(json['firstHalfPace']),
      secondHalfPace: jsonInt(json['secondHalfPace']),
      firstHalfPower: jsonInt(json['firstHalfPower']),
      secondHalfPower: jsonInt(json['secondHalfPower']),
      source: source,
    );
  }

  @override
  bool operator ==(Object other) => other is DecouplingResult && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

final class DecouplingSample {
  const DecouplingSample({required this.time, required this.output, required this.heartRate});

  /// Sekunden seit Start.
  final double time;

  /// m/s (Laufen) oder Watt (Rad).
  final double output;
  final double heartRate;
}

/// Aerobe Kopplung („aerobic decoupling“, Pa:HR bzw. Pw:HR) wie im Altbestand (`decoupling.py`, Methode 3).
///
/// Aufwärmen (10 min) abschneiden, den Rest nach Zeit halbieren und je Hälfte einen Effizienzfaktor (Tempo bzw.
/// Leistung je Herzschlag) bilden: Entkopplung % = (EF1 − EF2) / EF1 × 100. Positive Werte heißen, die HF steigt relativ
/// zur Leistung (Herz-Kreislauf-Drift). Unter 5 % gilt als stabile aerobe Basis für die Dauer – eine Praxisregel, keine
/// scharf belegte Schwelle. Nur gleichmäßige, aerobe Einheiten sind aussagekräftig: höchstens 10 % der Zeit in Zone
/// 4–5.
abstract final class AerobicDecoupling {
  static const methodVersion = 3;
  static const warmupSeconds = 600.0;
  static const maxHighZoneShare = 0.10;
  static const minRunMinutes = 35.0;
  static const minRideMinutes = 45.0;

  /// Unter diesem Wert gilt die Kopplung als stabil (Praxiswert nach Friel).
  static const goodBelowPercent = 5.0;

  /// Anteil der Zeit in Zone 4–5; `null` ohne Zonen.
  static double? highZoneShare(GarminActivity activity) {
    final zones = activity.secondsInZones;
    if (zones == null || zones.length != 5) return null;
    final total = zones.fold<double>(0, (sum, value) => sum + value);
    return total > 0 ? (zones[3] + zones[4]) / total : null;
  }

  /// Ob und als was die Aktivität infrage kommt (`classify`).
  static DecouplingSport? classify(GarminActivity activity) {
    final minutes = (activity.durationSeconds ?? 0) / 60;
    final DecouplingSport sport;
    switch (activity.sport) {
      case ActivitySport.run:
        if (minutes < minRunMinutes) return null;
        sport = DecouplingSport.run;
      case ActivitySport.bike:
        // Nur die Zwift-Aufzeichnung mit Distanz und Leistung, nicht die HF-Zweitaufzeichnung der Uhr.
        if (minutes < minRideMinutes || (activity.distanceMeters ?? 0) <= 0 || activity.averagePower == null) {
          return null;
        }
        sport = DecouplingSport.ride;
      default:
        return null;
    }
    final share = highZoneShare(activity);
    if (share == null || share > maxHighZoneShare) return null;
    return sport;
  }

  /// Klartext, warum [classify] die Aktivität verworfen hat; `null` für andere Sportarten und die HF-Zweitaufzeichnung
  /// der Uhr (`skip_reason`).
  static String? skipReason(GarminActivity activity) {
    final minutes = (activity.durationSeconds ?? 0) / 60;
    final isRun = activity.sport == ActivitySport.run;
    final isRide = activity.sport == ActivitySport.bike;
    if (!isRun && !isRide) return null;
    if (isRide && (activity.distanceMeters ?? 0) <= 0) return null;
    if (isRun && minutes < minRunMinutes) return 'kürzer als ${minRunMinutes.toInt()} min';
    if (isRide && minutes < minRideMinutes) return 'kürzer als ${minRideMinutes.toInt()} min';
    if (isRide && activity.averagePower == null) return 'keine Leistungsdaten';
    final share = highZoneShare(activity);
    if (share == null) return 'keine HF-Zonendaten von Garmin';
    if (share > maxHighZoneShare) return 'zu intensiv (${roundHalfEven(share * 100)} % der Zeit in Zone 4-5)';
    return 'nicht geeignet';
  }

  /// Messpunkte aus der FIT-Datei (Zeit relativ zum ersten Messpunkt).
  static List<DecouplingSample> samples(FitActivity fit, DecouplingSport sport) {
    if (fit.records.isEmpty) return const [];
    final start = fit.records.first.timestamp;
    return [
      for (final record in fit.records)
        if (record.heartRate case final heart? when heart > 0)
          if ((sport == DecouplingSport.ride ? record.power : record.speed) case final output?)
            DecouplingSample(time: record.timestamp - start, output: output, heartRate: heart),
    ];
  }

  /// Entkopplung aus der Zeitreihe (`compute_from_details`).
  static DecouplingResult? fromSeries(List<DecouplingSample> samples, DecouplingSport sport) {
    final points = samples.where((sample) => sample.heartRate > 0 && sample.time >= warmupSeconds).toList();
    if (points.length < 20 || points.last.time - points.first.time < 20 * 60) return null;
    final mid = points.first.time + (points.last.time - points.first.time) / 2;
    final firstHalf = points.where((sample) => sample.time < mid).toList();
    final secondHalf = points.where((sample) => sample.time >= mid).toList();
    if (firstHalf.isEmpty || secondHalf.isEmpty) return null;
    double mean(Iterable<double> values) => values.fold<double>(0, (sum, value) => sum + value) / values.length;
    final output1 = mean(firstHalf.map((sample) => sample.output));
    final heart1 = mean(firstHalf.map((sample) => sample.heartRate));
    final output2 = mean(secondHalf.map((sample) => sample.output));
    final heart2 = mean(secondHalf.map((sample) => sample.heartRate));
    if (output1 <= 0 || heart1 <= 0 || heart2 <= 0) return null;
    final efficiency1 = output1 / heart1;
    final efficiency2 = output2 / heart2;
    final result = DecouplingResult(
      percent: round1HalfEven((efficiency1 - efficiency2) / efficiency1 * 100),
      firstHalfHeartRate: round1HalfEven(heart1),
      secondHalfHeartRate: round1HalfEven(heart2),
      source: DecouplingSource.series,
    );
    if (sport == DecouplingSport.ride) {
      result
        ..firstHalfPower = roundHalfEven(output1)
        ..secondHalfPower = roundHalfEven(output2);
    } else {
      result
        ..firstHalfPace = pace(output1)
        ..secondHalfPace = pace(output2);
    }
    return result;
  }

  /// Rundenmethode für Läufe ohne Zeitreihe (`compute_from_laps_trimmed`): Runden der ersten 10 Minuten fallen weg,
  /// dann Teilung nach Distanz.
  static DecouplingResult? fromLaps(List<FitLap> laps) {
    final kept = <FitLap>[];
    var elapsed = 0.0;
    for (final lap in laps) {
      if (elapsed >= warmupSeconds) kept.add(lap);
      elapsed += lap.timerSeconds ?? lap.elapsedSeconds ?? 0;
    }
    final metrics = <({double distance, double duration, double heartRate})>[
      for (final lap in kept)
        if ((lap.distanceMeters, lap.timerSeconds ?? lap.elapsedSeconds, lap.averageHeartRate)
            case (final distance?, final duration?, final heart?) when distance > 0 && duration > 0 && heart > 0)
          (distance: distance, duration: duration, heartRate: heart),
    ];
    if (metrics.length < 2) return null;
    final half = metrics.fold<double>(0, (sum, lap) => sum + lap.distance) / 2;
    var firstHalf = <({double distance, double duration, double heartRate})>[];
    var secondHalf = <({double distance, double duration, double heartRate})>[];
    var cumulative = 0.0;
    for (final lap in metrics) {
      cumulative += lap.distance;
      if (cumulative <= half) {
        firstHalf.add(lap);
      } else {
        secondHalf.add(lap);
      }
    }
    if (firstHalf.isEmpty || secondHalf.isEmpty) {
      // Grenze fällt bei wenigen, ungleichen Runden so, dass eine Seite leer bleibt: nach Rundenzahl teilen.
      final mid = metrics.length ~/ 2 > 1 ? metrics.length ~/ 2 : 1;
      firstHalf = metrics.sublist(0, mid);
      secondHalf = metrics.sublist(mid);
    }
    ({double speed, double heart})? stats(List<({double distance, double duration, double heartRate})> part) {
      final distance = part.fold<double>(0, (sum, lap) => sum + lap.distance);
      final duration = part.fold<double>(0, (sum, lap) => sum + lap.duration);
      if (distance <= 0 || duration <= 0) return null;
      return (
        speed: distance / duration,
        heart: part.fold<double>(0, (sum, lap) => sum + lap.heartRate * lap.duration) / duration,
      );
    }

    final first = stats(firstHalf);
    final second = stats(secondHalf);
    if (first == null || second == null) return null;
    final efficiency1 = first.speed / first.heart;
    final efficiency2 = second.speed / second.heart;
    return DecouplingResult(
      percent: round1HalfEven((efficiency1 - efficiency2) / efficiency1 * 100),
      firstHalfHeartRate: round1HalfEven(first.heart),
      secondHalfHeartRate: round1HalfEven(second.heart),
      firstHalfPace: lapPace(first.speed),
      secondHalfPace: lapPace(second.speed),
      source: DecouplingSource.laps,
    );
  }

  /// Zeitreihe zuerst, bei Läufen notfalls die Runden (wie `_update_decoupling_cache`).
  static DecouplingResult? compute(FitActivity fit, DecouplingSport sport) =>
      fromSeries(samples(fit, sport), sport) ?? (sport == DecouplingSport.run ? fromLaps(fit.laps) : null);

  static int? pace(double speed) => speed > 0 ? roundHalfEven(1000 / speed) : null;

  /// Wie im Altbestand: erst auf 1/100 min/km, dann auf Sekunden runden. `toStringAsFixed` rundet wie Pythons
  /// `round(x, 2)` den exakten Binärwert, nicht das Produkt mit 100.
  static int? lapPace(double speed) {
    if (speed <= 0) return null;
    final minutes = double.parse((1000 / speed / 60).toStringAsFixed(2));
    return roundHalfEven(minutes * 60);
  }
}

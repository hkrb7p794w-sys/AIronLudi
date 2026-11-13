import '../garmin/garmin_activity.dart';
import '../util/german_format.dart';

final class DetailRow {
  const DetailRow(this.label, this.value);

  final String label;
  final String value;

  String get id => label;

  @override
  bool operator ==(Object other) => other is DetailRow && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

final class DetailSection {
  const DetailSection(this.title, this.rows);

  final String title;
  final List<DetailRow> rows;

  String get id => title;
}

/// Aufbereitung einer Aktivität für die Detailansicht, gegliedert wie in Garmin Connect: Übersicht, Zeit, Tempo,
/// Herzfrequenz, Höhe, Laufdynamik, Leistung, Schwimmen, Trainingseffekt. Nur vorhandene Werte erscheinen.
///
/// Verlauf und Strecke aus der FIT-Datei (`samples`, `route`) folgen mit dem FIT-Modul.
abstract final class ActivityDetails {
  static List<DetailSection> sections(GarminActivity activity) {
    final sport = activity.sport;
    final sections = <DetailSection>[];
    void add(String title, List<DetailRow?> rows) {
      final present = rows.nonNulls.toList();
      if (present.isNotEmpty) sections.add(DetailSection(title, present));
    }

    DetailRow? row(String label, double? value, String Function(double value) format) {
      if (value == null || !value.isFinite || value <= 0) return null;
      return DetailRow(label, format(value));
    }

    String bpm(double value) => '${value.round()} bpm';
    String meters(double value) => '${value.round()} m';
    String rounded(double value) => '${value.round()}';

    add('Übersicht', [
      row('Distanz', activity.distanceMeters, (value) => distance(value, sport)),
      row('Zeit', activity.durationSeconds, duration),
      row(speedLabel(sport), activity.averageSpeed, (value) => speed(value, sport)),
      row('Ø Herzfrequenz', activity.averageHeartRate, bpm),
      row('Kalorien', activity.calories, (value) => '${value.round()} kcal'),
      row('Anstieg', activity.elevationGain, meters),
    ]);
    add('Zeit', [
      row('Zeit', activity.durationSeconds, duration),
      row('Bewegungszeit', activity.movingSeconds, duration),
      row('Verstrichene Zeit', activity.elapsedSeconds, duration),
    ]);
    add(sport == ActivitySport.run || sport == ActivitySport.swim ? 'Pace' : 'Geschwindigkeit', [
      row(speedLabel(sport), activity.averageSpeed, (value) => speed(value, sport)),
      row(
        sport == ActivitySport.run ? 'Beste Pace' : 'Max. Geschwindigkeit',
        activity.maxSpeed,
        (value) => speed(value, sport),
      ),
      row('Ø bewegt', movingSpeed(activity), (value) => speed(value, sport)),
    ]);
    add('Herzfrequenz', [
      row('Ø Herzfrequenz', activity.averageHeartRate, bpm),
      row('Max. Herzfrequenz', activity.maxHeartRate, bpm),
      ...zoneRows(activity.secondsInZones),
    ]);
    add('Höhe', [
      row('Anstieg', activity.elevationGain, meters),
      row('Abstieg', activity.elevationLoss, meters),
      row('Min. Höhe', activity.minElevation, meters),
      row('Max. Höhe', activity.maxElevation, meters),
    ]);
    final cadenceUnit = sport == ActivitySport.bike ? 'U/min' : 'spm';
    add(sport == ActivitySport.run ? 'Laufdynamik' : 'Kadenz', [
      row('Ø Kadenz', activity.averageCadence, (value) => '${value.round()} $cadenceUnit'),
      row('Max. Kadenz', activity.maxCadence, (value) => '${value.round()} $cadenceUnit'),
      row('Ø Schrittlänge', activity.strideLength, (value) => '${GermanFormat.number(value.roundToDouble() / 100)} m'),
      row('Ø Bodenkontaktzeit', activity.groundContactTime, (value) => '${value.round()} ms'),
      row('Ø Vertikale Bewegung', activity.verticalOscillation, (value) => '${GermanFormat.decimal(value)} cm'),
      row('Ø Vertikales Verhältnis', activity.verticalRatio, (value) => '${GermanFormat.decimal(value)} %'),
      row('Schritte', activity.steps, rounded),
    ]);
    add('Leistung', [
      row('Ø Leistung', activity.averagePower, (value) => '${value.round()} W'),
      row('Max. Leistung', activity.maxPower, (value) => '${value.round()} W'),
      row('Normalized Power', activity.normalizedPower, (value) => '${value.round()} W'),
    ]);
    add('Schwimmen', [
      row('Bahnlänge', activity.poolLength, (value) => '${GermanFormat.number(value)} m'),
      row('Bahnen', activity.lengths, rounded),
      row('Züge gesamt', activity.strokes, rounded),
      row('Ø Zugfrequenz', activity.strokeRate, (value) => '${value.round()} Züge/min'),
      row('Ø SWOLF', activity.swolf, rounded),
    ]);
    add('Trainingseffekt', [
      row('Aerob', activity.aerobicTrainingEffect, GermanFormat.decimal),
      row('Anaerob', activity.anaerobicTrainingEffect, GermanFormat.decimal),
      if (activity.trainingEffectLabel case final label?) DetailRow('Schwerpunkt', effectLabel(label)),
      row('Trainingsbelastung', activity.trainingLoad, rounded),
      row('VO2max', activity.vo2Max, GermanFormat.decimal),
    ]);
    add('Sonstiges', [
      row('Aktive Kalorien', activity.activeKilocalories, (value) => '${value.round()} kcal'),
      if (activity.minTemperature case final value?) DetailRow('Min. Temperatur', '${value.round()} °C'),
      if (activity.maxTemperature case final value?) DetailRow('Max. Temperatur', '${value.round()} °C'),
      row('Runden', activity.lapCount, rounded),
      if (activity.locationName case final name?) DetailRow('Ort', name),
    ]);
    return sections;
  }

  static List<DetailRow> zoneRows(List<double>? zones) {
    if (zones == null || zones.length != 5) return const [];
    final total = zones.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return const [];
    return [
      for (var index = 0; index < 5; index++)
        DetailRow('Zone ${index + 1}', '${duration(zones[index])} (${(zones[index] / total * 100).round()} %)'),
    ];
  }

  static double? movingSpeed(GarminActivity activity) {
    final distance = activity.distanceMeters;
    final moving = activity.movingSeconds;
    if (distance == null || moving == null || moving <= 0) return null;
    return distance / moving;
  }

  static String speedLabel(ActivitySport sport) =>
      sport == ActivitySport.run || sport == ActivitySport.swim ? 'Ø Pace' : 'Ø Geschwindigkeit';

  /// Laufen: min/km, Schwimmen: min/100 m, sonst km/h.
  static String speed(double metersPerSecond, ActivitySport sport) {
    if (metersPerSecond <= 0) return '–';
    return switch (sport) {
      ActivitySport.run => '${clock(1000 / metersPerSecond)} /km',
      ActivitySport.swim => '${clock(100 / metersPerSecond)} /100 m',
      _ => '${GermanFormat.decimal(metersPerSecond * 3.6)} km/h',
    };
  }

  static String distance(double meters, ActivitySport sport) => sport == ActivitySport.swim
      ? '${meters.round()} m'
      : '${GermanFormat.number((meters / 10).roundToDouble() / 100)} km';

  /// „1:05:30“ bzw. „42:10“.
  static String duration(double seconds) {
    final total = seconds.round();
    final hours = total ~/ 3600;
    final minutes = total % 3600 ~/ 60;
    final rest = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${two(minutes)}:${two(rest)}' : '$minutes:${two(rest)}';
  }

  static String clock(double seconds) {
    final total = seconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  static String effectLabel(String key) => switch (key.toUpperCase()) {
    'RECOVERY' => 'Erholung',
    'AEROBIC_BASE' => 'Grundlage',
    'TEMPO' => 'Tempo',
    'LACTATE_THRESHOLD' => 'Laktatschwelle',
    'SPEED' => 'Schnelligkeit',
    'VO2MAX' => 'VO2max',
    'ANAEROBIC_CAPACITY' => 'Anaerobe Kapazität',
    'SPRINT' => 'Sprint',
    _ => _capitalized(key),
  };

  /// Wie `String.capitalized` in Swift: jedes durch Leerraum getrennte Wort groß, der Rest klein.
  static String _capitalized(String text) => text
      .toLowerCase()
      .split(RegExp(r'(?<=\s)|(?=\s)'))
      .map((part) => part.isEmpty ? part : part[0].toUpperCase() + part.substring(1))
      .join();
}

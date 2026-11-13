import 'dart:convert';

import 'inflate.dart';

/// Ein Messpunkt der Aktivität (FIT-Nachricht `record`, meist einer pro Sekunde).
final class FitRecord {
  FitRecord({required this.timestamp, this.heartRate, this.speed, this.power, this.distance});

  /// Sekunden seit dem FIT-Bezugszeitpunkt (31.12.1989 UTC).
  final double timestamp;
  final double? heartRate;

  /// m/s (`enhanced_speed`, sonst `speed`).
  final double? speed;
  final double? power;

  /// Meter seit Start.
  final double? distance;

  /// Höhe in Metern.
  double? altitude;

  /// Kadenz laut Uhr (Laufen: Schritte eines Fußes pro Minute, Rad: Umdrehungen pro Minute).
  double? cadence;

  /// Position in Grad.
  double? latitude;
  double? longitude;

  /// °C
  double? temperature;
}

/// Art der Runde laut Uhr; bei strukturierten Workouts gesetzt (FIT-Typ `intensity`).
enum FitLapIntensity { active, rest, warmup, cooldown, recovery, interval, other }

/// Eine Runde (FIT-Nachricht `lap`), entspricht Garmins `lapDTOs` aus der Rundenansicht.
final class FitLap {
  FitLap({this.timerSeconds, this.distanceMeters, this.averageHeartRate, this.maxHeartRate, this.intensity});

  double? startTime;

  /// Gesamtdauer inkl. Pausen (s).
  double? elapsedSeconds;

  /// Dauer bei laufender Uhr (s), entspricht Garmins `movingDuration`/`duration` je Runde.
  double? timerSeconds;
  double? distanceMeters;
  double? averageHeartRate;
  double? maxHeartRate;
  FitLapIntensity? intensity;

  /// m/s
  double? averageSpeed;
  double? maxSpeed;
  double? ascentMeters;
  double? descentMeters;

  /// Wie [FitRecord.cadence].
  double? averageCadence;
  double? averagePower;
  double? maxPower;
  double? calories;

  /// Arbeitsrunde laut Workout (Garmins `intensityType` ACTIVE/INTERVAL).
  bool get isWork => intensity == FitLapIntensity.active || intensity == FitLapIntensity.interval;
}

/// Ein Satz im Krafttraining (FIT-Nachricht `set`, 225).
final class FitSet {
  const FitSet({
    required this.active,
    this.repetitions,
    this.weightKg,
    this.durationSeconds,
    this.category,
    this.subtype,
  });

  final bool active;
  final int? repetitions;
  final double? weightKg;
  final double? durationSeconds;
  final int? category;
  final int? subtype;
}

final class FitActivity {
  FitActivity({List<FitRecord>? records, List<FitLap>? laps, List<FitSet>? sets})
    : records = records ?? [],
      laps = laps ?? [],
      sets = sets ?? [];

  final List<FitRecord> records;
  final List<FitLap> laps;
  final List<FitSet> sets;
}

enum FitFailureKind { notFit, truncated, undefinedLocalMessage }

final class FitFailure implements Exception {
  const FitFailure(this.kind, [this.localMessage]);

  final FitFailureKind kind;
  final int? localMessage;

  @override
  String toString() => 'FitFailure(${kind.name}${localMessage == null ? '' : ', $localMessage'})';
}

final class _Field {
  const _Field(this.number, this.size);

  final int number;
  final int size;
}

final class _Definition {
  const _Definition({
    required this.global,
    required this.bigEndian,
    required this.fields,
    required this.developerBytes,
  });

  final int global;
  final bool bigEndian;
  final List<_Field> fields;
  final int developerBytes;
}

/// Liest die für die Auswertung nötigen Nachrichten aus einer FIT-Datei (Garmin FIT-Protokoll 1.0/2.0).
///
/// Unterstützt Definitions- und Datennachrichten, beide Byte-Reihenfolgen, komprimierte Zeitstempel und
/// Entwicklerfelder (werden übersprungen). Feldnummern laut FIT-SDK-Profil: `record` (20): 253 Zeit, 3 Herzfrequenz,
/// 5 Distanz (1/100 m), 6 Tempo (1/1000 m/s), 7 Leistung, 73 erweitertes Tempo; `lap` (19): 2 Start, 7 Gesamtzeit,
/// 8 Uhrzeit (1/1000 s), 9 Distanz (1/100 m), 15/16 Ø/max HF, 23 Art. Für die Detailansicht außerdem `record`: 0/1
/// Position (Semicircles), 2/78 Höhe (1/5 m − 500), 4/53 Kadenz, 13 Temperatur; `lap`: 11 kcal, 13/14 Ø/max Tempo,
/// 17 Ø Kadenz, 19/20 Ø/max Leistung, 21/22 Auf-/Abstieg.
abstract final class FitDecoder {
  static bool looksLikeFit(List<int> bytes) =>
      bytes.length >= 12 &&
      (bytes[0] == 12 || bytes[0] == 14) &&
      bytes[8] == 0x2E &&
      bytes[9] == 0x46 &&
      bytes[10] == 0x49 &&
      bytes[11] == 0x54;

  static FitActivity decode(List<int> bytes) {
    final activity = FitActivity();
    var start = 0;
    // Mehrere FIT-Dateien können aneinanderhängen.
    while (start + 12 <= bytes.length &&
        looksLikeFit(bytes.sublist(start, start + 14 <= bytes.length ? start + 14 : bytes.length))) {
      final headerSize = bytes[start];
      final dataSize = bytes[start + 4] | bytes[start + 5] << 8 | bytes[start + 6] << 16 | bytes[start + 7] << 24;
      final end = start + headerSize + dataSize < bytes.length ? start + headerSize + dataSize : bytes.length;
      _decodeMessages(bytes, start + headerSize, end, activity);
      start = end + 2; // CRC
    }
    if (start <= 0) throw const FitFailure(FitFailureKind.notFit);
    return activity;
  }

  static void _decodeMessages(List<int> bytes, int begin, int end, FitActivity activity) {
    final definitions = <int, _Definition>{};
    var position = begin;
    var lastTimestamp = 0;
    List<int> read(int count) {
      if (position + count > end) throw const FitFailure(FitFailureKind.truncated);
      final slice = bytes.sublist(position, position + count);
      position += count;
      return slice;
    }

    while (position < end) {
      final header = read(1).first;
      if (header & 0x80 != 0) {
        // Komprimierter Zeitstempel: 5 Bit Versatz zum letzten vollen Zeitstempel.
        final local = (header >> 5) & 0x3;
        final offset = header & 0x1F;
        var timestamp = (lastTimestamp & ~0x1F) + offset;
        if (offset < (lastTimestamp & 0x1F)) timestamp += 0x20;
        lastTimestamp = timestamp & 0xFFFFFFFF;
        final definition = definitions[local];
        if (definition == null) throw FitFailure(FitFailureKind.undefinedLocalMessage, local);
        final values = _readValues(definition, read);
        values[253] = lastTimestamp.toDouble();
        _apply(definition.global, values, activity);
        continue;
      }
      final local = header & 0x0F;
      if (header & 0x40 != 0) {
        // Reserviert, Byte-Reihenfolge, globale Nummer (2 Byte), Anzahl Felder.
        final fixed = read(5);
        final bigEndian = fixed[1] == 1;
        final global = bigEndian ? fixed[2] << 8 | fixed[3] : fixed[2] | fixed[3] << 8;
        final fields = <_Field>[];
        for (var index = 0; index < fixed[4]; index++) {
          final field = read(3);
          fields.add(_Field(field[0], field[1]));
        }
        var developerBytes = 0;
        if (header & 0x20 != 0) {
          final count = read(1).first;
          for (var index = 0; index < count; index++) {
            developerBytes += read(3)[1];
          }
        }
        definitions[local] = _Definition(
          global: global,
          bigEndian: bigEndian,
          fields: fields,
          developerBytes: developerBytes,
        );
      } else {
        final definition = definitions[local];
        if (definition == null) throw FitFailure(FitFailureKind.undefinedLocalMessage, local);
        final values = _readValues(definition, read);
        final timestamp = values[253];
        if (timestamp != null) lastTimestamp = timestamp.toInt();
        _apply(definition.global, values, activity);
      }
    }
  }

  /// Rohwerte je Feldnummer; ungültige Werte (alle Bits gesetzt) fehlen.
  static Map<int, double> _readValues(_Definition definition, List<int> Function(int count) read) {
    final values = <int, double>{};
    for (final field in definition.fields) {
      final raw = read(field.size);
      if (!const [1, 2, 4].contains(field.size)) continue;
      var value = 0;
      final ordered = definition.bigEndian ? raw : raw.reversed;
      for (final byte in ordered) {
        value = value << 8 | byte;
      }
      final invalid = field.size == 4 ? 0xFFFFFFFF : (1 << (8 * field.size)) - 1;
      if (value != invalid) values[field.number] = value.toDouble();
    }
    read(definition.developerBytes);
    return values;
  }

  /// Vorzeichenbehafteter 32-Bit-Wert aus dem vorzeichenlos gelesenen Rohwert.
  static double signed32(double value) => value >= 2147483648 ? value - 4294967296 : value;

  static void _apply(int global, Map<int, double> values, FitActivity activity) {
    switch (global) {
      case 20:
        final timestamp = values[253];
        if (timestamp == null) return;
        final heart = values[3];
        final speed = values[73] ?? values[6];
        final record = FitRecord(
          timestamp: timestamp,
          heartRate: heart != null && heart > 0 ? heart : null,
          speed: speed == null ? null : speed / 1000,
          power: values[7],
          distance: values[5] == null ? null : values[5]! / 100,
        );
        final altitude = values[78] ?? values[2];
        if (altitude != null) record.altitude = altitude / 5 - 500;
        final cadence = values[4];
        if (cadence != null) record.cadence = cadence + (values[53] ?? 0) / 128;
        final latitude = values[0];
        final longitude = values[1];
        if (latitude != null && longitude != null) {
          final lat = signed32(latitude) * 180 / 2147483648;
          final lon = signed32(longitude) * 180 / 2147483648;
          if (lat.abs() <= 90 && lon.abs() <= 180 && (lat != 0 || lon != 0)) {
            record
              ..latitude = lat
              ..longitude = lon;
          }
        }
        final temperature = values[13];
        if (temperature != null) record.temperature = temperature > 127 ? temperature - 256 : temperature;
        activity.records.add(record);
      case 19:
        final intensity = values[23]?.toInt();
        activity.laps.add(
          FitLap(
              timerSeconds: values[8] == null ? null : values[8]! / 1000,
              distanceMeters: values[9] == null ? null : values[9]! / 100,
              averageHeartRate: values[15],
              maxHeartRate: values[16],
              intensity: intensity != null && intensity >= 0 && intensity < FitLapIntensity.values.length
                  ? FitLapIntensity.values[intensity]
                  : null,
            )
            ..startTime = values[2]
            ..elapsedSeconds = values[7] == null ? null : values[7]! / 1000
            ..averageSpeed = values[13] == null ? null : values[13]! / 1000
            ..maxSpeed = values[14] == null ? null : values[14]! / 1000
            ..ascentMeters = values[21]
            ..descentMeters = values[22]
            ..averageCadence = values[17]
            ..averagePower = values[19]
            ..maxPower = values[20]
            ..calories = values[11],
        );
      case 225:
        activity.sets.add(
          FitSet(
            active: values[5] == 1,
            repetitions: values[3]?.toInt(),
            weightKg: values[4] == null ? null : values[4]! / 16,
            durationSeconds: values[0] == null ? null : values[0]! / 1000,
            category: values[7]?.toInt(),
            subtype: values[8]?.toInt(),
          ),
        );
    }
  }
}

enum ZipFailureKind { notAZip, noFitEntry, unsupportedMethod, truncated }

final class ZipFailure implements Exception {
  const ZipFailure(this.kind, [this.method]);

  final ZipFailureKind kind;
  final int? method;

  @override
  String toString() => 'ZipFailure(${kind.name})';
}

final class _ZipEntry {
  const _ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.localHeaderOffset,
  });

  final String name;
  final int method;
  final int compressedSize;
  final int localHeaderOffset;
}

/// Liest die FIT-Datei aus Garmins Download (`/download-service/files/activity/{id}` liefert ein ZIP mit einer
/// `.fit`-Datei). Unterstützt die beiden üblichen Verfahren „gespeichert“ (0) und „Deflate“ (8).
abstract final class ZipArchive {
  /// FIT-Inhalt aus einem ZIP; ist [data] schon eine FIT-Datei, kommt sie unverändert zurück.
  static List<int> fitData(List<int> data) {
    if (FitDecoder.looksLikeFit(data)) return data;
    if (data.length < 22 || data[0] != 0x50 || data[1] != 0x4B) throw const ZipFailure(ZipFailureKind.notAZip);
    final entries = _centralDirectory(data);
    final entry = entries.where((entry) => entry.name.toLowerCase().endsWith('.fit')).firstOrNull;
    if (entry == null) throw const ZipFailure(ZipFailureKind.noFitEntry);
    return _extract(entry, data);
  }

  static List<_ZipEntry> _centralDirectory(List<int> bytes) {
    // Ende des zentralen Verzeichnisses rückwärts suchen (Kommentar am Ende ist bis 64 KB lang).
    final lowest = bytes.length - 22 - 65535 > 0 ? bytes.length - 22 - 65535 : 0;
    var end = bytes.length - 22;
    while (end >= lowest &&
        !(bytes[end] == 0x50 && bytes[end + 1] == 0x4B && bytes[end + 2] == 5 && bytes[end + 3] == 6)) {
      end -= 1;
    }
    if (end < lowest) throw const ZipFailure(ZipFailureKind.notAZip);
    final count = _uint16(bytes, end + 10);
    var offset = _uint32(bytes, end + 16);
    final entries = <_ZipEntry>[];
    for (var index = 0; index < count; index++) {
      if (offset + 46 > bytes.length || _uint32(bytes, offset) != 0x02014B50) {
        throw const ZipFailure(ZipFailureKind.truncated);
      }
      final nameLength = _uint16(bytes, offset + 28);
      final extraLength = _uint16(bytes, offset + 30);
      final commentLength = _uint16(bytes, offset + 32);
      if (offset + 46 + nameLength > bytes.length) throw const ZipFailure(ZipFailureKind.truncated);
      entries.add(
        _ZipEntry(
          name: utf8.decode(bytes.sublist(offset + 46, offset + 46 + nameLength), allowMalformed: true),
          method: _uint16(bytes, offset + 10),
          compressedSize: _uint32(bytes, offset + 20),
          localHeaderOffset: _uint32(bytes, offset + 42),
        ),
      );
      offset += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
  }

  static List<int> _extract(_ZipEntry entry, List<int> bytes) {
    final header = entry.localHeaderOffset;
    if (header + 30 > bytes.length || _uint32(bytes, header) != 0x04034B50) {
      throw const ZipFailure(ZipFailureKind.truncated);
    }
    final start = header + 30 + _uint16(bytes, header + 26) + _uint16(bytes, header + 28);
    final end = start + entry.compressedSize;
    if (end > bytes.length) throw const ZipFailure(ZipFailureKind.truncated);
    final payload = bytes.sublist(start, end);
    return switch (entry.method) {
      0 => payload,
      8 => InflateData.decompress(payload),
      _ => throw ZipFailure(ZipFailureKind.unsupportedMethod, entry.method),
    };
  }

  static int _uint16(List<int> bytes, int offset) => bytes[offset] | bytes[offset + 1] << 8;

  static int _uint32(List<int> bytes, int offset) =>
      bytes[offset] | bytes[offset + 1] << 8 | bytes[offset + 2] << 16 | bytes[offset + 3] << 24;
}

import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/season_plan.dart';
import '../coach/trends.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import 'season_schedule.dart';

/// Art eines Testwerts.
enum TestKind implements RawEnum {
  /// Sekunden je 100 m
  css,

  /// Watt
  ftp,

  /// Lauf-Schwellenpace, Sekunden je km
  threshold,

  /// Halbmarathon-Testzeit, Sekunden
  halfMarathon,

  /// Rad-Schnitt für die 94 km, km/h
  bikeSpeed,

  /// Renn-Laufpace nach dem Rad, Sekunden je km
  racePace;

  @override
  String get rawValue => name;

  String get label => switch (this) {
    css => 'CSS',
    ftp => 'FTP',
    threshold => 'Schwellenpace',
    halfMarathon => 'Halbmarathon',
    bikeSpeed => 'Rad-Schnitt',
    racePace => 'Renn-Laufpace',
  };

  static TestKind? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Ein eingetragener Testwert mit Datum – Grundlage der Verläufe (CSS, FTP, Schwelle) und der Aktualität.
final class TestRecord {
  const TestRecord({required this.kind, required this.value, required this.day});

  final TestKind kind;
  final double value;
  final CalendarDay day;

  String get id => '${kind.rawValue}-${day.iso}';

  Map<String, Object?> toJson() => {'kind': kind.rawValue, 'value': value, 'day': day.toJson()};

  static TestRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = TestKind.fromRaw(json['kind']);
    final value = jsonDouble(json['value']);
    final rawDay = json['day'];
    final day = rawDay is Map<String, Object?> ? _day(rawDay) : null;
    if (kind == null || value == null || day == null) return null;
    return TestRecord(kind: kind, value: value, day: day);
  }

  static CalendarDay? _day(Map<String, Object?> json) {
    try {
      return CalendarDay.fromJson(json);
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TestRecord && other.kind == kind && other.value == value && other.day == day;

  @override
  int get hashCode => Object.hash(kind, value, day);

  @override
  String toString() => 'TestRecord($kind, $value, $day)';
}

abstract final class TestHistory {
  /// Neuer Eintrag ersetzt einen gleichartigen vom selben Tag.
  static List<TestRecord> adding(TestRecord record, List<TestRecord> records) =>
      [...records.where((item) => item.id != record.id), record]..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        return byDay != 0 ? byDay : a.kind.rawValue.compareTo(b.kind.rawValue);
      });

  static TestRecord? latest(TestKind kind, List<TestRecord> records) {
    TestRecord? result;
    for (final record in records.where((item) => item.kind == kind)) {
      if (result == null || result.day < record.day) result = record;
    }
    return result;
  }

  static List<DayValue> values(TestKind kind, List<TestRecord> records) =>
      [for (final record in records.where((item) => item.kind == kind)) DayValue(day: record.day, value: record.value)]
        ..sort((a, b) => a.day.compareTo(b.day));
}

/// Eine Zeile einer Tempo- oder Zonentabelle.
final class PaceRow {
  const PaceRow({required this.label, required this.value, required this.use, this.isKey = false});

  final String label;
  final String value;
  final String use;
  final bool isKey;

  String get id => label;

  @override
  bool operator ==(Object other) =>
      other is PaceRow && other.label == label && other.value == value && other.use == use && other.isKey == isKey;

  @override
  int get hashCode => Object.hash(label, value, use, isKey);

  @override
  String toString() => 'PaceRow($label, $value, $use, $isKey)';
}

/// Schwimm-Paces aus der CSS (Tabelle `swim_paces` im Altbestand).
abstract final class SwimPaces {
  static List<PaceRow> rows(int css) {
    const t = PlanTokens.mmss;
    return [
      PaceRow(label: 'Tempo (50er)', value: '${t(css - 4)}–${t(css - 2)}', use: 'kurze, schnelle Wiederholungen'),
      PaceRow(label: 'Schwelle (100er)', value: t(css), use: 'CSS-Serien', isKey: true),
      PaceRow(label: '200er', value: '${t(css + 1)}–${t(css + 2)}', use: 'CSS 200er'),
      PaceRow(label: '400er', value: '${t(css + 3)}–${t(css + 4)}', use: 'CSS 400er'),
      PaceRow(label: 'Ausdauer / Technik', value: '${t(css + 4)}–${t(css + 6)}', use: 'lange Serien'),
      PaceRow(label: 'Rennen 1,9 km', value: '${t(css)}–${t(css + 3)}', use: 'Almere'),
    ];
  }

  /// CSS = (Zeit 400 m − Zeit 200 m) ÷ 2, in Sekunden je 100 m (Wakayoshi 1992). `null` bei unplausiblen Zeiten.
  static int? css({required int time400, required int time200}) {
    if (time400 <= time200 || time200 <= 0) return null;
    final css = ((time400 - time200) / 2).round();
    return css >= 60 && css <= 300 ? css : null;
  }
}

/// Rad-Zonen in % FTP (Tabelle `bike_zones` im Altbestand).
abstract final class BikeZones {
  static List<PaceRow> rows(int ftp) {
    String watts(int low, int high) => '${(ftp * low / 100).round()}–${(ftp * high / 100).round()} W';
    return [
      PaceRow(label: 'Z1 Erholung', value: watts(0, 55), use: '0–55 % FTP'),
      PaceRow(label: 'Z2 Grundlage', value: watts(56, 75), use: '56–75 % FTP'),
      PaceRow(label: 'Z3 Tempo', value: watts(76, 87), use: '76–87 % FTP'),
      PaceRow(label: 'Sweet Spot', value: watts(88, 94), use: '88–94 % FTP'),
      PaceRow(label: 'Z4 Schwelle', value: watts(95, 105), use: '95–105 % FTP'),
      PaceRow(label: 'Z5 VO2max', value: watts(106, 120), use: '106–120 % FTP'),
      PaceRow(label: 'Renntempo', value: watts(75, 78), use: '75–78 % FTP · Almere', isKey: true),
    ];
  }
}

/// Lauf-Paces (Tabelle `run_paces` im Altbestand).
abstract final class RunPaces {
  static List<PaceRow> rows(SeasonConfig config) {
    final tokens = PlanTokens(config);
    const t = PlanTokens.mmss;
    return [
      PaceRow(label: 'Locker (Z2)', value: tokens.easyRange, use: 'Z2-Läufe, Longruns – Herzfrequenz hat Vorrang'),
      PaceRow(label: 'Marathon', value: t(config.marathonPaceSecondsPerKm), use: 'Marathontempo-Abschnitte'),
      PaceRow(label: 'Renn-Lauf', value: t(config.racePaceSecondsPerKm), use: 'Lauf nach dem Rad'),
      PaceRow(
        label: 'Schwelle',
        value: t(config.thresholdPaceSecondsPerKm),
        use: '2–4-km-Intervalle, Tempodauerlauf',
        isKey: true,
      ),
      PaceRow(label: 'Intervall', value: tokens.intervalRange, use: '4×4 min – 90–95 % HFmax hat Vorrang'),
    ];
  }
}

/// Ein Abschnitt der Rennschätzung.
final class RaceLeg {
  const RaceLeg({required this.label, required this.assumption, required this.minutes});

  final String label;
  final String assumption;
  final double minutes;

  String get id => label;

  @override
  bool operator ==(Object other) =>
      other is RaceLeg && other.label == label && other.assumption == assumption && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(label, assumption, minutes);
}

/// Wie aktuell der letzte Test einer Disziplin ist.
final class RaceFreshness {
  const RaceFreshness({required this.label, required this.age});

  final String label;

  /// Tage seit dem letzten Test, `null` = nie getestet
  final int? age;

  String get id => label;
  bool get isFresh => age != null && age! <= RaceEstimate.maxAgeDays;

  @override
  bool operator ==(Object other) => other is RaceFreshness && other.label == label && other.age == age;

  @override
  int get hashCode => Object.hash(label, age);
}

/// Geschätzte Zeit für Almere aus den Benchmarks (Karte „Zielzeit Almere“ im Altbestand).
final class RaceEstimate {
  factory RaceEstimate({required SeasonConfig config, required List<TestRecord> tests, required CalendarDay today}) {
    final swim = config.cssSecondsPer100m.toDouble();
    final bike = math.max(config.raceBikeSpeedKmh, 1.0);
    final run = config.racePaceSecondsPerKm.toDouble();
    final swimMinutes = swim * swimMeters / 100 / 60;
    final bikeMinutes = bikeKilometers / bike * 60;
    final runMinutes = run * runKilometers / 60;
    final legs = [
      RaceLeg(label: 'Schwimmen 1,9 km', assumption: '${PlanTokens.mmss(swim.toInt())} /100 m', minutes: swimMinutes),
      const RaceLeg(label: 'Wechsel 1', assumption: 'Annahme', minutes: transition1),
      RaceLeg(label: 'Rad 94 km', assumption: '${GermanFormat.decimal(bike)} km/h', minutes: bikeMinutes),
      const RaceLeg(label: 'Wechsel 2', assumption: 'Annahme', minutes: transition2),
      RaceLeg(label: 'Lauf 21,1 km', assumption: '${PlanTokens.mmss(run.toInt())} /km', minutes: runMinutes),
    ];
    int? age(TestKind kind) => TestHistory.latest(kind, tests)?.day.daysUntil(today);
    return RaceEstimate._(
      legs: legs,
      totalMinutes: legs.fold(0, (sum, leg) => sum + leg.minutes),
      freshness: [
        RaceFreshness(label: 'Schwimmen', age: age(TestKind.css)),
        RaceFreshness(label: 'Rad', age: age(TestKind.bikeSpeed) ?? age(TestKind.ftp)),
        RaceFreshness(label: 'Lauf', age: age(TestKind.racePace) ?? age(TestKind.threshold)),
      ],
      savings: (
        swim: swimMeters / 100 * 5 / 60,
        bike: bikeMinutes - bikeKilometers / (bike + 1) * 60,
        run: runKilometers * 10 / 60,
      ),
    );
  }

  const RaceEstimate._({
    required this.legs,
    required this.totalMinutes,
    required this.freshness,
    required this.savings,
  });

  static const maxAgeDays = 56;
  static const corridorLower = 330.0;
  static const corridorUpper = 360.0;
  static const swimMeters = 1900.0;
  static const bikeKilometers = 94.0;
  static const runKilometers = 21.1;
  static const transition1 = 3.0;
  static const transition2 = 2.0;

  final List<RaceLeg> legs;
  final double totalMinutes;
  final List<RaceFreshness> freshness;

  /// Ersparnis in Minuten: Schwimmen −5 s/100 m, Rad +1 km/h, Lauf −10 s/km
  final ({double swim, double bike, double run}) savings;

  bool get allFresh => freshness.every((item) => item.isFresh);

  String get corridorText {
    if (totalMinutes < corridorLower) return 'Unter dem Zielkorridor 5:30–6:00.';
    if (totalMinutes <= corridorUpper) return 'Im Zielkorridor 5:30–6:00.';
    return '${(totalMinutes - corridorUpper).round()} min über dem Zielkorridor.';
  }

  /// „5:42“ für Minuten als Stunden:Minuten.
  static String hoursMinutes(double minutes) {
    final rounded = minutes.round();
    return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')}';
  }
}

/// Eine Woche der Marathon-Leiter.
final class LadderWeek {
  const LadderWeek({
    required this.sunday,
    required this.longRun,
    required this.quality,
    required this.isCurrent,
    required this.isPast,
  });

  final CalendarDay sunday;
  final String longRun;
  final String quality;
  final bool isCurrent;
  final bool isPast;

  String get id => sunday.iso;

  @override
  String toString() => 'LadderWeek($sunday, $longRun, $quality, current: $isCurrent, past: $isPast)';
}

/// Marathon-Ausblick (Reiter „Marathon“ im Altbestand).
final class MarathonOutlook {
  factory MarathonOutlook({
    required SeasonConfig config,
    required int? halfMarathonSeconds,
    required SeasonSchedule? schedule,
    required CalendarDay today,
  }) {
    final targetSeconds = (config.marathonPaceSecondsPerKm * marathonKilometers).round();
    ({int low, int high})? predicted;
    var targetTooFast = false;
    if (halfMarathonSeconds != null && halfMarathonSeconds > 0) {
      final low = (halfMarathonSeconds * halfMarathonFactorLower).round();
      final high = (halfMarathonSeconds * halfMarathonFactorUpper).round();
      predicted = (low: low, high: high);
      targetTooFast = config.marathonPaceSecondsPerKm < (low / marathonKilometers).floorToDouble();
    }
    final monday = today.adding(-today.weekdayIndex);
    final ladder = <LadderWeek>[];
    for (final week in schedule?.weeks ?? const <PlanWeek>[]) {
      if (week.ph != 'Marathon-Aufbau' && week.ph != 'Marathon-Taper') continue;
      final start = week.monday;
      if (start == null) continue;
      final sunday = start.adding(6);
      final String longRun;
      if (week.key == 'marathon') {
        longRun = '🏁 Marathon';
      } else if (week.lr == 21.1) {
        longRun = 'Halbmarathon-Test';
      } else {
        longRun = week.lr > 0 ? '${GermanFormat.decimal(week.lr)} km' : '–';
      }
      ladder.add(
        LadderWeek(
          sunday: sunday,
          longRun: longRun,
          quality: week.qc,
          isCurrent: start == monday,
          isPast: sunday < today,
        ),
      );
    }
    return MarathonOutlook._(
      daysToRace: today.daysUntil(config.marathonDate),
      targetSeconds: targetSeconds,
      predicted: predicted,
      targetTooFast: targetTooFast,
      ladder: ladder,
    );
  }

  const MarathonOutlook._({
    required this.daysToRace,
    required this.targetSeconds,
    required this.predicted,
    required this.targetTooFast,
    required this.ladder,
  });

  static const marathonKilometers = 42.195;

  /// Praxiswert: Marathonzeit ≈ Halbmarathon × 2,15–2,2 (für Debütanten vorsichtiger als Riegel × 2,09).
  static const halfMarathonFactorLower = 2.15;
  static const halfMarathonFactorUpper = 2.2;

  final int daysToRace;
  final int targetSeconds;
  final ({int low, int high})? predicted;

  /// Zielpace schneller als der Halbmarathon-Test hergibt
  final bool targetTooFast;
  final List<LadderWeek> ladder;

  static String hoursMinutesFromSeconds(int seconds) =>
      '${seconds ~/ 3600}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}';

  static String pace(double seconds) => PlanTokens.mmss(seconds.toInt());
}

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../garmin/garmin_profile.dart';
import '../json/json_value.dart';
import '../util/enum_codec.dart';

/// Eine Herzfrequenzzone mit Grenzen in Schlägen pro Minute (`null` = offen).
final class HeartRateZone {
  HeartRateZone({required this.name, required this.use, this.low, this.high});

  final String name;
  final String use;
  int? low;
  int? high;

  String get rangeText => switch ((low, high)) {
    (null, final high?) => 'bis $high',
    (final low?, null) => 'ab $low',
    (final low?, final high?) => '$low–$high',
    _ => '–',
  };

  @override
  bool operator ==(Object other) =>
      other is HeartRateZone && other.name == name && other.use == use && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(name, use, low, high);

  @override
  String toString() => '$name $rangeText';
}

/// Zonen, wie sie auf der Uhr eingestellt sind (`/biometric-service/heartRateZones/v2`).
final class WatchZones {
  const WatchZones({
    required this.sport,
    required this.method,
    this.maxHeartRate,
    this.restingHeartRate,
    this.lactateThreshold,
    required this.zones,
  });

  final String sport;

  /// `HR_MAX`, `HR_RESERVE` oder `LACTATE_THRESHOLD`.
  final String method;
  final int? maxHeartRate;
  final int? restingHeartRate;
  final int? lactateThreshold;
  final List<HeartRateZone> zones;

  String get methodText {
    final upper = method.toUpperCase();
    if (upper.contains('MAX')) return '% HFmax';
    if (upper.contains('RESERVE')) return 'HF-Reserve';
    if (upper.contains('LACTATE') || upper.contains('THRESHOLD')) return '% Laktatschwelle';
    return method;
  }
}

/// Schwellenbasierte Coach-Zonen einer Sportart.
final class CoachZones {
  const CoachZones({
    required this.sport,
    required this.lactateThreshold,
    required this.source,
    required this.isApproximate,
    required this.zones,
  });

  final ActivitySport sport;
  final int? lactateThreshold;
  final String source;

  /// Schwelle ist geschätzt oder aus der anderen Sportart übernommen.
  final bool isApproximate;
  final List<HeartRateZone> zones;

  /// Obergrenze „locker“ (Z2).
  int? get easyLimit => zones.length > 1 ? zones[1].high : null;

  /// Z5a–c zusammengefasst – fünf Felder bleiben auf dem Telefon lesbar.
  List<HeartRateZone> get fiveZones {
    final top = zones.where((zone) => zone.name.startsWith('Z5')).toList();
    final base = zones.where((zone) => !zone.name.startsWith('Z5')).take(4).toList();
    if (top.isNotEmpty) base.add(HeartRateZone(name: 'Z5', use: 'Schwelle+', low: top.first.low, high: top.last.high));
    return base;
  }
}

/// Zeitanteile locker / mittel / hart.
final class IntensityShare {
  const IntensityShare._({
    required this.minutes,
    required this.zonePercent,
    required this.easyPercent,
    required this.moderatePercent,
    required this.hardPercent,
  });

  final int minutes;
  final List<int> zonePercent;
  final int easyPercent;
  final int moderatePercent;
  final int hardPercent;

  static IntensityShare? fromSeconds(List<double> seconds) {
    final total = seconds.sum;
    if (total <= 0 || seconds.length != 5) return null;
    int percent(double value) => (value / total * 100).round();
    return IntensityShare._(
      minutes: (total / 60).round(),
      zonePercent: seconds.map(percent).toList(),
      easyPercent: percent(seconds[0] + seconds[1]),
      moderatePercent: percent(seconds[2]),
      hardPercent: percent(seconds[3] + seconds[4]),
    );
  }
}

final class ZoneWeek {
  const ZoneWeek({required this.monday, this.run, this.bike});

  final CalendarDay monday;
  final IntensityShare? run;
  final IntensityShare? bike;
}

/// Verteilung der Zeit in den Zonen der Uhr, gesamt und je Woche.
final class ZoneDistribution {
  const ZoneDistribution({
    required this.weeks,
    this.run,
    this.bike,
    required this.perWeek,
    required this.withoutZoneData,
  });

  final int weeks;
  final IntensityShare? run;
  final IntensityShare? bike;
  final List<ZoneWeek> perWeek;
  final int withoutZoneData;
}

/// Ergebnis der Zonenberechnung – wie `hr_zones.build()` im Altbestand.
final class HeartRateZoneReport {
  const HeartRateZoneReport({
    required this.maxHeartRate,
    required this.maxHeartRateSource,
    required this.observedConfirmedMax,
    required this.observedPeak,
    required this.observedCount,
    required this.watch,
    required this.run,
    required this.bike,
    required this.distribution,
    required this.hints,
  });

  final int? maxHeartRate;
  final String maxHeartRateSource;
  final int? observedConfirmedMax;
  final int? observedPeak;
  final int observedCount;
  final List<WatchZones> watch;
  final CoachZones run;
  final CoachZones bike;
  final ZoneDistribution distribution;
  final List<String> hints;
}

/// Eigene Werte aus den Einstellungen (0 oder `null` = automatisch).
final class HeartRateOverrides {
  const HeartRateOverrides({this.maxHeartRate, this.thresholdRun, this.thresholdBike});

  final int? maxHeartRate;
  final int? thresholdRun;
  final int? thresholdBike;

  int? valid(int? value) => value != null && value >= 40 ? value : null;

  Map<String, Object?> toJson() => {
    'maxHeartRate': ?maxHeartRate,
    'thresholdRun': ?thresholdRun,
    'thresholdBike': ?thresholdBike,
  };

  static HeartRateOverrides fromJson(Object? json) {
    if (json is! Map) return const HeartRateOverrides();
    return HeartRateOverrides(
      maxHeartRate: jsonInt(json['maxHeartRate']),
      thresholdRun: jsonInt(json['thresholdRun']),
      thresholdBike: jsonInt(json['thresholdBike']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HeartRateOverrides &&
      other.maxHeartRate == maxHeartRate &&
      other.thresholdRun == thresholdRun &&
      other.thresholdBike == thresholdBike;

  @override
  int get hashCode => Object.hash(maxHeartRate, thresholdRun, thresholdBike);
}

/// Herzfrequenzzonen nach dem Altbestand (`hr_zones.py`).
///
/// - Uhr-Zonen: unverändert aus Garmin Connect.
/// - Coach-Zonen: Friel (% der Laktatschwellen-HF), Anker Schwelle statt HFmax (Esteve-Lanao 2007).
/// - HFmax: eigener Wert > bestätigter Messwert (zweite Einheit höchstens 3 Schläge darunter) > Garmin.
///   Altersformeln weichen um ±11 Schläge ab (Nes 2013) und werden nicht benutzt.
/// - Verteilung: Zeit in den Uhr-Zonen der letzten 4 Wochen; Richtwert ca. 80 % locker (Seiler).
abstract final class HeartRateZoneCalculator {
  static const confirmTolerance = 3;
  static const plausibleMin = 140;
  static const plausibleMax = 230;
  static const estimateFactor = 0.90;
  static const ratioLow = 0.80;
  static const ratioHigh = 0.97;

  /// (Name, Verwendung, Untergrenze % LTHR, Obergrenze % LTHR) nach Friel.
  static const friel = <ActivitySport, List<(String, String, double?, double?)>>{
    ActivitySport.run: [
      ('Z1', 'Erholung', null, 85),
      ('Z2', 'Grundlagenausdauer', 85, 89),
      ('Z3', 'Tempo', 90, 94),
      ('Z4', 'Unterschwelle', 95, 99),
      ('Z5a', 'Schwelle', 100, 102),
      ('Z5b', 'VO₂max', 103, 106),
      ('Z5c', 'Anaerob', 106, null),
    ],
    ActivitySport.bike: [
      ('Z1', 'Erholung', null, 81),
      ('Z2', 'Grundlagenausdauer', 81, 89),
      ('Z3', 'Tempo', 90, 93),
      ('Z4', 'Unterschwelle', 94, 99),
      ('Z5a', 'Schwelle', 100, 102),
      ('Z5b', 'VO₂max', 103, 106),
      ('Z5c', 'Anaerob', 106, null),
    ],
  };

  static List<HeartRateZone> frielZones({required int threshold, required ActivitySport sport, int? maxHeartRate}) {
    final lthr = threshold.toDouble();
    final rows = [
      for (final (name, use, low, high) in friel[sport] ?? friel[ActivitySport.run]!)
        HeartRateZone(
          name: name,
          use: use,
          low: low == null ? null : (lthr * low / 100 - 1e-9).ceil(),
          high: high == null ? null : (lthr * high / 100 + 1e-9).floor(),
        ),
    ];
    // Lückenlos: Obergrenze = nächste Untergrenze - 1
    for (var index = 0; index < rows.length - 1; index++) {
      final next = rows[index + 1].low;
      if (next != null) rows[index].high = next - 1;
    }
    if (maxHeartRate != null && rows.isNotEmpty) rows.last.high = maxHeartRate;
    return rows;
  }

  /// Liest die Uhr-Zonen (Felder `zone1Floor` … `zone5Floor`, `maxHeartRateUsed`, `trainingMethod`).
  static List<WatchZones> watchZones(JsonValue json) {
    final List<Map<String, JsonValue>> entries;
    if (json.arrayValue case final values?) {
      entries = values.map((value) => value.objectValue).nonNulls.toList();
    } else if (json.objectValue case final object?) {
      entries = [object];
    } else {
      entries = [];
    }
    final letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
    final result = <WatchZones>[];
    for (final entry in entries) {
      final floors = <int, int>{};
      int? maxHR;
      int? restHR;
      int? lthr;
      for (final MapEntry(:key, :value) in entry.entries) {
        final normalized = key.toLowerCase().split('').where(letterOrDigit.hasMatch).join();
        final number = value.doubleValue;
        if (number == null) continue;
        if (normalized.startsWith('zone') && normalized.endsWith('floor') && normalized.length > 9) {
          final digit = int.tryParse(normalized.substring(4, normalized.length - 5));
          if (digit != null) {
            floors[digit] = number.truncate();
            continue;
          }
        }
        if (normalized.contains('max') && normalized.contains('heartrate')) {
          maxHR ??= number.truncate();
        } else if (normalized.contains('rest') && normalized.contains('heartrate')) {
          restHR ??= number.truncate();
        } else if (normalized.contains('lactate') && normalized.contains('heartrate')) {
          lthr ??= number.truncate();
        }
      }
      if (![1, 2, 3, 4, 5].every(floors.containsKey)) continue;
      result.add(
        WatchZones(
          sport: entry['sport']?.stringValue ?? 'DEFAULT',
          method: entry['trainingMethod']?.stringValue ?? entry['method']?.stringValue ?? '',
          maxHeartRate: maxHR,
          restingHeartRate: restHR,
          lactateThreshold: lthr != null && lthr > 0 ? lthr : null,
          zones: [
            for (var index = 1; index <= 5; index++)
              HeartRateZone(
                name: 'Z$index',
                use: '',
                low: floors[index],
                high: index < 5 ? floors[index + 1]! - 1 : maxHR,
              ),
          ],
        ),
      );
    }
    return result;
  }

  /// Höchster bestätigter Puls der letzten 12 Monate aus Lauf- und Radeinheiten (Schwimmen und Kraft haben
  /// unzuverlässigen optischen Puls).
  static ({int? confirmed, int? peak, int count}) observedMax(
    List<GarminActivity> activities, {
    required CalendarDay today,
  }) {
    final cutoff = today.adding(-365);
    final values =
        activities
            .where(
              (activity) =>
                  (activity.sport == ActivitySport.run || activity.sport == ActivitySport.bike) &&
                  activity.day != null &&
                  activity.day! >= cutoff,
            )
            .map((activity) => activity.maxHeartRate?.round())
            .nonNulls
            .where((value) => value >= plausibleMin && value <= plausibleMax)
            .toList()
          ..sort((a, b) => b.compareTo(a));
    int? confirmed;
    for (var index = 0; index < values.length - 1; index++) {
      if (values[index] - values[index + 1] <= confirmTolerance) {
        confirmed = values[index];
        break;
      }
    }
    return (confirmed: confirmed, peak: values.firstOrNull, count: values.length);
  }

  static HeartRateZoneReport report({
    required List<GarminActivity> activities,
    required JsonValue? watchZonesJSON,
    required GarminProfile? profile,
    required HeartRateOverrides overrides,
    required CalendarDay today,
  }) {
    final watch = watchZonesJSON == null ? <WatchZones>[] : watchZones(watchZonesJSON);
    final observed = observedMax(activities, today: today);
    final garminMax = watch.map((zones) => zones.maxHeartRate).nonNulls.firstOrNull;
    int? maxHR;
    var maxSource = 'unbekannt';
    final own = overrides.valid(overrides.maxHeartRate);
    if (own != null) {
      maxHR = own;
      maxSource = 'eigener Wert';
    } else {
      // Der größere Wert gewinnt; bei Gleichstand der Messwert (erster Kandidat, wie `max(by:)` in Swift).
      (int, String)? best;
      for (final candidate in [
        (observed.confirmed, 'bestätigter Messwert (12 Monate)'),
        (garminMax, 'Garmin-Einstellung'),
      ]) {
        final value = candidate.$1;
        if (value == null) continue;
        if (best == null || value > best.$1) best = (value, candidate.$2);
      }
      if (best != null) {
        maxHR = best.$1;
        maxSource = best.$2;
      } else if (observed.peak != null) {
        maxHR = observed.peak;
        maxSource = 'unbestätigter Höchstwert';
      }
    }
    final profileThreshold = profile?.lactateThresholdHeartRate?.round();
    final garminThreshold = (profileThreshold != null && profileThreshold >= 80 && profileThreshold <= 220)
        ? profileThreshold
        : watch.map((zones) => zones.lactateThreshold).nonNulls.firstOrNull;
    CoachZones coach(ActivitySport sport) {
      final ownRun = overrides.valid(overrides.thresholdRun);
      final ownValue = sport == ActivitySport.run ? ownRun : overrides.valid(overrides.thresholdBike);
      final (int?, String, bool) choice;
      if (ownValue != null) {
        choice = (ownValue, 'eigener Wert', false);
      } else if (sport == ActivitySport.run && garminThreshold != null) {
        choice = (garminThreshold, 'Garmin (Laktatschwelle)', false);
      } else if (sport == ActivitySport.bike && ownRun != null) {
        choice = (ownRun, 'eigener Laufwert als Näherung', true);
      } else if (sport == ActivitySport.bike && garminThreshold != null) {
        choice = (garminThreshold, 'Garmin-Laufwert als Näherung', true);
      } else if (maxHR != null) {
        choice = ((maxHR * estimateFactor).round(), 'Schätzung (${(estimateFactor * 100).toInt()} % HFmax)', true);
      } else {
        choice = (null, 'unbekannt', true);
      }
      final threshold = choice.$1;
      return CoachZones(
        sport: sport,
        lactateThreshold: threshold,
        source: choice.$2,
        isApproximate: choice.$3,
        zones: threshold == null ? const [] : frielZones(threshold: threshold, sport: sport, maxHeartRate: maxHR),
      );
    }

    final run = coach(ActivitySport.run);
    final bike = coach(ActivitySport.bike);
    final zoneDistribution = distribution(activities, today: today);
    return HeartRateZoneReport(
      maxHeartRate: maxHR,
      maxHeartRateSource: maxSource,
      observedConfirmedMax: observed.confirmed,
      observedPeak: observed.peak,
      observedCount: observed.count,
      watch: watch,
      run: run,
      bike: bike,
      distribution: zoneDistribution,
      hints: _hints(
        run: run,
        bike: bike,
        maxHR: maxHR,
        garminMax: garminMax,
        observed: observed,
        overrides: overrides,
        watch: watch,
        distribution: zoneDistribution,
        activities: activities,
        today: today,
      ),
    );
  }

  static ZoneDistribution distribution(List<GarminActivity> activities, {required CalendarDay today, int weeks = 4}) {
    final start = today.adding(-weeks * 7);
    final total = <ActivitySport, List<double>>{};
    final perWeek = <CalendarDay, Map<ActivitySport, List<double>>>{};
    var missing = 0;
    List<double> add(List<double>? base, List<double> values) => [
      for (var index = 0; index < 5; index++) (base?[index] ?? 0) + values[index],
    ];
    for (final activity in activities) {
      if (activity.sport != ActivitySport.run && activity.sport != ActivitySport.bike) continue;
      final day = activity.day;
      if (day == null || day < start || day > today) continue;
      final seconds = activity.secondsInZones;
      if (seconds == null) {
        missing += 1;
        continue;
      }
      total[activity.sport] = add(total[activity.sport], seconds);
      final monday = day.adding(-day.weekdayIndex);
      final week = perWeek.putIfAbsent(monday, () => {});
      week[activity.sport] = add(week[activity.sport], seconds);
    }
    final mondays = perWeek.keys.toList()..sort((a, b) => b.compareTo(a));
    IntensityShare? share(List<double>? seconds) => seconds == null ? null : IntensityShare.fromSeconds(seconds);
    return ZoneDistribution(
      weeks: weeks,
      run: share(total[ActivitySport.run]),
      bike: share(total[ActivitySport.bike]),
      perWeek: [
        for (final monday in mondays)
          ZoneWeek(
            monday: monday,
            run: share(perWeek[monday]![ActivitySport.run]),
            bike: share(perWeek[monday]![ActivitySport.bike]),
          ),
      ],
      withoutZoneData: missing,
    );
  }

  /// Näherung: jede Einheit (ab 15 min) nach ihrer Durchschnitts-HF einer Coach-Zone zuordnen.
  static IntensityShare? averageHeartRateShare(
    List<GarminActivity> activities, {
    required CoachZones coach,
    required CalendarDay today,
    int weeks = 4,
  }) {
    if (coach.zones.length < 3) return null;
    final easy = coach.zones[1].high;
    final moderate = coach.zones[2].high;
    if (easy == null || moderate == null) return null;
    final start = today.adding(-weeks * 7);
    final seconds = <double>[0, 0, 0, 0, 0];
    for (final activity in activities.where((activity) => activity.sport == coach.sport)) {
      final day = activity.day;
      final average = activity.averageHeartRate;
      final duration = activity.durationSeconds;
      if (day == null || day < start || day > today || average == null || duration == null || duration < 15 * 60) {
        continue;
      }
      final index = average <= easy ? 0 : (average <= moderate ? 2 : 3);
      seconds[index] += duration;
    }
    return IntensityShare.fromSeconds(seconds);
  }

  static List<String> _hints({
    required CoachZones run,
    required CoachZones bike,
    required int? maxHR,
    required int? garminMax,
    required ({int? confirmed, int? peak, int count}) observed,
    required HeartRateOverrides overrides,
    required List<WatchZones> watch,
    required ZoneDistribution distribution,
    required List<GarminActivity> activities,
    required CalendarDay today,
  }) {
    final hints = <String>[];
    for (final zones in [run, bike]) {
      final lthr = zones.lactateThreshold;
      if (lthr == null || maxHR == null) continue;
      final ratio = lthr / maxHR;
      if (ratio < ratioLow || ratio > ratioHigh) {
        final label = zones.sport == ActivitySport.run ? 'Lauf' : 'Rad';
        hints.add(
          '$label-Schwelle $lthr liegt bei ${(ratio * 100).round()} % der HFmax $maxHR – außerhalb des üblichen '
          'Bereichs von 80–97 %. HFmax oder Schwelle prüfen.',
        );
      }
    }
    if (run.isApproximate && run.lactateThreshold != null) {
      hints.add(
        'Die Lauf-Schwelle ist nur geschätzt. Genauer: 30 Minuten Lauf am Anschlag, Durchschnitts-HF der letzten 20 '
        'Minuten = Schwelle (Friel-Feldtest), dann unter Einstellungen eintragen.',
      );
    }
    if (bike.isApproximate && bike.lactateThreshold != null) {
      hints.add(
        'Für das Rad liegt kein eigener Schwellenwert vor – die Rad-Zonen sind eine Näherung. Ein eigener '
        '30-Minuten-Test auf dem Rad macht sie genau.',
      );
    }
    final confirmed = observed.confirmed;
    if (confirmed != null && garminMax != null && confirmed - garminMax > 3) {
      hints.add(
        'Bestätigter Höchstpuls $confirmed liegt über der Uhr-Einstellung $garminMax. Die Zonen der Uhr sind dadurch '
        'zu tief angesetzt.',
      );
    }
    if (confirmed != null &&
        garminMax != null &&
        garminMax - confirmed > 5 &&
        observed.count >= 5 &&
        overrides.valid(overrides.maxHeartRate) == null) {
      hints.add(
        'Die HFmax der Uhr ($garminMax) wurde bisher in keiner Einheit erreicht (höchster bestätigter Wert '
        '$confirmed). Die Coach-Zonen hängen an der Schwelle und sind davon kaum betroffen, die Uhr-Zonen schon.',
      );
    }
    final peak = observed.peak;
    if (peak != null && (confirmed == null || peak - confirmed > confirmTolerance)) {
      hints.add(
        'Höchstwert $peak wurde in keiner zweiten Einheit annähernd erreicht und gilt als möglicher Sensor-Ausreißer – '
        'er fließt nicht in die Zonen ein.',
      );
    }
    final method = watch
        .firstWhereOrNull((zones) => const ['DEFAULT', 'RUNNING'].contains(zones.sport.toUpperCase()))
        ?.method
        .toUpperCase();
    if (method != null) {
      if (method.contains('MAX')) {
        hints.add(
          'Die Uhr rechnet Zonen in % der HFmax. Das ist nicht dasselbe wie Zonen um die Schwelle: Z2 der Uhr liegt '
          'tiefer als Z2 nach Schwelle.',
        );
      } else if (method.contains('RESERVE')) {
        hints.add('Die Uhr rechnet Zonen nach HF-Reserve (Karvonen).');
      }
    }
    for (final (coach, label, share) in [(run, 'Laufen', distribution.run), (bike, 'Rad', distribution.bike)]) {
      final average = averageHeartRateShare(activities, coach: coach, today: today);
      if (average != null && average.minutes >= 120 && average.easyPercent < 70) {
        final watchText = share == null ? '' : ' Nach den Zonen der Uhr sind es ${share.easyPercent} % in Z1–2.';
        hints.add(
          '$label: ${average.easyPercent} % der Zeit liegen bei einer Durchschnitts-HF in Coach-Z1–2 (letzte 4 Wochen, '
          'Näherung je Einheit).$watchText Richtwert ~80 % locker – zu viel Mittelbereich macht lockere Einheiten '
          'weniger erholsam.',
        );
      } else if (average == null && share != null && share.minutes >= 120 && share.easyPercent < 70) {
        hints.add('$label: nur ${share.easyPercent} % der Zeit in Z1–2 der Uhr (letzte 4 Wochen); Richtwert ~80 %.');
      }
    }
    hints.add(
      'Optisches Messen am Handgelenk unterschätzt bei intensiven Intervallen die Zeit in hohen Zonen (Neudorfer 2024). '
      'Der Hart-Anteil ist eher eine Untergrenze.',
    );
    return hints;
  }
}

// Port von CoachCoreTests/AnalysisTests.swift und den FIT-Fällen aus ActivityDetailsTests.swift. Die Erwartungswerte
// in `fixtures/analysis-cases.json` hat der Original-Code (`decoupling.py`, `pace_check.py`, `tagesform.py`) aus
// Zufallsdaten berechnet; `run.zip` ist eine mit `fit_tool` erzeugte FIT-Datei, `run-expected.json` deren Inhalt laut
// `fitparse`.
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

Map<String, Object?> cases() =>
    jsonDecode(File('test/fixtures/analysis-cases.json').readAsStringSync()) as Map<String, Object?>;

double? number(Object? value) => value is num ? value.toDouble() : null;

GarminActivity activityFrom(Map<String, Object?> raw) {
  final activity = GarminActivity(1)
    ..typeKey = (raw['activityType'] as Map?)?['typeKey'] as String?
    ..name = raw['activityName'] as String?
    ..durationSeconds = number(raw['duration'])
    ..distanceMeters = number(raw['distance'])
    ..averagePower = number(raw['avgPower']);
  final zones = [for (var zone = 1; zone <= 5; zone++) number(raw['hrTimeInZone_$zone'])].nonNulls.toList();
  if (zones.length == 5 && zones.fold<double>(0, (sum, value) => sum + value) > 0) activity.secondsInZones = zones;
  return activity;
}

void main() {
  test('Entkopplung aus der Zeitreihe wie im Original', () {
    final all = (cases()['series'] as List).cast<Map<String, Object?>>();
    expect(all.any((testCase) => testCase['expected'] != null), isTrue);
    for (final testCase in all) {
      final sport = DecouplingSport.values.byName(testCase['sport'] as String);
      final samples = [
        for (final sample in (testCase['samples'] as List).cast<List<Object?>>())
          DecouplingSample(time: number(sample[0])!, output: number(sample[1])!, heartRate: number(sample[2])!),
      ];
      final result = AerobicDecoupling.fromSeries(samples, sport);
      final expected = testCase['expected'] as Map<String, Object?>?;
      if (expected == null) {
        expect(result, isNull);
        continue;
      }
      expect(result, isNotNull);
      expect((result!.percent - number(expected['percent'])!).abs(), lessThan(0.051));
      expect((result.firstHalfHeartRate - number(expected['hr1'])!).abs(), lessThan(0.051));
      expect((result.secondHalfHeartRate - number(expected['hr2'])!).abs(), lessThan(0.051));
      expect(result.firstHalfPace, expected['pace1']);
      expect(result.secondHalfPace, expected['pace2']);
      expect(result.firstHalfPower, expected['power1']);
      expect(result.secondHalfPower, expected['power2']);
    }
  });

  test('Entkopplung aus Runden wie im Original', () {
    for (final testCase in (cases()['laps'] as List).cast<Map<String, Object?>>()) {
      final laps = [
        for (final lap in (testCase['laps'] as List).cast<Map<String, Object?>>())
          FitLap(
            timerSeconds: number(lap['duration']),
            distanceMeters: number(lap['distance']),
            averageHeartRate: number(lap['averageHR']),
          ),
      ];
      final result = AerobicDecoupling.fromLaps(laps);
      final expected = testCase['expected'] as Map<String, Object?>?;
      if (expected == null) {
        expect(result, isNull);
        continue;
      }
      expect((result!.percent - number(expected['percent'])!).abs(), lessThan(0.051));
      expect((result.firstHalfHeartRate - number(expected['hr1'])!).abs(), lessThan(0.051));
      expect(result.firstHalfPace, expected['pace1']);
      expect(result.secondHalfPace, expected['pace2']);
    }
  });

  test('Einordnung wie im Original', () {
    const kinds = {
      'locker': SessionKind.easy,
      'test': SessionKind.test,
      'vo2': SessionKind.vo2,
      'schwelle': SessionKind.threshold,
      'hart': SessionKind.hard,
      'gym': SessionKind.gym,
    };
    for (final testCase in (cases()['classify'] as List).cast<Map<String, Object?>>()) {
      final raw = testCase['activity'] as Map<String, Object?>;
      final activity = activityFrom(raw);
      final label = '${activity.typeKey ?? '-'} ${activity.name ?? '-'}';
      expect(AerobicDecoupling.classify(activity)?.rawValue, testCase['classify'], reason: label);
      expect(AerobicDecoupling.skipReason(activity), testCase['skip'], reason: label);
      final kind = testCase['kind'] as String?;
      if (kind == null) continue;
      expect(SessionKind.isHard(activity), testCase['hard'], reason: label);
      expect(SessionKind.of(activity), kinds[kind], reason: label);
    }
  });

  test('Pace-Check wie im Original', () {
    const statuses = {
      'passt': PaceStatus.fits,
      'schneller': PaceStatus.faster,
      'langsamer': PaceStatus.slower,
      'zu wenig Daten': PaceStatus.tooFewData,
    };
    for (final testCase in (cases()['pace'] as List).cast<Map<String, Object?>>()) {
      final sessions = [
        for (final session in (testCase['sessions'] as List).cast<Map<String, Object?>>())
          PaceSession(
            id: session['id']! as int,
            day: CalendarDay.tryParse(session['date']! as String)!,
            name: session['name'] as String?,
            kind: session['kind'] == 'vo2' ? PaceKind.vo2 : PaceKind.threshold,
            rpe: number(session['rpe']),
            laps: [
              for (final lap in (session['laps'] as List).cast<Map<String, Object?>>())
                PaceLap(
                  duration: number(lap['dur'])!,
                  distance: number(lap['dist'])!,
                  heartRate: number(lap['hr']),
                  maxHeartRate: number(lap['hrmax']),
                  isWork: lap['type'] == null ? null : const ['ACTIVE', 'INTERVAL'].contains(lap['type']),
                ),
            ],
          ),
      ];
      final result = PaceCheck.evaluate(
        sessions,
        thresholdPace: testCase['thresholdPace']! as int,
        lthr: number(testCase['lthr']),
        maxHeartRate: number(testCase['maxHeartRate']),
        restingHeartRate: number(testCase['restingHeartRate'])!,
      );
      expect(result.status, statuses[testCase['status']]);
      expect(result.suggested, testCase['suggested']);
      expect(result.reason, testCase['reason']);
      expect(result.intervalBand, testCase['intervalBand']);
      expect(result.suggestedIntervalBand, testCase['suggestedIntervalBand']);
      final suggestion = PaceCheck.suggestionText(result);
      expect(suggestion?.title, testCase['suggestionTitle']);
      expect(suggestion?.text, testCase['suggestionText']);
      final rows = (testCase['rows'] as List).cast<Map<String, Object?>>();
      expect(result.rows.length, rows.length);
      for (var index = 0; index < rows.length; index++) {
        final row = result.rows[index];
        final expected = rows[index];
        expect(row.id, expected['id']);
        if (expected['verdict'] != null) expect(row.verdict, expected['verdict']);
        expect(row.workMinutes, expected['workMinutes']);
        expect(row.workPace, expected['workPace']);
        expect(row.workHeartRate, expected['workHeartRate']);
        expect(row.heartRatePercentOfThreshold, expected['percentOfThreshold']);
        expect(row.estimatedThreshold, expected['estimatedThreshold']);
        expect(row.repetitionPeakPercentOfMax, expected['peakPercent']);
      }
    }
  });

  test('liest eine FIT-Datei aus dem Garmin-ZIP', () {
    final expected = jsonDecode(File('test/fixtures/run-expected.json').readAsStringSync()) as Map<String, Object?>;
    final fit = FitDecoder.decode(ZipArchive.fitData(File('test/fixtures/run.zip').readAsBytesSync()));
    expect(fit.records.length, expected['recordCount']);
    expect(fit.records.where((record) => record.heartRate != null).length, expected['withHeartRate']);
    expect(fit.records.where((record) => record.power != null).length, expected['withPower']);
    expect((fit.records.last.distance! - number(expected['lastDistance'])!).abs(), lessThan(0.001));
    expect((fit.records.first.speed! - number(expected['firstSpeed'])!).abs(), lessThan(0.0005));
    final laps = (expected['laps'] as List).cast<Map<String, Object?>>();
    expect(fit.laps.length, laps.length);
    for (var index = 0; index < laps.length; index++) {
      final lap = fit.laps[index];
      final want = laps[index];
      expect(lap.timerSeconds, number(want['timer']));
      expect(lap.elapsedSeconds, number(want['elapsed']));
      expect((lap.distanceMeters! - number(want['distance'])!).abs(), lessThan(0.001));
      expect(lap.averageHeartRate, number(want['avgHR']));
      expect(lap.maxHeartRate, number(want['maxHR']));
      expect(lap.intensity?.index, want['intensity']);
    }
    final decoupling = expected['decoupling'] as Map<String, Object?>;
    final result = AerobicDecoupling.compute(fit, DecouplingSport.run)!;
    expect(result.source, DecouplingSource.series);
    expect((result.percent - number(decoupling['percent'])!).abs(), lessThan(0.051));
    expect((result.firstHalfHeartRate - number(decoupling['hr1'])!).abs(), lessThan(0.051));
    expect(GermanFormat.minutesSeconds(result.firstHalfPace!), decoupling['pace1']);
    expect(GermanFormat.minutesSeconds(result.secondHalfPace!), decoupling['pace2']);
    // Runden für den Pace-Check: Aufwärmen, Pausen und Auslaufen zählen nicht als Arbeit.
    expect(PaceCheck.workLaps(PaceLap.from(fit.laps), thresholdPace: 300).length, 4);
  });

  test('komprimierte Zeitstempel, Big Endian und Entwicklerfelder', () {
    final body = <int>[
      // Definition lokal 0: record (20), Big Endian, Felder 253 (4 Byte), 3 (1 Byte); 1 Entwicklerfeld à 2 Byte.
      0x60, 0, 1, 0, 20, 2, 253, 4, 0x86, 3, 1, 0x02, 1, 0, 2, 0, //
      // Daten: Zeit 1000 (0x3E8), HF 120, Entwicklerbytes.
      0x00, 0, 0, 0x03, 0xE8, 120, 0xAA, 0xBB, //
      // Definition lokal 1: record ohne Zeitfeld (nur HF), Little Endian.
      0x41, 0, 0, 20, 0, 1, 3, 1, 2, //
      // Komprimierter Zeitstempel lokal 1, Versatz 2 → 1000 & ~31 = 992, 992 + 2 < 1000 → +32 = 1026.
      0x80 | (1 << 5) | 2, 130, //
      // Ungültige HF (0xFF) fällt weg.
      0x80 | (1 << 5) | 4, 0xFF,
    ];
    final size = body.length;
    final header = <int>[
      12,
      0x20,
      0x08,
      0x08,
      size & 0xFF,
      size >> 8 & 0xFF,
      size >> 16 & 0xFF,
      size >> 24,
      ...'.FIT'.codeUnits,
    ];
    final fit = FitDecoder.decode([...header, ...body, 0, 0]);
    expect(fit.records.map((record) => record.timestamp), [1000, 1026, 1028]);
    expect(fit.records.map((record) => record.heartRate), [120, 130, null]);
    expect(() => FitDecoder.decode([1, 2, 3]), throwsA(isA<FitFailure>()));
  });

  test('entpackt gespeicherte und feste Blöcke', () {
    expect(InflateData.decompress([0x01, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63]), utf8.encode('abc'));
    expect(InflateData.decompress([0x4B, 0x4C, 0x84, 0x01, 0x00]), utf8.encode('aaaaaaaaaa'));
    expect(() => InflateData.decompress([0x07]), throwsA(isA<InflateFailure>()));
  });

  group('Auswahl und Speicherung', () {
    GarminActivity run(
      int id,
      String day,
      String name,
      double minutes, {
      List<double> zones = const [1200, 1500, 300, 60, 0],
    }) => GarminActivity(id)
      ..typeKey = 'running'
      ..name = name
      ..startLocal = '$day 07:00:00'
      ..durationSeconds = minutes * 60
      ..distanceMeters = minutes * 170
      ..secondsInZones = zones;

    test('wählt neue Läufe und übergeht bekannte', () {
      final today = CalendarDay.tryParse('2026-10-26')!;
      final easy = run(1, '2026-10-25', 'Berlin Laufen', 50);
      final threshold = run(2, '2026-10-24', 'Schwelle 3x2 km', 50, zones: [600, 900, 600, 900, 0]);
      final short = run(3, '2026-10-23', 'Lockerer Lauf', 20);
      final old = run(4, '2026-07-01', 'Berlin Laufen', 60);
      final known = ActivityAnalysis(id: 5, day: CalendarDay.tryParse('2026-10-22')!);
      final analyzedRun = run(5, '2026-10-22', 'Berlin Laufen', 50);
      final outdated = ActivityAnalysis(id: 6, day: CalendarDay.tryParse('2026-10-21')!)..method = 1;
      final outdatedRun = run(6, '2026-10-21', 'Berlin Laufen', 50);
      final pending = ActivityAnalysisPlanner.pending(
        [old, short, threshold, easy, analyzedRun, outdatedRun],
        analyzed: {5: known, 6: outdated},
        today: today,
      );
      expect(pending.map((activity) => activity.id), [1, 2, 3, 6]);
      expect(ActivityAnalysisPlanner.needsFile(easy), isTrue);
      expect(ActivityAnalysisPlanner.needsFile(threshold), isTrue);
      expect(ActivityAnalysisPlanner.needsFile(short), isFalse);
      expect(ActivityAnalysisPlanner.paceKind(threshold), PaceKind.threshold);
      expect(ActivityAnalysisPlanner.paceKind(easy), isNull);
      // Kurzer Lauf: ohne Datei, nur mit Grund.
      final skipped = ActivityAnalysisPlanner.analyze(short);
      expect(skipped.skipReason, 'kürzer als 35 min');
      expect(skipped.decoupling, isNull);
      // Schwellenlauf ohne lesbare Datei: Pace-Check bekommt leere Runden, Kopplung entfällt (zu intensiv).
      final hard = ActivityAnalysisPlanner.analyze(threshold, rpe: 8);
      expect(hard.paceKind, PaceKind.threshold);
      expect(hard.laps, isEmpty);
      expect(hard.skipReason, 'zu intensiv (30 % der Zeit in Zone 4-5)');
      expect(ActivityAnalysisPlanner.paceSessions([hard, skipped], today: today).map((session) => session.id), [2]);
      expect(ActivityAnalysisPlanner.needsRPE([hard, skipped], today: today), isEmpty);
      final noRPE = hard.copy()..rpe = null;
      expect(ActivityAnalysisPlanner.needsRPE([noRPE], today: today), [2]);
      expect(ActivityAnalysisPlanner.skipped([hard, skipped]).length, 2);
      expect(ActivityAnalysis.fromJson(jsonDecode(jsonEncode(hard.toJson())))!.toJson(), hard.toJson());
    });

    test('liest die RPE aus den Details', () {
      expect(
        ActivityAnalysisPlanner.rpeFromActivityDetail(
          JsonValue.parse('{"summaryDTO":{"directWorkoutRpe":70,"directWorkoutFeel":50}}'),
        ),
        7,
      );
      expect(ActivityAnalysisPlanner.rpeFromActivityDetail(JsonValue.parse('{"summaryDTO":{}}')), isNull);
    });

    test('Schnitt der letzten fünf', () {
      final values = [1.0, 9.0, 3.0, 4.0, 5.0, 6.0];
      final sessions = [
        for (var index = 0; index < values.length; index++)
          ActivityAnalysis(id: index, day: CalendarDay(2026, 10, index + 1))
            ..decouplingSport = DecouplingSport.run
            ..decoupling = DecouplingResult(
              percent: values[index],
              firstHalfHeartRate: 140,
              secondHalfHeartRate: 145,
              source: DecouplingSource.series,
            ),
      ];
      expect(ActivityAnalysisPlanner.recentAverage(sessions), 5.4);
      expect(
        ActivityAnalysisPlanner.decoupled(sessions.reversed, sport: DecouplingSport.run).map((analysis) => analysis.id),
        [0, 1, 2, 3, 4, 5],
      );
    });
  });

  test('Verlauf und Strecke aus der FIT-Datei', () {
    final fit = FitActivity(
      records: [
        for (var second = 0; second < 600; second++)
          FitRecord(timestamp: second.toDouble(), heartRate: 140, speed: 3.0, distance: second * 3.0)
            ..cadence = 86
            ..altitude = 10 + second / 60
            ..latitude = 52.5 + second / 100000
            ..longitude = 13.4,
      ],
    );
    final samples = ActivityDetails.samples(fit, ActivitySport.run, maxPoints: 60);
    expect(samples.length, 60);
    expect(samples.first.cadence, 172);
    expect((samples.first.pace! - 333.3).abs(), lessThan(1));
    expect(samples.last.x, 1.797);
    expect(ActivityDetails.route(fit, maxPoints: 100).length, 100);
    expect(FitDecoder.signed32(4294967295), -1);
    expect(FitDecoder.signed32(100), 100);
  });

  test('Bankers Rounding wie Python', () {
    expect(roundHalfEven(2.5), 2);
    expect(roundHalfEven(3.5), 4);
    expect(roundHalfEven(-2.5), -2);
    expect(roundHalfEven(2.6), 3);
    expect(round1HalfEven(0.25), 0.2);
  });
}

// Port von ActivityReportTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 11, 10);

GarminActivity run({int id = 1, double seconds = 3000}) => GarminActivity(id)
  ..typeKey = 'running'
  ..name = 'Morgenlauf'
  ..startLocal = '2026-11-09 07:00:00'
  ..durationSeconds = seconds
  ..secondsInZones = [300, 1500, 900, 300, 0];

/// Ein Messpunkt pro Sekunde; `speed` und `heartRate` je Sekunde.
FitActivity fit({
  required int seconds,
  required double Function(int) speed,
  required double Function(int) heartRate,
  List<FitLap> laps = const [],
}) {
  final activity = FitActivity();
  var distance = 0.0;
  for (var second = 0; second <= seconds; second++) {
    final current = speed(second);
    if (second > 0) distance += current;
    activity.records.add(
      FitRecord(timestamp: second.toDouble(), heartRate: heartRate(second), speed: current, distance: distance)
        ..altitude = 100
        ..cadence = 86,
    );
  }
  activity.laps.addAll(laps);
  return activity;
}

void main() {
  test('gleichmäßiger Lauf: gleiche Splits, stabiler Puls', () {
    final file = fit(seconds: 3000, speed: (_) => 10.0 / 3, heartRate: (_) => 145);
    final report = ActivityReportBuilder.build(run(), file);
    expect(report.splits.length, 10);
    expect(report.splits.every((split) => (split.seconds - 300).abs() <= 1), isTrue);
    expect(report.splits[0].averageHeartRate, 145);
    expect(report.halves.speedChangePercent, 0);
    expect(report.pausedSeconds, lessThan(5));
    expect(report.averageCadence, 172);
    expect(report.highZonePercent, 10);
    expect(report.samples.length, lessThanOrEqualTo(151));
    final texts = ActivityFindings.findings(report).map((finding) => finding.text).toList();
    expect(texts, contains('Tempo über die ganze Einheit gleichmäßig.'));
    expect(texts, contains('Puls blieb bei gleichem Tempo stabil.'));
    expect(texts, contains('10 % der Zeit in Zone 4–5.'));
  });

  test('nachlassendes Tempo und negativer Split', () {
    final fading = ActivityReportBuilder.build(
      run(),
      fit(seconds: 3000, speed: (second) => second < 1500 ? 3.6 : 3.2, heartRate: (_) => 150),
    );
    expect(fading.halves.speedChangePercent ?? 0, lessThan(-10));
    expect(ActivityFindings.findings(fading).first.tone, FindingTone.attention);
    expect(ActivityFindings.findings(fading).first.text, contains('zu schnell begonnen'));

    final negative = ActivityReportBuilder.build(
      run(),
      fit(seconds: 3000, speed: (second) => second < 1500 ? 3.2 : 3.4, heartRate: (_) => 150),
    );
    expect(ActivityFindings.findings(negative).first.text, contains('gut eingeteilt'));
    final splits = ActivityFindings.findings(negative).firstWhere((finding) => finding.id == 'splits');
    expect(splits.text, contains('Schnellster Kilometer'));
  });

  test('Puls-Drift bei gleichem Tempo', () {
    final report = ActivityReportBuilder.build(
      run(),
      fit(seconds: 3600, speed: (_) => 3.0, heartRate: (second) => second < 1800 ? 140 : 152),
    );
    expect(report.halves.heartRateChangePercent, 8.6);
    final drift = ActivityFindings.findings(report).firstWhere((finding) => finding.id == 'drift');
    expect(drift.tone, FindingTone.attention);
    expect(drift.text, contains('8,6 %'));
  });

  test('Pausen zählen als Standzeit', () {
    // 10 Minuten laufen, 5 Minuten stehen, 10 Minuten laufen.
    final file = fit(seconds: 1500, speed: (second) => second >= 600 && second < 900 ? 0 : 3, heartRate: (_) => 140);
    final report = ActivityReportBuilder.build(run(seconds: 1500), file);
    expect((report.pausedSeconds - 300).abs(), lessThanOrEqualTo(2));
    expect((report.movingSeconds - 1200).abs(), lessThanOrEqualTo(2));
    expect(
      ActivityFindings.findings(report)
          .any((finding) => finding.id == 'pause' && finding.text.startsWith('5 min Standzeit')),
      isTrue,
    );
  });

  test('Intervalle: erstes gegen letztes', () {
    FitLap lap(double speed, FitLapIntensity intensity, {required double heartRate}) =>
        FitLap(timerSeconds: 240, distanceMeters: speed * 240, averageHeartRate: heartRate, intensity: intensity)
          ..averageSpeed = speed;
    final laps = [
      lap(2.8, FitLapIntensity.warmup, heartRate: 130),
      lap(4.2, FitLapIntensity.interval, heartRate: 168),
      lap(2.5, FitLapIntensity.recovery, heartRate: 140),
      lap(4.1, FitLapIntensity.interval, heartRate: 172),
      lap(2.5, FitLapIntensity.recovery, heartRate: 142),
      lap(3.9, FitLapIntensity.interval, heartRate: 175),
    ];
    final report = ActivityReportBuilder.build(
      run(),
      fit(seconds: 1440, speed: (_) => 3.3, heartRate: (_) => 150, laps: laps),
    );
    final findings = ActivityFindings.findings(report);
    expect(findings.first.text.startsWith('3 Intervalle'), isTrue);
    expect(findings.any((finding) => finding.id == 'fade' && finding.tone == FindingTone.attention), isTrue);
    // Im Modus „reduziert“ gehen keine Pulswerte in Schlägen an die KI.
    final reduced = ActivityFindings.contextLine(report, full: false);
    expect(reduced, isNot(contains('Schläge')));
    expect(ActivityFindings.contextLine(report, full: true), contains('175 Schläge'));
    expect(reduced!.startsWith('Morgenlauf (09.11.2026): '), isTrue);
  });

  test('Bericht übersteht das Speichern', () {
    FitLap lap() =>
        FitLap(timerSeconds: 600, distanceMeters: 1800, averageHeartRate: 140, intensity: FitLapIntensity.active)
          ..averageSpeed = 3;
    final report = ActivityReportBuilder.build(
      run(),
      fit(seconds: 1200, speed: (_) => 3, heartRate: (_) => 140, laps: [lap(), lap()]),
    );
    final text = jsonEncode(report.toJson());
    final decoded = ActivityReport.fromJson(jsonDecode(text));
    expect(decoded, isNotNull);
    expect(jsonEncode(decoded!.toJson()), text);
    expect(decoded.laps.first.intensity, FitLapIntensity.active);
    final laps = (jsonDecode(text) as Map<String, Object?>)['laps']! as List<Object?>;
    expect((laps.first! as Map<String, Object?>)['intensity'], 0);
    expect(ActivityReport.fromJson({'id': 1}), isNull);
  });

  test('Planer nimmt jede neue Garmin-Aktivität einmal', () {
    final old = run(id: 2)..startLocal = '2026-08-01 07:00:00';
    final short = run(id: 3, seconds: 120)..startLocal = '2026-11-08 07:00:00';
    final health = run(id: -5)..startLocal = '2026-11-08 09:00:00';
    final strength = run(id: 4)
      ..typeKey = 'strength_training'
      ..startLocal = '2026-11-10 06:00:00';
    final all = [run(), old, short, health, strength];
    List<int> ids(List<GarminActivity> list) => [for (final activity in list) activity.id];
    expect(ids(ActivityReportPlanner.pending(all, known: {}, today: today)), [4, 1]);
    final known = {1: ActivityReportBuilder.build(run(), FitActivity())};
    expect(ids(ActivityReportPlanner.pending(all, known: known, today: today)), [4]);
    expect(ActivityReportPlanner.pending(all, known: known, failed: {4}, today: today), isEmpty);
    // Workouts aus Apple Health laufen getrennt (Verlauf aus HealthKit statt aus einer Datei).
    expect(ids(ActivityReportPlanner.pending(all, known: {}, today: today, health: true)), [-5]);
  });
}

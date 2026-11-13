// Import aus Apple Health bzw. Health Connect gegen eine nachgebildete Quelle.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/garmin/activity_stores.dart';
import 'package:aironludi/services/health/health_import_service.dart';
import 'package:aironludi/services/health/health_source.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeHealthSource implements HealthSource {
  final Map<HealthQuantity, List<HealthQuantitySample>> samples = {};
  List<SleepSample> nights = [];
  List<HealthWorkout> workoutList = [];
  final Set<HealthQuantity> failing = {};

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<void> requestAccess() async {}

  @override
  Future<List<HealthQuantitySample>> quantities(
    HealthQuantity kind, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (failing.contains(kind)) throw StateError('kaputt');
    return [
      for (final sample in samples[kind] ?? const <HealthQuantitySample>[])
        if (!sample.start.isBefore(from) && !sample.start.isAfter(to)) sample,
    ];
  }

  @override
  Future<List<SleepSample>> sleep({required DateTime from, required DateTime to}) async => nights;

  @override
  Future<List<HealthWorkout>> workouts({required DateTime from, required DateTime to}) async => workoutList;
}

HealthQuantitySample sample(DateTime start, double value, {String source = 'watch'}) =>
    HealthQuantitySample(start: start, end: start.add(const Duration(minutes: 1)), value: value, source: source);

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  final now = DateTime(2026, 11, 13, 9);
  final yesterday = DateTime(2026, 11, 12, 10);

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  test('Tagesstatistik: Summe ohne doppelte Quellen, Mittel und Minimum', () {
    final samples = [
      sample(yesterday, 4000, source: 'iphone'),
      sample(yesterday, 5000, source: 'watch'),
      sample(yesterday.add(const Duration(hours: 2)), 1000, source: 'watch'),
    ];
    const day = CalendarDay(2026, 11, 12);
    expect(HealthImportService.cumulativeSum(samples)[day], 6000);
    expect(HealthImportService.average(samples)[day], closeTo(3333.3, 0.1));
    expect(HealthImportService.minimum(samples)[day], 1000);
  });

  test('Import: Tageswerte, Workouts ohne eigene, Gewicht, Meldung mit Problemen', () async {
    final source = FakeHealthSource()
      ..samples[HealthQuantity.steps] = [sample(yesterday, 8000)]
      ..samples[HealthQuantity.restingHeartRate] = [sample(yesterday, 52), sample(yesterday, 54)]
      ..samples[HealthQuantity.bodyMass] = [sample(yesterday, 71.5)]
      ..failing.add(HealthQuantity.respiratoryRate)
      ..workoutList = [
        HealthWorkout(
          uuid: newUuid(),
          typeKey: 'running',
          start: DateTime(2026, 11, 12, 18),
          end: DateTime(2026, 11, 12, 18, 45),
          distanceMeters: 8000,
          sourceName: 'Apple Watch',
          sourceBundle: 'com.apple.health',
        ),
        HealthWorkout(
          uuid: newUuid(),
          typeKey: 'strength_training',
          start: DateTime(2026, 11, 12, 7),
          end: DateTime(2026, 11, 12, 8),
          sourceName: 'Coach',
          sourceBundle: 'io.github.hkrb7p794w.coach',
        ),
      ];
    final service = HealthImportService(
      source: source,
      settings: settings,
      metrics: MetricsRepository(db),
      activities: ActivityRepository(db),
      reportStore: ActivityReportStore(),
    )..isEnabled = true;
    await service.importNow(garminConnected: true, now: now);

    final metrics = await MetricsRepository(db).day(const CalendarDay(2026, 11, 12));
    expect(metrics?.steps, 8000);
    expect(metrics?.restingHeartRate, 53);
    final activities = await ActivityRepository(db).all();
    expect(activities.map((activity) => activity.typeKey), ['running']);
    expect(activities.single.id, isNegative);
    expect(service.weights.single.kilograms, 71.5);
    expect(service.lastImport, now);
    expect(service.lastResult, startsWith('1 Tage, 1 neue Workouts aus Apple Health'));
    expect(service.lastProblem, 'Nicht lesbar: respiratoryRate');
  });

  test('ausgeschaltet: kein Import', () async {
    final service = HealthImportService(
      source: FakeHealthSource()..samples[HealthQuantity.steps] = [sample(yesterday, 8000)],
      settings: settings,
      metrics: MetricsRepository(db),
      activities: ActivityRepository(db),
    );
    await service.importNow(garminConnected: false, now: now);
    expect(await MetricsRepository(db).all(), isEmpty);
    expect(service.lastResult, isNull);
  });

  test('Kennungen ohne UUID-Form werden stabil umgewandelt', () {
    expect(PluginHealthSource.uuidOf('8f14e45f-ceea-467a-9575-3c3c2d1a0b11'), '8f14e45f-ceea-467a-9575-3c3c2d1a0b11');
    final converted = PluginHealthSource.uuidOf('hc:12345');
    expect(converted, PluginHealthSource.uuidOf('hc:12345'));
    expect(HealthImport.activityID(converted), isNegative);
  });
}

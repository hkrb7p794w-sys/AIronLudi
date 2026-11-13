// Repositories und Quellen-Ablage (Port von `SourceStore`) auf einer Datenbank im Arbeitsspeicher.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/repositories/source_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const day = CalendarDay(2026, 11, 9);
final now = DateTime.utc(2026, 11, 10, 8);

GarminActivity run(int id, {DataProvider provider = DataProvider.garmin, String start = '2026-11-09 07:00:00'}) =>
    GarminActivity(id)
      ..name = 'Lauf'
      ..typeKey = 'running'
      ..startLocal = start
      ..durationSeconds = 3600
      ..provider = provider
      ..externalID = 'ext-$id';

MealItem item(String name, {MealItemSource source = MealItemSource.manual, double kcal = 100, double grams = 50}) =>
    MealItem(name: name, grams: grams, source: source, per100g: NutrientValues({Nutrient.kcal: kcal}));

void main() {
  late CoachDatabase db;
  late SettingsStore settings;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  group('Tageswerte', () {
    test('merge führt mit Gespeichertem zusammen, neue Felder überschreiben', () async {
      final repo = MetricsRepository(db);
      await repo.merge(DailyMetrics(day)..steps = 1000, at: now);
      await repo.merge(DailyMetrics(day)..restingHeartRate = 48, at: now);
      await repo.merge(DailyMetrics(day)..steps = 2000, at: now);
      final stored = await repo.day(day);
      expect(stored?.steps, 2000);
      expect(stored?.restingHeartRate, 48);
      expect(await repo.range(from: day, to: day.adding(1)), hasLength(1));
    });
  });

  group('Quellen', () {
    test('ingestDays legt Herkunft an und wählt je Datenart eine Quelle', () async {
      final store = SourceStore(db, settings, preferences: () => SourcePreferences(primary: DataProvider.garmin));
      expect(
        await store.ingestDays({day: DailyMetrics(day)..steps = 5000}, from: DataProvider.appleHealth, now: now),
        1,
      );
      expect(
        await store.ingestDays(
          {
            day: DailyMetrics(day)
              ..steps = 7000
              ..restingHeartRate = 50,
          },
          from: DataProvider.garmin,
          now: now,
        ),
        1,
      );
      final metrics = await MetricsRepository(db).day(day);
      expect(metrics?.steps, 7000);
      expect(metrics?.restingHeartRate, 50);
      expect(await store.sources(day), containsPair(DataKind.steps, DataProvider.garmin));
      // Unverändert geliefert: nichts zu tun.
      expect(await store.ingestDays({day: DailyMetrics(day)..steps = 7000}, from: DataProvider.garmin, now: now), 0);
      expect(
        (await store.entries()).map((entry) => entry.id),
        containsAll(['garmin|daily|2026-11-09', 'appleHealth|daily|2026-11-09']),
      );
    });

    test('Altbestand gilt einmalig als Garmin', () async {
      await MetricsRepository(db).replace(DailyMetrics(day)..steps = 3000, at: now);
      final store = SourceStore(db, settings);
      await store.migrateIfNeeded();
      await store.migrateIfNeeded();
      final entries = await store.entries();
      expect(entries, hasLength(1));
      expect(entries.single.provider, DataProvider.garmin);
      expect(settings.boolValue(SourceStore.migratedKey), isTrue);
      expect(await store.rebuild(now: now), 0);
    });

    test('Synchronisierungsstatus bleibt im Einstellungsschlüssel', () async {
      final store = SourceStore(db, settings);
      await store.recordFailure(DataProvider.garmin, error: 'offline', now: now);
      await store.recordFailure(DataProvider.garmin, error: 'offline', now: now);
      expect(store.syncStates[DataProvider.garmin]?.failures, 2);
      await store.recordSuccess(DataProvider.garmin, now: now);
      final state = store.syncStates[DataProvider.garmin];
      expect(state?.failures, 0);
      expect(state?.lastError, isNull);
      expect(state?.lastSuccessDay, CalendarDay.fromDate(now));
      expect(settings.json(SourceStore.statesKey), isA<Map<Object?, Object?>>());
    });

    test('vollständiger Abruf entfernt beim Anbieter gelöschte Aktivitäten', () async {
      final store = SourceStore(db, settings);
      final activities = ActivityRepository(db);
      final window = DateRange(day, day);
      await activities.upsertAll([run(1), run(2, start: '2026-11-09 18:00:00')]);
      expect(
        await store.recordActivities(
          [run(1), run(2, start: '2026-11-09 18:00:00')],
          from: DataProvider.garmin,
          window: window,
          complete: true,
          now: now,
        ),
        {1, 2},
      );
      await store.recordActivities([run(1)], from: DataProvider.garmin, window: window, complete: true, now: now);
      expect((await activities.all()).map((activity) => activity.id), [1]);
      final deleted = (await store.entries()).firstWhere((entry) => entry.externalID == 'ext-2');
      expect(deleted.status, SourceEntryStatus.deleted);
    });

    test(
      'Doppelte verschiedener Anbieter: nur die bevorzugte Quelle bleibt, die andere wird nicht neu angelegt',
      () async {
        final store = SourceStore(db, settings, preferences: () => SourcePreferences(primary: DataProvider.garmin));
        final activities = ActivityRepository(db);
        final health = run(-5, provider: DataProvider.appleHealth, start: '2026-11-09 07:02:00');
        await activities.upsertAll([run(1), health]);
        final removed = await store.deduplicateActivities(
          connected: {DataProvider.garmin, DataProvider.appleHealth},
          now: now,
        );
        expect(removed, 1);
        expect((await activities.all()).map((activity) => activity.id), [1]);
        final allowed = await store.recordActivities(
          [health],
          from: DataProvider.appleHealth,
          window: null,
          complete: false,
          now: now,
        );
        expect(allowed, isEmpty);
      },
    );
  });

  group('Mahlzeiten', () {
    test('Wasser zählt nicht als Mahlzeit, Bereich nach Tagen', () async {
      final repo = MealRepository(db);
      await repo.save(
        StoredMeal(
          day: day,
          createdAt: DateTime.utc(2026, 11, 9, 7),
          category: MealCategory.breakfast,
          title: 'Porridge',
          items: [item('Haferflocken')],
        ),
      );
      await repo.save(
        StoredMeal(
          day: day,
          createdAt: DateTime.utc(2026, 11, 9, 9),
          category: MealCategory.other,
          title: 'Wasser',
          items: [MealItem.water(milliliters: 250)],
        ),
      );
      final meals = await repo.day(day);
      expect(meals, hasLength(2));
      expect(MealRepository.entries(meals).map((entry) => entry.title), ['Porridge']);
      expect(await repo.day(day.adding(1)), isEmpty);
    });

    test('Lebensmittel merken: Menge übernehmen, eigene Nährwerte behalten, KI-Werte ersetzen', () async {
      final repo = MealRepository(db);
      await repo.rememberFoods([item('Quark', kcal: 70)], at: now);
      await repo.rememberFoods([item('Quark', kcal: 999, grams: 40)], at: now);
      await repo.rememberFoods([item('Brot', source: MealItemSource.ai, kcal: 300)], at: now);
      await repo.rememberFoods([item('Brot', source: MealItemSource.bls, kcal: 250)], at: now);
      final foods = await repo.foods();
      expect(foods.map((food) => food.useCount), [2, 2]);
      final quark = foods.firstWhere((food) => food.name == 'Quark').item!;
      expect(quark.grams, 40);
      expect(quark.per100g[Nutrient.kcal], 70);
      final bread = foods.firstWhere((food) => food.name == 'Brot').item!;
      expect(bread.per100g[Nutrient.kcal], 250);
      expect(MealRepository.foodKey(item('Quark')), 'name:quark');
      expect(foods.first.candidate.id, startsWith('food:name:'));
    });
  });

  group('Gym', () {
    test('Status bleibt beim erneuten Speichern', () async {
      final repo = GymRepository(db);
      final session = GymSession(
        workoutKey: null,
        title: 'Push A',
        start: DateTime.utc(2026, 11, 9, 17),
        end: DateTime.utc(2026, 11, 9, 18),
        exercises: [],
      );
      await repo.save(session, savedToHealth: true);
      await repo.save(session);
      expect((await repo.byID(session.id))?.savedToHealth, isTrue);
      await repo.setUploadedToGarmin(session.id, value: true);
      expect((await repo.byID(session.id))?.uploadedToGarmin, isTrue);
      expect(await repo.sessions(), hasLength(1));
      await repo.delete(session.id);
      expect(await repo.all(), isEmpty);
    });
  });
}

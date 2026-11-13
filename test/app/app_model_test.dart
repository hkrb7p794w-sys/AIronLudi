// App-Zustand: Abruf mit Garmin, Erinnerungen, Planerfüllung.
import 'dart:convert';

import 'package:aironludi/app/app_model.dart';
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/repositories/source_store.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/platform/notifications.dart';
import 'package:aironludi/services/garmin/activity_stores.dart';
import 'package:aironludi/services/garmin/garmin_client.dart';
import 'package:aironludi/services/garmin/garmin_sync_service.dart';
import 'package:aironludi/services/gym/garmin_strength_service.dart';
import 'package:aironludi/services/health/health_import_service.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/reminders/reminder_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/health_import_test.dart' show FakeHealthSource;

const longLivedToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.c2ln';

void main() {
  late CoachDatabase db;
  late SettingsStore store;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  AppModel model({String? garminKey, FakeNotificationCenter? center}) {
    final settings = CoachSettings(store);
    final profile = UserProfile(mode: ProfileMode.personal, onboardingDone: true, sports: const [TrainingSport.run]);
    for (final weekday in Weekday.values) {
      profile.schedule = profile.schedule.withSlots(const [SessionSlot(TrainingSport.run)], weekday);
    }
    settings.profile = profile;
    final today = CalendarDay.today().iso;
    final transport = FakeHttpTransport((request) {
      final path = request.url.path;
      final body = switch (path) {
        _ when path.endsWith('/token') => longLivedToken,
        _ when path.endsWith('/v2/dailysummaries') => '{"data": [{"calendarDate": "$today", "restingHeartRate": 49}]}',
        _ => '[]',
      };
      return HttpResponse(200, utf8.encode(body));
    });
    final secrets = Secrets.memory({SecretKey.garminAPIKey: ?garminKey});
    final garmin = GarminClient(secrets: secrets, transport: transport);
    final metrics = MetricsRepository(db);
    final activities = ActivityRepository(db);
    return AppModel(
      settings: settings,
      garmin: garmin,
      sync: GarminSyncService(
        client: garmin,
        settings: store,
        metrics: metrics,
        activities: activities,
        raw: RawResponseRepository(db),
        analysisStore: ActivityAnalysisStore(),
        reportStore: ActivityReportStore(),
      ),
      health: HealthImportService(
        source: FakeHealthSource(),
        settings: store,
        metrics: metrics,
        activities: activities,
      ),
      sources: SourceStore(db, store),
      reminders: ReminderService(settings: settings, center: center),
      strength: GarminStrengthService(gym: GymRepository(db), activities: activities, folder: null),
      metrics: metrics,
      activities: activities,
      meals: MealRepository(db),
      gymRepository: GymRepository(db),
    );
  }

  test('Abruf: Garmin-Werte über die Quellen-Ablage, Status, Erinnerungen geplant', () async {
    final center = FakeNotificationCenter();
    final app = model(garminKey: 'k', center: center);
    await app.start();
    await app.syncNow();
    expect(app.lastError, isNull);
    expect(app.lastReport, isNotNull);
    expect((await MetricsRepository(db).day(CalendarDay.today()))?.restingHeartRate, 49);
    expect(app.sources.syncStates[DataProvider.garmin]?.failures, 0);
    expect(center.pending.keys.where((id) => id.startsWith('coach.reminder.')), isNotEmpty);
    expect(app.isSyncing, isFalse);
  });

  test('ohne Quelle kein Abruf', () async {
    final app = model();
    await app.start();
    await app.syncIfDue();
    expect(app.lastReport, isNull);
    expect(app.connectedSources, isEmpty);
  });

  test('erfasste Mahlzeiten ohne Wasser und Planerfüllung', () async {
    final app = model();
    final today = CalendarDay.today();
    await MealRepository(db).save(
      StoredMeal(day: today, createdAt: DateTime.now(), category: MealCategory.breakfast, title: 'Müsli', items: []),
    );
    await MealRepository(db).save(
      StoredMeal(
        day: today,
        createdAt: DateTime.now(),
        category: MealCategory.lunch,
        title: 'Wasser',
        items: [MealItem.water(milliliters: 250)],
      ),
    );
    expect(await app.loggedMeals(), {MealReminderPlanner.loggedKey(today, MealCategory.breakfast)});
    final summary = app.motivation({today}, today: today);
    expect(summary.week.planned, 7);
    expect(summary.week.done, 1);
  });
}

// Einstellungen: Garmin-Key mit Ablaufwarnung, KI-Worker testen.
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
import 'package:aironludi/features/settings/settings_controller.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/garmin/activity_stores.dart';
import 'package:aironludi/services/garmin/garmin_client.dart';
import 'package:aironludi/services/garmin/garmin_sync_service.dart';
import 'package:aironludi/services/gym/garmin_strength_service.dart';
import 'package:aironludi/services/health/health_import_service.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/reminders/reminder_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/health_import_test.dart' show FakeHealthSource;

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

  (SettingsController, AIClient) make({Map<SecretKey, String>? secrets}) {
    final memory = Secrets.memory(secrets);
    final transport = FakeHttpTransport(
      (_) => HttpResponse(200, utf8.encode('{"output": {"gruss": "Hallo"}, "model": "m", "provider": "gemini"}')),
    );
    final garmin = GarminClient(secrets: memory, transport: transport);
    final settings = CoachSettings(store);
    final metrics = MetricsRepository(db);
    final activities = ActivityRepository(db);
    final model = AppModel(
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
      reminders: ReminderService(settings: settings),
      strength: GarminStrengthService(gym: GymRepository(db), activities: activities, folder: null),
      metrics: metrics,
      activities: activities,
      meals: MealRepository(db),
      gymRepository: GymRepository(db),
    );
    final ai = AIClient(secrets: memory, settings: store, transport: transport);
    return (SettingsController(model: model, ai: ai, settings: store, clock: () => DateTime(2026, 11, 13)), ai);
  }

  test('Ablaufwarnung des Garmin-Keys', () async {
    final (controller, _) = make(secrets: {SecretKey.garminAPIKey: 'k'});
    expect(controller.expiryWarning, isNull);
    await controller.saveExpiry(DateTime(2026, 11, 20));
    expect(controller.expiryWarning, 'Der Garmin-Key läuft in 7 Tagen ab.');
    await controller.saveExpiry(DateTime(2026, 11, 1));
    expect(controller.expiryWarning, startsWith('Der Garmin-Key ist abgelaufen'));
    await controller.removeGarminKey();
    expect(controller.hasGarminKey, isFalse);
    expect(controller.garminStatus, 'Key entfernt.');
  });

  test('leerer Key wird nicht gespeichert', () async {
    final (controller, _) = make();
    controller.garminKeyInput = '  ';
    await controller.saveGarminKey();
    expect(controller.garminStatus, 'Bitte den Key einfügen.');
  });

  test('KI-Worker speichern und testen', () async {
    final (controller, ai) = make();
    controller
      ..workerURLInput = 'https://coach-ai.example.workers.dev/'
      ..appTokenInput = 'tok';
    await controller.saveAndTestAI();
    expect(controller.aiStatus, 'Hallo (gemini, m)');
    expect(controller.workerURLInput, 'https://coach-ai.example.workers.dev');
    expect(controller.appTokenInput, isEmpty);
    expect(ai.hasToken, isTrue);
  });
}

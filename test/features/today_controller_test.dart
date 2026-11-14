// Port von `TodayViewModelTests`, dazu die zwischengespeicherte KI-Notiz.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/today/today_controller.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  final now = DateTime(2026, 10, 23, 12);
  final today = CalendarDay.fromDate(now);

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  DailyMetrics metrics(int offset, {required double rhr, String? hrv}) => DailyMetrics(today.adding(-offset))
    ..restingHeartRate = rhr
    ..hrvStatus = hrv;

  test('Heute gegen den 7-Tage-Schnitt', () {
    final controller = TodayController(store: store, schedule: null);
    final history = [metrics(0, rhr: 58, hrv: 'BALANCED'), for (var day = 1; day <= 7; day++) metrics(day, rhr: 50)];
    final settings = CoachSettings(store)..profile = UserProfile.seasonPlan;
    controller.update(days: history, activities: const [], settings: settings, now: now);

    final snapshot = controller.snapshot!;
    expect(snapshot.isFromYesterday, isFalse);
    expect(snapshot.recommendation.level, RecoveryLevel.locker);
    expect(snapshot.plan.weekday, 'Freitag');
    expect(snapshot.advice, isNull);
    // Ohne KI-Worker steht die regelbasierte Notiz da.
    expect(controller.notePoints.first, startsWith('Locker / verkürzt'));
    expect(controller.noteSource, TodayController.fallbackSource);
  });

  test('ohne Werte von heute gelten die von gestern', () {
    final controller = TodayController(store: store, schedule: null);
    controller.update(
      days: [metrics(1, rhr: 50, hrv: 'LOW')],
      activities: const [],
      settings: CoachSettings(store),
      now: now,
    );
    expect(controller.snapshot?.isFromYesterday, isTrue);
    expect(controller.snapshot?.recommendation.level, RecoveryLevel.pause);
  });

  test('Einstellungen bleiben gespeichert', () {
    final settings = CoachSettings(store);
    settings.season = settings.season..ftpWatts = 205;
    settings.privacy = PrivacyMode.full;
    final reloaded = CoachSettings(store);
    expect(reloaded.season.ftpWatts, 205);
    expect(reloaded.privacy, PrivacyMode.full);
  });

  test('KI-Notiz: einmal je Tag und Ampelstufe, persönliches Profil mit eigener Aufgabe', () async {
    final tasks = <String>[];
    final transport = FakeHttpTransport((request) {
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      tasks.add(body['task'] as String);
      return HttpResponse(
        200,
        utf8.encode(
          jsonEncode({
            'output': {
              'punkte': ['Heute locker bleiben.'],
              'quellen': ['recovery.hrv'],
            },
            'model': 'test-modell',
            'provider': 'test',
          }),
        ),
      );
    });
    await store.setString(AIClient.urlKey, 'https://coach.example.workers.dev');
    final settings = CoachSettings(store);
    final ai = AIClient(secrets: Secrets.memory({SecretKey.aiAppToken: 'app'}), settings: store, transport: transport)
      ..settings = (() => settings.ai);
    final controller = TodayController(store: store, schedule: null);
    settings.profile = UserProfile(mode: ProfileMode.personal, onboardingDone: true, sports: const [TrainingSport.run]);
    final history = [metrics(0, rhr: 50), for (var day = 1; day <= 7; day++) metrics(day, rhr: 50)];
    controller.update(days: history, activities: const [], settings: settings, now: now);
    expect(controller.snapshot!.advice, isNotNull);
    expect(controller.noteSource, TodayController.fallbackSource);

    await controller.loadNote(ai, settings: settings, force: true);
    expect(tasks, ['personal_note']);
    expect(controller.notePoints, ['Heute locker bleiben.']);
    expect(controller.noteSource, 'KI · test-modell');
    expect(controller.noteEvidence, contains('recovery.hrv'));

    // Zweiter Aufruf ohne „Neu formulieren“ nutzt den Zwischenspeicher, auch nach einem Neustart.
    final restarted = TodayController(store: store, schedule: null)
      ..update(days: history, activities: const [], settings: settings, now: now);
    expect(restarted.noteSource, 'KI · test-modell');
    await restarted.loadNote(ai, settings: settings);
    expect(tasks, hasLength(1));

    // Saisonplan nutzt die Notiz des persönlichen Profils nicht.
    settings.profile = UserProfile.seasonPlan;
    restarted.update(days: history, activities: const [], settings: settings, now: now);
    expect(restarted.noteSource, TodayController.fallbackSource);
  });
}

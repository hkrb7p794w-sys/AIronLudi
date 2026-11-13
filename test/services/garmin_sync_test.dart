// Port von `NetworkClientTests.syncStoresDaysActivitiesAndProfile`.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/repositories/source_store.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/garmin/activity_stores.dart';
import 'package:aironludi/services/garmin/garmin_client.dart';
import 'package:aironludi/services/garmin/garmin_sync_service.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const longLivedToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.c2ln';

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

  (int, String) respond(HttpRequest request, String today) {
    final path = request.url.path;
    if (path.endsWith('/token')) return (200, longLivedToken);
    if (path.endsWith('/v2/dailysummaries')) {
      return (200, '{"data": [{"calendarDate": "$today", "restingHeartRate": 49, "totalSteps": 9000}]}');
    }
    if (path.contains('/hrv/daily/')) {
      return (200, '{"hrvSummaries": [{"calendarDate": "$today", "lastNightAvg": 60, "status": "BALANCED"}]}');
    }
    if (path.contains('/activities/search')) {
      return (200, '[{"activityId": 7, "startTimeLocal": "$today 07:00:00", "activityType": {"typeKey": "running"}}]');
    }
    if (path.endsWith('/userprofile/settings')) return (200, '{"userData": {"weight": 80000, "gender": "MALE"}}');
    if (path.contains('/bodyBattery/')) return (500, '');
    return (200, '[]');
  }

  GarminSyncService service(String today, {SourceStore? sources}) {
    final transport = FakeHttpTransport((request) {
      final (status, body) = respond(request, today);
      return HttpResponse(status, utf8.encode(body));
    });
    final client = GarminClient(secrets: Secrets.memory({SecretKey.garminAPIKey: 'k'}), transport: transport);
    return GarminSyncService(
      client: client,
      settings: settings,
      metrics: MetricsRepository(db),
      activities: ActivityRepository(db),
      raw: RawResponseRepository(db),
      analysisStore: ActivityAnalysisStore(),
      reportStore: ActivityReportStore(),
      sources: sources,
    );
  }

  test('Abruf speichert Tage, Aktivitäten und Profil', () async {
    final now = const CalendarDay(2026, 10, 23).referenceDate;
    final today = CalendarDay.fromDate(now).iso;
    final sync = service(today);

    final report = await sync.sync(now: now);

    expect(report.range.dayCount, SyncPlan.initialDays);
    // Swift-Test: 1. Der Code zählt die Aktivität im einmaligen 13-Wochen-Nachladen ein zweites Mal (gleicher Ablauf
    // wie `syncActivities` in Swift, siehe docs/decisions.md); gespeichert ist sie nur einmal.
    expect(report.activitiesUpdated, 2);
    expect(await ActivityRepository(db).all(), hasLength(1));
    expect(report.errors, hasLength(3)); // Body Battery in drei 28-Tage-Blöcken
    final metrics = await MetricsRepository(db).day(CalendarDay.tryParse(today)!);
    expect(metrics?.restingHeartRate, 49);
    expect(metrics?.hrvStatus, 'BALANCED');
    expect(sync.profile?.weightKilograms, 80);
    expect(sync.lastSync?.isAtSameMomentAs(now), isTrue);
    expect(report.sources, {'Personal API': greaterThan(0)});
    expect(await sync.raw(GarminEndpoint.profileSettings), isNotNull);
  });

  test('mit Quellen-Ablage: Herkunft Garmin', () async {
    final now = const CalendarDay(2026, 10, 23).referenceDate;
    final today = CalendarDay.fromDate(now).iso;
    final sources = SourceStore(db, settings);
    await service(today, sources: sources).sync(now: now);
    final entries = await sources.entries();
    expect(entries.where((entry) => entry.kind == DataKind.activities).single.externalID, '7');
    expect(entries.any((entry) => entry.kind == null && entry.provider == DataProvider.garmin), isTrue);
    expect((await MetricsRepository(db).day(CalendarDay.tryParse(today)!))?.restingHeartRate, 49);
  });
}

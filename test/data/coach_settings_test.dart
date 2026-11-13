// Port der App-Tests zu `CoachSettings` (Personalisierung, Testwerte, Begleiter/Rangliste, Erinnerungen).
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/social/league_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Freitag, 23.10.2026.
const friday = CalendarDay(2026, 10, 23);

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

  /// Neustart: Einstellungen aus der Datenbank neu laden.
  Future<CoachSettings> reload() async {
    await Future<void>.delayed(Duration.zero);
    return CoachSettings(await SettingsStore.open(db));
  }

  CoachSettings personal(List<TrainingSport> sports, FitnessGoal goal, {bool everyDay = false}) {
    final settings = CoachSettings(store);
    final profile = UserProfile(mode: ProfileMode.personal, onboardingDone: true, sports: sports, goal: goal);
    if (everyDay) {
      for (final weekday in Weekday.values) {
        profile.schedule = profile.schedule.withSlots(const [SessionSlot(TrainingSport.run)], weekday);
      }
    } else {
      profile.schedule = profile.schedule
          .withSlots(const [SessionSlot(TrainingSport.run, SessionIntensity.hard)], Weekday.friday)
          .withSlots(const [SessionSlot(TrainingSport.strength, SessionIntensity.hard)], Weekday.saturday);
    }
    settings.profile = profile;
    return settings;
  }

  group('Personalisierung', () {
    test('Neuinstallation startet mit dem Assistenten', () {
      final settings = CoachSettings(store);
      expect(settings.profile.mode, ProfileMode.personal);
      expect(settings.profile.onboardingDone, isFalse);
    });

    test('Bestehende Nutzer behalten den Saisonplan', () async {
      await store.setDate(SettingsKeys.garminLastSync, DateTime.now());
      final settings = CoachSettings(store);
      expect(settings.profile.mode, ProfileMode.season);
      expect(settings.profile.onboardingDone, isTrue);
      // Auch nach dem Neustart.
      expect((await reload()).profile.mode, ProfileMode.season);
    });

    test('Profil bleibt gespeichert', () async {
      final settings = personal(const [TrainingSport.run, TrainingSport.strength], FitnessGoal.loseWeight);
      final reloaded = await reload();
      expect(reloaded.profile, settings.profile);
      expect(reloaded.profile.schedule.slots(Weekday.friday), [
        const SessionSlot(TrainingSport.run, SessionIntensity.hard),
      ]);
    });

    test('Ziel prägt die Ernährung nur im persönlichen Profil', () {
      final settings = personal(const [TrainingSport.run, TrainingSport.strength], FitnessGoal.loseWeight);
      settings.nutrition = settings.nutrition
        ..weightKilograms = 68
        ..heightCentimeters = 168
        ..age = 32
        ..isFemale = true;
      final assessment = settings.applyProfileToNutrition(null, day: friday);
      expect(assessment.nutritionGoal, NutritionGoal.lose);
      expect(settings.nutrition.goal, NutritionGoal.lose);
      expect(settings.nutrition.weeklyWeightChangePercent, -0.5);

      // Saisonplan: Ernährung bleibt unberührt.
      final season = CoachSettings(store)..profile = UserProfile.seasonPlan;
      season.nutrition = NutritionSettings();
      season.applyProfileToNutrition(null, day: friday);
      expect(season.nutrition.weeklyWeightChangePercent, isNull);
    });
  });

  test('Testwert setzt Saison und Verlauf', () async {
    final settings = CoachSettings(store);
    const day = CalendarDay(2026, 12, 7);
    settings
      ..record(TestKind.ftp, 185, on: day)
      ..record(TestKind.css, 128, on: day)
      ..record(TestKind.halfMarathon, 6300, on: day);
    expect(settings.season.ftpWatts, 185);
    expect(settings.season.cssSecondsPer100m, 128);
    expect(settings.halfMarathonSeconds, 6300);
    expect((await reload()).tests, hasLength(3));
  });

  test('Wägung: eine je Tag, die neue ersetzt die alte', () {
    // Älter als 365 Tage vor der neuen Wägung fällt weg.
    final settings = CoachSettings(store)
      ..logWeight(81, on: friday.adding(-400))
      ..logWeight(80, on: friday)
      ..logWeight(79.5, on: friday);
    expect(settings.weights.map((entry) => entry.kilograms), [79.5]);
  });

  group('Erinnerungen', () {
    test('ReminderSettings lesen tolerant', () {
      final decoded = ReminderSettings.fromJson(jsonDecode('{"hour":30}'));
      expect(decoded.enabled, isTrue);
      expect(decoded.hour, 23);
      expect(decoded.minute, 30);
    });

    test('Ausnahmen gelten nur für diese Woche und bleiben nach dem Neustart', () async {
      final settings = personal(const [TrainingSport.run], FitnessGoal.improveFitness, everyDay: true);
      final today = CalendarDay.today();
      settings.planAdjustments = settings.planAdjustments..skip(Weekday.values[today.weekdayIndex], inWeekOf: today);
      expect(settings.schedule(today).slots(Weekday.values[today.weekdayIndex]), isEmpty);
      expect(settings.schedule(today.adding(7)), settings.profile.schedule);
      expect((await reload()).planAdjustments, settings.planAdjustments);
      settings.planAdjustments = settings.planAdjustments..undo(Weekday.values[today.weekdayIndex], inWeekOf: today);
      expect(settings.schedule(today), settings.profile.schedule);
    });
  });

  group('Begleiter und Rangliste', () {
    late (int, String) Function(HttpRequest request) handler;
    late FakeHttpTransport transport;

    AIClient client() {
      handler = (_) => (200, '{}');
      transport = FakeHttpTransport((request) {
        final (status, body) = handler(request);
        return HttpResponse(status, utf8.encode(body));
      });
      return AIClient(secrets: Secrets.memory(), settings: store, transport: transport);
    }

    test('Mitglieds-ID bleibt stabil, Begleiter ist aus', () async {
      final settings = personal(const [TrainingSport.run], FitnessGoal.improveFitness, everyDay: true);
      expect(settings.companion.isActive, isFalse);
      expect(settings.league.isJoined, isFalse);
      expect((await reload()).league.memberID, settings.league.memberID);
      settings.companion = CompanionSettings(enabled: true, name: 'Daisy');
      expect((await reload()).companion.displayName, 'Daisy');
    });

    test('Einladung richtet den Worker ein und tritt bei', () async {
      final settings = personal(const [TrainingSport.run], FitnessGoal.improveFitness, everyDay: true);
      final ai = client();
      final league = LeagueService(ai: ai, settings: settings);
      expect(league.canUse, isFalse);
      await league.accept(
        const LeagueInvite(
          workerURL: 'https://coach-ai.example.workers.dev',
          token: 'g1.abcdefghijk2.0123',
          code: 'team-abc234xyz9',
        ),
      );
      expect(league.canUse, isTrue);
      expect(settings.league.code, 'team-abc234xyz9');
      // Gäste laden nicht weiter ein und sehen die private SideStore-Quelle nicht.
      expect(ai.isGuest, isTrue);
      expect(league.canInvite, isFalse);
      expect(ai.sideStoreSourceURL, isNull);
    });

    test('Einladung enthält ein frisches Gast-Token, nie das eigene', () async {
      final settings = personal(const [TrainingSport.run], FitnessGoal.improveFitness, everyDay: true);
      final ai = client();
      await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'haupt-token');
      settings.league = settings.league..code = 'team-abc234xyz9';
      final league = LeagueService(ai: ai, settings: settings);
      expect(league.canInvite, isTrue);
      handler = (_) => (200, '{"id":"abcdefghijk2","token":"g1.abcdefghijk2.0123"}');
      final url = (await league.makeInvite())!;
      expect(LeagueInvite.fromUri(url)?.token, 'g1.abcdefghijk2.0123');
      expect(url.toString(), isNot(contains('haupt-token')));
      expect(transport.requests.first.url.path, '/v1/invite');
      expect(transport.requests.first.method, 'POST');
    });

    test('Abgleich sendet nur Name und Punkte', () async {
      final settings = personal(const [TrainingSport.run], FitnessGoal.improveFitness, everyDay: true);
      final ai = client();
      await ai.configure(url: 'https://coach-ai.example.workers.dev', token: 'tok-123');
      settings.league = settings.league
        ..code = 'team-abc234xyz9'
        ..name = 'Lea';
      final league = LeagueService(ai: ai, settings: settings);
      final me = settings.league.memberID;
      handler = (request) => request.method == 'PUT'
          ? (200, '{"member":{}}')
          : (
              200,
              '{"members":[{"id":"$me","name":"Lea","avatar":"person.fill","week":"2026-10-26","weekPoints":20,'
                  '"totalPoints":20,"streak":0,"done":2,"planned":7}]}',
            );
      final today = CalendarDay.today();
      final summary = MotivationSummary.compute(
        schedule: settings.schedule,
        trainingDays: {today},
        today: today,
        weeks: 1,
      );
      await league.sync(summary);
      expect(league.lastError, isNull);
      expect(league.members.first.name, 'Lea');
      final put = transport.requests.first;
      expect(put.url.path, '/v1/league/team-abc234xyz9/members/$me');
      expect(put.headers['Authorization'], 'Bearer tok-123');
      expect(transport.requests.last.url.query, contains('week='));
    });
  });
}

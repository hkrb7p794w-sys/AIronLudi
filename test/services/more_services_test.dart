// Open Food Facts, wartende Auswertungen, Workout an Garmin senden, Krafttraining mit Garmin abgleichen.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/garmin/garmin_connect_session.dart';
import 'package:aironludi/services/garmin/garmin_workout_service.dart';
import 'package:aironludi/services/gym/garmin_strength_service.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:aironludi/services/nutrition/pending_analysis.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const connectToken =
    'eyJhbGciOiJSUzI1NiJ9.eyJjbGllbnRfaWQiOiJHQVJNSU5fQ09OTkVDVF9NT0JJTEVfSU9TX0RJIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2ln';

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late Directory temp;
  late (int, String) Function(HttpRequest request) handler;
  final requests = <HttpRequest>[];

  HttpTransport transport({bool cookies = false}) => FakeHttpTransport((request) {
    requests.add(request);
    final (status, body) = handler(request);
    return HttpResponse(status, utf8.encode(body));
  });

  GarminConnectSession loggedIn() {
    final token = ConnectToken(
      accessToken: connectToken,
      refreshToken: 'r1',
      clientID: 'GARMIN_CONNECT_MOBILE_IOS_DI',
      expiresAt: DateTime.utc(2100),
    );
    return GarminConnectSession(
      secrets: Secrets.memory({SecretKey.garminConnectToken: jsonEncode(token.toJson())}),
      settings: settings,
      makeTransport: transport,
      pause: () async {},
    );
  }

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    temp = Directory.systemTemp.createTempSync('coach-test');
    requests.clear();
    handler = (_) => (200, '{}');
  });

  tearDown(() async {
    await settings.close();
    await db.close();
    temp.deleteSync(recursive: true);
  });

  group('Open Food Facts', () {
    test('ungültiger Barcode ohne Netzwerk', () async {
      final client = OpenFoodFactsClient(transport: transport());
      await expectLater(client.product('4006381333932'), throwsA(FoodLookupError.invalidBarcode));
      expect(requests, isEmpty);
    });

    test('Produkt mit eigener Kennung, sonst nicht gefunden', () async {
      final client = OpenFoodFactsClient(transport: transport());
      handler = (_) =>
          (200, '{"status": 1, "product": {"product_name_de": "Haferriegel", "nutriments": {"energy_100g": 1674}}}');
      final product = await client.product('4006381333931');
      expect(product.name, 'Haferriegel');
      expect(requests.single.headers['User-Agent'], OpenFoodFacts.userAgent);
      handler = (_) => (404, '{"status": 0}');
      await expectLater(client.product('4006381333931'), throwsA(FoodLookupError.notFound));
    });

    test('Netzwerkfehler', () async {
      final client = OpenFoodFactsClient(
        transport: FakeHttpTransport((_) => throw const HttpTransportException('offline')),
      );
      await expectLater(client.product('4006381333931'), throwsA(const FoodLookupError.network('offline')));
    });
  });

  test('Wartende Auswertung mit Foto bleibt erhalten', () async {
    final store = PendingAnalysisStore(settings, folder: temp.path);
    final item = store.create(text: 'Nudeln mit Pesto', photo: Uint8List.fromList([1, 2, 3]));
    await store.save([item]);
    final loaded = store.load();
    expect(loaded, [item]);
    expect(store.photo(loaded.single), [1, 2, 3]);
    store.deletePhoto(loaded.single);
    expect(store.photo(loaded.single), isNull);
  });

  group('Workout an Garmin senden', () {
    final plan = GarminWorkout.plan(name: 'Lockerer Lauf', sport: WorkoutSport.run, text: '40 min locker');
    const day = CalendarDay(2026, 11, 14);

    test('ohne Anmeldung ein Hinweis', () async {
      final coach = CoachSettings(settings);
      final text = await GarminWorkoutService.send(plan, day: day, connect: null, settings: coach);
      expect(text, contains('Anmeldung mit dem Garmin-Konto'));
    });

    test('erneutes Senden ersetzt das alte Workout', () async {
      final coach = CoachSettings(settings);
      handler = (request) => request.url.path == GarminWorkout.createPath ? (200, '{"workoutId": 77}') : (200, '{}');
      final connect = loggedIn();
      final first = await GarminWorkoutService.send(
        plan,
        day: day,
        connect: connect,
        settings: coach,
        now: DateTime(2026, 11, 13),
      );
      expect(first, contains('14.11.2026'));
      expect(coach.sentWorkouts.ids.values, [77]);
      await GarminWorkoutService.send(plan, day: day, connect: connect, settings: coach, now: DateTime(2026, 11, 13));
      expect(requests.where((request) => request.method == 'DELETE').single.url.path, GarminWorkout.workoutPath(77));
      expect(requests.where((request) => request.url.path == GarminWorkout.schedulePath(77)), hasLength(2));
    });
  });

  group('Krafttraining mit Garmin abgleichen', () {
    GymSession session(DateTime start) => GymSession(
      workoutKey: null,
      title: 'Push A',
      start: start,
      end: start.add(const Duration(hours: 1)),
      exercises: [
        LoggedExercise(
          exerciseID: 'bankdruecken',
          name: 'Bankdrücken',
          group: MuscleGroup.chest,
          sets: [LoggedSet(reps: 8, weightKg: 60)],
        ),
      ],
      garmin: GarminLink(status: GarminLinkStatus.pending, updatedAt: start),
    );

    test('ohne Aufzeichnung der Uhr: warten', () async {
      final gym = GymRepository(db);
      final now = DateTime.now();
      await gym.save(session(now.subtract(const Duration(minutes: 30))));
      handler = (_) => (200, '[]');
      final service = GarminStrengthService(gym: gym, activities: ActivityRepository(db), folder: temp.path);
      final message = await service.reconcile(garmin: loggedIn(), gym: GymSettings(), now: now);
      expect(message, startsWith('Wartet auf die Aufzeichnung der Uhr'));
    });

    test('mit Aufzeichnung: Sätze hineinschreiben und Original sichern', () async {
      final gym = GymRepository(db);
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 1));
      final stored = session(start);
      await gym.save(stored);
      String two(int value) => value.toString().padLeft(2, '0');
      final local =
          '${start.year}-${two(start.month)}-${two(start.day)} ${two(start.hour)}:${two(start.minute)}:${two(start.second)}';
      await ActivityRepository(db).upsert(
        GarminActivity(42)
          ..typeKey = 'strength_training'
          ..startLocal = local
          ..durationSeconds = 3600
          ..averageHeartRate = 110
          ..provider = DataProvider.garmin,
      );
      handler = (request) {
        if (request.url.path.endsWith('/exerciseSets')) return (200, '{"activityId": 42, "exerciseSets": []}');
        return (200, '[]');
      };
      final service = GarminStrengthService(gym: gym, activities: ActivityRepository(db), folder: temp.path);
      final message = await service.reconcile(garmin: loggedIn(), gym: GymSettings(), now: now);
      expect(message, contains('Sätze in die Garmin-Aufzeichnung'));
      expect(service.hasBackup(42), isTrue);
      final link = (await gym.byID(stored.id))?.session.garmin;
      expect(link?.status, GarminLinkStatus.enriched);
      expect(link?.activityID, 42);
      expect(requests.where((request) => request.method == 'PUT'), isNotEmpty);
    });
  });
}

// Fotos gehen bei fehlgeschlagener Auswertung nicht verloren: erneut versuchen, später automatisch eintragen (auch im
// Hintergrund, mit der Uhrzeit der Aufnahme).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/nutrition/nutrition_controller.dart';
import 'package:aironludi/platform/notifications.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/open_food_facts_client.dart';
import 'package:aironludi/services/nutrition/pending_analysis.dart';
import 'package:aironludi/services/nutrition/pending_meal_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Antwort der KI auf `meal_analyze`: Käsespätzle mit Röstzwiebeln.
const _analysis = {
  'model': 'test',
  'provider': 'test',
  'output': {
    'titel': 'Käsespätzle',
    'kategorie': 'abendessen',
    'hinweis': 'Portion geschätzt.',
    'items': [
      {
        'name': 'Käsespätzle',
        'menge_g': 400,
        'naehrwerte_100g': {'kcal': 175, 'protein_g': 8, 'carbs_g': 20, 'fat_g': 7},
      },
    ],
  },
};

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late CoachSettings settings;
  late MealRepository meals;
  late Directory temp;
  late AIClient ai;
  var now = DateTime(2026, 11, 26, 18, 45);
  var status = 200;
  final photo = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
  final requests = <HttpRequest>[];

  setUpAll(() => initializeDateFormatting('de_DE'));

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    await store.setString(SettingsKeys.workerURL, 'https://coach-ai.example.workers.dev');
    settings = CoachSettings(store)..profile = UserProfile.seasonPlan;
    meals = MealRepository(db);
    temp = Directory.systemTemp.createTempSync('pending-meals');
    now = DateTime(2026, 11, 26, 18, 45);
    status = 200;
    requests.clear();
    ai = AIClient(
      secrets: Secrets.memory({SecretKey.aiAppToken: 'tok'}),
      settings: store,
      transport: FakeHttpTransport((request) {
        requests.add(request);
        return status == 200
            ? HttpResponse(200, utf8.encode(jsonEncode(_analysis)))
            : HttpResponse(status, utf8.encode('{"error": "overloaded"}'));
      }),
    );
  });

  tearDown(() async {
    await store.close();
    await db.close();
    temp.deleteSync(recursive: true);
  });

  PendingAnalysisStore pendingStore() => PendingAnalysisStore(store, folder: temp.path);

  NutritionController controller() => NutritionController(
    meals: meals,
    settings: settings,
    ai: ai,
    openFoodFacts: OpenFoodFactsClient(transport: FakeHttpTransport((_) => HttpResponse(404, const []))),
    pendingStore: pendingStore(),
    clock: () => now,
  );

  test('KI überlastet: Foto bleibt gesichert, „Erneut versuchen“ ohne neues Foto öffnet den Editor', () async {
    final model = controller();
    status = 503;
    expect(await model.analyze('ohne Soße', photo: photo, foods: const []), isFalse);
    final failure = model.failedAnalysis!;
    expect(failure.temporary, isTrue);
    expect(failure.message, contains('überlastet'));
    expect(model.draft, isNull);
    expect(model.waiting.single.text, 'ohne Soße');
    expect(model.pendingPhoto(model.waiting.single), photo);
    // Auch nach einem Neustart der App noch da.
    expect(pendingStore().load().single.lastError, failure.message);

    status = 200;
    expect(await model.retryItem(failure.item, const []), isTrue);
    expect(model.failedAnalysis, isNull);
    expect(model.draft?.title, 'Käsespätzle');
    expect(model.draft?.photo, photo);
    expect(model.draft?.date, now);
    expect(model.waiting, isEmpty);
    expect(pendingStore().load(), isEmpty);
    // Das Foto ging bei beiden Versuchen mit.
    expect(requests.every((request) => utf8.decode(request.body!).contains('"images"')), isTrue);
  });

  test('ohne Netz: Später automatisch eintragen – mit Uhrzeit und Mahlzeit der Aufnahme', () async {
    final model = controller();
    final transportFails = AIClient(
      secrets: Secrets.memory({SecretKey.aiAppToken: 'tok'}),
      settings: store,
      transport: FakeHttpTransport((_) => throw const HttpTransportException('offline')),
    );
    final offline = NutritionController(
      meals: meals,
      settings: settings,
      ai: transportFails,
      pendingStore: pendingStore(),
      clock: () => now,
    )..preferredCategory = MealCategory.lunch;
    expect(await offline.analyze('', photo: photo, foods: const []), isFalse);
    final failure = offline.failedAnalysis!;
    expect(failure.temporary, isTrue);
    await offline.autoLogLater(failure.item);
    expect(offline.waiting.single.autoLog, isTrue);

    // Später, wieder online: noch nicht fällig (2 Minuten Abstand) …
    now = now.add(const Duration(minutes: 1));
    await model.retryPending(const []);
    expect(await meals.all(), isEmpty);
    // … dann ohne Editor eingetragen, mit „Rückgängig“.
    now = now.add(const Duration(hours: 2));
    await model.retryPending(const []);
    final stored = (await meals.all()).single;
    expect(stored.title, 'Käsespätzle');
    expect(stored.createdAt, DateTime(2026, 11, 26, 18, 45));
    expect(stored.category, MealCategory.lunch);
    expect(stored.hint, contains(PendingMealService.autoHint));
    expect(stored.items.single.grams, 400);
    expect(model.draft, isNull);
    expect(model.lastLogged?.label, 'Käsespätzle automatisch nachgetragen');
    expect(model.waiting, isEmpty);
    expect(temp.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('im Hintergrund: eintragen und per Mitteilung melden; offen bleibt, was weiter fehlschlägt', () async {
    final created = pendingStore().create(
      text: 'Spätzle',
      photo: photo,
      created: now,
      mealTime: DateTime(2026, 11, 25, 19, 30),
      autoLog: true,
    );
    final center = FakeNotificationCenter();
    PendingMealService service() =>
        PendingMealService(store: pendingStore(), ai: ai, meals: meals, settings: settings, notifications: center);

    status = 502;
    expect(await service().processDue(notify: true), isEmpty);
    final failed = pendingStore().load().single;
    expect(failed.attempts, 1);
    expect(failed.autoLog, isTrue);
    expect(service().hasAutoLog, isTrue);
    expect(center.pending, isEmpty);

    status = 200;
    final waiting = PendingMealService(
      store: pendingStore(),
      ai: ai,
      meals: meals,
      settings: settings,
      notifications: center,
      clock: () => DateTime.now().add(const Duration(hours: 1)),
    );
    final logged = await waiting.processDue(notify: true);
    expect(logged.single.id, (await meals.all()).single.id);
    expect(logged.single.day, const CalendarDay(2026, 11, 25));
    expect(logged.single.category, MealCategory.dinner);
    expect(center.pending.values.single.body, 'Käsespätzle · 700 kcal · Abendessen um 19:30');
    expect(pendingStore().load(), isEmpty);
    expect(pendingStore().photo(created), isNull);
  });

  test('KI erkennt nichts: kein automatisches Eintragen anbieten', () async {
    final model = controller();
    final empty = AIClient(
      secrets: Secrets.memory({SecretKey.aiAppToken: 'tok'}),
      settings: store,
      transport: FakeHttpTransport(
        (_) => HttpResponse(200, utf8.encode('{"model": "m", "provider": "p", "output": {"items": []}}')),
      ),
    );
    final blind = NutritionController(meals: meals, settings: settings, ai: empty, pendingStore: pendingStore());
    expect(await blind.analyze('', photo: photo, foods: const []), isFalse);
    expect(blind.failedAnalysis?.temporary, isFalse);
    await blind.removePending(blind.failedAnalysis!.item);
    expect(model.waiting, isEmpty);
    expect(pendingStore().load(), isEmpty);
  });

  test('gerade belegt (Hintergrund wertet aus): kein doppelter Eintrag', () async {
    final item = pendingStore().create(text: 'Reis', photo: photo, created: now, autoLog: true);
    final background = pendingStore();
    expect(background.claim(item), isTrue);
    final service = PendingMealService(store: pendingStore(), ai: ai, meals: meals, settings: settings);
    expect(await service.processDue(), isEmpty);
    expect(requests, isEmpty);
    background.release(item);
    expect(await service.processDue(), hasLength(1));
  });
}

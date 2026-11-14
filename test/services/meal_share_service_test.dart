// Mahlzeit teilen über den Worker: Anlegen, Abrufen, Zurückziehen, Link.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/meal_share_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('Anlegen, Abrufen und Zurückziehen mit dem App-Token', () async {
    final requests = <HttpRequest>[];
    final meal = SharedMeal(
      title: 'Reis mit Hähnchen',
      items: [
        MealItem(
          name: 'Reis',
          grams: 150,
          source: MealItemSource.manual,
          per100g: NutrientValues({Nutrient.kcal: 130}),
        ),
      ],
    );
    final transport = FakeHttpTransport((request) {
      requests.add(request);
      final body = switch (request.method) {
        'POST' => '{"code": "k7m2q9xa4b", "expiresAt": "2026-11-21T00:00:00Z"}',
        'GET' when request.url.path.endsWith('/unbekannt') => '{"error": "nicht gefunden"}',
        'GET' => jsonEncode(meal.toJson()),
        _ => '{}',
      };
      return HttpResponse(request.url.path.endsWith('/unbekannt') ? 404 : 200, utf8.encode(body));
    });
    final ai = AIClient(
      secrets: Secrets.memory({SecretKey.aiAppToken: 'app'}),
      settings: settings,
      transport: transport,
    );
    await settings.setString(AIClient.urlKey, 'https://coach.example.workers.dev');
    final service = MealShareService(ai);

    final created = await service.share(meal);
    expect(created.code, 'k7m2q9xa4b');
    expect(requests.last.url.toString(), 'https://coach.example.workers.dev/v1/share/meal');
    expect(requests.last.headers['Authorization'], 'Bearer app');
    expect(jsonDecode(utf8.decode(requests.last.body!)), meal.toJson());

    final fetched = await service.fetch('k7m2q9xa4b');
    expect(fetched.title, 'Reis mit Hähnchen');
    expect(fetched.kilocalories, closeTo(195, 0.01));
    await expectLater(service.fetch('unbekannt'), throwsA(isA<AIHttpError>().having((e) => e.status, 'status', 404)));

    await service.revoke('k7m2q9xa4b');
    expect(requests.last.method, 'DELETE');
    expect(service.link('k7m2q9xa4b').toString(), 'https://coach.example.workers.dev/m/k7m2q9xa4b');
  });
}

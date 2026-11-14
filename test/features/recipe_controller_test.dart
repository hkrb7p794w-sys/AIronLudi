// Rezeptideen: Zeitraum, Ziele je Tag, Erstellen in Teilen, fehlende Tage nachfordern, Speichern, Einkaufsliste.
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/recipes/recipe_controller.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _dish(String title, String meal, String food, double kcal) => {
  'titel': title,
  'mahlzeit': meal,
  'minuten': 15,
  'zubereitung': ['Alles mischen.'],
  'zutaten': [
    {
      'name': food,
      'menge_g': 200,
      'naehrwerte_100g': {'kcal': kcal, 'protein_g': 12},
    },
  ],
};

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late Directory folder;
  final now = DateTime(2026, 11, 16, 9);

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    folder = Directory.systemTemp.createTempSync('recipes');
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  AIClient ai({required bool skipLastDay, List<int>? batchSizes}) {
    final transport = FakeHttpTransport((request) {
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      final days = ((body['input'] as Map)['days'] as List).cast<Map<String, Object?>>();
      batchSizes?.add(days.length);
      final output = {
        'tage': [
          for (final day in days)
            if (!(skipLastDay && day['datum'] == '2026-11-18'))
              {
                'datum': day['datum'],
                'gerichte': [
                  _dish('Porridge', 'fruehstueck', 'Haferflocken', 370),
                  _dish('Nudeln mit Linsen', 'mittagessen', 'Rote Linsen', 340),
                  _dish('Gemüsepfanne', 'abendessen', 'Kartoffeln', 300),
                ],
              },
        ],
      };
      return HttpResponse(200, utf8.encode(jsonEncode({'output': output, 'model': 'test', 'provider': 'test'})));
    });
    return AIClient(secrets: Secrets.memory({SecretKey.aiAppToken: 'app'}), settings: store, transport: transport);
  }

  test('Zeitraum, gleiche Ziele, Erstellen in Teilen, fehlende Tage und Einkaufsliste', () async {
    await store.setString(AIClient.urlKey, 'https://coach.example.workers.dev');
    final settings = CoachSettings(store);
    final controller = RecipeController(store: store, folder: () async => folder, clock: () => now)
      ..setPeriod(start: CalendarDay.fromDate(now), days: 3);
    controller.update(settings: settings, garminProfile: null, meals: const []);
    expect(controller.targets.map((target) => target.day.iso), ['2026-11-16', '2026-11-17', '2026-11-18']);
    expect(controller.targets.map((target) => target.kcal).toSet(), hasLength(1));

    final sizes = <int>[];
    await controller.generate(
      ai: ai(skipLastDay: true, batchSizes: sizes),
      settings: settings,
      favorites: const [],
    );
    // Zwei Anfragen (2 + 1 Tage), dann der fehlende Tag einmal nachgefordert – die Antwort lässt ihn wieder weg.
    expect(sizes, [2, 1, 1]);
    expect(controller.plan!.days.map((day) => day.day.iso), ['2026-11-16', '2026-11-17']);
    expect(controller.missing.single.day.iso, '2026-11-18');
    expect(controller.plan!.notes.last, contains('„Fehlende Tage erstellen“'));

    await controller.generate(ai: ai(skipLastDay: false), settings: settings, favorites: const [], missingOnly: true);
    expect(controller.missing, isEmpty);
    expect(controller.plan!.days, hasLength(3));

    // Gespeichert wie in Swift (recipes.json) und wieder lesbar.
    final reloaded = RecipeController(store: store, folder: () async => folder, clock: () => now);
    await reloaded.load();
    expect(reloaded.plan!.days, hasLength(3));
    expect(reloaded.length, 3);

    final list = RecipePlanner.shoppingList(controller.plan!, servings: 2);
    controller.toggle(list.first);
    expect(controller.checked, {list.first.id});
    expect(RecipeController(store: store, folder: () async => folder, clock: () => now).checked, {list.first.id});
  });

  test('ohne Worker ein Hinweis', () async {
    final controller = RecipeController(store: store, folder: () async => folder, clock: () => now);
    controller.update(settings: CoachSettings(store), garminProfile: null, meals: const []);
    final ai = AIClient(
      secrets: Secrets.memory({}),
      settings: store,
      transport: FakeHttpTransport((_) => HttpResponse(500, [])),
    );
    await controller.generate(ai: ai, settings: CoachSettings(store), favorites: const []);
    expect(controller.errorMessage, contains('KI-Worker'));
    expect(controller.plan, isNull);
  });
}

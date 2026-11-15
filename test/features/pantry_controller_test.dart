// Rezepte aus dem Kühlschrank-Foto: Foto an den Worker, Rückfragen beantworten, mit Antworten neu vorschlagen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/recipes/pantry_controller.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _dish(String title, List<String> missing) => {
  'titel': title,
  'mahlzeit': 'abendessen',
  'minuten': 15,
  'zubereitung': ['Anbraten.'],
  'zutaten': [
    {
      'name': 'Testgemüse',
      'menge_g': 300,
      'naehrwerte_100g': {'kcal': 120, 'protein_g': 8},
    },
  ],
  'fehlt': missing,
};

void main() {
  late CoachDatabase db;
  late SettingsStore store;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    await store.setString(AIClient.urlKey, 'https://coach.example.workers.dev');
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  test('Foto, Rückfrage „Ist noch Butter da?“, neu vorschlagen mit Antworten', () async {
    final bodies = <Map<String, Object?>>[];
    final transport = FakeHttpTransport((request) {
      final body = (jsonDecode(utf8.decode(request.body!)) as Map).cast<String, Object?>();
      bodies.add(body);
      final input = body['input']! as Map;
      final denied = (input['nicht_da'] as List).cast<String>();
      final output = denied.contains('Butter')
          ? {
              'erkannt': ['Eier', 'Paprika'],
              'gerichte': [_dish('Paprika-Eier aus dem Ofen', [])],
            }
          : {
              'erkannt': ['Eier', 'Paprika'],
              'gerichte': [
                _dish('Omelett', ['Butter']),
              ],
            };
      return HttpResponse(200, utf8.encode(jsonEncode({'output': output, 'model': 'test', 'provider': 'test'})));
    });
    final ai = AIClient(secrets: Secrets.memory({SecretKey.aiAppToken: 'app'}), settings: store, transport: transport);
    final controller = PantryController(
      ai: ai,
      settings: CoachSettings(store),
      clock: () => DateTime(2026, 11, 15, 19),
    );
    expect(controller.canAsk, isTrue);

    controller.setPhoto(Uint8List.fromList([1, 2, 3]));
    await controller.suggest();
    expect(bodies.single['task'], 'pantry_recipes');
    expect(bodies.single['images'], hasLength(1));
    expect((bodies.single['input']! as Map)['mahlzeit'], 'abendessen');
    expect(controller.detected, ['Eier', 'Paprika']);
    expect(controller.questions, ['Butter']);
    expect(controller.status(controller.recipes.single), PantryRecipeStatus.waiting);

    // „Nein“: Das Omelett geht nicht, also neu fragen – mit der Antwort und der korrigierten Liste.
    controller
      ..answer('Butter', available: false)
      ..removeDetected('Paprika')
      ..addDetected('Spinat');
    expect(controller.allBlocked, isTrue);
    expect(controller.questions, isEmpty);
    await controller.suggest();
    final second = bodies.last['input']! as Map;
    expect(second['nicht_da'], ['Butter']);
    expect(second['erkannt'], ['Eier', 'Spinat']);
    expect(controller.recipes.single.recipe.title, 'Paprika-Eier aus dem Ofen');
    expect(controller.status(controller.recipes.single), PantryRecipeStatus.ready);
    // Die korrigierte Liste bleibt; neu Erkanntes kommt dazu.
    expect(controller.detected, ['Eier', 'Spinat', 'Paprika']);

    // „Ja“ statt „Nein“ macht ein wartendes Gericht fertig.
    controller.answer('Butter', available: true);
    expect(controller.denied, isEmpty);
    expect(controller.confirmed, {'Butter'});
  });

  test('ohne Worker: Hinweis statt Anfrage', () async {
    await store.setString(AIClient.urlKey, '');
    final ai = AIClient(secrets: Secrets.memory(), settings: store);
    final controller = PantryController(ai: ai, settings: CoachSettings(store))..setPhoto(Uint8List.fromList([1]));
    await controller.suggest();
    expect(controller.errorMessage, AIClientError.notConfigured.message);
  });
}

// Gemeinsam kochen: eigene Ziele, Freigabe neu abrufen, Vorkochen prüfen, Speichern, Lösen und abgelaufene Freigaben.
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/recipes/cook_plan_controller.dart';
import 'package:aironludi/features/recipes/recipe_controller.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/nutrition/cook_share_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _dish(String title, {required bool prep, int fridge = 3}) => {
  'titel': title,
  'mahlzeit': 'abendessen',
  'minuten': 30,
  'zubereitung': ['Kochen.'],
  'zutaten': [
    {
      'name': 'Rote Linsen',
      'menge_g': 150,
      'naehrwerte_100g': {'kcal': 340, 'protein_g': 24},
    },
  ],
  'vorkochen_geeignet': prep,
  'haltbarkeit_tage': fridge,
  'einfrierbar': false,
  'lagerung': 'Luftdicht im Kühlschrank.',
  'aufwaermen': 'In der Pfanne.',
  'kompromiss': 'Mehr Linsen für Person 2.',
};

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late Directory folder;
  final now = DateTime(2026, 11, 16, 9);
  const code = 'abcde12345';

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    folder = Directory.systemTemp.createTempSync('cook');
    await store.setString(AIClient.urlKey, 'https://coach.example.workers.dev');
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  AIClient ai(FakeHttpTransport transport) =>
      AIClient(secrets: Secrets.memory({SecretKey.aiAppToken: 'app'}), settings: store, transport: transport);

  HttpResponse json(Object value, {int status = 200}) => HttpResponse(status, utf8.encode(jsonEncode(value)));

  List<RecipeDayTarget> targets(CoachSettings settings) {
    final recipes = RecipeController(store: store, folder: () async => folder, clock: () => now)
      ..update(settings: settings, garminProfile: null, meals: const []);
    return recipes.targets;
  }

  test('für beide, zwei Tage: Freigabe neu abgerufen, ungeeignete Gerichte verworfen, gespeichert, Lösen', () async {
    final settings = CoachSettings(store)
      ..cookPartners = [
        CookPartner(
          code: code,
          share: CookShare(name: 'Sam', kcal: 1800),
        ),
      ];
    Map<String, Object?>? input;
    final transport = FakeHttpTransport((request) {
      if (request.url.path.endsWith('v1/share/cook/$code')) {
        return json({'name': 'Sam', 'kcal': 2000, 'protein': 120, 'diet': 'vegetarisch', 'allergens': <String>[]});
      }
      input = ((jsonDecode(utf8.decode(request.body!)) as Map)['input'] as Map).cast();
      return json({
        'output': {
          'rezepte': [_dish('Linsen-Dal', prep: true), _dish('Salat', prep: false)],
        },
        'model': 'test',
        'provider': 'test',
      });
    });
    final controller = CookPlanController(folder: () async => folder, clock: () => now);
    await controller.createCookPlans(
      audience: CookAudience.both,
      partner: settings.cookPartners.single,
      meal: MealCategory.dinner,
      amount: const CookDays(2),
      targets: targets(settings),
      ai: ai(transport),
      settings: settings,
      garminProfile: null,
      favorites: const ['Haferflocken'],
    );
    expect(controller.cookError, isNull);
    // Namen gehen nicht an die KI.
    expect(jsonEncode(input), isNot(contains('Sam')));
    expect(input!['vorkochen'], isTrue);
    expect(input!['diet'], 'vegetarisch');
    expect(settings.cookPartners.single.share.kcal, 2000);
    final plan = controller.cookPlans.single;
    expect(plan.title, 'Linsen-Dal');
    expect(plan.people.map((person) => person.id), [CookPerson.meID, code]);
    expect(plan.storagePlan, [CookStorage.fresh, CookStorage.fridge]);
    expect(controller.cookNotes.single, contains('„Salat“ verworfen'));

    // Gespeichert wie in Swift (cook-plans.json) und wieder lesbar.
    expect(File('${folder.path}/cook-plans.json').existsSync(), isTrue);
    final reloaded = CookPlanController(folder: () async => folder, clock: () => now);
    await reloaded.load();
    expect(reloaded.cookPlans.single.title, 'Linsen-Dal');

    // Lösen: Verbindung und Pläne mit den Angaben der Person verschwinden.
    await reloaded.forget(settings.cookPartners.single, settings: settings);
    expect(settings.cookPartners, isEmpty);
    expect(reloaded.cookPlans, isEmpty);
  });

  test('zurückgezogene Freigabe: Angaben gelöscht, Hinweis', () async {
    final settings = CoachSettings(store)
      ..cookPartners = [
        CookPartner(
          code: code,
          share: CookShare(name: 'Sam'),
        ),
      ];
    final controller = CookPlanController(folder: () async => folder, clock: () => now);
    await controller.createCookPlans(
      audience: CookAudience.partner,
      partner: settings.cookPartners.single,
      meal: MealCategory.lunch,
      amount: const CookPortions(1),
      targets: targets(settings),
      ai: ai(FakeHttpTransport((_) => json({'error': 'not found'}, status: 404))),
      settings: settings,
      garminProfile: null,
      favorites: const [],
    );
    expect(controller.cookError, contains('zurückgezogen'));
    expect(settings.cookPartners, isEmpty);
  });

  test('ohne Worker ein Hinweis; eigene Ziele ohne Namen der Person', () async {
    final settings = CoachSettings(store);
    final controller = CookPlanController(folder: () async => folder, clock: () => now);
    final me = controller.myself(targets: targets(settings), settings: settings, garminProfile: null);
    expect(me.id, CookPerson.meID);
    expect(me.share.name, 'Ich');
    expect(me.share.kcal, isNotNull);
    await controller.createCookPlans(
      audience: CookAudience.me,
      partner: null,
      meal: MealCategory.dinner,
      amount: const CookPortions(2),
      targets: const [],
      ai: AIClient(secrets: Secrets.memory({}), settings: store, transport: FakeHttpTransport((_) => json({}))),
      settings: settings,
      garminProfile: null,
      favorites: const [],
    );
    expect(controller.cookError, contains('KI-Worker'));
  });

  test('Freigabe-Dienst: anlegen, ändern, abrufen, zurückziehen, Links', () async {
    final transport = FakeHttpTransport((request) {
      return switch (request.method) {
        'POST' => json({'code': code, 'expiresAt': '2027-02-14'}),
        'PUT' => json({'code': code, 'expiresAt': '2027-02-15'}),
        'GET' => json({'name': 'Sam', 'allergens': <String>[]}),
        _ => json({'ok': true}),
      };
    });
    final service = CookShareService(ai(transport));
    final created = await service.publish(CookShare(name: 'Ich'));
    expect((created.code, created.expiresAt), (code, '2027-02-14'));
    expect(await service.update(CookShare(name: 'Ich'), code: code), '2027-02-15');
    expect((await service.fetch(code)).name, 'Sam');
    await service.revoke(code);
    expect(transport.requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /v1/share/cook',
      'PUT /v1/share/cook/$code',
      'GET /v1/share/cook/$code',
      'DELETE /v1/share/cook/$code',
    ]);
    expect(service.link(code).toString(), 'https://coach.example.workers.dev/k/$code');
    expect(service.inviteLink().toString(), 'https://coach.example.workers.dev/k/einladen');
  });
}

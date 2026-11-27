// Krafttraining aus Screenshots (WHOOP Strength Trainer gibt Sätze nicht über die API heraus): KI liest ab, die App
// baut eine Gym-Einheit, man prüft und sichert.
import 'dart:convert';
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/gym/gym_screenshot_controller.dart';
import 'package:aironludi/features/gym/gym_screenshot_import_screen.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Antwort des Workers zu einem WHOOP-Screenshot ohne Uhrzeit.
Map<String, Object?> _response({bool withTime = false}) => {
  'model': 'test',
  'provider': 'test',
  'output': {
    'titel': 'Oberkörper',
    'tag': 19,
    'monat': 11,
    'jahr': null,
    'start': withTime ? '07:16' : null,
    'ende': withTime ? '08:09' : null,
    'uebungen': [
      {
        'name': 'Bankdrücken',
        'id': 'bankdruecken',
        'gruppe': null,
        'saetze': [
          {'wdh': 10, 'kg': 60, 'sekunden': null},
          {'wdh': 8, 'kg': 62.5, 'sekunden': null},
        ],
      },
      {
        'name': 'Butterfly-Maschine',
        'id': null,
        'gruppe': 'Brust',
        'saetze': [
          {'wdh': 12, 'kg': 45, 'sekunden': null},
        ],
      },
    ],
  },
};

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late CoachSettings settings;
  late GymRepository gym;
  final requests = <HttpRequest>[];
  var status = 200;
  var withTime = false;
  final image = Uint8List.fromList([0xFF, 0xD8, 1]);

  setUpAll(() => initializeDateFormatting('de_DE'));

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    await store.setString(SettingsKeys.workerURL, 'https://coach-ai.example.workers.dev');
    settings = CoachSettings(store);
    gym = GymRepository(db);
    requests.clear();
    status = 200;
    withTime = false;
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  AIClient ai() => AIClient(
    secrets: Secrets.memory({SecretKey.aiAppToken: 'tok'}),
    settings: store,
    transport: FakeHttpTransport((request) {
      requests.add(request);
      return status == 200
          ? HttpResponse(200, utf8.encode(jsonEncode(_response(withTime: withTime))))
          : HttpResponse(status, utf8.encode('{"error": "overloaded"}'));
    }),
  );

  /// WHOOP-Aufzeichnung „Gewichtheben“ am 19.11. von 07:16 bis 08:09.
  final whoop = GarminActivity(-7)
    ..typeKey = 'strength_training'
    ..name = 'Krafttraining · WHOOP'
    ..startLocal = '2026-11-19 07:16:00'
    ..durationSeconds = 53 * 60;

  GymScreenshotController controller({List<GarminActivity> activities = const []}) => GymScreenshotController(
    ai: ai(),
    gym: gym,
    settings: settings,
    activities: () async => activities,
    clock: () => DateTime(2026, 11, 27, 9),
  );

  test('ohne Uhrzeit auf dem Bild: Zeit der WHOOP-Aufzeichnung; Sichern legt neue Übungen an', () async {
    final model = controller(activities: [whoop]);
    await model.analyze([image, image]);
    final request = jsonDecode(utf8.decode(requests.single.body!)) as Map<String, Object?>;
    expect(request['task'], 'gym_import');
    expect((request['images']! as List).length, 2);
    expect(((request['input']! as Map)['library']! as List), contains('bankdruecken | Bankdrücken'));
    final session = model.session!;
    expect(session.start, DateTime(2026, 11, 19, 7, 16));
    expect(session.end, DateTime(2026, 11, 19, 8, 9));
    expect(model.guessedDate, isTrue);
    expect(session.exercises.map((exercise) => exercise.name), ['Bankdrücken', 'Butterfly-Maschine']);
    expect(model.newCustom.single.group, MuscleGroup.chest);

    model.updateSet(session.exercises.first.sets.last, reps: 9, weightKg: 62.5);
    expect(await model.save(), 'Oberkörper übernommen: 2 Übungen, 3 Sätze.');
    final stored = (await gym.all()).single.session;
    expect(stored.workoutKey, 'import:2026-11-19:07:16');
    expect(stored.exercises.first.sets.last.reps, 9);
    expect(settings.gym.customExercises.single.name, 'Butterfly-Maschine');

    // Derselbe Import noch einmal ersetzt die Einheit, statt sie zu verdoppeln.
    final again = controller(activities: [whoop]);
    await again.analyze([image]);
    expect(again.sameDay, isEmpty);
    await again.save();
    expect(await gym.all(), hasLength(1));
    expect(settings.gym.customExercises, hasLength(1));
  });

  test('entfernte Übung legt keine eigene Übung an; anderer Tag', () async {
    withTime = true;
    final model = controller();
    await model.analyze([image]);
    expect(model.guessedDate, isFalse);
    model.removeExercise(model.session!.exercises.last);
    await model.moveTo(DateTime(2026, 11, 20, 18));
    expect(model.session!.end, DateTime(2026, 11, 20, 18, 53));
    await model.save();
    expect(settings.gym.customExercises, isEmpty);
    expect((await gym.all()).single.session.day, const CalendarDay(2026, 11, 20));
  });

  test('KI überlastet: Meldung, erneut versuchen mit denselben Bildern', () async {
    final model = controller();
    status = 503;
    await model.analyze([image]);
    expect(model.session, isNull);
    expect(model.errorMessage, contains('überlastet'));
    status = 200;
    await model.retry();
    expect(model.session, isNotNull);
    expect(requests, hasLength(2));
  });

  testWidgets('Bildschirm: Anleitung, Screenshots wählen, prüfen, sichern', (tester) async {
    final storage = await tester.runAsync(
      () => AppStorage.open(executor: NativeDatabase.memory(), secrets: InMemorySecretStore()),
    );
    final container = ProviderContainer(
      overrides: [
        appStorageProvider.overrideWithValue(storage!),
        aiClientProvider.overrideWith((ref) {
          final client = AIClient(
            secrets: Secrets.memory({SecretKey.aiAppToken: 'tok'}),
            settings: ref.watch(settingsStoreProvider),
            transport: FakeHttpTransport((_) => HttpResponse(200, utf8.encode(jsonEncode(_response(withTime: true))))),
          );
          return client;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(settingsStoreProvider).setString(SettingsKeys.workerURL, 'https://w.example.dev'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          locale: const Locale('de'),
          home: GymScreenshotImportScreen(pickImages: () async => [image]),
        ),
      ),
    );
    expect(find.textContaining('„Alle anzeigen“'), findsOneWidget);
    await tester.tap(find.text('Screenshots wählen'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('BANKDRÜCKEN'), findsOneWidget);
    expect(find.text('BUTTERFLY-MASCHINE · NEUE ÜBUNG'), findsOneWidget);
    expect(find.text('60 kg × 10'), findsOneWidget);
    // „Sichern“ oben in der Leiste (unten steht zusätzlich „Einheit sichern“).
    await tester.tap(find.widgetWithText(TextButton, 'Sichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final stored = await tester.runAsync(() => container.read(gymRepositoryProvider).all());
    expect(stored!.single.session.title, 'Oberkörper');
  });
}

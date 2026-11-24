// Wurzel der App: Speicherwarnung, Update-Hinweis, Schnellaktionen am App-Icon, Bildschirm an während einer Einheit.
import 'dart:convert';

import 'package:aironludi/app/app.dart';
import 'package:aironludi/app/day_change.dart';
import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/preferences.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/features/nutrition/product_search_screen.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/services/update/app_update_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  Future<(Widget, ProviderContainer, FakeQuickActionsService, List<bool>)> build({
    bool temporary = false,
    String? update,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final opened = await AppStorage.open(executor: NativeDatabase.memory(), secrets: InMemorySecretStore());
    final storage = temporary
        ? AppStorage(
            database: opened.database,
            settings: opened.settings,
            secrets: opened.secrets,
            openError: 'Migration fehlgeschlagen',
          )
        : opened;
    final quick = FakeQuickActionsService();
    final awake = <bool>[];
    // Android mit Worker: der Worker meldet [update] als neueste Version.
    if (update != null) await storage.settings.setString(SettingsKeys.workerURL, 'https://w.example.dev');
    final updateTransport = FakeHttpTransport(
      (request) => HttpResponse(
        200,
        utf8.encode(
          '{"versionName": "$update", "versionCode": 10057, "url": "https://w.example.dev/android/abc/", '
          '"notes": "Commit abc1234, Build 57."}',
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        appStorageProvider.overrideWithValue(storage),
        midnightTimerProvider.overrideWithValue(false),
        quickActionsProvider.overrideWithValue(quick),
        screenAwakeProvider.overrideWithValue((on) async => awake.add(on)),
        if (update != null)
          appUpdateServiceProvider.overrideWith(
            (ref) => AppUpdateService(
              ai: AIClient(
                secrets: Secrets.memory({SecretKey.aiAppToken: 'g1.abcdefghijk2.0f'}),
                settings: ref.watch(settingsStoreProvider),
                transport: updateTransport,
              ),
              settings: ref.watch(settingsStoreProvider),
              installedBuild: () async => 10050,
              isAndroid: true,
            ),
          ),
      ],
    );
    container.read(coachSettingsProvider).profile = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run, TrainingSport.strength],
    );
    quick.initialize((route) => openRoute(container.read(_refProbe), route));
    return (UncontrolledProviderScope(container: container, child: const AIronLudiApp()), container, quick, awake);
  }

  testWidgets('„In der App verbinden“ (ironludi://connect) übernimmt den KI-Zugang', (tester) async {
    final (app, container, _, _) =
        await tester.runAsync(build) as (Widget, ProviderContainer, FakeQuickActionsService, List<bool>);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    container
        .read(incomingLinkProvider.notifier)
        .open(Uri.parse('ironludi://connect?worker=https%3A%2F%2Fw.example.dev&token=g1.abcdefghijk2.0f'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final ai = container.read(aiClientProvider);
    expect(ai.workerURL, 'https://w.example.dev');
    expect(ai.storedToken, 'g1.abcdefghijk2.0f');
    expect(find.text('KI-Zugang verbunden.'), findsOneWidget);
    expect(container.read(incomingLinkProvider), isNull);
  });

  testWidgets('Android: neuere Version als Hinweis oben, „Später“ blendet ihn aus', (tester) async {
    final (app, container, _, _) = await tester.runAsync(
      () => build(update: '2.0.57'),
    ) as (Widget, ProviderContainer, FakeQuickActionsService, List<bool>);
    await tester.pumpWidget(app);
    // Der Start ruft die Prüfung selbst auf (`_refresh`); echte Zeit für Datenbank und Antwort.
    for (var i = 0; i < 40 && find.textContaining('Neue Version').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Neue Version 2.0.57 verfügbar'), findsOneWidget);
    expect(find.text('Commit abc1234, Build 57.'), findsOneWidget);
    expect(find.text('Jetzt laden'), findsOneWidget);

    await tester.tap(find.text('Später'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.textContaining('Neue Version'), findsNothing);
  });

  testWidgets('Speicher nicht geöffnet: Warnung oben', (tester) async {
    final (app, _, _, _) = await tester.runAsync(
      () => build(temporary: true),
    ) as (Widget, ProviderContainer, FakeQuickActionsService, List<bool>);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.textContaining('Gespeicherte Daten konnten nicht geöffnet werden'), findsOneWidget);
  });

  testWidgets('Schnellaktionen nach Profil, Antippen wählt den Reiter; Bildschirm an während einer Einheit', (
    tester,
  ) async {
    final (app, container, quick, awake) =
        await tester.runAsync(build) as (Widget, ProviderContainer, FakeQuickActionsService, List<bool>);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.textContaining('Gespeicherte Daten'), findsNothing);
    expect(quick.routes, [AppRoute.startWorkout, AppRoute.logMeal, AppRoute.health]);
    expect(awake, [false]);

    quick.onSelect!(AppRoute.logMeal);
    await tester.pumpAndSettle();
    // Der Reiter Ernährung ist gewählt und hat das Erfassen geöffnet (die Aktion wird ausgeführt, nicht nur der Reiter).
    expect(find.byType(ProductSearchScreen), findsOneWidget);
    expect(container.read(pendingRouteProvider), isNull);

    container.read(gymControllerProvider).startEmpty();
    await tester.pump();
    expect(awake, [false, true]);
  });
}

/// Liefert einen `Ref` für `openRoute` im Test.
final _refProbe = Provider<Ref>((ref) => ref);

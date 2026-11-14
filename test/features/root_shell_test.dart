// Wurzel der App: Speicherwarnung, Schnellaktionen am App-Icon, Bildschirm an während einer Einheit.
import 'package:aironludi/app/app.dart';
import 'package:aironludi/app/day_change.dart';
import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/preferences.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/services/providers.dart';
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

  Future<(Widget, ProviderContainer, FakeQuickActionsService, List<bool>)> build({bool temporary = false}) async {
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
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        appStorageProvider.overrideWithValue(storage),
        midnightTimerProvider.overrideWithValue(false),
        quickActionsProvider.overrideWithValue(quick),
        screenAwakeProvider.overrideWithValue((on) async => awake.add(on)),
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
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Ernährung')), findsWidgets);

    container.read(gymControllerProvider).startEmpty();
    await tester.pump();
    expect(awake, [false, true]);
  });
}

/// Liefert einen `Ref` für `openRoute` im Test.
final _refProbe = Provider<Ref>((ref) => ref);

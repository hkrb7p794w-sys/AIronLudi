// Demo-Modus (Roast F-1): Demo-Daten füllen einen Benutzer, `coach.demo` macht das App-Modell zum Demo-Modell.
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/preferences.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/services/demo/demo_seed.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Demo-Daten und Demo-Kennzeichen', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final storage = await AppStorage.open(executor: NativeDatabase.memory(), secrets: InMemorySecretStore());
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences), appStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(() async {
      container.dispose();
      await storage.database.close();
    });
    expect(container.read(appModelProvider).isDemo, isFalse);

    await container.read(settingsStoreProvider).setBool(SettingsKeys.demo, true);
    await seedDemo(container);
    container.invalidate(appModelProvider);
    expect(container.read(appModelProvider).isDemo, isTrue);

    final today = CalendarDay.today();
    final metrics = await container.read(metricsRepositoryProvider).range(from: today.adding(-40), to: today);
    expect(metrics.length, 35);
    expect(await container.read(mealRepositoryProvider).day(today), isNotEmpty);
    expect(container.read(coachSettingsProvider).profile.onboardingDone, isTrue);
  });
}

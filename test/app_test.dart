import 'package:aironludi/app/app.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/preferences.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<Widget> app({required bool onboarded}) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  final storage = await AppStorage.open(executor: NativeDatabase.memory(), secrets: InMemorySecretStore());
  final container = ProviderContainer(
    overrides: [preferencesProvider.overrideWithValue(preferences), appStorageProvider.overrideWithValue(storage)],
  );
  if (onboarded) {
    container.read(coachSettingsProvider).profile = UserProfile(mode: ProfileMode.personal, onboardingDone: true);
  }
  return UncontrolledProviderScope(container: container, child: const AIronLudiApp());
}

void main() {
  testWidgets('vier Reiter wie in der iPhone-App, Wechsel per Tippen', (tester) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();

    Finder tabLabel(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
    for (final label in ['Heute', 'Aktivitäten', 'Training', 'Ernährung']) {
      expect(tabLabel(label), findsOneWidget);
    }
    await tester.tap(tabLabel('Ernährung'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Ernährung')), findsOneWidget);
  });

  testWidgets('erster Start: Einrichtungsassistent, Weiter erst mit Sportart', (tester) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: false)) as Widget);
    await tester.pumpAndSettle();
    expect(find.text('Was trainierst du?'), findsOneWidget);
    expect(find.text('Sicherung einspielen'), findsOneWidget);
    final next = find.widgetWithText(FilledButton, 'Weiter');
    // Wie in Swift sind Laufen und Krafttraining vorausgewählt; ohne Sportart geht es nicht weiter.
    await tester.tap(find.text('Laufen'));
    await tester.tap(find.text('Krafttraining'));
    await tester.pump();
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.tap(find.text('Laufen'));
    await tester.pump();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Was ist dein Ziel?'), findsOneWidget);
  });
}

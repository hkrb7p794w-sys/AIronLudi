import 'package:aironludi/app/app.dart';
import 'package:aironludi/data/settings/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('vier Reiter wie in der iPhone-App, Wechsel per Tippen', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: [preferencesProvider.overrideWithValue(preferences)], child: const AIronLudiApp()),
    );
    await tester.pumpAndSettle();

    Finder tabLabel(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
    for (final label in ['Heute', 'Aktivitäten', 'Training', 'Ernährung']) {
      expect(tabLabel(label), findsOneWidget);
    }
    await tester.tap(tabLabel('Ernährung'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Ernährung')), findsOneWidget);
  });
}

// WHOOP in den Einstellungen: ohne Worker ein Hinweis, Rücksprung mit Fehler als Meldung, verbunden mit Stand.
import 'dart:async';
import 'dart:convert';

import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/settings/whoop_section.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/services/whoop/whoop_service.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  /// [prepare] läuft vor dem Start der App (Datenbank und sicherer Speicher sind dann noch frei).
  Future<ProviderContainer> start(WidgetTester tester, {Future<void> Function(ProviderContainer)? prepare}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Kein echter Abruf bei WHOOP: leere Listen.
    final whoop = whoopServiceProvider.overrideWith(
      (ref) => WhoopService(
        ai: ref.watch(aiClientProvider),
        secrets: ref.watch(secretsProvider),
        settings: ref.watch(settingsStoreProvider),
        activities: ActivityRepository(ref.watch(databaseProvider)),
        transport: FakeHttpTransport((_) => HttpResponse(200, utf8.encode('{"records": []}'))),
      ),
    );
    final widget = await tester.runAsync(() async {
      final widget = await app(onboarded: true, overrides: [whoop]) as UncontrolledProviderScope;
      await prepare?.call(widget.container);
      return widget;
    });
    await tester.pumpWidget(widget!);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return widget.container;
  }

  testWidgets('nicht verbunden: Verbinden ohne Worker meldet den Hinweis', (tester) async {
    await start(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(LiquidTabBar))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SingleChildScrollView(child: WhoopSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mit WHOOP verbinden'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('KI-Worker'), findsOneWidget);
  });

  testWidgets('verbunden: Name, Körperwerte, Abrufen und Trennen', (tester) async {
    await start(
      tester,
      prepare: (container) async {
        await container
            .read(secretsProvider)
            .set(
              SecretKey.whoopToken,
              jsonEncode(
                WhoopToken(
                  accessToken: 'a',
                  refreshToken: 'r',
                  expiresAt: DateTime.now().add(const Duration(hours: 1)),
                ).toJson(),
              ),
            );
        final settings = container.read(settingsStoreProvider);
        await settings.setJson('whoop.profile', {'user_id': 1, 'first_name': 'Sam'});
        await settings.setJson('whoop.body', {'height_meter': 1.8, 'weight_kilogram': 80.5, 'max_heart_rate': 190});
      },
    );
    unawaited(
      Navigator.of(tester.element(find.byType(LiquidTabBar))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SingleChildScrollView(child: WhoopSection())),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Verbunden als Sam'), findsOneWidget);
    expect(find.text('180 cm · 80,5 kg · HFmax 190'), findsOneWidget);
    expect(find.text('Trennen'), findsOneWidget);
  });

  testWidgets('Rücksprung mit abgelehnter Freigabe: Meldung', (tester) async {
    final container = await start(tester);
    container.read(incomingLinkProvider.notifier).open(Uri.parse('coach://whoop?error=access_denied'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(WhoopAuthErrors.message('access_denied')), findsOneWidget);
    expect(container.read(incomingLinkProvider), isNull);
  });
}

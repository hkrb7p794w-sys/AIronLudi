// Freunde: ohne Konto Hinweis, Beitrag mit Inhalt und Reaktionen, Teilen ohne Konto, automatisches Teilen.
import 'dart:async';

import 'package:aironludi/features/social/social_views.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/services/social/social_auto_share.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> _open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(LiquidTabBar)));
  unawaited(
    Navigator.of(tester.element(find.byType(LiquidTabBar))).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  return container;
}

SocialPost _post({bool mine = false, String kind = 'workout'}) => SocialPost.fromJson({
  'id': 'p1',
  'kind': kind,
  'createdAt': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
  'author': {'username': 'anna', 'displayName': 'Anna'},
  'mine': mine,
  'payload': {
    'sport': 'strength',
    'title': 'Push-Tag',
    'durationMin': 55,
    'sets': 18,
    'exercises': ['Bankdrücken', 'Schulterdrücken'],
    'records': ['Bankdrücken 80 kg × 5'],
    'note': 'Endlich wieder stark!',
  },
  'reactions': 3,
  'myReaction': '🔥',
  'topReactions': '🔥👏',
  'comments': 2,
})!;

void main() {
  testWidgets('Freunde ohne Konto: Hinweis mit Anmelden', (tester) async {
    await _open(tester, const FriendsScreen());
    expect(find.text('Freunde brauchen ein Konto'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Konto erstellen'), findsOneWidget);
  });

  testWidgets('Beitrag: Kopf, Inhalt, Rekord, Notiz, Reaktionen', (tester) async {
    await _open(
      tester,
      Scaffold(
        body: ListView(children: [PostCard(post: _post())]),
      ),
    );
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Endlich wieder stark!'), findsOneWidget);
    expect(find.text('Bankdrücken 80 kg × 5'), findsOneWidget);
    expect(find.text('Bankdrücken · Schulterdrücken'), findsOneWidget);
    expect(find.text('🔥👏 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Stark, gewählt'), findsOneWidget);
    expect(find.byTooltip('Optionen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Teilen ohne Konto: Hinweis', (tester) async {
    await _open(
      tester,
      ShareWithFriendsScreen(
        content: ShareWorkout(WorkoutShare(sport: 'run', title: 'Lauf')),
      ),
    );
    expect(find.text('Zum Teilen mit Freunden brauchst du ein Konto.'), findsOneWidget);
  });

  testWidgets('automatisches Teilen: Schalter merkt den Zeitpunkt, ohne Konto kein Teilen', (tester) async {
    final container = await _open(tester, const SizedBox());
    final autoShare = container.read(socialAutoShareProvider);
    expect(autoShare.isEnabled, isFalse);
    await tester.runAsync(() => autoShare.setEnabled(true));
    expect(autoShare.isEnabled, isTrue);
    final store = container.read(socialServiceProvider);
    expect(store.isAvailable, isFalse);
    await tester.runAsync(autoShare.run);
    expect(store.feed, isEmpty);
    expect(SocialAutoShare.sinceKey, 'social.autoShareSince');
  });
}

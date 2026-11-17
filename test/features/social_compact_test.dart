// Beiträge in Listen dezent: keine Emoji-Leiste, nur vorhandene Reaktionen und Kommentare; Antippen öffnet alles.
import 'package:aironludi/features/social/social_views.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test.dart' show app;

SocialPost post({int reactions = 0, int comments = 0}) => SocialPost(
  id: 'p1',
  kind: SocialPostKind.workout,
  createdAt: '2026-11-17T08:00:00Z',
  author: const SocialPerson(username: 'ben', displayName: 'Ben'),
  mine: false,
  payload: SocialPayload()..title = 'Lauf',
  reactions: reactions,
  topReactions: reactions > 0 ? '🔥' : '',
  comments: comments,
);

void main() {
  testWidgets('kompakt ohne Reaktionen: keine Emojis; mit Reaktionen: Zusammenfassung; Detail mit allen', (
    tester,
  ) async {
    await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    Future<void> show(Widget child) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ListView(children: [child])),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(PostCard(post: post(), compact: true));
    expect(find.text(SocialReaction.values.first.rawValue), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

    await show(PostCard(post: post(reactions: 3, comments: 2), compact: true));
    expect(find.text('🔥 3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(SocialReaction.values.first.rawValue), findsNothing);
    await tester.tap(find.text('🔥 3'));
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsOneWidget);
    for (final reaction in SocialReaction.values) {
      expect(find.text(reaction.rawValue), findsOneWidget);
    }
  });
}

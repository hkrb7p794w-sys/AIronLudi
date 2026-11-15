// Motivation: Daisy in allen Stimmungen, Begleiter auf Heute, Einstellungen, Liga-Einladung, Foto verkleinern.
import 'dart:async';

import 'package:aironludi/app/deep_links.dart';
import 'package:aironludi/features/motivation/daisy_avatar.dart';
import 'package:aironludi/features/motivation/motivation_views.dart';
import 'package:aironludi/services/motivation/companion_photo.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../app_test.dart' show app;

Future<ProviderContainer> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 100));
  return ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
}

void main() {
  testWidgets('Daisy zeichnet jede Stimmung, auch ohne Bewegung', (tester) async {
    for (final mood in CompanionMood.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: DaisyAvatar(mood: mood)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: mood.name);
    }
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Center(child: DaisyAvatar(mood: CompanionMood.resting)),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Daisy'), findsOneWidget);
  });

  testWidgets('Begleiter auf Heute mit Nachricht', (tester) async {
    final container = await _start(tester);
    final settings = container.read(coachSettingsProvider);
    settings.companion = settings.companion
      ..enabled = true
      ..kind = CompanionKind.daisy
      ..name = 'Daisy';
    await tester.pump(const Duration(milliseconds: 100));
    // Sonntags steht der Wochenrückblick davor (`WeeklyReview.isDue`); die Liste baut nur, was sichtbar ist.
    await tester.scrollUntilVisible(find.byType(CompanionSection), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byType(CompanionSection), findsOneWidget);
    expect(find.byType(DaisyAvatar), findsOneWidget);
    settings.companion = settings.companion..enabled = false;
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Einstellungen: Begleiter einschalten, Art wählen; Liga-Code prüfen', (tester) async {
    final container = await _start(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(NavigationBar)))
          .push(MaterialPageRoute<void>(builder: (_) => const MotivationSettingsScreen())),
    );
    await tester.pumpAndSettle();
    final settings = container.read(coachSettingsProvider);
    await tester.tap(find.text('Begleiter anzeigen'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(settings.companion.enabled, isTrue);
    expect(find.text('Name, z. B. Daisy'), findsOneWidget);
    // Ohne KI-Worker keine Rangliste.
    expect(find.textContaining('Für die Rangliste muss der KI-Worker'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Code eingeben'), 'ungültig');
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Beitreten')).onPressed, isNull);
    settings.companion = settings.companion..enabled = false;
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Liga-Einladungslink öffnet „Rangliste beitreten“', (tester) async {
    final container = await _start(tester);
    container
        .read(incomingLinkProvider.notifier)
        .open(
          Uri.parse(
            'coach://join?worker=https%3A%2F%2Fcoach.example.workers.dev&league=${LeagueCode.generate()}&token=abc',
          ),
        );
    await tester.pumpAndSettle();
    expect(find.byType(JoinLeagueScreen), findsOneWidget);
    expect(find.text('coach.example.workers.dev'), findsOneWidget);
  });

  test('Begleiter-Foto: höchstens 600 Pixel, JPEG', () {
    final big = img.encodePng(img.Image(width: 1200, height: 800));
    final resized = img.decodeJpg(CompanionPhoto.resized(big)!)!;
    expect(resized.width, 600);
    expect(resized.height, 400);
  });
}

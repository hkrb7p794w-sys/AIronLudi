// Externe KI: Export erstellen, Antwort importieren (Hinweise), Prompt-Bibliothek mit eigenem Prompt.
import 'dart:async';

import 'package:aironludi/features/ai/coach_exchange.dart';
import 'package:aironludi/features/ai/prompt_library_screen.dart';
import 'package:aironludi/services/providers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

Future<ProviderContainer> _open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await tester.runAsync(() => app(onboarded: true)) as Widget);
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
  unawaited(
    Navigator.of(tester.element(find.byType(CupertinoTabBar))).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Export: Zeitraum, Daten, erstellen', (tester) async {
    await _open(tester, const CoachExportScreen());
    expect(find.text('Gym'), findsOneWidget);
    expect(find.textContaining('0 Einträge'), findsWidgets);
    await _tap(tester, find.text('Export erstellen'));
    expect(find.text('Datei teilen'), findsOneWidget);
    expect(find.text('Als Text kopieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Import: Antwort prüfen und Hinweise übernehmen', (tester) async {
    final container = await _open(tester, const CoachImportScreen());
    await tester.enterText(
      find.byType(TextField),
      'Hier mein Vorschlag:\n```ironludi\n{"hinweise": ["Schlaf vor harten Tagen priorisieren."]}\n```',
    );
    await tester.pump();
    await _tap(tester, find.text('Prüfen'));
    expect(find.text('HINWEISE DER KI'), findsOneWidget);
    await _tap(tester, find.text('Auswahl übernehmen'));
    expect(find.text('Übernommen'), findsOneWidget);
    expect(container.read(coachSettingsProvider).importedNotes?.texts, ['Schlaf vor harten Tagen priorisieren.']);

    await tester.enterText(find.byType(TextField), 'ohne Block');
    await tester.pump();
    await _tap(tester, find.text('Prüfen'));
    expect(find.textContaining('Kein Block'), findsOneWidget);
  });

  testWidgets('Import: Empfehlungen einer externen KI wählen, überschreiben und verwerfen', (tester) async {
    final container = await _open(tester, const CoachImportScreen());
    final settings = container.read(coachSettingsProvider);
    final now = DateTime.now();
    Insight make(InsightTopic topic, String subject, String title, InsightOrigin origin) => Insight(
      topic: topic,
      subject: subject,
      title: title,
      text: 'alt',
      direction: InsightDirection.more,
      origin: origin,
      created: now,
      validUntil: now.add(const Duration(days: 7)),
      basis: const ['Fakt'],
      model: origin == InsightOrigin.ai ? 'llama' : null,
    );
    settings.insights = [
      make(InsightTopic.recovery, 'schlaf', 'Mehr schlafen', InsightOrigin.ai),
      make(InsightTopic.nutrition, 'protein', 'Protein erhöhen', InsightOrigin.rules),
      make(InsightTopic.training, 'bankdruecken', 'Bankdrücken steigern', InsightOrigin.ai),
    ];
    await tester.enterText(
      find.byType(TextField),
      '```ironludi\n{"modell": "Claude", "empfehlungen": ['
      '{"id": "erholung.schlaf", "titel": "8 h vor harten Tagen", "text": "neu", "richtung": "mehr"},'
      '{"id": "ernaehrung.protein", "titel": "Protein 1,8 g/kg", "text": "neu", "richtung": "mehr"}],'
      '"verwerfen": ["training.bankdruecken"]}\n```',
    );
    await tester.pump();
    await _tap(tester, find.text('Prüfen'));
    expect(find.text('EMPFEHLUNGEN VON CLAUDE'), findsOneWidget);
    expect(find.text('Überschreibt: „Mehr schlafen“ (KI (llama))'), findsOneWidget);
    expect(find.text('Überschreibt: „Protein erhöhen“ (Regeln der App)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ALS FALSCH ODER ÜBERHOLT MARKIERT'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bankdrücken steigern'), findsOneWidget);
    await _tap(tester, find.text('Auswahl übernehmen'));
    expect(find.text('Übernommen'), findsOneWidget);
    final byID = {for (final insight in settings.insights) insight.id: insight};
    expect(byID['erholung.schlaf']?.title, '8 h vor harten Tagen');
    expect(byID['erholung.schlaf']?.model, 'Claude');
    expect(byID['ernaehrung.protein']?.title, 'Protein erhöhen'); // Regel nicht vorausgewählt
    expect(byID['training.bankdruecken']?.status, InsightStatus.dismissed);
  });

  testWidgets('Prompt-Bibliothek: Vorlage, eigener Prompt', (tester) async {
    final container = await _open(tester, const PromptLibraryScreen());
    final first = PromptLibrary.builtIn.first;
    await tester.tap(find.text(first.title));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(PromptDetailScreen), findsOneWidget);
    expect(find.text('ANGEHÄNGTE DATEN'), findsOneWidget);
    await _tap(tester, find.text('Als eigenen Prompt speichern'));
    expect(find.byType(PromptEditor), findsOneWidget);
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    final custom = container.read(coachSettingsProvider).customPrompts;
    expect(custom.single.title, '${first.title} (eigen)');
    expect(custom.single.isCustom, isTrue);
    expect(tester.takeException(), isNull);
  });
}

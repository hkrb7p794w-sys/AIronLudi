// Einstellungen nach Disziplin (Gym, Laufen, Rad, Schwimmen), Pausen je Übung, GymBook-Import und Diagnose.
import 'dart:async';
import 'dart:convert';

import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/gym/gym_providers.dart';
import 'package:aironludi/features/settings/diagnostics_screens.dart';
import 'package:aironludi/features/settings/discipline_settings.dart';
import 'package:aironludi/services/gym/rest_alarm.dart';
import 'package:aironludi/services/providers.dart';
import 'package:aironludi/ui/sport_style.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_test.dart' show app;

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  final sound = FakeRestAlarm();

  Future<ProviderContainer> start(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      await tester.runAsync(
        () => app(
          onboarded: true,
          overrides: [
            restSoundPlayerProvider.overrideWithValue(sound),
            healthProbeProvider.overrideWithValue(() async => HealthAccessDiagnosis.missingEntitlement),
            appVersionProvider.overrideWith((ref) async => '1.2 (34)'),
          ],
        ),
      ) as Widget,
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CupertinoTabBar)));
    unawaited(
      Navigator.of(tester.element(find.byType(CupertinoTabBar))).push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> choose(WidgetTester tester, String current, String option) async {
    await tester.tap(find.textContaining(current).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Disziplinen: Gym und Ausdauer je nach Profil', (tester) async {
    final container = await start(tester, const Scaffold(body: DisciplineSettingsSection()));
    final settings = container.read(coachSettingsProvider);
    settings.profile = settings.profile.copy()
      ..mode = ProfileMode.personal
      ..sports = [TrainingSport.run];
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsNothing);
    expect(find.text(TrainingSport.run.shortLabel), findsOneWidget);
    expect(find.text(TrainingSport.swim.shortLabel), findsNothing);
  });

  testWidgets('Gym: Pausen, Ton mit Probehören, RIR, Garmin', (tester) async {
    final container = await start(tester, const GymSettingsScreen());
    final settings = container.read(coachSettingsProvider);
    await choose(tester, RestText.format(settings.gym.restCompound), RestText.format(180));
    expect(settings.gym.restCompound, 180);
    await choose(tester, settings.gym.restSound.label, RestSound.bell.label);
    expect(settings.gym.restSound, RestSound.bell);
    expect(sound.played.last, RestSound.bell);
    final rir = settings.gym.tracksRIR;
    await tester.scrollUntilVisible(
      find.text('Wiederholungen in Reserve abfragen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Wiederholungen in Reserve abfragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wiederholungen in Reserve abfragen'));
    await tester.pumpAndSettle();
    expect(settings.gym.tracksRIR, !rir);
    await tester.scrollUntilVisible(
      find.text('Mit Garmin Connect abgleichen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Mit Garmin Connect abgleichen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mit Garmin Connect abgleichen'));
    await tester.pumpAndSettle();
    expect(settings.gym.uploadsToGarmin, isFalse);
    expect(find.text('Ohne Uhr als eigene Aktivität hochladen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Je Übung: Suche, eigene Pause, Notiz, Stange', (tester) async {
    final container = await start(tester, const ExerciseSettingsScreen());
    final settings = container.read(coachSettingsProvider);
    final squat = ExerciseLibrary.all.firstWhere((exercise) => exercise.equipment.firstOrNull == Equipment.barbell);
    await tester.enterText(find.byType(TextField), squat.name);
    await tester.pumpAndSettle();
    await tester.tap(find.text(squat.name).last);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseSettingsDetailScreen), findsOneWidget);
    await choose(tester, 'Standard', RestText.format(150));
    expect(settings.gym.restOverrides[squat.id], 150);
    await tester.enterText(find.widgetWithText(TextField, 'z. B. Sitz 4, Griff weit, Bank auf Stufe 3'), 'Rack 7');
    await tester.pumpAndSettle();
    expect(settings.gym.notes[squat.id], 'Rack 7');
    await choose(tester, 'Standard (${GermanFormat.number(settings.gym.barKg)} kg)', '15 kg');
    expect(settings.gym.bars[squat.id], 15);

    // Zurück in der Liste: unter „Meine Übungen“ mit Pause und Notiz.
    Navigator.of(tester.element(find.byType(ExerciseSettingsDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('MEINE ÜBUNGEN'), findsOneWidget);
    expect(find.textContaining('Pause ${RestText.format(150)} · Rack 7'), findsOneWidget);
  });

  testWidgets('Laufen im Saisonplan: Paces und eigene Pulswerte', (tester) async {
    final container = await start(tester, const EnduranceSettingsScreen(sport: TrainingSport.run));
    final settings = container.read(coachSettingsProvider);
    settings.profile = settings.profile.copy()..mode = ProfileMode.season;
    await tester.pumpAndSettle();
    final threshold = settings.season.thresholdPaceSecondsPerKm;
    await tester.tap(find.byTooltip('Mehr').first);
    await tester.pumpAndSettle();
    expect(settings.season.thresholdPaceSecondsPerKm, threshold + 1);

    expect(settings.heartRate.maxHeartRate, isNull);
    await tester.tap(find.text('eigenen Wert setzen').first);
    await tester.pumpAndSettle();
    expect(settings.heartRate.maxHeartRate, 195);
    expect(find.text('HFmax 195 bpm'), findsOneWidget);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(settings.heartRate.maxHeartRate, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schwimmen im persönlichen Modus: nur der Hinweis', (tester) async {
    final container = await start(tester, const EnduranceSettingsScreen(sport: TrainingSport.swim));
    final settings = container.read(coachSettingsProvider);
    settings.profile = settings.profile.copy()..mode = ProfileMode.personal;
    await tester.pumpAndSettle();
    expect(find.text('TESTWERTE'), findsNothing);
    expect(find.textContaining('im Wasser ungenau'), findsOneWidget);
  });

  testWidgets('GymBook-Import: Fehler einer unlesbaren Datei erscheint', (tester) async {
    await start(tester, Scaffold(body: GymBookImportSection(pickFile: () async => '/nicht/vorhanden.database')));
    await tester.tap(find.text('Verlauf aus Backup importieren'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('vorhanden.database'), findsOneWidget);
  });

  testWidgets('Diagnose: Rohantworten mit Feldnamen, Health-Prüfung, Version', (tester) async {
    final container = await start(tester, const SizedBox());
    await tester.runAsync(
      () => container
          .read(rawResponseRepositoryProvider)
          .store(
            'sleep',
            utf8.encode(
              jsonEncode({
                'dailySleepDTO': {'sleepTimeSeconds': 1},
              }),
            ),
            at: DateTime(2026, 11, 14, 7),
          ),
    );
    unawaited(
      Navigator.of(tester.element(find.byType(CupertinoTabBar, skipOffstage: false)))
          .push(MaterialPageRoute<void>(builder: (_) => const GarminDiagnosticsScreen())),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('sleep'), findsOneWidget);
    await tester.tap(find.text('sleep'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dailySleepDTO'), findsWidgets);
    expect(find.textContaining('sleepTimeSeconds'), findsOneWidget);
    expect(RawResponseScreen.keyPaths(utf8.encode('kein json')), isEmpty);

    unawaited(
      Navigator.of(tester.element(find.byType(RawResponseScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const HealthDiagnosticsScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.2 (34)'), findsOneWidget);
    expect(find.text(HealthAccessDiagnosis.notDetermined.title), findsOneWidget);
    await tester.tap(find.text('HealthKit prüfen'));
    await tester.pumpAndSettle();
    expect(find.text(HealthAccessDiagnosis.missingEntitlement.title), findsOneWidget);
  });
}

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/bootstrap.dart';
import '../../data/storage.dart';
import '../providers.dart';
import '../widgets/widget_providers.dart';

/// Hintergrundabruf (Port von `AppModel.backgroundRefresh`/`scheduleBackgroundRefresh`): Das System entscheidet, wann
/// (und ob) er läuft; frühestens alle 2 Stunden. Holt neue Werte und versorgt die Widgets. Ohne Planung holt die App
/// die Daten beim nächsten Öffnen.
abstract final class BackgroundRefresh {
  /// Gleiche Kennung wie in der Swift-App (`BGTaskSchedulerPermittedIdentifiers` in `Info.plist`).
  static const task = 'io.github.hkrb7p794w.coach.refresh';
  static const interval = Duration(hours: 2);

  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(backgroundDispatcher);
    } on Object {
      // Ohne Plattformteil (Tests, Desktop) kein Hintergrundabruf.
    }
  }

  /// Beim Verlassen der App: nächsten Abruf planen (ein vorhandener Plan bleibt bestehen).
  static Future<void> schedule() async {
    try {
      await Workmanager().registerPeriodicTask(
        task,
        task,
        frequency: interval,
        initialDelay: interval,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } on Object {
      // Nicht verfügbar; dann eben beim nächsten Öffnen.
    }
  }

  /// Ein Durchlauf im Hintergrund: abrufen, wenn fällig, dann die Widgets versorgen.
  static Future<bool> run() async {
    final container = await createAppContainer();
    try {
      final model = container.read(appModelProvider);
      if (model.isDemo || !container.read(coachSettingsProvider).profile.onboardingDone) return true;
      await model.start();
      await model.syncIfDue();
      // Neue Nacht- und Tageswerte auch auf dem Homescreen.
      await container.read(widgetPublisherProvider).publish();
      return true;
    } finally {
      final database = container.read(databaseProvider);
      container.dispose();
      await database.close();
    }
  }
}

/// Einstieg des Hintergrundabrufs in einem eigenen Isolate.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await initializeDateFormatting('de_DE');
      return await BackgroundRefresh.run();
    } on Object {
      // Fehler einzelner Abrufe stehen im Sync-Bericht; der nächste Versuch kommt mit dem nächsten Termin.
      return true;
    }
  });
}

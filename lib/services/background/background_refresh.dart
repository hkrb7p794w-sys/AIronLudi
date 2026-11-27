import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/bootstrap.dart';
import '../../data/storage.dart';
import '../../platform/notifications.dart';
import '../providers.dart';
import '../widgets/widget_providers.dart';

/// Hintergrundabruf (Port von `AppModel.backgroundRefresh`/`scheduleBackgroundRefresh`): Das System entscheidet, wann
/// (und ob) er läuft; frühestens alle 2 Stunden. Holt neue Werte und versorgt die Widgets. Ohne Planung holt die App
/// die Daten beim nächsten Öffnen.
abstract final class BackgroundRefresh {
  /// Gleiche Kennung wie in der Swift-App (`BGTaskSchedulerPermittedIdentifiers` in `Info.plist`).
  static const task = 'io.github.hkrb7p794w.coach.refresh';
  static const interval = Duration(hours: 2);

  /// Wartende Fotos auswerten und eintragen (iOS: `BGProcessingTask`, Kennung in `Info.plist`; Android: einmalige
  /// Arbeit mit Netz, bei Fehlschlag mit wachsendem Abstand erneut).
  static const mealsTask = 'io.github.hkrb7p794w.coach.meals';
  static const mealsDelay = Duration(minutes: 5);

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

  /// Automatisch einzutragende Fotos warten: Auswertung im Hintergrund planen – „zu einem besseren Zeitpunkt“, sobald
  /// Netz da ist. Der regelmäßige Abruf nimmt sie ebenfalls mit.
  static Future<void> scheduleMeals() async {
    try {
      if (Platform.isIOS) {
        await Workmanager().registerProcessingTask(
          mealsTask,
          mealsTask,
          initialDelay: mealsDelay,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      } else {
        await Workmanager().registerOneOffTask(
          mealsTask,
          mealsTask,
          initialDelay: mealsDelay,
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingWorkPolicy.replace,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: mealsDelay,
        );
      }
    } on Object {
      // Nicht verfügbar; dann beim nächsten Abruf oder Öffnen der App.
    }
  }

  /// Wartende Fotos auswerten und eintragen; `false`, solange noch welche offen sind (Android versucht es dann später
  /// erneut, iOS plant den nächsten Lauf).
  static Future<bool> runMeals() async {
    final center = await _notificationCenter();
    final container = await createAppContainer(notificationCenter: center);
    try {
      if (container.read(appModelProvider).isDemo) return true;
      final service = container.read(pendingMealServiceProvider);
      await service.processDue(notify: true);
      if (!service.hasAutoLog) return true;
      if (Platform.isIOS) await scheduleMeals();
      return !Platform.isAndroid;
    } finally {
      final database = container.read(databaseProvider);
      container.dispose();
      await database.close();
    }
  }

  static Future<NotificationCenterBridge?> _notificationCenter() =>
      DeviceNotificationCenter.create(onAnswer: (_) {})
          .then<NotificationCenterBridge?>((center) => center, onError: (Object _) => null);

  /// Ein Durchlauf im Hintergrund: wartende Fotos eintragen, abrufen, wenn fällig, dann die Widgets versorgen.
  static Future<bool> run() async {
    final container = await createAppContainer(notificationCenter: await _notificationCenter());
    try {
      final model = container.read(appModelProvider);
      if (model.isDemo || !container.read(coachSettingsProvider).profile.onboardingDone) return true;
      // Zuerst: die Hintergrundzeit ist knapp, und ein nachgetragenes Foto ist wichtiger als neue Werte.
      try {
        await container.read(pendingMealServiceProvider).processDue(notify: true);
      } on Object {
        // Offene Fotos bleiben für den nächsten Lauf.
      }
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
      if (task == BackgroundRefresh.mealsTask) return await BackgroundRefresh.runMeals();
      return await BackgroundRefresh.run();
    } on Object {
      // Fehler einzelner Abrufe stehen im Sync-Bericht; der nächste Versuch kommt mit dem nächsten Termin.
      return true;
    }
  });
}

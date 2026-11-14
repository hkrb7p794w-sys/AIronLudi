import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'platform/notifications.dart';
import 'services/background/background_refresh.dart';
import 'services/gym/rest_alarm.dart';
import 'services/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Datums- und Zahlenformate auf Deutsch (wie die iPhone-App).
  await initializeDateFormatting('de_DE');
  // Mitteilungen: Antworten (Antippen, Aktionen) gehen an die Erinnerungen; was vor dem Start eintrifft (App über
  // eine Mitteilung geöffnet), wird nachgereicht.
  ProviderContainer? container;
  final early = <NotificationAnswer>[];
  void answer(NotificationAnswer value) {
    final current = container;
    current == null ? early.add(value) : current.read(reminderServiceProvider).handle(value);
  }

  final center = await DeviceNotificationCenter.create(onAnswer: answer)
      .then<NotificationCenterBridge?>((center) => center, onError: (Object _) => null);
  unawaited(AssetRestSoundPlayer.installNotificationSounds());
  container = await createAppContainer(notificationCenter: center);
  // Hintergrundabruf (BGAppRefreshTask bzw. WorkManager): neue Nacht- und Tageswerte, auch für die Widgets.
  await BackgroundRefresh.initialize();
  early.forEach(answer);
  runApp(UncontrolledProviderScope(container: container, child: const AIronLudiApp()));
}

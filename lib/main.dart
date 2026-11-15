import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/bootstrap.dart';
import 'app/user_scope.dart';
import 'app/user_session.dart';
import 'data/users/user_storage.dart';
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
  UserSession? session;
  final early = <NotificationAnswer>[];
  void answer(NotificationAnswer value) {
    // Immer an den Container des aktiven Benutzers (nach einem Wechsel ist es der neue).
    final current = session;
    current == null || current.isSwitching
        ? early.add(value)
        : current.container.read(reminderServiceProvider).handle(value);
  }

  final center = await DeviceNotificationCenter.create(onAnswer: answer)
      .then<NotificationCenterBridge?>((center) => center, onError: (Object _) => null);
  unawaited(AssetRestSoundPlayer.installNotificationSounds());
  // Benutzer des Geräts: Verzeichnis laden, Container des aktiven Benutzers öffnen.
  final folders = await deviceFolders();
  final store = UserDirectoryStore(folders.support);
  session = UserSession(
    directory: await store.load(),
    store: store,
    folders: folders,
    notificationCenter: center,
    open: (user, session) => createAppContainer(notificationCenter: center, user: user, session: session),
  );
  await session.start();
  // Hintergrundabruf (BGAppRefreshTask bzw. WorkManager): neue Nacht- und Tageswerte, auch für die Widgets.
  await BackgroundRefresh.initialize();
  early.forEach(answer);
  runApp(UserScope(session: session));
}

import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/settings/preferences.dart';
import 'data/storage.dart';
import 'platform/notifications.dart';
import 'services/gym/rest_alarm.dart';
import 'services/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Datums- und Zahlenformate auf Deutsch (wie die iPhone-App).
  await initializeDateFormatting('de_DE');
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  // Lebensmitteltabelle im Hintergrund laden; bis dahin bleiben KI-Schätzungen stehen (wie ohne Treffer).
  unawaited(rootBundle.loadString('packages/coach_core/assets/bls.tsv').then(BLS.load));
  final storage = await AppStorage.open();
  final season = await rootBundle
      .loadString('packages/coach_core/assets/season-plan.json')
      .then<SeasonSchedule?>(SeasonSchedule.load, onError: (Object _) => null);
  final support = await getApplicationSupportDirectory().then<String?>((dir) => dir.path, onError: (Object _) => null);
  final cache = await getApplicationCacheDirectory().then<String?>((dir) => dir.path, onError: (Object _) => null);
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
  container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      appStorageProvider.overrideWithValue(storage),
      activityFoldersProvider.overrideWithValue((support: support, cache: cache)),
      seasonScheduleProvider.overrideWithValue(season),
      notificationCenterProvider.overrideWithValue(center),
    ],
  );
  early.forEach(answer);
  runApp(UncontrolledProviderScope(container: container, child: const AIronLudiApp()));
}

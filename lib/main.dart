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
import 'services/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Datums- und Zahlenformate auf Deutsch (wie die iPhone-App).
  await initializeDateFormatting('de_DE');
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  // Lebensmitteltabelle im Hintergrund laden; bis dahin bleiben KI-Schätzungen stehen (wie ohne Treffer).
  unawaited(rootBundle.loadString('packages/coach_core/assets/bls.tsv').then(BLS.load));
  final storage = await AppStorage.open();
  final support = await getApplicationSupportDirectory().then<String?>((dir) => dir.path, onError: (Object _) => null);
  final cache = await getApplicationCacheDirectory().then<String?>((dir) => dir.path, onError: (Object _) => null);
  runApp(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(preferences),
        appStorageProvider.overrideWithValue(storage),
        activityFoldersProvider.overrideWithValue((support: support, cache: cache)),
      ],
      child: const AIronLudiApp(),
    ),
  );
}

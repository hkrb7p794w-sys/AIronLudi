import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/settings/preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Datums- und Zahlenformate auf Deutsch (wie die iPhone-App).
  await initializeDateFormatting('de_DE');
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  runApp(ProviderScope(overrides: [preferencesProvider.overrideWithValue(preferences)], child: const AIronLudiApp()));
}

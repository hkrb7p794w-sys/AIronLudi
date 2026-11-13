import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings/appearance.dart';
import 'deep_links.dart';
import 'router.dart';
import 'theme.dart';

class AIronLudiApp extends ConsumerWidget {
  const AIronLudiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Links von außen (Widgets, Schnellaktionen, Einladungen) mitlaufen lassen.
    ref.watch(deepLinkListenerProvider);
    return MaterialApp.router(
      title: 'AIronLudi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(appearanceProvider).themeMode,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
